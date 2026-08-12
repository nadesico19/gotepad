class_name DocumentTabBar
extends Control

signal tab_selected(index: int)
signal tab_close_requested(index: int)

const kTabGap: float = 4.0
const kMinimumTabWidth: float = 72.0
const kMaximumTabWidth: float = 280.0
const kTitlePadding: float = 20.0
const kCloseButtonWidth: float = 28.0
const kTitleFontSizeReduction: int = 2

var titles_: PackedStringArray = PackedStringArray()
var buttons_: Array[Button] = []
var close_buttons_: Array[Button] = []
var selected_index_: int = -1


func _ready() -> void:
	clip_contents = true
	resized.connect(update_layout_)
	queue_redraw()


func _draw() -> void:
	draw_rect(
		Rect2(Vector2.ZERO, size),
		Color(0.08, 0.07, 0.055, 0.72)
	)
	if selected_index_ < 0 or selected_index_ >= buttons_.size():
		return
	var selected_button: Button = buttons_[selected_index_]
	var close_button: Button = close_buttons_[selected_index_]
	var selected_width: float = close_button.position.x \
		+ close_button.size.x - selected_button.position.x
	draw_rect(
		Rect2(
			Vector2(selected_button.position.x, size.y - 3.0),
			Vector2(selected_width, 3.0)
		),
		Color(0.95, 0.72, 0.28, 1.0)
	)


func set_tabs(titles: PackedStringArray, selected_index: int) -> void:
	var contents_changed: bool = titles_ != titles
	titles_ = titles.duplicate()
	selected_index_ = selected_index
	if contents_changed or buttons_.size() != titles_.size():
		rebuild_tab_buttons_()
	for index: int in range(buttons_.size()):
		buttons_[index].tooltip_text = titles_[index]
		buttons_[index].set_pressed_no_signal(index == selected_index_)
	update_layout_()


func set_selected(index: int) -> void:
	selected_index_ = index
	for button_index: int in range(buttons_.size()):
		buttons_[button_index].set_pressed_no_signal(
			button_index == selected_index_
		)
	queue_redraw()


func add_tab_button_() -> void:
	var button: Button = Button.new()
	button.flat = true
	button.clip_text = true
	button.toggle_mode = true
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.add_theme_color_override(&"font_color", Color(0.9, 0.9, 0.86))
	button.add_theme_color_override(
		&"font_hover_color", Color(1.0, 0.88, 0.56)
	)
	button.add_theme_color_override(
		&"font_pressed_color", Color(1.0, 0.88, 0.56)
	)
	button.add_theme_font_size_override(&"font_size", tab_title_font_size_())
	var index: int = buttons_.size()
	button.pressed.connect(on_tab_pressed_.bind(index))
	buttons_.append(button)
	add_child(button)

	var close_button: Button = Button.new()
	close_button.flat = true
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	close_button.tooltip_text = tr("关闭标签")
	close_button.text = "✕"
	close_button.add_theme_color_override(
		&"font_color", Color(0.78, 0.78, 0.74)
	)
	close_button.add_theme_color_override(
		&"font_hover_color", Color(1.0, 0.55, 0.45)
	)
	close_button.pressed.connect(on_tab_close_pressed_.bind(index))
	close_buttons_.append(close_button)
	add_child(close_button)


func rebuild_tab_buttons_() -> void:
	for button: Button in buttons_:
		remove_child(button)
		button.queue_free()
	for close_button: Button in close_buttons_:
		remove_child(close_button)
		close_button.queue_free()
	buttons_.clear()
	close_buttons_.clear()
	for _index: int in range(titles_.size()):
		add_tab_button_()


func on_tab_pressed_(index: int) -> void:
	if index < 0 or index >= buttons_.size():
		return
	set_selected(index)
	tab_selected.emit(index)


func on_tab_close_pressed_(index: int) -> void:
	if index < 0 or index >= close_buttons_.size():
		return
	tab_close_requested.emit(index)


func update_layout_() -> void:
	if not is_node_ready() or buttons_.is_empty():
		return
	var widths: PackedFloat32Array = calculate_tab_widths_()
	var x: float = 0.0
	for index: int in range(buttons_.size()):
		var button: Button = buttons_[index]
		var close_button: Button = close_buttons_[index]
		var width: float = widths[index]
		button.position = Vector2(x, 0.0)
		button.size = Vector2(
			maxf(width - kCloseButtonWidth, 0.0),
			size.y
		)
		close_button.position = Vector2(
			x + maxf(width - kCloseButtonWidth, 0.0),
			0.0
		)
		close_button.size = Vector2(
			minf(kCloseButtonWidth, width),
			size.y
		)
		button.text = elide_middle_(
			titles_[index],
			maxf(width - kCloseButtonWidth - kTitlePadding, 0.0)
		)
		x += width + kTabGap
	queue_redraw()


func calculate_tab_widths_() -> PackedFloat32Array:
	var widths: PackedFloat32Array = PackedFloat32Array()
	var desired_widths: PackedFloat32Array = PackedFloat32Array()
	var font: Font = get_theme_font(&"font", &"Button")
	var font_size: int = tab_title_font_size_()
	var desired_total: float = kTabGap * float(maxi(titles_.size() - 1, 0))
	for title: String in titles_:
		var text_width: float = font.get_string_size(
			title, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size
		).x
		var desired_width: float = clampf(
			text_width + kTitlePadding + kCloseButtonWidth,
			kMinimumTabWidth,
			kMaximumTabWidth
		)
		desired_widths.append(desired_width)
		desired_total += desired_width
	if desired_total <= size.x:
		return desired_widths

	var gap_total: float = kTabGap * float(maxi(titles_.size() - 1, 0))
	var usable_width: float = maxf(size.x - gap_total, 0.0)
	var base_width: float = minf(
		kMinimumTabWidth,
		usable_width / float(maxi(titles_.size(), 1))
	)
	for _index: int in range(titles_.size()):
		widths.append(base_width)

	var remaining: float = maxf(
		usable_width - base_width * float(titles_.size()),
		0.0
	)
	var unfinished: Array[int] = []
	for index: int in range(titles_.size()):
		if desired_widths[index] > base_width:
			unfinished.append(index)
	while remaining > 0.5 and not unfinished.is_empty():
		var share: float = remaining / float(unfinished.size())
		var next_unfinished: Array[int] = []
		var distributed: float = 0.0
		for index: int in unfinished:
			var needed: float = desired_widths[index] - widths[index]
			var addition: float = minf(needed, share)
			widths[index] += addition
			distributed += addition
			if needed - addition > 0.5:
				next_unfinished.append(index)
		if distributed <= 0.0:
			break
		remaining -= distributed
		unfinished = next_unfinished
	return widths


func elide_middle_(title: String, available_width: float) -> String:
	var font: Font = get_theme_font(&"font", &"Button")
	var font_size: int = tab_title_font_size_()
	if font.get_string_size(
		title, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size
	).x <= available_width:
		return title
	var ellipsis: String = ".."
	if font.get_string_size(
		ellipsis, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size
	).x > available_width:
		return ""

	var left_count: int = ceili(float(title.length()) * 0.5)
	var right_count: int = title.length() - left_count
	while left_count > 0 or right_count > 0:
		var right_text: String = ""
		if right_count > 0:
			right_text = title.substr(
				title.length() - right_count, right_count
			)
		var candidate: String = title.substr(0, left_count) \
			+ ellipsis + right_text
		if font.get_string_size(
			candidate, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size
		).x <= available_width:
			return candidate
		if left_count > right_count:
			left_count -= 1
		elif right_count > 0:
			right_count -= 1
		else:
			left_count -= 1
	return ellipsis


func tab_title_font_size_() -> int:
	return maxi(
		get_theme_font_size(&"font_size", &"Button")
			- kTitleFontSizeReduction,
		1
	)
