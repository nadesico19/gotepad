class_name AnalysisControlButton
extends Button

@export_enum("play", "pause", "stop") var icon_kind: String = "play"


func _draw() -> void:
	var color: Color = Color(1.0, 1.0, 1.0, 0.35) \
		if disabled else Color(0.95, 0.95, 0.92, 0.96)
	var center: Vector2 = size * 0.5
	var extent: float = minf(size.x, size.y) * 0.25
	match icon_kind:
		"play":
			draw_colored_polygon(PackedVector2Array([
				center + Vector2(-extent * 0.65, -extent),
				center + Vector2(-extent * 0.65, extent),
				center + Vector2(extent, 0.0)
			]), color)
		"pause":
			var bar_size: Vector2 = Vector2(extent * 0.48, extent * 2.0)
			draw_rect(Rect2(
				center + Vector2(-extent * 0.72, -extent), bar_size
			), color)
			draw_rect(Rect2(
				center + Vector2(extent * 0.24, -extent), bar_size
			), color)
		"stop":
			draw_rect(Rect2(
				center - Vector2.ONE * extent,
				Vector2.ONE * extent * 2.0
			), color)
