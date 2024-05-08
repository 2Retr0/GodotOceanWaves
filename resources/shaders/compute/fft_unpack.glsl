#[compute]
#version 460
/** Unpacks the IFFT outputs from the modulation stage and creates
  * the output displacement and normal maps.
  */

#define MAP_SIZE   (256U)
#define NUM_STAGES (8U) // log2(MAP_SIZE)
#define TILE_SIZE  (16U)

layout(local_size_x = TILE_SIZE, local_size_y = TILE_SIZE, local_size_z = 2) in;

layout(std430, set = 0, binding = 0) restrict buffer FFTBuffer {
	vec4 butterfly[NUM_STAGES][MAP_SIZE];
	vec2 data[2][4][MAP_SIZE][MAP_SIZE];
} fft_buffer;

layout(rgba16f, set = 1, binding = 0) restrict writeonly uniform image2D displacement_map;
layout(rgba16f, set = 1, binding = 1) restrict uniform image2D normal_map;

// Tiling doesn't provide much of a benefit here (but it does a *little*)
shared vec2 tile[4][TILE_SIZE][TILE_SIZE];

void main() {
	const uvec3 id_local = gl_LocalInvocationID;
	const ivec2 id = ivec2(gl_GlobalInvocationID.xy);
	// Multiplying output of inverse FFT by below factor is equivalent to ifftshift()
	const float sign_shift = -2*((id.x & 1) ^ (id.y & 1)) + 1; // Equivalent: (-1^id.x)(-1^id.y)

	tile[id_local.z*2][id_local.y][id_local.x] = fft_buffer.data[1][id_local.z*2][id.y][id.x];
	tile[id_local.z*2 + 1][id_local.y][id_local.x] = fft_buffer.data[1][id_local.z*2 + 1][id.y][id.x];
	barrier();

	switch (id_local.z) {
		case 0:
			float hy = tile[0][id_local.y][id_local.x].x;
			float hx = tile[0][id_local.y][id_local.x].y;
			float hz = tile[1][id_local.y][id_local.x].x;
			imageStore(displacement_map, id, vec4(hx, hy, hz, 0) * sign_shift);
			return;
		case 1:
			float dhy_dx = tile[1][id_local.y][id_local.x].y * sign_shift;
			float dhy_dz = tile[2][id_local.y][id_local.x].x * sign_shift;
			float dhx_dx = tile[2][id_local.y][id_local.x].y * sign_shift;
			float dhz_dz = tile[3][id_local.y][id_local.x].x * sign_shift;
			float dhz_dx = tile[3][id_local.y][id_local.x].y * sign_shift;

			float foam_threshold = 0.0;
			float foam_bias = 0.5;
			float foam_decay = 0.05;
			float foam_add = 1.0;

			float jacobian = (1.0 + dhx_dx) * (1.0 + dhz_dz) - dhz_dx*dhz_dx;
			float biased_jacobian = -min(0, jacobian - foam_bias);
			float foam = imageLoad(normal_map, id).a;
			foam *= exp(-foam_decay);
			foam += biased_jacobian * foam_add;

			vec2 gradient = vec2(dhy_dx, dhy_dz) / (1.0 + abs(vec2(dhx_dx, dhz_dz)));
			imageStore(normal_map, id, vec4(gradient, dhx_dx, foam));
			return;
	}
}