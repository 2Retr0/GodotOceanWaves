shader_type spatial;
#define MAX_CASCADES 8

uniform int num_cascades;
uniform sampler2DArray displacements;
uniform sampler2DArray normals;
uniform vec2 map_scales[MAX_CASCADES];
uniform float foam_scales[MAX_CASCADES];

varying float height;

void vertex() {
	UV = VERTEX.xz;
	vec3 displacement = vec3(0);
	for (int i = 0; i < num_cascades; ++i)
		displacement += texture(displacements, vec3(UV*map_scales[i], float(i))).xyz;
	VERTEX += displacement;
	height = displacement.y;
}

void fragment() {
	vec3 gradient = vec3(0);
	for (int i = 0; i < num_cascades; ++i)
		gradient += texture(normals, vec3(UV*map_scales[i], float(i))).xyw * vec3(1.0, 1.0, foam_scales[i]);
	ALBEDO.rgb = mix(vec3(0.023, 0.26, 0.45)*0.45, vec3(0.023, 0.26, 0.35)*0.7, smoothstep(0.0, 1.0, height));
	float foam = gradient.z;
	ALBEDO.rgb = mix(ALBEDO.rgb, vec3(0.7, 0.5, 0.4), smoothstep(0.0, 1.0, foam));

	gradient *= 0.7;
	NORMAL_MAP = normalize(vec3(gradient.x, 1.0, gradient.y));
	ROUGHNESS = 0.2;
	ANISOTROPY = 0.5;
}

void light() {
	DIFFUSE_LIGHT = clamp(dot(NORMAL, LIGHT), 0, 1) * ATTENUATION * ALBEDO;
}
