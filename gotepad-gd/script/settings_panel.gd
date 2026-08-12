class_name SettingsPanel
extends Control

const kGotepadVersion: String = "0.1.5"
const kKatagoTestTimeoutMsec: int = 5000
const kKatagoBenchmarkVisits: int = 8
const kKatagoBenchmarkSecondsPerMove: float = 10.0
const kKatagoBenchmarkThreads: String = \
	"2,4,6,8,12,16,24,32,48,64,96,128"
const kStatusNeutralColor: Color = Color(0.72, 0.72, 0.75, 1.0)
const kStatusValidColor: Color = Color(0.4, 0.9, 0.55, 1.0)
const kStatusErrorColor: Color = Color(1.0, 0.4, 0.4, 1.0)
const kStatusCanceledColor: Color = Color(0.95, 0.78, 0.28, 1.0)
const kBenchmarkStateIdle: int = 0
const kBenchmarkStateRunning: int = 1
const kBenchmarkStateSucceeded: int = 2
const kBenchmarkStateFailed: int = 3
const kPanelLeftButtonMargin: float = 18.0
const kLanguageLocales: Array[String] = [
	"zh_CN",
	"ja",
	"ko",
	"en",
]
const kLanguageNativeNames: Array[String] = [
	"中文",
	"日本語",
	"한국어",
	"English",
]
const kMobileHiddenKatagoOptionNodeNames: Array[String] = [
	"KatagoExecutableLabel",
	"KatagoExecutableRow",
	"KatagoModelLabel",
	"KatagoModelRow",
	"KatagoConfigLabel",
	"KatagoConfigRow",
]
const kKatagoOptionNodeNames: Array[String] = [
	"KatagoSeparator",
	"KatagoTitle",
	"KatagoExecutableLabel",
	"KatagoExecutableRow",
	"KatagoModelLabel",
	"KatagoModelRow",
	"KatagoConfigLabel",
	"KatagoConfigRow",
	"KatagoMaxVisitsRow",
	"KatagoReportIntervalRow",
	"KatagoAnalysisPvLengthRow",
	"KatagoShowScoreLead",
	"KatagoGameAnalysisVisitsRow",
	"KatagoTestRow",
	"KatagoStatus",
]
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
@onready var language_option_: OptionButton = \
	$SettingsPanel/Margin/Options/LanguageOption
@onready var horizontal_safe_margin_: SpinBox = \
	$SettingsPanel/Margin/Options/HorizontalSafeMarginRow/Pixels
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
@onready var stone_sound_volume_: HSlider = \
	$SettingsPanel/Margin/Options/StoneSoundVolumeRow/Volume
@onready var stone_sound_volume_value_: Label = \
	$SettingsPanel/Margin/Options/StoneSoundVolumeRow/Value
@onready var move_confirmation_: CheckBox = \
	$SettingsPanel/Margin/Options/MoveConfirmation
@onready var pptx_image_format_: OptionButton = \
	$SettingsPanel/Margin/Options/PptxImageFormatRow/Format
@onready var pptx_board_coordinates_: CheckBox = \
	$SettingsPanel/Margin/Options/PptxBoardCoordinates
@onready var katago_executable_path_: LineEdit = \
	$SettingsPanel/Margin/Options/KatagoExecutableRow/Path
@onready var katago_executable_browse_: Button = \
	$SettingsPanel/Margin/Options/KatagoExecutableRow/Browse
@onready var katago_model_path_: LineEdit = \
	$SettingsPanel/Margin/Options/KatagoModelRow/Path
@onready var katago_model_browse_: Button = \
	$SettingsPanel/Margin/Options/KatagoModelRow/Browse
@onready var katago_analysis_config_path_: LineEdit = \
	$SettingsPanel/Margin/Options/KatagoConfigRow/Path
@onready var katago_analysis_config_browse_: Button = \
	$SettingsPanel/Margin/Options/KatagoConfigRow/Browse
@onready var katago_max_visits_: SpinBox = \
	$SettingsPanel/Margin/Options/KatagoMaxVisitsRow/Visits
@onready var katago_report_interval_seconds_: SpinBox = \
	$SettingsPanel/Margin/Options/KatagoReportIntervalRow/Seconds
@onready var katago_analysis_pv_length_: SpinBox = \
	$SettingsPanel/Margin/Options/KatagoAnalysisPvLengthRow/Moves
@onready var katago_show_score_lead_: CheckBox = \
	$SettingsPanel/Margin/Options/KatagoShowScoreLead
@onready var katago_game_analysis_visits_: SpinBox = \
	$SettingsPanel/Margin/Options/KatagoGameAnalysisVisitsRow/Visits
@onready var katago_test_button_: Button = \
	$SettingsPanel/Margin/Options/KatagoTestRow/Test
@onready var katago_benchmark_button_: Button = \
	$SettingsPanel/Margin/Options/KatagoTestRow/Benchmark
@onready var katago_status_: Label = \
	$SettingsPanel/Margin/Options/KatagoStatus
@onready var katago_executable_dialog_: FileDialog = \
	$KatagoExecutableDialog
@onready var katago_model_dialog_: FileDialog = $KatagoModelDialog
@onready var katago_config_dialog_: FileDialog = $KatagoConfigDialog
@onready var katago_benchmark_confirmation_: ConfirmationDialog = \
	$KatagoBenchmarkConfirmation
@onready var katago_benchmark_window_: Window = $KatagoBenchmarkWindow
@onready var katago_benchmark_output_edit_: TextEdit = \
	$KatagoBenchmarkWindow/Panel/Margin/Content/Output
@onready var katago_benchmark_action_button_: Button = \
	$KatagoBenchmarkWindow/Panel/Margin/Content/Footer/Action
@onready var katago_benchmark_save_reminder_: AcceptDialog = \
	$KatagoBenchmarkWindow/SaveReminder
@onready var error_label_: Label = \
	$SettingsPanel/Margin/Options/ErrorLabel
@onready var close_button_: Button = $CloseButton
@onready var action_bar_: VBoxContainer = \
	$ActionBar
@onready var confirm_button_: Button = \
	$ActionBar/ConfirmButton
@onready var restore_button_: Button = \
	$ActionBar/RestoreButton
@onready var cancel_button_: Button = \
	$ActionBar/CancelButton

var opening_board_path_: String
var opening_language_: String
var opening_horizontal_safe_margin_: int
var opening_black_path_: String
var opening_white_path_: String
var opening_move_number_mode_: int
var opening_move_number_count_: int
var opening_absolute_move_numbers_: bool
var opening_playback_interval_seconds_: float
var opening_stone_sound_volume_: int
var opening_move_confirmation_: bool
var opening_pptx_image_format_: int
var opening_pptx_board_coordinates_: bool
var opening_katago_executable_path_: String
var opening_katago_model_path_: String
var opening_katago_analysis_config_path_: String
var opening_katago_max_visits_: int
var opening_katago_report_interval_seconds_: float
var opening_katago_analysis_pv_length_: int
var opening_katago_show_score_lead_: bool
var opening_katago_game_analysis_visits_: int
var updating_options_: bool = false
var katago_test_process_: Dictionary = {}
var katago_test_output_: String = ""
var katago_test_started_msec_: int = 0
var katago_benchmark_process_: Dictionary = {}
var katago_embedded_benchmark_: KataGoEmbeddedBenchmark
var katago_benchmark_output_: String = ""
var katago_benchmark_state_: int = kBenchmarkStateIdle
var pending_katago_benchmark_threads_: int = 0
var pending_katago_benchmark_batch_size_: int = 0
var active_katago_file_dialog_: FileDialog


func _ready() -> void:
	populate_options_()
	refresh_localized_options_()
	configure_platform_option_visibility_()
	settings_panel_.resized.connect(position_panel_left_buttons_)
	settings_button_.pressed.connect(on_settings_pressed_)
	language_option_.item_selected.connect(on_language_selected_)
	horizontal_safe_margin_.value_changed.connect(
		on_katago_analysis_option_changed_
	)
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
	stone_sound_volume_.value_changed.connect(on_stone_sound_volume_changed_)
	move_confirmation_.toggled.connect(on_katago_boolean_option_changed_)
	pptx_image_format_.item_selected.connect(on_option_selected_)
	pptx_board_coordinates_.toggled.connect(on_katago_boolean_option_changed_)
	katago_executable_path_.text_changed.connect(on_katago_path_changed_)
	katago_model_path_.text_changed.connect(on_katago_path_changed_)
	katago_analysis_config_path_.text_changed.connect(on_katago_path_changed_)
	katago_max_visits_.value_changed.connect(on_katago_max_visits_changed_)
	katago_report_interval_seconds_.value_changed.connect(
		on_katago_analysis_option_changed_
	)
	katago_analysis_pv_length_.value_changed.connect(
		on_katago_analysis_option_changed_
	)
	katago_show_score_lead_.toggled.connect(on_katago_boolean_option_changed_)
	katago_game_analysis_visits_.value_changed.connect(
		on_katago_analysis_option_changed_
	)
	katago_executable_browse_.pressed.connect(
		on_katago_executable_browse_pressed_
	)
	katago_model_browse_.pressed.connect(on_katago_model_browse_pressed_)
	katago_analysis_config_browse_.pressed.connect(
		on_katago_config_browse_pressed_
	)
	katago_executable_dialog_.file_selected.connect(
		on_katago_executable_selected_
	)
	katago_model_dialog_.file_selected.connect(on_katago_model_selected_)
	katago_config_dialog_.file_selected.connect(on_katago_config_selected_)
	katago_executable_dialog_.canceled.connect(on_katago_file_dialog_canceled_)
	katago_model_dialog_.canceled.connect(on_katago_file_dialog_canceled_)
	katago_config_dialog_.canceled.connect(on_katago_file_dialog_canceled_)
	katago_test_button_.pressed.connect(on_katago_test_pressed_)
	katago_benchmark_button_.pressed.connect(on_katago_benchmark_pressed_)
	katago_benchmark_confirmation_.confirmed.connect(start_katago_benchmark_)
	katago_benchmark_action_button_.pressed.connect(
		on_katago_benchmark_action_pressed_
	)
	katago_benchmark_window_.close_requested.connect(
		on_katago_benchmark_window_close_requested_
	)
	katago_benchmark_save_reminder_.confirmed.connect(
		close_katago_benchmark_window_
	)
	katago_benchmark_save_reminder_.canceled.connect(
		close_katago_benchmark_window_
	)
	close_button_.pressed.connect(on_cancel_pressed_)
	confirm_button_.pressed.connect(on_confirm_pressed_)
	restore_button_.pressed.connect(on_restore_pressed_)
	cancel_button_.pressed.connect(on_cancel_pressed_)
	settings_panel_.hide()
	close_button_.hide()
	action_bar_.hide()
	error_label_.hide()
	katago_benchmark_window_.hide()
	set_process(false)
	call_deferred(&"position_panel_left_buttons_")


func configure_platform_option_visibility_() -> void:
	if not OS.has_feature("mobile"):
		return
	var options: VBoxContainer = $SettingsPanel/Margin/Options
	var hidden_node_names: Array[String] = kMobileHiddenKatagoOptionNodeNames \
		if OS.get_name() == "Android" else kKatagoOptionNodeNames
	for node_name: String in hidden_node_names:
		var option_node: CanvasItem = options.get_node_or_null(node_name) \
			as CanvasItem
		if option_node != null:
			option_node.hide()
	if OS.get_name() == "Android":
		katago_test_button_.hide()


func populate_options_() -> void:
	for index in range(kLanguageLocales.size()):
		language_option_.add_item(kLanguageNativeNames[index])
		language_option_.set_item_metadata(index, kLanguageLocales[index])


func refresh_localized_options_() -> void:
	if not is_node_ready():
		return
	version_label_.text = tr("Gotepad 版本 %s") % kGotepadVersion
	custom_move_count_.suffix = " %s" % tr("手")
	playback_interval_seconds_.suffix = " %s" % tr("秒")
	katago_report_interval_seconds_.suffix = " %s" % tr("秒")
	katago_analysis_pv_length_.suffix = " %s" % tr("手")
	katago_executable_dialog_.filters = PackedStringArray([
		"*.exe ; %s" % tr("Windows 可执行文件"),
		"* ; %s" % tr("所有文件"),
	])
	katago_model_dialog_.filters = PackedStringArray([
		"*.bin.gz ; %s" % tr("KataGo 神经网络模型"),
	])
	katago_config_dialog_.filters = PackedStringArray([
		"*.cfg ; %s" % tr("KataGo 配置文件"),
	])
	var board_index: int = maxi(board_option_.selected, 0)
	var stone_index: int = maxi(stone_option_.selected, 0)
	var format_index: int = maxi(pptx_image_format_.selected, 0)
	updating_options_ = true
	board_option_.clear()
	for board_name: String in kBoardNames:
		board_option_.add_item(tr(board_name))
	stone_option_.clear()
	for stone_name: String in kStoneNames:
		stone_option_.add_item(tr(stone_name))
	pptx_image_format_.clear()
	pptx_image_format_.add_item(tr("SVG (矢量)"))
	pptx_image_format_.add_item(tr("PNG (兼容)"))
	board_option_.select(clampi(board_index, 0, kBoardNames.size() - 1))
	stone_option_.select(clampi(stone_index, 0, kStoneNames.size() - 1))
	pptx_image_format_.select(clampi(format_index, 0, 1))
	updating_options_ = false
	set_katago_benchmark_window_state_(katago_benchmark_state_)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		refresh_localized_options_()
		call_deferred(&"position_panel_left_buttons_")
	elif what == NOTIFICATION_RESIZED and is_node_ready():
		call_deferred(&"position_panel_left_buttons_")


func position_panel_left_buttons_() -> void:
	if not is_node_ready():
		return
	var target_x: float = roundf(
		settings_panel_.position.x + kPanelLeftButtonMargin
	)
	close_button_.position.x = target_x
	action_bar_.position.x = target_x


func on_settings_pressed_() -> void:
	if settings_panel_.visible:
		close_panel_()
	else:
		open_panel_()


func toggle_panel() -> void:
	on_settings_pressed_()


func open_panel_() -> void:
	pending_katago_benchmark_threads_ = 0
	pending_katago_benchmark_batch_size_ = 0
	opening_language_ = SettingsStore.get_language()
	opening_horizontal_safe_margin_ = SettingsStore.get_horizontal_safe_margin()
	opening_board_path_ = SettingsStore.get_board_texture_path()
	opening_black_path_ = SettingsStore.get_black_stone_texture_path()
	opening_white_path_ = SettingsStore.get_white_stone_texture_path()
	opening_move_number_mode_ = SettingsStore.get_move_number_mode()
	opening_move_number_count_ = SettingsStore.get_move_number_count()
	opening_absolute_move_numbers_ = \
		SettingsStore.get_absolute_move_numbers()
	opening_playback_interval_seconds_ = \
		SettingsStore.get_playback_interval_seconds()
	opening_stone_sound_volume_ = SettingsStore.get_stone_sound_volume()
	opening_move_confirmation_ = \
		SettingsStore.get_move_confirmation_enabled()
	opening_pptx_image_format_ = SettingsStore.get_pptx_image_format()
	opening_pptx_board_coordinates_ = \
		SettingsStore.get_pptx_board_coordinates()
	opening_katago_executable_path_ = \
		SettingsStore.get_katago_executable_path()
	opening_katago_model_path_ = SettingsStore.get_katago_model_path()
	opening_katago_analysis_config_path_ = \
		SettingsStore.get_katago_analysis_config_path()
	opening_katago_max_visits_ = SettingsStore.get_katago_max_visits()
	opening_katago_report_interval_seconds_ = \
		SettingsStore.get_katago_report_interval_seconds()
	opening_katago_analysis_pv_length_ = \
		SettingsStore.get_katago_analysis_pv_length()
	opening_katago_show_score_lead_ = \
		SettingsStore.get_katago_show_score_lead()
	opening_katago_game_analysis_visits_ = \
		SettingsStore.get_katago_game_analysis_visits()
	var local_katago_available: bool = not OS.has_feature("mobile")
	var executable_path_invalid: bool = local_katago_available \
		and not opening_katago_executable_path_.is_empty() \
		and not SettingsStore.is_katago_executable_path_valid(
			opening_katago_executable_path_
		)
	var model_path_invalid: bool = local_katago_available \
		and not opening_katago_model_path_.is_empty() \
		and not SettingsStore.is_katago_model_path_valid(
			opening_katago_model_path_
		)
	var config_path_invalid: bool = local_katago_available \
		and not SettingsStore.is_katago_analysis_config_path_valid(
			opening_katago_analysis_config_path_
		)
	updating_options_ = true
	select_language_(opening_language_)
	horizontal_safe_margin_.set_value_no_signal(
		opening_horizontal_safe_margin_
	)
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
	stone_sound_volume_.set_value_no_signal(opening_stone_sound_volume_)
	update_stone_sound_volume_label_()
	move_confirmation_.set_pressed_no_signal(opening_move_confirmation_)
	pptx_image_format_.select(opening_pptx_image_format_)
	pptx_board_coordinates_.set_pressed_no_signal(
		opening_pptx_board_coordinates_
	)
	katago_executable_path_.text = "" if executable_path_invalid \
		else opening_katago_executable_path_
	katago_model_path_.text = "" if model_path_invalid \
		else opening_katago_model_path_
	katago_analysis_config_path_.text = "" if config_path_invalid \
		else opening_katago_analysis_config_path_
	katago_max_visits_.set_value_no_signal(opening_katago_max_visits_)
	katago_report_interval_seconds_.set_value_no_signal(
		opening_katago_report_interval_seconds_
	)
	katago_analysis_pv_length_.set_value_no_signal(
		opening_katago_analysis_pv_length_
	)
	katago_show_score_lead_.set_pressed_no_signal(
		opening_katago_show_score_lead_
	)
	katago_game_analysis_visits_.set_value_no_signal(
		opening_katago_game_analysis_visits_
	)
	updating_options_ = false
	update_custom_move_count_editable_()
	action_bar_.visible = has_staged_changes_()
	error_label_.hide()
	if executable_path_invalid or model_path_invalid or config_path_invalid:
		var invalid_items: PackedStringArray = PackedStringArray()
		if executable_path_invalid:
			invalid_items.append(tr("KataGo 可执行文件"))
		if model_path_invalid:
			invalid_items.append(tr("神经网络模型"))
		if config_path_invalid:
			invalid_items.append(tr("分析配置文件"))
		update_katago_path_status_(
			tr("%s路径已失效，请重新选择") % tr("、").join(invalid_items),
			kStatusErrorColor
		)
	else:
		refresh_katago_path_status_()
	settings_panel_.show()
	close_button_.show()
	call_deferred(&"position_panel_left_buttons_")


func close_panel_() -> void:
	if not opening_language_.is_empty():
		SettingsStore.preview_language(opening_language_)
	cancel_katago_test_()
	cancel_katago_benchmark_()
	pending_katago_benchmark_threads_ = 0
	pending_katago_benchmark_batch_size_ = 0
	katago_benchmark_confirmation_.hide()
	katago_benchmark_save_reminder_.hide()
	katago_benchmark_window_.hide()
	settings_panel_.hide()
	close_button_.hide()
	action_bar_.hide()
	error_label_.hide()


func select_path_(
		option: OptionButton,
		paths: Array[String],
		path: String
) -> void:
	var option_index: int = paths.find(path)
	option.select(maxi(option_index, 0))


func select_language_(locale: String) -> void:
	var option_index: int = kLanguageLocales.find(locale)
	language_option_.select(maxi(option_index, 0))


func selected_language_() -> String:
	var option_index: int = clampi(
		language_option_.selected, 0, kLanguageLocales.size() - 1
	)
	return kLanguageLocales[option_index]


func on_language_selected_(_index: int) -> void:
	if updating_options_:
		return
	SettingsStore.preview_language(selected_language_())
	refresh_localized_options_()
	on_option_selected_(0)


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


func on_katago_max_visits_changed_(_value: float) -> void:
	on_option_selected_(0)


func on_katago_analysis_option_changed_(_value: float) -> void:
	on_option_selected_(0)


func on_katago_boolean_option_changed_(_value: bool) -> void:
	on_option_selected_(0)


func on_katago_path_changed_(_value: String) -> void:
	if updating_options_:
		return
	pending_katago_benchmark_threads_ = 0
	pending_katago_benchmark_batch_size_ = 0
	if not katago_test_process_.is_empty():
		cancel_katago_test_()
	if not katago_benchmark_process_.is_empty():
		cancel_katago_benchmark_()
	refresh_katago_path_status_()
	on_option_selected_(0)


func update_custom_move_count_editable_() -> void:
	custom_move_count_.editable = custom_moves_.button_pressed


func on_option_selected_(_index: int) -> void:
	if updating_options_:
		return
	error_label_.hide()
	action_bar_.visible = has_staged_changes_()


func has_staged_changes_() -> bool:
	return pending_katago_benchmark_threads_ > 0 \
		or selected_language_() != opening_language_ \
		or selected_horizontal_safe_margin_() \
			!= opening_horizontal_safe_margin_ \
		or selected_board_path_() != opening_board_path_ \
		or selected_black_path_() != opening_black_path_ \
		or selected_white_path_() != opening_white_path_ \
		or selected_move_number_mode_() != opening_move_number_mode_ \
		or selected_move_number_count_() != opening_move_number_count_ \
		or selected_absolute_move_numbers_() != opening_absolute_move_numbers_ \
		or selected_stone_sound_volume_() != opening_stone_sound_volume_ \
		or selected_move_confirmation_() != opening_move_confirmation_ \
		or selected_pptx_image_format_() != opening_pptx_image_format_ \
		or selected_pptx_board_coordinates_() \
			!= opening_pptx_board_coordinates_ \
		or selected_katago_executable_path_() \
			!= opening_katago_executable_path_ \
		or selected_katago_model_path_() != opening_katago_model_path_ \
		or selected_katago_analysis_config_path_() \
			!= opening_katago_analysis_config_path_ \
		or selected_katago_max_visits_() != opening_katago_max_visits_ \
		or not is_equal_approx(
			selected_katago_report_interval_seconds_(),
			opening_katago_report_interval_seconds_
		) or selected_katago_analysis_pv_length_() \
			!= opening_katago_analysis_pv_length_ \
		or selected_katago_show_score_lead_() \
			!= opening_katago_show_score_lead_ \
		or selected_katago_game_analysis_visits_() \
			!= opening_katago_game_analysis_visits_ \
		or not is_equal_approx(
			selected_playback_interval_seconds_(),
			opening_playback_interval_seconds_
		)


func selected_board_path_() -> String:
	return kBoardPaths[maxi(board_option_.selected, 0)]


func selected_horizontal_safe_margin_() -> int:
	return clampi(
		roundi(horizontal_safe_margin_.value),
		0,
		SettingsStore.kHorizontalSafeMarginMaximum
	)


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


func selected_stone_sound_volume_() -> int:
	return clampi(
		roundi(stone_sound_volume_.value),
		SettingsStore.kStoneSoundVolumeMinimum,
		SettingsStore.kStoneSoundVolumeMaximum
	)


func selected_move_confirmation_() -> bool:
	return move_confirmation_.button_pressed


func on_stone_sound_volume_changed_(_value: float) -> void:
	update_stone_sound_volume_label_()
	on_option_selected_(0)


func update_stone_sound_volume_label_() -> void:
	stone_sound_volume_value_.text = \
		str(selected_stone_sound_volume_()) + "%"


func selected_pptx_image_format_() -> int:
	return clampi(
		pptx_image_format_.selected,
		SettingsStore.kPptxImageFormatSvg,
		SettingsStore.kPptxImageFormatPng
	)


func selected_pptx_board_coordinates_() -> bool:
	return pptx_board_coordinates_.button_pressed


func selected_katago_executable_path_() -> String:
	return katago_executable_path_.text.strip_edges()


func selected_katago_model_path_() -> String:
	return katago_model_path_.text.strip_edges()


func selected_katago_analysis_config_path_() -> String:
	return katago_analysis_config_path_.text.strip_edges()


func selected_katago_max_visits_() -> int:
	return maxi(roundi(katago_max_visits_.value), 1)


func selected_katago_report_interval_seconds_() -> float:
	return clampf(katago_report_interval_seconds_.value, 0.1, 60.0)


func selected_katago_analysis_pv_length_() -> int:
	return maxi(roundi(katago_analysis_pv_length_.value), 1)


func selected_katago_show_score_lead_() -> bool:
	return katago_show_score_lead_.button_pressed


func selected_katago_game_analysis_visits_() -> int:
	return maxi(roundi(katago_game_analysis_visits_.value), 1)


func on_confirm_pressed_() -> void:
	var katago_validation_error: String = validate_selected_katago_paths_()
	if not katago_validation_error.is_empty():
		error_label_.text = katago_validation_error
		error_label_.show()
		return
	if pending_katago_benchmark_threads_ > 0:
		var write_error: Error = \
			SettingsStore.write_managed_katago_analysis_config(
				pending_katago_benchmark_threads_,
				pending_katago_benchmark_batch_size_
			)
		if write_error != OK:
			error_label_.text = tr("写入性能配置失败：%s") \
				% error_string(write_error)
			error_label_.show()
			return

	var error: Error = SettingsStore.set_settings(
		selected_language_(),
		selected_board_path_(),
		selected_black_path_(),
		selected_white_path_(),
		selected_move_number_mode_(),
		selected_move_number_count_(),
		selected_absolute_move_numbers_(),
		selected_playback_interval_seconds_(),
		selected_stone_sound_volume_(),
		selected_horizontal_safe_margin_(),
		selected_move_confirmation_(),
		selected_pptx_image_format_(),
		selected_pptx_board_coordinates_(),
		selected_katago_executable_path_(),
		selected_katago_model_path_(),
		selected_katago_max_visits_(),
		selected_katago_report_interval_seconds_(),
		selected_katago_analysis_pv_length_(),
		selected_katago_show_score_lead_(),
		selected_katago_game_analysis_visits_(),
		selected_katago_analysis_config_path_()
	)
	if error != OK:
		error_label_.text = tr("保存设置失败：%s") % error_string(error)
		error_label_.show()
		return

	opening_language_ = selected_language_()
	opening_board_path_ = selected_board_path_()
	opening_black_path_ = selected_black_path_()
	opening_white_path_ = selected_white_path_()
	opening_move_number_mode_ = selected_move_number_mode_()
	opening_move_number_count_ = selected_move_number_count_()
	opening_absolute_move_numbers_ = selected_absolute_move_numbers_()
	opening_playback_interval_seconds_ = selected_playback_interval_seconds_()
	opening_stone_sound_volume_ = selected_stone_sound_volume_()
	opening_horizontal_safe_margin_ = selected_horizontal_safe_margin_()
	opening_move_confirmation_ = selected_move_confirmation_()
	opening_pptx_image_format_ = selected_pptx_image_format_()
	opening_pptx_board_coordinates_ = selected_pptx_board_coordinates_()
	opening_katago_executable_path_ = selected_katago_executable_path_()
	opening_katago_model_path_ = selected_katago_model_path_()
	opening_katago_analysis_config_path_ = \
		selected_katago_analysis_config_path_()
	opening_katago_max_visits_ = selected_katago_max_visits_()
	opening_katago_report_interval_seconds_ = \
		selected_katago_report_interval_seconds_()
	opening_katago_analysis_pv_length_ = selected_katago_analysis_pv_length_()
	opening_katago_show_score_lead_ = selected_katago_show_score_lead_()
	opening_katago_game_analysis_visits_ = \
		selected_katago_game_analysis_visits_()
	pending_katago_benchmark_threads_ = 0
	pending_katago_benchmark_batch_size_ = 0
	error_label_.hide()
	action_bar_.hide()
	refresh_katago_path_status_()

func on_restore_pressed_() -> void:
	pending_katago_benchmark_threads_ = 0
	pending_katago_benchmark_batch_size_ = 0
	updating_options_ = true
	select_language_(opening_language_)
	horizontal_safe_margin_.set_value_no_signal(
		opening_horizontal_safe_margin_
	)
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
	stone_sound_volume_.set_value_no_signal(opening_stone_sound_volume_)
	update_stone_sound_volume_label_()
	move_confirmation_.set_pressed_no_signal(opening_move_confirmation_)
	pptx_image_format_.select(opening_pptx_image_format_)
	pptx_board_coordinates_.set_pressed_no_signal(
		opening_pptx_board_coordinates_
	)
	katago_executable_path_.text = opening_katago_executable_path_ \
		if OS.has_feature("mobile") \
			or SettingsStore.is_katago_executable_path_valid(
			opening_katago_executable_path_
		) else ""
	katago_model_path_.text = opening_katago_model_path_ \
		if OS.has_feature("mobile") \
			or SettingsStore.is_katago_model_path_valid(
			opening_katago_model_path_
		) else ""
	katago_analysis_config_path_.text = opening_katago_analysis_config_path_ \
		if OS.has_feature("mobile") \
			or SettingsStore.is_katago_analysis_config_path_valid(
			opening_katago_analysis_config_path_
		) else ""
	katago_max_visits_.set_value_no_signal(opening_katago_max_visits_)
	katago_report_interval_seconds_.set_value_no_signal(
		opening_katago_report_interval_seconds_
	)
	katago_analysis_pv_length_.set_value_no_signal(
		opening_katago_analysis_pv_length_
	)
	katago_show_score_lead_.set_pressed_no_signal(
		opening_katago_show_score_lead_
	)
	katago_game_analysis_visits_.set_value_no_signal(
		opening_katago_game_analysis_visits_
	)
	updating_options_ = false
	SettingsStore.preview_language(opening_language_)
	refresh_localized_options_()
	update_custom_move_count_editable_()
	error_label_.hide()
	action_bar_.visible = has_staged_changes_()
	refresh_katago_path_status_()


func on_cancel_pressed_() -> void:
	close_panel_()


func validate_selected_katago_paths_() -> String:
	if OS.has_feature("mobile"):
		return ""
	var executable_path: String = selected_katago_executable_path_()
	if not executable_path.is_empty() \
			and not SettingsStore.is_katago_executable_path_valid(
				executable_path
			):
		return tr("KataGo 可执行文件路径无效。")
	var model_path: String = selected_katago_model_path_()
	if not model_path.is_empty() \
			and not SettingsStore.is_katago_model_path_valid(model_path):
		return tr("KataGo 神经网络模型路径无效。")
	var config_path: String = selected_katago_analysis_config_path_()
	if not SettingsStore.is_katago_analysis_config_path_valid(config_path):
		return tr("KataGo 分析配置文件路径无效。")
	return ""


func validate_selected_katago_engine_paths_() -> String:
	if not SettingsStore.is_katago_executable_path_valid(
			selected_katago_executable_path_()
		):
		return tr("KataGo 可执行文件路径无效。")
	if not SettingsStore.is_katago_model_path_valid(
			selected_katago_model_path_()
		):
		return tr("KataGo 神经网络模型路径无效。")
	return ""


func refresh_katago_path_status_() -> void:
	if OS.get_name() == "Android":
		katago_test_button_.disabled = true
		katago_benchmark_button_.disabled = \
			is_katago_benchmark_running_()
		update_katago_path_status_(
			tr("使用 Android 内置 KataGo 引擎"), kStatusValidColor
		)
		return
	var executable_path: String = selected_katago_executable_path_()
	var model_path: String = selected_katago_model_path_()
	var config_path: String = selected_katago_analysis_config_path_()
	var executable_valid: bool = \
		SettingsStore.is_katago_executable_path_valid(executable_path)
	var model_valid: bool = SettingsStore.is_katago_model_path_valid(model_path)
	var config_valid: bool = \
		SettingsStore.is_katago_analysis_config_path_valid(config_path)
	var process_running: bool = not katago_test_process_.is_empty() \
		or not katago_benchmark_process_.is_empty()
	katago_test_button_.disabled = process_running
	katago_benchmark_button_.disabled = process_running
	if executable_path.is_empty() and model_path.is_empty():
		update_katago_path_status_(tr("尚未配置"), kStatusNeutralColor)
	elif not executable_path.is_empty() and not executable_valid:
		update_katago_path_status_(
			tr("KataGo 可执行文件路径无效"), kStatusErrorColor
		)
	elif not model_path.is_empty() and not model_valid:
		update_katago_path_status_(
			tr("神经网络模型路径无效"), kStatusErrorColor
		)
	elif not executable_valid:
		update_katago_path_status_(
			tr("请选择 KataGo 可执行文件"), kStatusNeutralColor
		)
	elif not model_valid:
		update_katago_path_status_(
			tr("请选择神经网络模型"), kStatusNeutralColor
		)
	elif not config_valid:
		update_katago_path_status_(
			tr("请选择有效的KataGo分析配置文件"), kStatusNeutralColor
		)
	else:
		update_katago_path_status_(tr("配置有效，可以测试"), kStatusValidColor)


func update_katago_path_status_(message: String, color: Color) -> void:
	katago_status_.text = message
	katago_status_.add_theme_color_override(&"font_color", color)


func on_katago_executable_browse_pressed_() -> void:
	if focus_active_katago_file_dialog_():
		return
	set_dialog_current_path_(
		katago_executable_dialog_, selected_katago_executable_path_()
	)
	active_katago_file_dialog_ = katago_executable_dialog_
	katago_executable_dialog_.popup_centered_ratio(0.8)


func on_katago_model_browse_pressed_() -> void:
	if focus_active_katago_file_dialog_():
		return
	set_dialog_current_path_(
		katago_model_dialog_, selected_katago_model_path_()
	)
	active_katago_file_dialog_ = katago_model_dialog_
	katago_model_dialog_.popup_centered_ratio(0.8)


func on_katago_config_browse_pressed_() -> void:
	if focus_active_katago_file_dialog_():
		return
	set_dialog_current_path_(
		katago_config_dialog_, selected_katago_analysis_config_path_()
	)
	active_katago_file_dialog_ = katago_config_dialog_
	katago_config_dialog_.popup_centered_ratio(0.8)


func focus_active_katago_file_dialog_() -> bool:
	if active_katago_file_dialog_ != null:
		active_katago_file_dialog_.grab_focus()
		return true
	var dialogs: Array[FileDialog] = [
		katago_executable_dialog_,
		katago_model_dialog_,
		katago_config_dialog_
	]
	for dialog: FileDialog in dialogs:
		if dialog.visible:
			active_katago_file_dialog_ = dialog
			dialog.grab_focus()
			return true
	return false


func on_katago_file_dialog_canceled_() -> void:
	active_katago_file_dialog_ = null


func set_dialog_current_path_(dialog: FileDialog, path: String) -> void:
	if path.is_empty():
		return
	if FileAccess.file_exists(path):
		dialog.current_path = path


func on_katago_executable_selected_(path: String) -> void:
	active_katago_file_dialog_ = null
	katago_executable_path_.text = path
	refresh_katago_path_status_()
	on_option_selected_(0)


func on_katago_model_selected_(path: String) -> void:
	active_katago_file_dialog_ = null
	katago_model_path_.text = path
	refresh_katago_path_status_()
	on_option_selected_(0)


func on_katago_config_selected_(path: String) -> void:
	active_katago_file_dialog_ = null
	katago_analysis_config_path_.text = path
	refresh_katago_path_status_()
	on_option_selected_(0)


func on_katago_test_pressed_() -> void:
	if not katago_test_process_.is_empty():
		return
	var validation_error: String = validate_selected_katago_engine_paths_()
	if not validation_error.is_empty():
		update_katago_path_status_(validation_error, kStatusErrorColor)
		return
	if not SettingsStore.is_katago_executable_path_valid(
			selected_katago_executable_path_()
		) or not SettingsStore.is_katago_model_path_valid(
			selected_katago_model_path_()
		):
		update_katago_path_status_(
			tr("请先完整配置有效路径"), kStatusErrorColor
		)
		return

	var process: Dictionary = OS.execute_with_pipe(
		selected_katago_executable_path_(),
		PackedStringArray(["version"]),
		false
	)
	if process.is_empty():
		update_katago_path_status_(
			tr("无法启动 KataGo"), kStatusErrorColor
		)
		return
	katago_test_process_ = process
	katago_test_output_ = ""
	katago_test_started_msec_ = Time.get_ticks_msec()
	set_katago_controls_enabled_(false)
	update_katago_path_status_(tr("正在检测 KataGo…"), kStatusNeutralColor)
	set_process(true)


func _process(_delta: float) -> void:
	if not katago_benchmark_process_.is_empty():
		process_katago_benchmark_()
		return
	if katago_test_process_.is_empty():
		set_process(false)
		return
	read_katago_test_output_()
	var pid: int = int(katago_test_process_.get("pid", -1))
	if pid > 0 and OS.is_process_running(pid):
		if Time.get_ticks_msec() - katago_test_started_msec_ \
				>= kKatagoTestTimeoutMsec:
			var _kill_error: Error = OS.kill(pid)
			finish_katago_test_(false, tr("KataGo 检测超时"))
		return

	read_katago_test_output_()
	var version_line: String = find_katago_version_line_(katago_test_output_)
	if version_line.is_empty():
		finish_katago_test_(false, tr("该文件不是可识别的 KataGo 程序"))
	else:
		finish_katago_test_(true, tr("已检测：%s") % version_line)


func read_katago_test_output_() -> void:
	append_katago_pipe_output_("stdio")
	append_katago_pipe_output_("stderr")


func append_katago_pipe_output_(key: String) -> void:
	var pipe_value: Variant = katago_test_process_.get(key)
	var pipe: FileAccess = pipe_value as FileAccess
	if pipe == null:
		return
	var available_bytes: int = pipe.get_length()
	if available_bytes <= 0:
		return
	var bytes: PackedByteArray = pipe.get_buffer(available_bytes)
	katago_test_output_ += bytes.get_string_from_utf8()


func find_katago_version_line_(output: String) -> String:
	for line: String in output.split("\n", false):
		var trimmed_line: String = line.strip_edges()
		if trimmed_line.begins_with("KataGo v"):
			return trimmed_line
	return ""


func finish_katago_test_(succeeded: bool, message: String) -> void:
	close_katago_test_pipes_()
	katago_test_process_.clear()
	katago_test_started_msec_ = 0
	set_process(false)
	set_katago_controls_enabled_(true)
	update_katago_path_status_(
		message,
		kStatusValidColor if succeeded else kStatusErrorColor
	)


func cancel_katago_test_() -> void:
	if katago_test_process_.is_empty():
		return
	var pid: int = int(katago_test_process_.get("pid", -1))
	if pid > 0 and OS.is_process_running(pid):
		var _kill_error: Error = OS.kill(pid)
	close_katago_test_pipes_()
	katago_test_process_.clear()
	katago_test_output_ = ""
	katago_test_started_msec_ = 0
	set_process(false)
	set_katago_controls_enabled_(true)


func on_katago_benchmark_pressed_() -> void:
	if is_katago_benchmark_running_():
		return
	if OS.get_name() != "Android":
		var validation_error: String = validate_selected_katago_engine_paths_()
		if validation_error.is_empty() and not \
				SettingsStore.is_katago_analysis_config_path_valid(
					selected_katago_analysis_config_path_()
				):
			validation_error = tr("KataGo 分析配置文件路径无效。")
		if not validation_error.is_empty():
			update_katago_path_status_(validation_error, kStatusErrorColor)
			return
	katago_benchmark_confirmation_.dialog_text = tr(
		"DIALOG_BENCHMARK_CONFIRMATION_MESSAGE"
	)
	katago_benchmark_confirmation_.popup_centered()


func start_katago_benchmark_() -> void:
	pending_katago_benchmark_threads_ = 0
	pending_katago_benchmark_batch_size_ = 0
	on_option_selected_(0)
	katago_benchmark_output_ = ""
	katago_benchmark_output_edit_.text = tr("正在启动 KataGo benchmark…")
	set_katago_benchmark_window_state_(kBenchmarkStateRunning)
	# 清除上一次打开时保留的尺寸，再由 Godot 根据父视图的实际可用尺寸计算弹窗大小。
	# 这可以避免最大化窗口和高分屏内容缩放造成物理像素与逻辑尺寸混用。
	katago_benchmark_window_.reset_size()
	katago_benchmark_window_.popup_centered_ratio(0.8)
	set_katago_controls_enabled_(false)
	update_katago_path_status_(
		tr("正在自动检测性能…"), kStatusNeutralColor
	)
	if OS.get_name() == "Android":
		start_embedded_katago_benchmark_()
		return
	var arguments: PackedStringArray = PackedStringArray([
		"benchmark",
		"-model", selected_katago_model_path_(),
		"-config", selected_katago_analysis_config_path_(),
		"-override-config", "numSearchThreads=6",
		"-v", str(kKatagoBenchmarkVisits),
		"-t", kKatagoBenchmarkThreads,
		"-n", "1",
		"-boardsize", "19",
		"-half-batch-size",
		"-i", str(kKatagoBenchmarkSecondsPerMove)
	])
	var process: Dictionary = OS.execute_with_pipe(
		selected_katago_executable_path_(), arguments, false
	)
	if process.is_empty():
		update_katago_path_status_(
			tr("无法启动KataGo性能检测"), kStatusErrorColor
		)
		katago_benchmark_output_edit_.text = tr("无法启动 KataGo benchmark。")
		set_katago_benchmark_window_state_(kBenchmarkStateFailed)
		set_katago_controls_enabled_(true)
		return
	katago_benchmark_process_ = process
	set_process(true)


func start_embedded_katago_benchmark_() -> void:
	katago_embedded_benchmark_ = KataGoEmbeddedBenchmark.new()
	add_child(katago_embedded_benchmark_)
	katago_embedded_benchmark_.output_changed.connect(
		on_embedded_katago_benchmark_output_changed_
	)
	katago_embedded_benchmark_.completed.connect(
		on_embedded_katago_benchmark_completed_
	)
	if not katago_embedded_benchmark_.start_benchmark():
		katago_embedded_benchmark_ = null


func on_embedded_katago_benchmark_output_changed_(output: String) -> void:
	katago_benchmark_output_ = output
	katago_benchmark_output_edit_.text = output
	katago_benchmark_output_edit_.scroll_vertical = \
		katago_benchmark_output_edit_.get_line_count()


func on_embedded_katago_benchmark_completed_(
		succeeded: bool,
		search_threads: int,
		batch_size: int,
		message: String
) -> void:
	katago_embedded_benchmark_ = null
	set_katago_controls_enabled_(true)
	if not succeeded:
		var effective_message: String = message if not message.is_empty() \
			else tr("性能检测没有取得有效结果。")
		update_katago_path_status_(effective_message, kStatusErrorColor)
		set_katago_benchmark_window_state_(kBenchmarkStateFailed)
		return
	apply_katago_benchmark_result_(search_threads, batch_size)


func process_katago_benchmark_() -> void:
	read_katago_benchmark_output_()
	var pid: int = int(katago_benchmark_process_.get("pid", -1))
	if pid > 0 and OS.is_process_running(pid):
		return
	read_katago_benchmark_output_()
	finish_katago_benchmark_()


func read_katago_benchmark_output_() -> void:
	for key: String in ["stdio", "stderr"]:
		var pipe_value: Variant = katago_benchmark_process_.get(key)
		var pipe: FileAccess = pipe_value as FileAccess
		if pipe == null:
			continue
		var available_bytes: int = pipe.get_length()
		if available_bytes <= 0:
			continue
		var bytes: PackedByteArray = pipe.get_buffer(available_bytes)
		katago_benchmark_output_ += bytes.get_string_from_utf8()
		katago_benchmark_output_edit_.text = katago_benchmark_output_
		katago_benchmark_output_edit_.scroll_vertical = \
			katago_benchmark_output_edit_.get_line_count()


func finish_katago_benchmark_() -> void:
	var best_threads: int = find_best_katago_benchmark_threads_(
		katago_benchmark_output_
	)
	close_katago_benchmark_pipes_()
	katago_benchmark_process_.clear()
	set_process(false)
	set_katago_controls_enabled_(true)
	if best_threads <= 0:
		update_katago_path_status_(
			tr("性能检测没有取得有效结果"),
			kStatusErrorColor
		)
		if katago_benchmark_output_.is_empty():
			katago_benchmark_output_edit_.text = tr("性能检测没有取得有效结果。")
		set_katago_benchmark_window_state_(kBenchmarkStateFailed)
		return
	var batch_size: int = maxi(8, ceili(float(best_threads) / 2.0))
	apply_katago_benchmark_result_(best_threads, batch_size)


func apply_katago_benchmark_result_(best_threads: int, batch_size: int) -> void:
	katago_analysis_config_path_.text = \
		SettingsStore.get_managed_katago_analysis_config_path()
	pending_katago_benchmark_threads_ = best_threads
	pending_katago_benchmark_batch_size_ = batch_size
	on_option_selected_(0)
	update_katago_path_status_(
		tr("检测完成：%d线程，批量%d；请确认保存") \
			% [best_threads, batch_size],
		kStatusValidColor
	)
	set_katago_benchmark_window_state_(kBenchmarkStateSucceeded)


func find_best_katago_benchmark_threads_(output: String) -> int:
	var recommended_regex: RegEx = RegEx.new()
	var compile_error: Error = recommended_regex.compile(
		"numSearchThreads\\s*=\\s*(\\d+)\\s*:.*\\(recommended\\)"
	)
	if compile_error == OK:
		var recommendations: Array[RegExMatch] = \
			recommended_regex.search_all(output)
		if not recommendations.is_empty():
			return int(recommendations[-1].get_string(1))
	return find_best_threads_from_partial_benchmark_(output)


func find_best_threads_from_partial_benchmark_(output: String) -> int:
	var result_regex: RegEx = RegEx.new()
	var compile_error: Error = result_regex.compile(
		"numSearchThreads\\s*=\\s*(\\d+)\\s*:.*visits/s\\s*=\\s*([0-9.]+)"
	)
	if compile_error != OK:
		return 0
	var visits_per_second_by_threads: Dictionary = {}
	for result: RegExMatch in result_regex.search_all(output):
		var thread_count: int = int(result.get_string(1))
		var visits_per_second: float = float(result.get_string(2))
		if visits_per_second > 0.0:
			visits_per_second_by_threads[thread_count] = visits_per_second
	var best_threads: int = 0
	var best_score: float = -INF
	for thread_key: Variant in visits_per_second_by_threads:
		var thread_count: int = int(thread_key)
		var visits_per_second: float = float(
			visits_per_second_by_threads[thread_key]
		)
		var visits_per_move: float = \
			visits_per_second * kKatagoBenchmarkSecondsPerMove
		var thread_cost: float = float(thread_count) * 7.0 * pow(
			1600.0 / (800.0 + visits_per_move), 0.85
		)
		var score: float = 250.0 * log(visits_per_second) / log(2.0) \
			- thread_cost
		if score > best_score:
			best_score = score
			best_threads = thread_count
	return best_threads


func set_katago_benchmark_window_state_(state: int) -> void:
	katago_benchmark_state_ = state
	match katago_benchmark_state_:
		kBenchmarkStateRunning:
			katago_benchmark_action_button_.text = tr("停止")
			katago_benchmark_action_button_.tooltip_text = tr("停止性能检测")
		kBenchmarkStateSucceeded:
			katago_benchmark_action_button_.text = tr("确认")
			katago_benchmark_action_button_.tooltip_text = tr("确认检测结果")
		kBenchmarkStateFailed:
			katago_benchmark_action_button_.text = tr("关闭")
			katago_benchmark_action_button_.tooltip_text = tr("关闭性能检测窗口")
		_:
			katago_benchmark_action_button_.text = tr("关闭")
			katago_benchmark_action_button_.tooltip_text = tr("关闭性能检测窗口")


func on_katago_benchmark_action_pressed_() -> void:
	match katago_benchmark_state_:
		kBenchmarkStateRunning:
			cancel_katago_benchmark_(true)
			close_katago_benchmark_window_()
		kBenchmarkStateSucceeded:
			katago_benchmark_save_reminder_.popup_centered(Vector2i(500, 190))
		_:
			close_katago_benchmark_window_()


func on_katago_benchmark_window_close_requested_() -> void:
	on_katago_benchmark_action_pressed_()


func close_katago_benchmark_window_() -> void:
	katago_benchmark_save_reminder_.hide()
	katago_benchmark_window_.hide()
	katago_benchmark_state_ = kBenchmarkStateIdle


func cancel_katago_benchmark_(show_canceled_status: bool = false) -> void:
	if katago_embedded_benchmark_ != null:
		var benchmark: KataGoEmbeddedBenchmark = katago_embedded_benchmark_
		katago_embedded_benchmark_ = null
		benchmark.cancel_benchmark()
		set_katago_controls_enabled_(true)
		if show_canceled_status:
			update_katago_path_status_(tr("已取消性能测试"), kStatusCanceledColor)
		return
	if katago_benchmark_process_.is_empty():
		return
	read_katago_benchmark_output_()
	var pid: int = int(katago_benchmark_process_.get("pid", -1))
	if pid > 0 and OS.is_process_running(pid):
		var _kill_error: Error = OS.kill(pid)
	close_katago_benchmark_pipes_()
	katago_benchmark_process_.clear()
	set_process(false)
	set_katago_controls_enabled_(true)
	if show_canceled_status:
		update_katago_path_status_(tr("已取消性能测试"), kStatusCanceledColor)


func close_katago_benchmark_pipes_() -> void:
	for key: String in ["stdio", "stderr"]:
		var pipe_value: Variant = katago_benchmark_process_.get(key)
		var pipe: FileAccess = pipe_value as FileAccess
		if pipe != null:
			pipe.close()


func close_katago_test_pipes_() -> void:
	for key: String in ["stdio", "stderr"]:
		var pipe_value: Variant = katago_test_process_.get(key)
		var pipe: FileAccess = pipe_value as FileAccess
		if pipe != null:
			pipe.close()


func set_katago_controls_enabled_(enabled: bool) -> void:
	settings_button_.disabled = not enabled
	language_option_.disabled = not enabled
	horizontal_safe_margin_.editable = enabled
	board_option_.disabled = not enabled
	stone_option_.disabled = not enabled
	one_move_.disabled = not enabled
	ten_moves_.disabled = not enabled
	all_moves_.disabled = not enabled
	custom_moves_.disabled = not enabled
	custom_move_count_.editable = enabled and custom_moves_.button_pressed
	absolute_move_numbers_.disabled = not enabled
	playback_interval_seconds_.editable = enabled
	stone_sound_volume_.editable = enabled
	move_confirmation_.disabled = not enabled
	pptx_image_format_.disabled = not enabled
	pptx_board_coordinates_.disabled = not enabled
	var desktop_paths_enabled: bool = enabled and not OS.has_feature("mobile")
	katago_executable_path_.editable = desktop_paths_enabled
	katago_model_path_.editable = desktop_paths_enabled
	katago_analysis_config_path_.editable = desktop_paths_enabled
	katago_executable_browse_.disabled = not desktop_paths_enabled
	katago_model_browse_.disabled = not desktop_paths_enabled
	katago_analysis_config_browse_.disabled = not desktop_paths_enabled
	katago_max_visits_.editable = enabled
	katago_report_interval_seconds_.editable = enabled
	katago_analysis_pv_length_.editable = enabled
	katago_show_score_lead_.disabled = not enabled
	katago_game_analysis_visits_.editable = enabled
	katago_test_button_.disabled = not desktop_paths_enabled
	katago_benchmark_button_.disabled = not enabled
	close_button_.disabled = not enabled
	confirm_button_.disabled = not enabled
	restore_button_.disabled = not enabled
	cancel_button_.disabled = not enabled
	action_bar_.visible = enabled and has_staged_changes_()


func is_katago_benchmark_running_() -> bool:
	return katago_embedded_benchmark_ != null \
		or not katago_benchmark_process_.is_empty()


func _exit_tree() -> void:
	cancel_katago_test_()
	cancel_katago_benchmark_()
