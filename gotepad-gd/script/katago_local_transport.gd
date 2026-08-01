class_name KataGoLocalTransport
extends KataGoTransport

var process_: Dictionary = {}
var stdout_buffer_: String = ""
var stderr_buffer_: String = ""
var stderr_error_summary_: String = ""
var stderr_error_detail_lines_: int = 0


func start_transport() -> bool:
	if is_transport_running():
		return true
	if OS.get_name() == "Android" or OS.get_name() == "iOS":
		transport_error.emit("移动端暂不支持本地KataGo引擎。")
		return false
	if not SettingsStore.has_valid_katago_paths():
		transport_error.emit("KataGo路径或配置文件无效，请先打开设置检查。")
		return false
	var arguments: PackedStringArray = PackedStringArray([
		"analysis",
		"-model", SettingsStore.get_katago_model_path(),
		"-config", SettingsStore.get_katago_analysis_config_path(),
		"-override-config", "reportAnalysisWinratesAs=BLACK"
	])
	process_ = OS.execute_with_pipe(
		SettingsStore.get_katago_executable_path(), arguments, false
	)
	if process_.is_empty():
		transport_error.emit("无法启动KataGo分析进程。")
		return false
	stdout_buffer_ = ""
	stderr_buffer_ = ""
	stderr_error_summary_ = ""
	stderr_error_detail_lines_ = 0
	set_process(true)
	return true


func send_line(line: String) -> bool:
	if not is_transport_running():
		return false
	var pipe: FileAccess = process_.get("stdio") as FileAccess
	if pipe == null:
		return false
	pipe.store_string(line + "\n")
	pipe.flush()
	return true


func stop_transport() -> void:
	if process_.is_empty():
		return
	var pid: int = int(process_.get("pid", -1))
	if pid > 0 and OS.is_process_running(pid):
		var _kill_error: Error = OS.kill(pid)
	close_pipes_()
	process_.clear()
	stdout_buffer_ = ""
	stderr_buffer_ = ""
	stderr_error_summary_ = ""
	stderr_error_detail_lines_ = 0
	set_process(false)
	transport_stopped.emit()


func is_transport_running() -> bool:
	if process_.is_empty():
		return false
	var pid: int = int(process_.get("pid", -1))
	return pid > 0 and OS.is_process_running(pid)


func _process(_delta: float) -> void:
	read_pipe_("stdio", false)
	read_pipe_("stderr", true)
	if is_transport_running():
		return
	read_pipe_("stdio", false)
	read_pipe_("stderr", true)
	flush_stderr_lines_(true)
	if not stderr_error_summary_.is_empty():
		transport_error.emit(
			"KataGo分析进程异常退出：%s" % stderr_error_summary_
		)
	else:
		transport_error.emit("KataGo分析进程已意外退出，请查看详细日志。")
	close_pipes_()
	process_.clear()
	set_process(false)
	transport_stopped.emit()


func read_pipe_(key: String, is_error: bool) -> void:
	var pipe: FileAccess = process_.get(key) as FileAccess
	if pipe == null:
		return
	var available_bytes: int = pipe.get_length()
	if available_bytes <= 0:
		return
	var chunk: String = pipe.get_buffer(available_bytes).get_string_from_utf8()
	if is_error:
		stderr_buffer_ += chunk
		flush_stderr_lines_(false)
		return
	stdout_buffer_ += chunk
	flush_stdout_lines_()


func flush_stdout_lines_() -> void:
	while true:
		var newline_index: int = stdout_buffer_.find("\n")
		if newline_index < 0:
			return
		var line: String = stdout_buffer_.substr(0, newline_index).strip_edges()
		stdout_buffer_ = stdout_buffer_.substr(newline_index + 1)
		if not line.is_empty():
			line_received.emit(line)


func flush_stderr_lines_(flush_remainder: bool) -> void:
	while true:
		var newline_index: int = stderr_buffer_.find("\n")
		if newline_index < 0:
			break
		var line: String = stderr_buffer_.substr(0, newline_index).strip_edges()
		stderr_buffer_ = stderr_buffer_.substr(newline_index + 1)
		handle_stderr_line_(line)
	if flush_remainder and not stderr_buffer_.strip_edges().is_empty():
		handle_stderr_line_(stderr_buffer_.strip_edges())
		stderr_buffer_ = ""


func handle_stderr_line_(line: String) -> void:
	if line.is_empty():
		return
	print("KataGo: %s" % line)
	if "ERROR" in line.to_upper():
		stderr_error_summary_ = line
		stderr_error_detail_lines_ = 3
	elif stderr_error_detail_lines_ > 0:
		stderr_error_summary_ += " | %s" % line
		stderr_error_detail_lines_ -= 1


func close_pipes_() -> void:
	for key: String in ["stdio", "stderr"]:
		var pipe: FileAccess = process_.get(key) as FileAccess
		if pipe != null:
			pipe.close()


func _exit_tree() -> void:
	stop_transport()
