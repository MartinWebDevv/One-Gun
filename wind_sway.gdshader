shader_type spatial;
// Gentle wind sway for foliage. Sway weight grows with vertex height so
// roots stay planted. Per-instance phase offset comes from world position.

uniform vec4 albedo_color : source_color = vec4(0.2, 0.5, 0.2, 1.0);
uniform float sway_strength = 0.06;
uniform float sway_speed = 1.6;
uniform float height_ref = 0.45; // vertex height (model space) of full sway

void vertex() {
	float w = clamp(VERTEX.y / max(height_ref, 0.001), 0.0, 1.0);
	w *= w;
	float phase = TIME * sway_speed + NODE_POSITION_WORLD.x * 0.7 + NODE_POSITION_WORLD.z * 0.9;
	VERTEX.x += sin(phase) * sway_strength * w;
	VERTEX.z += cos(phase * 0.83) * sway_strength * w * 0.6;
}

void fragment() {
	ALBEDO = albedo_color.rgb;
	ROUGHNESS = 1.0;
	SPECULAR = 0.1;
}
