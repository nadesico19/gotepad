extends Node

signal textures_changed
signal move_numbers_changed
signal playback_interval_changed
signal katago_paths_changed
signal katago_analysis_settings_changed

const kConfigPath: String = "user://settings.cfg"
const kSchemaVersion: int = 11
const kMoveNumberModeOne: int = 0
const kMoveNumberModeTen: int = 1
const kMoveNumberModeAll: int = 2
const kMoveNumberModeCustom: int = 3
const kDefaultMoveNumberMode: int = kMoveNumberModeOne
const kDefaultMoveNumberCount: int = 20
const kDefaultAbsoluteMoveNumbers: bool = false
const kDefaultPlaybackIntervalSeconds: float = 1.0
const kDefaultKatagoExecutablePath: String = ""
const kDefaultKatagoModelPath: String = ""
const kDefaultKatagoMaxVisits: int = 500
const kDefaultKatagoReportIntervalSeconds: float = 2.0
const kDefaultKatagoAnalysisPvLength: int = 10
const kDefaultKatagoShowScoreLead: bool = true
const kDefaultKatagoGameAnalysisVisits: int = 1
const kManagedKatagoConfigPath: String = \
	"user://katago/analysis.cfg"
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
var move_number_mode_: int = kDefaultMoveNumberMode
var move_number_count_: int = kDefaultMoveNumberCount
var absolute_move_numbers_: bool = kDefaultAbsoluteMoveNumbers
var playback_interval_seconds_: float = kDefaultPlaybackIntervalSeconds
var katago_executable_path_: String = kDefaultKatagoExecutablePath
var katago_model_path_: String = kDefaultKatagoModelPath
var katago_max_visits_: int = kDefaultKatagoMaxVisits
var katago_report_interval_seconds_: float = \
	kDefaultKatagoReportIntervalSeconds
var katago_analysis_pv_length_: int = kDefaultKatagoAnalysisPvLength
var katago_show_score_lead_: bool = kDefaultKatagoShowScoreLead
var katago_game_analysis_visits_: int = kDefaultKatagoGameAnalysisVisits
var katago_analysis_config_path_: String = ""


func _ready() -> void:
	load_config_()
	ensure_managed_katago_analysis_config_()
	load_textures_()


func get_board_texture() -> Texture2D:
	return board_texture_


func get_black_stone_texture() -> Texture2D:
	return black_texture_


func get_white_stone_texture() -> Texture2D:
	return white_texture_


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


func get_katago_executable_path() -> String:
	return katago_executable_path_


func get_katago_model_path() -> String:
	return katago_model_path_


func get_katago_max_visits() -> int:
	return katago_max_visits_


func get_katago_report_interval_seconds() -> float:
	return katago_report_interval_seconds_


func get_katago_analysis_pv_length() -> int:
	return katago_analysis_pv_length_


func get_katago_show_score_lead() -> bool:
	return katago_show_score_lead_


func get_katago_game_analysis_visits() -> int:
	return katago_game_analysis_visits_


func get_katago_analysis_config_path() -> String:
	return katago_analysis_config_path_


func get_managed_katago_analysis_config_path() -> String:
	return ProjectSettings.globalize_path(kManagedKatagoConfigPath)


func has_valid_katago_paths() -> bool:
	return is_katago_executable_path_valid(katago_executable_path_) \
		and is_katago_model_path_valid(katago_model_path_) \
		and is_katago_analysis_config_path_valid(katago_analysis_config_path_)


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
		and candidate.to_lower().ends_with(".bin.gz") \
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


func set_settings(
		board_path: String,
		black_path: String,
		white_path: String,
		move_number_mode: int,
		move_number_count: int,
		absolute_move_numbers: bool,
		playback_interval_seconds: float,
		katago_executable_path: String,
		katago_model_path: String,
		katago_max_visits: int,
		katago_report_interval_seconds: float,
		katago_analysis_pv_length: int,
		katago_show_score_lead: bool,
		katago_game_analysis_visits: int,
		katago_analysis_config_path: String
) -> Error:
	var previous_board_path: String = board_texture_path_
	var previous_black_path: String = black_texture_path_
	var previous_white_path: String = white_texture_path_
	var previous_move_number_mode: int = move_number_mode_
	var previous_move_number_count: int = move_number_count_
	var previous_absolute_move_numbers: bool = absolute_move_numbers_
	var previous_playback_interval: float = playback_interval_seconds_
	var previous_katago_executable_path: String = katago_executable_path_
	var previous_katago_model_path: String = katago_model_path_
	var previous_katago_max_visits: int = katago_max_visits_
	var previous_katago_report_interval: float = \
		katago_report_interval_seconds_
	var previous_katago_analysis_pv_length: int = \
		katago_analysis_pv_length_
	var previous_katago_show_score_lead: bool = katago_show_score_lead_
	var previous_katago_game_analysis_visits: int = \
		katago_game_analysis_visits_
	var previous_katago_analysis_config_path: String = \
		katago_analysis_config_path_
	board_texture_path_ = board_path
	black_texture_path_ = black_path
	white_texture_path_ = white_path
	move_number_mode_ = clampi(
		move_number_mode, kMoveNumberModeOne, kMoveNumberModeCustom
	)
	move_number_count_ = maxi(move_number_count, 1)
	absolute_move_numbers_ = absolute_move_numbers
	playback_interval_seconds_ = clampf(playback_interval_seconds, 0.1, 60.0)
	katago_executable_path_ = katago_executable_path.strip_edges()
	katago_model_path_ = katago_model_path.strip_edges()
	katago_max_visits_ = maxi(katago_max_visits, 1)
	katago_report_interval_seconds_ = clampf(
		katago_report_interval_seconds, 0.1, 60.0
	)
	katago_analysis_pv_length_ = maxi(katago_analysis_pv_length, 1)
	katago_show_score_lead_ = katago_show_score_lead
	katago_game_analysis_visits_ = maxi(katago_game_analysis_visits, 1)
	katago_analysis_config_path_ = katago_analysis_config_path.strip_edges()

	var error: Error = save_config_()
	if error != OK:
		board_texture_path_ = previous_board_path
		black_texture_path_ = previous_black_path
		white_texture_path_ = previous_white_path
		move_number_mode_ = previous_move_number_mode
		move_number_count_ = previous_move_number_count
		absolute_move_numbers_ = previous_absolute_move_numbers
		playback_interval_seconds_ = previous_playback_interval
		katago_executable_path_ = previous_katago_executable_path
		katago_model_path_ = previous_katago_model_path
		katago_max_visits_ = previous_katago_max_visits
		katago_report_interval_seconds_ = previous_katago_report_interval
		katago_analysis_pv_length_ = previous_katago_analysis_pv_length
		katago_show_score_lead_ = previous_katago_show_score_lead
		katago_game_analysis_visits_ = previous_katago_game_analysis_visits
		katago_analysis_config_path_ = previous_katago_analysis_config_path
		return error
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
	if katago_executable_path_ != previous_katago_executable_path \
			or katago_model_path_ != previous_katago_model_path \
			or katago_analysis_config_path_ \
				!= previous_katago_analysis_config_path:
		katago_paths_changed.emit()
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
	load_textures_()
	textures_changed.emit()
	move_numbers_changed.emit()
	playback_interval_changed.emit()
	katago_paths_changed.emit()
	katago_analysis_settings_changed.emit()


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
	katago_max_visits_ = maxi(int(config.get_value(
		"katago",
		"max_visits",
		kDefaultKatagoMaxVisits
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
	katago_analysis_config_path_ = str(config.get_value(
		"katago",
		"analysis_config_path",
		get_managed_katago_analysis_config_path()
	)).strip_edges()

	var schema_version: int = int(config.get_value(
		"general",
		"schema_version",
		0
	))
	if schema_version < 11:
		katago_game_analysis_visits_ = kDefaultKatagoGameAnalysisVisits
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
	config.set_value("katago", "executable_path", katago_executable_path_)
	config.set_value("katago", "model_path", katago_model_path_)
	config.set_value("katago", "max_visits", katago_max_visits_)
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
	board_texture_path_ = kDefaultBoardTexturePath
	black_texture_path_ = kDefaultBlackTexturePath
	white_texture_path_ = kDefaultWhiteTexturePath
	move_number_mode_ = kDefaultMoveNumberMode
	move_number_count_ = kDefaultMoveNumberCount
	absolute_move_numbers_ = kDefaultAbsoluteMoveNumbers
	playback_interval_seconds_ = kDefaultPlaybackIntervalSeconds
	katago_executable_path_ = kDefaultKatagoExecutablePath
	katago_model_path_ = kDefaultKatagoModelPath
	katago_max_visits_ = kDefaultKatagoMaxVisits
	katago_report_interval_seconds_ = kDefaultKatagoReportIntervalSeconds
	katago_analysis_pv_length_ = kDefaultKatagoAnalysisPvLength
	katago_show_score_lead_ = kDefaultKatagoShowScoreLead
	katago_game_analysis_visits_ = kDefaultKatagoGameAnalysisVisits
	katago_analysis_config_path_ = get_managed_katago_analysis_config_path()


func ensure_managed_katago_analysis_config_() -> void:
	if FileAccess.file_exists(kManagedKatagoConfigPath):
		return
	var error: Error = write_managed_katago_analysis_config(6, 8)
	if error != OK:
		push_warning(
			"Failed to create managed KataGo config: %s" % error_string(error)
		)


func build_managed_katago_config_(
		search_threads: int,
		batch_size: int
) -> String:
	return """# Generated by Gotepad. This file may be regenerated by performance detection.
reportAnalysisWinratesAs = BLACK
maxVisits = 500
numAnalysisThreads = 1
numSearchThreadsPerAnalysisThread = %d
nnMaxBatchSize = %d
nnCacheSizePowerOfTwo = 20
nnMutexPoolSizePowerOfTwo = 17
nnRandomize = true
""" % [maxi(search_threads, 1), maxi(batch_size, 1)]


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
