extends Node

const kMaximumWidthRatio: float = 2.0 / 3.0
const kButtonMinimumHeight: float = 44.0
const kButtonMinimumWidth: float = 96.0
const kButtonSeparation: int = 12
const kMaximumLayoutPasses: int = 4
const kStableLayoutPasses: int = 2

var requested_sizes_: Dictionary = {}
var pending_layouts_: Dictionary = {}
var next_layout_version_: int = 0


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
	var callback: Callable = Callable(self, "on_dialog_about_to_popup_").bind(dialog)
	if dialog.about_to_popup.is_connected(callback):
		return
	var dialog_id: int = dialog.get_instance_id()
	dialog.about_to_popup.connect(callback)
	dialog.visibility_changed.connect(on_dialog_visibility_changed_.bind(dialog))
	dialog.tree_exiting.connect(forget_dialog_.bind(dialog_id), CONNECT_ONE_SHOT)
	if dialog.is_node_ready():
		initialize_dialog_(dialog)
	else:
		dialog.ready.connect(initialize_dialog_.bind(dialog), CONNECT_ONE_SHOT)


func initialize_dialog_(dialog: AcceptDialog) -> void:
	configure_action_buttons_(dialog)
	dialog.get_label().autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


# 必须在 Godot 的 popup_centered() 首次读取最小尺寸之前准备布局。
# 保持同步弹出，避免后台操作结束或取消后，排队中的弹窗才延迟显示。
# 无请求尺寸时按当次内容计算，不把上次或首次未布局的高度作为下限。
func popup_centered(dialog: AcceptDialog, minimum_size: Vector2i = Vector2i.ZERO) -> void:
	if not is_instance_valid(dialog) or not dialog.is_inside_tree():
		return
	if dialog is FileDialog:
		dialog.popup_centered(minimum_size)
		return
	configure_dialog_(dialog)
	var dialog_id: int = dialog.get_instance_id()
	requested_sizes_[dialog_id] = minimum_size
	prepare_dialog_(dialog, requested_sizes_[dialog_id])
	dialog.popup_centered(dialog.size)


func on_dialog_about_to_popup_(dialog: AcceptDialog) -> void:
	var dialog_id: int = dialog.get_instance_id()
	var requested_size: Vector2i = requested_sizes_.get(
		dialog_id, Vector2i.ZERO
	)
	prepare_dialog_(dialog, requested_size)
	next_layout_version_ += 1
	pending_layouts_[dialog_id] = next_layout_version_
	settle_dialog_.call_deferred(dialog, requested_size, next_layout_version_)


func prepare_dialog_(dialog: AcceptDialog, requested_size: Vector2i) -> void:
	configure_action_buttons_(dialog)
	var maximum_size: Vector2i = maximum_window_size_(dialog)
	var content_scale: float = maxf(dialog.content_scale_factor, 0.01)
	var panel: StyleBox = dialog.get_theme_stylebox(&"panel", &"AcceptDialog")
	var padding: Vector2 = panel.get_minimum_size()
	var message_label: Label = dialog.get_label()
	message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var available_text_width: float = maxf(
		float(maximum_size.x) / content_scale - padding.x, 1.0
	)
	# 保留有限宽度，避免清零后以旧宽度或零宽度计算换行高度。
	message_label.custom_minimum_size.x = minf(
		measure_text_width_(message_label), available_text_width
	)
	var minimum_width: float = dialog.get_contents_minimum_size().x * content_scale
	var target_width: int = clampi(
		maxi(requested_size.x, ceili(minimum_width)), 1, maximum_size.x
	)
	var content_width: float = maxf(
		float(target_width) / content_scale - padding.x, 1.0
	)
	message_label.size.x = content_width
	message_label.update_minimum_size()
	# AcceptDialog 的自定义内容也需先获得宽度，再让嵌套容器完成排列。
	# get_children() 默认不包含内部按钮行和背景；内置 Label 单独处理。
	for child: Node in dialog.get_children():
		var control: Control = child as Control
		if control != null and control.visible and not control.is_set_as_top_level():
			control.size.x = content_width
			control.update_minimum_size()
	dialog.max_size = maximum_size
	var contents_size: Vector2 = dialog.get_contents_minimum_size() * content_scale
	dialog.size = Vector2i(
		target_width,
		clampi(maxi(requested_size.y, ceili(contents_size.y)), 1, maximum_size.y)
	)


func maximum_window_size_(dialog: AcceptDialog) -> Vector2i:
	var owner_window: Window = dialog.get_parent().get_window()
	if owner_window == null:
		owner_window = get_tree().root
	var viewport_size: Vector2 = owner_window.get_visible_rect().size
	# 嵌入窗口使用父视口坐标；独立系统窗口使用窗口像素。
	# 内容尺寸始终使用对话框自己的 content_scale_factor 换算。
	if not dialog.is_embedded():
		viewport_size *= maxf(owner_window.content_scale_factor, 0.01)
	return Vector2i(
		maxi(floori(viewport_size.x * kMaximumWidthRatio), 1),
		maxi(floori(viewport_size.y), 1)
	)


func settle_dialog_(dialog: AcceptDialog, requested_size: Vector2i, version: int) -> void:
	if not is_instance_valid(dialog):
		return
	var dialog_id: int = dialog.get_instance_id()
	var stable_passes: int = 0
	# call_deferred() 不是帧屏障；跨帧观察两次稳定尺寸，最多校正四次。
	for _pass_index: int in range(kMaximumLayoutPasses):
		await get_tree().process_frame
		if not is_instance_valid(dialog) \
				or pending_layouts_.get(dialog_id, -1) != version \
				or not dialog.visible:
			return
		var previous_size: Vector2i = dialog.size
		prepare_dialog_(dialog, requested_size)
		if dialog.size != previous_size:
			dialog.move_to_center()
			stable_passes = 0
		else:
			stable_passes += 1
		if stable_passes >= kStableLayoutPasses:
			break
	if pending_layouts_.get(dialog_id, -1) == version:
		pending_layouts_.erase(dialog_id)


func on_dialog_visibility_changed_(dialog: AcceptDialog) -> void:
	if not dialog.visible:
		var dialog_id: int = dialog.get_instance_id()
		pending_layouts_.erase(dialog_id)
		requested_sizes_.erase(dialog_id)


func forget_dialog_(dialog_id: int) -> void:
	requested_sizes_.erase(dialog_id)
	pending_layouts_.erase(dialog_id)


func configure_action_buttons_(dialog: AcceptDialog) -> void:
	var ok_button: Button = dialog.get_ok_button()
	if ok_button == null:
		return
	var button_row: Node = ok_button.get_parent()
	if button_row == null:
		return
	var row_container: BoxContainer = button_row as BoxContainer
	if row_container != null \
			and row_container.get_theme_constant(&"separation") != kButtonSeparation:
		row_container.add_theme_constant_override(&"separation", kButtonSeparation)
	var ok_variation: StringName = &"CafePrimaryButton"
	match str(dialog.get_meta(&"ok_role", &"primary")):
		"danger":
			ok_variation = &"CafeDangerButton"
		"secondary":
			ok_variation = &"CafeSecondaryButton"
	for child: Node in button_row.get_children():
		var button: Button = child as Button
		if button != null:
			var variation: StringName = ok_variation \
				if button == ok_button else &"CafeSecondaryButton"
			if button.theme_type_variation != variation:
				button.theme_type_variation = variation
			button.custom_minimum_size = Vector2(
				maxf(button.custom_minimum_size.x, kButtonMinimumWidth),
				maxf(button.custom_minimum_size.y, kButtonMinimumHeight)
			)
			button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


func measure_text_width_(label: Label) -> float:
	var font: Font = label.get_theme_font(&"font")
	var font_size: int = label.get_theme_font_size(&"font_size")
	if font == null or font_size <= 0:
		return 0.0
	var displayed_text: String = label.atr(label.text)
	if label.uppercase:
		displayed_text = displayed_text.to_upper()
	return font.get_multiline_string_size(
		displayed_text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		font_size
	).x
