class_name AnalysisCandidatesOverlay
extends Node2D

const kCandidateColors: Array[Color] = [
	Color(0.035, 0.30, 0.12, 0.68),
	Color(0.30, 0.68, 0.34, 0.64),
	Color(0.95, 0.73, 0.10, 0.66),
]
const kLightText: Color = Color(1.0, 1.0, 0.96, 0.98)
const kDarkText: Color = Color(0.10, 0.075, 0.02, 0.98)
const kLossColor: Color = Color(0.95, 0.48, 0.48, 0.68)
const kLossText: Color = Color(0.28, 0.025, 0.025, 0.98)

var candidates_: Array[Dictionary] = []
var played_move_loss_: Dictionary = {}
var board_size_: int = 19
var cell_size_: float = 1.0


func configure(
		candidates: Array[Dictionary],
		played_move_loss: Dictionary,
		board_size: int,
		cell_size: float
) -> void:
	candidates_ = candidates.duplicate(true)
	played_move_loss_ = played_move_loss.duplicate(true)
	board_size_ = board_size
	cell_size_ = cell_size
	visible = not candidates_.is_empty() or not played_move_loss_.is_empty()
	queue_redraw()


func clear_candidates() -> void:
	candidates_.clear()
	played_move_loss_.clear()
	visible = false
	queue_redraw()


func _draw() -> void:
	if board_size_ <= 0 or cell_size_ <= 0.0:
		return
	var font: Font = ThemeDB.fallback_font
	if font == null:
		return
	var radius: float = cell_size_ * 0.39
	var font_size: int = maxi(roundi(cell_size_ * 0.23), 1)
	for index in range(mini(candidates_.size(), kCandidateColors.size())):
		var candidate: Dictionary = candidates_[index]
		var center: Vector2 = candidate_position_(candidate)
		draw_circle(center, radius, kCandidateColors[index], true, -1.0, true)
		draw_arc(
			center, radius, 0.0, TAU, 32,
			kCandidateColors[index].lightened(0.20),
			maxf(cell_size_ * 0.035, 1.0), true
		)
		var text_color: Color = kLightText if index == 0 else kDarkText
		draw_centered_text_(
			font,
			"%.1f%%" % (float(candidate.get("winrate", 0.0)) * 100.0),
			center,
			font_size,
			text_color
		)
	if not played_move_loss_.is_empty():
		var center: Vector2 = candidate_position_(played_move_loss_)
		draw_circle(center, radius, kLossColor, true, -1.0, true)
		draw_arc(
			center, radius, 0.0, TAU, 32,
			kLossColor.lightened(0.16),
			maxf(cell_size_ * 0.035, 1.0), true
		)
		draw_centered_text_(
			font,
			"-%.1f%%" % (float(played_move_loss_.get("loss", 0.0)) * 100.0),
			center,
			font_size,
			kLossText
		)


func candidate_position_(candidate: Dictionary) -> Vector2:
	var row: int = int(candidate.get("row", 0))
	var column: int = int(candidate.get("column", 0))
	var half_extent: float = cell_size_ * float(board_size_ - 1) * 0.5
	return Vector2(
		-half_extent + cell_size_ * float(column - 1),
		-half_extent + cell_size_ * float(row - 1)
	)


func draw_centered_text_(
		font: Font,
		text: String,
		center: Vector2,
		font_size: int,
		color: Color
) -> void:
	var text_size: Vector2 = font.get_string_size(
		text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size
	)
	var baseline: Vector2 = Vector2(
		center.x - text_size.x * 0.5,
		center.y + (
			font.get_ascent(font_size) - font.get_descent(font_size)
		) * 0.5
	)
	draw_string_outline(
		font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0,
		font_size, 1, Color(0.0, 0.0, 0.0, 0.42)
	)
	draw_string(
		font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0,
		font_size, color
	)
