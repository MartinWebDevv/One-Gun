shader_type spatial;
render_mode blend_mix, depth_prepass_alpha, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic;
uniform float window_opacity : hint_range(0.0, 1.0) = 0.24;

varying vec3 source_position;


void vertex() {
	// Building C's imported mesh is scaled by its scene nodes. Keeping this in
	// source-mesh space makes the cutouts follow every instance transform.
	source_position = VERTEX;
}


bool in_rect(float value_a, float minimum_a, float maximum_a,
		float value_b, float minimum_b, float maximum_b) {
	return value_a >= minimum_a && value_a <= maximum_a
		&& value_b >= minimum_b && value_b <= maximum_b;
}


void fragment() {
	bool front_door = source_position.z > 0.0048
		&& in_rect(source_position.x, -0.00524, -0.00255,
			source_position.y, 0.00098, 0.00752);
	// The right wall is the clear side of the source model, away from the
	// dumpster cluster. Both entrances are permanent open passages.
	bool side_door = source_position.x > 0.00562
		&& in_rect(source_position.z, -0.00267, 0.00267,
			source_position.y, 0.00098, 0.00752);
	if (front_door || side_door) {
		discard;
	}

	vec4 sampled = texture(albedo_texture, UV);
	ALBEDO = sampled.rgb;
	METALLIC = 0.40;
	ROUGHNESS = 0.23;

	bool ground_window = source_position.z > 0.0048
		&& in_rect(source_position.x, -0.00091, 0.00491,
			source_position.y, 0.00248, 0.00612);
	bool upper_left_window = source_position.z > 0.0048
		&& in_rect(source_position.x, -0.00504, -0.00308,
			source_position.y, 0.01124, 0.01408);
	bool upper_center_window = source_position.z > 0.0048
		&& in_rect(source_position.x, -0.00100, 0.00100,
			source_position.y, 0.01124, 0.01408);
	bool upper_right_window = source_position.z > 0.0048
		&& in_rect(source_position.x, 0.00308, 0.00504,
			source_position.y, 0.01124, 0.01408);
	ALPHA = (ground_window || upper_left_window || upper_center_window
		|| upper_right_window) ? window_opacity : 1.0;
}
