#version 330
#extension GL_ARB_separate_shader_objects : require

uniform sampler2D StateSampler;

layout(location = 0) in vec2 texCoord;

layout(std140) uniform SamplerInfo {
    vec2 OutSize;
    vec2 StateSize;
};

layout(location = 0) out vec4 fragColor;

const uint STATE_TEXTURE_WIDTH = 128u;
const uint CACHE_VALID_BASE = 4608u;
const uint CACHE_SLOTS = 256u;
const uint CACHE_OVERFLOW_INDEX = 4864u;
const uint MEMOP_PENDING_INDEX = 4865u;

ivec2 stateWordCoordinate(uint index) {
    return ivec2(int(index % STATE_TEXTURE_WIDTH), int(index / STATE_TEXTURE_WIDTH));
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

void main() {
    uvec2 outputSize = uvec2(OutSize + 0.5);
    uvec2 pixel = min(uvec2(texCoord * OutSize), outputSize - uvec2(1u));
    uint outputIndex = pixel.y * STATE_TEXTURE_WIDTH + pixel.x;
    uint outputWord = decodeWord(texelFetch(
        StateSampler, stateWordCoordinate(outputIndex), 0));
    if ((outputIndex >= CACHE_VALID_BASE
            && outputIndex < CACHE_VALID_BASE + CACHE_SLOTS)
            || outputIndex == CACHE_OVERFLOW_INDEX
            || outputIndex == MEMOP_PENDING_INDEX) {
        outputWord = 0u;
    }
    fragColor = encodeWord(outputWord);
}
