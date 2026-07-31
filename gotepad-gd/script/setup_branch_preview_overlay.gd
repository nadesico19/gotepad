class_name SetupBranchPreviewOverlay
extends Node2D

const kBlack: int = 1
const kWhite: int = 2
const kBlackPreview: Color = Color(0.05, 0.06, 0.065, 0.66)
const kWhitePreview: Color = Color(0.96, 0.95, 0.91, 0.72)
const kPreviewOutline: Color = Color(1.0, 0.78, 0.28, 0.92)
const kClearColor: Color = Color(1.0, 0.34, 0.28, 0.88)

var changes_: Array[Dictionary] = []


func show_changes(changes: Array[Dictionary]) -> void:
	changes_ = changes.duplicate(true)
	visible = not changes_.is_empty()
	queue_redraw()


func clear_changes() -> void:
	changes_.clear()
	visible = false
	queue_redraw()


func _draw() -> void:
	for change: Dictionary in changes_:
		var center: Vector2 = Vector2(change.get("center", Vector2.ZERO))
		var radius: float = float(change.get("radius", 1.0))
		var target: int = int(change.get("target", 0))
		if target == kBlack or target == kWhite:
			var fill: Color = kBlackPreview \
				if target == kBlack else kWhitePreview
			draw_circle(center, radius, fill)
			draw_arc(
				center, radius, 0.0, TAU, 32,
				kPreviewOutline, maxf(radius * 0.08, 1.0), true
			)
			continue
		draw_arc(
			center, radius * 0.82, 0.0, TAU, 32,
			kClearColor, maxf(radius * 0.08, 1.0), true
		)
		var diagonal: float = radius * 0.58
		var width: float = maxf(radius * 0.12, 1.0)
		draw_line(
			center + Vector2(-diagonal, -diagonal),
			center + Vector2(diagonal, diagonal),
			kClearColor, width, true
		)
		draw_line(
			center + Vector2(diagonal, -diagonal),
			center + Vector2(-diagonal, diagonal),
			kClearColor, width, true
		)
