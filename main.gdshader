shader_type spatial;
render_mode world_vertex_coords;

uniform sampler2D displacement_map;
uniform sampler2D normal_map;
uniform float map_scale;

varying mat3 tangent_matrix;

void vertex() {
	UV = VERTEX.xz;
	vec3 displacement = texture(displacement_map, vec2(UV*map_scale)).xyz * 5.38 - 2.75;
	//displacement.xyz *= 2.5;
	VERTEX += displacement;
	tangent_matrix = transpose(mat3(TANGENT, BINORMAL, NORMAL));
}

void fragment() {
	vec2 gradient = texture(normal_map, vec2(UV*map_scale)).xy;
	NORMAL_MAP = normalize(tangent_matrix * normalize(vec3(-gradient.x, 1.0, -gradient.y)));

	ALBEDO = vec3(0.0, 157.0, 196.0) / 255.0;
	vec3 displacement = texture(displacement_map, vec2(UV*map_scale)).xyz * 5.38 - 2.75;
	ALBEDO = displacement;
}

//void light() {
	// Called for every pixel for every light affecting the material.
	// Uncomment to replace the default light processing function with this one.
//}
