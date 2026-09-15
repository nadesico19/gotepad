class_name KataGoAndroidTransport
extends KataGoTransport

var backend_: KataGoTransport
var override_config_: String = ""
var model_path_override_: String = ""
var human_model_path_: String = ""
var config_path_: String = ""
var active_queries_: Dictionary = {}
var using_fallback_: bool = false
var stopping_: bool = false
var switching_: bool = false
var opencl_runtime_restart_attempted_: bool = false
var user_analysis_recovery_enabled_: bool = false


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
	stopping_ = false
	using_fallback_ = false
	opencl_runtime_restart_attempted_ = false
	model_path_override_ = model_path_override
	human_model_path_ = human_model_path
	config_path_ = config_path
	override_config_ = override_config
	return start_backend_(KataGoOpenCLTransport.new(), true)


func send_line(line: String) -> bool:
	if backend_ == null:
		return false
	remember_query_(line)
	return backend_.send_line(line)


func stop_transport() -> void:
	stopping_ = true
	active_queries_.clear()
	opencl_runtime_restart_attempted_ = false
	user_analysis_recovery_enabled_ = false
	if backend_ != null:
		backend_.stop_transport()
		backend_.queue_free()
		backend_ = null
	transport_stopped.emit()


func is_transport_running() -> bool:
	return backend_ != null and backend_.is_transport_running()


func prepare_for_user_analysis() -> bool:
	user_analysis_recovery_enabled_ = true
	if using_fallback_:
		return restart_active_queries()
	return is_transport_running() or start_transport()


func set_user_analysis_recovery_enabled(enabled: bool) -> void:
	user_analysis_recovery_enabled_ = enabled


func restart_active_queries() -> bool:
	var pending_lines: Array = active_queries_.values().duplicate()
	recovery_started.emit()
	switching_ = true
	stopping_ = false
	if backend_ != null:
		backend_.stop_transport()
		backend_.queue_free()
		backend_ = null
	switching_ = false
	using_fallback_ = false
	var started: bool = start_backend_(KataGoOpenCLTransport.new(), true)
	if not started:
		return false
	# A synchronous OpenCL startup error may already have switched to Eigen and
	# replayed active_queries_. Avoid submitting the same requests twice.
	if using_fallback_:
		return true
	for line: Variant in pending_lines:
		if not backend_.send_line(str(line)):
			return switch_to_eigen_(tr("无法恢复 OpenCL KataGo 分析。"))
	return true


func start_backend_(candidate: KataGoTransport, allow_fallback: bool) -> bool:
	if backend_ != null:
		backend_.queue_free()
	backend_ = candidate
	add_child(backend_)
	backend_.line_received.connect(on_backend_line_.bind(candidate))
	backend_.log_received.connect(on_backend_log_.bind(candidate))
	backend_.transport_error.connect(on_backend_error_.bind(candidate))
	backend_.transport_stopped.connect(on_backend_stopped_.bind(candidate))
	var started: bool = false
	if backend_.has_method("start_custom_transport"):
		started = bool(backend_.call(
			"start_custom_transport", model_path_override_, human_model_path_,
			config_path_, override_config_
		))
	elif backend_.has_method("start_transport_with_override"):
		started = bool(backend_.call(
			"start_transport_with_override", override_config_
		))
	else:
		started = backend_.start_transport()
	if started:
		return true
	# A synchronous primary error may already have entered the signal handler and
	# completed the fallback switch before start_transport() returns.
	if allow_fallback and using_fallback_:
		return is_transport_running()
	if allow_fallback and not using_fallback_ and not switching_:
		return switch_to_eigen_(tr("设备的 OpenCL 后端不可用。"))
	return false


func switch_to_eigen_(reason: String) -> bool:
	if switching_ or using_fallback_:
		return false
	switching_ = true
	using_fallback_ = true
	if backend_ != null:
		backend_.stop_transport()
		backend_.queue_free()
		backend_ = null
	log_received.emit(tr("%s 已自动切换到兼容性更高的 Eigen 后端。") % reason)
	var fallback: KataGoEmbeddedTransport = KataGoEmbeddedTransport.new()
	var started: bool = start_backend_(fallback, false)
	if started:
		for line: Variant in active_queries_.values():
			fallback.send_line(str(line))
	switching_ = false
	if not started:
		transport_error.emit(tr("OpenCL 和 Eigen KataGo 后端均无法启动。"))
	return started


func remember_query_(line: String) -> void:
	var parsed: Variant = JSON.parse_string(line)
	if parsed is not Dictionary:
		return
	var query: Dictionary = Dictionary(parsed)
	if str(query.get("action", "")) == "terminate":
		active_queries_.erase(str(query.get("terminateId", "")))
		if active_queries_.is_empty():
			user_analysis_recovery_enabled_ = false
		return
	var query_id: String = str(query.get("id", ""))
	if not query_id.is_empty() and not query.has("action"):
		active_queries_[query_id] = line


func on_backend_line_(line: String, source: KataGoTransport) -> void:
	if source != backend_:
		return
	var parsed: Variant = JSON.parse_string(line)
	if parsed is Dictionary:
		var result: Dictionary = Dictionary(parsed)
		var query_id: String = str(result.get("id", ""))
		if not using_fallback_ and not query_id.is_empty():
			opencl_runtime_restart_attempted_ = false
		if not query_id.is_empty() and not bool(result.get("isDuringSearch", false)):
			active_queries_.erase(query_id)
			if active_queries_.is_empty():
				user_analysis_recovery_enabled_ = false
	line_received.emit(line)


func on_backend_log_(line: String, source: KataGoTransport) -> void:
	if source != backend_:
		return
	log_received.emit(line)


func on_backend_error_(message: String, source: KataGoTransport) -> void:
	if source != backend_ or stopping_ or switching_:
		return
	if user_analysis_recovery_enabled_ and not using_fallback_ \
			and not active_queries_.is_empty() \
			and not opencl_runtime_restart_attempted_:
		opencl_runtime_restart_attempted_ = true
		if restart_active_queries():
			log_received.emit(tr(
				"OpenCL KataGo 服务异常，已自动重启并恢复分析。"
			))
			return
	if not using_fallback_ and switch_to_eigen_(message):
		return
	transport_error.emit(message)


func on_backend_stopped_(source: KataGoTransport) -> void:
	if source != backend_ or stopping_ or switching_:
		return
	if user_analysis_recovery_enabled_ and not using_fallback_ \
			and not active_queries_.is_empty():
		if not opencl_runtime_restart_attempted_:
			opencl_runtime_restart_attempted_ = true
			if restart_active_queries():
				log_received.emit(tr(
					"OpenCL KataGo 服务已停止，已自动重启并恢复分析。"
				))
				return
		if switch_to_eigen_(tr("OpenCL KataGo 服务已停止。")):
			return
	transport_stopped.emit()


func _exit_tree() -> void:
	stop_transport()
