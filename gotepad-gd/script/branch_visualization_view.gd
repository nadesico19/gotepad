extends Control

signal exit_requested

const kThumbnailSize: float = 116.0
const kThumbnailTitleHeight: float = 14.0
const kThumbnailTitleFontSize: float = 9.0
const kHorizontalGap: float = 54.0
const kVerticalGap: float = 70.0
const kTopMargin: float = 88.0
const kSideMargin: float = 64.0
const kMinimumZoom: float = 0.25
const kMaximumZoom: float = 2.5
const kZoomStep: float = 1.12
const kGenerationFrameBudgetUsec: int = 6000
const kTreeScanBatchSize: int = 128
const kHitCellSize: float = kThumbnailSize + kHorizontalGap
const kThumbnailTextureScale: float = 2.0
const kTextureCacheLimit: int = 256
const kActionIconRadius: float = 11.0
const kActionIconOffset: float = 15.0
const kActionIconHitRadius: float = 18.0
const kCommentNotebookIcon: String = "📓"

@onready var exit_button_: Button = $ExitButton
@onready var thumbnail_layer_: Node2D = $ThumbnailLayer
@onready var loading_overlay_: ColorRect = $LoadingOverlay
@onready var progress_label_: Label = \
	$LoadingOverlay/Center/Content/ProgressLabel
@onready var progress_bar_: ProgressBar = \
	$LoadingOverlay/Center/Content/ProgressBar
@onready var delete_branch_confirmation_: ConfirmationDialog = \
	$DeleteBranchConfirmation

var go_notes_: GoNotes
var document_id_: int = 0
var current_uid_: int = 0
var board_size_: int = 19
var full_nodes_: Dictionary = {}
var parent_by_uid_: Dictionary = {}
var traversal_order_: Array[int] = []
var selected_uids_: Dictionary = {}
var selected_order_: Array[int] = []
var display_children_: Dictionary = {}
var display_roots_: Array[int] = []
var node_positions_: Dictionary = {}
var node_fingerprints_: Dictionary = {}
var node_titles_: Dictionary = {}
var hit_uids_by_cell_: Dictionary = {}
var snapshots_: Dictionary = {}
var snapshot_cache_by_document_: Dictionary = {}
var texture_cache_by_document_: Dictionary = {}
var texture_use_counter_: int = 0
var active_sprites_: Dictionary = {}
var sprite_pool_: Array[Sprite2D] = []
var active_title_labels_: Dictionary = {}
var title_label_pool_: Array[Label] = []
var placeholder_texture_: Texture2D
var pending_texture_uids_: Array[int] = []
var pending_texture_uid_set_: Dictionary = {}
var content_bounds_: Rect2 = Rect2()
var next_leaf_x_: float = 0.0
var zoom_: float = 1.0
var pan_: Vector2 = Vector2.ZERO
var selected_uid_: int = -1
var dragging_: bool = false
var last_drag_position_: Vector2 = Vector2.ZERO
var generation_token_: int = 0
var pending_delete_uid_: int = -1


func _ready() -> void:
	exit_button_.pressed.connect(_on_exit_pressed_)
	delete_branch_confirmation_.confirmed.connect(
		_on_delete_branch_confirmed_
	)
	delete_branch_confirmation_.canceled.connect(
		_on_delete_branch_canceled_
	)
	resized.connect(_on_view_resized_)
	set_process(false)


func rebuild(go_notes: GoNotes) -> void:
	go_notes_ = go_notes
	document_id_ = int(go_notes_.get_instance_id())
	current_uid_ = int(go_notes_.call(&"get_current_uid"))
	board_size_ = int(go_notes_.call(&"get_board_size"))
	var empty_states: PackedInt32Array = PackedInt32Array()
	empty_states.resize(board_size_ * board_size_)
	placeholder_texture_ = _texture_from_states_(empty_states)
	selected_uid_ = -1
	zoom_ = 1.0
	pan_ = Vector2.ZERO
	generation_token_ += 1
	loading_overlay_.show()
	progress_bar_.hide()
	progress_label_.text = "正在分析棋谱分支……"
	selected_order_.clear()
	snapshots_.clear()
	node_titles_.clear()
	_clear_active_sprites_()
	pending_texture_uids_.clear()
	pending_texture_uid_set_.clear()
	set_process(false)
	queue_redraw()
	_prepare_visualization_(generation_token_)


func cancel_generation() -> void:
	generation_token_ += 1
	loading_overlay_.hide()
	pending_texture_uids_.clear()
	pending_texture_uid_set_.clear()
	set_process(false)


func cancel_dialog() -> bool:
	if not delete_branch_confirmation_.visible:
		return false
	delete_branch_confirmation_.hide()
	pending_delete_uid_ = -1
	return true


func _prepare_visualization_(token: int) -> void:
	await get_tree().process_frame
	if token != generation_token_:
		return
	var tree_built: bool = await _build_full_tree_(token)
	if not tree_built:
		return
	_select_visualized_nodes_()
	_build_display_tree_()
	_layout_tree_()
	var total: int = selected_order_.size()
	progress_bar_.max_value = float(maxi(total, 1))
	progress_bar_.value = 0.0
	progress_bar_.show()
	progress_label_.text = "正在生成棋盘缩略图：0 / %d" % total
	await get_tree().process_frame
	if token != generation_token_:
		return
	var snapshots_cached: bool = await _cache_snapshots_(token)
	if not snapshots_cached:
		return
	loading_overlay_.hide()
	call_deferred(&"_focus_current_position_")


func _build_full_tree_(token: int) -> bool:
	full_nodes_.clear()
	parent_by_uid_.clear()
	traversal_order_.clear()
	node_fingerprints_.clear()
	var pending: Array[int] = [0]
	parent_by_uid_[0] = -1
	var pending_index: int = 0
	while pending_index < pending.size():
		var uid: int = pending[pending_index]
		pending_index += 1
		if full_nodes_.has(uid):
			continue
		var node: Dictionary = Dictionary(
			go_notes_.call(&"get_node_at", uid)
		)
		if node.is_empty():
			continue
		var child_uids: Array[int] = []
		var children: Array = Array(node.get("children", []))
		for child_value: Variant in children:
			var child: Dictionary = Dictionary(child_value)
			var child_uid: int = int(child.get("uid", -1))
			if child_uid < 0:
				continue
			child_uids.append(child_uid)
			parent_by_uid_[child_uid] = uid
			pending.append(child_uid)
		node["child_uids"] = child_uids
		full_nodes_[uid] = node
		var parent_uid: int = int(parent_by_uid_.get(uid, -1))
		var parent_fingerprint: int = int(
			node_fingerprints_.get(parent_uid, 0)
		)
		node_fingerprints_[uid] = hash([
			board_size_,
			parent_fingerprint,
			node.get("color", 0),
			node.get("row", 0),
			node.get("column", 0),
			node.get("preset_stones", []),
		])
		traversal_order_.append(uid)
		if pending_index % kTreeScanBatchSize == 0:
			await get_tree().process_frame
			if token != generation_token_:
				return false
	return true


func _select_visualized_nodes_() -> void:
	selected_uids_.clear()
	selected_order_.clear()
	for uid: int in traversal_order_:
		var node: Dictionary = Dictionary(full_nodes_.get(uid, {}))
		var children: Array = Array(node.get("child_uids", []))
		if bool(node.get("has_notes", false)):
			_select_uid_(uid)
		if children.size() > 1:
			_select_uid_(uid)
			for child_value: Variant in children:
				_select_uid_(int(child_value))
		elif children.is_empty():
			_select_uid_(uid)


func _select_uid_(uid: int) -> void:
	if selected_uids_.has(uid):
		return
	selected_uids_[uid] = true
	selected_order_.append(uid)


func _build_display_tree_() -> void:
	display_children_.clear()
	display_roots_.clear()
	for uid: int in selected_order_:
		display_children_[uid] = []
	for uid: int in selected_order_:
		var parent_uid: int = int(parent_by_uid_.get(uid, -1))
		while parent_uid >= 0 and not selected_uids_.has(parent_uid):
			parent_uid = int(parent_by_uid_.get(parent_uid, -1))
		if parent_uid < 0:
			display_roots_.append(uid)
			continue
		var siblings: Array = Array(display_children_.get(parent_uid, []))
		siblings.append(uid)
		display_children_[parent_uid] = siblings


func _cache_snapshots_(token: int) -> bool:
	snapshots_.clear()
	var document_cache: Dictionary = Dictionary(
		snapshot_cache_by_document_.get(document_id_, {})
	)
	var frame_started: int = Time.get_ticks_usec()
	for index: int in range(selected_order_.size()):
		var uid: int = selected_order_[index]
		var fingerprint: int = int(node_fingerprints_.get(uid, 0))
		var cache_entry: Dictionary = Dictionary(document_cache.get(uid, {}))
		var states: PackedInt32Array = PackedInt32Array()
		if not cache_entry.is_empty() \
				and int(cache_entry.get("fingerprint", -1)) == fingerprint:
			states = PackedInt32Array(cache_entry.get("states", []))
		else:
			states = PackedInt32Array(
				go_notes_.call(&"get_position_at", uid)
			)
			document_cache[uid] = {
				"fingerprint": fingerprint,
				"states": states,
			}
		snapshots_[uid] = states
		var node: Dictionary = Dictionary(full_nodes_.get(uid, {}))
		var title: String = str(
			node.get("first_note_title", "")
		).strip_edges()
		var comment: String = str(
			node.get("first_note_comment", "")
		).strip_edges()
		if title.is_empty():
			title = _first_comment_line_(comment)
		if not comment.is_empty():
			title = kCommentNotebookIcon \
				if title.is_empty() \
				else "%s %s" % [kCommentNotebookIcon, title]
		node_titles_[uid] = title
		var completed: int = index + 1
		progress_bar_.value = float(completed)
		progress_label_.text = "正在生成棋盘缩略图：%d / %d" % [
			completed,
			selected_order_.size(),
		]
		if Time.get_ticks_usec() - frame_started \
				>= kGenerationFrameBudgetUsec:
			snapshot_cache_by_document_[document_id_] = document_cache
			await get_tree().process_frame
			if token != generation_token_:
				return false
			frame_started = Time.get_ticks_usec()
	snapshot_cache_by_document_[document_id_] = document_cache
	return true


func _first_comment_line_(comment: String) -> String:
	var normalized: String = comment.replace("\r\n", "\n").replace("\r", "\n")
	if normalized.is_empty():
		return ""
	return normalized.get_slice("\n", 0).strip_edges()


func _layout_tree_() -> void:
	node_positions_.clear()
	next_leaf_x_ = kSideMargin + kThumbnailSize * 0.5
	for root_uid: int in display_roots_:
		_layout_node_(root_uid, 0)
	_update_content_bounds_()
	_build_hit_index_()


func _layout_node_(uid: int, depth: int) -> float:
	var children: Array = Array(display_children_.get(uid, []))
	var x_position: float = 0.0
	if children.is_empty():
		x_position = next_leaf_x_
		next_leaf_x_ += kThumbnailSize + kHorizontalGap
	else:
		var child_x_total: float = 0.0
		for child_value: Variant in children:
			child_x_total += _layout_node_(int(child_value), depth + 1)
		x_position = child_x_total / float(children.size())
	node_positions_[uid] = Vector2(
		x_position,
		kTopMargin + kThumbnailSize * 0.5 \
			+ float(depth) * (kThumbnailSize + kVerticalGap)
	)
	return x_position


func _update_content_bounds_() -> void:
	if selected_order_.is_empty():
		content_bounds_ = Rect2(Vector2.ZERO, Vector2.ONE)
		return
	var first_position: Vector2 = Vector2(
		node_positions_.get(selected_order_.front(), Vector2.ZERO)
	)
	var minimum: Vector2 = first_position
	var maximum: Vector2 = first_position
	for uid: int in selected_order_:
		var position: Vector2 = Vector2(node_positions_.get(uid, Vector2.ZERO))
		minimum = minimum.min(position)
		maximum = maximum.max(position)
	var padding: Vector2 = Vector2.ONE * (kThumbnailSize * 0.5 + 28.0)
	content_bounds_ = Rect2(minimum - padding, maximum - minimum + padding * 2.0)


func _build_hit_index_() -> void:
	hit_uids_by_cell_.clear()
	for uid: int in selected_order_:
		var center: Vector2 = Vector2(
			node_positions_.get(uid, Vector2.ZERO)
		)
		var cell: Vector2i = Vector2i(
			floori(center.x / kHitCellSize),
			floori(center.y / kHitCellSize)
		)
		var uids: Array = Array(hit_uids_by_cell_.get(cell, []))
		uids.append(uid)
		hit_uids_by_cell_[cell] = uids


func _fit_content_() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var available: Vector2 = Vector2(
		maxf(size.x - 120.0, 100.0),
		maxf(size.y - 100.0, 100.0)
	)
	var target_zoom: float = minf(
		available.x / maxf(content_bounds_.size.x, 1.0),
		available.y / maxf(content_bounds_.size.y, 1.0)
	)
	zoom_ = clampf(target_zoom, kMinimumZoom, 1.0)
	pan_ = size * 0.5 - content_bounds_.get_center() * zoom_
	_apply_view_transform_()


func _focus_current_position_() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var focus_result: Dictionary = _focus_position_for_uid_(current_uid_)
	if not bool(focus_result.get("found", false)):
		_fit_content_()
		return

	var focus_size: Vector2 = Vector2(
		kThumbnailSize * 2.0 + kHorizontalGap,
		kThumbnailSize * 2.0 + kVerticalGap
	)
	var available: Vector2 = Vector2(
		maxf(size.x - kSideMargin * 2.0, 100.0),
		maxf(size.y - kTopMargin - 40.0, 100.0)
	)
	zoom_ = clampf(
		minf(
			available.x / focus_size.x,
			available.y / focus_size.y
		),
		kMinimumZoom,
		kMaximumZoom
	)
	var focus_position: Vector2 = Vector2(
		focus_result.get("position", content_bounds_.get_center())
	)
	pan_ = size * 0.5 - focus_position * zoom_
	_apply_view_transform_()


func _focus_position_for_uid_(uid: int) -> Dictionary:
	if selected_uids_.has(uid):
		return {
			"found": true,
			"position": Vector2(node_positions_.get(uid, Vector2.ZERO)),
		}
	if not parent_by_uid_.has(uid):
		return {}

	var ancestor_uid: int = uid
	var steps_from_ancestor: int = 0
	while ancestor_uid >= 0 and not selected_uids_.has(ancestor_uid):
		ancestor_uid = int(parent_by_uid_.get(ancestor_uid, -1))
		steps_from_ancestor += 1

	var descendant_uid: int = uid
	var steps_to_descendant: int = 0
	while descendant_uid >= 0 and not selected_uids_.has(descendant_uid):
		var node: Dictionary = Dictionary(
			full_nodes_.get(descendant_uid, {})
		)
		var children: Array = Array(node.get("child_uids", []))
		if children.is_empty():
			descendant_uid = -1
			break
		descendant_uid = int(children.front())
		steps_to_descendant += 1

	if ancestor_uid < 0 and descendant_uid < 0:
		return {}
	if ancestor_uid < 0:
		return {
			"found": true,
			"position": Vector2(
				node_positions_.get(descendant_uid, Vector2.ZERO)
			),
		}
	if descendant_uid < 0:
		return {
			"found": true,
			"position": Vector2(
				node_positions_.get(ancestor_uid, Vector2.ZERO)
			),
		}

	var path_steps: int = steps_from_ancestor + steps_to_descendant
	var progress: float = float(steps_from_ancestor) \
		/ float(maxi(path_steps, 1))
	var ancestor_center: Vector2 = Vector2(
		node_positions_.get(ancestor_uid, Vector2.ZERO)
	)
	var descendant_center: Vector2 = Vector2(
		node_positions_.get(descendant_uid, Vector2.ZERO)
	)
	return {
		"found": true,
		"position": _point_on_connection_(
			ancestor_center,
			descendant_center,
			progress
		),
	}


func _point_on_connection_(
	parent_center: Vector2,
	child_center: Vector2,
	progress: float
) -> Vector2:
	var start: Vector2 = parent_center \
		+ Vector2(0.0, kThumbnailSize * 0.5)
	var finish: Vector2 = child_center \
		- Vector2(0.0, kThumbnailSize * 0.5)
	var middle_y: float = (start.y + finish.y) * 0.5
	var points: PackedVector2Array = PackedVector2Array([
		start,
		Vector2(start.x, middle_y),
		Vector2(finish.x, middle_y),
		finish,
	])
	var segment_lengths: PackedFloat32Array = PackedFloat32Array()
	var total_length: float = 0.0
	for index: int in range(points.size() - 1):
		var length: float = points[index].distance_to(points[index + 1])
		segment_lengths.append(length)
		total_length += length
	var remaining: float = clampf(progress, 0.0, 1.0) * total_length
	for index: int in range(segment_lengths.size()):
		var segment_length: float = segment_lengths[index]
		if remaining <= segment_length or index == segment_lengths.size() - 1:
			if segment_length <= 0.0:
				return points[index]
			return points[index].lerp(
				points[index + 1],
				clampf(remaining / segment_length, 0.0, 1.0)
			)
		remaining -= segment_length
	return finish


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("171b1a"), true)
	var visible_world_rect: Rect2 = Rect2(
		-pan_ / zoom_,
		size / zoom_
	).grow(kThumbnailSize)
	var connection_candidates: Array[int] = _uids_in_rect_(
		visible_world_rect.grow(kThumbnailSize + kVerticalGap)
	)
	draw_set_transform(pan_, 0.0, Vector2.ONE * zoom_)
	_draw_connections_(visible_world_rect, connection_candidates)
	if selected_uid_ >= 0 and node_positions_.has(selected_uid_):
		var selected_center: Vector2 = Vector2(
			node_positions_.get(selected_uid_, Vector2.ZERO)
		)
		var selection_rect: Rect2 = _thumbnail_rect_(
			selected_center
		).grow(6.0 / zoom_)
		draw_rect(
			selection_rect,
			Color(1.0, 0.72, 0.22, 0.95),
			false,
			3.0 / zoom_
		)
		_draw_selection_actions_(selection_rect)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_selection_actions_(selection_rect: Rect2) -> void:
	var radius: float = kActionIconRadius / zoom_
	var offset: float = kActionIconOffset / zoom_
	var line_width: float = 3.0 / zoom_
	var check_center: Vector2 = selection_rect.position \
		- Vector2.ONE * offset
	draw_circle(check_center, radius, Color(0.035, 0.08, 0.045, 0.96))
	var check_points: PackedVector2Array = PackedVector2Array([
		check_center + Vector2(-5.5, 0.0) / zoom_,
		check_center + Vector2(-1.5, 4.5) / zoom_,
		check_center + Vector2(6.5, -5.5) / zoom_,
	])
	draw_polyline(
		check_points,
		Color(0.2, 0.92, 0.38, 1.0),
		line_width,
		true
	)
	if selected_uid_ == 0:
		return
	var delete_center: Vector2 = Vector2(
		selection_rect.end.x + offset,
		selection_rect.position.y - offset
	)
	draw_circle(delete_center, radius, Color(0.11, 0.035, 0.035, 0.96))
	var arm: float = 5.5 / zoom_
	var delete_color: Color = Color(1.0, 0.27, 0.23, 1.0)
	draw_line(
		delete_center + Vector2(-arm, -arm),
		delete_center + Vector2(arm, arm),
		delete_color,
		line_width,
		true
	)
	draw_line(
		delete_center + Vector2(arm, -arm),
		delete_center + Vector2(-arm, arm),
		delete_color,
		line_width,
		true
	)


func _draw_connections_(
	visible_world_rect: Rect2,
	candidate_uids: Array[int]
) -> void:
	var line_color: Color = Color(0.72, 0.78, 0.75, 0.82)
	var line_width: float = 2.0 / zoom_
	for parent_uid: int in candidate_uids:
		var children: Array = Array(display_children_.get(parent_uid, []))
		if children.is_empty():
			continue
		var parent_center: Vector2 = Vector2(
			node_positions_.get(parent_uid, Vector2.ZERO)
		)
		var start: Vector2 = parent_center + Vector2(0.0, kThumbnailSize * 0.5)
		for child_value: Variant in children:
			var child_uid: int = int(child_value)
			var child_center: Vector2 = Vector2(
				node_positions_.get(child_uid, Vector2.ZERO)
			)
			var finish: Vector2 = child_center - Vector2(0.0, kThumbnailSize * 0.5)
			var connection_bounds: Rect2 = Rect2(start, Vector2.ZERO)
			connection_bounds = connection_bounds.expand(finish).grow(4.0)
			if not connection_bounds.intersects(visible_world_rect):
				continue
			var middle_y: float = (start.y + finish.y) * 0.5
			var points: PackedVector2Array = PackedVector2Array([
				start,
				Vector2(start.x, middle_y),
				Vector2(finish.x, middle_y),
				finish,
			])
			draw_polyline(points, line_color, line_width, true)


func _uids_in_rect_(world_rect: Rect2) -> Array[int]:
	var result: Array[int] = []
	var minimum_cell: Vector2i = Vector2i(
		floori(world_rect.position.x / kHitCellSize),
		floori(world_rect.position.y / kHitCellSize)
	)
	var maximum_cell: Vector2i = Vector2i(
		floori(world_rect.end.x / kHitCellSize),
		floori(world_rect.end.y / kHitCellSize)
	)
	for cell_y: int in range(minimum_cell.y, maximum_cell.y + 1):
		for cell_x: int in range(minimum_cell.x, maximum_cell.x + 1):
			var cell: Vector2i = Vector2i(cell_x, cell_y)
			for uid_value: Variant in Array(
				hit_uids_by_cell_.get(cell, [])
			):
				result.append(int(uid_value))
	return result


func _apply_view_transform_() -> void:
	thumbnail_layer_.position = pan_
	thumbnail_layer_.scale = Vector2.ONE * zoom_
	_refresh_visible_sprites_()
	queue_redraw()


func _refresh_visible_sprites_() -> void:
	if snapshots_.is_empty() or zoom_ <= 0.0:
		_clear_active_sprites_()
		return
	var visible_world_rect: Rect2 = Rect2(
		-pan_ / zoom_,
		size / zoom_
	).grow(kThumbnailSize)
	var visible_uids: Array[int] = _uids_in_rect_(visible_world_rect)
	var retained_uids: Dictionary = {}
	for uid: int in visible_uids:
		var center: Vector2 = Vector2(
			node_positions_.get(uid, Vector2.ZERO)
		)
		if not _thumbnail_rect_(center).intersects(visible_world_rect):
			continue
		retained_uids[uid] = true
		var sprite: Sprite2D = active_sprites_.get(uid) as Sprite2D
		if sprite == null:
			sprite = _acquire_sprite_()
			active_sprites_[uid] = sprite
		sprite.position = center
		_refresh_title_label_(uid, center)
		var texture: Texture2D = _cached_texture_(uid)
		if texture != null:
			_assign_sprite_texture_(sprite, texture)
		else:
			if placeholder_texture_ != null:
				_assign_sprite_texture_(sprite, placeholder_texture_)
			else:
				sprite.texture = null
			_queue_texture_generation_(uid)

	for uid_value: Variant in active_sprites_.keys():
		var uid: int = int(uid_value)
		if retained_uids.has(uid):
			continue
		var sprite: Sprite2D = active_sprites_.get(uid) as Sprite2D
		active_sprites_.erase(uid)
		_release_sprite_(sprite)
		var title_label: Label = active_title_labels_.get(uid) as Label
		active_title_labels_.erase(uid)
		_release_title_label_(title_label)


func _acquire_sprite_() -> Sprite2D:
	var sprite: Sprite2D
	if sprite_pool_.is_empty():
		sprite = Sprite2D.new()
		sprite.centered = true
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		thumbnail_layer_.add_child(sprite)
	else:
		sprite = sprite_pool_.pop_back()
	sprite.show()
	return sprite


func _release_sprite_(sprite: Sprite2D) -> void:
	if sprite == null:
		return
	sprite.texture = null
	sprite.hide()
	sprite_pool_.append(sprite)


func _refresh_title_label_(uid: int, center: Vector2) -> void:
	var title: String = str(node_titles_.get(uid, ""))
	var label: Label = active_title_labels_.get(uid) as Label
	if title.is_empty():
		if label != null:
			active_title_labels_.erase(uid)
			_release_title_label_(label)
		return
	if label == null:
		label = _acquire_title_label_()
		active_title_labels_[uid] = label
	label.text = title
	label.position = center + Vector2(
		-kThumbnailSize * 0.5,
		-kThumbnailSize * 0.5 - kThumbnailTitleHeight
	)
	label.size = Vector2(kThumbnailSize, kThumbnailTitleHeight)


func _acquire_title_label_() -> Label:
	var label: Label
	if title_label_pool_.is_empty():
		label = Label.new()
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.clip_text = true
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_CHAR
		label.add_theme_font_size_override(
			&"font_size", int(kThumbnailTitleFontSize)
		)
		label.add_theme_color_override(
			&"font_color", Color(0.94, 0.93, 0.9, 1.0)
		)
		label.add_theme_color_override(
			&"font_outline_color", Color(0.04, 0.05, 0.045, 0.95)
		)
		label.add_theme_constant_override(&"outline_size", 2)
		label.z_index = 1
		thumbnail_layer_.add_child(label)
	else:
		label = title_label_pool_.pop_back()
	label.show()
	return label


func _release_title_label_(label: Label) -> void:
	if label == null:
		return
	label.text = ""
	label.hide()
	title_label_pool_.append(label)


func _clear_active_sprites_() -> void:
	for sprite_value: Variant in active_sprites_.values():
		_release_sprite_(sprite_value as Sprite2D)
	active_sprites_.clear()
	for label_value: Variant in active_title_labels_.values():
		_release_title_label_(label_value as Label)
	active_title_labels_.clear()


func _cached_texture_(uid: int) -> Texture2D:
	var document_cache: Dictionary = Dictionary(
		texture_cache_by_document_.get(document_id_, {})
	)
	var cache_entry: Dictionary = Dictionary(document_cache.get(uid, {}))
	if cache_entry.is_empty():
		return null
	var fingerprint: int = int(node_fingerprints_.get(uid, 0))
	if int(cache_entry.get("fingerprint", -1)) != fingerprint:
		document_cache.erase(uid)
		texture_cache_by_document_[document_id_] = document_cache
		return null
	var texture: Texture2D = cache_entry.get("texture") as Texture2D
	if texture == null:
		return null
	texture_use_counter_ += 1
	cache_entry["last_used"] = texture_use_counter_
	document_cache[uid] = cache_entry
	texture_cache_by_document_[document_id_] = document_cache
	return texture


func _queue_texture_generation_(uid: int) -> void:
	if pending_texture_uid_set_.has(uid):
		return
	pending_texture_uid_set_[uid] = true
	pending_texture_uids_.append(uid)
	set_process(true)


func _process(_delta: float) -> void:
	var frame_started: int = Time.get_ticks_usec()
	while not pending_texture_uids_.is_empty():
		var uid: int = pending_texture_uids_.pop_front()
		pending_texture_uid_set_.erase(uid)
		if active_sprites_.has(uid):
			var texture: Texture2D = _cached_texture_(uid)
			if texture == null:
				texture = _create_thumbnail_texture_(uid)
				if texture != null:
					_store_texture_(uid, texture)
			var sprite: Sprite2D = active_sprites_.get(uid) as Sprite2D
			if sprite != null and texture != null:
				_assign_sprite_texture_(sprite, texture)
		if Time.get_ticks_usec() - frame_started \
				>= kGenerationFrameBudgetUsec:
			return
	set_process(false)


func _assign_sprite_texture_(sprite: Sprite2D, texture: Texture2D) -> void:
	sprite.texture = texture
	var texture_size: Vector2 = texture.get_size()
	if texture_size.x <= 0.0 or texture_size.y <= 0.0:
		sprite.scale = Vector2.ONE
		return
	sprite.scale = Vector2(
		kThumbnailSize / texture_size.x,
		kThumbnailSize / texture_size.y
	)


func _create_thumbnail_texture_(uid: int) -> Texture2D:
	var states: PackedInt32Array = PackedInt32Array(
		snapshots_.get(uid, [])
	)
	if states.size() != board_size_ * board_size_:
		return null
	return _texture_from_states_(states)


func _texture_from_states_(states: PackedInt32Array) -> Texture2D:
	var svg: String = _thumbnail_svg_(states)
	var image: Image = Image.new()
	var load_result: Error = image.load_svg_from_string(
		svg,
		kThumbnailTextureScale
	)
	if load_result != OK:
		return null
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)


func _thumbnail_svg_(states: PackedInt32Array) -> String:
	var parts: PackedStringArray = PackedStringArray()
	parts.append(
		'<svg xmlns="http://www.w3.org/2000/svg" '
		+ 'width="116" height="116" viewBox="0 0 116 116">'
	)
	parts.append('<rect width="116" height="116" fill="#bd8952"/>')
	parts.append(
		'<rect x="0.75" y="0.75" width="114.5" height="114.5" '
		+ 'fill="none" stroke="#4a2d17" stroke-width="1.5"/>'
	)
	var inset: float = 8.0
	var grid_size: float = kThumbnailSize - inset * 2.0
	var denominator: float = float(maxi(board_size_ - 1, 1))
	var cell_size: float = grid_size / denominator
	parts.append(
		'<g stroke="#2b1b0f" stroke-opacity="0.82" '
		+ 'stroke-width="0.72">'
	)
	if board_size_ > 1:
		for index: int in range(board_size_):
			var offset: float = inset + float(index) * cell_size
			parts.append(
				'<line x1="%.3f" y1="%.3f" x2="%.3f" y2="%.3f"/>'
				% [inset, offset, inset + grid_size, offset]
			)
			parts.append(
				'<line x1="%.3f" y1="%.3f" x2="%.3f" y2="%.3f"/>'
				% [offset, inset, offset, inset + grid_size]
			)
	parts.append("</g>")
	var stone_radius: float = minf(cell_size * 0.46, 4.3)
	for row: int in range(board_size_):
		for column: int in range(board_size_):
			var state: int = states[row * board_size_ + column]
			if state != 1 and state != 2:
				continue
			var center_x: float = inset + float(column) * cell_size
			var center_y: float = inset + float(row) * cell_size
			var fill: String = "#17191a" if state == 1 else "#f0eee7"
			var stroke: String = "#070809" if state == 1 else "#4d4d49"
			var stone_svg: String = (
				'<circle cx="%.3f" cy="%.3f" r="%.3f" '
				+ 'fill="%s" stroke="%s" stroke-width="0.65"/>'
			) % [center_x, center_y, stone_radius, fill, stroke]
			parts.append(stone_svg)
	parts.append("</svg>")
	return "".join(parts)


func _store_texture_(uid: int, texture: Texture2D) -> void:
	var document_cache: Dictionary = Dictionary(
		texture_cache_by_document_.get(document_id_, {})
	)
	texture_use_counter_ += 1
	document_cache[uid] = {
		"fingerprint": int(node_fingerprints_.get(uid, 0)),
		"texture": texture,
		"last_used": texture_use_counter_,
	}
	texture_cache_by_document_[document_id_] = document_cache
	_enforce_texture_cache_limit_()


func _enforce_texture_cache_limit_() -> void:
	while _texture_cache_size_() > kTextureCacheLimit:
		var oldest_document_id: int = -1
		var oldest_uid: int = -1
		var oldest_use: int = 9223372036854775807
		for document_key: Variant in texture_cache_by_document_.keys():
			var cached_document_id: int = int(document_key)
			var document_cache: Dictionary = Dictionary(
				texture_cache_by_document_.get(cached_document_id, {})
			)
			for uid_value: Variant in document_cache.keys():
				var uid: int = int(uid_value)
				if cached_document_id == document_id_ \
						and active_sprites_.has(uid):
					continue
				var entry: Dictionary = Dictionary(document_cache.get(uid, {}))
				var last_used: int = int(entry.get("last_used", 0))
				if last_used < oldest_use:
					oldest_use = last_used
					oldest_document_id = cached_document_id
					oldest_uid = uid
		if oldest_document_id < 0:
			break
		var oldest_cache: Dictionary = Dictionary(
			texture_cache_by_document_.get(oldest_document_id, {})
		)
		oldest_cache.erase(oldest_uid)
		if oldest_cache.is_empty():
			texture_cache_by_document_.erase(oldest_document_id)
		else:
			texture_cache_by_document_[oldest_document_id] = oldest_cache


func _texture_cache_size_() -> int:
	var total: int = 0
	for document_value: Variant in texture_cache_by_document_.values():
		total += Dictionary(document_value).size()
	return total


func _on_view_resized_() -> void:
	if loading_overlay_.visible or selected_order_.is_empty():
		return
	_apply_view_transform_()


func _thumbnail_rect_(center: Vector2) -> Rect2:
	return Rect2(
		center - Vector2.ONE * (kThumbnailSize * 0.5),
		Vector2.ONE * kThumbnailSize
	)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_handle_mouse_button_(event as InputEventMouseButton)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion_(event as InputEventMouseMotion)


func _handle_mouse_button_(event: InputEventMouseButton) -> void:
	if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
		_zoom_at_(event.position, kZoomStep)
		accept_event()
	elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
		_zoom_at_(event.position, 1.0 / kZoomStep)
		accept_event()
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		dragging_ = event.pressed
		last_drag_position_ = event.position
		accept_event()
	elif event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if _try_selection_action_at_(event.position):
			accept_event()
			return
		var clicked_uid: int = _uid_at_screen_position_(event.position)
		if event.double_click and clicked_uid >= 0 \
				and clicked_uid == selected_uid_:
			_roam_to_selected_()
		else:
			selected_uid_ = clicked_uid
			queue_redraw()
		accept_event()


func _handle_mouse_motion_(event: InputEventMouseMotion) -> void:
	if not dragging_ or (event.button_mask & MOUSE_BUTTON_MASK_RIGHT) == 0:
		return
	pan_ += event.position - last_drag_position_
	last_drag_position_ = event.position
	_apply_view_transform_()
	accept_event()


func _zoom_at_(screen_position: Vector2, factor: float) -> void:
	var old_zoom: float = zoom_
	var world_position: Vector2 = (screen_position - pan_) / old_zoom
	zoom_ = clampf(old_zoom * factor, kMinimumZoom, kMaximumZoom)
	pan_ = screen_position - world_position * zoom_
	_apply_view_transform_()


func _uid_at_screen_position_(screen_position: Vector2) -> int:
	var world_position: Vector2 = (screen_position - pan_) / zoom_
	var found_uid: int = -1
	var center_cell: Vector2i = Vector2i(
		floori(world_position.x / kHitCellSize),
		floori(world_position.y / kHitCellSize)
	)
	var candidates: Array[int] = []
	for y_offset: int in range(-1, 2):
		for x_offset: int in range(-1, 2):
			var cell: Vector2i = center_cell + Vector2i(x_offset, y_offset)
			for uid_value: Variant in Array(
				hit_uids_by_cell_.get(cell, [])
			):
				candidates.append(int(uid_value))
	for index: int in range(candidates.size() - 1, -1, -1):
		var uid: int = candidates[index]
		var center: Vector2 = Vector2(
			node_positions_.get(uid, Vector2.ZERO)
		)
		if _thumbnail_rect_(center).has_point(world_position):
			found_uid = uid
			break
	return found_uid


func _try_selection_action_at_(screen_position: Vector2) -> bool:
	if selected_uid_ < 0 or not node_positions_.has(selected_uid_):
		return false
	var selected_center: Vector2 = Vector2(
		node_positions_.get(selected_uid_, Vector2.ZERO)
	)
	var selected_screen_center: Vector2 = pan_ + selected_center * zoom_
	var selection_half_extent: float = \
		kThumbnailSize * 0.5 * zoom_ + 6.0
	var check_center: Vector2 = selected_screen_center + Vector2(
		-selection_half_extent - kActionIconOffset,
		-selection_half_extent - kActionIconOffset
	)
	if check_center.distance_to(screen_position) <= kActionIconHitRadius:
		_roam_to_selected_()
		return true
	if selected_uid_ == 0:
		return false
	var delete_center: Vector2 = selected_screen_center + Vector2(
		selection_half_extent + kActionIconOffset,
		-selection_half_extent - kActionIconOffset
	)
	if delete_center.distance_to(screen_position) <= kActionIconHitRadius:
		pending_delete_uid_ = selected_uid_
		delete_branch_confirmation_.popup_centered(Vector2i(500, 190))
		return true
	return false


func _roam_to_selected_() -> void:
	if selected_uid_ < 0 or not full_nodes_.has(selected_uid_):
		return
	if selected_uid_ == int(go_notes_.call(&"get_current_uid")):
		current_uid_ = selected_uid_
		_on_exit_pressed_()
		return
	var command: String = "ROAMING,%d;" % selected_uid_
	var result: int = int(go_notes_.execute_command(command))
	if result != 0:
		push_warning(CommandMessages.localize(go_notes_.get_message()))
		return
	current_uid_ = selected_uid_
	_on_exit_pressed_()


func _on_delete_branch_confirmed_() -> void:
	var target_uid: int = pending_delete_uid_
	pending_delete_uid_ = -1
	if target_uid <= 0 or not full_nodes_.has(target_uid):
		push_warning("所选局面已经不存在。")
		return
	var command: String = "CUTBRANCH,%d;" % target_uid
	var result: int = int(go_notes_.execute_command(command))
	if result != 0:
		push_warning(CommandMessages.localize(go_notes_.get_message()))
		return
	selected_uid_ = -1
	rebuild(go_notes_)


func _on_delete_branch_canceled_() -> void:
	pending_delete_uid_ = -1


func _on_exit_pressed_() -> void:
	cancel_generation()
	exit_requested.emit()
