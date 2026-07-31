class_name SetupBranchCard
extends Button

signal branch_hovered(uid: int)
signal branch_unhovered(uid: int)
signal branch_selected(uid: int)

const kCardSize: Vector2 = Vector2(320.0, 124.0)
const kThumbnailSize: float = 104.0

var uid_: int = -1
var board_size_: int = 19
var states_: PackedInt32Array = PackedInt32Array()
var title_: String = ""
var summary_: String = ""
var hovered_: bool = false


func _ready() -> void:
	custom_minimum_size = kCardSize
	focus_mode = Control.FOCUS_NONE
	flat = true
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	mouse_entered.connect(on_mouse_entered_)
	mouse_exited.connect(on_mouse_exited_)
	pressed.connect(on_pressed_)


func setup(
	uid: int,
	board_size: int,
	states: PackedInt32Array,
	title: String,
	summary: String
) -> void:
	uid_ = uid
	board_size_ = board_size
	states_ = states
	title_ = title
	summary_ = summary
	queue_redraw()


func on_mouse_entered_() -> void:
	hovered_ = true
	queue_redraw()
	branch_hovered.emit(uid_)


func on_mouse_exited_() -> void:
	hovered_ = false
	queue_redraw()
	branch_unhovered.emit(uid_)


func on_pressed_() -> void:
	branch_selected.emit(uid_)


func _draw() -> void:
	var card_rect: Rect2 = Rect2(Vector2.ZERO, size)
	var background: Color = Color(0.25, 0.20, 0.13, 0.96) \
		if hovered_ else Color(0.10, 0.085, 0.065, 0.94)
	draw_style_box(make_card_style_(background), card_rect)
	draw_thumbnail_(Rect2(Vector2(10.0, 10.0), Vector2.ONE * kThumbnailSize))
	var font: Font = ThemeDB.fallback_font
	if font == null:
		return
	draw_string(
		font, Vector2(128.0, 48.0), title_,
		HORIZONTAL_ALIGNMENT_LEFT, 178.0, 18,
		Color(1.0, 0.91, 0.70, 1.0)
	)
	draw_string(
		font, Vector2(128.0, 80.0), summary_,
		HORIZONTAL_ALIGNMENT_LEFT, 178.0, 15,
		Color(0.88, 0.88, 0.84, 1.0)
	)


func make_card_style_(background: Color) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = Color(1.0, 0.82, 0.42, 0.55 if hovered_ else 0.22)
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	return style


func draw_thumbnail_(board_rect: Rect2) -> void:
	draw_rect(board_rect, Color("bd8952"), true)
	draw_rect(board_rect, Color("4a2d17"), false, 1.5, true)
	var inset: float = 7.0
	var grid_extent: float = kThumbnailSize - inset * 2.0
	var denominator: float = float(maxi(board_size_ - 1, 1))
	var cell_size: float = grid_extent / denominator
	var top_left: Vector2 = board_rect.position + Vector2.ONE * inset
	if board_size_ > 1:
		for index in range(board_size_):
			var offset: float = float(index) * cell_size
			draw_line(
				top_left + Vector2(0.0, offset),
				top_left + Vector2(grid_extent, offset),
				Color(0.14, 0.09, 0.05, 0.80), 0.72, true
			)
			draw_line(
				top_left + Vector2(offset, 0.0),
				top_left + Vector2(offset, grid_extent),
				Color(0.14, 0.09, 0.05, 0.80), 0.72, true
			)
	if states_.size() != board_size_ * board_size_:
		return
	var stone_radius: float = minf(cell_size * 0.46, 4.0)
	for row in range(board_size_):
		for column in range(board_size_):
			var state: int = states_[row * board_size_ + column]
			if state != 1 and state != 2:
				continue
			var center: Vector2 = top_left + Vector2(
				float(column) * cell_size,
				float(row) * cell_size
			)
			var fill: Color = Color("17191a") \
				if state == 1 else Color("f0eee7")
			var outline: Color = Color("070809") \
				if state == 1 else Color("4d4d49")
			draw_circle(center, stone_radius, fill)
			draw_arc(
				center, stone_radius, 0.0, TAU, 16,
				outline, 0.65, true
			)
