#[compute]
#version 460
/** Generates a 2D texture representing the JONSWAP wave spectra
  * w/ Hasselmann directional spreading.
  *
  * Sources: Jerry Tessendorf - Simulating Ocean Water
  *          Christopher J. Horvath - Empirical Directional Wave Spectra for Computer Graphics
  */

#define PI         (3.141592653589793)
#define EPSILON    (1e-10)
#define G          (9.81)

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

layout(rgba16f, set = 0, binding = 0) restrict writeonly uniform image2D spectrum;

layout(push_constant) restrict readonly uniform PushConstants {
	vec2 tile_length;
	float alpha;
	float peak_frequency;
	float wind_speed;
	float depth;
	float swell;
	float angle;
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
	float theta = 2.0*PI * h.y;
	return vec2(r*cos(theta), r*sin(theta));
}

/** Returns the complex conjugate of x */
vec2 conj_complex(in vec2 x) {
	x.y *= -1;
	return x;
}

// --- SPECTRUM-RELATED FUNCTIONS ---
// Source: Jerry Tessendorf - Simulating Ocean Water
vec2 dispertion_relation(in float k) {
	float a = k*params.depth;
	float b = tanh(k*params.depth + 1e-6);
	float dispertion_relation = sqrt(G*k*b);
	float d_dispertion_relation = 0.5*G * (b + a*(1.0 - b*b)) / dispertion_relation;

	// Return both the dispertion relation and its derivative w.r.t. k
	return vec2(dispertion_relation, d_dispertion_relation);
}

/** Normalization factor approximation for Longuet-Higgins function. */
float longuet_higgins_normalization(in float s) {
	float a = sqrt(s);
	return (s < 0.4) ? (0.5/PI) + s*(0.220636+s*(-0.109+s*0.090)) : (1.0*inversesqrt(PI))*(a*0.5 + (1.0/a)*0.0625);
}

// Source: Christopher J. Horvath - Empirical Directional Wave Spectra for Computer Graphics
float longuet_higgins_function(in float s, in float theta) {
	return longuet_higgins_normalization(s) * pow(abs(cos(theta*0.5)), 2.0*s);
}

// Source: Christopher J. Horvath - Empirical Directional Wave Spectra for Computer Graphics
float hasselmann_directional_spread(in float w, in float w_p, in float wind_speed, in float theta) {
	float p = w / w_p;
    float s = (w <= w_p) ? 6.97*pow(p, 4.06) : 9.77*pow(p, -2.33 - 1.45*(wind_speed*w_p/G - 1.17));
	float s_xi = 16.0 * tanh(1.0 / p) * params.swell*params.swell;
    return longuet_higgins_normalization(w) * longuet_higgins_function(s + s_xi, theta);
}

// Source: Christopher J. Horvath - Empirical Directional Wave Spectra for Computer Graphics
float TMA_spectrum(in float w, in float w_p, in float alpha) {
	const float beta = 1.25;
	const float gamma = 3.3; // Spectral peak shape constant
	
	float diff = w - w_p;
	float sigma = (diff <= 0) ? 0.07 : 0.09;
	float r = exp(-diff*diff / (2.0 * sigma*sigma * w_p*w_p));
	float jonswap_spectrum = (alpha * G*G) / pow(w, 5) * exp(-beta * pow(w_p/w, 4)) * pow(gamma, r);

	float w_h = min(2.0, w * sqrt(params.depth / G));
	float kitaigorodskii_depth_attenuation = (w_h <= 1.0) ? 0.5*w_h*w_h : 1.0 - 0.5*pow(2.0 - w_h, 2);

	return jonswap_spectrum * kitaigorodskii_depth_attenuation;
}

vec2 get_spectrum_amplitude(in ivec2 id, in ivec2 map_size) {
	vec2 dk = 2.0*PI / params.tile_length;
	vec2 k_vec = (id - map_size*0.5)*dk; // Wave direction
	float k = length(k_vec) + EPSILON;
	float theta = atan(k_vec.y, k_vec.x);

	vec2 dispertion = dispertion_relation(k);
	float w = dispertion[0];
	float w_norm = dispertion[1] / k * dk.x*dk.y;
	float s = TMA_spectrum(w, params.peak_frequency, params.alpha);
	float d = hasselmann_directional_spread(w, params.peak_frequency, params.wind_speed, theta - params.angle);

	vec2 h0 = gaussian(id + k_vec*params.peak_frequency) * sqrt(2.0 * s * d * w_norm);	
	return any(greaterThan(h0, vec2(1e3))) ? vec2(0.0) : h0;
}

void main() {
	const ivec2 dims = imageSize(spectrum);
	const ivec2 id0 = ivec2(gl_GlobalInvocationID.xy);
	const ivec2 id1 = ivec2(mod(-id0, dims));

	// We pack the spectra at both k and -k for use in the modulation stage
	imageStore(spectrum, id0, vec4(get_spectrum_amplitude(id0, dims), conj_complex(get_spectrum_amplitude(id1, dims))));
}