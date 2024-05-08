#[compute]
#version 460
/** A coalesced Stockham FFT kernel. */

#define PI         (3.141592653589793)
#define TAU        (6.283185307179586)
#define MAP_SIZE   (256U)
#define NUM_STAGES (8U) // log2(MAP_SIZE)

layout(local_size_x = 256, local_size_y = 1, local_size_z = 1) in;

layout(std430, set = 0, binding = 0) restrict buffer FFTBuffer {
	vec4 butterfly[NUM_STAGES][MAP_SIZE];
	vec2 data[2][4][MAP_SIZE][MAP_SIZE];
} fft_buffer;

shared vec2 row_shared[2][MAP_SIZE]; // "Ping-pong" shared buffer for a single row

/** Returns (a0 + j*a1)(b0 + j*b1) */
vec2 mul_complex(in vec2 a, in vec2 b) {
	return vec2(a.x*b.x - a.y*b.y, a.x*b.y + a.y*b.x);
}

void main() {
	const uint row = gl_GlobalInvocationID.y;
	const uint col = gl_GlobalInvocationID.x;
	const uint spectrum = gl_GlobalInvocationID.z; // The spectrum in the buffer to perform FFT on.
	
	row_shared[0][col] = fft_buffer.data[0][spectrum][row][col];
	for (uint stage = 0U; stage < NUM_STAGES; ++stage) {
		barrier();
		uvec2 buf_idx = uvec2(stage % 2, (stage + 1) % 2); // x=read index, y=write index
		vec4 butterfly_data = fft_buffer.butterfly[stage][col];

		uvec2 read_indices = uvec2(floatBitsToUint(butterfly_data.xy));
		vec2 twiddle_factor = butterfly_data.zw;

		vec2 upper = row_shared[buf_idx[0]][read_indices[0]];
		vec2 lower = row_shared[buf_idx[0]][read_indices[1]];
		row_shared[buf_idx[1]][col] = upper + mul_complex(lower, twiddle_factor);
	}
	fft_buffer.data[1][spectrum][row][col] = row_shared[NUM_STAGES % 2][col];
}