#version 330
#extension GL_ARB_separate_shader_objects : require

uniform sampler2D SceneSampler;

layout(location = 0) in vec2 texCoord;

layout(std140) uniform SamplerInfo {
    vec2 OutSize;
    vec2 SceneSize;
};

layout(location = 0) out vec4 fragColor;

vec3 markerColour(int code) {
    return vec3(250.0, float(16 + code * 14), 246.0) / 255.0;
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
    float bestDistance = 1.0;
    uint marker = 0u;
    int x = clamp(int(SceneSize.x * 0.5), 0, int(SceneSize.x) - 1);
    for (int sampleIndex = 0; sampleIndex < 256; ++sampleIndex) {
        int y = clamp(
            int((float(sampleIndex) + 0.5) * SceneSize.y / 256.0),
            0,
            int(SceneSize.y) - 1
        );
        int secondY = min(y + max(int(SceneSize.y / 512.0), 1),
                          int(SceneSize.y) - 1);
        vec3 first = texelFetch(SceneSampler, ivec2(x, y), 0).rgb;
        vec3 second = texelFetch(SceneSampler, ivec2(x, secondY), 0).rgb;
        for (int code = 0; code < 16; ++code) {
            vec3 expected = markerColour(code);
            float distanceValue = max(
                max(length(first - expected), length(second - expected)),
                length(first - second) * 2.0
            );
            if (distanceValue < bestDistance) {
                bestDistance = distanceValue;
                marker = uint(code + 1);
            }
        }
    }
    fragColor = encodeWord(bestDistance < 0.08 ? marker : 0u);
}
