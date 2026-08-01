class_name OneGunHelpIcon
extends Control

# Small circular "?" help marker with a tooltip (packet Phase 1 tooltip/help
# icon). Purely informational — not focusable, but hoverable for the tooltip.

func _init() -> void:
	custom_minimum_size = Vector2(20.0, 20.0)
	mouse_filter = Control.MOUSE_FILTER_STOP  # required for tooltips
	mouse_default_cursor_shape = Control.CURSOR_HELP


func _ready() -> void:
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)


func _draw() -> void:
	var center := size * 0.5
	var radius := minf(size.x, size.y) * 0.5 - 1.0
	var tone := OneGunUI.color("gold") if _is_hovered() else OneGunUI.color("muted")
	draw_arc(center, radius, 0.0, TAU, 32, tone, 1.8, true)
	var font := OneGunUI.font_bold()
	if font != null:
		var mark_size := int(radius * 1.35)
		var text_size := font.get_string_size("?", HORIZONTAL_ALIGNMENT_LEFT, -1.0, mark_size)
		draw_string(font, center + Vector2(-text_size.x * 0.5, text_size.y * 0.32), "?",
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, mark_size, tone)


func _is_hovered() -> bool:
	return get_global_rect().has_point(get_global_mouse_position())
