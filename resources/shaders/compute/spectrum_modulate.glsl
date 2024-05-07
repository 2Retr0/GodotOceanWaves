#[compute]
#version 460

#define TAU        (6.283185307179586)
#define EPSILON    (1e-10)
#define G          (9.81)
#define MAP_SIZE   (256U)
#define NUM_STAGES (8U) // log2(MAP_SIZE)

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

layout(rgba16f, binding = 0) restrict readonly uniform image2D spectrum;
layout(std430, binding = 1) restrict writeonly buffer FFTBuffer {
	vec4 butterfly[NUM_STAGES][MAP_SIZE];
	vec2 data[2][4][MAP_SIZE][MAP_SIZE];
} fft_buffer;
layout(rgba16f, binding = 2) restrict readonly uniform image2D displacement_map;
layout(rgba16f, binding = 3) restrict readonly uniform image2D normal_map;

layout(push_constant) restrict readonly uniform PushConstants {
	vec2 tile_length;
	float time;
} params;

/** Returns exp(j*x) assuming x >= 0. */
vec2 exp_complex(in float x) {
	return vec2(cos(x), sin(x));
}

/** Returns (a0 + j*a1)(b0 + j*b1) */
vec2 mul_complex(in vec2 a, in vec2 b) {
	return vec2(a.x*b.x - a.y*b.y, a.x*b.y + a.y*b.x);
}

/** Returns the complex conjugate of x */
vec2 conj_complex(in vec2 x) {
	x.y *= -1;
	return x;
}

// Source: Simulating Ocean Water - Jerry Tessendorf
float dispertion_relation(in float k) {
	// Assumption: Depth is infinite
	return sqrt(G*k); // sqrt(g*k*tanh(k*depth))
}

void main() {
	const ivec2 dims = imageSize(spectrum);
	const ivec2 id = ivec2(gl_GlobalInvocationID.xy);

	vec2 k_vec = (id - dims*0.5)*(TAU / params.tile_length); // Wave direction
	float k = length(k_vec) + EPSILON;
	vec2 k_unit = k_vec / k;

	// --- WAVE SPECTRUM MODULATION ---
	vec4 h0 = imageLoad(spectrum, id); // xy=h0(k), zw=conj(h0(-k)

	vec2 modulation = exp_complex(dispertion_relation(k) * params.time);
	vec2 h = mul_complex(h0.xy, modulation) + mul_complex(h0.zw, conj_complex(modulation));
	vec2 h_inv = vec2(-h.y, h.x); // Used to simplify complex multiplication operations

	// --- WAVE DISPLACEMENT CALCULATION ---
	vec2 hx = h_inv * k_unit.x;            // Equivalent: mul_complex(vec2(0, -k_unit.x), h);
	vec2 hy = h;
	vec2 hz = h_inv * k_unit.y;            // Equivalent: mul_complex(vec2(0, -k_unit.z), h);

	// --- WAVE GRADIENT CALCULATION ---
	vec2 dhy_dx = h_inv * k_vec.x;         // Equivalent: mul_complex(vec2(0, k_vec.x), h);
	vec2 dhy_dz = h_inv * k_vec.y;         // Equivalent: mul_complex(vec2(0, k_vec.z), h);
	vec2 dhx_dx = -h * k_vec.x * k_unit.x; // Equivalent: mul_complex(vec2(k_vec.x * k_unit.x, 0), -h);
	vec2 dhz_dz = -h * k_vec.y * k_unit.y; // Equivalent: mul_complex(vec2(k_vec.y * k_unit.y, 0), -h);
	vec2 dhz_dx = -h * k_vec.x * k_unit.y; // Equivalent: mul_complex(vec2(k_vec.x * k_unit.y, 0), -h);

	fft_buffer.data[0][0][id.y][id.x] = vec2(    hx.x -     hy.y,     hx.y +     hy.x);	
	fft_buffer.data[0][1][id.y][id.x] = vec2(    hz.x - dhy_dx.y,     hz.y + dhy_dx.x);
	fft_buffer.data[0][2][id.y][id.x] = vec2(dhy_dz.x - dhx_dx.y, dhy_dz.y + dhx_dx.x);
	fft_buffer.data[0][3][id.y][id.x] = vec2(dhz_dz.x - dhz_dx.y, dhz_dz.y + dhz_dx.x);
}