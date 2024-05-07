#[compute]
#version 460

#define TAU        (6.283185307179586)
#define EPSILON    (1e-10)
#define PI_INV     (0.318309886183791)
#define G          (9.81)
#define MAP_SIZE   (256U)

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

layout(rgba16f, binding = 0) restrict writeonly uniform image2D spectrum;
layout(std430, binding = 1) restrict writeonly buffer FFTBuffer {
	float data[];
} fft_buffer;
layout(rgba16f, binding = 2) restrict readonly uniform image2D displacement_map;
layout(rgba16f, binding = 3) restrict readonly uniform image2D normal_map;

layout(push_constant) restrict readonly uniform PushConstants {
	vec2 tile_length;
	float alpha;
	float peak_frequency;
	float wind_speed;
} params;

// --- HELPER FUNCTIONS ---
// Source: https://www.shadertoy.com/view/Xt3cDn
vec2 hash(in uvec2 x) {
    x = 1103515245U * ((x >> 1U) ^ (x.yx));
    uint h32 = 1103515245U * ((x.x) ^ (x.y >> 3U));
	uint n = h32 ^ (h32 >> 16U);
    return vec2((uvec2(n, n*48271U).xy >> 1) & uvec2(0x7FFFFFFFU)) / float(0x7FFFFFFF);
}

/** Samples a 2D-bivariate normal distribution */
vec2 gaussian(in vec2 x) {
	vec2 h = hash(uvec2(x));
	// Use Box-Muller transform to convert uniform distribution->normal distribution.
	float r = sqrt(-2.0 * log(h.x));
	float theta = TAU * h.y;
	return vec2(r*cos(theta), r*sin(theta));
}

/** Approximate gamma function where s is in a range of 0..36. */
// Source: https://raw.githubusercontent.com/libretro/glsl-shaders/master/crt/shaders/crt-royale/port-helpers/special-functions.h
float gamma(in float s) {
	float g = 1.12906830989;
	float c0 = 0.8109119309638332633713423362694399653724431;
	float c1 = 0.4808354605142681877121661197951496120000040;
	float e = 2.71828182845904523536028747135266249775724709;

	float sph = s + 0.5;
	float lanczos_sum = c0 + c1/(s + 1.0);
	float base = (sph + g)/e;
	return (pow(base, sph) * lanczos_sum) / s;
}

/** Returns the complex conjugate of x */
vec2 conj_complex(in vec2 x) {
	x.y *= -1;
	return x;
}

// --- SPECTRUM-RELATED FUNCTIONS ---
// Source: Simulating Ocean Water - Jerry Tessendorf
float dispertion_relation(in float k) {
	// Assumption: Depth is infinite
	return sqrt(G*k); // sqrt(g*k*tanh(k*depth))
}

/** Derivative of dispertion_relation(float) */
float d_dispertion_relation(in float k) {
	return G / (2.0*sqrt(G*k));
}

// Source: Empirical Directional Wave Spectra for Computer Graphics
float hasselmann_directional_spread(in float w, in float w_p, in float wind_speed, in float theta) {
	float p = w / w_p;
    float s = (w <= w_p) ? 6.97*pow(p, 4.06) : 9.77*pow(p, -2.33 - 1.45*(wind_speed*w_p/G - 1.17));
	float s2 = 2.0*s;

	float g1 = gamma(s + 1.0);
	float g2 = gamma(s2 + 1.0);

	float q = pow(2.0, s2 - 1.0)*PI_INV * g1*g1/g2;
    return q * pow(abs(cos(theta*0.5)), s2);
}

// Source: https://wikiwaves.org/Ocean-Wave_Spectra#JONSWAP_Spectrum
float JONSWAP_spectrum(in float w, in float w_p, in float alpha) {
	float beta = 1.25;
	float gamma = 3.3; // Spectral peak shape constant
	
	float diff = w - w_p;
	float sigma = (diff <= 0) ? 0.07 : 0.09;
	float r = exp(-diff*diff / (2.0 * sigma*sigma * w_p*w_p));
	return (alpha * G*G) / pow(w, 5) * exp(-beta * pow(w_p/w, 4)) * pow(gamma, r);
}

vec2 get_spectrum_amplitude(in ivec2 id) {
	vec2 dk = TAU / params.tile_length;
	vec2 k_vec = (id - MAP_SIZE*0.5)*dk; // Wave direction
	float k = length(k_vec) + EPSILON;
	float theta = atan(k_vec.y, k_vec.x);

	float w = dispertion_relation(k);
	float w_norm = d_dispertion_relation(k) / k * dk.x*dk.y;
	float s = JONSWAP_spectrum(w, params.peak_frequency, params.alpha);
	float d = hasselmann_directional_spread(w, params.peak_frequency, params.wind_speed, theta);

	vec2 h0 = gaussian(id + k_vec*params.peak_frequency) * sqrt(2.0 * s * d * w_norm);	
	return any(greaterThan(h0, vec2(1e3))) ? vec2(0.0) : h0;
}

void main() {
	const ivec2 id0 = ivec2(gl_GlobalInvocationID.xy);
	const ivec2 id1 = ivec2(mod(-id0, MAP_SIZE));

	imageStore(spectrum, id0, vec4(get_spectrum_amplitude(id0), conj_complex(get_spectrum_amplitude(id1))));
}