class_name OneOfUsRoleVisual
extends Node3D

var _ring: MeshInstance3D
var _label: Label3D


func _ready() -> void:
	_ring = MeshInstance3D.new()
	_ring.name = "InfectedRing"
	var ring := TorusMesh.new()
	ring.inner_radius = 0.82
	ring.outer_radius = 1.0
	ring.rings = 32
	ring.ring_segments = 8
	_ring.mesh = ring
	_ring.position.y = 0.07
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.95, 0.08, 0.42, 0.78)
	material.emission_enabled = true
	material.emission = Color(0.85, 0.02, 0.32)
	material.emission_energy_multiplier = 2.2
	_ring.material_override = material
	add_child(_ring)
	_label = Label3D.new()
	_label.name = "InfectedRoleLabel"
	_label.text = "THEM"
	_label.position = Vector3(0.0, 3.35, 0.0)
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = false
	_label.font_size = 42
	_label.outline_size = 10
	_label.modulate = Color(1.0, 0.12, 0.38)
	add_child(_label)
	set_infected(false)


func set_infected(active: bool) -> void:
	visible = active
	set_process(active)



func play_transformation() -> void:
	if not visible:
		return
	var light := OmniLight3D.new()
	light.name = "InfectionFlash"
	light.light_color = Color(1.0, 0.04, 0.30)
	light.light_energy = 7.0
	light.omni_range = 7.0
	light.position = Vector3.UP * 1.25
	add_child(light)
	var light_tween := create_tween()
	light_tween.tween_property(light, "light_energy", 0.0, 0.75)
	light_tween.tween_callback(light.queue_free)
	for index in 3:
		var pulse := MeshInstance3D.new()
		pulse.name = "TransformationPulse%d" % index
		var torus := TorusMesh.new()
		torus.inner_radius = 0.86
		torus.outer_radius = 1.0
		torus.rings = 32
		torus.ring_segments = 8
		pulse.mesh = torus
		pulse.position.y = 0.22 + index * 0.48
		pulse.scale = Vector3.ONE * (0.25 + index * 0.08)
		pulse.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var material := StandardMaterial3D.new()
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = Color(1.0, 0.04, 0.34, 0.92)
		material.emission_enabled = true
		material.emission = Color(0.95, 0.01, 0.28)
		material.emission_energy_multiplier = 4.0
		pulse.material_override = material
		add_child(pulse)
		var tween := create_tween()
		tween.tween_interval(index * 0.09)
		tween.tween_property(pulse, "scale", Vector3.ONE * (3.0 + index * 0.45), 0.72)
		tween.parallel().tween_method(func(alpha: float):
			var color := material.albedo_color
			color.a = alpha
			material.albedo_color = color, 0.92, 0.0, 0.72)
		tween.tween_callback(pulse.queue_free)


func _process(_delta: float) -> void:
	if not visible:
		return
	var pulse := 1.0 + sin(Time.get_ticks_msec() * 0.008) * 0.12
	_ring.scale = Vector3.ONE * pulse
