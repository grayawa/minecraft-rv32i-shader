#version 330
#extension GL_ARB_separate_shader_objects : require

uniform sampler2D RamSampler;
uniform sampler2D StateSampler;
uniform sampler2D GuestImageSampler;
uniform sampler2D MtdImageSampler;

layout(location = 0) in vec2 texCoord;

layout(std140) uniform SamplerInfo {
    vec2 OutSize;
    vec2 RamSize;
    vec2 StateSize;
    vec2 GuestImageSize;
    vec2 MtdImageSize;
};

layout(location = 0) out vec4 fragColor;

const uint STATE_TEXTURE_WIDTH = 128u;
const uint RAM_TEXTURE_WIDTH = 4096u;
const uint RAM_TEXTURE_WORDS = 3145728u;
const uint RAM_MAGIC_INDEX = RAM_TEXTURE_WORDS - 1u;
const uint RAM_WORDS = RAM_TEXTURE_WORDS - 1024u;
const uint RAM_MAGIC_VALUE = 0x52414d31u;
const uint GUEST_TEXTURE_WIDTH = 2048u;
const uint GUEST_TEXTURE_WORDS = 2097152u;
const uint GUEST_DTB_INDEX = GUEST_TEXTURE_WORDS - 4u;
const uint GUEST_LOAD_INDEX = GUEST_TEXTURE_WORDS - 2u;
const uint GUEST_MAGIC_INDEX = GUEST_TEXTURE_WORDS - 1u;
const uint GUEST_MAGIC_VALUE = 0x4d435256u;
const uint MTD_TEXTURE_WIDTH = 4096u;
const uint MTD_TEXTURE_WORDS = 14118912u;
const uint MTD_BASE_ADDRESS = 0x40000000u;
const uint MTD_BYTES = MTD_TEXTURE_WORDS * 4u;
const uint CACHE_TAG_BASE = 4096u;
const uint CACHE_VALUE_BASE = 4352u;
const uint CACHE_VALID_BASE = 4608u;
const uint CACHE_SETS = 64u;
const uint CACHE_WAYS = 4u;
const uint MEMOP_PENDING_INDEX = 4865u;
const uint MEMOP_SOURCE_PHYSICAL_INDEX = 4866u;
const uint MEMOP_DESTINATION_PHYSICAL_INDEX = 4867u;
const uint MEMOP_BYTE_COUNT_INDEX = 4868u;

ivec2 stateWordCoordinate(uint index) {
    return ivec2(int(index % STATE_TEXTURE_WIDTH), int(index / STATE_TEXTURE_WIDTH));
}

ivec2 ramWordCoordinate(uint index) {
    return ivec2(int(index % RAM_TEXTURE_WIDTH), int(index / RAM_TEXTURE_WIDTH));
}

ivec2 guestWordCoordinate(uint index) {
    return ivec2(int(index % GUEST_TEXTURE_WIDTH), int(index / GUEST_TEXTURE_WIDTH));
}

ivec2 mtdWordCoordinate(uint index) {
    return ivec2(int(index % MTD_TEXTURE_WIDTH), int(index / MTD_TEXTURE_WIDTH));
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
    return decodeWord(texelFetch(GuestImageSampler, guestWordCoordinate(index), 0));
}

uint readMtdWord(uint index) {
    return decodeWord(texelFetch(MtdImageSampler, mtdWordCoordinate(index), 0));
}

uint readCachedRamWord(uint wordIndex) {
    uint wordAddress = wordIndex << 2u;
    uint cacheSet = (wordIndex ^ (wordIndex >> 7u) ^ (wordIndex >> 13u))
        & (CACHE_SETS - 1u);
    for (uint way = 0u; way < CACHE_WAYS; ++way) {
        uint slot = cacheSet * CACHE_WAYS + way;
        if (readStateWord(CACHE_VALID_BASE + slot) != 0u
                && readStateWord(CACHE_TAG_BASE + slot) == wordAddress) {
            return readStateWord(CACHE_VALUE_BASE + slot);
        }
    }
    return readRamWord(wordIndex);
}

uint readPhysicalWord(uint address, uint loadAddress, uint ramBytes) {
    if (address >= loadAddress && address - loadAddress <= ramBytes - 4u) {
        return readCachedRamWord((address - loadAddress) >> 2u);
    }
    if (address >= MTD_BASE_ADDRESS
            && address - MTD_BASE_ADDRESS <= MTD_BYTES - 4u) {
        return readMtdWord((address - MTD_BASE_ADDRESS) >> 2u);
    }
    return 0u;
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
    uint ramBytes = RAM_WORDS * 4u;

    uint cacheSet = (outputIndex ^ (outputIndex >> 7u) ^ (outputIndex >> 13u))
        & (CACHE_SETS - 1u);
    uint outputAddress = outputIndex << 2u;
    for (uint way = 0u; way < CACHE_WAYS; ++way) {
        uint slot = cacheSet * CACHE_WAYS + way;
        if (readStateWord(CACHE_VALID_BASE + slot) != 0u
                && readStateWord(CACHE_TAG_BASE + slot) == outputAddress) {
            outputWord = readStateWord(CACHE_VALUE_BASE + slot);
        }
    }

    if (readStateWord(MEMOP_PENDING_INDEX) != 0u) {
        uint sourceAddress = readStateWord(MEMOP_SOURCE_PHYSICAL_INDEX);
        uint destinationAddress = readStateWord(MEMOP_DESTINATION_PHYSICAL_INDEX);
        uint byteCount = readStateWord(MEMOP_BYTE_COUNT_INDEX);
        uint physicalOutputAddress = loadAddress + outputAddress;
        if (byteCount > 0u && physicalOutputAddress >= destinationAddress
                && physicalOutputAddress - destinationAddress < byteCount) {
            uint sourceWordAddress = sourceAddress
                + (physicalOutputAddress - destinationAddress);
            outputWord = readPhysicalWord(sourceWordAddress, loadAddress, ramBytes);
        }
    }

    if (outputIndex == RAM_MAGIC_INDEX) outputWord = RAM_MAGIC_VALUE;
    fragColor = encodeWord(outputWord);
}
