class_name AnalysisCandidatesOverlay
extends Node2D

const kCandidateColors: Array[Color] = [
	Color(0.035, 0.30, 0.12),
	Color(0.30, 0.68, 0.34),
	Color(0.95, 0.73, 0.10),
]
const kPrimaryCandidateCount: int = 3
const kExtraCandidateColor: Color = Color(0.975, 0.865, 0.55)
const kExtraCandidateText: Color = Color(0.10, 0.075, 0.02, 1.0)
const kLightText: Color = Color(1.0, 1.0, 0.96, 0.98)
const kDarkText: Color = Color(0.10, 0.075, 0.02, 0.98)
const kLossColor: Color = Color(0.95, 0.48, 0.48, 0.68)
const kLossText: Color = Color(0.28, 0.025, 0.025, 0.98)
const kPlayedCandidateOutlineColor: Color = Color(0.02, 0.02, 0.02, 0.96)

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
	var font_size: int = maxi(roundi(cell_size_ * 0.32), 1)
	var show_score_lead: bool = \
		SettingsStore.get_katago_show_score_lead_on_board()
	var split_winrate_font_size: int = maxi(roundi(cell_size_ * 0.25), 1)
	var split_score_font_size: int = maxi(roundi(cell_size_ * 0.22), 1)
	for index in range(candidates_.size()):
		var candidate: Dictionary = candidates_[index]
		var center: Vector2 = candidate_position_(candidate)
		var candidate_color: Color = kCandidateColors[index] \
			if index < kPrimaryCandidateCount else kExtraCandidateColor
		candidate_color.a = candidate_opacity_(index)
		draw_circle(center, radius, candidate_color, true, -1.0, true)
		draw_arc(
			center, radius, 0.0, TAU, 32,
			candidate_color.lightened(0.20),
			maxf(cell_size_ * 0.035, 1.0), true
		)
		if bool(candidate.get("is_played_next", false)) \
				and not candidate_matches_played_loss_(candidate):
			draw_arc(
				center, radius, 0.0, TAU, 48,
				kPlayedCandidateOutlineColor,
				maxf(cell_size_ * 0.035, 1.0), true
			)
		var text_color: Color = kLightText if index == 0 \
			else kDarkText if index < kPrimaryCandidateCount \
			else kExtraCandidateText
		if show_score_lead:
			draw_split_candidate_text_(
				font, candidate, center,
				split_winrate_font_size, split_score_font_size, text_color
			)
		else:
			draw_centered_text_(
				font,
				"%.1f" % (float(candidate.get("winrate", 0.0)) * 100.0),
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
			"-%.1f" % (float(played_move_loss_.get("loss", 0.0)) * 100.0),
			center,
			font_size,
			kLossText
		)


func candidate_opacity_(index: int) -> float:
	var percentage: int = SettingsStore.get_katago_primary_candidate_opacity() \
		if index < kPrimaryCandidateCount \
		else SettingsStore.get_katago_extra_candidate_opacity()
	return clampf(float(percentage) / 100.0, 0.0, 1.0)


func draw_split_candidate_text_(
		font: Font,
		candidate: Dictionary,
		center: Vector2,
		winrate_font_size: int,
		score_font_size: int,
		color: Color
) -> void:
	var vertical_offset: float = cell_size_ * 0.16
	draw_centered_text_(
		font,
		"%.1f" % (float(candidate.get("winrate", 0.0)) * 100.0),
		center - Vector2(0.0, vertical_offset),
		winrate_font_size,
		color
	)
	var separator_color: Color = color
	separator_color.a *= 0.72
	draw_line(
		center - Vector2(cell_size_ * 0.25, 0.0),
		center + Vector2(cell_size_ * 0.25, 0.0),
		separator_color,
		maxf(cell_size_ * 0.025, 1.0),
		true
	)
	draw_centered_text_(
		font,
		"%+.1f" % float(candidate.get("score_lead", 0.0)),
		center + Vector2(0.0, vertical_offset),
		score_font_size,
		color
	)


func candidate_position_(candidate: Dictionary) -> Vector2:
	var row: int = int(candidate.get("row", 0))
	var column: int = int(candidate.get("column", 0))
	var half_extent: float = cell_size_ * float(board_size_ - 1) * 0.5
	return Vector2(
		-half_extent + cell_size_ * float(column - 1),
		-half_extent + cell_size_ * float(row - 1)
	)


func candidate_matches_played_loss_(candidate: Dictionary) -> bool:
	return not played_move_loss_.is_empty() \
		and int(candidate.get("row", 0)) \
			== int(played_move_loss_.get("row", -1)) \
		and int(candidate.get("column", 0)) \
			== int(played_move_loss_.get("column", -1))


func draw_centered_text_(
		font: Font,
		text: String,
		center: Vector2,
		font_size: int,
		color: Color
) -> void:
	var actual_font_size: int = font_size
	var text_size: Vector2 = font.get_string_size(
		text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, actual_font_size
	)
	var max_text_width: float = cell_size_ * 0.70
	if text_size.x > max_text_width and text_size.x > 0.0:
		actual_font_size = maxi(floori(
			float(actual_font_size) * max_text_width / text_size.x
		), 1)
		text_size = font.get_string_size(
			text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, actual_font_size
		)
	var baseline: Vector2 = Vector2(
		center.x - text_size.x * 0.5,
		center.y + (
			font.get_ascent(actual_font_size) \
				- font.get_descent(actual_font_size)
		) * 0.5
	)
	draw_string_outline(
		font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0,
		actual_font_size, 1, Color(
			0.0, 0.0, 0.0, 0.42 * clampf(color.a / 0.98, 0.0, 1.0)
		)
	)
	draw_string(
		font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0,
		actual_font_size, color
	)
