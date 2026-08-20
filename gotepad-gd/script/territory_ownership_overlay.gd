class_name TerritoryOwnershipOverlay
extends Node2D

const kBlack: int = 1
const kWhite: int = 2
const kBlackFill: Color = Color(0.025, 0.08, 0.055, 0.58)
const kBlackBorder: Color = Color(0.34, 0.86, 0.52, 0.92)
const kWhiteFill: Color = Color(0.92, 0.97, 1.0, 0.56)
const kWhiteBorder: Color = Color(1.0, 1.0, 1.0, 0.94)

var marks_: PackedInt32Array = PackedInt32Array()
var confidence_: PackedFloat32Array = PackedFloat32Array()
var board_size_: int = 19
var cell_size_: float = 1.0


func configure(
		marks: PackedInt32Array,
		confidence: PackedFloat32Array,
		board_size: int,
		cell_size: float
) -> void:
	marks_ = marks.duplicate()
	confidence_ = confidence.duplicate()
	board_size_ = board_size
	cell_size_ = cell_size
	visible = marks_.size() == board_size_ * board_size_
	queue_redraw()


func clear_marks() -> void:
	marks_ = PackedInt32Array()
	confidence_ = PackedFloat32Array()
	visible = false
	queue_redraw()


func _draw() -> void:
	if marks_.size() != board_size_ * board_size_ or cell_size_ <= 0.0:
		return
	var marker_size: float = cell_size_ * 0.38
	var half_size: float = marker_size * 0.5
	var border_width: float = maxf(cell_size_ * 0.035, 1.0)
	var half_extent: float = cell_size_ * float(board_size_ - 1) * 0.5
	for index: int in range(marks_.size()):
		var mark: int = marks_[index]
		if mark != kBlack and mark != kWhite:
			continue
		var row: int = floori(float(index) / float(board_size_))
		var column: int = index % board_size_
		var center: Vector2 = Vector2(
			-half_extent + cell_size_ * float(column),
			-half_extent + cell_size_ * float(row)
		)
		var strength: float = clampf(
			confidence_[index] if index < confidence_.size() else 1.0,
			0.0, 1.0
		)
		var fill: Color = kBlackFill if mark == kBlack else kWhiteFill
		fill.a *= lerpf(0.55, 1.0, strength)
		var border: Color = kBlackBorder if mark == kBlack else kWhiteBorder
		var rect: Rect2 = Rect2(
			center - Vector2.ONE * half_size,
			Vector2.ONE * marker_size
		)
		draw_rect(rect, fill, true)
		draw_rect(rect, border, false, border_width, true)
