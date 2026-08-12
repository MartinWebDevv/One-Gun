extends Node

## Renders the real V2 character into the static profile portraits used by
## customization cards and local/online lobby rows. Run with the Forward+
## renderer (not --headless), then restart once so Godot imports the PNGs.

const SkinRegistry = preload("res://player_skin_registry.gd")
const VISUAL_SCENE = preload("res://models/player_v2/player_v2_visual.tscn")
const OUTPUT_DIR := "res://UI/assets/character_portraits"
const PORTRAIT_SIZE := Vector2i(512, 512)

var _viewport: SubViewport
var _pivot: Node3D
var _visual: Node3D


func _ready() -> void:
	_generate.call_deferred()


func _generate() -> void:
	_build_portrait_stage()
	await _wait_frames(8)
	var absolute_dir := ProjectSettings.globalize_path(OUTPUT_DIR)
	DirAccess.make_dir_recursive_absolute(absolute_dir)
	for skin in SkinRegistry.SKINS:
		var skin_id := str(skin["id"])
		_visual.call("set_skin", skin_id)
		await _wait_frames(3)
		await RenderingServer.frame_post_draw
		var image := _viewport.get_texture().get_image()
		var path := absolute_dir.path_join("%s.png" % skin_id)
		var error := image.save_png(path)
		if error != OK:
			push_error("CharacterPortraitGenerator: could not save %s (%d)" % [path, error])
			get_tree().quit(1)
			return
		print("CHARACTER_PORTRAIT_CAPTURE ", path)
	print("CHARACTER_PORTRAITS_GENERATED count=", SkinRegistry.skin_count())
	get_tree().quit(0)


func _build_portrait_stage() -> void:
	_viewport = SubViewport.new()
	_viewport.name = "PortraitViewport"
	_viewport.size = PORTRAIT_SIZE
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)

	var world := Node3D.new()
	_viewport.add_child(world)
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.0, 0.0, 0.0, 0.0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.69, 0.88)
	env.ambient_light_energy = 1.15
	environment.environment = env
	world.add_child(environment)

	_pivot = Node3D.new()
	_pivot.name = "PortraitPivot"
	world.add_child(_pivot)
	_visual = VISUAL_SCENE.instantiate()
	_visual.name = "PortraitCharacter"
	_visual.set("build_animation_library", false)
	_pivot.add_child(_visual)
	var animation_player := _visual.call("ensure_animations", ["idle"]) as AnimationPlayer
	if animation_player != null and animation_player.has_animation("idle"):
		animation_player.play("idle", 0.0)
		animation_player.advance(0.0)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-36.0, -28.0, 0.0)
	key.light_color = Color(1.0, 0.88, 0.72)
	key.light_energy = 2.35
	world.add_child(key)
	var rim := OmniLight3D.new()
	rim.position = Vector3(1.6, 2.05, -1.4)
	rim.light_color = Color(0.30, 0.62, 1.0)
	rim.light_energy = 3.2
	rim.omni_range = 5.0
	world.add_child(rim)

	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	# Frame the head and upper shoulders, with enough transparent breathing room
	# around both ears to survive the small square lobby-card crop.
	camera.size = 1.46
	camera.look_at_from_position(
		Vector3(-2.8, 1.96, 4.1), Vector3(0.0, 1.96, 0.0), Vector3.UP)
	world.add_child(camera)
	camera.current = true


func _wait_frames(count: int) -> void:
	for _index in count:
		await get_tree().process_frame
