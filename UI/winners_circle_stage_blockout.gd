class_name WinnersCircleStageBlockout
extends Node3D

# Replaceable visual stage for the Winners Circle. Static set dressing lives in
# three independently exported Blender GLBs; live characters, the equipped gun,
# trophy, labels and confetti are attached to stable anchors in the Godot scene.

const SkinRegistry = preload("res://player_skin_registry.gd")
const CosmeticRegistry = preload("res://supabase/supabase_cosmetic_registry.gd")

const GUN_MODEL_PATH := "res://models/weaponModels/water_gun.glb"
const TROPHY_MODEL_PATH := "res://models/rewards/winners_circle_trophy.glb"

var _entries: Array = []
var _result: Dictionary = {}
var _performers: Array[Dictionary] = []
var _trophy_root: Node3D = null
var _confetti: GPUParticles3D = null


func _ready() -> void:
	_configure_camera_and_lights()


func configure(entries: Array, result: Dictionary) -> void:
	_entries = entries.duplicate(true)
	_result = result.duplicate(true)
	_performers.clear()
	var placements := [
		{"entry_index": 1, "anchor": "SecondPlace", "label": "SecondName",
			"color": Color(0.18, 0.62, 1.0)},
		{"entry_index": 0, "anchor": "FirstPlace", "label": "FirstName",
			"color": Color(1.0, 0.64, 0.05)},
		{"entry_index": 2, "anchor": "ThirdPlace", "label": "ThirdName",
			"color": Color(0.30, 1.0, 0.26)},
	]
	for placement in placements:
		var entry_index := int(placement["entry_index"])
		var label := get_node("DynamicLabels/%s" % placement["label"]) as Label3D
		if entry_index >= _entries.size():
			label.visible = false
			continue
		var entry: Dictionary = _entries[entry_index]
		label.visible = true
		label.text = _entry_display_name(entry).to_upper()
		label.modulate = placement["color"]
		_build_competitor(
			get_node("Anchors/%s" % placement["anchor"]) as Node3D, entry)
	_build_ceremonial_gun()
	if bool(_result.get("trophy_awarded", false)):
		_build_trophy()
	_build_confetti()


func performer_records() -> Array[Dictionary]:
	return _performers


func trophy_root() -> Node3D:
	return _trophy_root


func confetti() -> GPUParticles3D:
	return _confetti


func _configure_camera_and_lights() -> void:
	var camera := get_node("WinnersCircleCamera") as Camera3D
	camera.look_at(get_node("LookTargets/CameraTarget").global_position, Vector3.UP)
	camera.current = true
	for pair in [
		["Lights/ChampionSpot", "LookTargets/ChampionTarget"],
		["Lights/SecondSpot", "LookTargets/SecondTarget"],
		["Lights/ThirdSpot", "LookTargets/ThirdTarget"],
	]:
		var light := get_node(pair[0]) as SpotLight3D
		light.look_at(get_node(pair[1]).global_position, Vector3.UP)


func _build_competitor(anchor: Node3D, entry: Dictionary) -> void:
	for child in anchor.get_children():
		child.queue_free()
	var model_id := SkinRegistry.sanitize_model_id(str(entry.get("model_id", "male")))
	var visual_scene := SkinRegistry.load_visual_scene(model_id)
	if visual_scene == null:
		return
	var visual := visual_scene.instantiate() as Node3D
	if visual == null:
		return
	visual.name = "VictoryPerformer"
	visual.set("model_id", model_id)
	visual.set("skin_id", SkinRegistry.sanitize_skin_id(
		str(entry.get("skin_id", "blue"))))
	visual.set("build_animation_library", false)
	anchor.add_child(visual)
	var cosmetics := CosmeticRegistry.sanitize_loadout(entry.get("cosmetics", {}))
	var move_id := str(cosmetics.get("emote", ""))
	var move_animation := CosmeticRegistry.local_victory_animation(move_id)
	var requested := ["idle", "long_idle"]
	if move_animation != "":
		requested.append(move_animation)
	var animation_player := visual.call("ensure_animations", requested) as AnimationPlayer
	_performers.append({
		"animation_player": animation_player,
		"animation": move_animation,
	})


func _build_ceremonial_gun() -> void:
	if _entries.is_empty() or not ResourceLoader.exists(GUN_MODEL_PATH):
		return
	var anchor := get_node("Anchors/CeremonialGun") as Node3D
	var gun_scene := load(GUN_MODEL_PATH) as PackedScene
	if gun_scene == null:
		return
	var gun := gun_scene.instantiate() as Node3D
	if gun == null:
		return
	gun.name = "CeremonialOneGun"
	gun.scale = Vector3.ONE * 0.0032
	anchor.add_child(gun)
	var champion: Dictionary = _entries[0]
	var cosmetics := CosmeticRegistry.sanitize_loadout(champion.get("cosmetics", {}))
	CosmeticRegistry.apply_gun_skin_to_display(
		gun, str(cosmetics.get("gun_skin", "")))


func _build_trophy() -> void:
	var start := get_node("Anchors/TrophyStart") as Marker3D
	var landing := get_node("Anchors/TrophyLanding") as Marker3D
	_trophy_root = Node3D.new()
	_trophy_root.name = "VictoryTrophy"
	_trophy_root.position = start.position
	_trophy_root.visible = false
	_trophy_root.set_meta("landing_y", landing.position.y)
	add_child(_trophy_root)
	if ResourceLoader.exists(TROPHY_MODEL_PATH):
		var trophy_scene := load(TROPHY_MODEL_PATH) as PackedScene
		if trophy_scene != null:
			var trophy := trophy_scene.instantiate() as Node3D
			if trophy != null:
				_trophy_root.add_child(trophy)
				return
	_build_placeholder_trophy(_trophy_root)


func _build_placeholder_trophy(parent: Node3D) -> void:
	var gold := _stage_material(Color(0.72, 0.39, 0.04),
		Color(1.0, 0.52, 0.06), 0.92)
	var cup := MeshInstance3D.new()
	var cup_mesh := SphereMesh.new()
	cup_mesh.radius = 0.42
	cup_mesh.height = 0.62
	cup.mesh = cup_mesh
	cup.scale = Vector3(1.0, 0.62, 0.72)
	cup.position.y = 0.72
	cup.material_override = gold
	parent.add_child(cup)
	for side in [-1.0, 1.0]:
		var handle := CSGTorus3D.new()
		handle.inner_radius = 0.11
		handle.outer_radius = 0.18
		handle.position = Vector3(side * 0.40, 0.76, 0.0)
		handle.rotation_degrees = Vector3(90.0, 0.0, 0.0)
		handle.material = gold
		parent.add_child(handle)
	var stem := MeshInstance3D.new()
	var stem_mesh := CylinderMesh.new()
	stem_mesh.top_radius = 0.09
	stem_mesh.bottom_radius = 0.13
	stem_mesh.height = 0.48
	stem.mesh = stem_mesh
	stem.position.y = 0.26
	stem.material_override = gold
	parent.add_child(stem)
	var base := MeshInstance3D.new()
	var base_mesh := BoxMesh.new()
	base_mesh.size = Vector3(0.72, 0.18, 0.52)
	base.mesh = base_mesh
	base.position.y = -0.05
	base.material_override = _stage_material(Color(0.05, 0.025, 0.01),
		Color(0.54, 0.28, 0.03), 0.75)
	parent.add_child(base)


func _build_confetti() -> void:
	_confetti = GPUParticles3D.new()
	_confetti.name = "WinnerConfetti"
	_confetti.position = (get_node("Anchors/Confetti") as Marker3D).position
	_confetti.amount = 56
	_confetti.lifetime = 3.4
	_confetti.one_shot = true
	_confetti.explosiveness = 0.92
	_confetti.emitting = false
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(5.4, 0.2, 1.6)
	process.direction = Vector3(0.0, -1.0, 0.0)
	process.spread = 42.0
	process.initial_velocity_min = 1.4
	process.initial_velocity_max = 3.4
	process.gravity = Vector3(0.0, -2.8, 0.0)
	_confetti.process_material = process
	var quad := QuadMesh.new()
	quad.size = Vector2(0.09, 0.16)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1.0, 0.63, 0.04)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.32, 0.02)
	material.emission_energy_multiplier = 1.8
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	quad.material = material
	_confetti.draw_pass_1 = quad
	add_child(_confetti)


func _stage_material(albedo: Color, emission: Color,
		metallic: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = albedo
	material.metallic = metallic
	material.roughness = 0.28
	if emission != Color.BLACK:
		material.emission_enabled = true
		material.emission = emission
		material.emission_energy_multiplier = 0.72
	return material


func _entry_display_name(entry: Dictionary) -> String:
	var display_name := str(entry.get("name", "Player")).strip_edges()
	var handle := str(entry.get("account_handle", "")).strip_edges()
	if handle != "":
		return "%s  @%s" % [display_name, handle.trim_prefix("@")]
	if bool(entry.get("duplicate_name", false)):
		return "%s  ·  P%d" % [display_name, int(entry.get("actor_id", 0))]
	return display_name
