shader_type spatial;
render_mode cull_back, unshaded, shadows_disabled;
/**
 * Handles the opacity and billboarding for the sea spray mesh.
 * This is not a great shader since it doesn't apply any lighting to particles (I am too lazy).
 */

global uniform vec4 water_color : source_color;
global uniform vec4 foam_color : source_color;

uniform float max_alpha : hint_range(0, 1) = 0.666;
uniform sampler2D albedo_texture : source_color, repeat_enable;
uniform sampler2D dissolve_texture : source_color, repeat_enable;

varying float dissolve_factor;
varying float alpha_fade;

void vertex() {
	// Billboarding
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(normalize(INV_VIEW_MATRIX[0]), normalize(INV_VIEW_MATRIX[1]), normalize(INV_VIEW_MATRIX[2]), MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz),0,0,0), vec4(0,length(MODEL_MATRIX[1].xyz),0,0), vec4(0,0,length(MODEL_MATRIX[2].xyz),0), vec4(0,0,0,1));
	dissolve_factor = INSTANCE_CUSTOM.z;
	alpha_fade = INSTANCE_CUSTOM.w;
}

void fragment() {
	vec4 albedo_tex = texture(albedo_texture, UV);
	ALBEDO = albedo_tex.rgb * foam_color.rgb*vec3(1.65,1.75,1.65);

	float distance_fade = 1.0 - exp(-length(VERTEX.xz)*0.04);
	ALPHA = albedo_tex.a * max_alpha;
	ALPHA *= distance_fade; // Fade
	ALPHA *= max((alpha_fade + dissolve_factor)*0.5 - texture(dissolve_texture, UV + vec2(TIME*0.35)).x, 0.0); // Dissolve
}
