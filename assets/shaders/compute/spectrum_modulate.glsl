#[compute]
#version 460
/**
 * Modulates the JONSWAP wave spectra texture in time and calculates
 * its gradients. Since the outputs are all real-valued, they are packed
 * in pairs.
 *
 * Sources: Jerry Tessendorf - Simulating Ocean Water
 *          Robert Matusiak - Implementing Fast Fourier Transform Algorithms of Real-Valued Sequences With the TMS320 DSP Platform
 */

#define PI          (3.141592653589793)
#define G           (9.81)
#define NUM_SPECTRA (4U)

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

layout(rgba16f, set = 0, binding = 0) restrict readonly uniform image2DArray spectrum;

layout(std430, set = 1, binding = 0) restrict writeonly buffer FFTBuffer {
	vec2 data[]; // map_size x map_size x num_spectra x 2 * num_cascades
};

layout(push_constant) restrict readonly uniform PushConstants {
	vec2 tile_length;
	float depth;
	float time;
	uint cascade_index;
};

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

// Jerry Tessendorf - Source: Simulating Ocean Water
float dispersion_relation(in float k) {
	return sqrt(G*k*tanh(k*depth));
}

#define FFT_DATA(id, layer) (data[(id.z)*map_size*map_size*NUM_SPECTRA*2 + (layer)*map_size*map_size + (id.y)*map_size + (id.x)])
void main() {
	const uint map_size = gl_NumWorkGroups.x * gl_WorkGroupSize.x;
	const uint num_stages = findMSB(map_size); // Equivalent: log2(map_size) (assuming map_size is a power of 2)
	const ivec2 dims = imageSize(spectrum).xy;
	const ivec3 id = ivec3(gl_GlobalInvocationID.xy, cascade_index);

	vec2 k_vec = (id.xy - dims*0.5)*2.0*PI / tile_length; // Wave direction
	float k = length(k_vec) + 1e-6;
	vec2 k_unit = k_vec / k;

	// --- WAVE SPECTRUM MODULATION ---
	vec4 h0 = imageLoad(spectrum, id); // xy=h0(k), zw=conj(h0(-k))
	float dispersion = dispersion_relation(k) * time;
	vec2 modulation = exp_complex(dispersion);
	// Note: h respects the complex conjugation property
	vec2 h = mul_complex(h0.xy, modulation) + mul_complex(h0.zw, conj_complex(modulation));
	vec2 h_inv = vec2(-h.y, h.x); // Used to simplify complex multiplication operations

	// --- WAVE DISPLACEMENT CALCULATION ---
	vec2 hx = h_inv * k_unit.y;            // Equivalent: mul_complex(vec2(0, -k_unit.x), h);
	vec2 hy = h;
	vec2 hz = h_inv * k_unit.x;            // Equivalent: mul_complex(vec2(0, -k_unit.z), h);

	// --- WAVE GRADIENT CALCULATION ---
	// FIXME: i dont understand why k vectors need to be accessed yx instead of xy :(
	vec2 dhy_dx = h_inv * k_vec.y;         // Equivalent: mul_complex(vec2(0, k_vec.x), h);
	vec2 dhy_dz = h_inv * k_vec.x;         // Equivalent: mul_complex(vec2(0, k_vec.z), h);
	vec2 dhx_dx = -h * k_vec.y * k_unit.y; // Equivalent: mul_complex(vec2(k_vec.x * k_unit.x, 0), -h);
	vec2 dhz_dz = -h * k_vec.x * k_unit.x; // Equivalent: mul_complex(vec2(k_vec.y * k_unit.y, 0), -h);
	vec2 dhz_dx = -h * k_vec.y * k_unit.x; // Equivalent: mul_complex(vec2(k_vec.x * k_unit.y, 0), -h);

	// Because h repsects the complex conjugation property (i.e., the output of IFFT will be a
	// real signal), we can pack two waves into one.
	FFT_DATA(id, 0) = vec2(    hx.x -     hy.y,     hx.y +     hy.x);
	FFT_DATA(id, 1) = vec2(    hz.x - dhy_dx.y,     hz.y + dhy_dx.x);
	FFT_DATA(id, 2) = vec2(dhy_dz.x - dhx_dx.y, dhy_dz.y + dhx_dx.x);
	FFT_DATA(id, 3) = vec2(dhz_dz.x - dhz_dx.y, dhz_dz.y + dhz_dx.x);
}