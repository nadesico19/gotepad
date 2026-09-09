class_name MobileTextEditLongPressController
extends Node

const kLongPressSeconds: float = 0.5
const kDragCancelDistance: float = 16.0

var editors_: Array[Control] = []
var press_token_: int = 0
var touch_index_: int = -1
var press_position_: Vector2 = Vector2.ZERO
var pressed_editor_: Control
var editing_editor_: Control


func configure(editors: Array) -> void:
	if OS.get_name() != "Android":
		return
	for value: Variant in editors:
		var editor: Control = value as Control
		if editor == null or not (editor is LineEdit or editor is TextEdit):
			continue
		editors_.append(editor)
		set_virtual_keyboard_enabled_(editor, false)
		set_virtual_keyboard_show_on_focus_(editor, false)
		editor.gui_input.connect(on_editor_gui_input_.bind(editor))
		editor.focus_exited.connect(on_editor_focus_exited_.bind(editor))
		if editor is LineEdit:
			var line_edit: LineEdit = editor as LineEdit
			line_edit.unedit()
			line_edit.editing_toggled.connect(
				on_line_edit_editing_toggled_.bind(line_edit)
			)
	set_process_input(not editors_.is_empty())


func reset() -> void:
	cancel_long_press_()
	if editing_editor_ != null:
		set_virtual_keyboard_enabled_(editing_editor_, false)
		if editing_editor_ is LineEdit:
			(editing_editor_ as LineEdit).unedit()
		editing_editor_ = null
		DisplayServer.virtual_keyboard_hide()


func _input(event: InputEvent) -> void:
	if touch_index_ < 0:
		return
	if event is InputEventScreenTouch:
		var touch: InputEventScreenTouch = event as InputEventScreenTouch
		if touch.index == touch_index_:
			if not touch.pressed or touch.canceled:
				cancel_long_press_()
		elif touch.pressed:
			cancel_long_press_()
	elif event is InputEventScreenDrag:
		var drag: InputEventScreenDrag = event as InputEventScreenDrag
		if drag.index != touch_index_ or pressed_editor_ == null:
			return
		var local_position: Vector2 = global_to_editor_(pressed_editor_, drag.position)
		if not Rect2(Vector2.ZERO, pressed_editor_.size).has_point(local_position) \
				or local_position.distance_to(press_position_) > kDragCancelDistance:
			cancel_long_press_()


func on_editor_gui_input_(event: InputEvent, editor: Control) -> void:
	if editor == editing_editor_:
		return
	if event is InputEventScreenTouch:
		var touch: InputEventScreenTouch = event as InputEventScreenTouch
		if touch.pressed and not touch.canceled:
			begin_long_press_(editor, touch.index, touch.position)
		elif touch.index == touch_index_:
			cancel_long_press_()
	elif event is InputEventScreenDrag:
		var drag: InputEventScreenDrag = event as InputEventScreenDrag
		if drag.index == touch_index_ \
				and drag.position.distance_to(press_position_) > kDragCancelDistance:
			cancel_long_press_()


func begin_long_press_(editor: Control, touch_index: int, position: Vector2) -> void:
	if not editor_is_editable_(editor):
		return
	press_token_ += 1
	var token: int = press_token_
	touch_index_ = touch_index
	press_position_ = position
	pressed_editor_ = editor
	get_tree().create_timer(kLongPressSeconds).timeout.connect(
		on_long_press_timeout_.bind(token, editor), CONNECT_ONE_SHOT
	)


func cancel_long_press_() -> void:
	press_token_ += 1
	touch_index_ = -1
	pressed_editor_ = null


func on_long_press_timeout_(token: int, editor: Control) -> void:
	if token != press_token_ or editor != pressed_editor_ \
			or not editor_is_editable_(editor) or not editor.is_visible_in_tree():
		return
	touch_index_ = -1
	pressed_editor_ = null
	if editing_editor_ != null and editing_editor_ != editor:
		set_virtual_keyboard_enabled_(editing_editor_, false)
	editing_editor_ = editor
	set_virtual_keyboard_enabled_(editor, true)
	if editor is LineEdit:
		activate_line_edit_(editor as LineEdit)
	else:
		activate_text_edit_(editor as TextEdit)


func activate_line_edit_(line_edit: LineEdit) -> void:
	line_edit.unedit()
	line_edit.grab_focus()
	line_edit.unedit()
	line_edit.edit()


func activate_text_edit_(text_edit: TextEdit) -> void:
	text_edit.grab_focus()
	DisplayServer.virtual_keyboard_show(
		text_edit.text,
		text_edit.get_global_rect(),
		text_edit.virtual_keyboard_type
	)


func on_editor_focus_exited_(editor: Control) -> void:
	if editor == pressed_editor_:
		cancel_long_press_()
	if editor != editing_editor_:
		return
	set_virtual_keyboard_enabled_(editor, false)
	if editor is LineEdit:
		(editor as LineEdit).unedit()
	editing_editor_ = null
	DisplayServer.virtual_keyboard_hide()


func on_line_edit_editing_toggled_(editing: bool, line_edit: LineEdit) -> void:
	if editing and line_edit != editing_editor_:
		line_edit.call_deferred(&"unedit")
	elif not editing and line_edit == editing_editor_:
		set_virtual_keyboard_enabled_(line_edit, false)
		editing_editor_ = null


func editor_is_editable_(editor: Control) -> bool:
	if editor is LineEdit:
		return (editor as LineEdit).editable
	return (editor as TextEdit).editable


func set_virtual_keyboard_enabled_(editor: Control, enabled: bool) -> void:
	if editor is LineEdit:
		(editor as LineEdit).virtual_keyboard_enabled = enabled
	else:
		(editor as TextEdit).virtual_keyboard_enabled = enabled


func set_virtual_keyboard_show_on_focus_(editor: Control, enabled: bool) -> void:
	if editor is LineEdit:
		(editor as LineEdit).virtual_keyboard_show_on_focus = enabled
	else:
		(editor as TextEdit).virtual_keyboard_show_on_focus = enabled


func global_to_editor_(editor: Control, position: Vector2) -> Vector2:
	return editor.get_global_transform_with_canvas().affine_inverse() * position
