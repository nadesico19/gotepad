class_name SgfMetadataPanel
extends Control

signal panel_visibility_changed(opened: bool)

const kScrollScreenRatio: float = 2.0 / 3.0
const kScrollAnimationSeconds: float = 0.22
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
@onready var scroll_: ScrollContainer = $Panel/Margin/Content/Scroll
@onready var form_: VBoxContainer = \
	$Panel/Margin/Content/Scroll/FormMargin/Form
@onready var rules_header_: HBoxContainer = \
	$Panel/Margin/Content/Scroll/FormMargin/Form/RulesHeader
@onready var komi_header_: HBoxContainer = \
	$Panel/Margin/Content/Scroll/FormMargin/Form/KomiHeader
@onready var actions_: HBoxContainer = \
	$Panel/Margin/Content/Header/ActionRow/EditActions
@onready var accept_button_: Button = \
	$Panel/Margin/Content/Header/ActionRow/EditActions/Accept
@onready var cancel_button_: Button = \
	$Panel/Margin/Content/Header/ActionRow/EditActions/Cancel
@onready var scroll_up_button_: Button = \
	$Panel/Margin/Content/Header/ActionRow/ScrollUp
@onready var scroll_down_button_: Button = \
	$Panel/Margin/Content/Header/ActionRow/ScrollDown
@onready var unsaved_confirmation_: ConfirmationDialog = \
	$UnsavedConfirmation
@onready var error_dialog_: AcceptDialog = $ErrorDialog

var go_notes_: GoNotes
var editors_: Dictionary = {}
var saved_values_: Dictionary = {}
var updating_: bool = false
var close_after_edit_resolution_: bool = false
var mobile_text_edit_long_press_: MobileTextEditLongPressController
var scroll_tween_: Tween
var scroll_target_: float = 0.0
var last_internal_button_press_frame_: int = -2


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
	configure_mobile_text_edit_long_press_()
	configure_quick_buttons_(rules_header_, "rules")
	configure_quick_buttons_(komi_header_, "komi")
	scroll_.resized.connect(on_scroll_resized_)
	scroll_.get_v_scroll_bar().value_changed.connect(on_scroll_changed_)
	accept_button_.pressed.connect(on_accept_pressed_)
	cancel_button_.pressed.connect(on_cancel_pressed_)
	scroll_up_button_.pressed.connect(on_scroll_pressed_.bind(-1))
	scroll_down_button_.pressed.connect(on_scroll_pressed_.bind(1))
	unsaved_confirmation_.confirmed.connect(on_unsaved_confirmed_)
	unsaved_confirmation_.canceled.connect(on_unsaved_discarded_)
	panel_.hide()
	actions_.hide()


func configure_quick_buttons_(header: HBoxContainer, field_name: String) -> void:
	var buttons: Array[Button] = []
	var widest: float = 0.0
	for child: Node in header.get_children():
		if child is Button:
			var button: Button = child as Button
			buttons.append(button)
			widest = maxf(widest, button.get_combined_minimum_size().x)
			button.pressed.connect(on_quick_value_pressed_.bind(field_name, button.text))
	for button: Button in buttons:
		button.custom_minimum_size = Vector2(widest, button.custom_minimum_size.y)


func _input(event: InputEvent) -> void:
	if scroll_tween_ != null and should_cancel_scroll_tween_(event):
		cancel_scroll_tween_()
	if not panel_.visible or unsaved_confirmation_.visible or not is_dirty_():
		return
	if event is not InputEventMouseButton:
		return
	var mouse_event: InputEventMouseButton = event as InputEventMouseButton
	if not mouse_event.pressed or mouse_event.button_index != MOUSE_BUTTON_LEFT:
		return
	if editor_at_(mouse_event.position) != null \
			or accept_button_.get_global_rect().has_point(mouse_event.position) \
			or cancel_button_.get_global_rect().has_point(mouse_event.position) \
			or scroll_button_at_(mouse_event.position):
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
	scroll_target_ = scroll_.get_v_scroll_bar().value
	refresh_metadata()
	call_deferred(&"update_scroll_buttons_")
	panel_visibility_changed.emit(true)


func close_panel() -> void:
	if not panel_.visible:
		return
	cancel_scroll_tween_()
	if is_dirty_():
		close_after_edit_resolution_ = true
		show_unsaved_confirmation_()
		return
	close_panel_immediately_()


func close_panel_immediately_() -> void:
	cancel_scroll_tween_()
	cancel_edit_()
	if mobile_text_edit_long_press_ != null:
		mobile_text_edit_long_press_.reset()
	panel_.hide()
	panel_visibility_changed.emit(false)


func configure_mobile_text_edit_long_press_() -> void:
	if OS.get_name() != "Android":
		return
	mobile_text_edit_long_press_ = MobileTextEditLongPressController.new()
	add_child(mobile_text_edit_long_press_)
	mobile_text_edit_long_press_.configure(editors_.values())


func is_panel_open() -> bool:
	return panel_.visible


func set_panel_rect(panel_rect: Rect2) -> void:
	panel_.position = panel_rect.position
	panel_.size = panel_rect.size


func on_scroll_pressed_(direction: int) -> void:
	last_internal_button_press_frame_ = Engine.get_process_frames()
	var scroll_bar: VScrollBar = scroll_.get_v_scroll_bar()
	var distance: float = maxf(scroll_.size.y * kScrollScreenRatio, 1.0)
	var base: float = scroll_target_ if scroll_tween_ != null else scroll_bar.value
	scroll_target_ = clampf(
		base + float(direction) * distance, 0.0, float(maximum_scroll_())
	)
	if scroll_tween_ != null:
		scroll_tween_.kill()
	if is_equal_approx(scroll_bar.value, scroll_target_):
		scroll_tween_ = null
		update_scroll_buttons_()
		return
	scroll_tween_ = create_tween()
	scroll_tween_.set_trans(Tween.TRANS_CUBIC)
	scroll_tween_.set_ease(Tween.EASE_OUT)
	scroll_tween_.tween_property(
		scroll_bar, ^"value", scroll_target_, kScrollAnimationSeconds
	)
	scroll_tween_.finished.connect(on_scroll_tween_finished_)


func on_scroll_tween_finished_() -> void:
	scroll_tween_ = null
	scroll_target_ = scroll_.get_v_scroll_bar().value
	update_scroll_buttons_()


func cancel_scroll_tween_() -> void:
	if scroll_tween_ != null:
		scroll_tween_.kill()
		scroll_tween_ = null
	scroll_target_ = scroll_.get_v_scroll_bar().value


func should_cancel_scroll_tween_(event: InputEvent) -> bool:
	if event is InputEventScreenDrag or event is InputEventPanGesture:
		return true
	if event is InputEventScreenTouch:
		return not scroll_button_at_((event as InputEventScreenTouch).position)
	if event is InputEventMouseButton:
		return not scroll_button_at_((event as InputEventMouseButton).position)
	return event is InputEventKey and (event as InputEventKey).pressed


func scroll_button_at_(position: Vector2) -> bool:
	return scroll_up_button_.get_global_rect().has_point(position) \
		or scroll_down_button_.get_global_rect().has_point(position)


func on_scroll_resized_() -> void:
	cancel_scroll_tween_()
	update_scroll_buttons_()


func on_scroll_changed_(_value: float) -> void:
	update_scroll_buttons_()


func maximum_scroll_() -> int:
	var scroll_bar: VScrollBar = scroll_.get_v_scroll_bar()
	return maxi(roundi(scroll_bar.max_value - scroll_bar.page), 0)


func update_scroll_buttons_() -> void:
	if not is_node_ready():
		return
	var position: int = scroll_.scroll_vertical
	var maximum: int = maximum_scroll_()
	scroll_up_button_.disabled = position <= 0
	scroll_down_button_.disabled = position >= maximum


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


func on_quick_value_pressed_(field_name: String, value: String) -> void:
	last_internal_button_press_frame_ = Engine.get_process_frames()
	set_editor_text_(editors_[field_name], value)
	on_text_changed_()


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
	if Engine.get_process_frames() <= last_internal_button_press_frame_ + 1:
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
	for header: HBoxContainer in [rules_header_, komi_header_]:
		if header.get_global_rect().has_point(position):
			return header
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
