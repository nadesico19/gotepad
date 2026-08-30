class_name BoardImageReview
extends Control

signal corners_changed
signal cells_changed

const kBlack: int = 1
const kWhite: int = 2
const kCornerHitRadius: float = 18.0
const kMinimumPointHitRadius: float = 10.0
const kCornerHandleGap: float = 15.0
const kStoneMarkerScale: float = 0.8
const kGridColor: Color = Color(0.25, 0.9, 1.0, 0.72)
const kLowConfidenceThreshold: float = 0.58
const kLowConfidenceColor: Color = Color(1.0, 0.16, 0.12, 1.0)

var source_image_: Image
var source_texture_: ImageTexture
var board_size_: int = 19
var corners_: PackedVector2Array = PackedVector2Array()
var grid_points_: PackedVector2Array = PackedVector2Array()
var cells_: PackedInt32Array = PackedInt32Array()
var confidence_: PackedFloat32Array = PackedFloat32Array()
var dragged_corner_: int = -1
var dragged_corner_offset_: Vector2 = Vector2.ZERO


func _ready() -> void:
	mouse_default_cursor_shape = Control.CURSOR_CROSS
	clip_contents = true
	set_process_unhandled_input(false)


func set_source_image(image: Image) -> void:
	source_image_ = image
	source_texture_ = ImageTexture.create_from_image(image)
	queue_redraw()


func apply_recognition(result: Dictionary) -> void:
	board_size_ = int(result.get("board_size", board_size_))
	corners_ = PackedVector2Array(result.get(
		"corners", PackedVector2Array()
	))
	grid_points_ = PackedVector2Array(result.get(
		"grid_points", PackedVector2Array()
	))
	cells_ = PackedInt32Array(result.get("cells", PackedInt32Array()))
	confidence_ = PackedFloat32Array(result.get(
		"confidence", PackedFloat32Array()
	))
	queue_redraw()


func get_grid_corners() -> PackedVector2Array:
	return corners_.duplicate()


func get_cells() -> PackedInt32Array:
	return cells_.duplicate()


func get_low_confidence_count() -> int:
	var count: int = 0
	for value: float in confidence_:
		if value < kLowConfidenceThreshold:
			count += 1
	return count


func rotate_clockwise() -> void:
	if source_image_ == null:
		return
	var old_height: int = source_image_.get_height()
	if corners_.size() == 4:
		var rotated_corners: PackedVector2Array = PackedVector2Array()
		rotated_corners.resize(4)
		rotated_corners[0] = rotate_image_point_clockwise_(
			corners_[3], old_height
		)
		rotated_corners[1] = rotate_image_point_clockwise_(
			corners_[0], old_height
		)
		rotated_corners[2] = rotate_image_point_clockwise_(
			corners_[1], old_height
		)
		rotated_corners[3] = rotate_image_point_clockwise_(
			corners_[2], old_height
		)
		corners_ = rotated_corners
	rotate_grid_points_clockwise_(old_height)
	rotate_cell_data_clockwise_()
	source_image_.rotate_90(CLOCKWISE)
	source_texture_ = ImageTexture.create_from_image(source_image_)
	cells_changed.emit()
	queue_redraw()


func rotate_grid_points_clockwise_(old_height: int) -> void:
	if grid_points_.size() != board_size_ * board_size_:
		grid_points_ = PackedVector2Array()
		return
	var rotated: PackedVector2Array = PackedVector2Array()
	rotated.resize(grid_points_.size())
	for row: int in range(board_size_):
		for column: int in range(board_size_):
			var old_index: int = row * board_size_ + column
			var new_row: int = column
			var new_column: int = board_size_ - row - 1
			var new_index: int = new_row * board_size_ + new_column
			rotated[new_index] = rotate_image_point_clockwise_(
				grid_points_[old_index], old_height
			)
	grid_points_ = rotated


func rotate_cell_data_clockwise_() -> void:
	if cells_.size() != board_size_ * board_size_:
		return
	var rotated: PackedInt32Array = PackedInt32Array()
	var rotated_confidence: PackedFloat32Array = PackedFloat32Array()
	rotated.resize(cells_.size())
	var has_confidence: bool = confidence_.size() == cells_.size()
	if has_confidence:
		rotated_confidence.resize(confidence_.size())
	for row: int in range(board_size_):
		for column: int in range(board_size_):
			var old_index: int = row * board_size_ + column
			var new_row: int = column
			var new_column: int = board_size_ - row - 1
			var new_index: int = new_row * board_size_ + new_column
			rotated[new_index] = cells_[old_index]
			if has_confidence:
				rotated_confidence[new_index] = confidence_[old_index]
	cells_ = rotated
	confidence_ = rotated_confidence


func rotate_image_point_clockwise_(point: Vector2, old_height: int) -> Vector2:
	return Vector2(float(old_height - 1) - point.y, point.x)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.035, 0.035, 0.035, 1.0))
	if source_texture_ == null or source_image_ == null:
		return
	var display_rect: Rect2 = image_display_rect_()
	draw_texture_rect(source_texture_, display_rect, false)
	if corners_.size() != 4:
		return
	draw_grid_()
	draw_cells_()
	draw_low_confidence_points_()
	for index: int in range(corners_.size()):
		var local_corner: Vector2 = image_to_local_(corners_[index])
		var handle_center: Vector2 = corner_handle_position_(index)
		var outward: Vector2 = (handle_center - local_corner).normalized()
		var connector_begin: Vector2 = local_corner + outward * (
			stone_radius_() + 2.0
		)
		var connector_end: Vector2 = handle_center - outward * 10.0
		draw_line(connector_begin, connector_end,
			Color(1.0, 0.72, 0.12, 0.9), 2.0, true)
		draw_circle(handle_center, 8.0, Color(1.0, 0.72, 0.12, 1.0))
		draw_arc(handle_center, 12.0, 0.0, TAU, 24,
			Color(0.08, 0.05, 0.01, 1.0), 3.0, true)


func draw_grid_() -> void:
	for row: int in range(board_size_):
		var first: Vector2 = local_grid_point_(row, 0)
		var last: Vector2 = local_grid_point_(row, board_size_ - 1)
		draw_line(first, last, kGridColor, 1.2, true)
	for column: int in range(board_size_):
		var first: Vector2 = local_grid_point_(0, column)
		var last: Vector2 = local_grid_point_(board_size_ - 1, column)
		draw_line(first, last, kGridColor, 1.2, true)


func draw_cells_() -> void:
	if cells_.size() != board_size_ * board_size_:
		return
	var radius: float = stone_radius_() * kStoneMarkerScale
	for index: int in range(cells_.size()):
		var color: int = cells_[index]
		if color == 0:
			continue
		var row: int = floori(float(index) / float(board_size_))
		var column: int = index % board_size_
		var center: Vector2 = local_grid_point_(row, column)
		var fill: Color = Color(0.03, 0.03, 0.03, 0.88) \
			if color == kBlack else Color(0.97, 0.97, 0.95, 0.9)
		draw_circle(center, radius, fill)
		var outline: Color = kGridColor if color == kBlack else \
			Color(0.05, 0.05, 0.05, 0.95)
		draw_arc(center, radius, 0.0, TAU, 24,
			outline, 1.5, true)


func draw_low_confidence_points_() -> void:
	var point_count: int = mini(
		board_size_ * board_size_, confidence_.size()
	)
	var point_radius: float = clampf(stone_radius_() * 0.28, 4.0, 8.0)
	for index: int in range(point_count):
		if confidence_[index] >= kLowConfidenceThreshold:
			continue
		var row: int = floori(float(index) / float(board_size_))
		var column: int = index % board_size_
		draw_circle(
			local_grid_point_(row, column), point_radius, kLowConfidenceColor
		)


func _gui_input(event: InputEvent) -> void:
	if source_image_ == null or corners_.size() != 4:
		return
	if event is InputEventMouseButton:
		var mouse_button: InputEventMouseButton = event as InputEventMouseButton
		if mouse_button.button_index != MOUSE_BUTTON_LEFT:
			return
		if mouse_button.pressed:
			dragged_corner_ = nearest_corner_(mouse_button.position)
			if dragged_corner_ < 0:
				cycle_nearest_cell_(mouse_button.position)
			else:
				dragged_corner_offset_ = (
					image_to_local_(corners_[dragged_corner_])
					- mouse_button.position
				)
		else:
			if dragged_corner_ >= 0:
				corners_changed.emit()
			dragged_corner_ = -1
			dragged_corner_offset_ = Vector2.ZERO
		accept_event()
	elif event is InputEventMouseMotion and dragged_corner_ >= 0:
		var motion: InputEventMouseMotion = event as InputEventMouseMotion
		corners_[dragged_corner_] = clamp_image_point_(
			local_to_image_(motion.position + dragged_corner_offset_)
		)
		grid_points_ = PackedVector2Array()
		queue_redraw()
		accept_event()


func nearest_corner_(local_position: Vector2) -> int:
	var best_index: int = -1
	var best_distance: float = kCornerHitRadius
	for index: int in range(corners_.size()):
		var distance: float = local_position.distance_to(
			corner_handle_position_(index)
		)
		if distance <= best_distance:
			best_distance = distance
			best_index = index
	return best_index


func corner_handle_position_(index: int) -> Vector2:
	var local_corner: Vector2 = image_to_local_(corners_[index])
	var local_center: Vector2 = Vector2.ZERO
	for corner: Vector2 in corners_:
		local_center += image_to_local_(corner)
	local_center /= float(corners_.size())
	var outward: Vector2 = (local_corner - local_center).normalized()
	return local_corner + outward * (stone_radius_() + kCornerHandleGap)


func cycle_nearest_cell_(local_position: Vector2) -> void:
	if cells_.size() != board_size_ * board_size_:
		return
	var best_index: int = -1
	var best_distance: float = maxf(stone_radius_() * 1.25, kMinimumPointHitRadius)
	for index: int in range(cells_.size()):
		var row: int = floori(float(index) / float(board_size_))
		var column: int = index % board_size_
		var distance: float = local_position.distance_to(
			local_grid_point_(row, column)
		)
		if distance <= best_distance:
			best_distance = distance
			best_index = index
	if best_index < 0:
		return
	cells_[best_index] = (cells_[best_index] + 1) % 3
	if best_index < confidence_.size():
		confidence_[best_index] = 1.0
	cells_changed.emit()
	queue_redraw()


func local_grid_point_(row: int, column: int) -> Vector2:
	var index: int = row * board_size_ + column
	if grid_points_.size() == board_size_ * board_size_:
		return image_to_local_(grid_points_[index])
	var horizontal: float = float(column) / maxf(board_size_ - 1.0, 1.0)
	var vertical: float = float(row) / maxf(board_size_ - 1.0, 1.0)
	var top: Vector2 = corners_[0].lerp(corners_[1], horizontal)
	var bottom: Vector2 = corners_[3].lerp(corners_[2], horizontal)
	return image_to_local_(top.lerp(bottom, vertical))


func stone_radius_() -> float:
	if board_size_ <= 1:
		return 4.0
	var horizontal: float = local_grid_point_(0, 0).distance_to(
		local_grid_point_(0, 1)
	)
	var vertical: float = local_grid_point_(0, 0).distance_to(
		local_grid_point_(1, 0)
	)
	return clampf(minf(horizontal, vertical) * 0.39, 3.0, 28.0)


func image_display_rect_() -> Rect2:
	var image_size: Vector2 = Vector2(source_image_.get_size())
	var scale: float = minf(size.x / image_size.x, size.y / image_size.y)
	var displayed_size: Vector2 = image_size * scale
	return Rect2((size - displayed_size) * 0.5, displayed_size)


func image_to_local_(point: Vector2) -> Vector2:
	var rect: Rect2 = image_display_rect_()
	var image_size: Vector2 = Vector2(source_image_.get_size())
	return rect.position + point * (rect.size / image_size)


func local_to_image_(point: Vector2) -> Vector2:
	var rect: Rect2 = image_display_rect_()
	var image_size: Vector2 = Vector2(source_image_.get_size())
	return (point - rect.position) * (image_size / rect.size)


func clamp_image_point_(point: Vector2) -> Vector2:
	var image_size: Vector2 = Vector2(source_image_.get_size())
	return Vector2(
		clampf(point.x, 0.0, image_size.x - 1.0),
		clampf(point.y, 0.0, image_size.y - 1.0)
	)
