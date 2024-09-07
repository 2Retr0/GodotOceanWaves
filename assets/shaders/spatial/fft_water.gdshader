shader_type spatial;
render_mode world_vertex_coords, shadows_disabled;
#define MAX_CASCADES 8
#define REFLECTANCE 0.02 // Reflectance from air to water (eta=1.33).

uniform vec3 water_color : source_color = vec3(0.17, 0.27, 0.3);
uniform vec3 foam_color : source_color = vec3(0.73, 0.67, 0.62);

uniform float roughness : hint_range(0.0, 1.0) = 0.5;
uniform float normal_strength : hint_range(0.0, 1.0) = 0.4;

group_uniforms cascade_data;
uniform int num_cascades;
uniform vec2 map_scales[MAX_CASCADES];        // Scales for displacement and normal maps.
uniform sampler2DArray displacements;         // Each layer represents one wave cascade.
uniform sampler2DArray normals : hint_normal; // Each layer represents one wave cascade.

varying float wave_height;
varying float foam_factor;
varying float fresnel;

void vertex() {
	UV = VERTEX.xz;
	vec3 displacement = vec3(0);
	for (int i = 0; i < num_cascades; ++i)
		displacement += texture(displacements, vec3(UV*map_scales[i], float(i))).xyz;
	VERTEX += displacement * min(exp(-(length(VERTEX.xz - CAMERA_POSITION_WORLD.xz) - 125.0)*0.01), 1.0);
	wave_height = displacement.y;
}

void fragment() {
	float dist = length(VERTEX.xz);
	// Read foam and normal information from normal map.
	vec3 gradient = vec3(0);
	for (int i = 0; i < num_cascades; ++i)
		gradient += texture(normals, vec3(UV*map_scales[i], float(i))).xyw;
	foam_factor = smoothstep(0.0, 1.0, gradient.z) * exp(-dist*0.0075);
	ALBEDO = mix(water_color, foam_color, foam_factor);

	gradient *= mix(0.0, normal_strength, exp(-dist*0.015));
	NORMAL = (VIEW_MATRIX * vec4(normalize(vec3(-gradient.x, 1.0, -gradient.y)), 0.0)).xyz;
	
	fresnel = mix(pow(1.0 - dot(VIEW, NORMAL), 5.0*exp(-2.69*roughness)) / (1.0 + 22.7*pow(roughness, 1.5)), 1.0, REFLECTANCE);
	ROUGHNESS = (1.0 - fresnel) * foam_factor + 0.3; // Roughness is proportional to foam/fog amount and fresnel.
}

float smith_masking_shadowing(in float cos_theta, in float alpha) {
	float a = cos_theta / (alpha * sqrt(1.0 - cos_theta*cos_theta)); // Approximate: 1.0 / (alpha * tan(acos(cos_theta)))
	float a_sq = a*a;
	return a < 1.6 ? (1.0 - 1.259*a + 0.396*a_sq) / (3.535*a + 2.181*a_sq) : 0.0;
}

// Source: https://github.com/godotengine/godot/blob/7b56111c297f24304eb911fe75082d8cdc3d4141/drivers/gles3/shaders/scene.glsl#L995
float ggx_distribution(in float cos_theta, in float alpha) {
	float a_sq = alpha*alpha;
	float d = 1.0 + (a_sq - 1.0) * cos_theta * cos_theta;
	return a_sq / (PI * d*d);
}

void light() {
	vec3 halfway = normalize(LIGHT + VIEW);
	float dot_nl = max(dot(NORMAL, LIGHT), 2e-5);
	float dot_nv = max(dot(NORMAL, VIEW), 2e-5);

	// --- SPECULAR ---
	float light_mask = smith_masking_shadowing(roughness, dot_nv);
	float view_mask = smith_masking_shadowing(roughness, dot_nl);
	float microfacet_distribution = ggx_distribution(dot(NORMAL, halfway), roughness);
	float geometric_attenuation = 1.0 / (1.0 + light_mask + view_mask);
	SPECULAR_LIGHT += fresnel * microfacet_distribution * geometric_attenuation / (4.0 * dot_nv + 0.1) * ATTENUATION;

	// --- DIFFUSE ---
	float k1 = 1.0*max(0.0, wave_height + 2.5) * pow(max(dot(LIGHT, -VIEW), 0.0), 4.0) * pow(0.5 - 0.5 * dot(LIGHT, NORMAL), 3.0);
	float k2 = 0.5*pow(dot_nv, 2.0);
	float k3 = 0.5*dot_nl;
	
	vec3 scatter = (k1*vec3(0.9,1.15,0.85) + k2) / (1.0 + light_mask) + k3;
	DIFFUSE_LIGHT += mix(scatter, foam_color, foam_factor) * (1.0 - fresnel) * ATTENUATION * LIGHT_COLOR;
}
