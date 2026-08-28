class_name NotesPanel
extends Control

signal panel_visibility_changed(opened: bool)
signal displayed_marks_changed(
	sequential_marks: Array[Dictionary],
	symbol_marks: Array[Dictionary]
)
signal mark_mode_requested(
	mode: int,
	note_index: int,
	sequential_marks: Array[Dictionary],
	symbol_marks: Array[Dictionary],
	initial_symbol: String
)
signal text_edit_became_dirty
signal edit_resolution_canceled
signal numbering_preview_changed(enabled: bool, uid: int, note_index: int)
signal preview_requested(note_index: int)
signal preview_close_requested

const kSequentialMode: int = 1
const kSymbolMode: int = 2

@onready var panel_: PanelContainer = $Panel
@onready var tabs_: HBoxContainer = \
	$Panel/Margin/Content/TabScroll/Tabs
@onready var title_edit_: LineEdit = \
	$Panel/Margin/Content/TitleRow/TitleEdit
@onready var comment_edit_: TextEdit = \
	$Panel/Margin/Content/CommentArea/CommentEdit
@onready var comment_actions_: HBoxContainer = \
	$Panel/Margin/Content/TitleRow/ActionSlot/CommentActions
@onready var comment_accept_: Button = \
	$Panel/Margin/Content/TitleRow/ActionSlot/CommentActions/Accept
@onready var comment_cancel_: Button = \
	$Panel/Margin/Content/TitleRow/ActionSlot/CommentActions/Cancel
@onready var clipboard_buttons_: HBoxContainer = \
	$Panel/Margin/Content/ClipboardButtons
@onready var clipboard_select_all_: Button = \
	$Panel/Margin/Content/ClipboardButtons/SelectAll
@onready var clipboard_copy_: Button = \
	$Panel/Margin/Content/ClipboardButtons/Copy
@onready var clipboard_cut_: Button = \
	$Panel/Margin/Content/ClipboardButtons/Cut
@onready var clipboard_paste_: Button = \
	$Panel/Margin/Content/ClipboardButtons/Paste
@onready var sequential_button_: Button = \
	$Panel/Margin/Content/MarkButtons/Sequential
@onready var triangle_button_: Button = \
	$Panel/Margin/Content/MarkButtons/Triangle
@onready var square_button_: Button = \
	$Panel/Margin/Content/MarkButtons/Square
@onready var circle_button_: Button = \
	$Panel/Margin/Content/MarkButtons/Circle
@onready var cross_button_: Button = \
	$Panel/Margin/Content/MarkButtons/Cross
@onready var erase_button_: Button = \
	$Panel/Margin/Content/MarkButtons/Erase
@onready var numbering_option_: OptionButton = \
	$Panel/Margin/Content/NumberingRow/Option
@onready var preview_button_: Button = \
	$Panel/Margin/Content/NumberingRow/Preview
@onready var unsaved_confirmation_: ConfirmationDialog = \
	$UnsavedConfirmation

var go_notes_: GoNotes
var notes_: Array = []
var selected_note_index_: int = -1
var saved_title_: String = ""
var saved_comment_: String = ""
var updating_text_: bool = false
var updating_numbering_: bool = false
var editing_uid_: int = -1
var pending_action_: Callable
var last_focused_editor_: Control
var text_was_dirty_: bool = false
var resolving_edit_: bool = false
var discard_and_continue_button_: Button
var preview_mode_: bool = false


func _ready() -> void:
	configure_clipboard_buttons_()
	populate_numbering_options_()
	numbering_option_.item_selected.connect(on_numbering_selected_)
	title_edit_.text_changed.connect(on_text_changed_)
	comment_edit_.text_changed.connect(on_text_changed_)
	title_edit_.focus_exited.connect(on_text_editor_focus_exited_)
	comment_edit_.focus_exited.connect(on_text_editor_focus_exited_)
	title_edit_.focus_entered.connect(on_text_editor_focus_entered_.bind(title_edit_))
	comment_edit_.focus_entered.connect(
		on_text_editor_focus_entered_.bind(comment_edit_)
	)
	title_edit_.gui_input.connect(on_text_editor_gui_input_)
	comment_edit_.gui_input.connect(on_text_editor_gui_input_)
	comment_accept_.pressed.connect(on_comment_accept_pressed_)
	comment_cancel_.pressed.connect(on_comment_cancel_pressed_)
	preview_button_.pressed.connect(on_preview_pressed_)
	unsaved_confirmation_.confirmed.connect(on_unsaved_edit_confirmed_)
	unsaved_confirmation_.canceled.connect(on_unsaved_edit_canceled_)
	unsaved_confirmation_.custom_action.connect(on_unsaved_custom_action_)
	discard_and_continue_button_ = unsaved_confirmation_.add_button(
		tr("放弃并继续"), false, &"discard"
	)
	sequential_button_.pressed.connect(
		request_mark_mode_.bind(kSequentialMode, "")
	)
	triangle_button_.pressed.connect(
		request_mark_mode_.bind(kSymbolMode, "TR")
	)
	square_button_.pressed.connect(
		request_mark_mode_.bind(kSymbolMode, "SQ")
	)
	circle_button_.pressed.connect(
		request_mark_mode_.bind(kSymbolMode, "CR")
	)
	cross_button_.pressed.connect(
		request_mark_mode_.bind(kSymbolMode, "MA")
	)
	erase_button_.pressed.connect(
		request_mark_mode_.bind(kSymbolMode, "")
	)
	panel_.hide()
	comment_actions_.hide()


func populate_numbering_options_() -> void:
	var selected_index: int = maxi(numbering_option_.selected, 0)
	numbering_option_.clear()
	numbering_option_.add_item(tr("分支相对编号"))
	numbering_option_.add_item(tr("分支绝对编号"))
	numbering_option_.add_item(tr("全局绝对编号"))
	numbering_option_.add_item(tr("无编号"))
	numbering_option_.select(clampi(selected_index, 0, 3))


func refresh_localized_texts() -> void:
	populate_numbering_options_()
	preview_button_.text = tr("退出") if preview_mode_ else tr("专注")
	refresh_clipboard_button_texts_()
	if discard_and_continue_button_ != null:
		discard_and_continue_button_.text = tr("放弃并继续")
	if text_was_dirty_:
		return
	refresh_current_position()


func toggle_panel(go_notes: GoNotes) -> void:
	if panel_.visible:
		close_panel()
	else:
		open_panel(go_notes)


func open_panel(go_notes: GoNotes) -> void:
	go_notes_ = go_notes
	panel_.show()
	refresh_current_position()
	panel_visibility_changed.emit(true)


func close_panel() -> void:
	if not panel_.visible:
		return
	request_action_after_edit_resolution(
		Callable(self, "close_panel_immediately_")
	)


func request_action_after_edit_resolution(action: Callable) -> void:
	if not is_text_dirty_():
		if action.is_valid():
			action.call()
		return
	if unsaved_confirmation_.visible:
		return
	pending_action_ = action
	show_unsaved_confirmation_()


func close_panel_immediately_() -> void:
	cancel_comment_edit_()
	panel_.hide()
	numbering_preview_changed.emit(false, -1, -1)
	var empty_sequential: Array[Dictionary] = []
	var empty_symbols: Array[Dictionary] = []
	displayed_marks_changed.emit(empty_sequential, empty_symbols)
	panel_visibility_changed.emit(false)


func is_panel_open() -> bool:
	return panel_.visible


func set_panel_rect(panel_rect: Rect2) -> void:
	panel_.position = panel_rect.position
	panel_.size = panel_rect.size


func refresh_current_position() -> void:
	if not panel_.visible or go_notes_ == null \
			or is_text_dirty_() or resolving_edit_:
		return
	var uid: int = int(go_notes_.get_current_uid())
	notes_ = Array(go_notes_.call(&"get_notes_at", uid))
	if notes_.is_empty():
		selected_note_index_ = -1
	else:
		selected_note_index_ = clampi(
			selected_note_index_, 0, notes_.size() - 1
		)
	rebuild_tabs_()
	load_selected_note_()


func get_selected_note_index() -> int:
	return selected_note_index_


func enter_preview_mode() -> void:
	preview_mode_ = true
	preview_button_.text = tr("退出")
	rebuild_tabs_()


func select_preview_note(note_index: int) -> void:
	if not preview_mode_:
		return
	refresh_current_position()
	if notes_.is_empty():
		return
	selected_note_index_ = clampi(note_index, 0, notes_.size() - 1)
	rebuild_tabs_()
	load_selected_note_()


func exit_preview_mode() -> void:
	if not preview_mode_:
		return
	preview_mode_ = false
	preview_button_.text = tr("专注")
	refresh_current_position()


func is_preview_mode() -> bool:
	return preview_mode_


func on_preview_pressed_() -> void:
	if preview_mode_:
		preview_close_requested.emit()
	else:
		preview_requested.emit(selected_note_index_)


func rebuild_tabs_() -> void:
	for child: Node in tabs_.get_children():
		tabs_.remove_child(child)
		child.queue_free()

	for index in range(notes_.size()):
		var tab: HBoxContainer = HBoxContainer.new()
		tab.add_theme_constant_override(&"separation", 0)
		var select_button: Button = Button.new()
		select_button.text = str(index)
		select_button.toggle_mode = true
		select_button.button_pressed = index == selected_note_index_
		select_button.disabled = preview_mode_
		select_button.focus_mode = Control.FOCUS_NONE
		select_button.custom_minimum_size = Vector2(42.0, 34.0)
		select_button.pressed.connect(on_note_tab_pressed_.bind(index))
		tab.add_child(select_button)
		if index == notes_.size() - 1:
			var close_button: Button = Button.new()
			close_button.text = "✕"
			close_button.tooltip_text = tr("关闭最后一层笔记")
			close_button.focus_mode = Control.FOCUS_NONE
			close_button.disabled = preview_mode_
			close_button.custom_minimum_size = Vector2(30.0, 34.0)
			close_button.add_theme_color_override(
				&"font_color", Color(0.96, 0.3, 0.3)
			)
			close_button.pressed.connect(on_remove_last_note_pressed_)
			tab.add_child(close_button)
		tabs_.add_child(tab)

	var append_button: Button = Button.new()
	append_button.text = "+"
	append_button.tooltip_text = tr("增加一层笔记")
	append_button.focus_mode = Control.FOCUS_NONE
	append_button.disabled = preview_mode_
	append_button.custom_minimum_size = Vector2(42.0, 34.0)
	append_button.add_theme_font_size_override(&"font_size", 22)
	append_button.pressed.connect(on_append_note_pressed_)
	tabs_.add_child(append_button)


func load_selected_note_() -> void:
	var has_note: bool = selected_note_index_ >= 0 \
		and selected_note_index_ < notes_.size()
	title_edit_.editable = has_note
	comment_edit_.editable = has_note
	sequential_button_.disabled = not has_note
	triangle_button_.disabled = not has_note
	square_button_.disabled = not has_note
	circle_button_.disabled = not has_note
	cross_button_.disabled = not has_note
	erase_button_.disabled = not has_note
	numbering_option_.disabled = not has_note
	updating_text_ = true
	updating_numbering_ = true
	editing_uid_ = int(go_notes_.get_current_uid()) if go_notes_ != null else -1
	if has_note:
		var note: Dictionary = Dictionary(notes_[selected_note_index_])
		numbering_option_.selected = clampi(
			int(note.get("numbering", 0)), 0,
			numbering_option_.item_count - 1
		)
		saved_title_ = str(note.get("title", ""))
		saved_comment_ = str(note.get("comment", ""))
		title_edit_.text = saved_title_
		title_edit_.placeholder_text = tr("输入节点标题")
		comment_edit_.text = saved_comment_
		comment_edit_.placeholder_text = tr("输入当前局面的笔记……")
		displayed_marks_changed.emit(
			to_dictionary_array_(note.get("sequential_marks", [])),
			to_dictionary_array_(note.get("symbol_marks", []))
		)
	else:
		numbering_option_.selected = 0
		saved_title_ = ""
		saved_comment_ = ""
		title_edit_.text = tr("点击 + 新建笔记")
		title_edit_.placeholder_text = ""
		comment_edit_.text = tr(
			"在SGF中，0号笔记进入落子节点，后续笔记依次进入独立节点。"
		)
		comment_edit_.placeholder_text = ""
		var empty_sequential: Array[Dictionary] = []
		var empty_symbols: Array[Dictionary] = []
		displayed_marks_changed.emit(empty_sequential, empty_symbols)
	updating_text_ = false
	updating_numbering_ = false
	text_was_dirty_ = false
	comment_actions_.hide()
	refresh_clipboard_buttons_()
	numbering_preview_changed.emit(
		has_note,
		editing_uid_ if has_note else -1,
		selected_note_index_ if has_note else -1
	)


func on_note_tab_pressed_(index: int) -> void:
	if index == selected_note_index_:
		return
	request_action_after_edit_resolution(
		Callable(self, "select_note_tab_").bind(index)
	)


func select_note_tab_(index: int) -> void:
	selected_note_index_ = index
	rebuild_tabs_()
	load_selected_note_()


func on_append_note_pressed_() -> void:
	request_action_after_edit_resolution(
		Callable(self, "append_note_")
	)


func append_note_() -> void:
	if go_notes_ == null:
		return
	var new_index: int = notes_.size()
	if int(go_notes_.call(&"append_note")) != 0:
		push_warning(CommandMessages.localize(go_notes_.get_message()))
		return
	selected_note_index_ = new_index
	refresh_current_position()


func on_remove_last_note_pressed_() -> void:
	request_action_after_edit_resolution(
		Callable(self, "remove_last_note_")
	)


func remove_last_note_() -> void:
	if go_notes_ == null or notes_.is_empty():
		return
	var last_index: int = notes_.size() - 1
	if int(go_notes_.call(&"remove_note", last_index)) != 0:
		push_warning(CommandMessages.localize(go_notes_.get_message()))
		return
	selected_note_index_ = mini(selected_note_index_, last_index - 1)
	refresh_current_position()


func on_text_changed_(_new_title: String = "") -> void:
	if updating_text_:
		return
	var dirty: bool = is_text_dirty_()
	comment_actions_.visible = dirty
	if dirty and not text_was_dirty_:
		text_edit_became_dirty.emit()
	text_was_dirty_ = dirty


func is_text_dirty_() -> bool:
	return selected_note_index_ >= 0 \
		and (
			title_edit_.text != saved_title_ \
			or comment_edit_.text != saved_comment_
		)


func on_text_editor_focus_exited_() -> void:
	call_deferred(&"show_unsaved_confirmation_after_focus_change_")


func show_unsaved_confirmation_after_focus_change_() -> void:
	if not panel_.visible or unsaved_confirmation_.visible \
			or not is_text_dirty_():
		return
	var focus_owner: Control = get_viewport().gui_get_focus_owner()
	if focus_owner == title_edit_ or focus_owner == comment_edit_:
		return
	show_unsaved_confirmation_()


func on_text_editor_focus_entered_(editor: Control) -> void:
	last_focused_editor_ = editor
	refresh_clipboard_buttons_()


func configure_clipboard_buttons_() -> void:
	clipboard_buttons_.visible = OS.has_feature("android")
	if not clipboard_buttons_.visible:
		return
	title_edit_.deselect_on_focus_loss_enabled = false
	comment_edit_.deselect_on_focus_loss_enabled = false
	clipboard_select_all_.pressed.connect(
		on_clipboard_action_.bind(&"select_all")
	)
	clipboard_copy_.pressed.connect(on_clipboard_action_.bind(&"copy"))
	clipboard_cut_.pressed.connect(on_clipboard_action_.bind(&"cut"))
	clipboard_paste_.pressed.connect(on_clipboard_action_.bind(&"paste"))
	refresh_clipboard_button_texts_()
	refresh_clipboard_buttons_()


func refresh_clipboard_button_texts_() -> void:
	clipboard_select_all_.text = tr("全选文本")
	clipboard_copy_.text = tr("复制文本")
	clipboard_cut_.text = tr("剪切文本")
	clipboard_paste_.text = tr("粘贴文本")


func on_clipboard_action_(action: StringName) -> void:
	if last_focused_editor_ == null \
			or not is_instance_valid(last_focused_editor_):
		return
	if last_focused_editor_ is LineEdit:
		apply_line_edit_clipboard_action_(
			last_focused_editor_ as LineEdit, action
		)
	elif last_focused_editor_ is TextEdit:
		apply_text_edit_clipboard_action_(
			last_focused_editor_ as TextEdit, action
		)
	last_focused_editor_.grab_focus()
	call_deferred(&"refresh_clipboard_buttons_")


func apply_line_edit_clipboard_action_(
		editor: LineEdit, action: StringName
) -> void:
	match action:
		&"select_all":
			editor.menu_option(LineEdit.MENU_SELECT_ALL)
		&"copy":
			editor.menu_option(LineEdit.MENU_COPY)
		&"cut":
			editor.menu_option(LineEdit.MENU_CUT)
		&"paste":
			editor.menu_option(LineEdit.MENU_PASTE)


func apply_text_edit_clipboard_action_(
		editor: TextEdit, action: StringName
) -> void:
	match action:
		&"select_all":
			editor.menu_option(TextEdit.MENU_SELECT_ALL)
		&"copy":
			editor.menu_option(TextEdit.MENU_COPY)
		&"cut":
			editor.menu_option(TextEdit.MENU_CUT)
		&"paste":
			editor.menu_option(TextEdit.MENU_PASTE)


func refresh_clipboard_buttons_() -> void:
	if not clipboard_buttons_.visible:
		return
	var has_editor: bool = last_focused_editor_ != null \
		and is_instance_valid(last_focused_editor_) \
		and (last_focused_editor_ is LineEdit \
			or last_focused_editor_ is TextEdit)
	var has_selection: bool = false
	var editable: bool = false
	if last_focused_editor_ is LineEdit:
		var line_edit: LineEdit = last_focused_editor_ as LineEdit
		has_selection = line_edit.has_selection()
		editable = line_edit.editable
	elif last_focused_editor_ is TextEdit:
		var text_edit: TextEdit = last_focused_editor_ as TextEdit
		has_selection = text_edit.has_selection()
		editable = text_edit.editable
	clipboard_select_all_.disabled = not has_editor
	clipboard_copy_.disabled = not has_selection
	clipboard_cut_.disabled = not has_selection or not editable
	# Android 对读取剪贴板有隐私提示和访问限制，因此不在每次刷新时
	# 主动读取内容；粘贴按钮交给控件自身判断剪贴板是否为空。
	clipboard_paste_.disabled = not has_editor or not editable


func show_unsaved_confirmation_() -> void:
	if unsaved_confirmation_.visible:
		return
	unsaved_confirmation_.popup_centered(Vector2i(450, 180))


func on_unsaved_edit_confirmed_() -> void:
	if not commit_comment_edit_():
		return
	continue_pending_action_()


func on_unsaved_edit_canceled_() -> void:
	pending_action_ = Callable()
	edit_resolution_canceled.emit()
	if last_focused_editor_ != null and is_instance_valid(last_focused_editor_):
		last_focused_editor_.call_deferred(&"grab_focus")


func on_unsaved_custom_action_(action: StringName) -> void:
	if action != &"discard":
		return
	unsaved_confirmation_.hide()
	cancel_comment_edit_()
	continue_pending_action_()


func continue_pending_action_() -> void:
	var action: Callable = pending_action_
	pending_action_ = Callable()
	if action.is_valid():
		action.call_deferred()


func on_text_editor_gui_input_(event: InputEvent) -> void:
	if clipboard_buttons_.visible:
		call_deferred(&"refresh_clipboard_buttons_")
	if event is not InputEventKey:
		return
	var key_event: InputEventKey = event as InputEventKey
	if not key_event.pressed or key_event.echo \
			or key_event.keycode != KEY_ESCAPE:
		return
	cancel_comment_edit_()
	title_edit_.release_focus()
	comment_edit_.release_focus()
	get_viewport().set_input_as_handled()


func on_comment_accept_pressed_() -> void:
	var _committed: bool = commit_comment_edit_()


func commit_comment_edit_() -> bool:
	if go_notes_ == null or selected_note_index_ < 0:
		return false
	if title_edit_.text == saved_title_ \
			and comment_edit_.text == saved_comment_:
		comment_actions_.hide()
		text_was_dirty_ = false
		return true
	if int(go_notes_.get_current_uid()) != editing_uid_:
		push_warning(tr("笔记对应的局面已经改变，无法保存本次编辑。"))
		return false
	resolving_edit_ = true
	if int(go_notes_.call(
		&"update_note_text",
		selected_note_index_,
		title_edit_.text,
		comment_edit_.text
	)) != 0:
		resolving_edit_ = false
		push_warning(CommandMessages.localize(go_notes_.get_message()))
		return false
	saved_title_ = title_edit_.text
	saved_comment_ = comment_edit_.text
	var updated_note: Dictionary = Dictionary(notes_[selected_note_index_])
	updated_note["title"] = saved_title_
	updated_note["comment"] = saved_comment_
	notes_[selected_note_index_] = updated_note
	resolving_edit_ = false
	text_was_dirty_ = false
	comment_actions_.hide()
	return true


func on_comment_cancel_pressed_() -> void:
	cancel_comment_edit_()


func on_numbering_selected_(index: int) -> void:
	if updating_numbering_ or go_notes_ == null \
			or selected_note_index_ < 0:
		return
	var note: Dictionary = Dictionary(notes_[selected_note_index_])
	updating_numbering_ = true
	numbering_option_.selected = clampi(
		int(note.get("numbering", 0)), 0,
		numbering_option_.item_count - 1
	)
	updating_numbering_ = false
	request_action_after_edit_resolution(
		Callable(self, "apply_numbering_selection_").bind(index)
	)


func apply_numbering_selection_(index: int) -> void:
	var result: int = int(go_notes_.call(
		&"update_note_numbering", selected_note_index_, index
	))
	if result == 0:
		updating_numbering_ = true
		numbering_option_.selected = index
		updating_numbering_ = false
		var updated_note: Dictionary = Dictionary(notes_[selected_note_index_])
		updated_note["numbering"] = index
		notes_[selected_note_index_] = updated_note
		return
	push_warning(CommandMessages.localize(go_notes_.get_message()))
	updating_numbering_ = true
	var note: Dictionary = Dictionary(notes_[selected_note_index_])
	numbering_option_.selected = clampi(
		int(note.get("numbering", 0)), 0,
		numbering_option_.item_count - 1
	)
	updating_numbering_ = false


func cancel_comment_edit_() -> void:
	updating_text_ = true
	title_edit_.text = saved_title_
	comment_edit_.text = saved_comment_
	updating_text_ = false
	text_was_dirty_ = false
	comment_actions_.hide()


func request_mark_mode_(mode: int, initial_symbol: String) -> void:
	if selected_note_index_ < 0 or selected_note_index_ >= notes_.size():
		return
	request_action_after_edit_resolution(
		Callable(self, "begin_mark_mode_").bind(mode, initial_symbol)
	)


func begin_mark_mode_(mode: int, initial_symbol: String) -> void:
	var note: Dictionary = Dictionary(notes_[selected_note_index_])
	var sequential_marks: Array[Dictionary] = to_dictionary_array_(
		note.get("sequential_marks", [])
	)
	var symbol_marks: Array[Dictionary] = to_dictionary_array_(
		note.get("symbol_marks", [])
	)
	mark_mode_requested.emit(
		mode,
		selected_note_index_,
		sequential_marks,
		symbol_marks,
		initial_symbol
	)


func to_dictionary_array_(value: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if value is not Array:
		return result
	for item: Variant in value:
		if item is Dictionary:
			result.append(Dictionary(item).duplicate(true))
	return result
