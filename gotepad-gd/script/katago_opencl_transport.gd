class_name KataGoOpenCLTransport
extends KataGoTransport

const kAndroidHostClass: StringName = &"com.godot.game.GodotApp"
const kModelResourcePath: String = "res://assets/katago/kata1-b10c128-s258941696-d77667876.kgmodel"
const kInstallDirectory: String = "user://katago/embedded/v1"
const kInstalledModelPath: String = "user://katago/embedded/v1/kata1-b10c128-s258941696-d77667876.txt.gz"
const kOpenCLDataDirectory: String = "user://katago/opencl"
const kModelSize: int = 14472513
const kCopyChunkSize: int = 1024 * 1024
const kStateStopped: int = 0
const kStateStarting: int = 1
const kStateRunning: int = 2
const kStateFailed: int = 4

var host_class_: Variant
var stopped_emitted_: bool = false


func start_transport() -> bool:
	return start_transport_with_override("")


func start_transport_with_override(override_config: String) -> bool:
	if is_transport_running():
		return true
	if OS.get_name() != "Android":
		transport_error.emit(tr("OpenCL KataGo 后端仅供安卓版使用。"))
		return false
	var install_error: String = install_runtime_files_()
	if not install_error.is_empty():
		transport_error.emit(install_error)
		return false
	host_class_ = JavaClassWrapper.wrap(kAndroidHostClass)
	if host_class_ == null:
		transport_error.emit(tr("无法连接 Android OpenCL 服务。"))
		return false
	var effective_override: String = (
		"reportAnalysisWinratesAs=BLACK,homeDataDir=%s,openclUseFP16=auto"
		% ProjectSettings.globalize_path(kOpenCLDataDirectory)
	)
	if not override_config.strip_edges().is_empty():
		effective_override += "," + override_config.strip_edges()
	var started: bool = bool(host_class_.startKataGoOpenCL(
		ProjectSettings.globalize_path(kInstalledModelPath),
		SettingsStore.get_managed_katago_analysis_config_path(),
		effective_override
	))
	if not started:
		transport_error.emit(native_error_())
		return false
	stopped_emitted_ = false
	set_process(true)
	return true


func send_line(line: String) -> bool:
	return host_class_ != null and bool(host_class_.sendKataGoOpenCLLine(line))


func stop_transport() -> void:
	if host_class_ != null:
		host_class_.stopKataGoOpenCL()
	set_process(false)
	emit_stopped_once_()


func is_transport_running() -> bool:
	if host_class_ == null:
		return false
	var state: int = int(host_class_.getKataGoOpenCLState())
	return state == kStateStarting or state == kStateRunning


func _process(_delta: float) -> void:
	if host_class_ == null:
		return
	var response_values: Variant = host_class_.pollKataGoOpenCLLines()
	if response_values != null:
		for value: Variant in response_values:
			var line: String = str(value)
			if not line.is_empty():
				line_received.emit(line)
	var log_values: Variant = host_class_.pollKataGoOpenCLLogs()
	if log_values != null:
		for value: Variant in log_values:
			var line: String = str(value)
			log_received.emit(line)
			print("KataGo OpenCL: %s" % line)
	var state: int = int(host_class_.getKataGoOpenCLState())
	if state == kStateFailed:
		set_process(false)
		transport_error.emit(native_error_())
		emit_stopped_once_()
	elif state == kStateStopped:
		set_process(false)
		emit_stopped_once_()


func install_runtime_files_() -> String:
	for directory: String in [kInstallDirectory, kOpenCLDataDirectory]:
		var error: Error = DirAccess.make_dir_recursive_absolute(
			ProjectSettings.globalize_path(directory)
		)
		if error != OK and error != ERR_ALREADY_EXISTS:
			return tr("无法创建内置 KataGo 数据目录：%s") % error_string(error)
	var must_copy_model: bool = true
	if FileAccess.file_exists(kInstalledModelPath):
		var installed_model: FileAccess = FileAccess.open(kInstalledModelPath, FileAccess.READ)
		must_copy_model = installed_model == null or installed_model.get_length() != kModelSize
		if installed_model != null:
			installed_model.close()
	if must_copy_model:
		var copy_error: Error = copy_resource_file_(kModelResourcePath, kInstalledModelPath)
		if copy_error != OK:
			return tr("无法安装内置 KataGo 模型：%s") % error_string(copy_error)
	var config_path: String = SettingsStore.get_managed_katago_analysis_config_path()
	if not FileAccess.file_exists(config_path):
		var config_error: Error = SettingsStore.write_managed_katago_analysis_config(1, 1)
		if config_error != OK:
			return tr("无法创建内置 KataGo 配置：%s") % error_string(config_error)
	return ""


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
	if host_class_ == null:
		return tr("Android OpenCL 服务不可用。")
	var message: String = str(host_class_.getKataGoOpenCLError())
	return tr("OpenCL KataGo 启动失败。") if message.is_empty() else message


func emit_stopped_once_() -> void:
	if stopped_emitted_:
		return
	stopped_emitted_ = true
	transport_stopped.emit()


func _exit_tree() -> void:
	stop_transport()
