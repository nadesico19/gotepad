class_name BoardSizeDialog
extends Control

signal create_requested(board_size: int)
signal sgf_load_requested(path: String)
signal cancel_requested

var options_: Array[BaseButton] = []
var sgf_file_dialog_open_: bool = false
@onready var size_9_: CheckBox = %Size9
@onready var size_11_: CheckBox = %Size11
@onready var size_13_: CheckBox = %Size13
@onready var size_15_: CheckBox = %Size15
@onready var size_19_: CheckBox = %Size19
@onready var create_button_: Button = %CreateButton
@onready var load_sgf_button_: Button = %LoadSgfButton
@onready var sgf_file_dialog_: FileDialog = %SgfFileDialog
@onready var load_error_dialog_: AcceptDialog = %LoadErrorDialog


func _ready() -> void:
	options_.append(size_9_)
	options_.append(size_11_)
	options_.append(size_13_)
	options_.append(size_15_)
	options_.append(size_19_)
	create_button_.pressed.connect(on_create_pressed_)
	size_19_.grab_focus()
	load_sgf_button_.pressed.connect(on_load_sgf_pressed_)
	sgf_file_dialog_.file_selected.connect(on_sgf_file_selected_)
	sgf_file_dialog_.canceled.connect(on_sgf_file_dialog_canceled_)
	sgf_file_dialog_.visibility_changed.connect(
		on_sgf_file_dialog_visibility_changed_
	)


func _input(event: InputEvent) -> void:
	if not visible or sgf_file_dialog_open_ or sgf_file_dialog_.visible \
			or load_error_dialog_.visible:
		return
	if event is not InputEventKey:
		return
	var key_event: InputEventKey = event as InputEventKey
	if not key_event.pressed or key_event.echo \
			or key_event.keycode != KEY_ESCAPE:
		return
	cancel_requested.emit()
	get_viewport().set_input_as_handled()


func show_dialog() -> void:
	# 此场景会在每次新建标签时重复使用。原生文件选择器的可见性信号
	# 在父控件隐藏期间不保证再次触发，因此打开创建窗口时主动清理旧状态。
	sgf_file_dialog_.hide()
	finish_sgf_file_dialog_()
	show()
	size_19_.grab_focus()

func on_create_pressed_() -> void:
	if sgf_file_dialog_open_ or sgf_file_dialog_.visible:
		return
	for option in options_:
		if option.button_pressed:
			var selected_size: int = int(option.get_meta("board_size"))
			create_requested.emit(selected_size)
			return


func show_load_error(message: String) -> void:
	load_error_dialog_.dialog_text = message
	load_error_dialog_.popup_centered()


func on_load_sgf_pressed_() -> void:
	if sgf_file_dialog_open_ or sgf_file_dialog_.visible:
		return
	sgf_file_dialog_open_ = true
	set_creation_controls_disabled_(true)
	sgf_file_dialog_.popup_centered_ratio(0.75)


func on_sgf_file_selected_(path: String) -> void:
	finish_sgf_file_dialog_()
	sgf_load_requested.emit(path)


func on_sgf_file_dialog_canceled_() -> void:
	finish_sgf_file_dialog_()


func on_sgf_file_dialog_visibility_changed_() -> void:
	if sgf_file_dialog_.visible:
		sgf_file_dialog_open_ = true
		set_creation_controls_disabled_(true)
		return
	finish_sgf_file_dialog_()


func finish_sgf_file_dialog_() -> void:
	sgf_file_dialog_open_ = false
	set_creation_controls_disabled_(false)


func set_creation_controls_disabled_(disabled: bool) -> void:
	for option in options_:
		option.disabled = disabled
	create_button_.disabled = disabled
	load_sgf_button_.disabled = disabled
