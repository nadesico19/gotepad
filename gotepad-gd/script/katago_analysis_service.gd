class_name KataGoAnalysisService
extends Node

signal result_received(result: Dictionary)
signal service_error(message: String)
signal query_error(query_id: String, message: String)
signal service_warning(message: String)
signal running_changed(running: bool)

var transport_: KataGoTransport
var query_serial_: int = 0


func _ready() -> void:
	set_transport(KataGoLocalTransport.new())


func set_transport(transport: KataGoTransport) -> void:
	if transport_ != null:
		transport_.stop_transport()
		transport_.queue_free()
	transport_ = transport
	add_child(transport_)
	transport_.line_received.connect(on_transport_line_)
	transport_.transport_error.connect(on_transport_error_)
	transport_.transport_stopped.connect(on_transport_stopped_)


func next_query_id(prefix: String) -> String:
	query_serial_ += 1
	return "%s-%d-%d" % [prefix, Time.get_ticks_msec(), query_serial_]


func submit_query(query: Dictionary) -> bool:
	if transport_ == null:
		service_error.emit("KataGo分析传输层尚未初始化。")
		return false
	if not transport_.is_transport_running():
		if not transport_.start_transport():
			return false
		running_changed.emit(true)
	var line: String = JSON.stringify(query, "", false)
	if transport_.send_line(line):
		return true
	service_error.emit("无法向KataGo发送分析请求。")
	return false


func terminate_query(query_id: String) -> bool:
	if query_id.is_empty() or transport_ == null \
			or not transport_.is_transport_running():
		return false
	return submit_query({
		"id": next_query_id("terminate"),
		"action": "terminate",
		"terminateId": query_id
	})


func shutdown() -> void:
	if transport_ != null:
		transport_.stop_transport()


func is_running() -> bool:
	return transport_ != null and transport_.is_transport_running()


func on_transport_line_(line: String) -> void:
	var parsed: Variant = JSON.parse_string(line)
	if parsed is not Dictionary:
		service_error.emit("KataGo返回了无法解析的数据。")
		return
	var result: Dictionary = Dictionary(parsed)
	if result.has("error"):
		var query_id: String = str(result.get("id", ""))
		var message: String = str(result.get("error", "KataGo分析失败。"))
		if query_id.is_empty():
			service_error.emit(message)
		else:
			query_error.emit(query_id, message)
		return
	if result.has("warning"):
		service_warning.emit(str(result.get("warning", "KataGo分析警告。")))
		return
	result_received.emit(result)


func on_transport_error_(message: String) -> void:
	service_error.emit(message)


func on_transport_stopped_() -> void:
	running_changed.emit(false)


func _exit_tree() -> void:
	shutdown()
