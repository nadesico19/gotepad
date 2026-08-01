class_name AnalysisCurve
extends Control

signal position_requested(uid: int)

const kWinrateColor: Color = Color(0.28, 0.9, 0.48, 1.0)
const kScoreColor: Color = Color(1.0, 0.78, 0.18, 1.0)
const kGridColor: Color = Color(1.0, 1.0, 1.0, 0.12)
const kCurrentPositionColor: Color = Color(0.92, 0.95, 1.0, 0.82)

var path_: PackedInt64Array = PackedInt64Array()
var results_by_uid_: Dictionary = {}
var show_score_lead_: bool = true
var current_uid_: int = -1


func set_series(
		path: PackedInt64Array,
		results_by_uid: Dictionary,
		show_score_lead: bool,
		current_uid: int
) -> void:
	path_ = path.duplicate()
	results_by_uid_ = results_by_uid.duplicate(true)
	show_score_lead_ = show_score_lead
	current_uid_ = current_uid
	queue_redraw()


func _draw() -> void:
	var plot: Rect2 = plot_rect_()
	if plot.size.x <= 1.0 or plot.size.y <= 1.0:
		return
	draw_rect(plot, Color(0.03, 0.035, 0.035, 0.72), true)
	for fraction: float in [0.0, 0.25, 0.5, 0.75, 1.0]:
		var y: float = plot.position.y + plot.size.y * fraction
		draw_line(
			Vector2(plot.position.x, y), Vector2(plot.end.x, y),
			kGridColor, 1.0, true
		)
	if path_.is_empty():
		return
	draw_curve_(plot, false)
	if show_score_lead_:
		draw_curve_(plot, true)
	draw_current_position_(plot)


func _gui_input(event: InputEvent) -> void:
	var mouse_event: InputEventMouseButton = event as InputEventMouseButton
	if mouse_event == null or not mouse_event.pressed \
			or mouse_event.button_index != MOUSE_BUTTON_LEFT:
		return
	var plot: Rect2 = plot_rect_()
	if path_.is_empty() or not plot.has_point(mouse_event.position):
		return
	var x_ratio: float = clampf(
		(mouse_event.position.x - plot.position.x) / plot.size.x,
		0.0,
		1.0
	)
	var index: int = 0 if path_.size() <= 1 else roundi(
		x_ratio * float(path_.size() - 1)
	)
	position_requested.emit(int(path_[index]))
	accept_event()


func plot_rect_() -> Rect2:
	return Rect2(Vector2(34.0, 12.0), size - Vector2(46.0, 30.0))


func draw_curve_(plot: Rect2, score_curve: bool) -> void:
	var score_extent: float = score_extent_()
	var previous: Vector2 = Vector2.ZERO
	var has_previous: bool = false
	for index in range(path_.size()):
		var uid: int = int(path_[index])
		if not results_by_uid_.has(uid):
			has_previous = false
			continue
		var result: Dictionary = Dictionary(results_by_uid_[uid])
		var value: float = float(result.get(
			"scoreLead" if score_curve else "winrate", 0.0
		))
		var x_ratio: float = 0.0 if path_.size() <= 1 \
			else float(index) / float(path_.size() - 1)
		var y_ratio: float = clampf(
			0.5 - value / (score_extent * 2.0), 0.0, 1.0
		) if score_curve else 1.0 - clampf(value, 0.0, 1.0)
		var point: Vector2 = Vector2(
			plot.position.x + plot.size.x * x_ratio,
			plot.position.y + plot.size.y * y_ratio
		)
		var color: Color = kScoreColor if score_curve else kWinrateColor
		if has_previous:
			draw_line(previous, point, color, 2.0, true)
		draw_circle(point, 2.8, color, true, -1.0, true)
		previous = point
		has_previous = true


func score_extent_() -> float:
	var extent: float = 10.0
	for uid_value: Variant in results_by_uid_:
		var result: Dictionary = Dictionary(results_by_uid_[uid_value])
		extent = maxf(extent, absf(float(result.get("scoreLead", 0.0))))
	return ceilf(extent / 5.0) * 5.0


func draw_current_position_(plot: Rect2) -> void:
	var index: int = path_.find(current_uid_)
	if index < 0:
		return
	var x_ratio: float = 0.0 if path_.size() <= 1 \
		else float(index) / float(path_.size() - 1)
	var x: float = plot.position.x + plot.size.x * x_ratio
	draw_line(
		Vector2(x, plot.position.y),
		Vector2(x, plot.end.y),
		kCurrentPositionColor,
		2.0,
		true
	)
