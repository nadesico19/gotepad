class_name SetupBranchPopup
extends PopupPanel

signal branch_hovered(uid: int)
signal preview_cleared
signal branch_selected(uid: int)

@onready var branch_list_: VBoxContainer = \
	$Margin/Content/Scroll/BranchList


func _ready() -> void:
	popup_hide.connect(on_popup_hidden_)


func rebuild(go_notes: GoNotes, branches: Array[Dictionary]) -> void:
	for child: Node in branch_list_.get_children():
		branch_list_.remove_child(child)
		child.queue_free()
	var board_size: int = int(go_notes.call(&"get_board_size"))
	for index in range(branches.size()):
		var branch: Dictionary = branches[index]
		var uid: int = int(branch.get("uid", -1))
		var states: PackedInt32Array = PackedInt32Array(
			go_notes.call(&"get_position_at", uid)
		)
		if uid < 0 or states.size() != board_size * board_size:
			continue
		var card: SetupBranchCard = SetupBranchCard.new()
		card.setup(
			uid,
			board_size,
			states,
			tr("预置分支 %d") % (index + 1),
			make_summary_(branch)
		)
		card.branch_hovered.connect(on_card_hovered_)
		card.branch_unhovered.connect(on_card_unhovered_)
		card.branch_selected.connect(on_card_selected_)
		branch_list_.add_child(card)


func make_summary_(branch: Dictionary) -> String:
	var black_count: int = 0
	var white_count: int = 0
	var clear_count: int = 0
	var stones: Array = Array(branch.get("preset_stones", []))
	for value: Variant in stones:
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


func on_card_hovered_(uid: int) -> void:
	branch_hovered.emit(uid)


func on_card_unhovered_(_uid: int) -> void:
	preview_cleared.emit()


func on_card_selected_(uid: int) -> void:
	branch_selected.emit(uid)
	hide()


func on_popup_hidden_() -> void:
	preview_cleared.emit()
