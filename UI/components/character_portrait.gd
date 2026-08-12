class_name CharacterPortrait
extends TextureRect

const SkinRegistry = preload("res://player_skin_registry.gd")

@export var skin_id := SkinRegistry.DEFAULT_SKIN_ID:
	set(value):
		skin_id = SkinRegistry.sanitize_skin_id(value)
		_refresh_texture()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_refresh_texture()


func set_skin(requested_id: String) -> void:
	skin_id = requested_id


func _refresh_texture() -> void:
	texture = SkinRegistry.load_portrait(skin_id)
	tooltip_text = "%s character portrait" % SkinRegistry.display_name(skin_id)
