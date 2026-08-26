#version 330
#extension GL_ARB_separate_shader_objects : require

uniform sampler2D StateSampler;

layout(location = 0) in vec2 texCoord;

layout(std140) uniform SamplerInfo {
    vec2 OutSize;
    vec2 StateSize;
};

layout(location = 0) out vec4 fragColor;

const uint TEXTURE_WIDTH = 128u;
const uint TEXTURE_WORDS = 16384u;
const uint REGISTER_BASE = 16348u;
const uint STATUS_INDEX = 16380u;
const uint CYCLE_INDEX = 16381u;
const uint PC_INDEX = 16382u;
const uint MAGIC_INDEX = 16383u;
const uint MAGIC_VALUE = 0x52563332u;
const uint RAM_WORDS = REGISTER_BASE;
const uint RAM_BYTES = RAM_WORDS * 4u;

const uint STATUS_RUNNING = 0u;
const uint STATUS_EBREAK = 1u;
const uint STATUS_ECALL = 2u;
const uint STATUS_ILLEGAL_INSTRUCTION = 3u;
const uint STATUS_FETCH_FAULT = 4u;
const uint STATUS_LOAD_FAULT = 5u;
const uint STATUS_STORE_FAULT = 6u;
const uint STATUS_MISALIGNED_ACCESS = 7u;

ivec2 wordCoordinate(uint index) {
    return ivec2(int(index % TEXTURE_WIDTH), int(index / TEXTURE_WIDTH));
}

uint decodeWord(vec4 encoded) {
    uvec4 bytes = uvec4(floor(encoded * 255.0 + 0.5));
    return bytes.r | (bytes.g << 8u) | (bytes.b << 16u) | (bytes.a << 24u);
}

vec4 encodeWord(uint word) {
    uvec4 bytes = uvec4(
        word & 0xffu,
        (word >> 8u) & 0xffu,
        (word >> 16u) & 0xffu,
        (word >> 24u) & 0xffu
    );
    return vec4(bytes) / 255.0;
}

uint readStateWord(uint index) {
    if (index >= TEXTURE_WORDS) {
        return 0u;
    }
    return decodeWord(texelFetch(StateSampler, wordCoordinate(index), 0));
}

uint readRegister(uint index) {
    return index == 0u ? 0u : readStateWord(REGISTER_BASE + index);
}

uint readMemoryWord(uint address) {
    return readStateWord(address >> 2u);
}

uint signExtend(uint value, uint bits) {
    uint shift = 32u - bits;
    return uint(int(value << shift) >> int(shift));
}

uint initialProgramWord(uint index) {
    // The bundled RV32I program fills the 32x18 framebuffer with values 1..576.
    // Its final EBREAK leaves the completed image and CPU state on the dashboard.
    if (index == 0u) return 0x000010b7u; // lui   x1, 0x1
    if (index == 1u) return 0x00100113u; // addi  x2, x0, 1
    if (index == 2u) return 0x00002337u; // lui   x6, 0x2
    if (index == 3u) return 0x90030313u; // addi  x6, x6, -1792
    if (index == 4u) return 0x0020a023u; // sw    x2, 0(x1)
    if (index == 5u) return 0x00408093u; // addi  x1, x1, 4
    if (index == 6u) return 0x00110113u; // addi  x2, x2, 1
    if (index == 7u) return 0xfe60eae3u; // bltu  x1, x6, -12
    if (index == 8u) return 0x00100073u; // ebreak
    return 0u;
}

uint initialWord(uint index) {
    if (index == MAGIC_INDEX) return MAGIC_VALUE;
    if (index == PC_INDEX) return 0u;
    if (index == CYCLE_INDEX) return 0u;
    if (index == STATUS_INDEX) return STATUS_RUNNING;
    if (index >= REGISTER_BASE && index < REGISTER_BASE + 32u) return 0u;
    return initialProgramWord(index);
}

void main() {
    uvec2 outputSize = uvec2(OutSize + 0.5);
    uvec2 pixel = min(uvec2(texCoord * OutSize), outputSize - uvec2(1u));
    uint outputIndex = pixel.y * TEXTURE_WIDTH + pixel.x;

    if (readStateWord(MAGIC_INDEX) != MAGIC_VALUE) {
        fragColor = encodeWord(initialWord(outputIndex));
        return;
    }

    uint currentWord = readStateWord(outputIndex);
    uint pc = readStateWord(PC_INDEX);
    uint cycle = readStateWord(CYCLE_INDEX);
    uint currentStatus = readStateWord(STATUS_INDEX);

    if (currentStatus != STATUS_RUNNING) {
        fragColor = encodeWord(currentWord);
        return;
    }

    uint nextPc = pc + 4u;
    uint nextStatus = STATUS_RUNNING;
    bool writeRegister = false;
    uint destinationRegister = 0u;
    uint registerValue = 0u;
    bool writeMemory = false;
    uint memoryAddress = 0u;
    uint memoryWidth = 0u;
    uint memoryValue = 0u;

    bool fetchValid = pc < RAM_BYTES && (pc & 3u) == 0u;
    uint instruction = fetchValid ? readMemoryWord(pc) : 0u;

    if (!fetchValid) {
        nextPc = pc;
        nextStatus = (pc & 3u) == 0u ? STATUS_FETCH_FAULT : STATUS_MISALIGNED_ACCESS;
    } else {
        uint opcode = instruction & 0x7fu;
        uint rd = (instruction >> 7u) & 0x1fu;
        uint funct3 = (instruction >> 12u) & 0x7u;
        uint rs1 = (instruction >> 15u) & 0x1fu;
        uint rs2 = (instruction >> 20u) & 0x1fu;
        uint funct7 = (instruction >> 25u) & 0x7fu;
        uint source1 = readRegister(rs1);
        uint source2 = readRegister(rs2);

        uint immediateI = signExtend(instruction >> 20u, 12u);
        uint immediateS = signExtend(
            ((instruction >> 25u) << 5u) | ((instruction >> 7u) & 0x1fu), 12u);
        uint immediateB = signExtend(
            (((instruction >> 31u) & 1u) << 12u)
            | (((instruction >> 7u) & 1u) << 11u)
            | (((instruction >> 25u) & 0x3fu) << 5u)
            | (((instruction >> 8u) & 0xfu) << 1u), 13u);
        uint immediateU = instruction & 0xfffff000u;
        uint immediateJ = signExtend(
            (((instruction >> 31u) & 1u) << 20u)
            | (((instruction >> 12u) & 0xffu) << 12u)
            | (((instruction >> 20u) & 1u) << 11u)
            | (((instruction >> 21u) & 0x3ffu) << 1u), 21u);

        bool legal = true;

        if (opcode == 0x37u) { // LUI
            writeRegister = true;
            destinationRegister = rd;
            registerValue = immediateU;
        } else if (opcode == 0x17u) { // AUIPC
            writeRegister = true;
            destinationRegister = rd;
            registerValue = pc + immediateU;
        } else if (opcode == 0x6fu) { // JAL
            uint target = pc + immediateJ;
            if ((target & 3u) != 0u) {
                nextPc = pc;
                nextStatus = STATUS_MISALIGNED_ACCESS;
            } else {
                writeRegister = true;
                destinationRegister = rd;
                registerValue = pc + 4u;
                nextPc = target;
            }
        } else if (opcode == 0x67u) { // JALR
            if (funct3 != 0u) {
                legal = false;
            } else {
                uint target = (source1 + immediateI) & 0xfffffffeu;
                if ((target & 3u) != 0u) {
                    nextPc = pc;
                    nextStatus = STATUS_MISALIGNED_ACCESS;
                } else {
                    writeRegister = true;
                    destinationRegister = rd;
                    registerValue = pc + 4u;
                    nextPc = target;
                }
            }
        } else if (opcode == 0x63u) { // Conditional branches
            bool takeBranch = false;
            if (funct3 == 0u) takeBranch = source1 == source2;
            else if (funct3 == 1u) takeBranch = source1 != source2;
            else if (funct3 == 4u) takeBranch = int(source1) < int(source2);
            else if (funct3 == 5u) takeBranch = int(source1) >= int(source2);
            else if (funct3 == 6u) takeBranch = source1 < source2;
            else if (funct3 == 7u) takeBranch = source1 >= source2;
            else legal = false;

            if (legal && takeBranch) {
                uint target = pc + immediateB;
                if ((target & 3u) != 0u) {
                    nextPc = pc;
                    nextStatus = STATUS_MISALIGNED_ACCESS;
                } else {
                    nextPc = target;
                }
            }
        } else if (opcode == 0x03u) { // Loads
            uint address = source1 + immediateI;
            uint width = funct3 == 0u || funct3 == 4u ? 1u
                       : funct3 == 1u || funct3 == 5u ? 2u
                       : funct3 == 2u ? 4u : 0u;
            bool aligned = width == 1u || (width == 2u && (address & 1u) == 0u)
                         || (width == 4u && (address & 3u) == 0u);
            bool inRange = width > 0u && address <= RAM_BYTES - width;

            if (width == 0u) {
                legal = false;
            } else if (!aligned) {
                nextPc = pc;
                nextStatus = STATUS_MISALIGNED_ACCESS;
            } else if (!inRange) {
                nextPc = pc;
                nextStatus = STATUS_LOAD_FAULT;
            } else {
                uint word = readMemoryWord(address);
                uint shift = (address & 3u) * 8u;
                uint loaded = width == 1u ? ((word >> shift) & 0xffu)
                            : width == 2u ? ((word >> shift) & 0xffffu)
                            : word;
                if (funct3 == 0u) loaded = signExtend(loaded, 8u);
                if (funct3 == 1u) loaded = signExtend(loaded, 16u);
                writeRegister = true;
                destinationRegister = rd;
                registerValue = loaded;
            }
        } else if (opcode == 0x23u) { // Stores
            uint address = source1 + immediateS;
            uint width = funct3 == 0u ? 1u : funct3 == 1u ? 2u : funct3 == 2u ? 4u : 0u;
            bool aligned = width == 1u || (width == 2u && (address & 1u) == 0u)
                         || (width == 4u && (address & 3u) == 0u);
            bool inRange = width > 0u && address <= RAM_BYTES - width;

            if (width == 0u) {
                legal = false;
            } else if (!aligned) {
                nextPc = pc;
                nextStatus = STATUS_MISALIGNED_ACCESS;
            } else if (!inRange) {
                nextPc = pc;
                nextStatus = STATUS_STORE_FAULT;
            } else {
                writeMemory = true;
                memoryAddress = address;
                memoryWidth = width;
                memoryValue = source2;
            }
        } else if (opcode == 0x13u) { // Register-immediate operations
            writeRegister = true;
            destinationRegister = rd;
            uint shiftAmount = (instruction >> 20u) & 0x1fu;
            if (funct3 == 0u) registerValue = source1 + immediateI;
            else if (funct3 == 2u) registerValue = int(source1) < int(immediateI) ? 1u : 0u;
            else if (funct3 == 3u) registerValue = source1 < immediateI ? 1u : 0u;
            else if (funct3 == 4u) registerValue = source1 ^ immediateI;
            else if (funct3 == 6u) registerValue = source1 | immediateI;
            else if (funct3 == 7u) registerValue = source1 & immediateI;
            else if (funct3 == 1u && funct7 == 0u) registerValue = source1 << shiftAmount;
            else if (funct3 == 5u && funct7 == 0u) registerValue = source1 >> shiftAmount;
            else if (funct3 == 5u && funct7 == 0x20u) registerValue = uint(int(source1) >> int(shiftAmount));
            else legal = false;
        } else if (opcode == 0x33u) { // Register-register operations
            writeRegister = true;
            destinationRegister = rd;
            uint shiftAmount = source2 & 0x1fu;
            if (funct3 == 0u && funct7 == 0u) registerValue = source1 + source2;
            else if (funct3 == 0u && funct7 == 0x20u) registerValue = source1 - source2;
            else if (funct3 == 1u && funct7 == 0u) registerValue = source1 << shiftAmount;
            else if (funct3 == 2u && funct7 == 0u) registerValue = int(source1) < int(source2) ? 1u : 0u;
            else if (funct3 == 3u && funct7 == 0u) registerValue = source1 < source2 ? 1u : 0u;
            else if (funct3 == 4u && funct7 == 0u) registerValue = source1 ^ source2;
            else if (funct3 == 5u && funct7 == 0u) registerValue = source1 >> shiftAmount;
            else if (funct3 == 5u && funct7 == 0x20u) registerValue = uint(int(source1) >> int(shiftAmount));
            else if (funct3 == 6u && funct7 == 0u) registerValue = source1 | source2;
            else if (funct3 == 7u && funct7 == 0u) registerValue = source1 & source2;
            else legal = false;
        } else if (opcode == 0x0fu) { // FENCE
            legal = funct3 == 0u;
        } else if (opcode == 0x73u) { // ECALL and EBREAK
            if (instruction == 0x00000073u) {
                nextPc = pc;
                nextStatus = STATUS_ECALL;
            } else if (instruction == 0x00100073u) {
                nextPc = pc;
                nextStatus = STATUS_EBREAK;
            } else {
                legal = false;
            }
        } else {
            legal = false;
        }

        if (!legal) {
            nextPc = pc;
            nextStatus = STATUS_ILLEGAL_INSTRUCTION;
            writeRegister = false;
            writeMemory = false;
        }
    }

    uint outputWord = currentWord;
    if (outputIndex == PC_INDEX) outputWord = nextPc;
    if (outputIndex == CYCLE_INDEX) outputWord = cycle + 1u;
    if (outputIndex == STATUS_INDEX) outputWord = nextStatus;

    if (writeRegister && destinationRegister != 0u
            && outputIndex == REGISTER_BASE + destinationRegister) {
        outputWord = registerValue;
    }
    if (outputIndex == REGISTER_BASE) {
        outputWord = 0u;
    }

    if (writeMemory && outputIndex == (memoryAddress >> 2u)) {
        uint shift = (memoryAddress & 3u) * 8u;
        if (memoryWidth == 1u) {
            uint mask = 0xffu << shift;
            outputWord = (currentWord & ~mask) | ((memoryValue << shift) & mask);
        } else if (memoryWidth == 2u) {
            uint mask = 0xffffu << shift;
            outputWord = (currentWord & ~mask) | ((memoryValue << shift) & mask);
        } else {
            outputWord = memoryValue;
        }
    }

    fragColor = encodeWord(outputWord);
}
