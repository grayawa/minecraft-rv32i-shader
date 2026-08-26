#version 330
#extension GL_ARB_separate_shader_objects : require

uniform sampler2D SceneSampler;
uniform sampler2D StateSampler;

layout(location = 0) in vec2 texCoord;

layout(std140) uniform SamplerInfo {
    vec2 OutSize;
    vec2 SceneSize;
    vec2 StateSize;
};

layout(location = 0) out vec4 fragColor;

const uint TEXTURE_WIDTH = 128u;
const uint REGISTER_BASE = 16348u;
const uint STATUS_INDEX = 16380u;
const uint CYCLE_INDEX = 16381u;
const uint PC_INDEX = 16382u;
const uint FRAMEBUFFER_BASE = 1024u;
const ivec2 FRAMEBUFFER_SIZE = ivec2(32, 18);

ivec2 wordCoordinate(uint index) {
    return ivec2(int(index % TEXTURE_WIDTH), int(index / TEXTURE_WIDTH));
}

uint decodeWord(vec4 encoded) {
    uvec4 bytes = uvec4(floor(encoded * 255.0 + 0.5));
    return bytes.r | (bytes.g << 8u) | (bytes.b << 16u) | (bytes.a << 24u);
}

uint readWord(uint index) {
    return decodeWord(texelFetch(StateSampler, wordCoordinate(index), 0));
}

uint glyphBits(int code) {
    switch (code) {
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
        case 65: return 0x99F996u; // A
        case 66: return 0xE99E9Eu; // B
        case 67: return 0x788887u; // C
        case 68: return 0xE9999Eu; // D
        case 69: return 0xF88E8Fu; // E
        case 70: return 0x888E8Fu; // F
        case 73: return 0xF2222Fu; // I
        case 77: return 0x999FF9u; // M
        case 80: return 0x888E9Eu; // P
        case 82: return 0x99AE9Eu; // R
        case 83: return 0xE11687u; // S
        case 84: return 0x22222Fu; // T
        case 86: return 0x669999u; // V
        case 88: return 0x996699u; // X
        case 89: return 0x222699u; // Y
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

    float border = min(min(p.x, 320.0 - p.x), min(p.y, 180.0 - p.y));
    colour += vec3(0.02, 0.16, 0.20) * (1.0 - smoothstep(0.0, 2.0, border));

    // The right panel displays the memory-mapped 32x18 framebuffer at 0x1000.
    vec2 framebufferOrigin = vec2(116.0, 24.0);
    vec2 framebufferExtent = vec2(192.0, 108.0);
    vec2 framebufferPixel = p - framebufferOrigin;
    bool inFramebuffer = framebufferPixel.x >= 0.0 && framebufferPixel.y >= 0.0
                      && framebufferPixel.x < framebufferExtent.x
                      && framebufferPixel.y < framebufferExtent.y;
    if (inFramebuffer) {
        ivec2 cell = ivec2(floor(framebufferPixel / 6.0));
        uint index = FRAMEBUFFER_BASE + uint(cell.y * FRAMEBUFFER_SIZE.x + cell.x);
        vec3 pixelColour = framebufferColour(readWord(index));
        vec2 withinCell = fract(framebufferPixel / 6.0);
        float cellEdge = min(min(withinCell.x, 1.0 - withinCell.x),
                             min(withinCell.y, 1.0 - withinCell.y));
        pixelColour *= mix(0.72, 1.0, smoothstep(0.0, 0.12, cellEdge));
        colour = pixelColour;
    }

    // A compact memory activity strip visualizes the first 384 RAM words.
    vec2 memoryOrigin = vec2(116.0, 143.0);
    vec2 memoryPixel = p - memoryOrigin;
    if (memoryPixel.x >= 0.0 && memoryPixel.x < 192.0
            && memoryPixel.y >= 0.0 && memoryPixel.y < 24.0) {
        ivec2 cell = ivec2(floor(memoryPixel / 3.0));
        uint index = uint(cell.y * 64 + cell.x);
        uint value = readWord(index);
        vec3 heat = vec3(
            float(value & 0xffu),
            float((value >> 8u) & 0xffu),
            float((value >> 16u) & 0xffu)
        ) / 255.0;
        colour = mix(vec3(0.012, 0.020, 0.030), heat + vec3(0.02, 0.04, 0.05), 0.86);
    }

    vec3 textColour = vec3(0.30, 0.96, 1.00);
    vec3 valueColour = vec3(0.72, 0.84, 0.92);
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
    valueInk = max(valueInk, drawHex(p, vec2(25.0, 28.0), readWord(PC_INDEX), 1.0));
    valueInk = max(valueInk, drawHex(p, vec2(25.0, 39.0), readWord(CYCLE_INDEX), 1.0));
    valueInk = max(valueInk, drawHex(p, vec2(25.0, 50.0), readWord(STATUS_INDEX), 1.0));

    for (int row = 0; row < 8; ++row) {
        int registerIndex = row + 1;
        float y = 68.0 + float(row) * 13.0;
        float registerLabel = drawRegisterLabel(p, vec2(10.0, y), registerIndex);
        colour = mix(colour, textColour * 0.88, registerLabel);
        valueInk = max(valueInk, drawHex(p, vec2(29.0, y),
                                         readWord(REGISTER_BASE + uint(registerIndex)), 1.0));
    }
    colour = mix(colour, valueColour, valueInk);

    uint status = readWord(STATUS_INDEX);
    vec3 statusColour = status == 0u ? vec3(0.18, 1.0, 0.48)
                      : status == 1u ? vec3(1.0, 0.78, 0.16)
                      : vec3(1.0, 0.18, 0.30);
    float statusLamp = 1.0 - smoothstep(3.0, 4.5, length(p - vec2(103.0, 53.0)));
    colour = mix(colour, statusColour, statusLamp);
    colour += statusColour * statusLamp * 0.22;

    fragColor = vec4(colour, 1.0);
}
