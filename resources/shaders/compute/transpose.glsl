#[compute]
#version 460
/** A memory-efficient coalesced matrix transpose kernel. 
 * Source: https://developer.nvidia.com/blog/efficient-matrix-transpose-cuda-cc/
 */

#define MAP_SIZE   (256U)
#define NUM_STAGES (8U) // log2(MAP_SIZE)
#define TILE_SIZE  (32)

layout(local_size_x = TILE_SIZE, local_size_y = TILE_SIZE, local_size_z = 1) in;

layout(rgba16f, binding = 0) restrict readonly uniform image2D spectrum;
layout(std430, binding = 1) restrict buffer FFTBuffer {
	vec4 butterfly[NUM_STAGES][MAP_SIZE];
	vec2 data[2][4][MAP_SIZE][MAP_SIZE];
} fft_buffer;
layout(rgba16f, binding = 2) restrict readonly uniform image2D displacement_map;
layout(rgba16f, binding = 3) restrict readonly uniform image2D normal_map;

shared vec2 tile[TILE_SIZE][TILE_SIZE+1];

void main() {
	const uvec2 id_block = gl_WorkGroupID.xy;
	const uvec2 id_local = gl_LocalInvocationID.xy;
	const uint spectrum = gl_GlobalInvocationID.z;

	uvec2 id = gl_GlobalInvocationID.xy;
	tile[id_local.y][id_local.x] = fft_buffer.data[1][spectrum][id.y][id.x];
	barrier();

	id = id_block.yx * TILE_SIZE + id_local.xy;
	fft_buffer.data[0][spectrum][id.y][id.x] = tile[id_local.x][id_local.y];
}