@tool
class_name FixedWidthTextButton
extends Button

@export var source_text: String = ""
@export_range(1, 128, 1) var fixed_font_size: int = 16
@export_range(0.0, 64.0, 1.0) var horizontal_padding: float = 14.0
@export_range(0.0, 32.0, 1.0) var reserved_right_width: float = 0.0


func _ready() -> void:
	text = ""
	clip_text = true
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED \
			or what == NOTIFICATION_THEME_CHANGED \
			or what == NOTIFICATION_RESIZED:
		queue_redraw()


func _draw() -> void:
	if source_text.is_empty():
		return
	var display_text: String = tr(source_text)
	var font: Font = get_theme_font(&"font")
	var text_size: Vector2 = font.get_string_size(
		display_text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		fixed_font_size
	)
	if text_size.x <= 0.0 or text_size.y <= 0.0:
		return
	var available_width: float = maxf(
		size.x - horizontal_padding - reserved_right_width, 1.0
	)
	var horizontal_scale: float = minf(available_width / text_size.x, 1.0)
	var center: Vector2 = Vector2(
		(size.x - reserved_right_width) * 0.5,
		size.y * 0.5
	)
	var baseline: float = -text_size.y * 0.5 \
		+ font.get_ascent(fixed_font_size)
	draw_set_transform(center, 0.0, Vector2(horizontal_scale, 1.0))
	draw_string(
		font,
		Vector2(-text_size.x * 0.5, baseline),
		display_text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		fixed_font_size,
		font_color_()
	)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func font_color_() -> Color:
	match get_draw_mode():
		DRAW_PRESSED:
			return get_theme_color(&"font_pressed_color")
		DRAW_HOVER:
			return get_theme_color(&"font_hover_color")
		DRAW_DISABLED:
			return get_theme_color(&"font_disabled_color")
		DRAW_HOVER_PRESSED:
			return get_theme_color(&"font_hover_pressed_color")
		_:
			return get_theme_color(&"font_color")
