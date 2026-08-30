extends Node

## Renders the real V2 character into the static profile portraits used by
## customization cards and local/online lobby rows. Run with the Forward+
## renderer (not --headless), then restart once so Godot imports the PNGs.

const SkinRegistry = preload("res://player_skin_registry.gd")
const OUTPUT_DIR := "res://UI/assets/character_portraits"
const PORTRAIT_SIZE := Vector2i(512, 512)

var _viewport: SubViewport
var _pivot: Node3D
var _visual: Node3D
var _model_id := SkinRegistry.DEFAULT_MODEL_ID


func _ready() -> void:
	_generate.call_deferred()


func _generate() -> void:
	_model_id = SkinRegistry.sanitize_model_id(
		OS.get_environment("ONEGUN_PORTRAIT_MODEL"))
	_build_portrait_stage()
	await _wait_frames(8)
	var output_dir := OUTPUT_DIR
	if _model_id != SkinRegistry.DEFAULT_MODEL_ID \
			and not SkinRegistry.uses_fixed_texture(_model_id):
		output_dir = OUTPUT_DIR.path_join(_model_id)
	var absolute_dir := ProjectSettings.globalize_path(output_dir)
	DirAccess.make_dir_recursive_absolute(absolute_dir)
	var output_suffix := OS.get_environment("ONEGUN_PORTRAIT_SUFFIX").strip_edges()
	var portrait_skins: Array = [SkinRegistry.SKINS[0]] \
		if SkinRegistry.uses_fixed_texture(_model_id) else SkinRegistry.SKINS
	for skin in portrait_skins:
		var skin_id := str(skin["id"])
		_visual.call("set_skin", skin_id)
		await _wait_frames(3)
		await RenderingServer.frame_post_draw
		var image := _viewport.get_texture().get_image()
		var file_name := "%s%s.png" % [_model_id, output_suffix] \
			if SkinRegistry.uses_fixed_texture(_model_id) else "%s.png" % skin_id
		var path := absolute_dir.path_join(file_name)
		var error := image.save_png(path)
		if error != OK:
			push_error("CharacterPortraitGenerator: could not save %s (%d)" % [path, error])
			get_tree().quit(1)
			return
		print("CHARACTER_PORTRAIT_CAPTURE ", path)
	print("CHARACTER_PORTRAITS_GENERATED model=", _model_id,
		" count=", portrait_skins.size())
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
	_pivot.rotation_degrees.y = float(OS.get_environment(
		"ONEGUN_PORTRAIT_YAW"))
	world.add_child(_pivot)
	var visual_scene := SkinRegistry.load_visual_scene(_model_id)
	if visual_scene == null:
		push_error("CharacterPortraitGenerator: selected model scene is unavailable.")
		get_tree().quit(1)
		return
	_visual = visual_scene.instantiate()
	_visual.name = "PortraitCharacter"
	_visual.set("build_animation_library", false)
	_pivot.add_child(_visual)
	var portrait_hat := OS.get_environment("ONEGUN_PORTRAIT_HAT").strip_edges()
	if portrait_hat != "" and _visual.has_method("set_hat_cosmetic"):
		_visual.call("set_hat_cosmetic", portrait_hat)
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
