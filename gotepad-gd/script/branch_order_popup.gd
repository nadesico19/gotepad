class_name BranchOrderPopup
extends PopupPanel

signal order_accepted(parent_uid: int, ordered_uids: PackedInt64Array)

@onready var branch_list_: VBoxContainer = \
	$Margin/Content/Scroll/BranchList
@onready var accept_button_: Button = $Margin/Content/Header/Accept
@onready var cancel_button_: Button = $Margin/Content/Header/Cancel

var go_notes_: GoNotes
var parent_uid_: int = -1
var original_uids_: PackedInt64Array = PackedInt64Array()
var branches_: Array[Dictionary] = []


func _ready() -> void:
	accept_button_.pressed.connect(on_accept_pressed_)
	cancel_button_.pressed.connect(hide)


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
	hide()


func rebuild_rows_() -> void:
	for child: Node in branch_list_.get_children():
		branch_list_.remove_child(child)
		child.queue_free()
	if go_notes_ == null:
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
		var up_button: Button = make_arrow_button_("↑", "上移这个分支")
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
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(card)

		var down_button: Button = make_arrow_button_("↓", "下移这个分支")
		down_button.disabled = index == branches_.size() - 1
		down_button.pressed.connect(move_branch_.bind(index, 1))
		row.add_child(down_button)
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


func branch_title_(branch: Dictionary, index: int) -> String:
	var preset_stones: Array = Array(branch.get("preset_stones", []))
	if int(branch.get("color", 0)) == 0 and not preset_stones.is_empty():
		return "预置分支 %d" % (index + 1)
	var color_name: String = "黑" \
		if int(branch.get("color", 0)) == 1 else "白"
	return "%s方落子分支 %d" % [color_name, index + 1]


func branch_summary_(branch: Dictionary) -> String:
	var preset_stones: Array = Array(branch.get("preset_stones", []))
	if int(branch.get("color", 0)) != 0 or preset_stones.is_empty():
		return "第 %d 行，第 %d 列" % [
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
	return "黑 +%d　白 +%d　清除 %d" % [
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
