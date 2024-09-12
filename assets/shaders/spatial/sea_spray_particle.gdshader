shader_type particles;
render_mode disable_velocity;
/**
 * Handles where sea spray particles should spawn and determines their animation.
 */

#define MAX_CASCADES        8
#define G                   (vec3(0, -9.81, 0))

// Some definitions for convenience...
#define POSITION            (TRANSFORM[3].xyz)
#define START_POS           (USERDATA1.xyz)
#define START_TIME          (USERDATA1.w)
#define PARTICLE_SCALE      (USERDATA2.xyz)
#define PARTICLE_LIFETIME   (USERDATA2.w)
#define SCALE_FACTOR        (USERDATA3.z)
#define HAS_STARTED         (USERDATA3.w)

uniform uint num_particles;
uniform vec3 particle_scale;
uniform float lifetime = 3.0; // Actual lifetime.
uniform float lifetime_randomness : hint_range(0.0, 1.0) = 0.25;

group_uniforms cascade_data;
global uniform uint num_cascades;
uniform vec2 map_scales[MAX_CASCADES];        // Scales for displacement and normal maps.
global uniform sampler2DArray displacements;         // Each layer represents one wave cascade.
global uniform sampler2DArray normals : hint_normal; // Each layer represents one wave cascade.

// Source: https://www.shadertoy.com/view/Xt3cDn
vec3 hash32(uvec2 p) {
	p = 1103515245U * ((p >> 1U) ^ p.yx);
	uint h32 = 1103515245U * (p.x ^ (p.y>>3U));
	uint n = h32 ^ (h32 >> 16U);
    uvec3 rz = uvec3(n, n*16807U, n*48271U);
    return vec3((rz >> 1U) & uvec3(0x7FFFFFFFU)) / float(0x7FFFFFFF);
}

void set_scale(inout mat4 transform, in vec3 scale) {
	transform[0].xyz = normalize(transform[0].xyz) * scale.x;
	transform[1].xyz = normalize(transform[1].xyz) * scale.y;
	transform[2].xyz = normalize(transform[2].xyz) * scale.z;
}

void start() {
	if (RESTART_POSITION) {
		uint t = uint(sqrt(float(num_particles)));
		vec3 rand = hash32(uvec2(NUMBER, 1U) + uint(TIME) + RANDOM_SEED);
		
		// These are the coords of the (roughly) equally-distributed particles within the
		// emitter's box (in local space).
		vec2 coords = (vec2(uvec2(INDEX / t, INDEX % t)) / (float(t) - 1.0) - 0.5) * 10.0;
		TRANSFORM[3].xyz = vec3(coords.x, 0, coords.y); // POSITION
		TRANSFORM = EMISSION_TRANSFORM * TRANSFORM;

		CUSTOM.z = rand.x; 
		PARTICLE_LIFETIME = lifetime - lifetime*lifetime_randomness*rand.y;
		START_POS = POSITION;
		START_TIME = TIME + rand.z*(LIFETIME - PARTICLE_LIFETIME);
		
		HAS_STARTED = 0.0;
		POSITION = vec3(0,-1e10,0); // idk if this is needed.
		set_scale(TRANSFORM, vec3(1e-3));
		// Rest of initialization starts after the particle's start time has passed...
	}
}

// Source: https://iquilezles.org/articles/functions/
float exp_impulse(float x, float k) {
    float h = k*x;
    return h * exp(1.0 - h);
}

void process() {
	if (TIME > START_TIME + PARTICLE_LIFETIME) {
		ACTIVE = false;
	} else if (TIME >= START_TIME) {
		if (HAS_STARTED == 0.0) { // Particle has just started according to its start time.
			// --- INITIALIZATION ---
			// Read foam and normal information from normal maps.
			vec3 gradient = vec3(0);
			for (uint i = 0U; i < num_cascades; ++i)
				gradient += texture(normals, vec3(START_POS.xz*map_scales[i], float(i))).xyw;
			vec3 normal = normalize(vec3(-gradient.x, 1.0, -gradient.y));
			float foam = gradient.z;
			float normal_factor = mix(0.25, 1.0, (normal.y - 0.92) / (0.99 - 0.92)); // [0.92..0.99] -> [0.25..1]
			float foam_factor = mix(0.25, 1.0, (foam - 0.9) / (1.0 - 0.9));          // [0.90..1.00] -> [0.25..1]

			ACTIVE = normal_factor >= 0.0 && normal_factor <= 1.0 && foam > 0.9;
			SCALE_FACTOR = normal_factor*foam_factor;
			// Size of particle is based on foam amount and is flattened based on normal height.
			PARTICLE_SCALE = vec3(foam_factor * (float(ACTIVE) + 1e-3));
			PARTICLE_SCALE *= vec3(1, normal_factor, 1);
			PARTICLE_SCALE *= particle_scale;
			HAS_STARTED = 1.0;
		}
		
		if (ACTIVE) {
			float t = (TIME - START_TIME) / PARTICLE_LIFETIME;
			CUSTOM.a = exp_impulse(t, 10.0); // For use in mesh shader (`sea_spray.gdshader`)
			
			// Read displacements from displacement maps.
			vec3 displacement = vec3(0);
			for (uint i = 0U; i < num_cascades; ++i)
				displacement += texture(displacements, vec3(START_POS.xz*map_scales[i], float(i))).xyz;
			// Particles which are active will follow the displacement map for their lifetime.
			// We multiply the horizontal displacement by a factor < 1 to prevent jittering that occasionally
			// occurs from this method.
			// The particle will follow a parabolic trajectory vertically w.r.t. the displacement height
			// so that it rises and sinks in to the ground over its lifetime.
			POSITION = START_POS + displacement*vec3(0.75,1,0.75) + vec3(0, -5.0*pow(2.5*t - 0.45, 2.0)*SCALE_FACTOR + 0.5, 0);
			
			float size = PARTICLE_LIFETIME / lifetime; // Shorter particle lifetime = smaller size.
			vec3 scale_modifier = vec3(size*size);
			
			// Some shaping functions to get a splash-like animation.
			scale_modifier.y *= exp_impulse(t, 3.0);
			scale_modifier.xz *= vec2(log(1.0 + t));
			set_scale(TRANSFORM, PARTICLE_SCALE*scale_modifier);
		}
	}
}
