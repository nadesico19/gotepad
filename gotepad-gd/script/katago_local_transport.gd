class_name KataGoLocalTransport
extends KataGoTransport

const kReadyLogSuffix: String = "Started, ready to begin handling requests"
const kIoPollMsec: int = 8

var process_: Dictionary = {}
var stdout_buffer_: PackedByteArray = PackedByteArray()
var stderr_buffer_: String = ""
var stderr_error_summary_: String = ""
var stderr_error_detail_lines_: int = 0
var io_thread_: Thread = Thread.new()
var io_mutex_: Mutex = Mutex.new()
var ready_: bool = false
var io_stopping_: bool = false
var write_failed_: bool = false
var pending_lines_: Array[String] = []
var received_stdout_: PackedByteArray = PackedByteArray()


func _ready() -> void:
	set_process(not process_.is_empty())


func start_transport() -> bool:
	return start_custom_transport(
		SettingsStore.get_katago_model_path(), "",
		SettingsStore.get_katago_analysis_config_path(), ""
	)


func start_human_transport() -> bool:
	return start_custom_transport(
		SettingsStore.get_katago_model_path(),
		SettingsStore.get_katago_human_model_path(),
		SettingsStore.get_managed_katago_human_analysis_config_path(), ""
	)


func start_custom_transport(
		model_path: String,
		human_model_path: String,
		config_path: String,
		override_config: String
) -> bool:
	if is_transport_running():
		return true
	if OS.get_name() == "Android" or OS.get_name() == "iOS":
		transport_error.emit(tr("移动端暂不支持本地KataGo引擎。"))
		return false
	if not SettingsStore.is_katago_executable_path_valid(
			SettingsStore.get_katago_executable_path()
		) or not SettingsStore.is_katago_model_path_valid(model_path) \
			or not SettingsStore.is_katago_analysis_config_path_valid(config_path) \
			or (not human_model_path.is_empty() \
				and not SettingsStore.is_katago_model_path_valid(human_model_path)):
		transport_error.emit(tr("KataGo路径或配置文件无效，请先打开设置检查。"))
		return false
	var arguments: PackedStringArray = PackedStringArray([
		"analysis",
		"-model", model_path,
		"-config", config_path,
	])
	if not human_model_path.is_empty():
		arguments.append_array(PackedStringArray([
			"-human-model", human_model_path
		]))
	var effective_override: String = "reportAnalysisWinratesAs=BLACK"
	if not override_config.strip_edges().is_empty():
		effective_override += "," + override_config.strip_edges()
	arguments.append_array(PackedStringArray([
		"-override-config", effective_override
	]))
	stop_transport()
	# The worker can write a full line even when it exceeds the pipe capacity.
	# Keep both ends of the stdio FileAccess on that worker.
	process_ = OS.execute_with_pipe(
		SettingsStore.get_katago_executable_path(), arguments, true
	)
	if process_.is_empty():
		transport_error.emit(tr("无法启动KataGo分析进程。"))
		return false
	var pipe: FileAccess = process_.get("stdio") as FileAccess
	if pipe == null or io_thread_.start(run_io_.bind(pipe)) != OK:
		stop_transport()
		transport_error.emit(tr("无法启动KataGo分析进程。"))
		return false
	set_process(true)
	return true


func send_line(line: String) -> bool:
	if not is_transport_running():
		return false
	if is_transport_initializing() and cancel_queued_query_(line):
		return true
	io_mutex_.lock()
	pending_lines_.append(line)
	io_mutex_.unlock()
	return true


func is_transport_initializing() -> bool:
	return not process_.is_empty() and not ready_


func cancel_queued_query_(line: String) -> bool:
	var command: Variant = JSON.parse_string(line)
	if command is not Dictionary or command.get("action") != "terminate":
		return false
	# The worker cannot consume this queue before readiness, which is set
	# on the main thread. A cancelled startup request never enters the pipe.
	io_mutex_.lock()
	for index in range(pending_lines_.size()):
		var query: Variant = JSON.parse_string(pending_lines_[index])
		if query is Dictionary and query.get("id") == command.get("terminateId"):
			pending_lines_.remove_at(index)
			io_mutex_.unlock()
			call_deferred(&"emit_cancelled_query_", query)
			return true
	io_mutex_.unlock()
	return false


func emit_cancelled_query_(query: Dictionary) -> void:
	for turn: Variant in query.get("analyzeTurns", []):
		line_received.emit(JSON.stringify({
			"id": query["id"], "turnNumber": turn,
			"isDuringSearch": false, "noResults": true,
		}))


func run_io_(pipe: FileAccess) -> void:
	while true:
		io_mutex_.lock()
		if io_stopping_:
			io_mutex_.unlock()
			return
		var line: String = ""
		if ready_ and not pending_lines_.is_empty():
			line = pending_lines_.pop_front()
		io_mutex_.unlock()
		collect_stdout_(pipe)
		if line.is_empty():
			OS.delay_msec(kIoPollMsec)
		elif not pipe.store_string(line + "\n"):
			# The API doesn't expose the byte count. Reusing this stream
			# could append another JSON request to a partially written line.
			io_mutex_.lock()
			write_failed_ = true
			io_mutex_.unlock()
			return


func collect_stdout_(pipe: FileAccess) -> void:
	var available_bytes: int = pipe.get_length()
	if available_bytes <= 0:
		return
	var chunk: PackedByteArray = pipe.get_buffer(available_bytes)
	io_mutex_.lock()
	received_stdout_.append_array(chunk)
	io_mutex_.unlock()


func stop_transport() -> void:
	if process_.is_empty():
		return
	stop_process_()
	transport_stopped.emit()


func stop_process_() -> void:
	io_mutex_.lock()
	io_stopping_ = true
	io_mutex_.unlock()
	var pid: int = int(process_.get("pid", -1))
	if pid > 0 and OS.is_process_running(pid):
		var _kill_error: Error = OS.kill(pid)
	# Terminating the child releases a write waiting for it to read stdin.
	if io_thread_.is_started():
		io_thread_.wait_to_finish()
	reset_transport_()


func reset_transport_() -> void:
	close_pipes_()
	process_.clear()
	stdout_buffer_.clear()
	stderr_buffer_ = ""
	stderr_error_summary_ = ""
	stderr_error_detail_lines_ = 0
	ready_ = false
	io_stopping_ = false
	write_failed_ = false
	pending_lines_.clear()
	received_stdout_.clear()
	set_process(false)


func is_transport_running() -> bool:
	if process_.is_empty():
		return false
	var pid: int = int(process_.get("pid", -1))
	return pid > 0 and OS.is_process_running(pid)


func _process(_delta: float) -> void:
	read_stderr_()
	var write_failed: bool = drain_stdout_()
	if process_.is_empty():
		return
	if write_failed and is_transport_running():
		stop_process_()
		transport_error.emit(tr("无法完整写入KataGo请求，请重新开始分析。"))
		transport_stopped.emit()
		return
	if is_transport_running():
		return
	io_mutex_.lock()
	io_stopping_ = true
	io_mutex_.unlock()
	io_thread_.wait_to_finish()
	collect_stdout_(process_["stdio"] as FileAccess)
	drain_stdout_()
	if process_.is_empty():
		return
	read_stderr_()
	flush_stderr_lines_(true)
	var message: String = tr("KataGo分析进程已意外退出，请查看详细日志。")
	if not stderr_error_summary_.is_empty():
		message = tr("KataGo分析进程异常退出：%s") % stderr_error_summary_
	reset_transport_()
	transport_error.emit(message)
	transport_stopped.emit()


func read_stderr_() -> void:
	var pipe: FileAccess = process_.get("stderr") as FileAccess
	if pipe == null:
		return
	var available_bytes: int = pipe.get_length()
	if available_bytes <= 0:
		return
	stderr_buffer_ += pipe.get_buffer(available_bytes).get_string_from_utf8()
	flush_stderr_lines_(false)


func drain_stdout_() -> bool:
	io_mutex_.lock()
	var chunk: PackedByteArray = received_stdout_
	received_stdout_ = PackedByteArray()
	var write_failed: bool = write_failed_
	io_mutex_.unlock()
	stdout_buffer_.append_array(chunk)
	flush_stdout_lines_()
	return write_failed


func flush_stdout_lines_() -> void:
	while not stdout_buffer_.is_empty():
		var newline_index: int = stdout_buffer_.find(10)
		if newline_index < 0:
			break
		var line_bytes: PackedByteArray = stdout_buffer_.slice(0, newline_index)
		stdout_buffer_ = stdout_buffer_.slice(newline_index + 1)
		var line: String = line_bytes.get_string_from_utf8().strip_edges()
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
	if not ready_ and line.ends_with(kReadyLogSuffix) and is_transport_running():
		io_mutex_.lock()
		ready_ = true
		io_mutex_.unlock()
		transport_ready.emit()
	print("KataGo: %s" % line)
	log_received.emit(line)
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
