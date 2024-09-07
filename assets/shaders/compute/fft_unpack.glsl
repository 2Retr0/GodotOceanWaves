#[compute]
#version 460
/** 
 * Unpacks the IFFT outputs from the modulation stage and creates
 * the output displacement and normal maps.
 */

#define TILE_SIZE   (16U)
#define NUM_SPECTRA (4U)

layout(local_size_x = TILE_SIZE, local_size_y = TILE_SIZE, local_size_z = 2) in;

layout(rgba16f, set = 0, binding = 0) restrict writeonly uniform image2DArray displacement_map;
layout(rgba16f, set = 0, binding = 1) restrict uniform image2DArray normal_map;

layout(std430, set = 1, binding = 0) restrict buffer FFTBuffer {
	vec2 data[]; // map_size x map_size x num_spectra x 2 * num_cascades
};

layout(push_constant) restrict readonly uniform PushConstants {
	uint cascade_index;
	float whitecap;
	float foam_grow_rate;
	float foam_decay_rate;
};

// Tiling doesn't provide much of a benefit here (but it does a *little*)
shared vec2 tile[NUM_SPECTRA][TILE_SIZE][TILE_SIZE];

// Note: There is an assumption that the FFT does not transpose a second time. Thus,
//       we access the FFT buffer at an offset of NUM_LAYERS*map_size*map_size
#define FFT_DATA(id, layer) (data[(id.z)*map_size*map_size*NUM_SPECTRA*2 + NUM_SPECTRA*map_size*map_size + (layer)*map_size*map_size + (id).y*map_size + (id).x])
void main() {
	const uint map_size = gl_NumWorkGroups.x * gl_WorkGroupSize.x;
	const uvec3 id_local = gl_LocalInvocationID;
	const ivec3 id = ivec3(gl_GlobalInvocationID.xy, cascade_index);
	// Multiplying output of inverse FFT by below factor is equivalent to ifftshift()
	const float sign_shift = -2*((id.x & 1) ^ (id.y & 1)) + 1; // Equivalent: (-1^id.x)(-1^id.y)

	tile[id_local.z*2][id_local.y][id_local.x] = FFT_DATA(id, id_local.z*2);
	tile[id_local.z*2 + 1][id_local.y][id_local.x] = FFT_DATA(id, id_local.z*2 + 1);
	barrier();

	// Half of all threads writes to displacement map while other half writes to normal map.
	switch (id_local.z) {
		case 0:
			float hx = tile[0][id_local.y][id_local.x].x;
			float hy = tile[0][id_local.y][id_local.x].y;
			float hz = tile[1][id_local.y][id_local.x].x;
			imageStore(displacement_map, id, vec4(hx, hy, hz, 0) * sign_shift);
			break;
		case 1:
			float dhy_dx = tile[1][id_local.y][id_local.x].y * sign_shift;
			float dhy_dz = tile[2][id_local.y][id_local.x].x * sign_shift;
			float dhx_dx = tile[2][id_local.y][id_local.x].y * sign_shift;
			float dhz_dz = tile[3][id_local.y][id_local.x].x * sign_shift;
			float dhz_dx = tile[3][id_local.y][id_local.x].y * sign_shift;

			float jacobian = (1.0 + dhx_dx) * (1.0 + dhz_dz) - dhz_dx*dhz_dx;
			float foam_factor = -min(0, jacobian - whitecap);
			float foam = imageLoad(normal_map, id).a;
			foam *= exp(-foam_decay_rate);
			foam += foam_factor * foam_grow_rate;
			foam = clamp(foam, 0.0, 1.0);

			vec2 gradient = vec2(dhy_dx, dhy_dz) / (1.0 + abs(vec2(dhx_dx, dhz_dz)));
			imageStore(normal_map, id, vec4(gradient, dhx_dx, foam));
			break;
	}
}