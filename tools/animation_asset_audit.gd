extends SceneTree

# Read-only audit for staged Mixamo-style animation FBXs. It reports imported
# clip structure and compares normalized rotation curves so renamed/re-exported
# duplicates are caught before animation IDs enter the catalog.

const SOURCES := [
	"res://models/player_v2/animations/Hip Hop Dancing.fbx",
	"res://models/player_v2/animations/Swing Dancing.fbx",
]
const VICTORY_MOVE_DIRS := [
	"res://models/player_v2/animations/victory_moves/podium",
	"res://models/player_v2/animations/victory_moves/round",
]
const SAMPLE_COUNT := 31

var _clips: Array[Dictionary] = []
var _failed := false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var paths: Array[String] = []
	paths.assign(SOURCES)
	for directory in VICTORY_MOVE_DIRS:
		for file_name in DirAccess.get_files_at(directory):
			if file_name.get_extension().to_lower() == "fbx":
				paths.append(directory.path_join(file_name))
	paths.sort()
	for path in paths:
		_audit_path(path)
	print("ANIMATION_CURVE_COMPARISONS")
	for left_index in _clips.size():
		for right_index in range(left_index + 1, _clips.size()):
			var comparison := _compare_clips(
				_clips[left_index], _clips[right_index])
			if float(comparison.get("mean_degrees", 999.0)) <= 8.0:
				print("SIMILAR|%s|%s|mean_deg=%.4f|max_deg=%.4f|tracks=%d" % [
					str(_clips[left_index]["name"]),
					str(_clips[right_index]["name"]),
					float(comparison["mean_degrees"]),
					float(comparison["max_degrees"]),
					int(comparison["tracks"]),
				])
	print("ANIMATION_ASSET_AUDIT_%s clips=%d" % [
		"FAILED" if _failed else "OK", _clips.size()])
	quit(1 if _failed else 0)


func _audit_path(path: String) -> void:
	var packed := load(path) as PackedScene
	if packed == null:
		_fail("could not load %s" % path)
		return
	var instance := packed.instantiate()
	root.add_child(instance)
	var player := instance.find_child(
		"AnimationPlayer", true, false) as AnimationPlayer
	var animation := _first_animation(player)
	if animation == null:
		_fail("no imported animation in %s" % path)
		instance.queue_free()
		return
	var clip := _sample_clip(path.get_file(), animation)
	_clips.append(clip)
	print("CLIP|%s|length=%.4f|tracks=%d|keys=%d|rotation_tracks=%d|fingerprint=%s" % [
		path.get_file(), animation.length, animation.get_track_count(),
		int(clip["key_count"]), int(clip["rotation_tracks"]),
		str(clip["fingerprint"]),
	])
	instance.queue_free()


func _sample_clip(file_name: String, animation: Animation) -> Dictionary:
	var samples := {}
	var key_count := 0
	var fingerprint_parts: Array[String] = []
	for track_index in animation.get_track_count():
		key_count += animation.track_get_key_count(track_index)
		if animation.track_get_type(track_index) != Animation.TYPE_ROTATION_3D:
			continue
		var track_path := str(animation.track_get_path(track_index))
		var bone_name := track_path.get_slice(":", track_path.get_slice_count(":") - 1)
		var rotations: Array[Quaternion] = []
		for sample_index in SAMPLE_COUNT:
			var time := animation.length * float(sample_index) / float(SAMPLE_COUNT - 1)
			var rotation := animation.rotation_track_interpolate(track_index, time)
			rotations.append(rotation.normalized())
			fingerprint_parts.append("%s:%.4f,%.4f,%.4f,%.4f" % [
				bone_name, snappedf(rotation.x, 0.0001),
				snappedf(rotation.y, 0.0001), snappedf(rotation.z, 0.0001),
				snappedf(rotation.w, 0.0001),
			])
		samples[bone_name] = rotations
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update("|".join(fingerprint_parts).to_utf8_buffer())
	return {
		"name": file_name,
		"length": animation.length,
		"key_count": key_count,
		"rotation_tracks": samples.size(),
		"samples": samples,
		"fingerprint": context.finish().hex_encode(),
	}


func _compare_clips(left: Dictionary, right: Dictionary) -> Dictionary:
	var left_samples: Dictionary = left.get("samples", {})
	var right_samples: Dictionary = right.get("samples", {})
	var total := 0.0
	var maximum := 0.0
	var count := 0
	var matching_tracks := 0
	for bone_name in left_samples:
		if not right_samples.has(bone_name):
			continue
		matching_tracks += 1
		var left_rotations: Array = left_samples[bone_name]
		var right_rotations: Array = right_samples[bone_name]
		for sample_index in mini(left_rotations.size(), right_rotations.size()):
			var left_rotation: Quaternion = left_rotations[sample_index]
			var right_rotation: Quaternion = right_rotations[sample_index]
			var dot := clampf(absf(left_rotation.dot(right_rotation)), 0.0, 1.0)
			var degrees := rad_to_deg(2.0 * acos(dot))
			total += degrees
			maximum = maxf(maximum, degrees)
			count += 1
	return {
		"mean_degrees": total / maxf(float(count), 1.0),
		"max_degrees": maximum,
		"tracks": matching_tracks,
	}


func _first_animation(player: AnimationPlayer) -> Animation:
	if player == null:
		return null
	for animation_name in player.get_animation_list():
		if animation_name != "RESET":
			return player.get_animation(animation_name)
	return null


func _fail(message: String) -> void:
	_failed = true
	push_error("ANIMATION_ASSET_AUDIT: %s" % message)
