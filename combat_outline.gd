extends RefCounted

const GUN_HOLDER_MARKER_FONT_SIZE := 52
const GUN_HOLDER_MARKER_OUTLINE_SIZE := 18
const GUN_HOLDER_MARKER_PULSE_AMOUNT := 0.16

# Overtime needs to reveal survivors through map geometry, but an inverted-hull
# material with depth testing disabled renders the whole rear shell through the
# character. On the V2 model (whose imported mesh is scaled by its visual root)
# that becomes a large red blob. This material draws only grazing-angle pixels
# on the real character surface, producing a scale-independent silhouette rim.
static var _overtime_reveal_shader: Shader = null
static var _gun_holder_rim_shader: Shader = null


static func create_gun_holder_rim_material() -> ShaderMaterial:
	# The V2 cat is imported beneath a heavily scaled visual root. Expanding an
	# inverted hull therefore produces a giant solid shell instead of a narrow
	# outline. Draw a Fresnel rim directly on the real skinned surface so its
	# thickness is independent of the model's import scale. Unlike overtime,
	# normal depth testing is retained: walls still conceal the gun holder.
	if _gun_holder_rim_shader == null:
		_gun_holder_rim_shader = Shader.new()
		_gun_holder_rim_shader.code = """
shader_type spatial;
render_mode unshaded, cull_back, blend_mix;

uniform vec4 rim_color : source_color = vec4(1.0, 0.055, 0.005, 0.98);
uniform float rim_start = 0.46;
uniform float rim_end = 0.78;

void fragment() {
	float facing = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float rim = smoothstep(rim_start, rim_end, 1.0 - facing);
	float pulse = 0.88 + 0.12 * sin(TIME * 10.0);
	ALBEDO = rim_color.rgb;
	EMISSION = rim_color.rgb * (1.65 * pulse);
	ALPHA = rim_color.a * rim;
}
"""
	var material := ShaderMaterial.new()
	material.shader = _gun_holder_rim_shader
	material.render_priority = 1
	return material


static func create_overtime_reveal_material() -> ShaderMaterial:
	if _overtime_reveal_shader == null:
		_overtime_reveal_shader = Shader.new()
		_overtime_reveal_shader.code = """
shader_type spatial;
render_mode unshaded, cull_back, depth_test_disabled, blend_mix;

uniform vec4 reveal_color : source_color = vec4(1.0, 0.025, 0.025, 0.96);
uniform float rim_start = 0.50;
uniform float rim_end = 0.82;

void fragment() {
	float facing = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float rim = 1.0 - facing;
	float outline = smoothstep(rim_start, rim_end, rim);
	float pulse = 0.90 + 0.10 * sin(TIME * 12.0);
	ALBEDO = reveal_color.rgb;
	EMISSION = reveal_color.rgb * (1.55 * pulse);
	ALPHA = reveal_color.a * outline;
}
"""
	var material := ShaderMaterial.new()
	material.shader = _overtime_reveal_shader
	material.render_priority = 1
	return material


static func create_decoy_reveal_material() -> ShaderMaterial:
	# Decoy destruction intentionally reveals the shooter through cover, but it
	# must use the same scale-independent surface treatment as overtime. The old
	# expanded inverted hull turns the heavily scaled V2 import into a solid blob.
	var material := create_overtime_reveal_material()
	material.set_shader_parameter("reveal_color", Color(1.0, 0.05, 0.015, 0.96))
	return material
