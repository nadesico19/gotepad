class_name KataGoEmbeddedTransport
extends KataGoTransport

const kEngineClass: StringName = &"KataGoEmbeddedEngine"
const kModelResourcePath: String = \
	"res://assets/katago/g170e-b10c128-s1141046784-d204142634.kgmodel"
const kInstallDirectory: String = "user://katago/embedded/v1"
const kInstalledModelPath: String = \
	"user://katago/embedded/v1/g170e-b10c128-s1141046784-d204142634.bin.gz"
const kModelSize: int = 11138361
const kCopyChunkSize: int = 1024 * 1024
const kStateStopped: int = 0
const kStateStarting: int = 1
const kStateRunning: int = 2
const kStateFailed: int = 4

var engine_: Object
var stopped_emitted_: bool = false


func start_transport() -> bool:
	return start_transport_with_override("")


func start_transport_with_override(override_config: String) -> bool:
	return start_custom_transport(
		"", "", SettingsStore.get_managed_katago_analysis_config_path(),
		override_config
	)


func start_human_transport_with_override(override_config: String) -> bool:
	return start_custom_transport(
		"", SettingsStore.get_android_external_katago_human_model_path(),
		SettingsStore.get_managed_katago_human_analysis_config_path(),
		override_config
	)


func start_custom_transport(
		model_path_override: String,
		human_model_path: String,
		config_path: String,
		override_config: String
) -> bool:
	if is_transport_running():
		return true
	if OS.get_name() != "Android":
		transport_error.emit(tr("内置 KataGo 引擎仅供安卓版使用。"))
		return false
	if not ClassDB.class_exists(kEngineClass):
		transport_error.emit(tr("安卓版未包含内置 KataGo 引擎扩展。"))
		return false
	var install_error: String = install_runtime_files_()
	if not install_error.is_empty():
		transport_error.emit(install_error)
		return false
	if engine_ == null:
		engine_ = ClassDB.instantiate(kEngineClass)
	if engine_ == null:
		transport_error.emit(tr("无法创建内置 KataGo 引擎。"))
		return false
	var selected_model_path: String = selected_model_path_() \
		if model_path_override.is_empty() else model_path_override
	var model_path: String = ProjectSettings.globalize_path(selected_model_path)
	var effective_human_model_path: String = "" if human_model_path.is_empty() \
		else ProjectSettings.globalize_path(human_model_path)
	var effective_override: String = "reportAnalysisWinratesAs=BLACK"
	if not override_config.strip_edges().is_empty():
		effective_override += "," + override_config.strip_edges()
	var started: bool = bool(engine_.call(
		"start_engine", model_path, effective_human_model_path, config_path,
		effective_override
	))
	if not started:
		transport_error.emit(native_error_())
		return false
	stopped_emitted_ = false
	set_process(true)
	return true


func send_line(line: String) -> bool:
	return engine_ != null and bool(engine_.call("send_line", line))


func stop_transport() -> void:
	if engine_ != null:
		engine_.call("stop_engine")
	set_process(false)
	emit_stopped_once_()


func is_transport_running() -> bool:
	if engine_ == null:
		return false
	var state: int = int(engine_.call("get_state"))
	return state == kStateStarting or state == kStateRunning


func _process(_delta: float) -> void:
	if engine_ == null:
		return
	var response_lines: PackedStringArray = \
		PackedStringArray(engine_.call("poll_lines"))
	for line: String in response_lines:
		if not line.is_empty():
			line_received.emit(line)
	var log_lines: PackedStringArray = \
		PackedStringArray(engine_.call("poll_logs"))
	for line: String in log_lines:
		log_received.emit(line)
		print("KataGo embedded: %s" % line)
	var state: int = int(engine_.call("get_state"))
	if state == kStateFailed:
		set_process(false)
		transport_error.emit(native_error_())
		emit_stopped_once_()
	elif state == kStateStopped:
		set_process(false)
		emit_stopped_once_()


func install_runtime_files_() -> String:
	var absolute_directory: String = \
		ProjectSettings.globalize_path(kInstallDirectory)
	var directory_error: Error = DirAccess.make_dir_recursive_absolute(
		absolute_directory
	)
	if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
		return tr("无法创建内置 KataGo 数据目录：%s") % \
			error_string(directory_error)
	if not SettingsStore.get_android_external_katago_model_path().is_empty():
		return ensure_config_()
	var must_copy_model: bool = true
	if FileAccess.file_exists(kInstalledModelPath):
		var installed_model: FileAccess = FileAccess.open(
			kInstalledModelPath, FileAccess.READ
		)
		must_copy_model = installed_model == null \
			or installed_model.get_length() != kModelSize
		if installed_model != null:
			installed_model.close()
	if must_copy_model:
		var copy_error: Error = copy_resource_file_(
			kModelResourcePath, kInstalledModelPath
		)
		if copy_error != OK:
			return tr("无法安装内置 KataGo 模型：%s") % \
				error_string(copy_error)
	return ensure_config_()


func ensure_config_() -> String:
	var config_path: String = SettingsStore.get_managed_katago_analysis_config_path()
	if not FileAccess.file_exists(config_path):
		var config_error: Error = \
			SettingsStore.write_managed_katago_analysis_config(1, 1)
		if config_error != OK:
			return tr("无法创建内置 KataGo 配置：%s") % \
				error_string(config_error)
	return ""


func selected_model_path_() -> String:
	var external_path: String = \
		SettingsStore.get_android_external_katago_model_path()
	return kInstalledModelPath if external_path.is_empty() else external_path


func copy_resource_file_(source_path: String, target_path: String) -> Error:
	var source: FileAccess = FileAccess.open(source_path, FileAccess.READ)
	if source == null:
		return FileAccess.get_open_error()
	var target: FileAccess = FileAccess.open(target_path, FileAccess.WRITE)
	if target == null:
		var open_error: Error = FileAccess.get_open_error()
		source.close()
		return open_error
	while source.get_position() < source.get_length():
		var remaining: int = source.get_length() - source.get_position()
		var count: int = mini(remaining, kCopyChunkSize)
		var bytes: PackedByteArray = source.get_buffer(count)
		if bytes.size() != count or not target.store_buffer(bytes):
			source.close()
			target.close()
			return ERR_FILE_CANT_WRITE
	target.flush()
	var result: Error = target.get_error()
	source.close()
	target.close()
	return result


func native_error_() -> String:
	if engine_ == null:
		return tr("内置 KataGo 引擎不可用。")
	var message: String = str(engine_.call("get_error"))
	return tr("内置 KataGo 引擎启动失败。") if message.is_empty() else message


func emit_stopped_once_() -> void:
	if stopped_emitted_:
		return
	stopped_emitted_ = true
	transport_stopped.emit()


func _exit_tree() -> void:
	stop_transport()
