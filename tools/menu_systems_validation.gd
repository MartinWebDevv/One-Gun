extends SceneTree

# Lightweight parser/resource smoke test for the redesigned menu systems.
# Run with:
# Godot --headless --path <project> --script res://tools/menu_systems_validation.gd

const TARGETS := [
	"res://network_manager.gd",
	"res://player_prefs.gd",
	"res://UI/player_settings_applier.gd",
	"res://player_settings.gd",
	"res://player_settings.tscn",
	"res://game_setup.gd",
	"res://game_setup.tscn",
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
		settings_screen.set("_accessibility_subpage", "crosshair")
		for tab in ["shape", "behavior", "feedback"]:
			settings_screen.set("_crosshair_tab", tab)
			settings_screen.call("_rebuild_page")
			await process_frame
		print("MENU RUNTIME OK: Crosshair Shape / Behavior / Feedback tabs")
		var prefs = root.get_node("PlayerPrefs")
		var before: Dictionary = prefs.snapshot()
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
