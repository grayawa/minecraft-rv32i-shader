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
const uint CSR_BASE = 16316u;
const uint REGISTER_BASE = 16348u;
const uint STATUS_INDEX = 16380u;
const uint CYCLE_INDEX = 16381u;
const uint PC_INDEX = 16382u;
const uint MAGIC_INDEX = 16383u;
const uint MAGIC_VALUE = 0x52563332u;
const uint RAM_WORDS = CSR_BASE;
const uint RAM_BYTES = RAM_WORDS * 4u;
const uint INVALID_INDEX = 0xffffffffu;

const uint CSR_MSTATUS = 0x300u;
const uint CSR_MISA = 0x301u;
const uint CSR_MEDELEG = 0x302u;
const uint CSR_MIDELEG = 0x303u;
const uint CSR_MIE = 0x304u;
const uint CSR_MTVEC = 0x305u;
const uint CSR_MSCRATCH = 0x340u;
const uint CSR_MEPC = 0x341u;
const uint CSR_MCAUSE = 0x342u;
const uint CSR_MTVAL = 0x343u;
const uint CSR_MIP = 0x344u;
const uint CSR_SATP = 0x180u;
const uint CSR_MCYCLE = 0xb00u;
const uint CSR_MINSTRET = 0xb02u;
const uint CSR_CYCLE = 0xc00u;
const uint CSR_INSTRET = 0xc02u;
const uint CSR_MHARTID = 0xf14u;
const uint CSR_SSTATUS = 0x100u;
const uint CSR_SIE = 0x104u;
const uint CSR_STVEC = 0x105u;
const uint CSR_SSCRATCH = 0x140u;
const uint CSR_SEPC = 0x141u;
const uint CSR_SCAUSE = 0x142u;
const uint CSR_STVAL = 0x143u;
const uint CSR_SIP = 0x144u;
const uint PRIVILEGE_INDEX = CSR_BASE + 28u;
const uint RESERVATION_ADDRESS_INDEX = CSR_BASE + 29u;
const uint RESERVATION_VALID_INDEX = CSR_BASE + 30u;

const uint PRIVILEGE_USER = 0u;
const uint PRIVILEGE_SUPERVISOR = 1u;
const uint PRIVILEGE_MACHINE = 3u;

const uint STATUS_RUNNING = 0u;
const uint STATUS_EBREAK = 1u;

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

uint multiplyHighUnsigned(uint left, uint right) {
    uint leftLow = left & 0xffffu;
    uint leftHigh = left >> 16u;
    uint rightLow = right & 0xffffu;
    uint rightHigh = right >> 16u;
    uint lowProduct = leftLow * rightLow;
    uint middle = leftHigh * rightLow + (lowProduct >> 16u);
    uint carryProduct = leftLow * rightHigh + (middle & 0xffffu);
    return leftHigh * rightHigh + (middle >> 16u) + (carryProduct >> 16u);
}

uint multiplyHighSignedUnsigned(uint left, uint right) {
    uint highWord = multiplyHighUnsigned(left, right);
    return (left & 0x80000000u) != 0u ? highWord - right : highWord;
}

uint multiplyHighSigned(uint left, uint right) {
    uint highWord = multiplyHighUnsigned(left, right);
    if ((left & 0x80000000u) != 0u) highWord -= right;
    if ((right & 0x80000000u) != 0u) highWord -= left;
    return highWord;
}

uint csrStateIndex(uint address) {
    if (address == CSR_MSTATUS || address == CSR_SSTATUS) return CSR_BASE + 0u;
    if (address == CSR_MEDELEG) return CSR_BASE + 1u;
    if (address == CSR_MIDELEG) return CSR_BASE + 2u;
    if (address == CSR_MIE || address == CSR_SIE) return CSR_BASE + 3u;
    if (address == CSR_MTVEC) return CSR_BASE + 4u;
    if (address == CSR_MSCRATCH) return CSR_BASE + 5u;
    if (address == CSR_MEPC) return CSR_BASE + 6u;
    if (address == CSR_MCAUSE) return CSR_BASE + 7u;
    if (address == CSR_MTVAL) return CSR_BASE + 8u;
    if (address == CSR_MIP || address == CSR_SIP) return CSR_BASE + 9u;
    if (address == CSR_SATP) return CSR_BASE + 10u;
    if (address == CSR_STVEC) return CSR_BASE + 11u;
    if (address == CSR_SSCRATCH) return CSR_BASE + 12u;
    if (address == CSR_SEPC) return CSR_BASE + 13u;
    if (address == CSR_SCAUSE) return CSR_BASE + 14u;
    if (address == CSR_STVAL) return CSR_BASE + 15u;
    return INVALID_INDEX;
}

bool csrSupported(uint address) {
    return csrStateIndex(address) != INVALID_INDEX
        || address == CSR_MISA
        || address == CSR_MCYCLE
        || address == CSR_MINSTRET
        || address == CSR_CYCLE
        || address == CSR_INSTRET
        || address == CSR_MHARTID;
}

bool csrWritable(uint address) {
    return csrStateIndex(address) != INVALID_INDEX;
}

uint csrWriteMask(uint address) {
    if (address == CSR_SSTATUS) return 0x000de162u;
    if (address == CSR_SIE || address == CSR_SIP) return 0x00000222u;
    return 0xffffffffu;
}

bool csrAccessible(uint address, uint privilege) {
    uint requiredPrivilege = (address >> 8u) & 0x3u;
    return privilege >= requiredPrivilege;
}

uint readCSR(uint address) {
    if (address == CSR_MISA) return 0x40001101u; // RV32IMA
    if (address == CSR_MCYCLE || address == CSR_MINSTRET
            || address == CSR_CYCLE || address == CSR_INSTRET) {
        return readStateWord(CYCLE_INDEX);
    }
    if (address == CSR_MHARTID) return 0u;
    uint index = csrStateIndex(address);
    uint value = index == INVALID_INDEX ? 0u : readStateWord(index);
    if (address == CSR_SSTATUS) return value & 0x000de162u;
    if (address == CSR_SIE || address == CSR_SIP) return value & 0x00000222u;
    return value;
}

uint initialProgramWord(uint index) {
    // The bundled program validates RV32IMA, M/S CSR access, synchronous
    // exception delegation, MRET, and SRET before filling the framebuffer.
    if (index == 0u) return 0x01500193u;
    if (index == 1u) return 0x00600213u;
    if (index == 2u) return 0x024182b3u;
    if (index == 3u) return 0x02419333u;
    if (index == 4u) return 0x0241a3b3u;
    if (index == 5u) return 0x0241b433u;
    if (index == 6u) return 0x0241c4b3u;
    if (index == 7u) return 0x0241d533u;
    if (index == 8u) return 0x0241e5b3u;
    if (index == 9u) return 0x0241f633u;
    if (index == 10u) return 0x07e00693u;
    if (index == 11u) return 0x22d29a63u;
    if (index == 12u) return 0x22031863u;
    if (index == 13u) return 0x22039663u;
    if (index == 14u) return 0x22041463u;
    if (index == 15u) return 0x00300713u;
    if (index == 16u) return 0x22e49063u;
    if (index == 17u) return 0x20e51e63u;
    if (index == 18u) return 0x20e59c63u;
    if (index == 19u) return 0x20e61a63u;
    if (index == 20u) return 0x340297f3u;
    if (index == 21u) return 0x34002873u;
    if (index == 22u) return 0x20079463u;
    if (index == 23u) return 0x20581263u;
    if (index == 24u) return 0x40000893u;
    if (index == 25u) return 0x00700913u;
    if (index == 26u) return 0x0128a023u;
    if (index == 27u) return 0x1008a9afu;
    if (index == 28u) return 0x00900a13u;
    if (index == 29u) return 0x1948aaafu;
    if (index == 30u) return 0x0008ab03u;
    if (index == 31u) return 0x00700b93u;
    if (index == 32u) return 0x1f799063u;
    if (index == 33u) return 0x1c0a9e63u;
    if (index == 34u) return 0x00900b93u;
    if (index == 35u) return 0x1d7b1a63u;
    if (index == 36u) return 0x0128ac2fu;
    if (index == 37u) return 0x0008ac83u;
    if (index == 38u) return 0x1d7c1463u;
    if (index == 39u) return 0x01000b93u;
    if (index == 40u) return 0x1d7c9063u;
    if (index == 41u) return 0x27400d13u;
    if (index == 42u) return 0x305d1073u;
    if (index == 43u) return 0x00000d93u;
    if (index == 44u) return 0x00000073u;
    if (index == 45u) return 0x00100e13u;
    if (index == 46u) return 0x1bcd9463u;
    if (index == 47u) return 0x34202ef3u;
    if (index == 48u) return 0x00b00f13u;
    if (index == 49u) return 0x19ee9e63u;
    if (index == 50u) return 0x00102003u;
    if (index == 51u) return 0x00200e13u;
    if (index == 52u) return 0x19cd9863u;
    if (index == 53u) return 0x34202ef3u;
    if (index == 54u) return 0x00400f13u;
    if (index == 55u) return 0x19ee9263u;
    if (index == 56u) return 0x34302ef3u;
    if (index == 57u) return 0x00100f13u;
    if (index == 58u) return 0x17ee9c63u;
    if (index == 59u) return 0x28800d13u;
    if (index == 60u) return 0x105d1073u;
    if (index == 61u) return 0x2f700d13u;
    if (index == 62u) return 0x302d1073u;
    if (index == 63u) return 0x11400d13u;
    if (index == 64u) return 0x341d1073u;
    if (index == 65u) return 0x00001d37u;
    if (index == 66u) return 0x800d0d13u;
    if (index == 67u) return 0x300d1073u;
    if (index == 68u) return 0x30200073u;
    if (index == 69u) return 0x00000d93u;
    if (index == 70u) return 0x00000073u;
    if (index == 71u) return 0x00100e13u;
    if (index == 72u) return 0x15cd9063u;
    if (index == 73u) return 0x14202ef3u;
    if (index == 74u) return 0x00900f13u;
    if (index == 75u) return 0x13ee9a63u;
    if (index == 76u) return 0xffffffffu;
    if (index == 77u) return 0x00200e13u;
    if (index == 78u) return 0x13cd9463u;
    if (index == 79u) return 0x14202ef3u;
    if (index == 80u) return 0x00200f13u;
    if (index == 81u) return 0x11ee9e63u;
    if (index == 82u) return 0x14302ef3u;
    if (index == 83u) return 0xfff00f13u;
    if (index == 84u) return 0x11ee9863u;
    if (index == 85u) return 0x00102003u;
    if (index == 86u) return 0x00300e13u;
    if (index == 87u) return 0x11cd9263u;
    if (index == 88u) return 0x14202ef3u;
    if (index == 89u) return 0x00400f13u;
    if (index == 90u) return 0x0fee9c63u;
    if (index == 91u) return 0x14302ef3u;
    if (index == 92u) return 0x00100f13u;
    if (index == 93u) return 0x0fee9663u;
    if (index == 94u) return 0x00002123u;
    if (index == 95u) return 0x00400e13u;
    if (index == 96u) return 0x0fcd9063u;
    if (index == 97u) return 0x14202ef3u;
    if (index == 98u) return 0x00600f13u;
    if (index == 99u) return 0x0dee9a63u;
    if (index == 100u) return 0x14302ef3u;
    if (index == 101u) return 0x00200f13u;
    if (index == 102u) return 0x0dee9463u;
    if (index == 103u) return 0x00010d37u;
    if (index == 104u) return 0xef0d0d13u;
    if (index == 105u) return 0x000d2003u;
    if (index == 106u) return 0x00500e13u;
    if (index == 107u) return 0x0bcd9a63u;
    if (index == 108u) return 0x14202ef3u;
    if (index == 109u) return 0x00500f13u;
    if (index == 110u) return 0x0bee9463u;
    if (index == 111u) return 0x14302ef3u;
    if (index == 112u) return 0x0bae9063u;
    if (index == 113u) return 0x000d2023u;
    if (index == 114u) return 0x00600e13u;
    if (index == 115u) return 0x09cd9a63u;
    if (index == 116u) return 0x14202ef3u;
    if (index == 117u) return 0x00700f13u;
    if (index == 118u) return 0x09ee9463u;
    if (index == 119u) return 0x14302ef3u;
    if (index == 120u) return 0x09ae9063u;
    if (index == 121u) return 0x00200d13u;
    if (index == 122u) return 0x000d0067u;
    if (index == 123u) return 0x00700e13u;
    if (index == 124u) return 0x07cd9863u;
    if (index == 125u) return 0x14202ef3u;
    if (index == 126u) return 0x00000f13u;
    if (index == 127u) return 0x07ee9263u;
    if (index == 128u) return 0x14302ef3u;
    if (index == 129u) return 0x00200f13u;
    if (index == 130u) return 0x05ee9c63u;
    if (index == 131u) return 0x22000d13u;
    if (index == 132u) return 0x140d1073u;
    if (index == 133u) return 0x00010d37u;
    if (index == 134u) return 0xef0d0d13u;
    if (index == 135u) return 0x000d0067u;
    if (index == 136u) return 0x00800e13u;
    if (index == 137u) return 0x03cd9e63u;
    if (index == 138u) return 0x14202ef3u;
    if (index == 139u) return 0x00100f13u;
    if (index == 140u) return 0x03ee9863u;
    if (index == 141u) return 0x14302ef3u;
    if (index == 142u) return 0x03ae9463u;
    if (index == 143u) return 0x000010b7u;
    if (index == 144u) return 0x00100113u;
    if (index == 145u) return 0x00002337u;
    if (index == 146u) return 0x90030313u;
    if (index == 147u) return 0x0020a023u;
    if (index == 148u) return 0x00408093u;
    if (index == 149u) return 0x00110113u;
    if (index == 150u) return 0xfe60eae3u;
    if (index == 151u) return 0x00100073u;
    if (index == 152u) return 0x000010b7u;
    if (index == 153u) return 0xdeadc137u;
    if (index == 154u) return 0xeef10113u;
    if (index == 155u) return 0x0020a023u;
    if (index == 156u) return 0x00100073u;
    if (index == 157u) return 0x001d8d93u;
    if (index == 158u) return 0x34102ff3u;
    if (index == 159u) return 0x004f8f93u;
    if (index == 160u) return 0x341f9073u;
    if (index == 161u) return 0x30200073u;
    if (index == 162u) return 0x001d8d93u;
    if (index == 163u) return 0x14202f73u;
    if (index == 164u) return 0x00100f93u;
    if (index == 165u) return 0x01ff1863u;
    if (index == 166u) return 0x14002ff3u;
    if (index == 167u) return 0x141f9073u;
    if (index == 168u) return 0x10200073u;
    if (index == 169u) return 0x14102ff3u;
    if (index == 170u) return 0x004f8f93u;
    if (index == 171u) return 0x141f9073u;
    if (index == 172u) return 0x10200073u;
    return 0u;
}

uint initialWord(uint index) {
    if (index == MAGIC_INDEX) return MAGIC_VALUE;
    if (index == PC_INDEX) return 0u;
    if (index == CYCLE_INDEX) return 0u;
    if (index == STATUS_INDEX) return STATUS_RUNNING;
    if (index == PRIVILEGE_INDEX) return PRIVILEGE_MACHINE;
    if (index >= CSR_BASE && index < REGISTER_BASE) return 0u;
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
    uint currentPrivilege = readStateWord(PRIVILEGE_INDEX);
    uint nextPrivilege = currentPrivilege;
    uint nextReservationAddress = readStateWord(RESERVATION_ADDRESS_INDEX);
    uint nextReservationValid = readStateWord(RESERVATION_VALID_INDEX);

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
    bool writeCSR = false;
    uint csrWriteIndex = INVALID_INDEX;
    uint csrWriteValue = 0u;
    bool machineTrap = false;
    bool supervisorTrap = false;
    bool takeTrap = false;
    uint trapCause = 0u;
    uint trapValue = 0u;
    uint trapMstatus = 0u;

    bool fetchValid = pc < RAM_BYTES && (pc & 3u) == 0u;
    uint instruction = fetchValid ? readMemoryWord(pc) : 0u;

    if (!fetchValid) {
        takeTrap = true;
        trapCause = (pc & 3u) == 0u ? 1u : 0u;
        trapValue = pc;
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
                takeTrap = true;
                trapCause = 0u;
                trapValue = target;
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
                    takeTrap = true;
                    trapCause = 0u;
                    trapValue = target;
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
                    takeTrap = true;
                    trapCause = 0u;
                    trapValue = target;
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
                takeTrap = true;
                trapCause = 4u;
                trapValue = address;
            } else if (!inRange) {
                takeTrap = true;
                trapCause = 5u;
                trapValue = address;
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
                takeTrap = true;
                trapCause = 6u;
                trapValue = address;
            } else if (!inRange) {
                takeTrap = true;
                trapCause = 7u;
                trapValue = address;
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
            if (funct7 == 0x01u) { // RV32M
                if (funct3 == 0u) registerValue = source1 * source2;
                else if (funct3 == 1u) registerValue = multiplyHighSigned(source1, source2);
                else if (funct3 == 2u) registerValue = multiplyHighSignedUnsigned(source1, source2);
                else if (funct3 == 3u) registerValue = multiplyHighUnsigned(source1, source2);
                else if (funct3 == 4u) {
                    if (source2 == 0u) registerValue = 0xffffffffu;
                    else if (source1 == 0x80000000u && source2 == 0xffffffffu) registerValue = source1;
                    else registerValue = uint(int(source1) / int(source2));
                } else if (funct3 == 5u) {
                    registerValue = source2 == 0u ? 0xffffffffu : source1 / source2;
                } else if (funct3 == 6u) {
                    if (source2 == 0u) registerValue = source1;
                    else if (source1 == 0x80000000u && source2 == 0xffffffffu) registerValue = 0u;
                    else registerValue = uint(int(source1) % int(source2));
                } else if (funct3 == 7u) {
                    registerValue = source2 == 0u ? source1 : source1 % source2;
                } else legal = false;
            } else if (funct3 == 0u && funct7 == 0u) registerValue = source1 + source2;
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
        } else if (opcode == 0x2fu) { // RV32A word operations
            uint address = source1;
            uint atomicFunction = instruction >> 27u;
            bool aligned = (address & 3u) == 0u;
            bool inRange = address <= RAM_BYTES - 4u;

            if (funct3 != 2u) {
                legal = false;
            } else if (!aligned) {
                takeTrap = true;
                trapCause = atomicFunction == 2u ? 4u : 6u;
                trapValue = address;
            } else if (!inRange) {
                takeTrap = true;
                trapCause = atomicFunction == 2u ? 5u : 7u;
                trapValue = address;
            } else {
                uint oldMemoryValue = readMemoryWord(address);
                writeRegister = true;
                destinationRegister = rd;
                registerValue = oldMemoryValue;

                if (atomicFunction == 2u && rs2 == 0u) { // LR.W
                    nextReservationAddress = address;
                    nextReservationValid = 1u;
                } else if (atomicFunction == 3u) { // SC.W
                    bool reservationMatches = nextReservationValid != 0u
                        && nextReservationAddress == address;
                    registerValue = reservationMatches ? 0u : 1u;
                    if (reservationMatches) {
                        writeMemory = true;
                        memoryAddress = address;
                        memoryWidth = 4u;
                        memoryValue = source2;
                    }
                    nextReservationValid = 0u;
                } else {
                    uint atomicValue = 0u;
                    if (atomicFunction == 1u) atomicValue = source2; // AMOSWAP.W
                    else if (atomicFunction == 0u) atomicValue = oldMemoryValue + source2; // AMOADD.W
                    else if (atomicFunction == 4u) atomicValue = oldMemoryValue ^ source2; // AMOXOR.W
                    else if (atomicFunction == 12u) atomicValue = oldMemoryValue & source2; // AMOAND.W
                    else if (atomicFunction == 8u) atomicValue = oldMemoryValue | source2; // AMOOR.W
                    else if (atomicFunction == 16u) atomicValue = int(oldMemoryValue) < int(source2) ? oldMemoryValue : source2; // AMOMIN.W
                    else if (atomicFunction == 20u) atomicValue = int(oldMemoryValue) > int(source2) ? oldMemoryValue : source2; // AMOMAX.W
                    else if (atomicFunction == 24u) atomicValue = oldMemoryValue < source2 ? oldMemoryValue : source2; // AMOMINU.W
                    else if (atomicFunction == 28u) atomicValue = oldMemoryValue > source2 ? oldMemoryValue : source2; // AMOMAXU.W
                    else legal = false;

                    if (legal) {
                        writeMemory = true;
                        memoryAddress = address;
                        memoryWidth = 4u;
                        memoryValue = atomicValue;
                        nextReservationValid = 0u;
                    }
                }
            }
        } else if (opcode == 0x0fu) { // FENCE and FENCE.I
            legal = funct3 == 0u || funct3 == 1u;
        } else if (opcode == 0x73u) { // Environment and CSR operations
            if (funct3 == 0u) {
                if (instruction == 0x00000073u) {
                    takeTrap = true;
                    trapCause = currentPrivilege == PRIVILEGE_USER ? 8u
                        : currentPrivilege == PRIVILEGE_SUPERVISOR ? 9u : 11u;
                } else if (instruction == 0x00100073u) {
                    nextPc = pc;
                    nextStatus = STATUS_EBREAK;
                } else if (instruction == 0x30200073u
                        && currentPrivilege == PRIVILEGE_MACHINE) {
                    uint mstatus = readCSR(CSR_MSTATUS);
                    uint machinePreviousInterruptEnable = (mstatus >> 7u) & 1u;
                    uint machinePreviousPrivilege = (mstatus >> 11u) & 0x3u;
                    nextPc = readCSR(CSR_MEPC);
                    nextPrivilege = machinePreviousPrivilege;
                    writeCSR = true;
                    csrWriteIndex = csrStateIndex(CSR_MSTATUS);
                    csrWriteValue = (mstatus & ~0x1888u)
                        | (machinePreviousInterruptEnable << 3u)
                        | (1u << 7u);
                } else if (instruction == 0x10200073u
                        && currentPrivilege >= PRIVILEGE_SUPERVISOR) {
                    uint mstatus = readCSR(CSR_MSTATUS);
                    uint supervisorPreviousInterruptEnable = (mstatus >> 5u) & 1u;
                    uint supervisorPreviousPrivilege = (mstatus >> 8u) & 1u;
                    nextPc = readCSR(CSR_SEPC);
                    nextPrivilege = supervisorPreviousPrivilege;
                    writeCSR = true;
                    csrWriteIndex = csrStateIndex(CSR_MSTATUS);
                    csrWriteValue = (mstatus & ~0x122u)
                        | (supervisorPreviousInterruptEnable << 1u)
                        | (1u << 5u);
                } else {
                    legal = false;
                }
            } else {
                uint csrAddress = instruction >> 20u;
                bool immediateCSR = funct3 >= 5u;
                uint csrOperand = immediateCSR ? rs1 : source1;
                uint oldCSRValue = readCSR(csrAddress);
                bool replaceCSR = funct3 == 1u || funct3 == 5u;
                bool setCSRBits = funct3 == 2u || funct3 == 6u;
                bool clearCSRBits = funct3 == 3u || funct3 == 7u;
                bool wantsCSRWrite = replaceCSR || ((setCSRBits || clearCSRBits) && csrOperand != 0u);

                if (!csrSupported(csrAddress) || !csrAccessible(csrAddress, currentPrivilege)
                        || (!replaceCSR && !setCSRBits && !clearCSRBits)
                        || (wantsCSRWrite && !csrWritable(csrAddress))) {
                    legal = false;
                } else {
                    writeRegister = true;
                    destinationRegister = rd;
                    registerValue = oldCSRValue;
                    if (wantsCSRWrite) {
                        writeCSR = true;
                        csrWriteIndex = csrStateIndex(csrAddress);
                        uint requestedCSRValue = replaceCSR ? csrOperand
                            : setCSRBits ? oldCSRValue | csrOperand
                            : oldCSRValue & ~csrOperand;
                        uint writeMask = csrWriteMask(csrAddress);
                        uint rawCSRValue = readStateWord(csrWriteIndex);
                        csrWriteValue = (rawCSRValue & ~writeMask)
                            | (requestedCSRValue & writeMask);
                    }
                }
            }
        } else {
            legal = false;
        }

        if (!legal) {
            takeTrap = true;
            trapCause = 2u;
            trapValue = instruction;
            writeRegister = false;
            writeMemory = false;
            writeCSR = false;
        }
    }

    if (takeTrap) {
        writeRegister = false;
        writeMemory = false;
        writeCSR = false;
        uint mstatus = readCSR(CSR_MSTATUS);
        bool delegated = currentPrivilege != PRIVILEGE_MACHINE
            && ((readCSR(CSR_MEDELEG) >> trapCause) & 1u) != 0u;
        if (delegated) {
            supervisorTrap = true;
            uint supervisorInterruptEnable = (mstatus >> 1u) & 1u;
            trapMstatus = (mstatus & ~0x122u)
                | (supervisorInterruptEnable << 5u)
                | ((currentPrivilege & 1u) << 8u);
            nextPc = readCSR(CSR_STVEC) & ~0x3u;
            nextPrivilege = PRIVILEGE_SUPERVISOR;
        } else {
            machineTrap = true;
            uint machineInterruptEnable = (mstatus >> 3u) & 1u;
            trapMstatus = (mstatus & ~0x1888u)
                | (machineInterruptEnable << 7u)
                | (currentPrivilege << 11u);
            nextPc = readCSR(CSR_MTVEC) & ~0x3u;
            nextPrivilege = PRIVILEGE_MACHINE;
        }
    }

    if (writeMemory) {
        nextReservationValid = 0u;
    }

    uint outputWord = currentWord;
    if (outputIndex == PC_INDEX) outputWord = nextPc;
    if (outputIndex == CYCLE_INDEX) outputWord = cycle + 1u;
    if (outputIndex == STATUS_INDEX) outputWord = nextStatus;
    if (outputIndex == PRIVILEGE_INDEX) outputWord = nextPrivilege;
    if (outputIndex == RESERVATION_ADDRESS_INDEX) outputWord = nextReservationAddress;
    if (outputIndex == RESERVATION_VALID_INDEX) outputWord = nextReservationValid;

    if (writeRegister && destinationRegister != 0u
            && outputIndex == REGISTER_BASE + destinationRegister) {
        outputWord = registerValue;
    }
    if (outputIndex == REGISTER_BASE) {
        outputWord = 0u;
    }

    if (writeCSR && outputIndex == csrWriteIndex) {
        outputWord = csrWriteValue;
    }

    if (machineTrap) {
        if (outputIndex == csrStateIndex(CSR_MSTATUS)) outputWord = trapMstatus;
        if (outputIndex == csrStateIndex(CSR_MEPC)) outputWord = pc;
        if (outputIndex == csrStateIndex(CSR_MCAUSE)) outputWord = trapCause;
        if (outputIndex == csrStateIndex(CSR_MTVAL)) outputWord = trapValue;
    }
    if (supervisorTrap) {
        if (outputIndex == csrStateIndex(CSR_MSTATUS)) outputWord = trapMstatus;
        if (outputIndex == csrStateIndex(CSR_SEPC)) outputWord = pc;
        if (outputIndex == csrStateIndex(CSR_SCAUSE)) outputWord = trapCause;
        if (outputIndex == csrStateIndex(CSR_STVAL)) outputWord = trapValue;
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
