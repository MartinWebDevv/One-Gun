shader_type spatial;
render_mode blend_mix, depth_prepass_alpha, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic;
uniform float window_opacity : hint_range(0.0, 1.0) = 0.24;

varying vec3 source_position;


void vertex() {
	// Building B keeps the source GLB untouched; this material is bound only to
	// the independent enterable scene.
	source_position = VERTEX;
}


bool in_rect(float value_a, float minimum_a, float maximum_a,
		float value_b, float minimum_b, float maximum_b) {
	return value_a >= minimum_a && value_a <= maximum_a
		&& value_b >= minimum_b && value_b <= maximum_b;
}


void fragment() {
	bool front_door = source_position.z > 0.0048
		&& in_rect(source_position.x, -0.00748, -0.00452,
			source_position.y, 0.00095, 0.00635);
	bool side_door = source_position.x > 0.00775
		&& in_rect(source_position.z, -0.00295, 0.00295,
			source_position.y, 0.00095, 0.00635);
	if (front_door || side_door) {
		discard;
	}

	vec4 sampled = texture(albedo_texture, UV);
	ALBEDO = sampled.rgb;
	METALLIC = 0.40;
	ROUGHNESS = 0.23;

	bool ground_left = source_position.z > 0.0048
		&& in_rect(source_position.x, -0.00308, -0.00092,
			source_position.y, 0.00225, 0.00555);
	bool ground_center = source_position.z > 0.0048
		&& in_rect(source_position.x, 0.00092, 0.00308,
			source_position.y, 0.00225, 0.00555);
	bool ground_right = source_position.z > 0.0048
		&& in_rect(source_position.x, 0.00492, 0.00708,
			source_position.y, 0.00225, 0.00555);
	bool upper_left = source_position.z > 0.0048
		&& in_rect(source_position.x, -0.00765, -0.00535,
			source_position.y, 0.01075, 0.01420);
	bool upper_center_left = source_position.z > 0.0048
		&& in_rect(source_position.x, -0.00365, -0.00135,
			source_position.y, 0.01075, 0.01420);
	bool upper_center_right = source_position.z > 0.0048
		&& in_rect(source_position.x, 0.00035, 0.00265,
			source_position.y, 0.01075, 0.01420);
	bool upper_right = source_position.z > 0.0048
		&& in_rect(source_position.x, 0.00485, 0.00715,
			source_position.y, 0.01075, 0.01420);
	bool transparent_window = ground_left || ground_center || ground_right
		|| upper_left || upper_center_left || upper_center_right
		|| upper_right;
	ALPHA = transparent_window ? window_opacity : 1.0;
}
