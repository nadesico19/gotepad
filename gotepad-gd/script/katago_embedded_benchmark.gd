class_name KataGoEmbeddedBenchmark
extends Node

signal output_changed(output: String)
signal completed(succeeded: bool, search_threads: int, batch_size: int, message: String)

const kCandidates: Array[int] = [1, 2, 4, 6, 8]
const kWarmupVisits: int = 8
const kBenchmarkVisits: int = 64
const kMaxThreads: int = 8
const kMaxBatchSize: int = 4

var transport_: KataGoAndroidTransport
var output_: String = ""
var candidate_index_: int = -1
var query_id_: String = ""
var query_started_usec_: int = 0
var visits_per_second_: Dictionary = {}
var finishing_: bool = false


func start_benchmark() -> bool:
	if OS.get_name() != "Android":
		return false
	transport_ = KataGoAndroidTransport.new()
	add_child(transport_)
	transport_.line_received.connect(on_line_received_)
	transport_.log_received.connect(on_log_received_)
	transport_.transport_error.connect(on_transport_error_)
	transport_.transport_stopped.connect(on_transport_stopped_)
	append_output_(tr("正在准备 Android 内置 KataGo 性能检测…"))
	var override_config: String = (
		"numSearchThreadsPerAnalysisThread=%d,nnMaxBatchSize=%d"
		% [kMaxThreads, kMaxBatchSize]
	)
	if not transport_.start_transport_with_override(override_config):
		finish_(false, 0, 0, tr("无法启动内置 KataGo 性能检测。"))
		return false
	start_query_(true)
	return true


func cancel_benchmark() -> void:
	if finishing_:
		return
	finishing_ = true
	terminate_current_query_()
	stop_transport_()
	queue_free()


func start_query_(warmup: bool) -> void:
	var threads: int = kMaxThreads if warmup else kCandidates[candidate_index_]
	query_id_ = "embedded-benchmark-%s-%d" % [
		"warmup" if warmup else str(threads), Time.get_ticks_usec()
	]
	var visits: int = kWarmupVisits if warmup else kBenchmarkVisits
	var query: Dictionary = {
		"id": query_id_,
		"moves": [],
		"initialStones": [],
		"initialPlayer": "B",
		"rules": "chinese",
		"komi": 7.5,
		"boardXSize": 19,
		"boardYSize": 19,
		"maxVisits": visits,
		"analysisPVLen": 1,
		"overrideSettings": {"numSearchThreads": threads}
	}
	if not warmup:
		append_output_(tr("正在测试 %d 个搜索线程…") % threads)
	query_started_usec_ = Time.get_ticks_usec()
	if not transport_.send_line(JSON.stringify(query, "", false)):
		finish_(false, 0, 0, tr("无法向内置 KataGo 发送性能检测请求。"))


func on_line_received_(line: String) -> void:
	if finishing_:
		return
	var parsed: Variant = JSON.parse_string(line)
	if parsed is not Dictionary:
		return
	var result: Dictionary = Dictionary(parsed)
	if str(result.get("id", "")) != query_id_:
		return
	if result.has("error"):
		finish_(false, 0, 0, str(result.get("error", tr("性能检测失败。"))))
		return
	if bool(result.get("isDuringSearch", false)):
		return
	if candidate_index_ < 0:
		candidate_index_ = 0
		start_query_(false)
		return
	var elapsed_seconds: float = maxf(
		float(Time.get_ticks_usec() - query_started_usec_) / 1000000.0,
		0.001
	)
	var root_info: Dictionary = Dictionary(result.get("rootInfo", {}))
	var visits: int = int(root_info.get("visits", kBenchmarkVisits))
	var rate: float = float(visits) / elapsed_seconds
	var threads: int = kCandidates[candidate_index_]
	visits_per_second_[threads] = rate
	append_output_(
		"numSearchThreads = %d : visits/s = %.2f" % [threads, rate]
	)
	candidate_index_ += 1
	if candidate_index_ < kCandidates.size():
		start_query_(false)
	else:
		finish_success_()


func finish_success_() -> void:
	var best_threads: int = 0
	var best_rate: float = -1.0
	for key: Variant in visits_per_second_:
		var threads: int = int(key)
		var rate: float = float(visits_per_second_[key])
		if rate > best_rate:
			best_rate = rate
			best_threads = threads
	if best_threads <= 0:
		finish_(false, 0, 0, tr("性能检测没有取得有效结果。"))
		return
	var batch_size: int = maxi(2, ceili(float(best_threads) / 2.0))
	append_output_(tr("推荐配置：%d 个搜索线程，批量大小 %d") % [
		best_threads, batch_size
	])
	finish_(true, best_threads, batch_size, "")


func finish_(
		succeeded: bool,
		search_threads: int,
		batch_size: int,
		message: String
) -> void:
	if finishing_:
		return
	finishing_ = true
	stop_transport_()
	completed.emit(succeeded, search_threads, batch_size, message)
	queue_free()


func terminate_current_query_() -> void:
	if transport_ == null or query_id_.is_empty():
		return
	transport_.send_line(JSON.stringify({
		"id": "terminate-%d" % Time.get_ticks_usec(),
		"action": "terminate",
		"terminateId": query_id_
	}, "", false))


func stop_transport_() -> void:
	if transport_ != null:
		transport_.stop_transport()
		transport_ = null


func append_output_(line: String) -> void:
	if line.is_empty():
		return
	if not output_.is_empty():
		output_ += "\n"
	output_ += line
	output_changed.emit(output_)


func on_log_received_(line: String) -> void:
	append_output_(line)


func on_transport_error_(message: String) -> void:
	finish_(false, 0, 0, message)


func on_transport_stopped_() -> void:
	if not finishing_:
		finish_(false, 0, 0, tr("内置 KataGo 性能检测意外停止。"))


func _exit_tree() -> void:
	if transport_ != null:
		transport_.stop_transport()
