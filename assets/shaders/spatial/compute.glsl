#[compute]
#version 450

layout(local_size_x = 16, local_size_y = 16) in;

layout(set = 0, binding = 0) uniform sampler2DArray displacementMap;
layout(set = 0, binding = 1, std430) buffer HeightBuffer {
    float heights[];
};

layout(push_constant, std430) uniform Params {
    vec2 samplePoint;
    float mapSize;
};

void main() {
    uvec2 id = gl_GlobalInvocationID.xy;
    if (id.x >= uint(mapSize) || id.y >= uint(mapSize)) {
        return;
    }

    vec2 uv = (vec2(id) + samplePoint) / mapSize;
    float height = texture(displacementMap, vec3(uv, 0.0)).r;
    heights[id.y * uint(mapSize) + id.x] = height;
}
