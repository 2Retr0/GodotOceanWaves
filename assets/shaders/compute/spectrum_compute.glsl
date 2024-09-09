#[compute]
#version 460
/**
 * Generates a 2D texture representing the JONSWAP wave spectra
 * w/ Hasselmann directional spreading.
 *
 * Sources: Jerry Tessendorf - Simulating Ocean Water
 *          Christopher J. Horvath - Empirical Directional Wave Spectra for Computer Graphics
 */

#define PI (3.141592653589793)
#define G  (9.81)

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

layout(rgba16f, set = 0, binding = 0) restrict writeonly uniform image2DArray spectrum;

layout(push_constant) restrict readonly uniform PushConstants {
	ivec2 seed;
	vec2 tile_length;
	float alpha;
	float peak_frequency;
	float wind_speed;
	float angle;
	float depth;
	float swell;
	float detail;
	float spread;
	uint cascade_index;
};

// --- HELPER FUNCTIONS ---
// Source: https://www.shadertoy.com/view/Xt3cDn
vec2 hash(in uvec2 x) {
	uint h32 = x.y + 374761393U + x.x*3266489917U;
    h32 = 2246822519U * (h32 ^ (h32 >> 15));
    h32 = 3266489917U * (h32 ^ (h32 >> 13));
    uint n = h32 ^ (h32 >> 16);
    uvec2 rz = uvec2(n, n*48271U);
    return vec2((rz.xy >> 1) & uvec2(0x7FFFFFFFU)) / float(0x7FFFFFFF);
}

/** Samples a 2D-bivariate normal distribution */
vec2 gaussian(in vec2 x) {
	// Use Box-Muller transform to convert uniform distribution->normal distribution.
	float r = sqrt(-2.0 * log(x.x));
	float theta = 2.0*PI * x.y;
	return vec2(r*cos(theta), r*sin(theta));
}

/** Returns the complex conjugate of x */
vec2 conj_complex(in vec2 x) {
	return vec2(x.x, -x.y);
}

// --- SPECTRUM-RELATED FUNCTIONS ---
// Source: Jerry Tessendorf - Simulating Ocean Water
vec2 dispersion_relation(in float k) {
	float a = k*depth;
	float b = tanh(a);
	float dispersion_relation = sqrt(G*k*b);
	float d_dispersion_relation = 0.5*G * (b + a*(1.0 - b*b)) / dispersion_relation;

	// Return both the dispersion relation and its derivative w.r.t. k
	return vec2(dispersion_relation, d_dispersion_relation);
}

/** Normalization factor approximation for Longuet-Higgins function. */
float longuet_higgins_normalization(in float s) {
	// Note: i forgot how i derived this :skull:
	float a = sqrt(s);
	return (s < 0.4) ? (0.5/PI) + s*(0.220636+s*(-0.109+s*0.090)) : inversesqrt(PI)*(a*0.5 + (1.0/a)*0.0625);
}

// Source: Christopher J. Horvath - Empirical Directional Wave Spectra for Computer Graphics
float longuet_higgins_function(in float s, in float theta) {
	return longuet_higgins_normalization(s) * pow(abs(cos(theta*0.5)), 2.0*s);
}

// Source: Christopher J. Horvath - Empirical Directional Wave Spectra for Computer Graphics
float hasselmann_directional_spread(in float w, in float w_p, in float wind_speed, in float theta) {
	float p = w / w_p;
	float s = (w <= w_p) ? 6.97*pow(abs(p), 4.06) : 9.77*pow(abs(p), -2.33 - 1.45*(wind_speed*w_p/G - 1.17)); // Shaping parameter
	float s_xi = 16.0 * tanh(w_p / w) * swell*swell; // Shaping parameter w/ swell
    return longuet_higgins_function(s + s_xi, theta - angle);
}

// Source: Christopher J. Horvath - Empirical Directional Wave Spectra for Computer Graphics
float TMA_spectrum(in float w, in float w_p, in float alpha) {
	const float beta = 1.25;
	const float gamma = 3.3; // Spectral peak shape constant
	
	float sigma = (w <= w_p) ? 0.07 : 0.09;
	float r = exp(-(w-w_p)*(w-w_p) / (2.0 * sigma*sigma * w_p*w_p));
	float jonswap_spectrum = (alpha * G*G) / pow(w, 5) * exp(-beta * pow(w_p/w, 4)) * pow(gamma, r);

	float w_h = min(w * sqrt(depth / G), 2.0);
	float kitaigorodskii_depth_attenuation = (w_h <= 1.0) ? 0.5*w_h*w_h : 1.0 - 0.5*(2.0-w_h)*(2.0-w_h);

	return jonswap_spectrum * kitaigorodskii_depth_attenuation;
}

vec2 get_spectrum_amplitude(in ivec2 id, in ivec2 map_size) {
	vec2 dk = 2.0*PI / tile_length;
	vec2 k_vec = (id - map_size*0.5)*dk; // Wave direction
	float k = length(k_vec) + 1e-6;
	float theta = atan(k_vec.x, k_vec.y);

	vec2 dispersion = dispersion_relation(k);
	float w = dispersion[0];
	float w_norm = dispersion[1] / k * dk.x*dk.y;
	float s = TMA_spectrum(w, peak_frequency, alpha);
	float d = mix(0.5/PI, hasselmann_directional_spread(w, peak_frequency, wind_speed, theta), 1.0 - spread) * exp(-(1.0-detail)*(1.0-detail) * k*k);
	return gaussian(hash(uvec2(id + seed))) * sqrt(2.0 * s * d * w_norm);
}

void main() {
	const ivec2 dims = imageSize(spectrum).xy;
	const ivec3 id = ivec3(gl_GlobalInvocationID.xy, cascade_index);
	const ivec2 id0 = id.xy;
	const ivec2 id1 = ivec2(mod(-id0, dims));

	// We pack the spectra at both k and -k for use in the modulation stage
	imageStore(spectrum, id, vec4(get_spectrum_amplitude(id0, dims), conj_complex(get_spectrum_amplitude(id1, dims))));
}