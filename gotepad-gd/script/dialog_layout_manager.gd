extends Node

const kMaximumWidthRatio: float = 2.0 / 3.0
const kDialogHorizontalPadding: float = 64.0
const kButtonHorizontalPadding: float = 10.0
const kButtonVerticalPadding: float = 0.0


func _ready() -> void:
	get_tree().node_added.connect(on_node_added_)
	configure_descendants_(get_tree().root)


func on_node_added_(node: Node) -> void:
	configure_dialog_(node)


func configure_descendants_(node: Node) -> void:
	configure_dialog_(node)
	for child: Node in node.get_children():
		configure_descendants_(child)


func configure_dialog_(node: Node) -> void:
	if node is FileDialog:
		return
	var dialog: AcceptDialog = node as AcceptDialog
	if dialog == null:
		return
	var callback: Callable = Callable(self, "prepare_dialog_").bind(dialog)
	if not dialog.about_to_popup.is_connected(callback):
		dialog.about_to_popup.connect(callback)


func prepare_dialog_(dialog: AcceptDialog) -> void:
	if not is_instance_valid(dialog):
		return
	configure_action_buttons_(dialog)
	var viewport_size: Vector2 = get_tree().root.get_visible_rect().size
	var viewport_width: int = roundi(viewport_size.x)
	var maximum_content_width: int = maxi(
		floori(float(viewport_width) * kMaximumWidthRatio), 1
	)
	# AcceptDialog 内部控件使用逻辑像素，而 Window.size/max_size 使用
	# 窗口像素。高分屏和移动端必须按对话框的内容缩放倍率进行换算，
	# 否则 max_size 会小于内容的物理最小宽度并被 Window 忽略。
	var content_scale: float = maxf(dialog.content_scale_factor, 0.01)
	var maximum_window_width: int = maxi(
		roundi(float(maximum_content_width) * content_scale), 1
	)
	var maximum_window_height: int = maxi(
		roundi(viewport_size.y * content_scale), 1
	)
	dialog.dialog_autowrap = true
	# Window.max_size 的分量为 0 表示最大尺寸就是 0，并非“不限制”。
	# 高度必须使用实际视口上限，否则内容区会被压缩到只剩标题栏。
	dialog.max_size = Vector2i(maximum_window_width, maximum_window_height)

	var message_label: Label = dialog.get_label()
	if message_label == null:
		return
	message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message_label.custom_minimum_size.x = 0.0
	var natural_text_width: float = measure_text_width_(message_label)
	var available_text_width: float = maxf(
		float(maximum_content_width) - kDialogHorizontalPadding, 1.0
	)
	if natural_text_width > available_text_width \
			or dialog.size.x > maximum_window_width:
		message_label.custom_minimum_size.x = available_text_width
	# about_to_popup 会在 popup_centered() 应用请求尺寸之前发出。这里不能
	# 写入 dialog.size，也不能调用 reset_size()：前者会沿用尚未布局的高度，
	# 后者会按自动换行 Label 接近零的最小尺寸收缩窗口。只设置宽度约束，
	# 让随后执行的 popup_centered() 正常决定高度和最终布局。


func configure_action_buttons_(dialog: AcceptDialog) -> void:
	var ok_button: Button = dialog.get_ok_button()
	if ok_button == null:
		return
	var button_row: Node = ok_button.get_parent()
	if button_row == null:
		return
	for child: Node in button_row.get_children():
		var button: Button = child as Button
		if button != null:
			apply_button_padding_(button)


func apply_button_padding_(button: Button) -> void:
	if button.has_meta(&"gotepad_dialog_padding"):
		return
	button.set_meta(&"gotepad_dialog_padding", true)
	for style_name: StringName in [
		&"normal", &"hover", &"pressed", &"disabled", &"hover_pressed"
	]:
		var source_style: StyleBox = button.get_theme_stylebox(style_name)
		if source_style == null:
			continue
		var padded_style: StyleBox = source_style.duplicate() as StyleBox
		padded_style.content_margin_left = \
			source_style.get_content_margin(SIDE_LEFT) \
			+ kButtonHorizontalPadding
		padded_style.content_margin_right = \
			source_style.get_content_margin(SIDE_RIGHT) \
			+ kButtonHorizontalPadding
		padded_style.content_margin_top = \
			source_style.get_content_margin(SIDE_TOP) \
			+ kButtonVerticalPadding
		padded_style.content_margin_bottom = \
			source_style.get_content_margin(SIDE_BOTTOM) \
			+ kButtonVerticalPadding
		button.add_theme_stylebox_override(style_name, padded_style)


func measure_text_width_(label: Label) -> float:
	var font: Font = label.get_theme_font(&"font")
	var font_size: int = label.get_theme_font_size(&"font_size")
	if font == null or font_size <= 0:
		return 0.0
	return font.get_multiline_string_size(
		label.text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		font_size
	).x
