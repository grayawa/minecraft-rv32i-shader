#version 330
#extension GL_ARB_separate_shader_objects : require

uniform sampler2D RamSampler;
uniform sampler2D StateSampler;
uniform sampler2D GuestImageSampler;

layout(location = 0) in vec2 texCoord;

layout(std140) uniform SamplerInfo {
    vec2 OutSize;
    vec2 RamSize;
    vec2 StateSize;
    vec2 GuestImageSize;
};

layout(location = 0) out vec4 fragColor;

const uint STATE_TEXTURE_WIDTH = 128u;
const uint RAM_TEXTURE_WIDTH = 1024u;
const uint RAM_TEXTURE_WORDS = 262144u;
const uint RAM_MAGIC_INDEX = RAM_TEXTURE_WORDS - 1u;
const uint RAM_MAGIC_VALUE = 0x52414d31u;
const uint GUEST_DTB_INDEX = RAM_TEXTURE_WORDS - 4u;
const uint GUEST_LOAD_INDEX = RAM_TEXTURE_WORDS - 2u;
const uint GUEST_MAGIC_INDEX = RAM_TEXTURE_WORDS - 1u;
const uint GUEST_MAGIC_VALUE = 0x4d435256u;
const uint CSR_BASE = 16316u;
const uint RAM_WRITE_VALID_INDEX = CSR_BASE + 16u;
const uint RAM_WRITE_ADDRESS_INDEX = CSR_BASE + 17u;
const uint RAM_WRITE_VALUE_INDEX = CSR_BASE + 18u;
const uint RAM_WRITE_WIDTH_INDEX = CSR_BASE + 19u;

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

vec4 encodeWord(uint word) {
    uvec4 bytes = uvec4(
        word & 0xffu,
        (word >> 8u) & 0xffu,
        (word >> 16u) & 0xffu,
        (word >> 24u) & 0xffu
    );
    return vec4(bytes) / 255.0;
}

uint readRamWord(uint index) {
    return decodeWord(texelFetch(RamSampler, ramWordCoordinate(index), 0));
}

uint readStateWord(uint index) {
    return decodeWord(texelFetch(StateSampler, stateWordCoordinate(index), 0));
}

uint readGuestWord(uint index) {
    return decodeWord(texelFetch(GuestImageSampler, ramWordCoordinate(index), 0));
}

void main() {
    uvec2 outputSize = uvec2(OutSize + 0.5);
    uvec2 pixel = min(uvec2(texCoord * OutSize), outputSize - uvec2(1u));
    uint outputIndex = pixel.y * RAM_TEXTURE_WIDTH + pixel.x;

    if (readRamWord(RAM_MAGIC_INDEX) != RAM_MAGIC_VALUE) {
        uint initialWord = outputIndex < GUEST_DTB_INDEX ? readGuestWord(outputIndex) : 0u;
        if (outputIndex == RAM_MAGIC_INDEX) initialWord = RAM_MAGIC_VALUE;
        fragColor = encodeWord(initialWord);
        return;
    }

    uint outputWord = readRamWord(outputIndex);
    bool descriptorPresent = readGuestWord(GUEST_MAGIC_INDEX) == GUEST_MAGIC_VALUE;
    uint loadAddress = descriptorPresent ? readGuestWord(GUEST_LOAD_INDEX) : 0u;
    bool writeValid = readStateWord(RAM_WRITE_VALID_INDEX) != 0u;
    uint writeAddress = readStateWord(RAM_WRITE_ADDRESS_INDEX);
    uint writeValue = readStateWord(RAM_WRITE_VALUE_INDEX);
    uint writeWidth = readStateWord(RAM_WRITE_WIDTH_INDEX);
    uint ramBytes = RAM_MAGIC_INDEX * 4u;
    bool writeInRange = writeValid && writeWidth > 0u && writeWidth <= ramBytes
        && writeAddress >= loadAddress && writeAddress - loadAddress <= ramBytes - writeWidth;

    if (writeInRange) {
        uint offset = writeAddress - loadAddress;
        if (outputIndex == (offset >> 2u)) {
            uint shift = (offset & 3u) * 8u;
            if (writeWidth == 1u) {
                uint mask = 0xffu << shift;
                outputWord = (outputWord & ~mask) | ((writeValue << shift) & mask);
            } else if (writeWidth == 2u) {
                uint mask = 0xffffu << shift;
                outputWord = (outputWord & ~mask) | ((writeValue << shift) & mask);
            } else if (writeWidth == 4u) {
                outputWord = writeValue;
            }
        }
    }

    if (outputIndex == RAM_MAGIC_INDEX) outputWord = RAM_MAGIC_VALUE;
    fragColor = encodeWord(outputWord);
}
