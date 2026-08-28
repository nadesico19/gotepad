class_name BoardSizeDialog
extends Control

signal create_requested(board_size: int)
signal sgf_load_requested(path: String)
signal sgf_paste_requested(content: String)
signal image_create_requested(
	board_size: int, cells: PackedInt32Array, source_path: String
)
signal cancel_requested

const kAndroidHostClass: String = "com.godot.game.GodotApp"

var options_: Array[BaseButton] = []
var sgf_file_dialog_open_: bool = false
var image_file_dialog_open_: bool = false
var android_host_class_: Variant
var android_image_request_active_: bool = false
var android_image_board_size_: int = 19
@onready var size_9_: CheckBox = %Size9
@onready var size_11_: CheckBox = %Size11
@onready var size_13_: CheckBox = %Size13
@onready var size_15_: CheckBox = %Size15
@onready var size_19_: CheckBox = %Size19
@onready var create_button_: Button = %CreateButton
@onready var close_button_: Button = %CloseButton
@onready var close_balance_: Control = %CloseBalance
@onready var load_sgf_button_: Button = %LoadSgfButton
@onready var paste_sgf_button_: Button = %PasteSgfButton
@onready var sgf_file_dialog_: FileDialog = %SgfFileDialog
@onready var load_error_dialog_: AcceptDialog = %LoadErrorDialog
@onready var image_description_: Label = %ImageDescription
@onready var select_image_button_: Button = %SelectImageButton
@onready var android_image_buttons_: HBoxContainer = %AndroidImageButtons
@onready var camera_button_: Button = %CameraButton
@onready var gallery_button_: Button = %GalleryButton
@onready var image_file_dialog_: FileDialog = %ImageFileDialog
@onready var image_import_dialog_: BoardImageImportDialog = \
	%BoardImageImportDialog


func _ready() -> void:
	options_.append(size_9_)
	options_.append(size_11_)
	options_.append(size_13_)
	options_.append(size_15_)
	options_.append(size_19_)
	create_button_.pressed.connect(on_create_pressed_)
	close_button_.pressed.connect(on_close_pressed_)
	size_19_.grab_focus()
	load_sgf_button_.pressed.connect(on_load_sgf_pressed_)
	paste_sgf_button_.pressed.connect(on_paste_sgf_pressed_)
	sgf_file_dialog_.file_selected.connect(on_sgf_file_selected_)
	sgf_file_dialog_.canceled.connect(on_sgf_file_dialog_canceled_)
	sgf_file_dialog_.visibility_changed.connect(
		on_sgf_file_dialog_visibility_changed_
	)
	select_image_button_.pressed.connect(on_select_image_pressed_)
	camera_button_.pressed.connect(on_camera_pressed_)
	gallery_button_.pressed.connect(on_gallery_pressed_)
	image_file_dialog_.file_selected.connect(on_image_file_selected_)
	image_file_dialog_.canceled.connect(on_image_file_dialog_canceled_)
	image_file_dialog_.visibility_changed.connect(
		on_image_file_dialog_visibility_changed_
	)
	image_import_dialog_.import_confirmed.connect(on_image_import_confirmed_)
	image_import_dialog_.import_canceled.connect(on_image_import_canceled_)
	var is_android: bool = OS.get_name() == "Android"
	select_image_button_.visible = not is_android
	android_image_buttons_.visible = is_android
	if is_android:
		android_host_class_ = JavaClassWrapper.wrap(kAndroidHostClass)
	set_process(false)
	camera_button_.disabled = android_host_class_ == null
	gallery_button_.disabled = android_host_class_ == null
	refresh_localized_texts()


func _process(_delta: float) -> void:
	if android_host_class_ == null:
		return
	var values: Variant = android_host_class_.pollBoardImageResults()
	if values == null:
		return
	for value: Variant in values:
		handle_android_image_result_(str(value))


func refresh_localized_texts() -> void:
	if not is_node_ready():
		return
	sgf_file_dialog_.filters = PackedStringArray([
		"*.sgf ; %s" % tr("SGF 棋谱"),
	])
	image_file_dialog_.filters = PackedStringArray([
		"*.png,*.jpg,*.jpeg,*.webp,*.bmp ; %s" % tr("图片文件"),
	])
	image_file_dialog_.title = tr("选择棋盘图片")
	image_file_dialog_.ok_button_text = tr("选择")
	image_description_.text = tr("从图片创建")
	load_sgf_button_.text = tr("加载")
	paste_sgf_button_.text = tr("粘贴")
	select_image_button_.text = tr("选择本地图片")
	camera_button_.text = tr("拍照")
	gallery_button_.text = tr("相册")
	image_import_dialog_.refresh_localized_texts()


func _input(event: InputEvent) -> void:
	if not visible or sgf_file_dialog_open_ or sgf_file_dialog_.visible \
			or image_file_dialog_open_ or image_file_dialog_.visible \
			or image_import_dialog_.visible or load_error_dialog_.visible:
		return
	if event is not InputEventKey:
		return
	var key_event: InputEventKey = event as InputEventKey
	if not key_event.pressed or key_event.echo \
			or key_event.keycode != KEY_ESCAPE:
		return
	cancel_requested.emit()
	get_viewport().set_input_as_handled()


func show_dialog(can_cancel: bool) -> void:
	# 此场景会在每次新建标签时重复使用。原生文件选择器的可见性信号
	# 在父控件隐藏期间不保证再次触发，因此打开创建窗口时主动清理旧状态。
	sgf_file_dialog_.hide()
	finish_sgf_file_dialog_()
	image_file_dialog_.hide()
	finish_image_file_dialog_()
	image_import_dialog_.hide()
	close_button_.visible = can_cancel
	close_balance_.visible = can_cancel
	show()
	size_19_.grab_focus()


func on_close_pressed_() -> void:
	if not close_button_.visible or close_button_.disabled:
		return
	cancel_requested.emit()

func on_create_pressed_() -> void:
	if sgf_file_dialog_open_ or sgf_file_dialog_.visible \
			or image_file_dialog_open_ or image_file_dialog_.visible \
			or image_import_dialog_.visible:
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
		sgf_file_dialog_.grab_focus()
		return
	sgf_file_dialog_open_ = true
	set_creation_controls_disabled_(true)
	sgf_file_dialog_.popup_centered_ratio(0.75)


func on_paste_sgf_pressed_() -> void:
	if sgf_file_dialog_open_ or sgf_file_dialog_.visible \
			or image_file_dialog_open_ or image_file_dialog_.visible \
			or image_import_dialog_.visible:
		return
	var content: String = DisplayServer.clipboard_get()
	if content.strip_edges().is_empty():
		show_load_error(tr("剪贴板中没有 SGF 文本。"))
		return
	sgf_paste_requested.emit(content)


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
	close_button_.disabled = disabled
	# 文件选择期间仍允许再次点击此按钮，以便将原生对话框提到前台。
	load_sgf_button_.disabled = false
	paste_sgf_button_.disabled = disabled
	select_image_button_.disabled = false
	if OS.get_name() != "Android":
		return
	if android_image_request_active_:
		load_sgf_button_.disabled = true
		camera_button_.disabled = true
		gallery_button_.disabled = true
		return
	camera_button_.disabled = disabled or android_host_class_ == null
	gallery_button_.disabled = disabled or android_host_class_ == null


func selected_board_size_() -> int:
	for option: BaseButton in options_:
		if option.button_pressed:
			return int(option.get_meta("board_size"))
	return 19


func on_select_image_pressed_() -> void:
	if image_file_dialog_open_ or image_file_dialog_.visible:
		image_file_dialog_.grab_focus()
		return
	if sgf_file_dialog_open_ or sgf_file_dialog_.visible:
		return
	image_file_dialog_open_ = true
	set_creation_controls_disabled_(true)
	image_file_dialog_.popup_centered_ratio(0.75)


func on_image_file_selected_(path: String) -> void:
	finish_image_file_dialog_()
	set_creation_controls_disabled_(true)
	image_import_dialog_.open_image(path, selected_board_size_())


func on_image_file_dialog_canceled_() -> void:
	finish_image_file_dialog_()


func on_image_file_dialog_visibility_changed_() -> void:
	if image_file_dialog_.visible:
		image_file_dialog_open_ = true
		set_creation_controls_disabled_(true)
		return
	finish_image_file_dialog_()


func finish_image_file_dialog_() -> void:
	image_file_dialog_open_ = false
	if not image_import_dialog_.visible:
		set_creation_controls_disabled_(false)


func on_image_import_confirmed_(
	board_size: int, cells: PackedInt32Array, source_path: String
) -> void:
	set_creation_controls_disabled_(false)
	image_create_requested.emit(board_size, cells, source_path)


func on_image_import_canceled_() -> void:
	set_creation_controls_disabled_(false)


func on_camera_pressed_() -> void:
	start_android_image_request_(true)


func on_gallery_pressed_() -> void:
	start_android_image_request_(false)


func start_android_image_request_(use_camera: bool) -> void:
	if android_host_class_ == null or android_image_request_active_:
		return
	android_image_board_size_ = selected_board_size_()
	var started: bool = false
	if use_camera:
		started = bool(android_host_class_.requestBoardImageFromCamera())
	else:
		started = bool(android_host_class_.requestBoardImageFromGallery())
	if not started:
		show_load_error(tr("无法打开安卓图片来源。"))
		return
	android_image_request_active_ = true
	set_process(true)
	set_creation_controls_disabled_(true)


func handle_android_image_result_(result: String) -> void:
	if not android_image_request_active_:
		return
	android_image_request_active_ = false
	set_process(false)
	set_creation_controls_disabled_(false)
	if result == "cancel":
		return
	if not result.begins_with("ok\n"):
		show_load_error(tr("无法读取所选图片。"))
		return
	var path: String = result.trim_prefix("ok\n")
	if path.is_empty():
		show_load_error(tr("无法读取所选图片。"))
		return
	set_creation_controls_disabled_(true)
	image_import_dialog_.open_image(path, android_image_board_size_)
