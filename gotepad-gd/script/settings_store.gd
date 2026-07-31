extends Node

signal textures_changed
signal move_numbers_changed
signal playback_interval_changed

const kConfigPath: String = "user://settings.cfg"
const kSchemaVersion: int = 5
const kMoveNumberModeOne: int = 0
const kMoveNumberModeTen: int = 1
const kMoveNumberModeAll: int = 2
const kMoveNumberModeCustom: int = 3
const kDefaultMoveNumberMode: int = kMoveNumberModeOne
const kDefaultMoveNumberCount: int = 20
const kDefaultAbsoluteMoveNumbers: bool = false
const kDefaultPlaybackIntervalSeconds: float = 1.0
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


func _ready() -> void:
	load_config_()
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



func set_display_settings(
		board_path: String,
		black_path: String,
		white_path: String,
		move_number_mode: int,
		move_number_count: int,
		absolute_move_numbers: bool,
		playback_interval_seconds: float
) -> Error:
	var previous_board_path: String = board_texture_path_
	var previous_black_path: String = black_texture_path_
	var previous_white_path: String = white_texture_path_
	var previous_move_number_mode: int = move_number_mode_
	var previous_move_number_count: int = move_number_count_
	var previous_absolute_move_numbers: bool = absolute_move_numbers_
	var previous_playback_interval: float = playback_interval_seconds_
	board_texture_path_ = board_path
	black_texture_path_ = black_path
	white_texture_path_ = white_path
	move_number_mode_ = clampi(
		move_number_mode, kMoveNumberModeOne, kMoveNumberModeCustom
	)
	move_number_count_ = maxi(move_number_count, 1)
	absolute_move_numbers_ = absolute_move_numbers
	playback_interval_seconds_ = clampf(playback_interval_seconds, 0.1, 60.0)

	var error: Error = save_config_()
	if error != OK:
		board_texture_path_ = previous_board_path
		black_texture_path_ = previous_black_path
		white_texture_path_ = previous_white_path
		move_number_mode_ = previous_move_number_mode
		move_number_count_ = previous_move_number_count
		absolute_move_numbers_ = previous_absolute_move_numbers
		playback_interval_seconds_ = previous_playback_interval
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
	return OK


func reload() -> void:
	load_config_()
	load_textures_()
	textures_changed.emit()
	move_numbers_changed.emit()
	playback_interval_changed.emit()


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

	var schema_version: int = int(config.get_value(
		"general",
		"schema_version",
		0
	))
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
	return config.save(kConfigPath)


func reset_settings_() -> void:
	board_texture_path_ = kDefaultBoardTexturePath
	black_texture_path_ = kDefaultBlackTexturePath
	white_texture_path_ = kDefaultWhiteTexturePath
	move_number_mode_ = kDefaultMoveNumberMode
	move_number_count_ = kDefaultMoveNumberCount
	absolute_move_numbers_ = kDefaultAbsoluteMoveNumbers
	playback_interval_seconds_ = kDefaultPlaybackIntervalSeconds


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
