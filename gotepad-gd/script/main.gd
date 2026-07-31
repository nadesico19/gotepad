extends Node2D

const kBoardToolbarGap: float = 8.0
const kBlack: int = 1
const kWhite: int = 2
const kNoteMarkDisabled: int = 0
const kNoteSequentialMarkMode: int = 1
const kNoteSymbolMarkMode: int = 2
const kPendingPanelNone: int = 0
const kPendingPanelNotes: int = 1
const kPendingPanelSgfMetadata: int = 2
const kSequentialMarkLetters: String = \
	"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
const kPptxTemplatePath: String = \
	"res://assets/publication/go_book_b5_landscape_template.pptx"


class DocumentState extends RefCounted:
	var notes: GoNotes
	var title: String = ""
	var file_path: String = ""
	var initialized: bool = false
	var interactions_locked: bool = false


@onready var board_: GoBoardView = $Board
@onready var camera_: Camera2D = $Camera
@onready var background_layer_: CanvasLayer = $Background
@onready var interface_layer_: CanvasLayer = $Interface
@onready var branch_visualization_layer_: CanvasLayer = \
	$BranchVisualizationLayer
@onready var branch_visualization_: Control = \
	$BranchVisualizationLayer/BranchVisualization
@onready var note_mark_layer_: CanvasLayer = $NoteMarkLayer
@onready var note_mark_toolbar_: VBoxContainer = \
	$NoteMarkLayer/NoteMarkToolBar
@onready var next_mark_label_: Label = \
	$NoteMarkLayer/NoteMarkToolBar/NextMarkLabel
@onready var note_triangle_button_: Button = \
	$NoteMarkLayer/NoteMarkToolBar/Triangle
@onready var note_square_button_: Button = \
	$NoteMarkLayer/NoteMarkToolBar/Square
@onready var note_circle_button_: Button = \
	$NoteMarkLayer/NoteMarkToolBar/Circle
@onready var note_cross_button_: Button = \
	$NoteMarkLayer/NoteMarkToolBar/Cross
@onready var note_erase_button_: Button = \
	$NoteMarkLayer/NoteMarkToolBar/Erase
@onready var note_mark_accept_button_: Button = \
	$NoteMarkLayer/NoteMarkToolBar/Accept
@onready var note_mark_cancel_button_: Button = \
	$NoteMarkLayer/NoteMarkToolBar/Cancel
@onready var board_size_dialog_: BoardSizeDialog = $Interface/BoardSizeDialog
@onready var board_toolbar_: AdaptiveToolbar = $Interface/BoardToolBar
@onready var variation_toolbar_: VBoxContainer = \
	$Interface/VariationToolBar
@onready var variation_exit_button_: Button = \
	$Interface/VariationToolBar/ExitButton
@onready var variation_keep_button_: Button = \
	$Interface/VariationToolBar/KeepBranchButton
@onready var undo_button_: Button = $Interface/BoardToolBar/UndoButton
@onready var redo_button_: Button = $Interface/BoardToolBar/RedoButton
@onready var find_previous_button_: Button = \
	$Interface/BoardToolBar/FindPreviousButton
@onready var find_next_button_: Button = \
	$Interface/BoardToolBar/FindNextButton
@onready var reorder_branch_button_: Button = \
	$Interface/BoardToolBar/ReorderBranchButton
@onready var cut_branch_button_: Button = \
	$Interface/BoardToolBar/CutBranchButton
@onready var variation_button_: Button = \
	$Interface/BoardToolBar/VariationButton
@onready var branch_visualization_button_: Button = \
	$Interface/BoardToolBar/BranchVisualizationButton
@onready var notes_button_: Button = $Interface/BoardToolBar/NotesButton
@onready var notes_panel_: NotesPanel = $Interface/NotesPanel
@onready var sgf_metadata_button_: Button = \
	$Interface/BoardToolBar/SgfMetadataButton
@onready var sgf_metadata_panel_: SgfMetadataPanel = \
	$Interface/SgfMetadataPanel
@onready var settings_ui_: Control = $Interface/SettingsUI
@onready var undo_unavailable_mark_: TextureRect = \
	$Interface/BoardToolBar/UndoButton/UnavailableMark
@onready var redo_unavailable_mark_: TextureRect = \
	$Interface/BoardToolBar/RedoButton/UnavailableMark
@onready var board_lock_checkbox_: CheckBox = \
	$Interface/BoardToolBar/BoardLockControl/CheckBox
@onready var next_color_button_: Button = \
	$Interface/BoardToolBar/NextColorButton
@onready var preset_accept_button_: Button = \
	$Interface/BoardToolBar/PresetAcceptButton
@onready var preset_cancel_button_: Button = \
	$Interface/BoardToolBar/PresetCancelButton
@onready var setup_branch_button_: Button = \
	$Interface/BoardToolBar/SetupBranchButton
@onready var setup_branch_count_: Label = \
	$Interface/BoardToolBar/SetupBranchButton/CountBadge
@onready var setup_branch_popup_: SetupBranchPopup = \
	$Interface/SetupBranchPopup
@onready var branch_order_popup_: BranchOrderPopup = \
	$Interface/BranchOrderPopup
@onready var document_tab_bar_: DocumentTabBar = $Interface/DocumentTabBar
@onready var new_tab_button_: Button = $Interface/NewTabButton
@onready var save_button_: Button = $Interface/SaveButton
@onready var save_as_button_: Button = $Interface/SaveAsButton
@onready var export_button_: Button = $Interface/ExportButton
@onready var save_file_dialog_: FileDialog = $Interface/SaveFileDialog
@onready var save_error_dialog_: AcceptDialog = $Interface/SaveErrorDialog
@onready var save_confirmation_: ConfirmationDialog = \
	$Interface/SaveConfirmation
@onready var export_file_dialog_: FileDialog = $Interface/ExportFileDialog
@onready var export_error_dialog_: AcceptDialog = \
	$Interface/ExportErrorDialog
@onready var export_success_dialog_: AcceptDialog = \
	$Interface/ExportSuccessDialog
@onready var close_tab_confirmation_: ConfirmationDialog = \
	$Interface/CloseTabConfirmation
@onready var preset_button_: Button = $Board/PresetButton
@onready var preset_unavailable_mark_: TextureRect = \
	$Board/PresetButton/UnavailableMark

var go_notes_: GoNotes
var setup_branches_: Array[Dictionary] = []
var documents_: Array[DocumentState] = []
var active_document_index_: int = -1
var pending_close_index_: int = -1
var note_mark_mode_: int = kNoteMarkDisabled
var note_mark_note_index_: int = -1
var note_mark_original_sequential_: Array[Dictionary] = []
var note_mark_original_symbols_: Array[Dictionary] = []
var pending_save_path_: String = ""
var pending_side_panel_: int = kPendingPanelNone


func _enter_tree() -> void:
	var document: DocumentState = DocumentState.new()
	document.notes = GoNotes.new()
	document.title = unique_document_title_("新建笔记")
	documents_.append(document)
	active_document_index_ = 0
	go_notes_ = document.notes
	var board: GoBoardView = get_node("Board") as GoBoardView
	if board == null or not board.bind_go_notes(go_notes_):
		push_error("Failed to bind the main board to GoNotes.")


func _ready() -> void:
	board_size_dialog_.create_requested.connect(on_create_requested_)
	board_size_dialog_.sgf_load_requested.connect(on_sgf_load_requested_)
	board_size_dialog_.cancel_requested.connect(
		on_board_creation_cancel_requested_
	)
	undo_button_.pressed.connect(on_undo_requested_)
	redo_button_.pressed.connect(on_redo_requested_)
	find_previous_button_.pressed.connect(on_find_previous_requested_)
	find_next_button_.pressed.connect(on_find_next_requested_)
	reorder_branch_button_.pressed.connect(on_reorder_branch_requested_)
	cut_branch_button_.pressed.connect(on_cut_branch_requested_)
	variation_button_.pressed.connect(on_variation_requested_)
	branch_visualization_button_.pressed.connect(
		on_branch_visualization_requested_
	)
	notes_button_.pressed.connect(on_notes_requested_)
	notes_panel_.panel_visibility_changed.connect(
		on_notes_panel_visibility_changed_
	)
	sgf_metadata_button_.pressed.connect(on_sgf_metadata_requested_)
	sgf_metadata_panel_.panel_visibility_changed.connect(
		on_sgf_metadata_panel_visibility_changed_
	)
	notes_panel_.displayed_marks_changed.connect(
		on_displayed_note_marks_changed_
	)
	notes_panel_.mark_mode_requested.connect(on_note_mark_mode_requested_)
	branch_visualization_.connect(
		&"exit_requested",
		Callable(self, "on_branch_visualization_exit_requested_")
	)
	variation_exit_button_.pressed.connect(on_variation_exit_requested_)
	variation_keep_button_.pressed.connect(on_variation_keep_requested_)
	board_.find_mode_changed.connect(on_find_mode_changed_)
	board_.cut_branch_mode_changed.connect(on_cut_branch_mode_changed_)
	board_.variation_mode_changed.connect(on_variation_mode_changed_)
	board_.next_color_changed.connect(on_next_color_changed_)
	board_.preset_mode_changed.connect(on_preset_mode_changed_)
	board_.note_mark_cancel_requested.connect(on_note_mark_cancel_requested_)
	board_.note_mark_draft_changed.connect(on_note_mark_draft_changed_)
	board_.setup_branches_changed.connect(on_setup_branches_changed_)
	setup_branch_button_.pressed.connect(on_setup_branch_requested_)
	document_tab_bar_.tab_selected.connect(on_document_tab_selected_)
	document_tab_bar_.tab_close_requested.connect(
		on_document_tab_close_requested_
	)
	new_tab_button_.pressed.connect(on_new_tab_requested_)
	save_button_.pressed.connect(on_save_requested_)
	save_as_button_.pressed.connect(on_save_as_requested_)
	export_button_.pressed.connect(on_export_requested_)
	save_file_dialog_.file_selected.connect(on_save_file_selected_)
	save_confirmation_.confirmed.connect(on_save_confirmed_)
	save_confirmation_.canceled.connect(on_save_canceled_)
	export_file_dialog_.file_selected.connect(on_export_file_selected_)
	close_tab_confirmation_.confirmed.connect(on_close_tab_confirmed_)
	close_tab_confirmation_.canceled.connect(on_close_tab_canceled_)
	setup_branch_popup_.branch_hovered.connect(
		on_setup_branch_hovered_
	)
	setup_branch_popup_.preview_cleared.connect(
		on_setup_branch_preview_cleared_
	)
	setup_branch_popup_.branch_selected.connect(
		on_setup_branch_selected_
	)
	branch_order_popup_.order_accepted.connect(
		on_branch_order_accepted_
	)
	var changed_callback: Callable = Callable(
		self, "on_go_notes_history_changed_"
	)
	go_notes_.connect(&"changed", changed_callback)
	board_lock_checkbox_.toggled.connect(on_board_lock_toggled_)
	next_color_button_.pressed.connect(on_next_color_requested_)
	note_triangle_button_.pressed.connect(
		on_note_symbol_selected_.bind("TR")
	)
	note_square_button_.pressed.connect(
		on_note_symbol_selected_.bind("SQ")
	)
	note_circle_button_.pressed.connect(
		on_note_symbol_selected_.bind("CR")
	)
	note_cross_button_.pressed.connect(
		on_note_symbol_selected_.bind("MA")
	)
	note_erase_button_.pressed.connect(
		on_note_symbol_selected_.bind("")
	)
	note_mark_accept_button_.pressed.connect(on_note_mark_accept_requested_)
	note_mark_cancel_button_.pressed.connect(on_note_mark_cancel_requested_)
	preset_accept_button_.pressed.connect(on_preset_accept_requested_)
	preset_cancel_button_.pressed.connect(on_preset_cancel_requested_)
	preset_button_.pressed.connect(on_preset_requested_)
	get_window().size_changed.connect(on_board_layout_changed_)
	board_.board_texture_changed.connect(on_board_assets_changed_)
	board_.set_interactions_locked(
		board_lock_checkbox_.button_pressed
	)
	update_history_buttons_()
	update_preset_button_()
	update_next_color_button_(board_.get_next_color())
	on_setup_branches_changed_(board_.get_setup_branches())
	update_reorder_branch_button_()
	refresh_document_tabs_()
	on_board_layout_changed_()


func _input(event: InputEvent) -> void:
	if export_success_dialog_.visible and event is InputEventKey:
		var success_key_event: InputEventKey = event as InputEventKey
		if success_key_event.pressed and not success_key_event.echo \
				and success_key_event.keycode in [
					KEY_SPACE, KEY_ESCAPE, KEY_ENTER, KEY_KP_ENTER
				]:
			export_success_dialog_.hide()
			get_viewport().set_input_as_handled()
			return
	if save_confirmation_.visible:
		if event is InputEventKey:
			var save_key_event: InputEventKey = event as InputEventKey
			if save_key_event.pressed and not save_key_event.echo \
					and save_key_event.keycode == KEY_ESCAPE:
				save_confirmation_.hide()
				on_save_canceled_()
				get_viewport().set_input_as_handled()
		return
	if close_tab_confirmation_.visible:
		return
	if setup_branch_popup_.visible and event is InputEventKey:
		var popup_key_event: InputEventKey = event as InputEventKey
		if popup_key_event.pressed and not popup_key_event.echo \
				and popup_key_event.keycode == KEY_ESCAPE:
			setup_branch_popup_.hide()
			get_viewport().set_input_as_handled()
			return
	if branch_order_popup_.visible and event is InputEventKey:
		var order_key_event: InputEventKey = event as InputEventKey
		if order_key_event.pressed and not order_key_event.echo \
				and order_key_event.keycode == KEY_ESCAPE:
			branch_order_popup_.cancel()
			get_viewport().set_input_as_handled()
			return
	if branch_visualization_layer_.visible:
		if event is InputEventKey:
			var branch_key_event: InputEventKey = event as InputEventKey
			if branch_key_event.pressed and not branch_key_event.echo \
					and branch_key_event.keycode == KEY_ESCAPE:
				var dialog_canceled: bool = bool(
					branch_visualization_.call(&"cancel_dialog")
				)
				if not dialog_canceled:
					on_branch_visualization_exit_requested_()
				get_viewport().set_input_as_handled()
		return
	if note_mark_mode_ != kNoteMarkDisabled:
		return
	if event is not InputEventKey or board_.is_variation_mode():
		return
	var key_event: InputEventKey = event as InputEventKey
	if not key_event.pressed or key_event.echo \
			or not key_event.ctrl_pressed \
			or key_event.alt_pressed or key_event.meta_pressed:
		return
	if key_event.shift_pressed:
		return

	var focus_owner: Control = get_viewport().gui_get_focus_owner()
	if focus_owner is LineEdit or focus_owner is TextEdit:
		return
	if board_.is_preset_mode() and key_event.keycode != KEY_Q:
		return

	var handled: bool = false
	match key_event.keycode:
		KEY_N:
			on_new_tab_requested_()
			handled = true
		KEY_S:
			on_save_requested_()
			handled = true
		KEY_A:
			on_save_as_requested_()
			handled = true
		KEY_O:
			settings_ui_.call(&"toggle_panel")
			handled = true
		KEY_Z:
			handled = perform_undo_()
		KEY_R:
			handled = perform_redo_()
		KEY_G:
			on_find_previous_requested_()
			handled = true
		KEY_F:
			on_find_next_requested_()
			handled = true
		KEY_X:
			on_cut_branch_requested_()
			handled = true
		KEY_E:
			on_board_lock_toggled_(not board_.is_interactions_locked())
			handled = true
		KEY_Q:
			on_next_color_requested_()
			handled = true
		KEY_H:
			on_preset_requested_()
			handled = true
		KEY_T:
			on_variation_requested_()
			handled = true
		KEY_M:
			on_notes_requested_()
			handled = true
		KEY_W:
			on_branch_visualization_requested_()
			handled = true
		_:
			return
	if handled:
		get_viewport().set_input_as_handled()


func on_undo_requested_() -> void:
	var _succeeded: bool = perform_undo_()


func on_redo_requested_() -> void:
	var _succeeded: bool = perform_redo_()


func on_find_previous_requested_() -> void:
	board_.toggle_find_mode(-1)


func on_find_next_requested_() -> void:
	board_.toggle_find_mode(1)


func on_find_mode_changed_(direction: int) -> void:
	find_previous_button_.set_pressed_no_signal(direction == -1)
	find_next_button_.set_pressed_no_signal(direction == 1)


func on_cut_branch_requested_() -> void:
	board_.toggle_cut_branch_mode()


func on_cut_branch_mode_changed_(enabled: bool) -> void:
	cut_branch_button_.set_pressed_no_signal(enabled)


func on_reorder_branch_requested_() -> void:
	var branches: Array = Array(go_notes_.call(&"get_next_moves"))
	if branches.size() < 2:
		return
	if setup_branch_popup_.visible:
		setup_branch_popup_.hide()
	if cut_branch_button_.button_pressed:
		board_.toggle_cut_branch_mode()
	if find_previous_button_.button_pressed:
		board_.toggle_find_mode(-1)
	if find_next_button_.button_pressed:
		board_.toggle_find_mode(1)
	var typed_branches: Array[Dictionary] = []
	for value: Variant in branches:
		if value is Dictionary:
			typed_branches.append(Dictionary(value))
	branch_order_popup_.rebuild(
		go_notes_,
		int(go_notes_.get_current_uid()),
		typed_branches
	)
	var popup_size: Vector2i = Vector2i(
		440,
		clampi(92 + typed_branches.size() * 132, 260, 560)
	)
	var viewport_size: Vector2i = Vector2i(get_viewport_rect().size)
	var popup_position: Vector2 = Vector2(
		reorder_branch_button_.global_position.x \
			+ reorder_branch_button_.size.x + 8.0,
		reorder_branch_button_.global_position.y
	)
	if popup_position.x + popup_size.x > viewport_size.x - 8:
		popup_position.x = reorder_branch_button_.global_position.x \
			- float(popup_size.x) - 8.0
	popup_position.y = clampf(
		popup_position.y,
		8.0,
		maxf(float(viewport_size.y - popup_size.y - 8), 8.0)
	)
	branch_order_popup_.popup(Rect2i(
		Vector2i(roundi(popup_position.x), roundi(popup_position.y)),
		popup_size
	))


func on_branch_order_accepted_(
	parent_uid: int,
	ordered_uids: PackedInt64Array
) -> void:
	if parent_uid != int(go_notes_.get_current_uid()):
		push_warning("当前局面已经改变，分支顺序调整已放弃。")
		return
	var result: int = int(
		go_notes_.call(&"reorder_branches", parent_uid, ordered_uids)
	)
	if result != 0:
		push_warning(CommandMessages.localize(go_notes_.get_message()))


func update_reorder_branch_button_() -> void:
	var branch_count: int = Array(
		go_notes_.call(&"get_next_moves")
	).size()
	reorder_branch_button_.disabled = branch_count < 2
	reorder_branch_button_.tooltip_text = \
		"调整下一手分支顺序（%d）" % branch_count \
		if branch_count >= 2 else "当前局面没有可调整的多个分支"


func on_setup_branches_changed_(branches: Array[Dictionary]) -> void:
	setup_branches_ = branches.duplicate(true)
	var available: bool = not setup_branches_.is_empty() \
		and not board_.is_variation_mode() \
		and not board_.is_preset_mode()
	setup_branch_button_.visible = available
	setup_branch_count_.text = str(setup_branches_.size())
	setup_branch_button_.tooltip_text = \
		"选择下一步的预置棋子分支（%d）" % setup_branches_.size()
	if setup_branch_popup_.visible:
		setup_branch_popup_.hide()
	update_reorder_branch_button_()
	call_deferred(&"position_board_toolbar_")


func on_setup_branch_requested_() -> void:
	if setup_branches_.is_empty():
		return
	setup_branch_popup_.rebuild(go_notes_, setup_branches_)
	var popup_size: Vector2i = Vector2i(
		356,
		clampi(76 + setup_branches_.size() * 132, 220, 520)
	)
	var viewport_size: Vector2i = Vector2i(get_viewport_rect().size)
	var popup_position: Vector2 = Vector2(
		setup_branch_button_.global_position.x \
			+ setup_branch_button_.size.x + 8.0,
		setup_branch_button_.global_position.y
	)
	if popup_position.x + popup_size.x > viewport_size.x - 8:
		popup_position.x = setup_branch_button_.global_position.x \
			- float(popup_size.x) - 8.0
	popup_position.y = clampf(
		popup_position.y,
		8.0,
		maxf(float(viewport_size.y - popup_size.y - 8), 8.0)
	)
	setup_branch_popup_.popup(Rect2i(
		Vector2i(roundi(popup_position.x), roundi(popup_position.y)),
		popup_size
	))


func on_setup_branch_hovered_(uid: int) -> void:
	var _previewed: bool = board_.set_setup_branch_preview(uid)


func on_setup_branch_preview_cleared_() -> void:
	board_.clear_setup_branch_preview()


func on_setup_branch_selected_(uid: int) -> void:
	if not board_.roam_to_setup_branch(uid):
		push_warning("所选预置棋子分支已经不存在。")


func on_new_tab_requested_() -> void:
	var document: DocumentState = DocumentState.new()
	document.notes = GoNotes.new()
	document.title = unique_document_title_("新建笔记")
	documents_.append(document)
	switch_document_(documents_.size() - 1)


func on_save_requested_() -> void:
	if active_document_index_ < 0 \
			or active_document_index_ >= documents_.size():
		return
	var document: DocumentState = documents_[active_document_index_]
	if document.file_path.is_empty():
		show_save_dialog_()
		return
	request_save_confirmation_(document.file_path)


func on_save_as_requested_() -> void:
	if active_document_index_ < 0 \
			or active_document_index_ >= documents_.size():
		return
	show_save_dialog_()


func show_save_dialog_() -> void:
	var document: DocumentState = documents_[active_document_index_]
	if document.file_path.is_empty():
		save_file_dialog_.current_file = "%s.sgf" % document.title
	else:
		save_file_dialog_.current_path = document.file_path
	save_file_dialog_.popup_centered_ratio(0.72)


func on_save_file_selected_(path: String) -> void:
	var save_path: String = path
	if save_path.get_extension().to_lower() != "sgf":
		save_path += ".sgf"
	request_save_confirmation_(save_path)


func request_save_confirmation_(path: String) -> void:
	pending_save_path_ = path
	save_confirmation_.dialog_text = "是否将当前棋谱保存到：\n%s" % path
	save_confirmation_.popup_centered(Vector2i(520, 190))


func on_save_confirmed_() -> void:
	var save_path: String = pending_save_path_
	pending_save_path_ = ""
	if save_path.is_empty():
		return
	save_document_to_(save_path)


func on_save_canceled_() -> void:
	pending_save_path_ = ""


func save_document_to_(path: String) -> bool:
	if active_document_index_ < 0 \
			or active_document_index_ >= documents_.size():
		return false
	var saved: bool = bool(go_notes_.call(&"save_sgf_file", path))
	if not saved:
		save_error_dialog_.dialog_text = CommandMessages.localize(
			go_notes_.get_message()
		)
		save_error_dialog_.popup_centered(Vector2i(480, 180))
		return false

	var document: DocumentState = documents_[active_document_index_]
	document.file_path = path
	var file_name: String = path.get_file()
	if file_name.is_empty():
		file_name = "新建笔记.sgf"
	document.title = unique_document_title_(
		file_name, active_document_index_
	)
	refresh_document_tabs_()
	return true


func on_export_requested_() -> void:
	if active_document_index_ < 0 \
			or active_document_index_ >= documents_.size():
		return
	var document: DocumentState = documents_[active_document_index_]
	export_file_dialog_.current_file = "%s.pptx" % document.title
	export_file_dialog_.popup_centered_ratio(0.72)


func on_export_file_selected_(path: String) -> void:
	var export_path: String = path
	if export_path.get_extension().to_lower() != "pptx":
		export_path += ".pptx"
	var exported: bool = bool(go_notes_.call(
		&"export_pptx_file", export_path, kPptxTemplatePath
	))
	if not exported:
		export_error_dialog_.dialog_text = CommandMessages.localize(
			str(go_notes_.get_message())
		)
		export_error_dialog_.popup_centered(Vector2i(480, 180))
		return
	export_success_dialog_.popup_centered(Vector2i(360, 150))


func on_document_tab_close_requested_(index: int) -> void:
	if index < 0 or index >= documents_.size():
		return
	pending_close_index_ = index
	close_tab_confirmation_.dialog_text = "是否关闭标签“%s”？" \
		% documents_[index].title
	close_tab_confirmation_.popup_centered()


func on_close_tab_confirmed_() -> void:
	var index: int = pending_close_index_
	pending_close_index_ = -1
	if index < 0 or index >= documents_.size():
		return

	if index == active_document_index_:
		leave_transient_modes_()
		disconnect_history_signal_(go_notes_)
		documents_.remove_at(index)
		active_document_index_ = -1
		if documents_.is_empty():
			var replacement: DocumentState = DocumentState.new()
			replacement.notes = GoNotes.new()
			replacement.title = unique_document_title_("新建笔记")
			documents_.append(replacement)
		switch_document_(mini(index, documents_.size() - 1))
		return

	documents_.remove_at(index)
	if index < active_document_index_:
		active_document_index_ -= 1
	refresh_document_tabs_()


func on_close_tab_canceled_() -> void:
	pending_close_index_ = -1


func on_branch_visualization_requested_() -> void:
	if setup_branch_popup_.visible:
		setup_branch_popup_.hide()
	background_layer_.visible = false
	board_.hide()
	interface_layer_.visible = false
	branch_visualization_layer_.visible = true
	branch_visualization_.call(&"rebuild", go_notes_)


func on_branch_visualization_exit_requested_() -> void:
	branch_visualization_.call(&"cancel_generation")
	branch_visualization_layer_.visible = false
	background_layer_.visible = true
	board_.show()
	interface_layer_.visible = true
	call_deferred(&"position_board_toolbar_")


func on_notes_requested_() -> void:
	if notes_panel_.is_panel_open():
		pending_side_panel_ = kPendingPanelNone
		notes_panel_.close_panel()
		return
	if sgf_metadata_panel_.is_panel_open():
		pending_side_panel_ = kPendingPanelNotes
		sgf_metadata_panel_.close_panel()
		return
	pending_side_panel_ = kPendingPanelNone
	notes_panel_.open_panel(go_notes_)


func on_notes_panel_visibility_changed_(opened: bool) -> void:
	notes_button_.set_pressed_no_signal(opened)
	if opened:
		pending_side_panel_ = kPendingPanelNone
		sgf_metadata_button_.set_pressed_no_signal(false)
	elif pending_side_panel_ == kPendingPanelSgfMetadata:
		pending_side_panel_ = kPendingPanelNone
		sgf_metadata_panel_.open_panel(go_notes_)
	call_deferred(&"position_side_panels_")


func on_sgf_metadata_requested_() -> void:
	if sgf_metadata_panel_.is_panel_open():
		pending_side_panel_ = kPendingPanelNone
		sgf_metadata_panel_.close_panel()
		return
	if notes_panel_.is_panel_open():
		pending_side_panel_ = kPendingPanelSgfMetadata
		notes_panel_.close_panel()
		return
	pending_side_panel_ = kPendingPanelNone
	sgf_metadata_panel_.open_panel(go_notes_)


func on_sgf_metadata_panel_visibility_changed_(opened: bool) -> void:
	sgf_metadata_button_.set_pressed_no_signal(opened)
	if opened:
		pending_side_panel_ = kPendingPanelNone
		notes_button_.set_pressed_no_signal(false)
	elif pending_side_panel_ == kPendingPanelNotes:
		pending_side_panel_ = kPendingPanelNone
		notes_panel_.open_panel(go_notes_)
	call_deferred(&"position_side_panels_")


func on_displayed_note_marks_changed_(
	sequential_marks: Array[Dictionary],
	symbol_marks: Array[Dictionary]
) -> void:
	board_.set_displayed_note_marks(sequential_marks, symbol_marks)


func on_note_mark_mode_requested_(
	mode: int,
	note_index: int,
	sequential_marks: Array[Dictionary],
	symbol_marks: Array[Dictionary],
	initial_symbol: String
) -> void:
	if mode != kNoteSequentialMarkMode and mode != kNoteSymbolMarkMode:
		return
	note_mark_mode_ = mode
	note_mark_note_index_ = note_index
	note_mark_original_sequential_ = sequential_marks.duplicate(true)
	note_mark_original_symbols_ = symbol_marks.duplicate(true)
	interface_layer_.visible = false
	note_mark_layer_.visible = true
	if mode == kNoteSequentialMarkMode:
		board_.begin_note_sequential_mark_mode(
			sequential_marks, symbol_marks
		)
	else:
		board_.begin_note_symbol_mark_mode(
			sequential_marks, symbol_marks, initial_symbol
		)
		set_note_symbol_selection_(initial_symbol)
	update_note_mark_toolbar_()
	call_deferred(&"position_note_mark_toolbar_")


func on_note_symbol_selected_(symbol: String) -> void:
	if note_mark_mode_ != kNoteSymbolMarkMode:
		return
	board_.set_active_note_symbol(symbol)
	set_note_symbol_selection_(symbol)


func set_note_symbol_selection_(symbol: String) -> void:
	var selections: Dictionary = {
		"TR": note_triangle_button_,
		"SQ": note_square_button_,
		"CR": note_circle_button_,
		"MA": note_cross_button_,
		"": note_erase_button_
	}
	for key: String in selections:
		var button: Button = selections[key] as Button
		var selected: bool = key == symbol
		button.set_pressed_no_signal(selected)
		button.add_theme_font_size_override(
			&"font_size",
			40 if selected else (34 if key.is_empty() else 38)
		)
		button.add_theme_constant_override(
			&"outline_size", 3 if selected else 0
		)


func on_note_mark_draft_changed_() -> void:
	update_note_mark_toolbar_()


func update_note_mark_toolbar_() -> void:
	var sequential: bool = note_mark_mode_ == kNoteSequentialMarkMode
	next_mark_label_.visible = sequential
	note_triangle_button_.visible = not sequential
	note_square_button_.visible = not sequential
	note_circle_button_.visible = not sequential
	note_cross_button_.visible = not sequential
	note_erase_button_.visible = not sequential
	if sequential:
		var mark_count: int = board_.get_note_sequential_mark_count()
		next_mark_label_.text = kSequentialMarkLetters.substr(
			clampi(mark_count, 0, kSequentialMarkLetters.length() - 1), 1
		) if mark_count < kSequentialMarkLetters.length() else "满"


func on_note_mark_accept_requested_() -> void:
	if note_mark_mode_ == kNoteMarkDisabled or note_mark_note_index_ < 0:
		return
	var result: int = -1
	if note_mark_mode_ == kNoteSequentialMarkMode:
		var sequential_draft: Array[Dictionary] = \
			board_.get_note_sequential_mark_draft()
		if sequential_draft == note_mark_original_sequential_:
			finish_note_mark_mode_()
			return
		result = int(go_notes_.call(
			&"replace_note_sequential_marks",
			note_mark_note_index_,
			sequential_draft
		))
	else:
		var symbol_draft: Array[Dictionary] = \
			board_.get_note_symbol_mark_draft()
		if symbol_draft == note_mark_original_symbols_:
			finish_note_mark_mode_()
			return
		result = int(go_notes_.call(
			&"replace_note_symbol_marks",
			note_mark_note_index_,
			symbol_draft
		))
	if result != 0:
		push_warning(CommandMessages.localize(go_notes_.get_message()))
		return
	finish_note_mark_mode_()


func on_note_mark_cancel_requested_() -> void:
	if note_mark_mode_ == kNoteMarkDisabled:
		return
	finish_note_mark_mode_()


func finish_note_mark_mode_() -> void:
	board_.end_note_mark_mode()
	note_mark_mode_ = kNoteMarkDisabled
	note_mark_note_index_ = -1
	note_mark_original_sequential_.clear()
	note_mark_original_symbols_.clear()
	note_mark_layer_.visible = false
	interface_layer_.visible = true
	notes_panel_.refresh_current_position()
	call_deferred(&"position_board_toolbar_")
	call_deferred(&"position_side_panels_")


func on_variation_requested_() -> void:
	if not board_.enter_variation_mode():
		push_warning("无法从当前盘面进入变化图。")


func on_variation_exit_requested_() -> void:
	var _variation_exited: bool = board_.exit_variation_mode()


func on_variation_keep_requested_() -> void:
	if not board_.keep_variation_branch():
		push_warning("无法将当前变化图保留到主棋谱。")


func on_variation_mode_changed_(enabled: bool) -> void:
	board_toolbar_.visible = not enabled
	variation_toolbar_.visible = enabled
	preset_button_.visible = not enabled
	setup_branch_button_.visible = not enabled \
		and not setup_branches_.is_empty()
	if enabled and setup_branch_popup_.visible:
		setup_branch_popup_.hide()
	if not enabled:
		update_history_buttons_()
		update_preset_button_()
		update_next_color_button_(board_.get_next_color())
		call_deferred(&"position_board_toolbar_")


func on_next_color_requested_() -> void:
	board_.toggle_next_color()


func on_next_color_changed_(color: int) -> void:
	update_next_color_button_(color)


func on_preset_requested_() -> void:
	if board_.is_preset_mode():
		preset_button_.set_pressed_no_signal(true)
		return
	board_.toggle_preset_mode()


func on_preset_accept_requested_() -> void:
	var _accepted: bool = board_.accept_preset_mode()


func on_preset_cancel_requested_() -> void:
	var _canceled: bool = board_.cancel_preset_mode()


func on_preset_mode_changed_(enabled: bool) -> void:
	preset_button_.set_pressed_no_signal(enabled)
	preset_button_.tooltip_text = \
		"正在预置棋子（Esc 取消）" if enabled else "预置棋子（Ctrl+H）"
	update_preset_toolbar_(enabled)
	update_preset_button_()


func update_preset_toolbar_(enabled: bool) -> void:
	for child: Node in board_toolbar_.get_children():
		if child is Control:
			(child as Control).visible = not enabled
	next_color_button_.visible = true
	preset_accept_button_.visible = enabled
	preset_cancel_button_.visible = enabled
	if not enabled:
		setup_branch_button_.visible = not setup_branches_.is_empty() \
			and not board_.is_variation_mode()
	call_deferred(&"position_board_toolbar_")


func update_next_color_button_(color: int) -> void:
	next_color_button_.icon = board_.get_next_color_texture()
	if color == kBlack:
		next_color_button_.tooltip_text = \
			"当前黑方落子；点击或按 Ctrl+Q 切换为白方"
	elif color == kWhite:
		next_color_button_.tooltip_text = \
			"当前白方落子；点击或按 Ctrl+Q 切换为黑方"


func perform_undo_() -> bool:
	if not go_notes_.can_undo():
		return false
	var result: int = int(go_notes_.undo())
	if result != 0:
		push_warning(CommandMessages.localize(go_notes_.get_message()))
		update_history_buttons_()
		return false
	return true


func perform_redo_() -> bool:
	if not go_notes_.can_redo():
		return false
	var result: int = int(go_notes_.redo())
	if result != 0:
		push_warning(CommandMessages.localize(go_notes_.get_message()))
		update_history_buttons_()
		return false
	return true


func on_go_notes_history_changed_() -> void:
	if branch_order_popup_.visible:
		branch_order_popup_.cancel()
	update_history_buttons_()
	update_preset_button_()
	update_reorder_branch_button_()
	notes_panel_.refresh_current_position()
	sgf_metadata_panel_.refresh_metadata()


func update_history_buttons_() -> void:
	var undo_unavailable: bool = not go_notes_.can_undo()
	var redo_unavailable: bool = not go_notes_.can_redo()
	undo_button_.disabled = undo_unavailable
	redo_button_.disabled = redo_unavailable
	undo_unavailable_mark_.visible = undo_unavailable
	redo_unavailable_mark_.visible = redo_unavailable


func update_preset_button_() -> void:
	var unavailable: bool = board_.is_interactions_locked() \
		or int(go_notes_.call(&"can_preset_stone")) != 0
	preset_button_.disabled = unavailable
	preset_unavailable_mark_.visible = unavailable
	if unavailable and board_.is_preset_mode():
		board_.toggle_preset_mode()


func on_document_tab_selected_(index: int) -> void:
	switch_document_(index)


func switch_document_(index: int) -> void:
	if index < 0 or index >= documents_.size():
		return
	if index == active_document_index_:
		document_tab_bar_.set_selected(index)
		return

	leave_transient_modes_()
	if active_document_index_ >= 0:
		var outgoing: DocumentState = documents_[active_document_index_]
		outgoing.interactions_locked = board_.is_interactions_locked()
		disconnect_history_signal_(outgoing.notes)

	var incoming: DocumentState = documents_[index]
	var previous_index: int = active_document_index_
	var previous_notes: GoNotes = go_notes_
	active_document_index_ = index
	go_notes_ = incoming.notes
	if not board_.bind_go_notes(go_notes_):
		push_error("无法切换到所选棋局标签。")
		active_document_index_ = previous_index
		go_notes_ = previous_notes
		var _restored: bool = board_.bind_go_notes(go_notes_)
		connect_history_signal_(go_notes_)
		refresh_document_tabs_()
		return

	connect_history_signal_(go_notes_)
	board_lock_checkbox_.set_pressed_no_signal(
		incoming.interactions_locked
	)
	board_.set_interactions_locked(incoming.interactions_locked)
	if incoming.initialized:
		board_size_dialog_.hide()
	else:
		board_size_dialog_.show_dialog()
	update_history_buttons_()
	update_preset_button_()
	update_next_color_button_(board_.get_next_color())
	if notes_panel_.is_panel_open():
		notes_panel_.open_panel(go_notes_)
	if sgf_metadata_panel_.is_panel_open():
		sgf_metadata_panel_.open_panel(go_notes_)
	refresh_document_tabs_()
	call_deferred(&"position_board_toolbar_")


func leave_transient_modes_() -> void:
	if note_mark_mode_ != kNoteMarkDisabled:
		on_note_mark_cancel_requested_()
	if branch_visualization_layer_.visible:
		on_branch_visualization_exit_requested_()
	if board_.is_variation_mode():
		var _variation_exited: bool = board_.exit_variation_mode()
	if board_.is_preset_mode():
		var _preset_canceled: bool = board_.cancel_preset_mode()
	if find_previous_button_.button_pressed:
		board_.toggle_find_mode(-1)
	if find_next_button_.button_pressed:
		board_.toggle_find_mode(1)
	if cut_branch_button_.button_pressed:
		board_.toggle_cut_branch_mode()
	if setup_branch_popup_.visible:
		setup_branch_popup_.hide()
	if branch_order_popup_.visible:
		branch_order_popup_.cancel()


func connect_history_signal_(notes: GoNotes) -> void:
	var changed_callback: Callable = Callable(
		self, "on_go_notes_history_changed_"
	)
	if not notes.is_connected(&"changed", changed_callback):
		notes.connect(&"changed", changed_callback)


func disconnect_history_signal_(notes: GoNotes) -> void:
	var changed_callback: Callable = Callable(
		self, "on_go_notes_history_changed_"
	)
	if notes.is_connected(&"changed", changed_callback):
		notes.disconnect(&"changed", changed_callback)


func refresh_document_tabs_() -> void:
	var titles: PackedStringArray = PackedStringArray()
	for document: DocumentState in documents_:
		titles.append(document.title)
	document_tab_bar_.set_tabs(titles, active_document_index_)


func unique_document_title_(
	base_title: String,
	excluded_index: int = -1
) -> String:
	var used_titles: Dictionary = {}
	for index: int in range(documents_.size()):
		if index != excluded_index:
			used_titles[documents_[index].title] = true
	if not used_titles.has(base_title):
		return base_title
	var suffix: int = 2
	while used_titles.has("%s %d" % [base_title, suffix]):
		suffix += 1
	return "%s %d" % [base_title, suffix]




func get_go_notes() -> GoNotes:
	return go_notes_


func bind_board_view(board_view: GoBoardView, view_uid: int = -1) -> bool:
	if board_view == null:
		return false
	return board_view.bind_go_notes(go_notes_, view_uid)


func on_create_requested_(board_size: int) -> void:
	if board_.initialize_board(board_size):
		if active_document_index_ >= 0:
			documents_[active_document_index_].initialized = true
		board_size_dialog_.hide()
	else:
		board_size_dialog_.show_dialog()


func on_board_creation_cancel_requested_() -> void:
	if documents_.size() <= 1 or active_document_index_ < 0:
		return
	var document: DocumentState = documents_[active_document_index_]
	if document.initialized:
		return

	var closing_index: int = active_document_index_
	leave_transient_modes_()
	disconnect_history_signal_(go_notes_)
	documents_.remove_at(closing_index)
	active_document_index_ = -1
	switch_document_(
		clampi(closing_index - 1, 0, documents_.size() - 1)
	)


func on_board_lock_toggled_(locked: bool) -> void:
	board_.set_interactions_locked(locked)
	if active_document_index_ >= 0:
		documents_[active_document_index_].interactions_locked = \
			board_.is_interactions_locked()
	board_lock_checkbox_.set_pressed_no_signal(
		board_.is_interactions_locked()
	)
	update_preset_button_()


func on_board_layout_changed_() -> void:
	call_deferred(&"position_board_toolbar_")
	call_deferred(&"position_side_panels_")
	call_deferred(&"position_note_mark_toolbar_")


func on_board_assets_changed_() -> void:
	update_next_color_button_(board_.get_next_color())
	on_board_layout_changed_()


func position_board_toolbar_() -> void:
	if board_.texture == null:
		return
	var board_rect: Rect2 = board_.get_rect()
	var canvas_transform: Transform2D = \
		board_.get_global_transform_with_canvas()
	var board_top_left: Vector2 = canvas_transform * board_rect.position
	var board_top_right: Vector2 = canvas_transform * Vector2(
		board_rect.end.x,
		board_rect.position.y
	)
	var toolbar_position: Vector2 = Vector2(
		roundf(board_top_right.x + kBoardToolbarGap),
		roundf(board_top_left.y)
	)
	var viewport_size: Vector2 = get_viewport_rect().size
	board_toolbar_.set_available_height(
		maxf(viewport_size.y - toolbar_position.y - kBoardToolbarGap, 56.0)
	)
	var required_toolbar_size: Vector2 = board_toolbar_.get_required_size()
	var required_right_reserve: float = maxf(
		96.0,
		required_toolbar_size.x + kBoardToolbarGap * 2.0
	)
	var current_right_reserve: float = float(
		camera_.get("right_ui_reserve")
	)
	if not is_equal_approx(current_right_reserve, required_right_reserve):
		camera_.set("right_ui_reserve", required_right_reserve)
		camera_.call(&"update_zoom_")
		call_deferred(&"position_board_toolbar_")
		return
	board_toolbar_.size = required_toolbar_size
	board_toolbar_.queue_sort()
	board_toolbar_.position = toolbar_position
	variation_toolbar_.position = toolbar_position
	position_side_panels_()
	position_note_mark_toolbar_()


func position_side_panels_() -> void:
	if not notes_panel_.is_panel_open() \
			and not sgf_metadata_panel_.is_panel_open():
		return
	var viewport_size: Vector2 = get_viewport_rect().size
	var right: float = viewport_size.x - 96.0
	var left: float = board_toolbar_.position.x \
		+ board_toolbar_.size.x + kBoardToolbarGap
	if right - left < 280.0:
		left = maxf(12.0, right - 280.0)
	var top: float = maxf(board_toolbar_.position.y, 12.0)
	var panel_rect: Rect2 = Rect2(
		Vector2(left, top),
		Vector2(
			maxf(right - left, 240.0),
			maxf(viewport_size.y - top - 12.0, 280.0)
		)
	)
	if notes_panel_.is_panel_open():
		notes_panel_.set_panel_rect(panel_rect)
	if sgf_metadata_panel_.is_panel_open():
		sgf_metadata_panel_.set_panel_rect(panel_rect)


func position_note_mark_toolbar_() -> void:
	if not note_mark_layer_.visible or board_.texture == null:
		return
	var board_rect: Rect2 = board_.get_rect()
	var canvas_transform: Transform2D = \
		board_.get_global_transform_with_canvas()
	var board_top_left: Vector2 = canvas_transform * board_rect.position
	var board_top_right: Vector2 = canvas_transform * Vector2(
		board_rect.end.x, board_rect.position.y
	)
	note_mark_toolbar_.position = Vector2(
		roundf(board_top_right.x + kBoardToolbarGap),
		roundf(board_top_left.y)
	)


func on_sgf_load_requested_(path: String) -> void:
	if activate_existing_sgf_document_(path):
		return
	var load_succeeded: bool = bool(
		go_notes_.call(&"load_sgf_file", path)
	)
	if load_succeeded:
		if active_document_index_ >= 0:
			var document: DocumentState = documents_[active_document_index_]
			var file_name: String = path.get_file()
			if file_name.is_empty():
				file_name = "新建笔记"
			document.title = unique_document_title_(
				file_name, active_document_index_
			)
			document.file_path = path
			document.initialized = true
			document.interactions_locked = true
			refresh_document_tabs_()
		board_lock_checkbox_.set_pressed_no_signal(true)
		board_.set_interactions_locked(true)
		update_history_buttons_()
		board_size_dialog_.hide()
	else:
		board_size_dialog_.show_load_error(go_notes_.get_message())


func activate_existing_sgf_document_(path: String) -> bool:
	var normalized_path: String = normalized_file_path_(path)
	if normalized_path.is_empty():
		return false
	var existing_index: int = -1
	for index in range(documents_.size()):
		if index == active_document_index_:
			continue
		var document: DocumentState = documents_[index]
		if document.file_path.is_empty():
			continue
		if normalized_file_path_(document.file_path) == normalized_path:
			existing_index = index
			break
	if existing_index < 0:
		return false

	var closing_index: int = active_document_index_
	if closing_index < 0 or closing_index >= documents_.size():
		switch_document_(existing_index)
		return true
	leave_transient_modes_()
	disconnect_history_signal_(go_notes_)
	documents_.remove_at(closing_index)
	if closing_index < existing_index:
		existing_index -= 1
	active_document_index_ = -1
	switch_document_(existing_index)
	return true


func normalized_file_path_(path: String) -> String:
	if path.is_empty():
		return ""
	var normalized: String = ProjectSettings.globalize_path(
		path
	).simplify_path().replace("\\", "/")
	if OS.get_name() == "Windows":
		normalized = normalized.to_lower()
	return normalized
