class_name BoardImageImportDialog
extends Control

signal import_confirmed(board_size: int, cells: PackedInt32Array, source_path: String)
signal import_canceled

const kMaximumDecodeDimension: int = 2400

@onready var title_: Label = %Title
@onready var instruction_: Label = %Instruction
@onready var review_: BoardImageReview = %Review
@onready var status_: RichTextLabel = %Status
@onready var recognize_button_: Button = %RecognizeButton
@onready var rotate_button_: Button = %RotateButton
@onready var accept_button_: Button = %AcceptButton
@onready var cancel_button_: Button = %CancelButton
@onready var error_dialog_: AcceptDialog = %ErrorDialog

var recognizer_: GoBoardImageRecognizer
var source_image_: Image
var source_path_: String = ""
var board_size_: int = 19
var recognition_running_: bool = false
var cancel_after_error_: bool = false


func _ready() -> void:
	recognizer_ = GoBoardImageRecognizer.new()
	recognize_button_.pressed.connect(recognize_with_current_corners_)
	rotate_button_.pressed.connect(on_rotate_pressed_)
	accept_button_.pressed.connect(on_accept_pressed_)
	cancel_button_.pressed.connect(on_cancel_pressed_)
	review_.corners_changed.connect(on_review_changed_)
	review_.cells_changed.connect(refresh_status_)
	error_dialog_.confirmed.connect(on_error_dialog_closed_)
	error_dialog_.canceled.connect(on_error_dialog_closed_)
	refresh_localized_texts()
	hide()


func refresh_localized_texts() -> void:
	if not is_node_ready():
		return
	title_.text = tr("从图片创建棋盘")
	instruction_.text = tr(
		"拖动四个黄色控制点，使其分别对准棋盘最外侧的四个交叉点；点击交叉点可在空、黑、白之间修正。"
	)
	recognize_button_.text = tr("按当前四角重新识别")
	rotate_button_.text = tr("顺时针旋转盘面")
	accept_button_.text = "✓ " + tr("创建")
	cancel_button_.text = "✕ " + tr("取消")
	error_dialog_.title = tr("图片识别失败")


func open_image(path: String, board_size: int) -> void:
	if recognition_running_:
		return
	show()
	var image: Image = Image.new()
	var load_error: Error = image.load(path)
	if load_error != OK or image.is_empty():
		cancel_after_error_ = true
		show_error_(tr("无法读取所选图片。"))
		return
	resize_for_recognition_(image)
	image.convert(Image.FORMAT_RGBA8)
	source_image_ = image
	source_path_ = path
	board_size_ = board_size
	review_.set_source_image(source_image_)
	recognize_(PackedVector2Array())


func _input(event: InputEvent) -> void:
	if not visible or error_dialog_.visible:
		return
	if event is InputEventKey:
		var key_event: InputEventKey = event as InputEventKey
		if key_event.pressed and not key_event.echo \
				and key_event.keycode == KEY_ESCAPE:
			on_cancel_pressed_()
			get_viewport().set_input_as_handled()


func recognize_with_current_corners_() -> void:
	recognize_(review_.get_grid_corners())


func recognize_(corners: PackedVector2Array) -> void:
	if source_image_ == null or recognition_running_:
		return
	if recognizer_ == null or not recognizer_.is_available():
		show_error_(tr("当前平台暂不支持棋盘图片识别。"))
		return
	recognition_running_ = true
	set_buttons_disabled_(true)
	status_.text = tr("正在识别棋盘图片…")
	var result: Dictionary = Dictionary(recognizer_.recognize(
		source_image_.get_data(),
		source_image_.get_width(),
		source_image_.get_height(),
		board_size_,
		corners
	))
	recognition_running_ = false
	set_buttons_disabled_(false)
	if not bool(result.get("ok", false)):
		var message: String = tr("棋盘图片识别失败。")
		var detail: String = str(result.get("detail", ""))
		if not detail.is_empty():
			message += "\n" + detail
		show_error_(message)
		return
	review_.apply_recognition(result)
	refresh_status_()


func refresh_status_() -> void:
	var cells: PackedInt32Array = review_.get_cells()
	var black_count: int = 0
	var white_count: int = 0
	for color: int in cells:
		if color == 1:
			black_count += 1
		elif color == 2:
			white_count += 1
	var uncertain: int = review_.get_low_confidence_count()
	var status_template: String = tr(
		"识别结果：黑子 %d，白子 %d，低置信度点 %d"
	)
	var uncertain_placeholder: int = status_template.rfind("%d")
	if uncertain_placeholder >= 0:
		status_template = status_template.insert(
			uncertain_placeholder + 2, "[/color]"
		).insert(uncertain_placeholder, "[color=#ff3b30]")
	status_.text = status_template % [
		black_count, white_count, uncertain
	]


func on_review_changed_() -> void:
	status_.text = tr("棋盘四角已调整，请点击“按当前四角重新识别”。")


func on_rotate_pressed_() -> void:
	review_.rotate_clockwise()


func on_accept_pressed_() -> void:
	if recognition_running_:
		return
	var cells: PackedInt32Array = review_.get_cells()
	if cells.size() != board_size_ * board_size_:
		show_error_(tr("棋盘图片尚未完成识别。"))
		return
	var validation_notes: GoNotes = GoNotes.new()
	if not validation_notes.reset(board_size_):
		show_error_(tr("无法校验识别盘面。"))
		return
	var command: String = build_preset_command_(cells)
	if not command.is_empty() \
			and int(validation_notes.execute_command(command)) != 0:
		show_error_(tr(
			"识别盘面包含无法预置的棋子，请修正红框附近的识别结果后重试。"
		))
		return
	hide()
	import_confirmed.emit(board_size_, cells, source_path_)


func on_cancel_pressed_() -> void:
	if recognition_running_:
		return
	hide()
	import_canceled.emit()


func set_buttons_disabled_(disabled: bool) -> void:
	recognize_button_.disabled = disabled
	rotate_button_.disabled = disabled
	accept_button_.disabled = disabled
	cancel_button_.disabled = disabled


func resize_for_recognition_(image: Image) -> void:
	var width: int = image.get_width()
	var height: int = image.get_height()
	var maximum: int = maxi(width, height)
	if maximum <= kMaximumDecodeDimension:
		return
	var scale: float = float(kMaximumDecodeDimension) / float(maximum)
	image.resize(
		maxi(1, roundi(width * scale)),
		maxi(1, roundi(height * scale)),
		Image.INTERPOLATE_LANCZOS
	)


func show_error_(message: String) -> void:
	error_dialog_.dialog_text = message
	error_dialog_.popup_centered()


func on_error_dialog_closed_() -> void:
	if not cancel_after_error_:
		return
	cancel_after_error_ = false
	hide()
	import_canceled.emit()


func build_preset_command_(cells: PackedInt32Array) -> String:
	var fields: PackedStringArray = PackedStringArray(["PRESET"])
	for index: int in range(cells.size()):
		var color: int = cells[index]
		if color != 1 and color != 2:
			continue
		fields.append(str(color))
		fields.append(str(floori(float(index) / float(board_size_)) + 1))
		fields.append(str(index % board_size_ + 1))
	return "" if fields.size() == 1 else ",".join(fields) + ";"
