class_name KataGoHumanTransport
extends KataGoTransport

var backend_: KataGoTransport


func start_transport() -> bool:
	if is_transport_running():
		return true
	if not SettingsStore.has_valid_katago_human_paths():
		transport_error.emit(tr("KataGo人类模仿棋模型或分析配置无效，请先打开设置检查。"))
		return false
	backend_ = KataGoAndroidTransport.new() if OS.get_name() == "Android" \
		else KataGoLocalTransport.new()
	add_child(backend_)
	backend_.line_received.connect(on_backend_line_received_)
	backend_.log_received.connect(on_backend_log_received_)
	backend_.transport_error.connect(on_backend_error_)
	backend_.transport_stopped.connect(on_backend_stopped_)
	if OS.get_name() == "Android":
		return bool(backend_.call("start_human_transport_with_override", ""))
	return bool(backend_.call("start_human_transport"))


func send_line(line: String) -> bool:
	return backend_ != null and backend_.send_line(line)


func stop_transport() -> void:
	if backend_ == null:
		return
	backend_.stop_transport()
	backend_.queue_free()
	backend_ = null


func is_transport_running() -> bool:
	return backend_ != null and backend_.is_transport_running()


func on_backend_stopped_() -> void:
	transport_stopped.emit()


func on_backend_line_received_(line: String) -> void:
	line_received.emit(line)


func on_backend_log_received_(line: String) -> void:
	log_received.emit(line)


func on_backend_error_(message: String) -> void:
	transport_error.emit(message)


func _exit_tree() -> void:
	stop_transport()
