extends SceneTree
# Rebuilds the exact procedural alpha mask without doing pixel loops in combat.
func _initialize() -> void:
	var mask := _build_smoke_image()
	var path := "res://textures/smoke_mask.res"
	var error := ResourceSaver.save(mask, path, ResourceSaver.FLAG_COMPRESS)
	if error != OK:
		push_error("Smoke mask save failed: %d" % error)
		quit(1)
		return
	var restored := load(path) as Image
	if restored == null or restored.get_data() != mask.get_data():
		push_error("Smoke mask round-trip changed pixels")
		quit(1)
		return
	print("SMOKE_MASK_GENERATOR: PASS exact RGBA pixels and mipmaps")
	quit()

func _build_smoke_image() -> Image:
	const TEXTURE_SIZE := 192
	var image := Image.create(TEXTURE_SIZE, TEXTURE_SIZE, false, Image.FORMAT_RGBA8)
	for y in TEXTURE_SIZE:
		for x in TEXTURE_SIZE:
			var uv := (Vector2(x, y) + Vector2(0.5, 0.5)) / float(TEXTURE_SIZE)
			var centered := (uv - Vector2(0.5, 0.5)) * Vector2(2.0, 2.35)
			var angle := atan2(centered.y, centered.x)
			var edge_noise := sin(angle * 7.0 + 0.6) * 0.055 \
				+ sin(angle * 13.0 - 1.3) * 0.028 \
				+ sin((uv.x * 9.0 + uv.y * 7.0) * TAU) * 0.018
			var distance := centered.length()
			var alpha := 1.0 - smoothstep(
				0.67 + edge_noise, 0.96 + edge_noise, distance)
			image.set_pixel(
				x, y, Color(1.0, 1.0, 1.0, clampf(alpha, 0.0, 1.0)))
	image.generate_mipmaps()
	return image

