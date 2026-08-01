class_name NoteSymbolButton
extends Button

@export var symbol_code: String = "TR"


func _ready() -> void:
	text = ""
	toggled.connect(on_toggled_)


func _draw() -> void:
	var color: Color = Color(1.0, 1.0, 1.0, 0.42) \
		if disabled else Color(1.0, 0.84, 0.28, 1.0) \
		if button_pressed else Color(0.94, 0.94, 0.94, 0.96)
	var extent: float = minf(size.x, size.y) * 0.29
	var line_width: float = maxf(2.4, minf(size.x, size.y) * 0.065)
	if button_pressed:
		line_width *= 1.35
	var center: Vector2 = size * 0.5
	match symbol_code:
		"TR":
			draw_triangle_(
				center + Vector2(0.0, extent * 0.25),
				extent,
				color,
				line_width
			)
		"SQ":
			var square_extent: float = extent * 0.84
			draw_rect(
				Rect2(
					center - Vector2.ONE * square_extent,
					Vector2.ONE * square_extent * 2.0
				),
				color, false, line_width, true
			)
		"CR":
			draw_arc(center, extent, 0.0, TAU, 40, color, line_width, true)
		"MA":
			draw_cross_(center, extent, color, line_width)


func draw_triangle_(
		center: Vector2, extent: float, color: Color, line_width: float
) -> void:
	var triangle: PackedVector2Array = PackedVector2Array([
		center + Vector2(0.0, -extent),
		center + Vector2(extent * 0.866, extent * 0.5),
		center + Vector2(-extent * 0.866, extent * 0.5),
		center + Vector2(0.0, -extent)
	])
	draw_polyline(triangle, color, line_width, true)


func draw_cross_(
		center: Vector2, extent: float, color: Color, line_width: float
) -> void:
	var diagonal: Vector2 = Vector2.ONE * extent * 0.78
	draw_line(center - diagonal, center + diagonal, color, line_width, true)
	draw_line(
		center + Vector2(-diagonal.x, diagonal.y),
		center + Vector2(diagonal.x, -diagonal.y),
		color, line_width, true
	)


func on_toggled_(_pressed: bool) -> void:
	queue_redraw()
