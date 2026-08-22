extends Node

# Applies the user's effects tier to render nodes as they enter the tree.
# This stays event-driven: there is no per-frame quality scan, and authored
# High/Ultra values are cached so changing presets is reversible at runtime.

const APPLIER = preload("res://UI/player_settings_applier.gd")
const QUALITY_KEYS := ["quality_preset", "shadow_quality", "anti_aliasing", "render_scale", "effects_quality"]
const META_ENVIRONMENT := &"one_gun_quality_environment"
const META_LIGHT_SHADOW := &"one_gun_quality_light_shadow"
const META_DIRECTIONAL_DISTANCE := &"one_gun_quality_directional_distance"
const META_PARTICLE_RATIO := &"one_gun_quality_particle_ratio"
const META_CAMERA_ATTRIBUTES := &"one_gun_quality_camera_attributes"

const PARTICLE_FACTORS := {
	"low": 0.45,
	"medium": 0.70,
	"high": 1.0,
	"ultra": 1.0,
}

var _apply_queued := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().node_added.connect(_on_node_added)
	PlayerPrefs.setting_changed.connect(_on_setting_changed)
	call_deferred("_apply_whole_tree")


func effects_quality() -> String:
	return _normalize_quality(str(PlayerPrefs.get_setting("effects_quality")))


func apply_effects_quality(quality: String) -> void:
	# Player Settings calls this while previewing an unsaved preset. Only touch
	# effect nodes here: reapplying viewports from PlayerPrefs would overwrite
	# the pending render scale, AA, and shadow-atlas values.
	_apply_subtree_with_quality(get_tree().root, _normalize_quality(quality), false)


func apply_subtree(root: Node) -> void:
	_apply_subtree_with_quality(root, effects_quality(), true)


func _apply_subtree_with_quality(root: Node, quality: String, apply_viewport_settings: bool) -> void:
	if not is_instance_valid(root):
		return
	_apply_node(root, quality, apply_viewport_settings)
	for child in root.get_children():
		_apply_subtree_with_quality(child, quality, apply_viewport_settings)


func _normalize_quality(quality: String) -> String:
	return quality if quality in PARTICLE_FACTORS else "high"


func _on_node_added(node: Node) -> void:
	# Resources/properties are already assigned for authored scene nodes when
	# node_added fires. Runtime-built nodes that finish setup afterward can call
	# apply_subtree() once, as the menu environment does.
	_apply_node(node, effects_quality(), true)


func _on_setting_changed(key: String, _value) -> void:
	if key not in QUALITY_KEYS or _apply_queued:
		return
	_apply_queued = true
	call_deferred("_apply_whole_tree")


func _apply_whole_tree() -> void:
	_apply_queued = false
	apply_subtree(get_tree().root)


func _apply_node(node: Node, quality: String, apply_viewport_settings: bool) -> void:
	if apply_viewport_settings and node is Viewport:
		APPLIER.apply_viewport(node as Viewport, PlayerPrefs.settings)
	if node is WorldEnvironment:
		_apply_environment(node as WorldEnvironment, quality)
	elif node is DirectionalLight3D:
		_apply_directional_light(node as DirectionalLight3D, quality)
	elif node is OmniLight3D or node is SpotLight3D:
		_apply_local_light(node as Light3D, quality)
	elif node is GPUParticles3D:
		_apply_particles(node as GPUParticles3D, quality)
	elif node is Camera3D:
		_apply_camera(node as Camera3D, quality)


func _apply_environment(holder: WorldEnvironment, quality: String) -> void:
	if holder.environment == null:
		return
	if not holder.has_meta(META_ENVIRONMENT):
		var local_environment := holder.environment.duplicate() as Environment
		if local_environment == null:
			return
		holder.environment = local_environment
		holder.set_meta(META_ENVIRONMENT, {
			"ssao": local_environment.ssao_enabled,
			"ssil": local_environment.ssil_enabled,
			"ssr": local_environment.ssr_enabled,
			"volumetric_fog": local_environment.volumetric_fog_enabled,
			"glow": local_environment.glow_enabled,
		})
	var baseline: Dictionary = holder.get_meta(META_ENVIRONMENT)
	var environment := holder.environment
	environment.ssao_enabled = bool(baseline.get("ssao", false))
	environment.ssil_enabled = bool(baseline.get("ssil", false))
	environment.ssr_enabled = bool(baseline.get("ssr", false))
	environment.volumetric_fog_enabled = bool(baseline.get("volumetric_fog", false))
	environment.glow_enabled = bool(baseline.get("glow", false))
	if quality == "low":
		environment.ssao_enabled = false
		environment.ssil_enabled = false
		environment.ssr_enabled = false
		environment.volumetric_fog_enabled = false
		environment.glow_enabled = false
	elif quality == "medium":
		environment.ssil_enabled = false
		environment.ssr_enabled = false


func _apply_local_light(light: Light3D, quality: String) -> void:
	if not light.has_meta(META_LIGHT_SHADOW):
		light.set_meta(META_LIGHT_SHADOW, light.shadow_enabled)
	var authored_shadow := bool(light.get_meta(META_LIGHT_SHADOW))
	light.shadow_enabled = authored_shadow and quality != "low"


func _apply_directional_light(light: DirectionalLight3D, quality: String) -> void:
	if not light.has_meta(META_LIGHT_SHADOW):
		light.set_meta(META_LIGHT_SHADOW, light.shadow_enabled)
	if not light.has_meta(META_DIRECTIONAL_DISTANCE):
		light.set_meta(META_DIRECTIONAL_DISTANCE, light.directional_shadow_max_distance)
	light.shadow_enabled = bool(light.get_meta(META_LIGHT_SHADOW))
	var authored_distance := float(light.get_meta(META_DIRECTIONAL_DISTANCE))
	match quality:
		"low": light.directional_shadow_max_distance = minf(authored_distance, 35.0)
		"medium": light.directional_shadow_max_distance = minf(authored_distance, 60.0)
		_: light.directional_shadow_max_distance = authored_distance


func _apply_particles(particles: GPUParticles3D, quality: String) -> void:
	if not particles.has_meta(META_PARTICLE_RATIO):
		particles.set_meta(META_PARTICLE_RATIO, particles.amount_ratio)
	var authored_ratio := float(particles.get_meta(META_PARTICLE_RATIO))
	var factor := float(PARTICLE_FACTORS.get(quality, 1.0))
	# Tiny one-shot effects are already cheap and can disappear completely if
	# their amount is ratio-reduced. Preserve those gameplay-readable cues.
	if particles.amount <= 4:
		particles.amount_ratio = authored_ratio
		return
	var minimum_visible_ratio := minf(1.0, 4.0 / float(particles.amount))
	particles.amount_ratio = minf(authored_ratio, maxf(authored_ratio * factor, minimum_visible_ratio))


func _apply_camera(camera: Camera3D, quality: String) -> void:
	var attributes := camera.attributes as CameraAttributesPractical
	if attributes == null:
		return
	if not camera.has_meta(META_CAMERA_ATTRIBUTES):
		attributes = attributes.duplicate() as CameraAttributesPractical
		camera.attributes = attributes
		camera.set_meta(META_CAMERA_ATTRIBUTES, {
			"dof_near": attributes.dof_blur_near_enabled,
			"dof_far": attributes.dof_blur_far_enabled,
		})
	var baseline: Dictionary = camera.get_meta(META_CAMERA_ATTRIBUTES)
	attributes = camera.attributes as CameraAttributesPractical
	attributes.dof_blur_near_enabled = bool(baseline.get("dof_near", false)) and quality != "low"
	attributes.dof_blur_far_enabled = bool(baseline.get("dof_far", false)) and quality != "low"
