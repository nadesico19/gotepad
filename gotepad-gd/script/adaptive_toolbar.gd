class_name AdaptiveToolbar
extends Container

@export_range(0.0, 64.0, 1.0) var separation: float = 8.0

var available_height_: float = 100000.0


func set_available_height(available_height: float) -> void:
	var normalized_height: float = maxf(available_height, 1.0)
	if is_equal_approx(available_height_, normalized_height):
		return
	available_height_ = normalized_height
	update_minimum_size()
	queue_sort()


func get_required_size() -> Vector2:
	var controls: Array[Control] = visible_controls_()
	if controls.is_empty():
		return Vector2.ZERO
	var cell_size: Vector2 = cell_size_for_(controls)
	var rows_per_column: int = rows_per_column_(
		controls.size(), cell_size.y
	)
	var column_count: int = ceili(
		float(controls.size()) / float(rows_per_column)
	)
	var used_rows: int = mini(rows_per_column, controls.size())
	return Vector2(
		float(column_count) * cell_size.x \
			+ float(maxi(column_count - 1, 0)) * separation,
		float(used_rows) * cell_size.y \
			+ float(maxi(used_rows - 1, 0)) * separation
	)


func _get_minimum_size() -> Vector2:
	return get_required_size()


func _notification(what: int) -> void:
	if what != NOTIFICATION_SORT_CHILDREN:
		return
	var controls: Array[Control] = visible_controls_()
	if controls.is_empty():
		return
	var cell_size: Vector2 = cell_size_for_(controls)
	var rows_per_column: int = rows_per_column_(
		controls.size(), cell_size.y
	)
	for index in range(controls.size()):
		var column: int = floori(
			float(index) / float(rows_per_column)
		)
		var row: int = index % rows_per_column
		var position: Vector2 = Vector2(
			float(column) * (cell_size.x + separation),
			float(row) * (cell_size.y + separation)
		)
		fit_child_in_rect(controls[index], Rect2(position, cell_size))


func visible_controls_() -> Array[Control]:
	var controls: Array[Control] = []
	for child: Node in get_children():
		if child is not Control:
			continue
		var control: Control = child as Control
		if not control.visible:
			continue
		controls.append(control)
	return controls


func cell_size_for_(controls: Array[Control]) -> Vector2:
	var cell_size: Vector2 = Vector2.ONE
	for control: Control in controls:
		cell_size = cell_size.max(control.get_combined_minimum_size())
	return cell_size


func rows_per_column_(control_count: int, cell_height: float) -> int:
	var result: int = maxi(
		floori(
			(available_height_ + separation) \
			/ (cell_height + separation)
		),
		1
	)
	return mini(result, maxi(control_count, 1))
