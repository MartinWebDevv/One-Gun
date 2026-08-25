extends SceneTree

# Lightweight parser/resource smoke test for the redesigned menu systems.
# Run with:
# Godot --headless --path <project> --script res://tools/menu_systems_validation.gd

const TARGETS := [
	"res://audio_manager.gd",
	"res://map_registry.gd",
	"res://network_manager.gd",
	"res://player_prefs.gd",
	"res://graphics_quality_manager.gd",
	"res://UI/player_settings_applier.gd",
	"res://player_settings.gd",
	"res://player_settings.tscn",
	"res://game_setup.gd",
	"res://game_setup.tscn",
	"res://supabase/supabase_manager.gd",
	"res://UI/supabase_overlay.gd",
	"res://UI/character_customization_overlay.gd",
	"res://UI/progression_road_overlay.gd",
	"res://lobby_map_preview.gd",
	"res://menu_map_cycler.gd",
	"res://maps/test/title_bg_map.tscn",
	"res://main_menu.gd",
	"res://pause_menu.gd",
	"res://UI/accessibility_manager.gd",
	"res://UI/crosshair_renderer.gd",
	"res://crosshair.gd",
	"res://hit_marker.gd",
	"res://character_body_3d.gd",
	"res://bullet.gd",
	"res://melee_weapon.gd",
]

class ReloadGunStub extends Node:
	var can_fire := false
	func get_reload_progress() -> float: return 0.42


func _initialize() -> void:
	_validate.call_deferred()


func _validate() -> void:
	var failed := false
	for path in TARGETS:
		var resource := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE)
		if resource == null:
			push_error("Menu validation failed to load: %s" % path)
			failed = true
		else:
			print("MENU VALIDATION OK: %s" % path)
	if not failed:
		var scene := load("res://player_settings.tscn") as PackedScene
		var settings_screen := scene.instantiate()
		settings_screen.is_overlay = true
		root.add_child(settings_screen)
		await process_frame
		await process_frame
		for category in ["Audio", "Gameplay", "Video", "Controls", "Accessibility"]:
			settings_screen.call("_select_category", category)
			await process_frame
		print("MENU RUNTIME OK: Player Settings categories")
		settings_screen.call("_select_category", "Audio")
		await process_frame
		var ceremony_slider_found := false
		for label in settings_screen.find_children("*", "Label", true, false):
			if str(label.text) == "Ceremony Volume":
				ceremony_slider_found = true
				break
		if not ceremony_slider_found:
			push_error("Menu validation: Audio settings did not expose Ceremony Volume")
			failed = true
		else:
			print("MENU RUNTIME OK: Ceremony Volume slider is present")
		settings_screen.set("_accessibility_subpage", "crosshair")
		for tab in ["shape", "behavior", "feedback"]:
			settings_screen.set("_crosshair_tab", tab)
			settings_screen.call("_rebuild_page")
			await process_frame
		print("MENU RUNTIME OK: Crosshair Shape / Behavior / Feedback tabs")
		var prefs = root.get_node("PlayerPrefs")
		var before: Dictionary = prefs.snapshot()
		var audio = root.get_node("AudioManager")
		var ceremony_bus_index := AudioServer.get_bus_index("Ceremony")
		var ceremony_player := audio.get_node_or_null("CeremonyPlayer") as AudioStreamPlayer
		if ceremony_bus_index < 0 or ceremony_player == null or ceremony_player.bus != &"Ceremony":
			push_error("Menu validation: dedicated Ceremony audio bus/player is incomplete")
			failed = true
		else:
			audio.set_ceremony_volume(0.5)
			var expected_ceremony_db := linear_to_db(0.25)
			if not is_equal_approx(AudioServer.get_bus_volume_db(ceremony_bus_index), expected_ceremony_db):
				push_error("Menu validation: Ceremony Volume did not control its bus")
				failed = true
			else:
				print("MENU RUNTIME OK: dedicated Ceremony bus follows its saved mix control")
			audio.play_music("menu", 0.0)
			await process_frame
			var music_player := audio.get_node_or_null("MusicPlayer") as AudioStreamPlayer
			var preview_started := bool(audio.play_ceremony_preview(
				"winners_circle_deep_orbit", 0.2))
			if not preview_started or music_player == null or not music_player.stream_paused:
				push_error("Menu validation: ceremony preview did not pause menu music")
				failed = true
			audio.stop_ceremony_preview()
			if music_player != null and music_player.stream_paused:
				push_error("Menu validation: stopping ceremony preview did not resume menu music")
				failed = true
			else:
				print("MENU RUNTIME OK: ceremony preview pauses and resumes menu music")
			audio.stop_music(0.0)
			audio.set_ceremony_volume(float(before.get("ceremony_volume", 0.8)))
		var alphabetical := MapRegistry.sorted_indices("alphabetical")
		var newest := MapRegistry.sorted_indices("newest")
		if alphabetical.is_empty() or newest.is_empty() or str(MapRegistry.MAPS[newest[0]]["name"]) != "Neon Circuit":
			push_error("Menu validation: map sorting modes are incomplete")
			failed = true
		else:
			print("MENU RUNTIME OK: alphabetical and newest map sorting")
		var preview_descriptor := {"type": "key", "code": KEY_F12}
		settings_screen.call("_store_bindings", "p1_move_forward",
			"keyboard_mouse", [preview_descriptor])
		var preview_bound := InputMap.action_get_events("p1_move_forward").any(func(event):
			return event is InputEventKey \
				and int(event.physical_keycode if event.physical_keycode != 0 else event.keycode) == KEY_F12)
		if not preview_bound:
			push_error("Menu validation: pending key rebind did not apply to live InputMap")
			failed = true
		var pending := before.duplicate(true)
		pending["master_volume"] = 0.123
		settings_screen.set("_pending", pending)
		settings_screen.call("_cancel_and_close")
		if prefs.snapshot() != before:
			push_error("Menu validation: Cancel mutated active PlayerPrefs")
			failed = true
		else:
			print("MENU RUNTIME OK: Cancel preserved active preferences")
		var preview_still_bound := InputMap.action_get_events("p1_move_forward").any(func(event):
			return event is InputEventKey \
				and int(event.physical_keycode if event.physical_keycode != 0 else event.keycode) == KEY_F12)
		if preview_still_bound:
			push_error("Menu validation: Cancel did not restore saved key bindings")
			failed = true
		else:
			print("MENU RUNTIME OK: live key rebind preview and Cancel rollback")
		var axis_descriptor := {"type": "joy_axis", "axis": 2, "direction": -1}
		var axis_event = prefs.descriptor_to_event(axis_descriptor)
		if not axis_event is InputEventJoypadMotion or axis_event.axis != 2 or axis_event.axis_value >= 0.0:
			push_error("Menu validation: gamepad axis descriptor round-trip failed")
			failed = true
		else:
			print("MENU RUNTIME OK: input descriptor supports gamepad axes")
		var crosshair_script = load("res://UI/crosshair_renderer.gd")
		var expected_segments := {"classic": 4, "dot": 0, "ring": 1, "cross_dot": 4, "brackets": 6, "chevron": 2, "minimal": 2, "hidden": 0}
		for style in expected_segments:
			if crosshair_script.shape_segment_count(style) != expected_segments[style]:
				push_error("Menu validation: crosshair geometry mismatch for %s" % style)
				failed = true
		if crosshair_script.normalized_reload(0.5, 2.0) != 0.25 or crosshair_script.normalized_reload(3.0, 2.0) != 1.0:
			push_error("Menu validation: reload normalization failed")
			failed = true
		else:
			print("MENU RUNTIME OK: crosshair geometry and reload normalization")
		var crosshair = crosshair_script.new()
		var player_stub := Node.new()
		var gun_stub := ReloadGunStub.new()
		player_stub.add_child(gun_stub)
		crosshair.set("player", player_stub)
		crosshair.set("_cached_gun", gun_stub)
		if not is_equal_approx(float(crosshair.call("_reload_progress", prefs.snapshot())), 0.42):
			push_error("Menu validation: live gun reload progress was not consumed")
			failed = true
		else:
			print("MENU RUNTIME OK: live gun reload progress adapter")
		player_stub.free()
		crosshair.free()
		var normalized: Dictionary = prefs.call("_normalize", {"crosshair_style": "invalid", "ui_scale": 9.0, "hit_marker_duration": -4.0})
		if normalized["crosshair_style"] != "classic" or normalized["ui_scale"] != 1.25 or normalized["hit_marker_duration"] != 0.08:
			push_error("Menu validation: accessibility preference normalization failed")
			failed = true
		else:
			print("MENU RUNTIME OK: accessibility/crosshair preference migration defaults")
		var null_name: Dictionary = prefs.call("_normalize", {"player_name": null})
		var placeholder_name: Dictionary = prefs.call(
			"_normalize", {"player_name": "<null>"})
		if str(null_name.get("player_name", "")) != "Player 1" \
				or str(placeholder_name.get("player_name", "")) != "Player 1":
			push_error("Menu validation: legacy null Display Name did not normalize")
			failed = true
		else:
			print("MENU RUNTIME OK: null Display Name migration fallback")
		var normalized_audio: Dictionary = prefs.call("_normalize", {"ceremony_volume": 4.0})
		if not is_equal_approx(float(normalized_audio["ceremony_volume"]), 1.0):
			push_error("Menu validation: Ceremony Volume preference normalization failed")
			failed = true
		else:
			print("MENU RUNTIME OK: Ceremony Volume defaults/migration schema")
		var migrated_low: Dictionary = prefs.call("_normalize", {"quality_preset": "low"})
		if migrated_low["effects_quality"] != "low":
			push_error("Menu validation: pre-effects-tier Low preset did not migrate to Low effects")
			failed = true
		var applier = load("res://UI/player_settings_applier.gd")
		var low_preset: Dictionary = {}
		applier.apply_quality_preset(low_preset, "low")
		if low_preset.get("effects_quality") != "low" or not is_equal_approx(float(low_preset.get("render_scale", 0.0)), 0.75):
			push_error("Menu validation: Low preset does not include its effects/render-scale policy")
			failed = true
		else:
			print("MENU RUNTIME OK: graphics preset schema and version-4 migration")
		var quality_root := Node3D.new()
		var world_environment := WorldEnvironment.new()
		var authored_environment := Environment.new()
		authored_environment.ssao_enabled = true
		authored_environment.ssil_enabled = true
		authored_environment.ssr_enabled = true
		authored_environment.volumetric_fog_enabled = true
		authored_environment.glow_enabled = true
		world_environment.environment = authored_environment
		quality_root.add_child(world_environment)
		var local_light := OmniLight3D.new()
		local_light.shadow_enabled = true
		quality_root.add_child(local_light)
		var sun := DirectionalLight3D.new()
		sun.shadow_enabled = true
		sun.directional_shadow_max_distance = 120.0
		quality_root.add_child(sun)
		var particles := GPUParticles3D.new()
		particles.amount = 100
		particles.amount_ratio = 1.0
		quality_root.add_child(particles)
		var quality_camera := Camera3D.new()
		var camera_attributes := CameraAttributesPractical.new()
		camera_attributes.dof_blur_far_enabled = true
		quality_camera.attributes = camera_attributes
		quality_root.add_child(quality_camera)
		root.add_child(quality_root)
		await process_frame
		var quality_manager = root.get_node("GraphicsQualityManager")
		var pending_low_viewport := SubViewport.new()
		pending_low_viewport.size = Vector2i(320, 180)
		root.add_child(pending_low_viewport)
		applier.apply_viewport(pending_low_viewport, low_preset)
		quality_manager.apply_effects_quality("low")
		if not is_equal_approx(pending_low_viewport.scaling_3d_scale, 0.75) \
				or pending_low_viewport.msaa_3d != Viewport.MSAA_DISABLED \
				or pending_low_viewport.screen_space_aa != Viewport.SCREEN_SPACE_AA_DISABLED:
			push_error("Menu validation: effects preview overwrote pending Low viewport settings")
			failed = true
		else:
			print("MENU RUNTIME OK: pending Low viewport settings survive effects preview")
		pending_low_viewport.queue_free()
		var low_environment := world_environment.environment
		if low_environment.ssao_enabled or low_environment.ssil_enabled or low_environment.ssr_enabled \
				or low_environment.volumetric_fog_enabled or low_environment.glow_enabled \
				or local_light.shadow_enabled or sun.directional_shadow_max_distance > 35.01 \
				or not is_equal_approx(particles.amount_ratio, 0.45) \
				or (quality_camera.attributes as CameraAttributesPractical).dof_blur_far_enabled:
			push_error("Menu validation: Low effects policy was not applied completely")
			failed = true
		quality_manager.apply_effects_quality("high")
		var restored_environment := world_environment.environment
		if not restored_environment.ssao_enabled or not restored_environment.ssil_enabled \
				or not restored_environment.ssr_enabled or not restored_environment.volumetric_fog_enabled \
				or not restored_environment.glow_enabled or not local_light.shadow_enabled \
				or not is_equal_approx(sun.directional_shadow_max_distance, 120.0) \
				or not is_equal_approx(particles.amount_ratio, 1.0) \
				or not (quality_camera.attributes as CameraAttributesPractical).dof_blur_far_enabled:
			push_error("Menu validation: High did not restore authored render values")
			failed = true
		else:
			print("MENU RUNTIME OK: Low effects scaling and High authored-value restoration")
		quality_root.queue_free()
		await process_frame
		var saved_effects_quality := str(prefs.settings["effects_quality"])
		prefs.settings["effects_quality"] = "low"
		var preview_host := Control.new()
		root.add_child(preview_host)
		var lobby_preview = load("res://lobby_map_preview.gd").new()
		root.add_child(lobby_preview)
		var map_registry = load("res://map_registry.gd")
		lobby_preview.setup(preview_host, map_registry.MAPS)
		lobby_preview.apply(1, 0)
		await process_frame
		if lobby_preview.get("_viewport") == null or lobby_preview.get("_preview_root") == null \
				or lobby_preview.current_index() != 0:
			push_error("Menu validation: Low lobby preview did not retain its live 3D viewport")
			failed = true
		else:
			print("MENU RUNTIME OK: Low lobby retains the live 3D map preview")
		lobby_preview.queue_free()
		preview_host.queue_free()
		var low_viewport := SubViewport.new()
		low_viewport.size = Vector2i(320, 180)
		root.add_child(low_viewport)
		var low_camera := Camera3D.new()
		low_viewport.add_child(low_camera)
		var low_menu_host := Control.new()
		root.add_child(low_menu_host)
		var low_fade := ColorRect.new()
		low_menu_host.add_child(low_fade)
		var low_cycler = load("res://menu_map_cycler.gd").new()
		low_viewport.add_child(low_cycler)
		low_cycler.setup(low_viewport, low_camera, low_fade, low_menu_host, false)
		await process_frame
		var low_maps: Array = low_cycler.get("_maps")
		if low_maps.size() != 1 or str(low_maps[0].get("scene_path", "")) != "res://maps/test/title_bg_map.tscn":
			push_error("Menu validation: Low main menu did not select the lightweight live world")
			failed = true
		else:
			print("MENU RUNTIME OK: Low main menu uses the lightweight live title world")
		low_viewport.queue_free()
		low_menu_host.queue_free()
		prefs.settings["effects_quality"] = saved_effects_quality
		quality_manager.apply_effects_quality(saved_effects_quality)
		await process_frame
		var accessibility_script = load("res://UI/accessibility_manager.gd")
		if accessibility_script.motion_blur_vector(Vector3(2.0, 0.5, 0.0), Vector2(0.1, -0.05)).is_zero_approx():
			push_error("Menu validation: motion-dependent blur vector failed")
			failed = true
		else:
			print("MENU RUNTIME OK: motion blur responds to camera transform deltas")
		var accessibility = root.get_node("AccessibilityManager")
		var policy: Dictionary = prefs.snapshot()
		policy["reduced_motion"] = false
		policy["screen_shake_intensity"] = 0.25
		policy["camera_bob_intensity"] = 0.4
		policy["reduce_flashing"] = true
		accessibility.preview_policy(policy)
		if not is_equal_approx(accessibility.screen_shake_scale(), 0.25) or not is_equal_approx(accessibility.camera_bob_scale(), 0.4) or accessibility.allow_flash():
			push_error("Menu validation: accessibility live policy preview failed")
			failed = true
		else:
			print("MENU RUNTIME OK: shake/bob/flash live policy preview")
		accessibility.apply_all()
		var marker_script = load("res://hit_marker.gd")
		if marker_script.should_replace("gun_elimination", "gun_hit") or not marker_script.should_replace("gun_hit", "melee_elimination"):
			push_error("Menu validation: elimination marker precedence failed")
			failed = true
		else:
			print("MENU RUNTIME OK: non-stacking marker elimination precedence")
		var confirm = load("res://UI/components/one_gun_confirm_button.gd").new()
		confirm.text = "LEAVE MATCH"
		root.add_child(confirm)
		await process_frame
		confirm.call("_on_confirm_pressed")
		if not confirm.is_armed():
			push_error("Menu validation: two-click confirm did not arm")
			failed = true
		confirm.reset_confirm()
		if confirm.is_armed():
			push_error("Menu validation: confirmation reset failed")
			failed = true
		else:
			print("MENU RUNTIME OK: destructive inline confirmation arm/reset")
		confirm.queue_free()
		var pause_menu := Control.new()
		pause_menu.set_script(load("res://pause_menu.gd"))
		root.add_child(pause_menu)
		await process_frame
		var action_ids := _collect_action_ids(pause_menu)
		if "resume" not in action_ids or "player_settings" not in action_ids or "return_lobby" not in action_ids or "leave_match" not in action_ids:
			push_error("Menu validation: local pause actions incomplete")
			failed = true
		else:
			print("MENU RUNTIME OK: local pause cabinet actions and no restart")
		var pause_manager = root.get_node("PauseManager")
		pause_manager.pause()
		if not paused or not pause_menu.visible:
			push_error("Menu validation: local pause did not pause SceneTree")
			failed = true
		pause_manager.resume()
		if paused or pause_menu.visible:
			push_error("Menu validation: local resume did not restore SceneTree")
			failed = true
		else:
			print("MENU RUNTIME OK: local pause/resume semantics")
		pause_menu.set("_capture_role", "pause_host")
		pause_menu.call("_build_ui")
		await process_frame
		action_ids = _collect_action_ids(pause_menu)
		if "return_lobby" not in action_ids or "leave_match" not in action_ids:
			push_error("Menu validation: online host pause authority actions incomplete")
			failed = true
		pause_menu.set("_capture_role", "pause_guest")
		pause_menu.call("_build_ui")
		await process_frame
		action_ids = _collect_action_ids(pause_menu)
		if "return_lobby" in action_ids or "leave_match" not in action_ids:
			push_error("Menu validation: online guest received host-only action")
			failed = true
		else:
			print("MENU RUNTIME OK: online host/guest pause authority split")
		pause_menu.queue_free()
		settings_screen.queue_free()
		await process_frame
	if not failed:
		print("MENU SYSTEMS VALIDATION: PASS")
	quit(1 if failed else 0)


func _collect_action_ids(root: Node) -> Array[String]:
	var result: Array[String] = []
	for button in root.find_children("*", "Button", true, false):
		var action_id := str(button.get_meta("action_id", ""))
		if action_id != "":
			result.append(action_id)
	return result
