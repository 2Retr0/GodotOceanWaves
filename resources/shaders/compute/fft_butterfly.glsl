#[compute]
#version 460
/** Precomputes the butterfly factors for a Stockham FFT kernel */

#define PI         (3.141592653589793)
#define NUM_STAGES (8U) // log2(MAP_SIZE)
#define MAP_SIZE   (256U)

layout(local_size_x = 1, local_size_y = 64, local_size_z = 1) in;

layout(std430, set = 0, binding = 0) restrict writeonly buffer FFTBuffer {
	vec4 butterfly[NUM_STAGES][MAP_SIZE];
	float data[];
} fft_buffer;

/** Returns exp(j*x) assuming x >= 0. */
vec2 exp_complex(in float x) {
	return vec2(cos(x), sin(x));
}

void main() {
	const uint col = gl_GlobalInvocationID.y;   // Column in row
	const uint stage = gl_GlobalInvocationID.z; // Stage of FFT

	uint stride = 1 << stage, mid = 256 >> (stage + 1);
	uint i = col >> stage, j = col % stride;

	vec2 twiddle_factor = exp_complex(PI / float(stride) * float(j));
	uint r0 = stride*(i +   0) + j, r1 = stride*(i + mid) + j;
	uint w0 = stride*(2*i + 0) + j, w1 = stride*(2*i + 1) + j;

	vec2 read_indices = vec2(uintBitsToFloat(r0), uintBitsToFloat(r1));

	fft_buffer.butterfly[stage][w0] = vec4(read_indices,  twiddle_factor);
	fft_buffer.butterfly[stage][w1] = vec4(read_indices, -twiddle_factor);
}