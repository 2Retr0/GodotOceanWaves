#[compute]
#version 460
/** 
 * A memory-efficient coalesced matrix transpose kernel. 
 * Source: https://developer.nvidia.com/blog/efficient-matrix-transpose-cuda-cc/
 */

#define TILE_SIZE   (32U)
#define NUM_SPECTRA (4U)

layout(local_size_x = TILE_SIZE, local_size_y = TILE_SIZE, local_size_z = 1) in;

layout(std430, set = 0, binding = 0) restrict readonly buffer ButterflyFactorBuffer {
	vec4 butterfly[]; // log2(map_size) x map_size
}; 

layout(std430, set = 0, binding = 1) restrict buffer FFTBuffer {
	vec2 data[]; // map_size x map_size x num_spectra x 2 * num_cascades
};

layout(push_constant) restrict readonly uniform PushConstants {
	uint cascade_index;
};

shared vec2 tile[TILE_SIZE][TILE_SIZE+1];

#define DATA_IN(id, layer)  (data[(id.z)*map_size*map_size*NUM_SPECTRA*2 + NUM_SPECTRA*map_size*map_size + (layer)*map_size*map_size + (id.y)*map_size + (id.x)])
#define DATA_OUT(id, layer) (data[(id.z)*map_size*map_size*NUM_SPECTRA*2 +                             0 + (layer)*map_size*map_size + (id.y)*map_size + (id.x)])
void main() {
	const uint map_size = gl_NumWorkGroups.x * gl_WorkGroupSize.x;
	const uvec2 id_block = gl_WorkGroupID.xy;
	const uvec2 id_local = gl_LocalInvocationID.xy;
	const uint spectrum = gl_GlobalInvocationID.z;

	uvec3 id = uvec3(gl_GlobalInvocationID.xy, cascade_index);
	tile[id_local.y][id_local.x] = DATA_IN(id, spectrum);
	barrier();

	id.xy = id_block.yx * TILE_SIZE + id_local.xy;
	DATA_OUT(id, spectrum) = tile[id_local.x][id_local.y];
}