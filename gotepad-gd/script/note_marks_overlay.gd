extends Node2D

const kSequentialMarkLetters: String = \
	"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
const kMarkColor: Color = Color(1.0, 0.82, 0.24, 1.0)
const kMarkOutlineColor: Color = Color(0.12, 0.08, 0.03, 0.88)

var sequential_marks_: Array[Dictionary] = []
var symbol_marks_: Array[Dictionary] = []
var board_size_: int = 19
var cell_size_: float = 1.0


func configure(
		sequential_marks: Array[Dictionary],
		symbol_marks: Array[Dictionary],
		board_size: int,
		cell_size: float
) -> void:
	sequential_marks_ = sequential_marks.duplicate(true)
	symbol_marks_ = symbol_marks.duplicate(true)
	board_size_ = board_size
	cell_size_ = cell_size
	queue_redraw()


func _draw() -> void:
	if board_size_ <= 0 or cell_size_ <= 0.0:
		return
	var canvas_scale: float = maxf(
		absf(get_global_transform_with_canvas().get_scale().x), 0.001
	)
	var outline_width: float = 4.0 / canvas_scale
	var mark_width: float = 2.0 / canvas_scale
	for mark: Dictionary in symbol_marks_:
		draw_symbol_(
			str(mark.get("symbol", "")),
			mark_position_(mark),
			outline_width,
			mark_width
		)
	draw_sequential_marks_()


func draw_sequential_marks_() -> void:
	var font: Font = ThemeDB.fallback_font
	if font == null:
		return
	var font_size: int = maxi(roundi(cell_size_ * 0.48), 1)
	var outline_size: int = maxi(roundi(cell_size_ * 0.09), 1)
	for index in range(mini(sequential_marks_.size(), kSequentialMarkLetters.length())):
		draw_centered_text_(
			font,
			kSequentialMarkLetters.substr(index, 1),
			mark_position_(sequential_marks_[index]),
			font_size,
			outline_size
		)


func draw_symbol_(
		symbol: String,
		center: Vector2,
		outline_width: float,
		mark_width: float
) -> void:
	var radius: float = cell_size_ * 0.27
	if symbol != "SQ":
		radius *= 1.12
	match symbol:
		"TR":
			draw_triangle_(center, radius, outline_width, mark_width)
		"SQ":
			draw_square_(center, radius, outline_width, mark_width)
		"CR":
			draw_circle_mark_(center, radius, outline_width, mark_width)
		"MA":
			draw_cross_(center, radius, outline_width, mark_width)


func draw_triangle_(
		center: Vector2, radius: float, outline_width: float, mark_width: float
) -> void:
	var triangle: PackedVector2Array = PackedVector2Array([
		center + Vector2(0.0, -radius),
		center + Vector2(radius * 0.87, radius * 0.5),
		center + Vector2(-radius * 0.87, radius * 0.5),
		center + Vector2(0.0, -radius)
	])
	draw_polyline(triangle, kMarkOutlineColor, outline_width, true)
	draw_polyline(triangle, kMarkColor, mark_width, true)


func draw_square_(
		center: Vector2, radius: float, outline_width: float, mark_width: float
) -> void:
	var square: Rect2 = Rect2(
		center - Vector2.ONE * radius, Vector2.ONE * radius * 2.0
	)
	draw_rect(square, kMarkOutlineColor, false, outline_width, true)
	draw_rect(square, kMarkColor, false, mark_width, true)


func draw_circle_mark_(
		center: Vector2, radius: float, outline_width: float, mark_width: float
) -> void:
	draw_arc(
		center, radius, 0.0, TAU, 32, kMarkOutlineColor, outline_width, true
	)
	draw_arc(center, radius, 0.0, TAU, 32, kMarkColor, mark_width, true)


func draw_cross_(
		center: Vector2, radius: float, outline_width: float, mark_width: float
) -> void:
	var diagonal: Vector2 = Vector2.ONE * radius * 0.78
	var from_1: Vector2 = center - diagonal
	var to_1: Vector2 = center + diagonal
	var from_2: Vector2 = center + Vector2(-diagonal.x, diagonal.y)
	var to_2: Vector2 = center + Vector2(diagonal.x, -diagonal.y)
	draw_line(from_1, to_1, kMarkOutlineColor, outline_width, true)
	draw_line(from_2, to_2, kMarkOutlineColor, outline_width, true)
	draw_line(from_1, to_1, kMarkColor, mark_width, true)
	draw_line(from_2, to_2, kMarkColor, mark_width, true)


func draw_centered_text_(
		font: Font,
		text: String,
		center: Vector2,
		font_size: int,
		outline_size: int
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
		font_size, outline_size, kMarkOutlineColor
	)
	draw_string(
		font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0,
		font_size, kMarkColor
	)


func mark_position_(mark: Dictionary) -> Vector2:
	var row: int = int(mark.get("row", 0))
	var column: int = int(mark.get("column", 0))
	var half_extent: float = cell_size_ * float(board_size_ - 1) * 0.5
	return Vector2(
		-half_extent + cell_size_ * float(column - 1),
		-half_extent + cell_size_ * float(row - 1)
	)
