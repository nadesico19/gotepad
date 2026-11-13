class_name MobileTextEditLongPressController
extends Node

const kLongPressSeconds: float = 0.5
const kDragCancelDistance: float = 16.0

static var android_ime_host_: Variant
static var ios_ime_editor_id_: int = 0

var editors_: Array[Control] = []
var press_token_: int = 0
var touch_index_: int = -1
var press_position_: Vector2 = Vector2.ZERO
var pressed_editor_: Control
var editing_editor_: Control


func configure(editors: Array) -> void:
	if not OS.has_feature("mobile"):
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
		end_physical_ime(editing_editor_)
		set_virtual_keyboard_enabled_(editing_editor_, false)
		if editing_editor_ is LineEdit:
			(editing_editor_ as LineEdit).unedit()
		editing_editor_ = null
		DisplayServer.virtual_keyboard_hide()


func _input(event: InputEvent) -> void:
	if is_keyboard_focus_navigation(event):
		call_deferred(&"edit_after_focus_navigation_", get_viewport().gui_get_focus_owner())
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
	if is_physical_mouse_edit_click(event):
		activate_physical_edit_(editor)
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


func edit_after_focus_navigation_(previous_focus: Control) -> void:
	var editor: Control = get_viewport().gui_get_focus_owner()
	if editor != null and editor != previous_focus and editors_.has(editor):
		activate_physical_edit_(editor)


func activate_physical_edit_(editor: Control) -> void:
	if editor == editing_editor_ or not editor_is_editable_(editor):
		return
	cancel_long_press_()
	editor.grab_focus()
	editing_editor_ = editor
	if editor is LineEdit:
		(editor as LineEdit).edit()
	begin_physical_ime(editor)


static func begin_physical_ime(editor: Control) -> void:
	if OS.get_name() == "iOS":
		if DisplayServer.has_hardware_keyboard():
			open_ios_ime.call_deferred(editor)
	else:
		begin_android_ime(editor, false)


static func open_ios_ime(editor: Control) -> void:
	if not is_instance_valid(editor) or not editor.has_focus() or not editor.is_visible_in_tree():
		return
	var text: String
	var type: int
	var max_length: int = -1
	var start: int
	var end: int = -1
	if editor is LineEdit:
		var line_edit: LineEdit = editor as LineEdit
		if not line_edit.is_editing():
			return
		text = line_edit.text
		type = line_edit.virtual_keyboard_type
		max_length = line_edit.max_length
		start = line_edit.caret_column
		if line_edit.has_selection():
			start = line_edit.get_selection_from_column()
			end = line_edit.get_selection_to_column()
	else:
		var text_edit: TextEdit = editor as TextEdit
		if not text_edit.editable:
			return
		text = text_edit.text
		type = text_edit.virtual_keyboard_type
		start = text_offset_(text_edit, text_edit.get_caret_line(), text_edit.get_caret_column())
		if text_edit.has_selection():
			start = text_offset_(text_edit, text_edit.get_selection_from_line(), text_edit.get_selection_from_column())
			end = text_offset_(text_edit, text_edit.get_selection_to_line(), text_edit.get_selection_to_column())
	ios_ime_editor_id_ = editor.get_instance_id()
	DisplayServer.virtual_keyboard_show(text, editor.get_global_rect(), type, max_length, start, end)


static func text_offset_(editor: TextEdit, line: int, column: int) -> int:
	var offset: int = column
	for index: int in range(line):
		offset += editor.get_line(index).length() + 1
	return offset


static func end_physical_ime(editor: Control) -> void:
	if OS.get_name() == "iOS":
		if ios_ime_editor_id_ == editor.get_instance_id():
			ios_ime_editor_id_ = 0
			DisplayServer.virtual_keyboard_hide()
	else:
		end_android_ime(editor)


static func begin_android_ime(editor: Control, show_keyboard: bool) -> void:
	if OS.get_name() != "Android":
		return
	if android_ime_host_ == null:
		android_ime_host_ = JavaClassWrapper.wrap("com.godot.game.GodotApp")
	if android_ime_host_ != null:
		android_ime_host_.beginHardwareIme(editor.get_instance_id(), editor is TextEdit, show_keyboard)


static func end_android_ime(editor: Control) -> void:
	if android_ime_host_ != null:
		android_ime_host_.endHardwareIme(editor.get_instance_id())


static func is_keyboard_focus_navigation(event: InputEvent) -> bool:
	return OS.has_feature("mobile") and event is InputEventKey and ( \
		event.is_action_pressed(&"ui_focus_next", true, true) \
		or event.is_action_pressed(&"ui_focus_prev", true, true)
	)


static func is_physical_mouse_edit_click(event: InputEvent) -> bool:
	if not OS.has_feature("mobile") or event is not InputEventMouseButton:
		return false
	var button: InputEventMouseButton = event as InputEventMouseButton
	return button.device != InputEvent.DEVICE_ID_EMULATION \
		and button.button_index == MOUSE_BUTTON_LEFT and button.pressed and not button.canceled


func begin_long_press_(editor: Control, touch_index: int, position: Vector2) -> void:
	if not editor_is_editable_(editor):
		return
	if editor == editing_editor_ and editor.get("virtual_keyboard_enabled"):
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
	if editor is LineEdit:
		var line_edit: LineEdit = editor as LineEdit
		line_edit.grab_focus()
		line_edit.unedit()
		editing_editor_ = line_edit
		set_virtual_keyboard_enabled_(line_edit, true)
		line_edit.edit()
	else:
		editing_editor_ = editor
		set_virtual_keyboard_enabled_(editor, true)
		activate_text_edit_(editor as TextEdit)
	begin_android_ime(editor, true)


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
	end_physical_ime(editor)
	set_virtual_keyboard_enabled_(editor, false)
	if editor is LineEdit:
		(editor as LineEdit).unedit()
	editing_editor_ = null
	DisplayServer.virtual_keyboard_hide()


func on_line_edit_editing_toggled_(editing: bool, line_edit: LineEdit) -> void:
	if editing and line_edit != editing_editor_:
		call_deferred(&"unedit_inactive_line_edit_", line_edit)
	elif not editing and line_edit == editing_editor_:
		end_physical_ime(line_edit)
		set_virtual_keyboard_enabled_(line_edit, false)
		editing_editor_ = null


func unedit_inactive_line_edit_(line_edit: LineEdit) -> void:
	if is_instance_valid(line_edit) and line_edit != editing_editor_:
		line_edit.unedit()


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
