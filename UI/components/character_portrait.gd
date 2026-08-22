class_name CharacterPortrait
extends TextureRect

const SkinRegistry = preload("res://player_skin_registry.gd")

@export var skin_id := SkinRegistry.DEFAULT_SKIN_ID:
	set(value):
		skin_id = SkinRegistry.sanitize_skin_id(value)
		_refresh_texture()
@export var model_id := SkinRegistry.DEFAULT_MODEL_ID:
	set(value):
		model_id = SkinRegistry.sanitize_model_id(value)
		_refresh_texture()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_refresh_texture()


func set_skin(requested_id: String) -> void:
	skin_id = requested_id


func set_model(requested_id: String) -> void:
	model_id = requested_id


func set_appearance(requested_skin_id: String, requested_model_id: String) -> void:
	skin_id = SkinRegistry.sanitize_skin_id(requested_skin_id)
	model_id = SkinRegistry.sanitize_model_id(requested_model_id)
	_refresh_texture()


func _refresh_texture() -> void:
	texture = SkinRegistry.load_portrait(skin_id, model_id)
	tooltip_text = "%s %s character portrait" % [
		SkinRegistry.display_name(skin_id),
		SkinRegistry.model_display_name(model_id),
	]
