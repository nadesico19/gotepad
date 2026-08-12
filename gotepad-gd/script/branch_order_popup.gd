class_name BranchOrderPopup
extends PopupPanel

signal order_accepted(parent_uid: int, ordered_uids: PackedInt64Array)
signal branch_delete_requested(parent_uid: int, branch_uid: int)
signal branch_enter_requested(parent_uid: int, branch_uid: int)

@onready var branch_list_: VBoxContainer = \
	$Margin/Content/Scroll/BranchList
@onready var accept_button_: Button = $Margin/Content/Header/Accept
@onready var cancel_button_: Button = $Margin/Content/Header/Cancel
@onready var delete_confirmation_: ConfirmationDialog = $DeleteConfirmation

var go_notes_: GoNotes
var parent_uid_: int = -1
var original_uids_: PackedInt64Array = PackedInt64Array()
var branches_: Array[Dictionary] = []
var pending_delete_uid_: int = -1


func _ready() -> void:
	accept_button_.pressed.connect(on_accept_pressed_)
	cancel_button_.pressed.connect(cancel)
	delete_confirmation_.confirmed.connect(on_delete_confirmed_)
	delete_confirmation_.canceled.connect(on_delete_canceled_)


func rebuild(
	go_notes: GoNotes,
	parent_uid: int,
	branches: Array[Dictionary]
) -> void:
	go_notes_ = go_notes
	parent_uid_ = parent_uid
	branches_ = branches.duplicate(true)
	original_uids_ = branch_uids_()
	rebuild_rows_()


func cancel() -> void:
	if delete_confirmation_.visible:
		delete_confirmation_.hide()
		pending_delete_uid_ = -1
		return
	hide()


func apply_deleted_branch(branch_uid: int) -> void:
	for index in range(branches_.size()):
		if int(branches_[index].get("uid", -1)) == branch_uid:
			branches_.remove_at(index)
			break
	var original_index: int = original_uids_.find(branch_uid)
	if original_index >= 0:
		original_uids_.remove_at(original_index)
	if branches_.is_empty():
		hide()
		return
	rebuild_rows_()


func rebuild_rows_() -> void:
	for child: Node in branch_list_.get_children():
		branch_list_.remove_child(child)
		child.queue_free()
	if go_notes_ == null:
		return
	if branches_.is_empty():
		var empty_label: Label = Label.new()
		empty_label.custom_minimum_size = Vector2(0.0, 96.0)
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		empty_label.text = tr("当前局面没有下一手分支")
		empty_label.add_theme_color_override(
			&"font_color", Color(0.78, 0.76, 0.70)
		)
		branch_list_.add_child(empty_label)
		return

	var board_size: int = int(go_notes_.call(&"get_board_size"))
	for index in range(branches_.size()):
		var branch: Dictionary = branches_[index]
		var uid: int = int(branch.get("uid", -1))
		var states: PackedInt32Array = PackedInt32Array(
			go_notes_.call(&"get_position_at", uid)
		)
		if uid < 0 or states.size() != board_size * board_size:
			continue

		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override(&"separation", 6)
		var up_button: Button = make_arrow_button_("↑", tr("上移这个分支"))
		up_button.disabled = index == 0
		up_button.pressed.connect(move_branch_.bind(index, -1))
		row.add_child(up_button)

		var card: SetupBranchCard = SetupBranchCard.new()
		card.setup(
			uid,
			board_size,
			states,
			branch_title_(branch, index),
			branch_summary_(branch)
		)
		card.branch_double_clicked.connect(request_enter_)
		row.add_child(card)

		var enter_button: Button = make_enter_button_()
		enter_button.pressed.connect(request_enter_.bind(uid))
		row.add_child(enter_button)

		var down_button: Button = make_arrow_button_("↓", tr("下移这个分支"))
		down_button.disabled = index == branches_.size() - 1
		down_button.pressed.connect(move_branch_.bind(index, 1))
		row.add_child(down_button)

		var delete_button: Button = make_delete_button_()
		delete_button.pressed.connect(request_delete_.bind(uid))
		row.add_child(delete_button)
		branch_list_.add_child(row)


func make_arrow_button_(text: String, tooltip: String) -> Button:
	var button: Button = Button.new()
	button.custom_minimum_size = Vector2(38.0, 124.0)
	button.focus_mode = Control.FOCUS_NONE
	button.flat = true
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.tooltip_text = tooltip
	button.text = text
	button.add_theme_font_size_override(&"font_size", 28)
	return button


func make_delete_button_() -> Button:
	var button: Button = make_arrow_button_("✕", tr("删除这个分支"))
	button.add_theme_color_override(&"font_color", Color(0.96, 0.24, 0.24))
	button.add_theme_color_override(&"font_hover_color", Color(1.0, 0.4, 0.4))
	button.add_theme_color_override(&"font_pressed_color", Color(1.0, 0.3, 0.3))
	return button


func make_enter_button_() -> Button:
	var button: Button = make_arrow_button_(tr("进入"), tr("进入这个分支"))
	button.custom_minimum_size.x = 52.0
	button.add_theme_font_size_override(&"font_size", 17)
	button.add_theme_color_override(&"font_color", Color(0.62, 0.82, 1.0))
	button.add_theme_color_override(&"font_hover_color", Color(0.76, 0.9, 1.0))
	button.add_theme_color_override(&"font_pressed_color", Color(0.48, 0.7, 1.0))
	return button


func branch_title_(branch: Dictionary, index: int) -> String:
	var preset_stones: Array = Array(branch.get("preset_stones", []))
	if int(branch.get("color", 0)) == 0 and not preset_stones.is_empty():
		return tr("预置分支 %d") % (index + 1)
	var color_name: String = tr("黑") \
		if int(branch.get("color", 0)) == 1 else tr("白")
	return tr("%s方落子分支 %d") % [color_name, index + 1]


func branch_summary_(branch: Dictionary) -> String:
	var preset_stones: Array = Array(branch.get("preset_stones", []))
	if int(branch.get("color", 0)) != 0 or preset_stones.is_empty():
		return tr("第 %d 行，第 %d 列") % [
			int(branch.get("row", 0)),
			int(branch.get("column", 0))
		]
	var black_count: int = 0
	var white_count: int = 0
	var clear_count: int = 0
	for value: Variant in preset_stones:
		var stone: Dictionary = Dictionary(value)
		match int(stone.get("color", -1)):
			0:
				clear_count += 1
			1:
				black_count += 1
			2:
				white_count += 1
	return tr("黑 +%d　白 +%d　清除 %d") % [
		black_count, white_count, clear_count
	]


func move_branch_(index: int, direction: int) -> void:
	var target: int = index + direction
	if index < 0 or index >= branches_.size() \
			or target < 0 or target >= branches_.size():
		return
	var branch: Dictionary = branches_[index]
	branches_.remove_at(index)
	branches_.insert(target, branch)
	rebuild_rows_()


func request_delete_(branch_uid: int) -> void:
	if branch_uid < 0:
		return
	pending_delete_uid_ = branch_uid
	delete_confirmation_.dialog_text = tr("DIALOG_DELETE_ORDER_BRANCH_MESSAGE")
	delete_confirmation_.popup_centered(Vector2i(460, 180))


func request_enter_(branch_uid: int) -> void:
	if branch_uid >= 0:
		branch_enter_requested.emit(parent_uid_, branch_uid)


func on_delete_confirmed_() -> void:
	var branch_uid: int = pending_delete_uid_
	pending_delete_uid_ = -1
	if branch_uid >= 0:
		branch_delete_requested.emit(parent_uid_, branch_uid)


func on_delete_canceled_() -> void:
	pending_delete_uid_ = -1


func refresh_localized_texts() -> void:
	if go_notes_ != null:
		rebuild_rows_()


func branch_uids_() -> PackedInt64Array:
	var result: PackedInt64Array = PackedInt64Array()
	for branch: Dictionary in branches_:
		result.append(int(branch.get("uid", -1)))
	return result


func on_accept_pressed_() -> void:
	var ordered_uids: PackedInt64Array = branch_uids_()
	hide()
	if ordered_uids == original_uids_:
		return
	order_accepted.emit(parent_uid_, ordered_uids)
