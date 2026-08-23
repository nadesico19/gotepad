class_name KataGoEmbeddedBenchmark
extends Node

signal output_changed(output: String)
signal completed(succeeded: bool, search_threads: int, batch_size: int, message: String)

const kCandidates: Array[int] = [1, 2, 4, 6, 8]
const kWarmupVisits: int = 8
const kBenchmarkVisits: int = 64
const kMaxThreads: int = 8
const kMaxBatchSize: int = 4
const kHumanBenchmarkVisits: int = 40
const kHumanCandidates: Array[Vector2i] = [
	Vector2i(1, 1),
	Vector2i(2, 1),
	Vector2i(2, 2),
	Vector2i(4, 2),
	Vector2i(4, 4),
	Vector2i(6, 4),
	Vector2i(8, 4),
]

var transport_: KataGoTransport
var output_: String = ""
var candidate_index_: int = -1
var query_id_: String = ""
var query_started_usec_: int = 0
var visits_per_second_: Dictionary = {}
var finishing_: bool = false
var human_model_: bool = false
var human_model_path_: String = ""
var human_candidate_index_: int = 0
var human_warming_up_: bool = true
var human_latencies_: Dictionary = {}


func _init(
		use_human_model: bool = false,
		human_model_path: String = ""
) -> void:
	human_model_ = use_human_model
	human_model_path_ = human_model_path.strip_edges()


func start_benchmark() -> bool:
	if OS.get_name() != "Android" and not human_model_:
		return false
	if human_model_:
		append_output_(tr("正在准备人类模仿棋端到端性能检测…"))
		append_output_(tr("检测会同时运行主分析模型和 Human SL 模型。"))
		return start_human_candidate_()
	return start_regular_benchmark_()


func start_regular_benchmark_() -> bool:
	transport_ = KataGoAndroidTransport.new()
	connect_transport_()
	append_output_(tr("正在准备 Android 内置 KataGo 性能检测…"))
	var override_config: String = (
		"numSearchThreadsPerAnalysisThread=%d,nnMaxBatchSize=%d"
		% [kMaxThreads, kMaxBatchSize]
	)
	var started: bool = bool(transport_.call(
		"start_transport_with_override", override_config
	))
	if not started:
		finish_(false, 0, 0, tr("无法启动内置 KataGo 性能检测。"))
		return false
	start_query_(true)
	return true


func start_human_candidate_() -> bool:
	if human_candidate_index_ >= kHumanCandidates.size():
		finish_human_success_()
		return true
	var candidate: Vector2i = kHumanCandidates[human_candidate_index_]
	append_output_(tr("正在测试仿人配置：%d线程，批量%d…") % [
		candidate.x, candidate.y
	])
	transport_ = KataGoAndroidTransport.new() if OS.get_name() == "Android" \
		else KataGoLocalTransport.new()
	connect_transport_()
	var model_path: String = human_model_path_ if not human_model_path_.is_empty() \
		else SettingsStore.get_android_external_katago_human_model_path()
	var override_config: String = (
		"numSearchThreadsPerAnalysisThread=%d,nnMaxBatchSize=%d"
		% [candidate.x, candidate.y]
	)
	var primary_model_path: String = "" if OS.get_name() == "Android" \
		else SettingsStore.get_katago_model_path()
	var started: bool = not model_path.is_empty() and bool(transport_.call(
		"start_custom_transport", primary_model_path, model_path,
		SettingsStore.get_managed_katago_human_analysis_config_path(),
		override_config
	))
	if not started:
		finish_(false, 0, 0, tr("无法启动内置 KataGo 性能检测。"))
		return false
	human_warming_up_ = true
	start_human_query_()
	return true


func connect_transport_() -> void:
	var source: KataGoTransport = transport_
	add_child(source)
	source.line_received.connect(on_line_received_.bind(source))
	source.log_received.connect(on_log_received_.bind(source))
	source.transport_error.connect(on_transport_error_.bind(source))
	source.transport_stopped.connect(on_transport_stopped_.bind(source))


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
	if human_model_:
		var overrides: Dictionary = Dictionary(query["overrideSettings"])
		overrides["humanSLProfile"] = "rank_1d"
		overrides["ignorePreRootHistory"] = false
		overrides["analysisIgnorePreRootHistory"] = false
		query["overrideSettings"] = overrides
		query["includePolicy"] = true
	if not warmup:
		append_output_(tr("正在测试 %d 个搜索线程…") % threads)
	query_started_usec_ = Time.get_ticks_usec()
	if not transport_.send_line(JSON.stringify(query, "", false)):
		finish_(false, 0, 0, tr("无法向内置 KataGo 发送性能检测请求。"))


func start_human_query_() -> void:
	var candidate: Vector2i = kHumanCandidates[human_candidate_index_]
	query_id_ = "human-benchmark-%s-%d-%d-%d" % [
		"warmup" if human_warming_up_ else "measure",
		candidate.x,
		candidate.y,
		Time.get_ticks_usec(),
	]
	var query: Dictionary = KataGoQueryBuilder.build_human_query(
		human_benchmark_context_(human_warming_up_),
		query_id_,
		KataGoQueryBuilder.kDefaultHumanProfile,
		kWarmupVisits if human_warming_up_ else kHumanBenchmarkVisits,
		60.0,
		2
	)
	var overrides: Dictionary = Dictionary(query.get("overrideSettings", {}))
	overrides["numSearchThreads"] = candidate.x
	query["overrideSettings"] = overrides
	query_started_usec_ = Time.get_ticks_usec()
	if not transport_.send_line(JSON.stringify(query, "", false)):
		finish_(false, 0, 0, tr("无法向内置 KataGo 发送性能检测请求。"))


func human_benchmark_context_(warmup: bool) -> Dictionary:
	var moves: Array = [
		["B", "Q16"], ["W", "D4"], ["B", "D16"], ["W", "Q4"],
		["B", "K16"], ["W", "K4"], ["B", "C10"], ["W", "Q10"],
	]
	if not warmup:
		moves.append_array([
			["B", "F17"], ["W", "F3"], ["B", "R14"], ["W", "C6"],
			["B", "J14"], ["W", "L6"], ["B", "E12"], ["W", "O7"],
			["B", "N16"], ["W", "D14"], ["B", "C4"], ["W", "R6"],
			["B", "H17"], ["W", "H3"], ["B", "P12"], ["W", "E8"],
		])
	return {
		"board_size": 19,
		"initialStones": [],
		"initialPlayer": "B",
		"moves": moves,
		"rules": "chinese",
		"komi": 7.5,
	}


func on_line_received_(line: String, source: KataGoTransport) -> void:
	if finishing_ or source != transport_:
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
	if human_model_:
		on_human_query_completed_(result)
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


func on_human_query_completed_(result: Dictionary) -> void:
	if human_warming_up_:
		human_warming_up_ = false
		start_human_query_()
		return
	var elapsed_seconds: float = maxf(
		float(Time.get_ticks_usec() - query_started_usec_) / 1000000.0,
		0.001
	)
	var root_info: Dictionary = Dictionary(result.get("rootInfo", {}))
	var visits: int = int(root_info.get("visits", kHumanBenchmarkVisits))
	var candidate: Vector2i = kHumanCandidates[human_candidate_index_]
	var key: String = "%d:%d" % [candidate.x, candidate.y]
	human_latencies_[key] = elapsed_seconds
	append_output_(
		"threads = %d, batch = %d : latency = %.3f s, visits/s = %.2f"
		% [candidate.x, candidate.y, elapsed_seconds,
			float(visits) / elapsed_seconds]
	)
	human_candidate_index_ += 1
	stop_transport_()
	call_deferred(&"start_human_candidate_")


func finish_human_success_() -> void:
	var best_candidate: Vector2i = Vector2i.ZERO
	var best_latency: float = INF
	for candidate: Vector2i in kHumanCandidates:
		var key: String = "%d:%d" % [candidate.x, candidate.y]
		if not human_latencies_.has(key):
			continue
		var latency: float = float(human_latencies_[key])
		if latency < best_latency:
			best_latency = latency
			best_candidate = candidate
	if best_candidate == Vector2i.ZERO:
		finish_(false, 0, 0, tr("性能检测没有取得有效结果。"))
		return
	append_output_(tr("推荐仿人配置：%d线程，批量%d，单次选点%.3f秒") % [
		best_candidate.x, best_candidate.y, best_latency
	])
	finish_(true, best_candidate.x, best_candidate.y, "")


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
		var transport: KataGoTransport = transport_
		transport_ = null
		transport.stop_transport()
		transport.queue_free()


func append_output_(line: String) -> void:
	if line.is_empty():
		return
	if not output_.is_empty():
		output_ += "\n"
	output_ += line
	output_changed.emit(output_)


func on_log_received_(line: String, source: KataGoTransport) -> void:
	if source != transport_:
		return
	append_output_(line)


func on_transport_error_(message: String, source: KataGoTransport) -> void:
	if source != transport_:
		return
	finish_(false, 0, 0, message)


func on_transport_stopped_(source: KataGoTransport) -> void:
	if source != transport_:
		return
	if not finishing_:
		finish_(false, 0, 0, tr("内置 KataGo 性能检测意外停止。"))


func _exit_tree() -> void:
	if transport_ != null:
		transport_.stop_transport()
