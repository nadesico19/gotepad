class_name KataGoEmbeddedBenchmark
extends Node

signal output_changed(output: String)
signal completed(succeeded: bool, search_threads: int, batch_size: int, message: String)

const kRegularThreadCandidates: Array[int] = [1, 2, 4, 8, 16, 32]
const kRegularBatchCandidates: Array[int] = [1, 2, 4, 8, 16, 32]
const kRegularBenchmarkVisits: int = 128
const kRegularNnBenchmarkDurationMillis: int = 1500
const kRegularWarmupDurationMillis: int = 10000
const kRegularRetestCandidateCount: int = 4
const kRegularSelectionTolerance: float = 1.05
const kRegularReportPath: String = \
	"user://katago/benchmark-latest.jsonl"
const kRegularPhaseInitialStats: int = 1
const kRegularPhaseNnBenchmark: int = 2
const kRegularPhaseWarmup: int = 3
const kRegularPhasePrepareSearch: int = 4
const kRegularPhaseSearch: int = 5
const kRegularPhaseSearchStats: int = 6
const kHumanCandidates: Array[Vector2i] = [
	Vector2i(4, 2),
	Vector2i(1, 1),
	Vector2i(8, 4),
	Vector2i(2, 1),
	Vector2i(6, 4),
	Vector2i(2, 2),
	Vector2i(4, 4),
]
const kHumanSimpleCandidateTolerance: float = 1.08
const kHumanCandidateMaxRetries: int = 2

var acceleration_status_text_: String = ""
var acceleration_wait_count_: int = 0
var o3_validation_mode_: bool = false
var o3_validation_index_: int = 0
var o3_validation_run_id_: String = ""

var transport_: KataGoTransport
var output_: String = ""
var query_id_: String = ""
var query_started_usec_: int = 0
var finishing_: bool = false
var regular_phase_: int = 0
var regular_nn_candidates_: Array[int] = []
var regular_nn_candidate_index_: int = 0
var regular_search_candidates_: Array[Vector2i] = []
var regular_search_candidate_index_: int = 0
var regular_search_retesting_: bool = false
var regular_search_samples_: Dictionary = {}
var regular_search_retest_samples_: Dictionary = {}
var regular_retest_candidates_: Array[Vector2i] = []
var regular_pending_sample_: Dictionary = {}
var regular_report_records_: Array[Dictionary] = []
var human_model_: bool = false
var human_model_path_: String = ""
var human_benchmark_visits_: int = SettingsStore.kDefaultKatagoHumanMaxVisits
var human_candidates_: Array[Vector2i] = []
var human_candidate_index_: int = 0
var human_warming_up_: bool = true
var human_retesting_: bool = false
var human_latency_samples_: Dictionary = {}
var human_candidate_retry_count_: int = 0
var human_transport_starting_: bool = false


func _init(
		use_human_model: bool = false,
		human_model_path: String = "",
		human_benchmark_visits: int = SettingsStore.kDefaultKatagoHumanMaxVisits
) -> void:
	human_model_ = use_human_model
	human_model_path_ = human_model_path.strip_edges()
	human_benchmark_visits_ = maxi(human_benchmark_visits, 1)


func _notification(what: int) -> void:
	if OS.get_name() == "iOS" and what == NOTIFICATION_APPLICATION_PAUSED \
			and not finishing_:
		finish_(false, 0, 0, tr("应用进入后台，性能检测已停止，请返回前台后重新开始。"))


func start_benchmark() -> bool:
	if OS.get_name() not in ["Android", "iOS"] and not human_model_:
		return false
	if human_model_:
		append_output_(tr("正在准备人类模仿棋端到端性能检测…"))
		append_output_(tr("检测会同时运行主分析模型和 Human SL 模型。"))
		append_output_(tr("本次按 %d visits 检测仿人棋配置。") % \
			human_benchmark_visits_)
		human_candidates_ = kHumanCandidates.duplicate()
		return start_human_candidate_()
	return start_regular_benchmark_()


func start_o3_validation() -> bool:
	o3_validation_mode_ = true
	o3_validation_run_id_ = "%d-%d" % [int(Time.get_unix_time_from_system() * 1000), Time.get_ticks_usec()]
	if OS.get_name() != "Android":
		finish_(false, 0, 0, tr("数值验证需要 Android OpenCL 后端。"))
		return false
	var host: Variant = JavaClassWrapper.wrap(KataGoOpenCLTransport.kAndroidHostClass)
	if host == null:
		finish_(false, 0, 0, tr("数值验证需要 Android OpenCL 后端。"))
		return false
	host.protectKataGoValidationHistory(o3_validation_run_id_, true)
	append_regular_report_("validationStart", {
		"runId": o3_validation_run_id_,
		"deviceModel": OS.get_model_name(), "osVersion": OS.get_version(),
		"batchSizes": kRegularBatchCandidates, "caseCount": 32,
		"numericalAcceptance": "not_evaluated",
	})
	transport_ = KataGoOpenCLTransport.new()
	connect_transport_()
	append_output_(tr("正在验证特定模型加速内核；使用已保存的分析模型。"))
	append_output_(tr("自动对照原内核与实验内核，不改变已保存设置；诊断采样关闭。"))
	append_output_(tr("覆盖 32 个固定生成局面、6 种真实批量及两种排列；完成后需要审核误差。"))
	var started: bool = bool(transport_.call("start_transport_with_override",
		"numSearchThreadsPerAnalysisThread=1,nnMaxBatchSize=1,gotepadO3Profile=false,gotepadO3Optimize=false,gotepadO3Validation=true,gotepadO3ValidationRunId=" + o3_validation_run_id_))
	if not started:
		finish_(false, 0, 0, tr("无法启动数值验证。"))
		return false
	send_next_o3_validation_()
	return true


func send_next_o3_validation_() -> void:
	if o3_validation_index_ >= kRegularBatchCandidates.size():
		append_output_(tr("全部批量验证已完成，报告待审核；这不等于数值正确性已通过。"))
		finish_(true, 0, 0, tr("数值验证已完成，报告待审核。"))
		return
	var batch_size: int = kRegularBatchCandidates[o3_validation_index_]
	append_output_(tr("正在验证实际 batch %d：重复性、新旧内核、单条与批量一致性…") % batch_size)
	send_regular_action_("validate_o3_nn", {"batchSize": batch_size})


func on_o3_validation_response_(result: Dictionary) -> void:
	var validation: Dictionary = Dictionary(result.get("validation", {}))
	var expected_batch: int = kRegularBatchCandidates[o3_validation_index_]
	if validation.is_empty() or int(validation.get("batchSize", 0)) != expected_batch:
		finish_(false, 0, 0, tr("数值验证未返回完整结果。"))
		return
	append_regular_report_("validation", validation)
	append_output_(tr("批量 %d 的报告：%s") % [expected_batch, str(validation.get("reportPath", ""))])
	var all_metrics: Dictionary = Dictionary(validation.get("maxAbsByComparison", {}))
	var metrics: Dictionary = Dictionary(all_metrics.get("originalVsCandidate", {}))
	append_output_(tr("新旧内核最大绝对差：落子概率 %.6f，胜率 %.6f，目差 %.6f，归属 %.6f") % [
		float(metrics.get("legalPolicyProbability", 0.0)), float(metrics.get("whiteWinProbability", 0.0)),
		float(metrics.get("whiteScoreMeanPoints", 0.0)), float(metrics.get("whiteOwnership", 0.0))])
	if str(validation.get("status", "")) != "completed_needs_review":
		finish_(false, 0, 0, tr("发现非有限值或验证不完整，请检查报告。"))
		return
	o3_validation_index_ += 1
	send_next_o3_validation_()


func start_regular_benchmark_() -> bool:
	# Benchmark only the requested OpenCL backend. Falling back to Eigen here
	# would produce a valid-looking result for the wrong implementation.
	transport_ = KataGoOpenCLTransport.new() if OS.get_name() == "Android" \
		else KataGoEmbeddedTransport.new()
	connect_transport_()
	append_output_(tr("正在准备内置 KataGo 性能检测…"))
	append_output_(tr("检测将分别测量纯神经网络吞吐量和真实搜索性能。"))
	var host: Variant = null
	if OS.get_name() == "Android":
		host = JavaClassWrapper.wrap(KataGoOpenCLTransport.kAndroidHostClass)
	if host != null:
		append_output_(tr("特定模型加速开关：%s（按已保存设置，实际状态将在模型加载后显示）") % (
			tr("已开启") if SettingsStore.get_katago_o3_optimize() else tr("已关闭")
		))
	append_regular_report_("environment", {
		"platform": OS.get_name(),
		"o3OptimizeRequested": SettingsStore.get_katago_o3_optimize(),
		"o3ProfileRequested": false,
		"deviceModel": OS.get_model_name(),
		"osVersion": OS.get_version(),
		"engineVersion": Engine.get_version_info(),
	})
	var override_config: String = (
		"numSearchThreadsPerAnalysisThread=%d,nnMaxBatchSize=%d"
		% [
			kRegularThreadCandidates[kRegularThreadCandidates.size() - 1],
			kRegularBatchCandidates[kRegularBatchCandidates.size() - 1],
		]
	)
	# Diagnostic sampling must not affect throughput or thread selection.
	if OS.get_name() == "Android":
		override_config += ",gotepadO3Profile=false"
	var started: bool = bool(transport_.call(
		"start_transport_with_override", override_config
	))
	if not started:
		finish_(false, 0, 0, tr("无法启动内置 KataGo 性能检测。"))
		return false
	regular_phase_ = kRegularPhaseInitialStats
	send_regular_action_("query_runtime_stats")
	return true


func start_human_candidate_() -> bool:
	if human_candidate_index_ >= human_candidates_.size():
		if not human_retesting_ and prepare_human_retest_():
			return start_human_candidate_()
		finish_human_success_()
		return true
	var candidate: Vector2i = human_candidates_[human_candidate_index_]
	var status_text: String = "复测候选配置：%d线程，批量%d…" \
		if human_retesting_ else "正在测试仿人配置：%d线程，批量%d…"
	append_output_(tr(status_text) % [
		candidate.x, candidate.y
	])
	transport_ = KataGoOpenCLTransport.new() if OS.get_name() == "Android" \
		else KataGoEmbeddedTransport.new() if OS.get_name() == "iOS" \
		else KataGoLocalTransport.new()
	connect_transport_()
	var model_path: String = human_model_path_ if not human_model_path_.is_empty() \
		else SettingsStore.get_android_external_katago_human_model_path()
	var override_config: String = (
		"numSearchThreadsPerAnalysisThread=%d,nnMaxBatchSize=%d"
		% [candidate.x, candidate.y]
	)
	var primary_model_path: String = "" if OS.get_name() in ["Android", "iOS"] \
		else SettingsStore.get_katago_model_path()
	human_transport_starting_ = true
	if OS.get_name() == "Android":
		override_config += ",gotepadO3Profile=false"
	var started: bool = not model_path.is_empty() and bool(transport_.call(
		"start_custom_transport", primary_model_path, model_path,
		SettingsStore.get_managed_katago_human_analysis_config_path(),
		override_config
	))
	human_transport_starting_ = false
	if not started:
		finish_(false, 0, 0, tr("无法启动内置 KataGo 性能检测。"))
		return false
	human_warming_up_ = true
	acceleration_wait_count_ = 0
	if OS.get_name() == "Android":
		send_regular_action_("query_runtime_stats")
	else:
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
	if o3_validation_mode_:
		append_regular_report_("validationEnd", {"status": "canceled", "completedBatches": o3_validation_index_})
		write_regular_report_()
	finishing_ = true
	terminate_current_query_()
	stop_transport_()
	queue_free()


func configure_regular_candidates_(max_batch_size: int) -> void:
	regular_nn_candidates_.clear()
	for batch_size: int in kRegularBatchCandidates:
		if batch_size <= max_batch_size:
			regular_nn_candidates_.append(batch_size)
	if regular_nn_candidates_.is_empty() \
			or regular_nn_candidates_[regular_nn_candidates_.size() - 1] \
				< max_batch_size:
		regular_nn_candidates_.append(max_batch_size)
	regular_search_candidates_.clear()
	for threads: int in kRegularThreadCandidates:
		for batch_size: int in regular_nn_candidates_:
			if batch_size <= threads:
				regular_search_candidates_.append(
					Vector2i(threads, batch_size)
				)


func send_regular_action_(action: String, values: Dictionary = {}) -> void:
	query_id_ = "embedded-benchmark-%s-%d" % [
		action, Time.get_ticks_usec()
	]
	var request: Dictionary = {"id": query_id_, "action": action}
	for key: Variant in values:
		request[key] = values[key]
	if not transport_.send_line(JSON.stringify(request, "", false)):
		finish_(false, 0, 0, tr("无法向内置 KataGo 发送性能检测请求。"))


func start_regular_nn_benchmark_() -> void:
	if regular_nn_candidate_index_ >= regular_nn_candidates_.size():
		start_regular_warmup_()
		return
	var batch_size: int = regular_nn_candidates_[regular_nn_candidate_index_]
	regular_phase_ = kRegularPhaseNnBenchmark
	append_output_(tr("正在测试纯神经网络批量 %d…") % batch_size)
	send_regular_action_("benchmark_nn", {
		"batchSize": batch_size,
		"durationMillis": kRegularNnBenchmarkDurationMillis,
	})


func start_regular_warmup_() -> void:
	var batch_size: int = regular_nn_candidates_[
		regular_nn_candidates_.size() - 1
	]
	regular_phase_ = kRegularPhaseWarmup
	append_output_(tr("正在进行持续负载预热，以测量热态性能…"))
	send_regular_action_("benchmark_nn", {
		"batchSize": batch_size,
		"durationMillis": kRegularWarmupDurationMillis,
	})


func start_regular_search_candidate_() -> void:
	if regular_search_candidate_index_ >= regular_search_candidates_.size():
		if not regular_search_retesting_ and prepare_regular_search_retest_():
			start_regular_search_candidate_()
			return
		finish_regular_success_()
		return
	var candidate: Vector2i = \
		regular_search_candidates_[regular_search_candidate_index_]
	var status: String = "正在复测搜索配置：%d线程，批量%d…" \
		if regular_search_retesting_ else "正在测试搜索配置：%d线程，批量%d…"
	append_output_(tr(status) % [candidate.x, candidate.y])
	regular_phase_ = kRegularPhasePrepareSearch
	send_regular_action_("prepare_benchmark", {"batchSize": candidate.y})


func start_regular_search_query_() -> void:
	var candidate: Vector2i = \
		regular_search_candidates_[regular_search_candidate_index_]
	query_id_ = "embedded-search-%d-%d-%d" % [
		candidate.x, candidate.y, Time.get_ticks_usec()
	]
	var query: Dictionary = {
		"id": query_id_,
		"moves": [
			["B", "Q16"], ["W", "D4"], ["B", "D16"], ["W", "Q4"],
			["B", "K16"], ["W", "K4"], ["B", "C10"], ["W", "Q10"],
			["B", "F17"], ["W", "F3"], ["B", "R14"], ["W", "C6"],
			["B", "J14"], ["W", "L6"], ["B", "E12"], ["W", "O7"],
		],
		"initialStones": [],
		"initialPlayer": "B",
		"rules": "chinese",
		"komi": 7.5,
		"boardXSize": 19,
		"boardYSize": 19,
		"maxVisits": kRegularBenchmarkVisits,
		"analysisPVLen": 1,
		"overrideSettings": {"numSearchThreads": candidate.x},
	}
	regular_phase_ = kRegularPhaseSearch
	query_started_usec_ = Time.get_ticks_usec()
	if not transport_.send_line(JSON.stringify(query, "", false)):
		finish_(false, 0, 0, tr("无法向内置 KataGo 发送性能检测请求。"))


func start_human_query_() -> void:
	var candidate: Vector2i = human_candidates_[human_candidate_index_]
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
		human_warmup_visits_() if human_warming_up_ \
			else human_benchmark_visits_,
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
	if o3_validation_mode_:
		on_o3_validation_response_(result)
		return
	if human_model_:
		if result.has("nn"):
			var stats: Dictionary = Dictionary(result["nn"])
			report_model_acceleration_(stats)
			if not bool(Dictionary(stats.get("modelAcceleration", {})).get("available", false)):
				acceleration_wait_count_ += 1
				if acceleration_wait_count_ > 120:
					finish_(false, 0, 0, tr("无法确认模型加速状态，未开始测速。"))
					return
				await get_tree().create_timer(0.25).timeout
				if not finishing_:
					send_regular_action_("query_runtime_stats")
				return
			start_human_query_()
			return
		on_human_query_completed_(result)
		return
	on_regular_response_(result)


func report_model_acceleration_(stats: Dictionary) -> void:
	var status: Dictionary = Dictionary(stats.get("modelAcceleration", {}))
	if status.is_empty():
		return
	var reasons: Dictionary = {
		"initializing": tr("正在初始化，尚未确认启用"),
		"disabled_by_setting": tr("开关未开启，使用原实现"),
		"model_not_supported": tr("模型结构不兼容，使用原实现"),
		"unsupported_structure": tr("网络结构或输入格式暂不支持，使用原实现"),
		"no_compatible_operators": tr("未找到兼容的加速算子，使用原实现"),
		"board_not_supported": tr("棋盘条件不满足，使用原实现"),
		"precision_not_supported": tr("当前后端精度配置不满足旧版加速条件，使用原实现"),
		"fp16_storage_not_enabled": tr("当前后端未启用 FP16 存储，使用原实现"),
		"tensor_core_layout_not_supported": tr("当前 1×1 矩阵计算路径不兼容，使用原实现"),
		"device_fp16_not_supported": tr("设备未提供实验内核所需的 FP16 能力，使用原实现"),
		"device_capability_query_failed": tr("设备 FP16 能力查询失败，使用原实现"),
		"kernel_compilation_failed": tr("实验内核编译失败，使用原实现"),
		"kernel_initialization_failed": tr("加速内核初始化失败，使用原实现"),
		"kernel_failed": tr("加速内核运行失败，已回退原实现"),
		"enabled": tr("加速路径已启用"),
	}
	var compatibility: String = tr("未确认")
	if bool(status.get("available", false)):
		compatibility = tr("兼容") if bool(status.get("structureSupported", false)) else tr("不兼容")
	var message: String = tr("模型：%s；结构适配：%s；实际状态：%s") % [
		str(stats.get("modelInternalName", "")),
		compatibility,
		str(reasons.get(str(status.get("reason", "")), tr("状态未知"))),
	]
	var structure: Dictionary = Dictionary(status.get("structure", {}))
	if not structure.is_empty():
		message += tr("；结构类型：%s；候选内核数量（单路、FFN 融合、QKV 融合）：%s") % [
			str(structure.get("family", "")), str(structure.get("kernelCandidates", []))]
	var precision: Dictionary = Dictionary(status.get("precision", {}))
	if bool(status.get("enabled", false)) and not precision.is_empty() \
			and not bool(precision.get("backendFP16Compute", false)):
		message += tr("；原后端未启用 FP16 计算，实验内核独立使用 FP16，请先进行数值验证")
	if message != acceleration_status_text_:
		acceleration_status_text_ = message
		append_output_(message)
		append_regular_report_("modelAcceleration", status)


func on_regular_response_(result: Dictionary) -> void:
	var runtime: Dictionary = Dictionary(result.get("nn", result.get("benchmark", {})))
	report_model_acceleration_(runtime)
	match regular_phase_:
		kRegularPhaseInitialStats:
			var stats: Dictionary = Dictionary(result.get("nn", {}))
			var acceleration: Dictionary = Dictionary(stats.get("modelAcceleration", {}))
			if OS.get_name() == "Android" and not bool(acceleration.get("available", false)):
				acceleration_wait_count_ += 1
				if acceleration_wait_count_ > 120:
					finish_(false, 0, 0, tr("无法确认模型加速状态，未开始测速。请检查后端或更新应用。"))
					return
				await get_tree().create_timer(0.25).timeout
				if not finishing_:
					send_regular_action_("query_runtime_stats")
				return
			var max_batch_size: int = int(stats.get("maxBatchSize", 0))
			if max_batch_size <= 0:
				finish_(false, 0, 0, tr("内置 KataGo 没有返回有效的最大批量。"))
				return
			configure_regular_candidates_(max_batch_size)
			append_output_(
				"NN buffer = %dx%d, max batch = %d, FP16 = %s (%s)" % [
					int(stats.get("nnXLen", 0)), int(stats.get("nnYLen", 0)),
					int(stats.get("maxBatchSize", 0)),
					str(stats.get("usingFP16", false)),
					str(stats.get("requestedFP16Mode", "unknown")),
				]
			)
			append_output_(tr("已按后端实际最大批量 %d 调整检测范围。") % \
				max_batch_size)
			append_regular_report_("runtime", stats)
			regular_nn_candidate_index_ = 0
			start_regular_nn_benchmark_()
		kRegularPhaseNnBenchmark:
			on_regular_nn_benchmark_completed_(result)
		kRegularPhaseWarmup:
			on_regular_warmup_completed_(result)
		kRegularPhasePrepareSearch:
			start_regular_search_query_()
		kRegularPhaseSearch:
			on_regular_search_completed_(result)
		kRegularPhaseSearchStats:
			on_regular_search_stats_received_(result)
		_:
			finish_(false, 0, 0, tr("性能检测收到未知阶段的结果。"))


func on_regular_nn_benchmark_completed_(result: Dictionary) -> void:
	var benchmark: Dictionary = Dictionary(result.get("benchmark", {}))
	if benchmark.is_empty():
		finish_(false, 0, 0, tr("纯神经网络性能检测没有返回有效结果。"))
		return
	append_output_(
		"NN batch = %d : positions/s = %.2f, actual batch = %.2f" % [
			int(benchmark.get("requestedBatchSize", 0)),
			float(benchmark.get("positionsPerSecond", 0.0)),
			float(benchmark.get("averageBatchSize", 0.0)),
		]
	)
	append_regular_report_("nn", benchmark)
	regular_nn_candidate_index_ += 1
	start_regular_nn_benchmark_()


func on_regular_warmup_completed_(result: Dictionary) -> void:
	var benchmark: Dictionary = Dictionary(result.get("benchmark", {}))
	if benchmark.is_empty():
		finish_(false, 0, 0, tr("持续负载预热没有返回有效结果。"))
		return
	append_output_(
		tr("预热完成：%.2f positions/s，实际批量 %.2f") % [
			float(benchmark.get("positionsPerSecond", 0.0)),
			float(benchmark.get("averageBatchSize", 0.0)),
		]
	)
	append_regular_report_("warmup", benchmark)
	regular_search_candidate_index_ = 0
	start_regular_search_candidate_()


func on_regular_search_completed_(result: Dictionary) -> void:
	var elapsed_seconds: float = maxf(
		float(Time.get_ticks_usec() - query_started_usec_) / 1000000.0,
		0.001
	)
	var root_info: Dictionary = Dictionary(result.get("rootInfo", {}))
	var visits: int = int(root_info.get("visits", kRegularBenchmarkVisits))
	var rate: float = float(visits) / elapsed_seconds
	var candidate: Vector2i = \
		regular_search_candidates_[regular_search_candidate_index_]
	regular_pending_sample_ = {
		"threads": candidate.x,
		"batch": candidate.y,
		"visits": visits,
		"elapsedSeconds": elapsed_seconds,
		"visitsPerSecond": rate,
		"retest": regular_search_retesting_,
	}
	regular_phase_ = kRegularPhaseSearchStats
	send_regular_action_("query_runtime_stats")


func on_regular_search_stats_received_(result: Dictionary) -> void:
	var stats: Dictionary = Dictionary(result.get("nn", {}))
	var sample: Dictionary = regular_pending_sample_.duplicate(true)
	sample["nn"] = stats
	var threads: int = int(sample.get("threads", 0))
	var batch_size: int = int(sample.get("batch", 0))
	var rate: float = float(sample.get("visitsPerSecond", 0.0))
	var key: String = "%d:%d" % [threads, batch_size]
	if regular_search_retesting_:
		var retest_samples: Array = regular_search_retest_samples_.get(key, [])
		retest_samples.append(rate)
		regular_search_retest_samples_[key] = retest_samples
	else:
		var samples: Array = regular_search_samples_.get(key, [])
		samples.append(rate)
		regular_search_samples_[key] = samples
	append_output_(
		"threads = %d, batch = %d : visits/s = %.2f, NN rows/s = %.2f, actual batch = %.2f, cache hits = %d" % [
			threads, batch_size, rate,
			float(stats.get("rows", 0)) /
				maxf(float(sample.get("elapsedSeconds", 0.0)), 0.001),
			float(stats.get("averageBatchSize", 0.0)),
			int(stats.get("cacheHits", 0)),
		]
	)
	append_regular_report_("search", sample)
	regular_pending_sample_.clear()
	regular_search_candidate_index_ += 1
	start_regular_search_candidate_()


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
	var visits: int = int(root_info.get("visits", human_benchmark_visits_))
	var candidate: Vector2i = human_candidates_[human_candidate_index_]
	var key: String = "%d:%d" % [candidate.x, candidate.y]
	var samples: Array = human_latency_samples_.get(key, [])
	samples.append(elapsed_seconds)
	human_latency_samples_[key] = samples
	append_output_(
		"threads = %d, batch = %d : latency = %.3f s, visits/s = %.2f"
		% [candidate.x, candidate.y, elapsed_seconds,
			float(visits) / elapsed_seconds]
	)
	human_candidate_retry_count_ = 0
	human_candidate_index_ += 1
	stop_transport_(Callable(self, "start_human_candidate_"))


func recover_human_candidate_(message: String) -> void:
	var candidate: Vector2i = human_candidates_[human_candidate_index_]
	if human_candidate_retry_count_ < kHumanCandidateMaxRetries:
		human_candidate_retry_count_ += 1
		append_output_(tr(
			"配置 %d线程、批量%d 的 OpenCL 服务异常，正在重试（%d/%d）…"
		) % [candidate.x, candidate.y, human_candidate_retry_count_,
			kHumanCandidateMaxRetries])
		if not message.strip_edges().is_empty():
			append_output_(message)
		stop_transport_(Callable(self, "start_human_candidate_"))
		return
	append_output_(tr(
		"配置 %d线程、批量%d 连续失败，已跳过并继续检测其他配置。"
	) % [candidate.x, candidate.y])
	if not message.strip_edges().is_empty():
		append_output_(message)
	human_candidate_retry_count_ = 0
	human_candidate_index_ += 1
	stop_transport_(Callable(self, "start_human_candidate_"))


func finish_human_success_() -> void:
	var fastest_candidate: Vector2i = Vector2i.ZERO
	var best_latency: float = INF
	for candidate: Vector2i in kHumanCandidates:
		var latency: float = human_average_latency_(candidate)
		if not is_finite(latency):
			continue
		if latency < best_latency:
			best_latency = latency
			fastest_candidate = candidate
	if fastest_candidate == Vector2i.ZERO:
		finish_(false, 0, 0, tr("性能检测没有取得有效结果。"))
		return
	var best_candidate: Vector2i = fastest_candidate
	var best_cost: int = fastest_candidate.x * fastest_candidate.y
	for candidate: Vector2i in kHumanCandidates:
		var latency: float = human_average_latency_(candidate)
		var cost: int = candidate.x * candidate.y
		if is_finite(latency) \
				and latency <= best_latency * kHumanSimpleCandidateTolerance \
				and (cost < best_cost or (cost == best_cost \
					and candidate.x < best_candidate.x)):
			best_candidate = candidate
			best_cost = cost
	var selected_latency: float = human_average_latency_(best_candidate)
	append_output_(tr("推荐仿人配置：%d线程，批量%d，单次选点%.3f秒") % [
		best_candidate.x, best_candidate.y, selected_latency
	])
	finish_(true, best_candidate.x, best_candidate.y, "")


func human_warmup_visits_() -> int:
	return clampi(roundi(float(human_benchmark_visits_) * 0.125), 8, 64)


func human_average_latency_(candidate: Vector2i) -> float:
	var key: String = "%d:%d" % [candidate.x, candidate.y]
	var samples: Array = human_latency_samples_.get(key, [])
	if samples.is_empty():
		return INF
	var total: float = 0.0
	for sample: Variant in samples:
		total += float(sample)
	return total / float(samples.size())


func prepare_human_retest_() -> bool:
	var first: Vector2i = Vector2i.ZERO
	var second: Vector2i = Vector2i.ZERO
	var first_latency: float = INF
	var second_latency: float = INF
	for candidate: Vector2i in kHumanCandidates:
		var latency: float = human_average_latency_(candidate)
		if latency < first_latency:
			second = first
			second_latency = first_latency
			first = candidate
			first_latency = latency
		elif latency < second_latency:
			second = candidate
			second_latency = latency
	if first == Vector2i.ZERO:
		return false
	human_candidates_.clear()
	human_candidates_.append(first)
	if second != Vector2i.ZERO:
		human_candidates_.append(second)
	human_candidate_index_ = 0
	human_retesting_ = true
	append_output_(tr("将复测最快的候选配置，以降低首次运行和设备温度的影响。"))
	return true


func regular_average_rate_(candidate: Vector2i) -> float:
	var key: String = "%d:%d" % [candidate.x, candidate.y]
	var samples: Array = regular_search_samples_.get(key, [])
	if samples.is_empty():
		return -1.0
	var total: float = 0.0
	for sample: Variant in samples:
		total += float(sample)
	return total / float(samples.size())


func regular_retest_average_rate_(candidate: Vector2i) -> float:
	var key: String = "%d:%d" % [candidate.x, candidate.y]
	var samples: Array = regular_search_retest_samples_.get(key, [])
	if samples.is_empty():
		return -1.0
	var total: float = 0.0
	for sample: Variant in samples:
		total += float(sample)
	return total / float(samples.size())


func regular_measured_candidates_() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for key_value: Variant in regular_search_samples_:
		var fields: PackedStringArray = str(key_value).split(":", false, 1)
		if fields.size() == 2:
			result.append(Vector2i(int(fields[0]), int(fields[1])))
	return result


func prepare_regular_search_retest_() -> bool:
	var remaining: Array[Vector2i] = regular_measured_candidates_()
	if remaining.is_empty():
		return false
	regular_retest_candidates_.clear()
	var candidate_count: int = mini(
		kRegularRetestCandidateCount, remaining.size()
	)
	while regular_retest_candidates_.size() < candidate_count:
		var fastest: Vector2i = Vector2i.ZERO
		var fastest_rate: float = -1.0
		for candidate: Vector2i in remaining:
			var rate: float = regular_average_rate_(candidate)
			if rate > fastest_rate:
				fastest = candidate
				fastest_rate = rate
		if fastest == Vector2i.ZERO:
			break
		regular_retest_candidates_.append(fastest)
		remaining.erase(fastest)
	if regular_retest_candidates_.is_empty():
		return false
	regular_search_candidates_.clear()
	# Run two passes in opposite order. Each candidate's two samples are then
	# centered at roughly the same point in the device's thermal timeline.
	for candidate: Vector2i in regular_retest_candidates_:
		regular_search_candidates_.append(candidate)
	for index: int in range(
		regular_retest_candidates_.size() - 1, -1, -1
	):
		regular_search_candidates_.append(regular_retest_candidates_[index])
	regular_search_candidate_index_ = 0
	regular_search_retesting_ = true
	append_output_(tr(
		"将对最快的 %d 组配置进行两轮反向热态复测。"
	) % regular_retest_candidates_.size())
	return true


func finish_regular_success_() -> void:
	var fastest_candidate: Vector2i = Vector2i.ZERO
	var fastest_rate: float = -1.0
	# Select exclusively from the symmetric hot retests. The initial scan is
	# intentionally used only to shortlist candidates because its early samples
	# still benefit from a colder device.
	for candidate: Vector2i in regular_retest_candidates_:
		var rate: float = regular_retest_average_rate_(candidate)
		if rate > fastest_rate:
			fastest_rate = rate
			fastest_candidate = candidate
	if fastest_candidate == Vector2i.ZERO:
		finish_(false, 0, 0, tr("性能检测没有取得有效结果。"))
		return
	var selected: Vector2i = fastest_candidate
	var minimum_acceptable_rate: float = \
		fastest_rate / kRegularSelectionTolerance
	for candidate: Vector2i in regular_retest_candidates_:
		var rate: float = regular_retest_average_rate_(candidate)
		if rate >= minimum_acceptable_rate \
				and (candidate.x < selected.x \
				or (candidate.x == selected.x and candidate.y < selected.y)):
			selected = candidate
	var selected_rate: float = regular_retest_average_rate_(selected)
	var selected_key: String = "%d:%d" % [selected.x, selected.y]
	var fastest_key: String = "%d:%d" % [
		fastest_candidate.x, fastest_candidate.y
	]
	append_output_(tr(
		"推荐配置：%d 个搜索线程，批量大小 %d，热态复测 %.2f visits/s"
	) % [selected.x, selected.y, selected_rate])
	append_regular_report_("summary", {
		"selectionMode": "hotRetestMean",
		"selectedThreads": selected.x,
		"selectedBatchSize": selected.y,
		"selectedVisitsPerSecond": selected_rate,
		"selectedInitialVisitsPerSecond": regular_average_rate_(selected),
		"selectedRetestSamples": regular_search_retest_samples_.get(
			selected_key, []
		),
		"fastestThreads": fastest_candidate.x,
		"fastestBatchSize": fastest_candidate.y,
		"fastestVisitsPerSecond": fastest_rate,
		"fastestInitialVisitsPerSecond": regular_average_rate_(
			fastest_candidate
		),
		"fastestRetestSamples": regular_search_retest_samples_.get(
			fastest_key, []
		),
	})
	finish_(true, selected.x, selected.y, "")


func append_regular_report_(record_type: String, data: Dictionary) -> void:
	regular_report_records_.append({
		"type": record_type,
		"unixTime": Time.get_unix_time_from_system(),
		"data": data.duplicate(true),
	})


func write_regular_report_() -> String:
	if regular_report_records_.is_empty():
		return ""
	var local_path: String = "user://katago/validation-latest.jsonl" if o3_validation_mode_ else kRegularReportPath
	var file: FileAccess = FileAccess.open(local_path, FileAccess.WRITE)
	if file == null:
		return ""
	for record: Dictionary in regular_report_records_:
		file.store_line(JSON.stringify(record, "", false))
	file.close()
	# Keep an externally readable, separate report for each O3 model/run.
	if OS.get_name() == "Android":
		var host: Variant = JavaClassWrapper.wrap(KataGoOpenCLTransport.kAndroidHostClass)
		if host != null:
			var directory: String = str(host.getKataGoO3ProfileDirectory())
			if not directory.is_empty():
				var prefix: String = "validation-summary" if o3_validation_mode_ else "benchmark"
				var report_name: String = "%s-%d-%d.jsonl" % [
					prefix,
					int(Time.get_unix_time_from_system() * 1000), Time.get_ticks_usec()
				]
				var public_path: String = directory.path_join(report_name)
				if o3_validation_mode_:
					report_name = "validation-summary-run%s.jsonl" % o3_validation_run_id_
					public_path = directory.path_join(report_name)
				if bool(host.saveKataGoHistoryReport(ProjectSettings.globalize_path(local_path), report_name)):
					return public_path
				append_output_(tr("诊断报告副本保存失败：%s") % error_string(ERR_CANT_CREATE))
	return ProjectSettings.globalize_path(local_path)


func finish_(
		succeeded: bool,
		search_threads: int,
		batch_size: int,
		message: String
) -> void:
	if finishing_:
		return
	if o3_validation_mode_:
		append_regular_report_("validationEnd", {
			"status": "completed_needs_review" if succeeded else "failed",
			"completedBatches": o3_validation_index_, "message": message,
			"numericalAcceptance": "not_evaluated",
		})
	var report_path: String = write_regular_report_()
	if not report_path.is_empty():
		append_output_(tr("报告已保存：%s") % report_path)
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


func stop_transport_(after_stopped: Callable = Callable()) -> void:
	if transport_ != null:
		var transport: KataGoTransport = transport_
		transport_ = null
		transport.stop_transport()
		if after_stopped.is_valid():
			transport.tree_exited.connect(
				on_transport_tree_exited_.bind(after_stopped), CONNECT_ONE_SHOT
			)
		transport.queue_free()
	elif after_stopped.is_valid():
		after_stopped.call_deferred()


func on_transport_tree_exited_(after_stopped: Callable) -> void:
	# Start the next candidate on the following main-loop turn, after Godot has
	# fully removed the old transport and its _exit_tree() has completed.
	after_stopped.call_deferred()


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
	if not human_model_:
		append_regular_report_("engineLog", {"message": line})


func on_transport_error_(message: String, source: KataGoTransport) -> void:
	if finishing_ or source != transport_:
		return
	if human_model_ and not human_transport_starting_:
		recover_human_candidate_(message)
		return
	finish_(false, 0, 0, message)


func on_transport_stopped_(source: KataGoTransport) -> void:
	if source != transport_:
		return
	if not finishing_:
		if human_model_ and not human_transport_starting_:
			recover_human_candidate_(
				tr("内置 KataGo 性能检测意外停止。"))
			return
		finish_(false, 0, 0, tr("内置 KataGo 性能检测意外停止。"))


func _exit_tree() -> void:
	if transport_ != null:
		transport_.stop_transport()
	if o3_validation_mode_ and OS.get_name() == "Android":
		var host: Variant = JavaClassWrapper.wrap(KataGoOpenCLTransport.kAndroidHostClass)
		if host != null:
			host.protectKataGoValidationHistory(o3_validation_run_id_, false)
