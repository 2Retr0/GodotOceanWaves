shader_type spatial;
#define MAX_CASCADES 8

uniform int num_cascades;
uniform sampler2DArray displacements : filter_nearest;
uniform sampler2DArray normals : filter_linear;
uniform float scales[MAX_CASCADES];

void vertex() {
	UV = VERTEX.xz;
	for (int i = 0; i < num_cascades; ++i)
		VERTEX += texture(displacements, vec3(UV*scales[i], float(i))).xyz;
}

void fragment() {
	float height = 0.0;
	vec3 gradient = vec3(0);
	for (int i = 0; i < num_cascades; ++i) {
		height += texture(displacements, vec3(UV*scales[i], float(i))).y;
		gradient += texture(normals, vec3(UV*scales[i], float(i))).xyw;
	}
	ALBEDO.rgb = mix(vec3(0.1, 0.25, 0.30), vec3(0.1, 0.28, 0.27), clamp(height, 0.0, 1.0));
	ALBEDO.rgb = mix(ALBEDO.rgb, vec3(0.3, 0.4, 0.4), gradient.z);

	NORMAL = normalize(vec3(-gradient.x, 1.0, -gradient.y))*0.7;
	ROUGHNESS = 0.2;
	SPECULAR = 1.0;
	//RIM = 0.05;
}
