#[compute]
#version 460
/** 
 * A coalesced decimation-in-time Stockham FFT kernel. 
 * Source: http://wwwa.pikara.ne.jp/okojisan/otfft-en/stockham3.html
 */

#define PI           (3.141592653589793)
#define MAX_MAP_SIZE (1024U)
#define NUM_SPECTRA  (4U)

layout(local_size_x = MAX_MAP_SIZE, local_size_y = 1, local_size_z = 1) in;

layout(std430, set = 0, binding = 0) restrict readonly buffer ButterflyFactorBuffer {
	vec4 butterfly[]; // log2(map_size) x map_size
};

layout(std430, set = 0, binding = 1) restrict buffer FFTBuffer {
	vec2 data[]; // map_size x map_size x num_spectra x 2 * num_cascades
};

layout(push_constant) restrict readonly uniform PushConstants {
	uint cascade_index;
};

shared vec2 row_shared[2 * MAX_MAP_SIZE]; // "Ping-pong" shared buffer for a single row

/** Returns (a0 + j*a1)(b0 + j*b1) */
vec2 mul_complex(in vec2 a, in vec2 b) {
	return vec2(a.x*b.x - a.y*b.y, a.x*b.y + a.y*b.x);
}

#define ROW_SHARED(col, pingpong) (row_shared[(pingpong)*MAX_MAP_SIZE + (col)])
#define BUTTERFLY(col, stage)     (butterfly[(stage)*map_size + (col)])
#define DATA_IN(id, layer)  (data[(id.z)*map_size*map_size*NUM_SPECTRA*2 +                             0 + (layer)*map_size*map_size + (id.y)*map_size + (id.x)])
#define DATA_OUT(id, layer) (data[(id.z)*map_size*map_size*NUM_SPECTRA*2 + NUM_SPECTRA*map_size*map_size + (layer)*map_size*map_size + (id.y)*map_size + (id.x)])
void main() {
	const uint map_size = gl_NumWorkGroups.y * gl_WorkGroupSize.y;
	const uint num_stages = findMSB(map_size); // Equivalent: log2(map_size) (assuming map_size is a power of 2)
	const uvec3 id = uvec3(gl_GlobalInvocationID.xy, cascade_index); // col, row, cascade
	const uint col = id.x;
	const uint spectrum = gl_GlobalInvocationID.z; // The spectrum in the buffer to perform FFT on.
	
	if (gl_LocalInvocationID.x >= map_size) return;

	ROW_SHARED(col, 0) = DATA_IN(id, spectrum);
	for (uint stage = 0U; stage < num_stages; ++stage) {
		barrier();
		uvec2 buf_idx = uvec2(stage % 2, (stage + 1) % 2); // x=read index, y=write index
		vec4 butterfly_data = BUTTERFLY(col, stage);

		uvec2 read_indices = uvec2(floatBitsToUint(butterfly_data.xy));
		vec2 twiddle_factor = butterfly_data.zw;

		vec2 upper = ROW_SHARED(read_indices[0], buf_idx[0]);
		vec2 lower = ROW_SHARED(read_indices[1], buf_idx[0]);
		ROW_SHARED(col, buf_idx[1]) = upper + mul_complex(lower, twiddle_factor);
	}
	DATA_OUT(id, spectrum) = ROW_SHARED(col, num_stages % 2);
}