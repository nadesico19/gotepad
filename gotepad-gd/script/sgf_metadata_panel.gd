class_name SgfMetadataPanel
extends Control

signal panel_visibility_changed(opened: bool)

const kFieldNodes: Dictionary = {
	"game_name": "GameName",
	"event": "Event",
	"round": "Round",
	"date": "Date",
	"place": "Place",
	"black_name": "BlackName",
	"black_rank": "BlackRank",
	"white_name": "WhiteName",
	"white_rank": "WhiteRank",
	"result": "Result",
	"rules": "Rules",
	"komi": "Komi",
	"handicap": "Handicap",
	"time_limit": "TimeLimit",
	"overtime": "Overtime",
	"opening": "Opening",
	"annotator": "Annotator",
	"source": "Source",
	"copyright": "Copyright",
	"game_comment": "GameComment",
}

@onready var panel_: PanelContainer = $Panel
@onready var form_: VBoxContainer = $Panel/Margin/Content/Scroll/Form
@onready var actions_: HBoxContainer = \
	$Panel/Margin/Content/Header/ActionSlot/Actions
@onready var accept_button_: Button = \
	$Panel/Margin/Content/Header/ActionSlot/Actions/Accept
@onready var cancel_button_: Button = \
	$Panel/Margin/Content/Header/ActionSlot/Actions/Cancel
@onready var unsaved_confirmation_: ConfirmationDialog = \
	$UnsavedConfirmation
@onready var error_dialog_: AcceptDialog = $ErrorDialog

var go_notes_: GoNotes
var editors_: Dictionary = {}
var saved_values_: Dictionary = {}
var updating_: bool = false
var close_after_edit_resolution_: bool = false


func _ready() -> void:
	for field_name: String in kFieldNodes:
		var editor: Control = form_.get_node(str(kFieldNodes[field_name]))
		editors_[field_name] = editor
		if editor is LineEdit:
			var line_edit: LineEdit = editor as LineEdit
			line_edit.text_changed.connect(on_text_changed_)
			line_edit.focus_exited.connect(on_editor_focus_exited_)
			line_edit.gui_input.connect(on_editor_gui_input_)
		elif editor is TextEdit:
			var text_edit: TextEdit = editor as TextEdit
			text_edit.text_changed.connect(on_text_changed_)
			text_edit.focus_exited.connect(on_editor_focus_exited_)
			text_edit.gui_input.connect(on_editor_gui_input_)
	accept_button_.pressed.connect(on_accept_pressed_)
	cancel_button_.pressed.connect(on_cancel_pressed_)
	unsaved_confirmation_.confirmed.connect(on_unsaved_confirmed_)
	unsaved_confirmation_.canceled.connect(on_unsaved_discarded_)
	panel_.hide()
	actions_.hide()


func _input(event: InputEvent) -> void:
	if not panel_.visible or unsaved_confirmation_.visible or not is_dirty_():
		return
	if event is not InputEventMouseButton:
		return
	var mouse_event: InputEventMouseButton = event as InputEventMouseButton
	if not mouse_event.pressed or mouse_event.button_index != MOUSE_BUTTON_LEFT:
		return
	if editor_at_(mouse_event.position) != null \
			or accept_button_.get_global_rect().has_point(mouse_event.position) \
			or cancel_button_.get_global_rect().has_point(mouse_event.position):
		return
	show_unsaved_confirmation_()
	get_viewport().set_input_as_handled()


func toggle_panel(go_notes: GoNotes) -> void:
	if panel_.visible:
		close_panel()
	else:
		open_panel(go_notes)


func open_panel(go_notes: GoNotes) -> void:
	go_notes_ = go_notes
	panel_.show()
	refresh_metadata()
	panel_visibility_changed.emit(true)


func close_panel() -> void:
	if not panel_.visible:
		return
	if is_dirty_():
		close_after_edit_resolution_ = true
		show_unsaved_confirmation_()
		return
	close_panel_immediately_()


func close_panel_immediately_() -> void:
	cancel_edit_()
	panel_.hide()
	panel_visibility_changed.emit(false)


func is_panel_open() -> bool:
	return panel_.visible


func set_panel_rect(panel_rect: Rect2) -> void:
	panel_.position = panel_rect.position
	panel_.size = panel_rect.size


func refresh_metadata() -> void:
	if not panel_.visible or go_notes_ == null or is_dirty_():
		return
	var metadata: Dictionary = Dictionary(go_notes_.call(&"get_sgf_metadata"))
	updating_ = true
	for field_name: String in editors_:
		var value: String = str(metadata.get(field_name, ""))
		set_editor_text_(editors_[field_name], value)
		saved_values_[field_name] = value
	updating_ = false
	actions_.hide()


func on_text_changed_(_unused: String = "") -> void:
	if updating_:
		return
	actions_.visible = is_dirty_()


func is_dirty_() -> bool:
	if updating_ or saved_values_.is_empty():
		return false
	for field_name: String in editors_:
		if editor_text_(editors_[field_name]) != str(
			saved_values_.get(field_name, "")
		):
			return true
	return false


func on_editor_focus_exited_() -> void:
	call_deferred(&"show_unsaved_after_focus_change_")


func show_unsaved_after_focus_change_() -> void:
	if not panel_.visible or unsaved_confirmation_.visible or not is_dirty_():
		return
	var focus_owner: Control = get_viewport().gui_get_focus_owner()
	if focus_owner != null and editors_.values().has(focus_owner):
		return
	show_unsaved_confirmation_()


func show_unsaved_confirmation_() -> void:
	if not unsaved_confirmation_.visible:
		unsaved_confirmation_.popup_centered(Vector2i(470, 180))


func on_unsaved_confirmed_() -> void:
	on_accept_pressed_()


func on_unsaved_discarded_() -> void:
	cancel_edit_()
	finish_pending_close_()


func finish_pending_close_() -> void:
	if not close_after_edit_resolution_:
		return
	close_after_edit_resolution_ = false
	close_panel_immediately_()


func on_editor_gui_input_(event: InputEvent) -> void:
	if event is not InputEventKey:
		return
	var key_event: InputEventKey = event as InputEventKey
	if not key_event.pressed or key_event.echo or key_event.keycode != KEY_ESCAPE:
		return
	cancel_edit_()
	for editor: Control in editors_.values():
		editor.release_focus()
	get_viewport().set_input_as_handled()


func on_accept_pressed_() -> void:
	if go_notes_ == null:
		return
	var changes: Dictionary = {}
	for field_name: String in editors_:
		var value: String = editor_text_(editors_[field_name])
		if value != str(saved_values_.get(field_name, "")):
			changes[field_name] = value
	if changes.is_empty():
		actions_.hide()
		finish_pending_close_()
		return
	if int(go_notes_.call(&"update_sgf_metadata", changes)) != 0:
		error_dialog_.dialog_text = CommandMessages.localize(
			go_notes_.get_message()
		)
		error_dialog_.popup_centered(Vector2i(470, 180))
		return
	for field_name: String in changes:
		saved_values_[field_name] = str(changes[field_name])
	actions_.hide()
	finish_pending_close_()


func on_cancel_pressed_() -> void:
	cancel_edit_()


func cancel_edit_() -> void:
	updating_ = true
	for field_name: String in editors_:
		set_editor_text_(
			editors_[field_name], str(saved_values_.get(field_name, ""))
		)
	updating_ = false
	actions_.hide()


func editor_at_(position: Vector2) -> Control:
	for editor: Control in editors_.values():
		if editor.get_global_rect().has_point(position):
			return editor
	return null


func editor_text_(editor: Control) -> String:
	if editor is LineEdit:
		return (editor as LineEdit).text
	return (editor as TextEdit).text


func set_editor_text_(editor: Control, value: String) -> void:
	if editor is LineEdit:
		(editor as LineEdit).text = value
	else:
		(editor as TextEdit).text = value
