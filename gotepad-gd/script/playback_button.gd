class_name PlaybackButton
extends Button

@export_range(-1, 1, 1) var step_direction: int = 0

var playing_: bool = false


func set_playing(playing: bool) -> void:
	if playing_ == playing:
		return
	playing_ = playing
	tooltip_text = tr("停止播放") if playing_ else tr("播放棋局")
	queue_redraw()


func refresh_localized_texts() -> void:
	tooltip_text = tr("停止播放") if playing_ else tr("播放棋局")


func _draw() -> void:
	var icon_color: Color = Color(1.0, 1.0, 1.0, 0.45) \
		if disabled else Color(1.0, 1.0, 1.0, 0.95)
	var icon_extent: float = minf(size.x, size.y) * 0.38
	var center: Vector2 = size * 0.5
	if step_direction != 0:
		var horizontal_extent: float = icon_extent * 0.58
		var points: PackedVector2Array = PackedVector2Array([
			center + Vector2(
				-horizontal_extent * float(step_direction), -icon_extent
			),
			center + Vector2(
				horizontal_extent * float(step_direction), 0.0
			),
			center + Vector2(
				-horizontal_extent * float(step_direction), icon_extent
			)
		])
		draw_polyline(points, icon_color, 4.8, true)
		return
	if playing_:
		var square_size: float = icon_extent * 1.45
		draw_rect(
			Rect2(
				center - Vector2.ONE * square_size * 0.5,
				Vector2.ONE * square_size
			),
			icon_color
		)
		return
	var triangle: PackedVector2Array = PackedVector2Array([
		center + Vector2(-icon_extent * 0.55, -icon_extent),
		center + Vector2(-icon_extent * 0.55, icon_extent),
		center + Vector2(icon_extent, 0.0)
	])
	draw_colored_polygon(triangle, icon_color)
