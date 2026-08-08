extends Camera2D

@export var target_path: NodePath
@export_range(0.0, 256.0, 1.0) var margin: float = 0.0
@export_range(0.0, 256.0, 1.0) var bottom_extension: float = 52.0
@export_range(0.0, 512.0, 1.0) var right_ui_reserve: float = 96.0
@export_range(0.0, 256.0, 1.0) var top_ui_reserve: float = 42.0

var target_: Sprite2D
var window_: Window


func _ready() -> void:
	target_ = get_node_or_null(target_path) as Sprite2D
	if target_ == null:
		push_warning("FitBoardCamera requires a Sprite2D target.")
		return

	window_ = get_window()
	window_.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	window_.content_scale_size = Vector2i.ZERO
	global_position = target_.global_position
	window_.size_changed.connect(update_zoom_)
	if target_.has_signal(&"board_texture_changed"):
		target_.connect(
			&"board_texture_changed", Callable(self, "update_zoom_")
		)
	update_zoom_()


func update_zoom_() -> void:
	var target_scale: Vector2 = target_.global_scale.abs()
	var target_size: Vector2 = target_.get_rect().size * target_scale
	var content_size := Vector2(
		target_size.x,
		target_size.y + bottom_extension * target_scale.y
	)
	# content_scale_factor会把物理窗口换算为较小的逻辑视口。相机必须按
	# 逻辑视口计算，否则高分屏UI放大后棋盘还会被重复放大并超出窗口。
	var viewport_size: Vector2 = window_.get_visible_rect().size
	var available_size := viewport_size - Vector2(
		margin * 2.0 + right_ui_reserve,
		margin * 2.0 + top_ui_reserve
	)
	if content_size.x <= 0.0 or content_size.y <= 0.0:
		return
	if available_size.x <= 0.0 or available_size.y <= 0.0:
		return

	var fit_zoom: float = minf(
		available_size.x / content_size.x,
		available_size.y / content_size.y
	)
	zoom = Vector2.ONE * fit_zoom

	var target_position: Vector2 = target_.global_position
	var target_left: float = target_position.x - target_size.x * 0.5
	var target_top: float = target_position.y - target_size.y * 0.5
	var content_center_y: float = target_top + content_size.y * 0.5
	var visible_half_width: float = viewport_size.x * 0.5 / fit_zoom
	global_position = Vector2(
		target_left + visible_half_width - margin / fit_zoom,
		content_center_y - top_ui_reserve * 0.5 / fit_zoom
	)
	target_.queue_redraw()
