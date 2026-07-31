class_name SettingsPanel
extends Control

const kGotepadVersion: String = "0.1.0"
const kBoardNames: Array[String] = [
	"浅色木纹",
	"深色木纹"
]
const kBoardPaths: Array[String] = [
	"res://assets/board/wood_light.jpg",
	"res://assets/board/wood_medium.jpg"
]
const kStoneNames: Array[String] = [
	"亮面棋子",
	"哑光棋子"
]
const kStoneBlackPaths: Array[String] = [
	"res://assets/stones/black.png",
	"res://assets/stones/black_matte.png"
]
const kStoneWhitePaths: Array[String] = [
	"res://assets/stones/white.png",
	"res://assets/stones/white_matte.png"
]

@onready var settings_button_: Button = $SettingsButton
@onready var settings_panel_: PanelContainer = $SettingsPanel
@onready var version_label_: Label = \
	$SettingsPanel/Margin/Options/Version
@onready var board_option_: OptionButton = \
	$SettingsPanel/Margin/Options/BoardOption
@onready var stone_option_: OptionButton = \
	$SettingsPanel/Margin/Options/StoneOption
@onready var one_move_: CheckBox = \
	$SettingsPanel/Margin/Options/MoveNumberOptions/OneMove
@onready var ten_moves_: CheckBox = \
	$SettingsPanel/Margin/Options/MoveNumberOptions/TenMoves
@onready var all_moves_: CheckBox = \
	$SettingsPanel/Margin/Options/MoveNumberOptions/AllMoves
@onready var custom_moves_: CheckBox = \
	$SettingsPanel/Margin/Options/CustomMoveNumberRow/CustomMoves
@onready var custom_move_count_: SpinBox = \
	$SettingsPanel/Margin/Options/CustomMoveNumberRow/CustomMoveCount
@onready var absolute_move_numbers_: CheckBox = \
	$SettingsPanel/Margin/Options/MoveNumberHeader/AbsoluteMoveNumbers
@onready var playback_interval_seconds_: SpinBox = \
	$SettingsPanel/Margin/Options/PlaybackIntervalRow/Seconds
@onready var error_label_: Label = \
	$SettingsPanel/Margin/Options/ErrorLabel
@onready var action_bar_: HBoxContainer = \
	$SettingsPanel/Margin/Options/ActionBar
@onready var confirm_button_: Button = \
	$SettingsPanel/Margin/Options/ActionBar/ConfirmButton
@onready var restore_button_: Button = \
	$SettingsPanel/Margin/Options/ActionBar/RestoreButton
@onready var cancel_button_: Button = \
	$SettingsPanel/Margin/Options/ActionBar/CancelButton

var opening_board_path_: String
var opening_black_path_: String
var opening_white_path_: String
var opening_move_number_mode_: int
var opening_move_number_count_: int
var opening_absolute_move_numbers_: bool
var opening_playback_interval_seconds_: float
var updating_options_: bool = false


func _ready() -> void:
	version_label_.text = "Gotepad 版本 %s" % kGotepadVersion
	populate_options_()
	settings_button_.pressed.connect(on_settings_pressed_)
	board_option_.item_selected.connect(on_option_selected_)
	stone_option_.item_selected.connect(on_option_selected_)
	one_move_.toggled.connect(on_move_number_option_toggled_)
	ten_moves_.toggled.connect(on_move_number_option_toggled_)
	all_moves_.toggled.connect(on_move_number_option_toggled_)
	custom_moves_.toggled.connect(on_move_number_option_toggled_)
	custom_move_count_.value_changed.connect(on_custom_move_count_changed_)
	absolute_move_numbers_.toggled.connect(on_absolute_move_numbers_toggled_)
	playback_interval_seconds_.value_changed.connect(
		on_playback_interval_changed_
	)
	confirm_button_.pressed.connect(on_confirm_pressed_)
	restore_button_.pressed.connect(on_restore_pressed_)
	cancel_button_.pressed.connect(on_cancel_pressed_)
	settings_panel_.hide()
	action_bar_.hide()
	error_label_.hide()


func populate_options_() -> void:
	for board_name in kBoardNames:
		board_option_.add_item(board_name)
	for stone_name in kStoneNames:
		stone_option_.add_item(stone_name)


func on_settings_pressed_() -> void:
	if settings_panel_.visible:
		close_panel_()
	else:
		open_panel_()


func toggle_panel() -> void:
	on_settings_pressed_()


func open_panel_() -> void:
	opening_board_path_ = SettingsStore.get_board_texture_path()
	opening_black_path_ = SettingsStore.get_black_stone_texture_path()
	opening_white_path_ = SettingsStore.get_white_stone_texture_path()
	opening_move_number_mode_ = SettingsStore.get_move_number_mode()
	opening_move_number_count_ = SettingsStore.get_move_number_count()
	opening_absolute_move_numbers_ = \
		SettingsStore.get_absolute_move_numbers()
	opening_playback_interval_seconds_ = \
		SettingsStore.get_playback_interval_seconds()
	updating_options_ = true
	select_path_(board_option_, kBoardPaths, opening_board_path_)
	select_stone_paths_(opening_black_path_, opening_white_path_)
	select_move_number_settings_(
		opening_move_number_mode_, opening_move_number_count_
	)
	absolute_move_numbers_.set_pressed_no_signal(
		opening_absolute_move_numbers_
	)
	playback_interval_seconds_.set_value_no_signal(
		opening_playback_interval_seconds_
	)
	updating_options_ = false
	update_custom_move_count_editable_()
	action_bar_.hide()
	error_label_.hide()
	settings_panel_.show()


func close_panel_() -> void:
	settings_panel_.hide()
	action_bar_.hide()
	error_label_.hide()


func select_path_(
		option: OptionButton,
		paths: Array[String],
		path: String
) -> void:
	var option_index: int = paths.find(path)
	option.select(maxi(option_index, 0))


func select_stone_paths_(black_path: String, white_path: String) -> void:
	var option_index: int = -1
	for index in range(kStoneBlackPaths.size()):
		if kStoneBlackPaths[index] == black_path \
				and kStoneWhitePaths[index] == white_path:
			option_index = index
			break
	stone_option_.select(maxi(option_index, 0))


func select_move_number_settings_(mode: int, count: int) -> void:
	var selected_mode: int = clampi(
		mode,
		SettingsStore.kMoveNumberModeOne,
		SettingsStore.kMoveNumberModeCustom
	)
	one_move_.set_pressed_no_signal(
		selected_mode == SettingsStore.kMoveNumberModeOne
	)
	ten_moves_.set_pressed_no_signal(
		selected_mode == SettingsStore.kMoveNumberModeTen
	)
	all_moves_.set_pressed_no_signal(
		selected_mode == SettingsStore.kMoveNumberModeAll
	)
	custom_moves_.set_pressed_no_signal(
		selected_mode == SettingsStore.kMoveNumberModeCustom
	)
	custom_move_count_.set_value_no_signal(float(maxi(count, 1)))


func on_move_number_option_toggled_(_pressed: bool) -> void:
	if updating_options_:
		return
	update_custom_move_count_editable_()
	on_option_selected_(0)


func on_custom_move_count_changed_(_value: float) -> void:
	on_option_selected_(0)


func on_absolute_move_numbers_toggled_(_pressed: bool) -> void:
	on_option_selected_(0)


func on_playback_interval_changed_(_value: float) -> void:
	on_option_selected_(0)


func update_custom_move_count_editable_() -> void:
	custom_move_count_.editable = custom_moves_.button_pressed


func on_option_selected_(_index: int) -> void:
	if updating_options_:
		return
	error_label_.hide()
	action_bar_.visible = has_staged_changes_()


func has_staged_changes_() -> bool:
	return selected_board_path_() != opening_board_path_ \
		or selected_black_path_() != opening_black_path_ \
		or selected_white_path_() != opening_white_path_ \
		or selected_move_number_mode_() != opening_move_number_mode_ \
		or selected_move_number_count_() != opening_move_number_count_ \
		or selected_absolute_move_numbers_() != opening_absolute_move_numbers_ \
		or not is_equal_approx(
			selected_playback_interval_seconds_(),
			opening_playback_interval_seconds_
		)


func selected_board_path_() -> String:
	return kBoardPaths[maxi(board_option_.selected, 0)]


func selected_black_path_() -> String:
	return kStoneBlackPaths[maxi(stone_option_.selected, 0)]


func selected_white_path_() -> String:
	return kStoneWhitePaths[maxi(stone_option_.selected, 0)]


func selected_move_number_mode_() -> int:
	if ten_moves_.button_pressed:
		return SettingsStore.kMoveNumberModeTen
	if all_moves_.button_pressed:
		return SettingsStore.kMoveNumberModeAll
	if custom_moves_.button_pressed:
		return SettingsStore.kMoveNumberModeCustom
	return SettingsStore.kMoveNumberModeOne


func selected_move_number_count_() -> int:
	return maxi(roundi(custom_move_count_.value), 1)



func selected_absolute_move_numbers_() -> bool:
	return absolute_move_numbers_.button_pressed


func selected_playback_interval_seconds_() -> float:
	return clampf(playback_interval_seconds_.value, 0.1, 60.0)


func on_confirm_pressed_() -> void:
	var error: Error = SettingsStore.set_display_settings(
		selected_board_path_(),
		selected_black_path_(),
		selected_white_path_(),
		selected_move_number_mode_(),
		selected_move_number_count_(),
		selected_absolute_move_numbers_(),
		selected_playback_interval_seconds_()
	)
	if error != OK:
		error_label_.text = "保存设置失败：%s" % error_string(error)
		error_label_.show()
		return

	opening_board_path_ = selected_board_path_()
	opening_black_path_ = selected_black_path_()
	opening_white_path_ = selected_white_path_()
	opening_move_number_mode_ = selected_move_number_mode_()
	opening_move_number_count_ = selected_move_number_count_()
	opening_absolute_move_numbers_ = selected_absolute_move_numbers_()
	opening_playback_interval_seconds_ = selected_playback_interval_seconds_()
	error_label_.hide()
	action_bar_.hide()

func on_restore_pressed_() -> void:
	updating_options_ = true
	select_path_(board_option_, kBoardPaths, opening_board_path_)
	select_stone_paths_(opening_black_path_, opening_white_path_)
	select_move_number_settings_(
		opening_move_number_mode_, opening_move_number_count_
	)
	absolute_move_numbers_.set_pressed_no_signal(
		opening_absolute_move_numbers_
	)
	playback_interval_seconds_.set_value_no_signal(
		opening_playback_interval_seconds_
	)
	updating_options_ = false
	update_custom_move_count_editable_()
	error_label_.hide()
	action_bar_.hide()


func on_cancel_pressed_() -> void:
	close_panel_()
