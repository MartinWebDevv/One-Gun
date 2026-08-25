extends Node

# Forward+ visual QA fixture for locally mapped victory moves. It renders two
# representative frames per clip through the real PlayerV2 retargeting path.

const SkinRegistry = preload("res://player_skin_registry.gd")
const MOVES := [
	"podium_backbeat_bounce", "podium_champion_canter",
	"podium_fresh_footwork", "podium_house_party_heat",
	"podium_serpent_flow", "podium_midnight_monster", "podium_victory_wave",
	"round_breakspin_finale", "round_floorwork_finish", "round_birdie_boogie",
	"round_arena_clapline", "round_soul_cyclone",
	"round_quickstep_shuffle", "round_victory_swing",
]

var _viewport: SubViewport
var _visual: Node3D


func _ready() -> void:
	_build_world()
	_capture_all.call_deferred()


func _build_world() -> void:
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(600, 600)
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)
	var world := Node3D.new()
	_viewport.add_child(world)
	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.008, 0.014, 0.035)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.50, 0.62, 0.90)
	environment.ambient_light_energy = 1.1
	world_environment.environment = environment
	world.add_child(world_environment)
	var floor := MeshInstance3D.new()
	var floor_mesh := CylinderMesh.new()
	floor_mesh.top_radius = 1.25
	floor_mesh.bottom_radius = 1.34
	floor_mesh.height = 0.28
	floor.mesh = floor_mesh
	floor.position.y = 0.14
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.06, 0.09, 0.18)
	floor_material.metallic = 0.55
	floor_material.roughness = 0.30
	floor.material_override = floor_material
	world.add_child(floor)
	var visual_scene := SkinRegistry.load_visual_scene("male")
	_visual = visual_scene.instantiate() as Node3D
	_visual.set("model_id", "male")
	_visual.set("skin_id", "blue")
	_visual.set("build_animation_library", false)
	_visual.position.y = 0.30
	world.add_child(_visual)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-42.0, -28.0, 0.0)
	key.light_color = Color(1.0, 0.84, 0.66)
	key.light_energy = 2.4
	key.shadow_enabled = true
	world.add_child(key)
	var rim := OmniLight3D.new()
	rim.position = Vector3(1.8, 2.2, -1.8)
	rim.light_color = Color(0.25, 0.58, 1.0)
	rim.light_energy = 3.0
	rim.omni_range = 6.0
	world.add_child(rim)
	var camera := Camera3D.new()
	camera.fov = 38.0
	camera.look_at_from_position(
		Vector3(-2.65, 1.82, 5.15), Vector3(0.0, 1.30, 0.0), Vector3.UP)
	world.add_child(camera)
	camera.current = true


func _capture_all() -> void:
	var output_dir := OS.get_environment("ONEGUN_VICTORY_CAPTURE_DIR")
	if output_dir.is_empty():
		output_dir = ProjectSettings.globalize_path(
			"res://docs/screenshots/victory_moves/qa")
	DirAccess.make_dir_recursive_absolute(output_dir)
	await get_tree().process_frame
	var player := _visual.call("ensure_animations", MOVES) as AnimationPlayer
	if player == null:
		get_tree().quit(1)
		return
	for animation_name in MOVES:
		var animation := player.get_animation(animation_name)
		for frame_data in [["a", 0.28], ["b", 0.68]]:
			player.play(animation_name)
			player.seek(animation.length * float(frame_data[1]), true)
			player.advance(0.0)
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var path := output_dir.path_join(
				"%s_%s.png" % [animation_name, str(frame_data[0])])
			var error := _viewport.get_texture().get_image().save_png(path)
			if error != OK:
				push_error("Could not save %s: %s" % [path, error_string(error)])
				get_tree().quit(1)
				return
	print("VICTORY_MOVE_RENDER_FIXTURE_OK frames=%d" % (MOVES.size() * 2))
	get_tree().quit(0)
