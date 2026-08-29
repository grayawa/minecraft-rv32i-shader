#version 330
#extension GL_ARB_separate_shader_objects : require

uniform sampler2D SceneSampler;
uniform sampler2D StateSampler;
uniform sampler2D RamSampler;

layout(location = 0) in vec2 texCoord;

layout(std140) uniform SamplerInfo {
    vec2 OutSize;
    vec2 SceneSize;
    vec2 StateSize;
    vec2 RamSize;
};

layout(location = 0) out vec4 fragColor;

const uint STATE_TEXTURE_WIDTH = 128u;
const uint RAM_TEXTURE_WIDTH = 4096u;
const uint RAM_TEXTURE_WORDS = 3145728u;
const uint RAM_WORDS = RAM_TEXTURE_WORDS - 1024u;
const uint REGISTER_BASE = 16348u;
const uint STATUS_INDEX = 16380u;
const uint CYCLE_INDEX = 16381u;
const uint PC_INDEX = 16382u;
const uint CSR_MEPC_INDEX = 0x341u;
const uint CSR_MCAUSE_INDEX = 0x342u;
const uint CSR_MTVAL_INDEX = 0x343u;
const uint FRAMEBUFFER_BASE = 1024u;
const uint UART_TX_HEAD_INDEX = 16307u;
const uint UART_LINE_LENGTH_BASE = 4871u;
const uint UART_LINE_COUNT = 32u;
const uint KEYBOARD_SELECTION_INDEX = 4904u;
const uint RAM_PAGE_INDEX = 4907u;
const uint TERMINAL_CELL_BASE = 4908u;
const uint TERMINAL_COLUMNS = 32u;
const uint TERMINAL_ROWS = 14u;
const uint TERMINAL_CELL_COUNT = TERMINAL_COLUMNS * TERMINAL_ROWS;
const uint UART_TX_BUFFER_OFFSET = RAM_WORDS * 4u;
const uint UART_TX_BUFFER_BYTES = 1024u;
const uint UART_TERMINAL_BYTES = 448u;
const uint RAM_PAGE_COUNT = 24u;
const uint RAM_PAGE_WORDS = 131072u;
const uint RAM_SAMPLE_WORD_STRIDE = 1024u;
const ivec2 FRAMEBUFFER_SIZE = ivec2(32, 18);

ivec2 stateWordCoordinate(uint index) {
    return ivec2(int(index % STATE_TEXTURE_WIDTH), int(index / STATE_TEXTURE_WIDTH));
}

ivec2 ramWordCoordinate(uint index) {
    return ivec2(int(index % RAM_TEXTURE_WIDTH), int(index / RAM_TEXTURE_WIDTH));
}

uint decodeWord(vec4 encoded) {
    uvec4 bytes = uvec4(floor(encoded * 255.0 + 0.5));
    return bytes.r | (bytes.g << 8u) | (bytes.b << 16u) | (bytes.a << 24u);
}

uint readStateWord(uint index) {
    return decodeWord(texelFetch(StateSampler, stateWordCoordinate(index), 0));
}

uint readRamWord(uint index) {
    return decodeWord(texelFetch(RamSampler, ramWordCoordinate(index), 0));
}

uint readByte(uint address) {
    return (readRamWord(address >> 2u) >> ((address & 3u) * 8u)) & 0xffu;
}

uint glyphBits(int code) {
    if (code >= 97 && code <= 122) code -= 32;
    switch (code) {
        case 32: return 0x000000u; // space
        case 35: return 0x5F55F5u; // #
        case 39: return 0x200002u; // '
        case 40: return 0x244442u; // (
        case 41: return 0x422224u; // )
        case 45: return 0x000F00u; // -
        case 46: return 0x200000u; // .
        case 47: return 0x442211u; // /
        case 48: return 0x69DB96u; // 0
        case 49: return 0x722262u; // 1
        case 50: return 0xF42196u; // 2
        case 51: return 0x69161Eu; // 3
        case 52: return 0x22FA62u; // 4
        case 53: return 0x691E8Fu; // 5
        case 54: return 0x699E86u; // 6
        case 55: return 0x44421Fu; // 7
        case 56: return 0x699696u; // 8
        case 57: return 0x617996u; // 9
        case 58: return 0x202002u; // :
        case 59: return 0x202006u; // ;
        case 60: return 0x842480u; // <
        case 61: return 0x0F0F00u; // =
        case 62: return 0x124210u; // >
        case 63: return 0x202196u; // ?
        case 65: return 0x99F996u; // A
        case 66: return 0xE99E9Eu; // B
        case 67: return 0x788887u; // C
        case 68: return 0xE9999Eu; // D
        case 69: return 0xF88E8Fu; // E
        case 70: return 0x888E8Fu; // F
        case 71: return 0x698B96u; // G
        case 72: return 0x999F99u; // H
        case 73: return 0xF2222Fu; // I
        case 74: return 0x4AA22Fu; // J
        case 75: return 0x99ACA9u; // K
        case 76: return 0xF88888u; // L
        case 77: return 0x999FF9u; // M
        case 78: return 0x999BD9u; // N
        case 79: return 0x699996u; // O
        case 80: return 0x888E9Eu; // P
        case 81: return 0x7B9996u; // Q
        case 82: return 0x99AE9Eu; // R
        case 83: return 0xE11687u; // S
        case 84: return 0x22222Fu; // T
        case 85: return 0x699999u; // U
        case 86: return 0x669999u; // V
        case 87: return 0x6FF999u; // W
        case 88: return 0x996699u; // X
        case 89: return 0x222699u; // Y
        case 90: return 0xF8421Fu; // Z
        case 91: return 0x644446u; // [
        case 92: return 0x112244u; // backslash
        case 93: return 0x622226u; // ]
        case 95: return 0xF00000u; // _
        default: return 0u;
    }
}

float glyphPixel(vec2 p, vec2 origin, int code, float scale) {
    ivec2 cell = ivec2(floor((p - origin) / scale));
    if (cell.x < 0 || cell.x >= 4 || cell.y < 0 || cell.y >= 6) {
        return 0.0;
    }
    uint bitIndex = uint(cell.y * 4 + (3 - cell.x));
    return float((glyphBits(code) >> bitIndex) & 1u);
}

int hexCode(uint value) {
    return value < 10u ? int(48u + value) : int(55u + value);
}

int keyboardGlyph(uint selection) {
    const int keys[50] = int[50](
        49, 50, 51, 52, 53, 54, 55, 56, 57, 48,
        81, 87, 69, 82, 84, 89, 85, 73, 79, 80,
        65, 83, 68, 70, 71, 72, 74, 75, 76, 47,
        90, 88, 67, 86, 66, 78, 77, 46, 45, 95,
        95, 60, 69, 67, 61, 58, 59, 39, 63, 92
    );
    return keys[min(selection, 49u)];
}

float drawHex(vec2 p, vec2 origin, uint value, float scale) {
    float ink = 0.0;
    for (int index = 0; index < 8; ++index) {
        uint shift = uint((7 - index) * 4);
        uint digit = (value >> shift) & 0xfu;
        vec2 glyphOrigin = origin + vec2(float(index) * 5.0 * scale, 0.0);
        ink = max(ink, glyphPixel(p, glyphOrigin, hexCode(digit), scale));
    }
    return ink;
}

float drawTitle(vec2 p, vec2 origin, float scale) {
    float ink = 0.0;
    for (int index = 0; index < 7; ++index) {
        int code = index == 0 ? 77  // M
                 : index == 1 ? 67  // C
                 : index == 2 ? 82  // R
                 : index == 3 ? 86  // V
                 : index == 4 ? 51  // 3
                 : index == 5 ? 50  // 2
                 : 65;              // A
        vec2 glyphOrigin = origin + vec2(float(index) * 5.0 * scale, 0.0);
        ink = max(ink, glyphPixel(p, glyphOrigin, code, scale));
    }
    return ink;
}

float drawRegisterLabel(vec2 p, vec2 origin, int registerIndex) {
    int tens = registerIndex / 10;
    int ones = registerIndex - tens * 10;
    float ink = glyphPixel(p, origin, 88, 1.0);
    ink = max(ink, glyphPixel(p, origin + vec2(5.0, 0.0), 48 + tens, 1.0));
    ink = max(ink, glyphPixel(p, origin + vec2(10.0, 0.0), 48 + ones, 1.0));
    return ink;
}

vec3 framebufferColour(uint value) {
    if (value == 0u) {
        return vec3(0.012, 0.020, 0.030);
    }
    float phase = float(value) * 0.075;
    return 0.52 + 0.48 * cos(vec3(phase, phase + 2.1, phase + 4.2));
}

vec3 terminalPalette(uint packedCell, vec3 defaultColour) {
    uint style = (packedCell >> 8u) & 0x11fu;
    uint encodedColour = style & 0x1fu;
    if (encodedColour == 0u) return defaultColour;
    uint paletteIndex = encodedColour - 1u;
    if ((style & 0x100u) != 0u && paletteIndex < 8u) paletteIndex += 8u;
    const vec3 colours[16] = vec3[16](
        vec3(0.10, 0.13, 0.16), vec3(0.72, 0.20, 0.22),
        vec3(0.24, 0.70, 0.30), vec3(0.78, 0.68, 0.20),
        vec3(0.28, 0.46, 0.78), vec3(0.70, 0.28, 0.72),
        vec3(0.24, 0.70, 0.72), vec3(0.72, 0.78, 0.82),
        vec3(0.34, 0.40, 0.46), vec3(1.00, 0.34, 0.36),
        vec3(0.38, 1.00, 0.46), vec3(1.00, 0.90, 0.34),
        vec3(0.42, 0.66, 1.00), vec3(1.00, 0.42, 1.00),
        vec3(0.40, 1.00, 1.00), vec3(0.96, 0.98, 1.00)
    );
    return colours[min(paletteIndex, 15u)];
}

void main() {
    vec3 scene = texture(SceneSampler, texCoord).rgb;
    float scale = max(floor(min(OutSize.x / 320.0, OutSize.y / 180.0)), 1.0);
    vec2 dashboardSize = vec2(320.0, 180.0) * scale;
    vec2 dashboardOrigin = floor((OutSize - dashboardSize) * 0.5);
    vec2 localPixel = texCoord * OutSize - dashboardOrigin;

    bool inside = localPixel.x >= 0.0 && localPixel.y >= 0.0
               && localPixel.x < dashboardSize.x && localPixel.y < dashboardSize.y;
    if (!inside) {
        fragColor = vec4(scene, 1.0);
        return;
    }

    // Virtual dashboard coordinates use a top-left origin and a 320x180 canvas.
    vec2 p = vec2(localPixel.x, dashboardSize.y - localPixel.y) / scale;
    vec3 colour = scene * vec3(0.035, 0.055, 0.075) + vec3(0.006, 0.010, 0.016);
    vec3 textColour = vec3(0.30, 0.96, 1.00);
    vec3 valueColour = vec3(0.72, 0.84, 0.92);

    float border = min(min(p.x, 320.0 - p.x), min(p.y, 180.0 - p.y));
    colour += vec3(0.02, 0.16, 0.20) * (1.0 - smoothstep(0.0, 2.0, border));

    bool linuxView = readRamWord(0u) == 0x00050433u
                  && readRamWord(1u) == 0x000584b3u;

    // The demo view displays the memory-mapped 32x18 framebuffer at 0x1000.
    vec2 framebufferOrigin = vec2(116.0, 24.0);
    vec2 framebufferExtent = vec2(192.0, 108.0);
    vec2 framebufferPixel = p - framebufferOrigin;
    bool inFramebuffer = framebufferPixel.x >= 0.0 && framebufferPixel.y >= 0.0
                      && framebufferPixel.x < framebufferExtent.x
                      && framebufferPixel.y < framebufferExtent.y;
    if (inFramebuffer && !linuxView) {
        ivec2 cell = ivec2(floor(framebufferPixel / 6.0));
        uint index = FRAMEBUFFER_BASE + uint(cell.y * FRAMEBUFFER_SIZE.x + cell.x);
        vec3 pixelColour = framebufferColour(readRamWord(index));
        vec2 withinCell = fract(framebufferPixel / 6.0);
        float cellEdge = min(min(withinCell.x, 1.0 - withinCell.x),
                             min(withinCell.y, 1.0 - withinCell.y));
        pixelColour *= mix(0.72, 1.0, smoothstep(0.0, 0.12, cellEdge));
        colour = pixelColour;
    }

    // Linux uses the right panel as a UART terminal and on-screen keyboard.
    vec2 uartPanelOrigin = linuxView ? vec2(116.0, 16.0) : vec2(116.0, 134.0);
    vec2 uartPanelPixel = p - uartPanelOrigin;
    if (uartPanelPixel.x >= 0.0 && uartPanelPixel.x < 192.0
            && uartPanelPixel.y >= 0.0
            && uartPanelPixel.y < (linuxView ? 144.0 : 26.0)) {
        colour = mix(colour, vec3(0.008, 0.025, 0.034), 0.88);
    }
    float uartLabelInk = 0.0;
    vec2 uartLabelOrigin = linuxView ? vec2(118.0, 18.0) : vec2(118.0, 136.0);
    uartLabelInk = max(uartLabelInk, glyphPixel(p, uartLabelOrigin, 84, 1.0));
    uartLabelInk = max(uartLabelInk,
        glyphPixel(p, uartLabelOrigin + vec2(5.0, 0.0), 88, 1.0));
    colour = mix(colour, textColour * 0.88, uartLabelInk);

    uint uartHead = readStateWord(UART_TX_HEAD_INDEX);
    uint uartDisplayEnd = linuxView ? (uartHead + 31u) & ~31u : uartHead;
    uint uartDisplayBytes = linuxView ? UART_TERMINAL_BYTES : 96u;
    uint uartCount = min(uartDisplayEnd, uartDisplayBytes);
    uint uartStart = uartDisplayEnd - uartCount;
    float uartInk = 0.0;
    vec3 uartColour = valueColour;
    vec2 uartTextOrigin = linuxView ? vec2(143.0, 18.0) : vec2(143.0, 136.0);
    float uartRowStride = linuxView ? 7.0 : 8.0;
    vec2 uartTextPixel = p - uartTextOrigin;
    int uartRows = linuxView ? 14 : 3;
    bool inUartText = uartTextPixel.x >= 0.0 && uartTextPixel.x < 160.0
                   && uartTextPixel.y >= 0.0
                   && uartTextPixel.y < float(uartRows) * uartRowStride;
    if (inUartText) {
        int column = int(floor(uartTextPixel.x / 5.0));
        int row = int(floor(uartTextPixel.y / uartRowStride));
        uint index = uint(row * 32 + column);
        uint packedCell = 0u;
        bool populated = false;
        if (linuxView) {
            if (index < TERMINAL_CELL_COUNT) {
                packedCell = readStateWord(TERMINAL_CELL_BASE + index);
                populated = (packedCell & 0xffu) != 0u;
                uartColour = terminalPalette(packedCell, valueColour);
            }
        } else {
            populated = index < uartCount;
        }
        if (populated) {
            int code = 0;
            if (linuxView) {
                code = int(packedCell & 0xffu);
            } else {
                uint absoluteIndex = uartStart + index;
                uint bufferOffset = absoluteIndex % UART_TX_BUFFER_BYTES;
                code = int(readByte(UART_TX_BUFFER_OFFSET + bufferOffset));
            }
            uartInk = glyphPixel(
                p,
                uartTextOrigin + vec2(float(column) * 5.0,
                                      float(row) * uartRowStride),
                code,
                1.0
            );
        }
    }
    colour = mix(colour, uartColour, uartInk);

    if (linuxView) {
        vec2 keyboardOrigin = vec2(143.0, 120.0);
        vec2 keyboardPixel = p - keyboardOrigin;
        bool inKeyboard = keyboardPixel.x >= 0.0 && keyboardPixel.x < 160.0
                       && keyboardPixel.y >= 0.0 && keyboardPixel.y < 40.0;
        if (inKeyboard) {
            ivec2 keyCell = ivec2(floor(keyboardPixel / vec2(16.0, 8.0)));
            uint keyIndex = uint(keyCell.y * 10 + keyCell.x);
            vec2 withinKey = fract(keyboardPixel / vec2(16.0, 8.0));
            float keyEdge = min(min(withinKey.x, 1.0 - withinKey.x),
                                min(withinKey.y, 1.0 - withinKey.y));
            bool selected = keyIndex == readStateWord(KEYBOARD_SELECTION_INDEX);
            vec3 keyBackground = selected
                ? vec3(0.08, 0.52, 0.64)
                : vec3(0.012, 0.038, 0.052);
            colour = mix(colour, keyBackground,
                mix(0.48, 0.94, smoothstep(0.0, 0.10, keyEdge)));
            float keyInk = glyphPixel(
                p,
                keyboardOrigin + vec2(float(keyCell.x) * 16.0 + 6.0,
                                      float(keyCell.y) * 8.0 + 1.0),
                keyboardGlyph(keyIndex),
                1.0
            );
            colour = mix(colour, selected ? vec3(1.0) : valueColour, keyInk);
        }
        float keyboardLabel = glyphPixel(p, vec2(118.0, 121.0), 75, 1.0);
        keyboardLabel = max(keyboardLabel,
            glyphPixel(p, vec2(123.0, 121.0), 66, 1.0));
        colour = mix(colour, textColour * 0.88, keyboardLabel);
    }

    // The Linux memory strip samples every 4 KiB page in a 512 KiB window.
    vec2 memoryOrigin = vec2(116.0, 164.0);
    vec2 memoryPixel = p - memoryOrigin;
    if (memoryPixel.x >= 0.0 && memoryPixel.x < 192.0
            && memoryPixel.y >= 0.0 && memoryPixel.y < 6.0) {
        ivec2 cell = ivec2(floor(memoryPixel / 3.0));
        uint sampleIndex = uint(cell.y * 64 + cell.x);
        uint page = readStateWord(RAM_PAGE_INDEX) % RAM_PAGE_COUNT;
        uint index = linuxView
            ? min(page * RAM_PAGE_WORDS
                  + sampleIndex * RAM_SAMPLE_WORD_STRIDE, RAM_WORDS - 1u)
            : sampleIndex;
        uint value = readRamWord(index);
        vec3 heat = vec3(
            float(value & 0xffu),
            float((value >> 8u) & 0xffu),
            float((value >> 16u) & 0xffu)
        ) / 255.0;
        colour = mix(vec3(0.012, 0.020, 0.030), heat + vec3(0.02, 0.04, 0.05), 0.86);
    }

    float titleInk = drawTitle(p, vec2(10.0, 9.0), 2.0);
    colour = mix(colour, textColour, titleInk);

    // PC, cycle, and status labels occupy the top of the register panel.
    float labelInk = 0.0;
    labelInk = max(labelInk, glyphPixel(p, vec2(10.0, 28.0), 80, 1.0));
    labelInk = max(labelInk, glyphPixel(p, vec2(15.0, 28.0), 67, 1.0));
    labelInk = max(labelInk, glyphPixel(p, vec2(10.0, 39.0), 67, 1.0));
    labelInk = max(labelInk, glyphPixel(p, vec2(15.0, 39.0), 89, 1.0));
    labelInk = max(labelInk, glyphPixel(p, vec2(10.0, 50.0), 83, 1.0));
    labelInk = max(labelInk, glyphPixel(p, vec2(15.0, 50.0), 84, 1.0));
    colour = mix(colour, textColour, labelInk);

    float valueInk = 0.0;
    valueInk = max(valueInk, drawHex(p, vec2(25.0, 28.0), readStateWord(PC_INDEX), 1.0));
    valueInk = max(valueInk, drawHex(p, vec2(25.0, 39.0), readStateWord(CYCLE_INDEX), 1.0));
    valueInk = max(valueInk, drawHex(p, vec2(25.0, 50.0), readStateWord(STATUS_INDEX), 1.0));

    for (int row = 0; row < 5; ++row) {
        int registerIndex = row + 1;
        float y = 68.0 + float(row) * 13.0;
        float registerLabel = drawRegisterLabel(p, vec2(10.0, y), registerIndex);
        colour = mix(colour, textColour * 0.88, registerLabel);
        valueInk = max(valueInk, drawHex(p, vec2(29.0, y),
                                         readStateWord(REGISTER_BASE + uint(registerIndex)), 1.0));
    }

    const int trapLabelFirst[3] = int[3](77, 77, 77);
    const int trapLabelSecond[3] = int[3](67, 69, 84);
    const uint trapStateIndex[3] = uint[3](
        CSR_MCAUSE_INDEX, CSR_MEPC_INDEX, CSR_MTVAL_INDEX);
    for (int row = 0; row < 3; ++row) {
        float y = 133.0 + float(row) * 13.0;
        float trapLabel = glyphPixel(p, vec2(10.0, y), trapLabelFirst[row], 1.0);
        trapLabel = max(trapLabel,
            glyphPixel(p, vec2(15.0, y), trapLabelSecond[row], 1.0));
        colour = mix(colour, textColour * 0.88, trapLabel);
        valueInk = max(valueInk,
            drawHex(p, vec2(29.0, y), readStateWord(trapStateIndex[row]), 1.0));
    }
    if (linuxView) {
        float ramPageLabel = glyphPixel(p, vec2(10.0, 170.0), 82, 1.0);
        ramPageLabel = max(ramPageLabel,
            glyphPixel(p, vec2(15.0, 170.0), 80, 1.0));
        colour = mix(colour, textColour * 0.88, ramPageLabel);
        valueInk = max(valueInk,
            drawHex(p, vec2(29.0, 170.0),
                    readStateWord(RAM_PAGE_INDEX) % RAM_PAGE_COUNT, 1.0));
    }
    colour = mix(colour, valueColour, valueInk);

    uint status = readStateWord(STATUS_INDEX);
    vec3 statusColour = status == 0u ? vec3(0.18, 1.0, 0.48)
                      : status == 1u ? vec3(1.0, 0.78, 0.16)
                      : vec3(1.0, 0.18, 0.30);
    float statusLamp = 1.0 - smoothstep(3.0, 4.5, length(p - vec2(103.0, 53.0)));
    colour = mix(colour, statusColour, statusLamp);
    colour += statusColour * statusLamp * 0.22;

    fragColor = vec4(colour, 1.0);
}
