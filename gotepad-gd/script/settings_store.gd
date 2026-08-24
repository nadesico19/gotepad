extends Node

signal textures_changed
signal move_numbers_changed
signal playback_interval_changed
signal move_confirmation_changed(enabled: bool)
signal katago_paths_changed
signal katago_human_paths_changed
signal katago_analysis_settings_changed
signal language_changed(locale: String)
signal horizontal_safe_margin_changed(margin: int)
signal board_width_percentage_changed(percentage: int)
signal large_ui_changed(enabled: bool, multiplier: float)

const kConfigPath: String = "user://settings.cfg"
const kWindowStatePath: String = "user://window_state.cfg"
const kSchemaVersion: int = 26
const kLanguageSimplifiedChinese: String = "zh_CN"
const kLanguageJapanese: String = "ja"
const kLanguageKorean: String = "ko"
const kLanguageEnglish: String = "en"
const kDefaultLanguage: String = kLanguageSimplifiedChinese
const kSupportedLanguages: Array[String] = [
	kLanguageSimplifiedChinese,
	kLanguageJapanese,
	kLanguageKorean,
	kLanguageEnglish,
]
const kMoveNumberModeOne: int = 0
const kMoveNumberModeTen: int = 1
const kMoveNumberModeAll: int = 2
const kMoveNumberModeCustom: int = 3
const kDefaultMoveNumberMode: int = kMoveNumberModeOne
const kDefaultMoveNumberCount: int = 20
const kDefaultAbsoluteMoveNumbers: bool = false
const kDefaultPlaybackIntervalSeconds: float = 1.0
const kStoneSoundVolumeMinimum: int = 0
const kStoneSoundVolumeMaximum: int = 100
const kDefaultStoneSoundVolume: int = 50
const kDefaultHorizontalSafeMargin: int = 0
const kHorizontalSafeMarginMaximum: int = 512
const kBoardWidthPercentageMinimum: int = 50
const kBoardWidthPercentageMaximum: int = 100
const kDefaultBoardWidthPercentage: int = 100
const kDefaultLargeUiEnabled: bool = false
const kLargeUiMultiplierMinimum: float = 0.7
const kLargeUiMultiplierMaximum: float = 2.0
const kDefaultLargeUiMultiplier: float = 1.5
const kDefaultDesktopMoveConfirmation: bool = false
const kDefaultMobileMoveConfirmation: bool = true
const kPptxImageFormatSvg: int = 0
const kPptxImageFormatPng: int = 1
const kDefaultPptxImageFormat: int = kPptxImageFormatSvg
const kDefaultPptxBoardCoordinates: bool = false
const kDefaultKatagoExecutablePath: String = ""
const kDefaultKatagoModelPath: String = ""
const kDefaultKatagoHumanModelPath: String = ""
const kDefaultKatagoMaxVisits: int = 500
const kDefaultKatagoHumanMaxVisits: int = 500
const kDefaultKatagoReportIntervalSeconds: float = 2.0
const kDefaultKatagoAnalysisPvLength: int = 10
const kDefaultKatagoShowScoreLead: bool = true
const kDefaultKatagoGameAnalysisVisits: int = 1
const kManagedKatagoConfigPath: String = \
	"user://katago/analysis.cfg"
const kManagedKatagoHumanConfigPath: String = \
	"user://katago/human_analysis.cfg"
const kDefaultBoardTexturePath: String = \
	"res://assets/board/wood_light.jpg"
const kDefaultBlackTexturePath: String = \
	"res://assets/stones/black.png"
const kDefaultWhiteTexturePath: String = \
	"res://assets/stones/white.png"

const kDefaultBoardTexture: Texture2D = preload(
	"res://assets/board/wood_light.jpg"
)
const kDefaultBlackTexture: Texture2D = preload(
	"res://assets/stones/black.png"
)
const kDefaultWhiteTexture: Texture2D = preload(
	"res://assets/stones/white.png"
)

var board_texture_path_: String = kDefaultBoardTexturePath
var black_texture_path_: String = kDefaultBlackTexturePath
var white_texture_path_: String = kDefaultWhiteTexturePath
var board_texture_: Texture2D = kDefaultBoardTexture
var black_texture_: Texture2D = kDefaultBlackTexture
var white_texture_: Texture2D = kDefaultWhiteTexture
var language_: String = kDefaultLanguage
var move_number_mode_: int = kDefaultMoveNumberMode
var move_number_count_: int = kDefaultMoveNumberCount
var absolute_move_numbers_: bool = kDefaultAbsoluteMoveNumbers
var playback_interval_seconds_: float = kDefaultPlaybackIntervalSeconds
var stone_sound_volume_: int = kDefaultStoneSoundVolume
var horizontal_safe_margin_: int = kDefaultHorizontalSafeMargin
var board_width_percentage_: int = kDefaultBoardWidthPercentage
var large_ui_enabled_: bool = kDefaultLargeUiEnabled
var large_ui_multiplier_: float = kDefaultLargeUiMultiplier
var move_confirmation_enabled_: bool = kDefaultMobileMoveConfirmation \
	if OS.has_feature("mobile") else kDefaultDesktopMoveConfirmation
var pptx_image_format_: int = kDefaultPptxImageFormat
var pptx_board_coordinates_: bool = kDefaultPptxBoardCoordinates
var katago_executable_path_: String = kDefaultKatagoExecutablePath
var katago_model_path_: String = kDefaultKatagoModelPath
var katago_human_model_path_: String = kDefaultKatagoHumanModelPath
var katago_max_visits_: int = kDefaultKatagoMaxVisits
var katago_human_max_visits_: int = kDefaultKatagoHumanMaxVisits
var katago_report_interval_seconds_: float = \
	kDefaultKatagoReportIntervalSeconds
var katago_analysis_pv_length_: int = kDefaultKatagoAnalysisPvLength
var katago_show_score_lead_: bool = kDefaultKatagoShowScoreLead
var katago_game_analysis_visits_: int = kDefaultKatagoGameAnalysisVisits
var katago_analysis_config_path_: String = ""
var saved_window_state_available_: bool = false
var saved_window_position_: Vector2i = Vector2i.ZERO
var saved_window_size_: Vector2i = Vector2i(1600, 900)
var saved_window_maximized_: bool = false


func _ready() -> void:
	load_config_()
	apply_runtime_language_(language_)
	load_window_state_()
	ensure_managed_katago_analysis_config_()
	ensure_managed_katago_human_analysis_config_()
	load_textures_()


func get_board_texture() -> Texture2D:
	return board_texture_


func get_black_stone_texture() -> Texture2D:
	return black_texture_


func get_white_stone_texture() -> Texture2D:
	return white_texture_


func get_language() -> String:
	return language_


func is_supported_language(locale: String) -> bool:
	return kSupportedLanguages.has(locale)


func preview_language(locale: String) -> bool:
	if not is_supported_language(locale):
		return false
	apply_runtime_language_(locale)
	return true


func restore_saved_language() -> void:
	apply_runtime_language_(language_)


func get_board_texture_path() -> String:
	return board_texture_path_


func get_black_stone_texture_path() -> String:
	return black_texture_path_


func get_white_stone_texture_path() -> String:
	return white_texture_path_


func get_move_number_mode() -> int:
	return move_number_mode_


func get_move_number_count() -> int:
	return move_number_count_


func get_absolute_move_numbers() -> bool:
	return absolute_move_numbers_

func get_playback_interval_seconds() -> float:
	return playback_interval_seconds_


func get_stone_sound_volume() -> int:
	return stone_sound_volume_


func get_horizontal_safe_margin() -> int:
	return horizontal_safe_margin_


func get_board_width_percentage() -> int:
	return board_width_percentage_


func get_large_ui_enabled() -> bool:
	return large_ui_enabled_


func get_large_ui_multiplier() -> float:
	return large_ui_multiplier_


func get_move_confirmation_enabled() -> bool:
	return move_confirmation_enabled_


func get_pptx_image_format() -> int:
	return pptx_image_format_


func get_pptx_image_format_name() -> String:
	return "png" if pptx_image_format_ == kPptxImageFormatPng else "svg"


func get_pptx_board_coordinates() -> bool:
	return pptx_board_coordinates_


func get_katago_executable_path() -> String:
	return katago_executable_path_


func get_katago_model_path() -> String:
	return katago_model_path_


func get_katago_human_model_path() -> String:
	return katago_human_model_path_


func get_android_external_katago_model_path() -> String:
	if OS.get_name() != "Android" \
			or not is_katago_model_path_valid(katago_model_path_):
		return ""
	return katago_model_path_


func get_android_external_katago_human_model_path() -> String:
	if OS.get_name() != "Android" \
			or not is_katago_model_path_valid(katago_human_model_path_):
		return ""
	return katago_human_model_path_


func get_katago_max_visits() -> int:
	return katago_max_visits_


func get_katago_human_max_visits() -> int:
	return katago_human_max_visits_


func get_katago_report_interval_seconds() -> float:
	return katago_report_interval_seconds_


func get_katago_analysis_pv_length() -> int:
	return katago_analysis_pv_length_


func get_katago_show_score_lead() -> bool:
	return katago_show_score_lead_


func get_katago_game_analysis_visits() -> int:
	return katago_game_analysis_visits_


func get_katago_analysis_config_path() -> String:
	if OS.get_name() == "Android":
		return get_managed_katago_analysis_config_path()
	return katago_analysis_config_path_


func get_managed_katago_analysis_config_path() -> String:
	return ProjectSettings.globalize_path(kManagedKatagoConfigPath)


func get_managed_katago_human_analysis_config_path() -> String:
	return ProjectSettings.globalize_path(kManagedKatagoHumanConfigPath)


func get_saved_window_state() -> Dictionary:
	if not saved_window_state_available_:
		return {}
	return {
		"position": saved_window_position_,
		"size": saved_window_size_,
		"maximized": saved_window_maximized_,
	}


func save_window_state(
	position: Vector2i,
	size: Vector2i,
	maximized: bool
) -> Error:
	if size.x <= 0 or size.y <= 0:
		return ERR_INVALID_PARAMETER
	saved_window_position_ = position
	saved_window_size_ = size
	saved_window_maximized_ = maximized
	saved_window_state_available_ = true
	var config: ConfigFile = ConfigFile.new()
	config.set_value("window", "position", saved_window_position_)
	config.set_value("window", "size", saved_window_size_)
	config.set_value("window", "maximized", saved_window_maximized_)
	return config.save(kWindowStatePath)


func has_valid_katago_paths() -> bool:
	return is_katago_executable_path_valid(katago_executable_path_) \
		and is_katago_model_path_valid(katago_model_path_) \
		and is_katago_analysis_config_path_valid(katago_analysis_config_path_)


func has_valid_katago_human_paths() -> bool:
	if not is_katago_model_path_valid(katago_human_model_path_) \
			or not is_katago_analysis_config_path_valid(
				get_managed_katago_human_analysis_config_path()
			):
		return false
	if OS.get_name() == "Android":
		return true
	return is_katago_executable_path_valid(katago_executable_path_) \
		and is_katago_model_path_valid(katago_model_path_)


func is_katago_executable_path_valid(path: String) -> bool:
	var candidate: String = path.strip_edges()
	if candidate.is_empty() or not FileAccess.file_exists(candidate):
		return false
	if OS.get_name() == "Windows" \
			and candidate.get_extension().to_lower() != "exe":
		return false
	return true


func is_katago_model_path_valid(path: String) -> bool:
	var candidate: String = path.strip_edges()
	return not candidate.is_empty() \
		and (
			candidate.to_lower().ends_with(".bin.gz")
			or candidate.to_lower().ends_with(".txt.gz")
		) \
		and FileAccess.file_exists(candidate)


func is_katago_analysis_config_path_valid(path: String) -> bool:
	var candidate: String = path.strip_edges()
	return not candidate.is_empty() \
		and candidate.get_extension().to_lower() == "cfg" \
		and FileAccess.file_exists(candidate)


func write_managed_katago_analysis_config(
		search_threads: int,
		batch_size: int
) -> Error:
	var directory_error: Error = DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path("user://katago")
	)
	if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
		return directory_error
	var file: FileAccess = FileAccess.open(
		kManagedKatagoConfigPath, FileAccess.WRITE
	)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(build_managed_katago_config_(search_threads, batch_size))
	file.close()
	return OK


func write_managed_katago_human_analysis_config(
		search_threads: int,
		batch_size: int
) -> Error:
	var directory_error: Error = DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path("user://katago")
	)
	if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
		return directory_error
	var file: FileAccess = FileAccess.open(
		kManagedKatagoHumanConfigPath, FileAccess.WRITE
	)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(build_managed_katago_human_config_(
		search_threads, batch_size
	))
	file.close()
	katago_human_paths_changed.emit()
	return OK


func set_settings(
		language: String,
		board_path: String,
		black_path: String,
		white_path: String,
		move_number_mode: int,
		move_number_count: int,
		absolute_move_numbers: bool,
		playback_interval_seconds: float,
		stone_sound_volume: int,
		horizontal_safe_margin: int,
		board_width_percentage: int,
		large_ui_enabled: bool,
		large_ui_multiplier: float,
		move_confirmation_enabled: bool,
		pptx_image_format: int,
		pptx_board_coordinates: bool,
		katago_executable_path: String,
		katago_model_path: String,
		katago_max_visits: int,
		katago_report_interval_seconds: float,
		katago_analysis_pv_length: int,
		katago_show_score_lead: bool,
		katago_game_analysis_visits: int,
		katago_analysis_config_path: String,
		katago_human_model_path: String,
		katago_human_max_visits: int
) -> Error:
	if not is_finite(large_ui_multiplier) \
			or large_ui_multiplier < kLargeUiMultiplierMinimum \
			or large_ui_multiplier > kLargeUiMultiplierMaximum:
		return ERR_INVALID_PARAMETER
	var previous_language: String = language_
	var previous_board_path: String = board_texture_path_
	var previous_black_path: String = black_texture_path_
	var previous_white_path: String = white_texture_path_
	var previous_move_number_mode: int = move_number_mode_
	var previous_move_number_count: int = move_number_count_
	var previous_absolute_move_numbers: bool = absolute_move_numbers_
	var previous_playback_interval: float = playback_interval_seconds_
	var previous_stone_sound_volume: int = stone_sound_volume_
	var previous_horizontal_safe_margin: int = horizontal_safe_margin_
	var previous_board_width_percentage: int = board_width_percentage_
	var previous_large_ui_enabled: bool = large_ui_enabled_
	var previous_large_ui_multiplier: float = large_ui_multiplier_
	var previous_move_confirmation_enabled: bool = move_confirmation_enabled_
	var previous_pptx_image_format: int = pptx_image_format_
	var previous_pptx_board_coordinates: bool = pptx_board_coordinates_
	var previous_katago_executable_path: String = katago_executable_path_
	var previous_katago_model_path: String = katago_model_path_
	var previous_katago_human_model_path: String = katago_human_model_path_
	var previous_katago_max_visits: int = katago_max_visits_
	var previous_katago_human_max_visits: int = katago_human_max_visits_
	var previous_katago_report_interval: float = \
		katago_report_interval_seconds_
	var previous_katago_analysis_pv_length: int = \
		katago_analysis_pv_length_
	var previous_katago_show_score_lead: bool = katago_show_score_lead_
	var previous_katago_game_analysis_visits: int = \
		katago_game_analysis_visits_
	var previous_katago_analysis_config_path: String = \
		katago_analysis_config_path_
	language_ = language if is_supported_language(language) else kDefaultLanguage
	board_texture_path_ = board_path
	black_texture_path_ = black_path
	white_texture_path_ = white_path
	move_number_mode_ = clampi(
		move_number_mode, kMoveNumberModeOne, kMoveNumberModeCustom
	)
	move_number_count_ = maxi(move_number_count, 1)
	absolute_move_numbers_ = absolute_move_numbers
	playback_interval_seconds_ = clampf(playback_interval_seconds, 0.1, 60.0)
	stone_sound_volume_ = clampi(
		stone_sound_volume,
		kStoneSoundVolumeMinimum,
		kStoneSoundVolumeMaximum
	)
	horizontal_safe_margin_ = clampi(
		horizontal_safe_margin, 0, kHorizontalSafeMarginMaximum
	)
	board_width_percentage_ = clampi(
		board_width_percentage,
		kBoardWidthPercentageMinimum,
		kBoardWidthPercentageMaximum
	)
	large_ui_enabled_ = large_ui_enabled
	large_ui_multiplier_ = large_ui_multiplier
	move_confirmation_enabled_ = move_confirmation_enabled
	pptx_image_format_ = clampi(
		pptx_image_format, kPptxImageFormatSvg, kPptxImageFormatPng
	)
	pptx_board_coordinates_ = pptx_board_coordinates
	katago_executable_path_ = katago_executable_path.strip_edges()
	katago_model_path_ = katago_model_path.strip_edges()
	katago_human_model_path_ = katago_human_model_path.strip_edges()
	katago_max_visits_ = maxi(katago_max_visits, 1)
	katago_human_max_visits_ = maxi(katago_human_max_visits, 1)
	katago_report_interval_seconds_ = clampf(
		katago_report_interval_seconds, 0.1, 60.0
	)
	katago_analysis_pv_length_ = maxi(katago_analysis_pv_length, 1)
	katago_show_score_lead_ = katago_show_score_lead
	katago_game_analysis_visits_ = maxi(katago_game_analysis_visits, 1)
	katago_analysis_config_path_ = get_managed_katago_analysis_config_path() \
		if OS.get_name() == "Android" \
		else katago_analysis_config_path.strip_edges()

	var error: Error = save_config_()
	if error != OK:
		language_ = previous_language
		apply_runtime_language_(previous_language)
		board_texture_path_ = previous_board_path
		black_texture_path_ = previous_black_path
		white_texture_path_ = previous_white_path
		move_number_mode_ = previous_move_number_mode
		move_number_count_ = previous_move_number_count
		absolute_move_numbers_ = previous_absolute_move_numbers
		playback_interval_seconds_ = previous_playback_interval
		stone_sound_volume_ = previous_stone_sound_volume
		horizontal_safe_margin_ = previous_horizontal_safe_margin
		board_width_percentage_ = previous_board_width_percentage
		large_ui_enabled_ = previous_large_ui_enabled
		large_ui_multiplier_ = previous_large_ui_multiplier
		move_confirmation_enabled_ = previous_move_confirmation_enabled
		pptx_image_format_ = previous_pptx_image_format
		pptx_board_coordinates_ = previous_pptx_board_coordinates
		katago_executable_path_ = previous_katago_executable_path
		katago_model_path_ = previous_katago_model_path
		katago_human_model_path_ = previous_katago_human_model_path
		katago_max_visits_ = previous_katago_max_visits
		katago_human_max_visits_ = previous_katago_human_max_visits
		katago_report_interval_seconds_ = previous_katago_report_interval
		katago_analysis_pv_length_ = previous_katago_analysis_pv_length
		katago_show_score_lead_ = previous_katago_show_score_lead
		katago_game_analysis_visits_ = previous_katago_game_analysis_visits
		katago_analysis_config_path_ = previous_katago_analysis_config_path
		return error
	if language_ != previous_language:
		apply_runtime_language_(language_)
	if board_path != previous_board_path or black_path != previous_black_path \
			or white_path != previous_white_path:
		load_textures_()
		textures_changed.emit()
	if move_number_mode_ != previous_move_number_mode \
			or move_number_count_ != previous_move_number_count \
			or absolute_move_numbers_ != previous_absolute_move_numbers:
		move_numbers_changed.emit()
	if not is_equal_approx(
		playback_interval_seconds_, previous_playback_interval
	):
		playback_interval_changed.emit()
	if move_confirmation_enabled_ != previous_move_confirmation_enabled:
		move_confirmation_changed.emit(move_confirmation_enabled_)
	if horizontal_safe_margin_ != previous_horizontal_safe_margin:
		horizontal_safe_margin_changed.emit(horizontal_safe_margin_)
	if board_width_percentage_ != previous_board_width_percentage:
		board_width_percentage_changed.emit(board_width_percentage_)
	if large_ui_enabled_ != previous_large_ui_enabled \
			or not is_equal_approx(
				large_ui_multiplier_, previous_large_ui_multiplier
			):
		large_ui_changed.emit(large_ui_enabled_, large_ui_multiplier_)
	if katago_executable_path_ != previous_katago_executable_path \
			or katago_model_path_ != previous_katago_model_path \
			or katago_analysis_config_path_ \
				!= previous_katago_analysis_config_path:
		katago_paths_changed.emit()
	if katago_human_model_path_ != previous_katago_human_model_path:
		katago_human_paths_changed.emit()
	if katago_max_visits_ != previous_katago_max_visits \
			or not is_equal_approx(
				katago_report_interval_seconds_, previous_katago_report_interval
			) or katago_analysis_pv_length_ \
				!= previous_katago_analysis_pv_length \
			or katago_show_score_lead_ != previous_katago_show_score_lead \
			or katago_game_analysis_visits_ \
				!= previous_katago_game_analysis_visits:
		katago_analysis_settings_changed.emit()
	return OK


func reload() -> void:
	load_config_()
	apply_runtime_language_(language_)
	load_textures_()
	textures_changed.emit()
	move_numbers_changed.emit()
	playback_interval_changed.emit()
	move_confirmation_changed.emit(move_confirmation_enabled_)
	horizontal_safe_margin_changed.emit(horizontal_safe_margin_)
	board_width_percentage_changed.emit(board_width_percentage_)
	large_ui_changed.emit(large_ui_enabled_, large_ui_multiplier_)
	katago_paths_changed.emit()
	katago_human_paths_changed.emit()
	katago_analysis_settings_changed.emit()


func apply_runtime_language_(locale: String) -> void:
	TranslationServer.set_locale(locale)
	language_changed.emit(locale)


func load_window_state_() -> void:
	saved_window_state_available_ = false
	var config: ConfigFile = ConfigFile.new()
	var error: Error = config.load(kWindowStatePath)
	if error == ERR_FILE_NOT_FOUND:
		return
	if error != OK:
		push_warning(
			"Failed to load window state: %s" % error_string(error)
		)
		return
	var position_value: Variant = config.get_value(
		"window", "position", Vector2i.ZERO
	)
	var size_value: Variant = config.get_value(
		"window", "size", Vector2i.ZERO
	)
	if position_value is not Vector2i or size_value is not Vector2i:
		return
	var loaded_size: Vector2i = size_value as Vector2i
	if loaded_size.x <= 0 or loaded_size.y <= 0:
		return
	saved_window_position_ = position_value as Vector2i
	saved_window_size_ = loaded_size
	saved_window_maximized_ = bool(config.get_value(
		"window", "maximized", false
	))
	saved_window_state_available_ = true


func load_config_() -> void:
	var config: ConfigFile = ConfigFile.new()
	var error: Error = config.load(kConfigPath)
	if error == ERR_FILE_NOT_FOUND:
		reset_settings_()
		error = save_config_()
		if error != OK:
			push_warning("Failed to create settings file: %s" % error_string(error))
		return
	if error != OK:
		push_warning("Failed to load settings file: %s" % error_string(error))
		reset_settings_()
		return
	var schema_version: int = int(config.get_value(
		"general",
		"schema_version",
		0
	))
	language_ = str(config.get_value(
		"general", "language", kDefaultLanguage
	))
	if not is_supported_language(language_):
		language_ = kDefaultLanguage

	board_texture_path_ = str(config.get_value(
		"board",
		"path",
		kDefaultBoardTexturePath
	))
	black_texture_path_ = str(config.get_value(
		"stones",
		"black_path",
		kDefaultBlackTexturePath
	))
	white_texture_path_ = load_white_texture_path_(config)
	move_number_mode_ = clampi(int(config.get_value(
		"display",
		"move_number_mode",
		kDefaultMoveNumberMode
	)), kMoveNumberModeOne, kMoveNumberModeCustom)
	move_number_count_ = maxi(int(config.get_value(
		"display",
		"move_number_count",
		kDefaultMoveNumberCount
	)), 1)
	absolute_move_numbers_ = bool(config.get_value(
		"display",
		"absolute_move_numbers",
		kDefaultAbsoluteMoveNumbers
	))
	playback_interval_seconds_ = clampf(float(config.get_value(
		"display",
		"playback_interval_seconds",
		kDefaultPlaybackIntervalSeconds
	)), 0.1, 60.0)
	var stored_stone_sound_volume: int = int(config.get_value(
		"audio",
		"stone_sound_volume",
		kDefaultStoneSoundVolume
	))
	if schema_version < 15:
		match stored_stone_sound_volume:
			0:
				stored_stone_sound_volume = 0
			1:
				stored_stone_sound_volume = 25
			2:
				stored_stone_sound_volume = 50
			3:
				stored_stone_sound_volume = 100
	stone_sound_volume_ = clampi(
		stored_stone_sound_volume,
		kStoneSoundVolumeMinimum,
		kStoneSoundVolumeMaximum
	)
	move_confirmation_enabled_ = bool(config.get_value(
		"gameplay",
		"move_confirmation_enabled",
		default_move_confirmation_enabled_()
	))
	pptx_image_format_ = clampi(int(config.get_value(
		"export",
		"pptx_image_format",
		kDefaultPptxImageFormat
	)), kPptxImageFormatSvg, kPptxImageFormatPng)
	pptx_board_coordinates_ = bool(config.get_value(
		"export",
		"pptx_board_coordinates",
		kDefaultPptxBoardCoordinates
	))
	horizontal_safe_margin_ = clampi(int(config.get_value(
		"display",
		"horizontal_safe_margin",
		kDefaultHorizontalSafeMargin
	)), 0, kHorizontalSafeMarginMaximum)
	board_width_percentage_ = clampi(int(config.get_value(
		"display",
		"board_width_percentage",
		kDefaultBoardWidthPercentage
	)), kBoardWidthPercentageMinimum, kBoardWidthPercentageMaximum)
	large_ui_enabled_ = bool(config.get_value(
		"display",
		"large_ui_enabled",
		kDefaultLargeUiEnabled
	))
	var stored_large_ui_multiplier: float = float(config.get_value(
		"display",
		"large_ui_multiplier",
		kDefaultLargeUiMultiplier
	))
	large_ui_multiplier_ = stored_large_ui_multiplier \
		if stored_large_ui_multiplier >= kLargeUiMultiplierMinimum \
			and stored_large_ui_multiplier <= kLargeUiMultiplierMaximum \
		else kDefaultLargeUiMultiplier
	katago_executable_path_ = str(config.get_value(
		"katago",
		"executable_path",
		kDefaultKatagoExecutablePath
	)).strip_edges()
	katago_model_path_ = str(config.get_value(
		"katago",
		"model_path",
		kDefaultKatagoModelPath
	)).strip_edges()
	katago_human_model_path_ = str(config.get_value(
		"katago_human",
		"model_path",
		kDefaultKatagoHumanModelPath
	)).strip_edges()
	katago_max_visits_ = maxi(int(config.get_value(
		"katago",
		"max_visits",
		kDefaultKatagoMaxVisits
	)), 1)
	katago_human_max_visits_ = maxi(int(config.get_value(
		"katago_human",
		"max_visits",
		kDefaultKatagoHumanMaxVisits
	)), 1)
	katago_report_interval_seconds_ = clampf(float(config.get_value(
		"katago",
		"report_interval_seconds",
		kDefaultKatagoReportIntervalSeconds
	)), 0.1, 60.0)
	katago_analysis_pv_length_ = maxi(int(config.get_value(
		"katago",
		"analysis_pv_length",
		kDefaultKatagoAnalysisPvLength
	)), 1)
	katago_show_score_lead_ = bool(config.get_value(
		"katago",
		"show_score_lead",
		kDefaultKatagoShowScoreLead
	))
	katago_game_analysis_visits_ = maxi(int(config.get_value(
		"katago",
		"game_analysis_visits",
		kDefaultKatagoGameAnalysisVisits
	)), 1)
	katago_analysis_config_path_ = get_managed_katago_analysis_config_path() \
		if OS.get_name() == "Android" else str(config.get_value(
			"katago",
			"analysis_config_path",
			get_managed_katago_analysis_config_path()
		)).strip_edges()

	if schema_version < 11:
		katago_game_analysis_visits_ = kDefaultKatagoGameAnalysisVisits
	if schema_version < 20 and OS.get_name() == "Android":
		var managed_config_error: Error = \
			write_managed_katago_analysis_config(1, 1)
		if managed_config_error != OK:
			push_warning(
				"Failed to migrate Android KataGo config: %s" \
					% error_string(managed_config_error)
			)
	if schema_version < kSchemaVersion:
		error = save_config_()
		if error != OK:
			push_warning("Failed to migrate settings file: %s" % error_string(error))


func load_white_texture_path_(config: ConfigFile) -> String:
	if config.has_section_key("stones", "white_path"):
		return migrate_white_texture_path_(str(config.get_value(
			"stones",
			"white_path",
			kDefaultWhiteTexturePath
		)))

	var old_paths: Variant = config.get_value(
		"stones",
		"white_paths",
		PackedStringArray()
	)
	if old_paths is PackedStringArray or old_paths is Array:
		var paths: PackedStringArray = PackedStringArray(old_paths)
		if not paths.is_empty():
			return migrate_white_texture_path_(paths[0])
	return kDefaultWhiteTexturePath


func migrate_white_texture_path_(path: String) -> String:
	for index in range(16):
		if path == "res://assets/stones/white_%02d.png" % index:
			return kDefaultWhiteTexturePath
	return path


func save_config_() -> Error:
	var config: ConfigFile = ConfigFile.new()
	config.set_value("general", "schema_version", kSchemaVersion)
	config.set_value("general", "language", language_)
	config.set_value("board", "path", board_texture_path_)
	config.set_value("stones", "black_path", black_texture_path_)
	config.set_value("stones", "white_path", white_texture_path_)
	config.set_value("display", "move_number_mode", move_number_mode_)
	config.set_value("display", "move_number_count", move_number_count_)
	config.set_value(
		"display",
		"absolute_move_numbers",
		absolute_move_numbers_
	)
	config.set_value(
		"display",
		"playback_interval_seconds",
		playback_interval_seconds_
	)
	config.set_value("audio", "stone_sound_volume", stone_sound_volume_)
	config.set_value(
		"display", "horizontal_safe_margin", horizontal_safe_margin_
	)
	config.set_value(
		"display", "board_width_percentage", board_width_percentage_
	)
	config.set_value("display", "large_ui_enabled", large_ui_enabled_)
	config.set_value("display", "large_ui_multiplier", large_ui_multiplier_)
	config.set_value(
		"gameplay", "move_confirmation_enabled", move_confirmation_enabled_
	)
	config.set_value("export", "pptx_image_format", pptx_image_format_)
	config.set_value(
		"export", "pptx_board_coordinates", pptx_board_coordinates_
	)
	config.set_value("katago", "executable_path", katago_executable_path_)
	config.set_value("katago", "model_path", katago_model_path_)
	config.set_value(
		"katago_human", "model_path", katago_human_model_path_
	)
	config.set_value("katago", "max_visits", katago_max_visits_)
	config.set_value(
		"katago_human", "max_visits", katago_human_max_visits_
	)
	config.set_value(
		"katago", "report_interval_seconds", katago_report_interval_seconds_
	)
	config.set_value(
		"katago", "analysis_pv_length", katago_analysis_pv_length_
	)
	config.set_value("katago", "show_score_lead", katago_show_score_lead_)
	config.set_value(
		"katago", "game_analysis_visits", katago_game_analysis_visits_
	)
	config.set_value(
		"katago", "analysis_config_path", katago_analysis_config_path_
	)
	return config.save(kConfigPath)


func reset_settings_() -> void:
	language_ = kDefaultLanguage
	board_texture_path_ = kDefaultBoardTexturePath
	black_texture_path_ = kDefaultBlackTexturePath
	white_texture_path_ = kDefaultWhiteTexturePath
	move_number_mode_ = kDefaultMoveNumberMode
	move_number_count_ = kDefaultMoveNumberCount
	absolute_move_numbers_ = kDefaultAbsoluteMoveNumbers
	playback_interval_seconds_ = kDefaultPlaybackIntervalSeconds
	stone_sound_volume_ = kDefaultStoneSoundVolume
	horizontal_safe_margin_ = kDefaultHorizontalSafeMargin
	board_width_percentage_ = kDefaultBoardWidthPercentage
	large_ui_enabled_ = kDefaultLargeUiEnabled
	large_ui_multiplier_ = kDefaultLargeUiMultiplier
	move_confirmation_enabled_ = default_move_confirmation_enabled_()
	pptx_image_format_ = kDefaultPptxImageFormat
	pptx_board_coordinates_ = kDefaultPptxBoardCoordinates
	katago_executable_path_ = kDefaultKatagoExecutablePath
	katago_model_path_ = kDefaultKatagoModelPath
	katago_human_model_path_ = kDefaultKatagoHumanModelPath
	katago_max_visits_ = kDefaultKatagoMaxVisits
	katago_human_max_visits_ = kDefaultKatagoHumanMaxVisits
	katago_report_interval_seconds_ = kDefaultKatagoReportIntervalSeconds
	katago_analysis_pv_length_ = kDefaultKatagoAnalysisPvLength
	katago_show_score_lead_ = kDefaultKatagoShowScoreLead
	katago_game_analysis_visits_ = kDefaultKatagoGameAnalysisVisits
	katago_analysis_config_path_ = get_managed_katago_analysis_config_path()


func default_move_confirmation_enabled_() -> bool:
	return kDefaultMobileMoveConfirmation if OS.has_feature("mobile") \
		else kDefaultDesktopMoveConfirmation


func ensure_managed_katago_analysis_config_() -> void:
	if FileAccess.file_exists(kManagedKatagoConfigPath):
		if OS.get_name() != "Android":
			remove_deprecated_desktop_batch_size_()
		return
	var default_threads: int = 1 if OS.get_name() == "Android" else 6
	var default_batch_size: int = 1 if OS.get_name() == "Android" else 8
	var error: Error = write_managed_katago_analysis_config(
		default_threads, default_batch_size
	)
	if error != OK:
		push_warning(
			"Failed to create managed KataGo config: %s" % error_string(error)
		)


func remove_deprecated_desktop_batch_size_() -> void:
	var source: FileAccess = FileAccess.open(
		kManagedKatagoConfigPath, FileAccess.READ
	)
	if source == null:
		return
	var original: String = source.get_as_text()
	var kept_lines: PackedStringArray = PackedStringArray()
	for line: String in original.split("\n", true):
		if not line.strip_edges().begins_with("nnMaxBatchSize"):
			kept_lines.append(line)
	var updated: String = "\n".join(kept_lines)
	if updated == original:
		return
	var destination: FileAccess = FileAccess.open(
		kManagedKatagoConfigPath, FileAccess.WRITE
	)
	if destination != null:
		destination.store_string(updated)


func ensure_managed_katago_human_analysis_config_() -> void:
	if FileAccess.file_exists(kManagedKatagoHumanConfigPath):
		remove_deprecated_human_config_keys_()
		return
	var default_threads: int = 1 if OS.get_name() == "Android" else 2
	var default_batch_size: int = 1 if OS.get_name() == "Android" else 2
	var error: Error = write_managed_katago_human_analysis_config(
		default_threads, default_batch_size
	)
	if error != OK:
		push_warning(
			"Failed to create managed KataGo Human SL config: %s" \
				% error_string(error)
		)


func remove_deprecated_human_config_keys_() -> void:
	var source: FileAccess = FileAccess.open(
		kManagedKatagoHumanConfigPath, FileAccess.READ
	)
	if source == null:
		return
	var original: String = source.get_as_text()
	var updated: String = original
	for value: String in ["true", "false"]:
		updated = updated.replace(
			"analysisIgnorePreRootHistory = %s\r\n" % value, ""
		).replace(
			"analysisIgnorePreRootHistory = %s\n" % value, ""
		)
	if updated == original:
		return
	var destination: FileAccess = FileAccess.open(
		kManagedKatagoHumanConfigPath, FileAccess.WRITE
	)
	if destination != null:
		destination.store_string(updated)


func build_managed_katago_config_(
		search_threads: int,
		batch_size: int
) -> String:
	var cache_power: int = 16 if OS.get_name() == "Android" else 20
	var mutex_pool_power: int = 14 if OS.get_name() == "Android" else 17
	var batch_size_setting: String = ("nnMaxBatchSize = %d\n" \
		% maxi(batch_size, 1)) if OS.get_name() == "Android" else ""
	return """# Generated by Gotepad. This file may be regenerated by performance detection.
reportAnalysisWinratesAs = BLACK
maxVisits = 500
numAnalysisThreads = 1
numSearchThreadsPerAnalysisThread = %d
%snnCacheSizePowerOfTwo = %d
nnMutexPoolSizePowerOfTwo = %d
nnRandomize = true
""" % [
		maxi(search_threads, 1), batch_size_setting, cache_power,
		mutex_pool_power
]


func build_managed_katago_human_config_(
		search_threads: int,
		batch_size: int
) -> String:
	var cache_power: int = 15 if OS.get_name() == "Android" else 18
	var mutex_pool_power: int = 13 if OS.get_name() == "Android" else 16
	return """# Generated by Gotepad for KataGo Human SL. This file may be regenerated by performance detection.
reportAnalysisWinratesAs = BLACK
maxVisits = 40
numAnalysisThreads = 1
numSearchThreadsPerAnalysisThread = %d
nnMaxBatchSize = %d
nnCacheSizePowerOfTwo = %d
nnMutexPoolSizePowerOfTwo = %d
nnRandomize = true
humanSLProfile = rank_1d
ignorePreRootHistory = false
rootNumSymmetriesToSample = 2
""" % [
		maxi(search_threads, 1), maxi(batch_size, 1),
		cache_power, mutex_pool_power
	]


func load_textures_() -> void:
	board_texture_ = load_texture_(
		board_texture_path_,
		kDefaultBoardTexture
	)
	black_texture_ = load_texture_(
		black_texture_path_,
		kDefaultBlackTexture
	)
	white_texture_ = load_texture_(
		white_texture_path_,
		kDefaultWhiteTexture
	)


func load_texture_(path: String, fallback: Texture2D) -> Texture2D:
	if ResourceLoader.exists(path, "Texture2D"):
		var resource: Resource = ResourceLoader.load(path, "Texture2D")
		var resource_texture: Texture2D = resource as Texture2D
		if resource_texture != null:
			return resource_texture

	var image: Image = Image.new()
	var error: Error = image.load(path)
	if error == OK:
		return ImageTexture.create_from_image(image)

	push_warning("Failed to load texture '%s'; using the default." % path)
	return fallback
