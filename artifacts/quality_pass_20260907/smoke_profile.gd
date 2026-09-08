extends "res://tools/smoke_cloud_render_validation.gd"
func _ready() -> void:
 _run.call_deferred()
func _run() -> void:
 _build_environment()
 PlayerPrefs.settings.merge(PlayerSettingsApplier.QUALITY_PRESETS.low, true)
 GraphicsQualityManager.apply_effects_quality("low")
 DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
 Engine.max_fps = 0
 var rows: Array = []
 var order := [0.0, 3.2, 0.0, 3.2] if OS.get_environment("ONEGUN_SMOKE_ZERO_FIRST") == "1" else [3.2, 0.0, 3.2, 0.0]
 for pre_roll in order:
  await get_tree().create_timer(0.5).timeout
  var previous := Time.get_ticks_usec()
  var cloud := SMOKE_SCENE.instantiate()
  add_child(cloud)
  var construction_ms := (Time.get_ticks_usec()-previous)/1000.0
  cloud._particles.preprocess = pre_roll
  cloud._update_radius(cloud.cloud_radius)
  cloud.set_process(false)
  var samples: Array[float] = []
  var end := previous + 2500000
  while Time.get_ticks_usec() < end:
   await get_tree().process_frame
   var now := Time.get_ticks_usec()
   samples.append((now-previous)/1000.0)
   previous=now
  samples.sort()
  rows.append({"construction_ms":construction_ms,"preprocess":pre_roll,"max_ms":samples[-1],"p95_ms":samples[int(samples.size()*0.95)]})
  cloud.queue_free()
  await get_tree().process_frame
 var f := FileAccess.open("res://artifacts/quality_pass_20260907/smoke_profile_zero_first.json" if OS.get_environment("ONEGUN_SMOKE_ZERO_FIRST") == "1" else "res://artifacts/quality_pass_20260907/smoke_profile.json",FileAccess.WRITE)
 f.store_string(JSON.stringify(rows,"\t"));f.close()
 print("SMOKE_SPAWN_PROFILE ",JSON.stringify(rows))
 get_tree().quit()
