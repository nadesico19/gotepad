class_name KataGoAnalysisPanel
extends Control

signal panel_visibility_changed(opened: bool)
signal variation_requested(pv: Array)

const kStateIdle: int = 0
const kStateAnalyzing: int = 1
const kStatePaused: int = 2
const kStateStopping: int = 3
const kStateContinuous: int = 4
@onready var panel_: PanelContainer = $Panel
@onready var play_button_: Button = $Panel/Margin/Content/Controls/Primary/Play
@onready var pause_button_: Button = $Panel/Margin/Content/Controls/Primary/Pause
@onready var stop_button_: Button = $Panel/Margin/Content/Controls/Primary/Stop
@onready var increase_button_: Button = \
	$Panel/Margin/Content/Controls/Primary/Increase
@onready var max_playouts_: SpinBox = \
	$Panel/Margin/Content/Controls/Primary/MaxPlayouts
@onready var status_label_: Label = \
	$Panel/Margin/Content/Controls/Secondary/Status
@onready var continuous_: CheckBox = \
	$Panel/Margin/Content/Controls/Secondary/Continuous
@onready var candidates_: Tree = $Panel/Margin/Content/Candidates
@onready var curve_: AnalysisCurve = $Panel/Margin/Content/Curve
@onready var score_legend_: Label = $Panel/Margin/Content/CurveFooter/ScoreLegend
@onready var analyze_game_button_: Button = \
	$Panel/Margin/Content/CurveFooter/AnalyzeGame
@onready var invalid_max_playouts_dialog_: AcceptDialog = \
	$InvalidMaxPlayoutsDialog

var service_: KataGoAnalysisService
var go_notes_: GoNotes
var board_: GoBoardView
var state_: int = kStateIdle
var current_query_id_: String = ""
var current_max_playouts_: int = 0
var batch_query_id_: String = ""
var batch_member_ids_: Dictionary = {}
var current_uid_: int = -1
var paused_result_: Dictionary = {}
var candidate_pvs_: Dictionary = {}
var latest_move_infos_: Array = []
var results_by_uid_: Dictionary = {}
var query_turn_uids_: Dictionary = {}
var batch_pending_turns_: Dictionary = {}
var document_instance_id_: int = 0
var cached_request_settings_signature_: String = ""


func _ready() -> void:
	play_button_.pressed.connect(on_play_pressed_)
	pause_button_.pressed.connect(on_pause_pressed_)
	stop_button_.pressed.connect(on_stop_pressed_)
	increase_button_.pressed.connect(on_increase_pressed_)
	continuous_.toggled.connect(on_continuous_toggled_)
	analyze_game_button_.pressed.connect(on_analyze_game_pressed_)
	curve_.position_requested.connect(on_curve_position_requested_)
	candidates_.gui_input.connect(on_candidates_gui_input_)
	SettingsStore.katago_paths_changed.connect(on_analysis_paths_changed_)
	SettingsStore.katago_analysis_settings_changed.connect(
		on_analysis_settings_changed_
	)
	cached_request_settings_signature_ = request_settings_signature_()
	configure_tree_()
	panel_.hide()
	update_controls_()


func bind_service(service: KataGoAnalysisService) -> void:
	if service_ == service:
		return
	service_ = service
	service_.result_received.connect(on_analysis_result_)
	service_.service_error.connect(on_service_error_)
	service_.query_error.connect(on_query_error_)
	service_.service_warning.connect(on_service_warning_)


func open_panel(go_notes: GoNotes, board: GoBoardView) -> void:
	if go_notes == null or board == null:
		return
	var new_instance_id: int = go_notes.get_instance_id()
	if document_instance_id_ != new_instance_id:
		stop_all_queries_()
		results_by_uid_.clear()
		latest_move_infos_.clear()
		document_instance_id_ = new_instance_id
	go_notes_ = go_notes
	board_ = board
	current_uid_ = board_.get_view_uid()
	panel_.show()
	refresh_candidates_(latest_move_infos_)
	refresh_curve_()
	update_controls_()
	panel_visibility_changed.emit(true)


func close_panel() -> void:
	stop_all_queries_()
	if board_ != null:
		board_.clear_analysis_candidates()
	continuous_.set_pressed_no_signal(false)
	state_ = kStateIdle
	panel_.hide()
	panel_visibility_changed.emit(false)


func is_panel_open() -> bool:
	return panel_.visible


func set_panel_rect(rect: Rect2) -> void:
	position = rect.position
	size = rect.size


func on_board_position_changed(uid: int) -> void:
	var position_really_changed: bool = uid != current_uid_
	current_uid_ = uid
	if position_really_changed:
		latest_move_infos_.clear()
		refresh_candidates_([])
	refresh_curve_()
	if not is_panel_open():
		return
	if state_ == kStateContinuous:
		query_turn_uids_.erase(current_query_id_)
		terminate_current_query_()
		start_current_analysis_(true)
	elif state_ == kStatePaused and current_query_id_.is_empty():
		paused_result_.clear()
		state_ = kStateIdle
		status_label_.text = tr("局面已改变，请重新开始分析")
		update_controls_()


	elif state_ != kStateIdle:
		terminate_current_query_()
		state_ = kStateStopping
		update_controls_()


func on_curve_position_requested_(uid: int) -> void:
	if board_ == null or uid == current_uid_:
		return
	var _roam_succeeded: bool = board_.roam_to_playback_uid(uid)


func on_play_pressed_() -> void:
	if state_ == kStatePaused:
		state_ = kStateAnalyzing if not current_query_id_.is_empty() \
			else kStateIdle
		if not paused_result_.is_empty():
			apply_current_result_(paused_result_)
			paused_result_.clear()
		update_controls_()
		return
	start_current_analysis_(false)


func on_pause_pressed_() -> void:
	if state_ != kStateAnalyzing:
		return
	state_ = kStatePaused
	status_label_.text = tr("已暂停界面刷新，KataGo仍在分析")
	update_controls_()


func on_stop_pressed_() -> void:
	if current_query_id_.is_empty():
		return
	terminate_current_query_()
	state_ = kStateStopping
	status_label_.text = tr("正在停止分析…")
	update_controls_()


func on_increase_pressed_() -> void:
	var requested_playouts: int = roundi(max_playouts_.value)
	if requested_playouts <= 0:
		invalid_max_playouts_dialog_.popup_centered()
		return
	start_current_analysis_(false, requested_playouts)


func on_continuous_toggled_(enabled: bool) -> void:
	if enabled:
		stop_batch_query_()
		state_ = kStateContinuous
		start_current_analysis_(true)
	else:
		terminate_current_query_()
		query_turn_uids_.erase(current_query_id_)
		current_query_id_ = ""
		current_max_playouts_ = 0
		state_ = kStateIdle
		status_label_.text = tr("持续分析已关闭")
	update_controls_()


func start_current_analysis_(continuous: bool, max_playouts: int = 0) -> void:
	if service_ == null or go_notes_ == null or board_ == null:
		return
	var path: PackedInt64Array = board_.get_playback_path()
	var current_index: int = path.find(board_.get_view_uid())
	if current_index < 0:
		on_service_error_(tr("当前局面不在播放路径中。"))
		return
	var context: Dictionary = KataGoQueryBuilder.build_context(
		go_notes_, path, current_index
	)
	if context.is_empty():
		on_service_error_(tr("无法构造当前局面的KataGo请求。"))
		return
	current_uid_ = board_.get_view_uid()
	query_turn_uids_.erase(current_query_id_)
	current_query_id_ = service_.next_query_id("current")
	current_max_playouts_ = maxi(max_playouts, 0)
	var turns: Array = Array(context.get("analyze_turns", []))
	var target_turn: int = int(turns[-1])
	query_turn_uids_[current_query_id_] = {target_turn: current_uid_}
	var query: Dictionary = KataGoQueryBuilder.build_query(
		context,
		current_query_id_,
		[target_turn],
		SettingsStore.get_katago_max_visits(),
		SettingsStore.get_katago_report_interval_seconds(),
		SettingsStore.get_katago_analysis_pv_length(),
		current_max_playouts_
	)
	query["initialPlayer"] = "W" if board_.get_next_color() == 2 else "B"
	if not service_.submit_query(query):
		current_query_id_ = ""
		current_max_playouts_ = 0
		state_ = kStateIdle
		update_controls_()
		return
	state_ = kStateContinuous if continuous else kStateAnalyzing
	status_label_.text = tr("正在分析当前局面…") \
		if current_max_playouts_ <= 0 \
		else tr("正在加大计算量：%d maxplayouts…") % current_max_playouts_
	update_controls_()


func on_analyze_game_pressed_() -> void:
	if not batch_query_id_.is_empty():
		stop_batch_query_()
		return
	if service_ == null or go_notes_ == null or board_ == null:
		return
	if not current_query_id_.is_empty() or state_ == kStateContinuous:
		return
	var contexts: Array[Dictionary] = KataGoQueryBuilder.build_path_contexts(
		go_notes_, board_.get_playback_path()
	)
	if contexts.is_empty():
		on_service_error_(tr("无法构造整局分析请求。"))
		return
	batch_query_id_ = service_.next_query_id("game-group")
	batch_member_ids_.clear()
	batch_pending_turns_.clear()
	for context: Dictionary in contexts:
		var turns: Array = Array(context.get("analyze_turns", []))
		var uids: Array = Array(context.get("turn_uids", []))
		if turns.is_empty() or turns.size() != uids.size():
			continue
		var member_id: String = service_.next_query_id("game")
		var mapping: Dictionary = {}
		for index in range(turns.size()):
			var turn: int = int(turns[index])
			mapping[turn] = int(uids[index])
			batch_pending_turns_[batch_result_key_(member_id, turn)] = true
		query_turn_uids_[member_id] = mapping
		batch_member_ids_[member_id] = true
		var query: Dictionary = KataGoQueryBuilder.build_query(
			context,
			member_id,
			turns,
			SettingsStore.get_katago_game_analysis_visits(),
			SettingsStore.get_katago_report_interval_seconds(),
			2
		)
		query.erase("reportDuringSearchEvery")
		if not service_.submit_query(query):
			stop_batch_query_()
			return
	if batch_member_ids_.is_empty():
		batch_query_id_ = ""
		on_service_error_(tr("播放路径没有可分析的局面。"))
		return
	analyze_game_button_.text = tr("取消整局分析")
	status_label_.text = tr("正在分析整条播放路径：0/%d") % \
		batch_pending_turns_.size()
	update_controls_()


func on_analysis_result_(result: Dictionary) -> void:
	var query_id: String = str(result.get("id", ""))
	if query_id == current_query_id_:
		handle_current_result_(result)
	elif batch_member_ids_.has(query_id):
		handle_batch_result_(result)


func handle_current_result_(result: Dictionary) -> void:
	if state_ == kStatePaused:
		paused_result_ = result.duplicate(true)
	elif state_ != kStateStopping:
		apply_current_result_(result)
	if bool(result.get("isDuringSearch", false)):
		return
	query_turn_uids_.erase(current_query_id_)
	current_query_id_ = ""
	if state_ == kStateStopping:
		state_ = kStateIdle
		status_label_.text = tr("分析已停止")
	elif state_ == kStateAnalyzing:
		state_ = kStateIdle
	elif state_ == kStatePaused:
		status_label_.text = tr("分析已完成，点击播放按钮显示最终结果")
	update_controls_()


func apply_current_result_(result: Dictionary) -> void:
	if bool(result.get("noResults", false)):
		return
	var root_info: Dictionary = Dictionary(result.get("rootInfo", {}))
	if not root_info.is_empty():
		results_by_uid_[current_uid_] = root_info
	latest_move_infos_ = Array(result.get("moveInfos", [])).duplicate(true)
	refresh_candidates_(latest_move_infos_)
	refresh_curve_()
	var visits: int = int(root_info.get("visits", 0))
	var progress_name: String = \
		tr("分析中") if bool(result.get("isDuringSearch", false)) \
		else tr("分析完成")
	if current_max_playouts_ > 0:
		status_label_.text = tr("%s · %d visits · 目标 %d maxplayouts") % [
			progress_name, visits, current_max_playouts_
		]
	else:
		status_label_.text = "%s · %d/%d visits" % [
			progress_name, visits, SettingsStore.get_katago_max_visits()
		]


func handle_batch_result_(result: Dictionary) -> void:
	var query_id: String = str(result.get("id", ""))
	var turn: int = int(result.get("turnNumber", -1))
	var result_key: String = batch_result_key_(query_id, turn)
	if bool(result.get("noResults", false)):
		batch_pending_turns_.erase(result_key)
	elif not bool(result.get("isDuringSearch", false)):
		var mapping: Dictionary = Dictionary(query_turn_uids_.get(
			query_id, {}
		))
		if mapping.has(turn):
			results_by_uid_[int(mapping[turn])] = Dictionary(
				result.get("rootInfo", {})
			)
		batch_pending_turns_.erase(result_key)
	refresh_curve_()
	var total: int = 0
	for member_id: String in batch_member_ids_:
		total += Dictionary(query_turn_uids_.get(member_id, {})).size()
	var completed: int = total - batch_pending_turns_.size()
	status_label_.text = tr("正在分析整条播放路径：%d/%d") % [completed, total]
	if not batch_pending_turns_.is_empty():
		return
	for member_id: String in batch_member_ids_:
		query_turn_uids_.erase(member_id)
	batch_member_ids_.clear()
	batch_query_id_ = ""
	analyze_game_button_.text = tr("分析整条播放路径")
	status_label_.text = tr("整局分析完成")
	update_controls_()


func refresh_candidates_(move_infos: Array) -> void:
	candidates_.clear()
	configure_tree_()
	candidate_pvs_.clear()
	var sorted_infos: Array = move_infos.duplicate(true)
	sorted_infos.sort_custom(Callable(self, "candidate_winrate_precedes_"))
	var show_score: bool = SettingsStore.get_katago_show_score_lead()
	var variation_column: int = 3 if show_score else 2
	var root: TreeItem = candidates_.create_item()
	for index in range(sorted_infos.size()):
		var info: Dictionary = Dictionary(sorted_infos[index])
		var item: TreeItem = candidates_.create_item(root)
		item.set_text(0, str(info.get("move", "")))
		item.set_text(1, "%.1f%%" % (float(info.get("winrate", 0.0)) * 100.0))
		if show_score:
			item.set_text(2, "%+.1f" % float(info.get("scoreLead", 0.0)))
		var pv: Array = truncate_pv_(Array(info.get("pv", [])))
		if pv.is_empty():
			item.set_text(variation_column, "—")
		else:
			item.set_cell_mode(variation_column, TreeItem.CELL_MODE_STRING)
			item.set_text(variation_column, tr("进入"))
			item.set_text_alignment(
				variation_column, HORIZONTAL_ALIGNMENT_CENTER
			)
			item.set_custom_bg_color(
				variation_column, Color(0.18, 0.19, 0.19, 0.92)
			)
			item.set_custom_color(
				variation_column, Color(0.96, 0.96, 0.93, 1.0)
			)
			item.set_tooltip_text(variation_column, tr("进入候选变化图"))
			candidate_pvs_[index] = pv
			item.set_metadata(variation_column, index)
	if board_ != null and panel_.visible:
		board_.set_analysis_candidates(sorted_infos)


func candidate_winrate_precedes_(left: Variant, right: Variant) -> bool:
	var left_winrate: float = float(Dictionary(left).get("winrate", 0.0))
	var right_winrate: float = float(Dictionary(right).get("winrate", 0.0))
	if board_ != null and board_.get_next_color() == 2:
		return left_winrate < right_winrate
	return left_winrate > right_winrate


func on_candidates_gui_input_(event: InputEvent) -> void:
	var mouse_event: InputEventMouseButton = event as InputEventMouseButton
	if mouse_event == null or not mouse_event.pressed \
			or mouse_event.button_index != MOUSE_BUTTON_LEFT:
		return
	var variation_column: int = 3 \
		if SettingsStore.get_katago_show_score_lead() else 2
	if candidates_.get_column_at_position(mouse_event.position) \
			!= variation_column:
		return
	var item: TreeItem = candidates_.get_item_at_position(mouse_event.position)
	if item == null:
		return
	var id_value: Variant = item.get_metadata(variation_column)
	if id_value == null:
		return
	var id: int = int(id_value)
	if not candidate_pvs_.has(id):
		return
	variation_requested.emit(Array(candidate_pvs_[id]).duplicate())
	candidates_.accept_event()


func refresh_curve_() -> void:
	if board_ == null:
		return
	var show_score: bool = SettingsStore.get_katago_show_score_lead()
	curve_.set_series(
		board_.get_playback_path(), results_by_uid_, show_score, current_uid_
	)
	score_legend_.visible = show_score


func configure_tree_() -> void:
	var show_score: bool = SettingsStore.get_katago_show_score_lead()
	var variation_column: int = 3 if show_score else 2
	candidates_.columns = 4 if show_score else 3
	candidates_.column_titles_visible = true
	candidates_.hide_root = true
	candidates_.set_column_title(0, tr("位置"))
	candidates_.set_column_title(1, tr("黑胜率"))
	if show_score:
		candidates_.set_column_title(2, tr("目差"))
	candidates_.set_column_title(variation_column, tr("变化图"))
	candidates_.set_column_expand(0, true)
	candidates_.set_column_expand(1, true)
	if show_score:
		candidates_.set_column_expand(2, true)
	candidates_.set_column_expand(variation_column, false)
	candidates_.set_column_custom_minimum_width(variation_column, 58)


func update_controls_() -> void:
	var continuous_enabled: bool = state_ == kStateContinuous
	play_button_.disabled = continuous_enabled or state_ == kStateAnalyzing \
		or state_ == kStateStopping or not batch_query_id_.is_empty()
	pause_button_.disabled = state_ != kStateAnalyzing
	stop_button_.disabled = current_query_id_.is_empty() \
		or (state_ != kStateAnalyzing and state_ != kStatePaused)
	increase_button_.disabled = state_ != kStateIdle \
		or not current_query_id_.is_empty() or not batch_query_id_.is_empty()
	max_playouts_.editable = not increase_button_.disabled
	continuous_.disabled = state_ == kStateStopping \
		or not batch_query_id_.is_empty()
	analyze_game_button_.disabled = not current_query_id_.is_empty() \
		or state_ == kStateContinuous
	play_button_.queue_redraw()
	pause_button_.queue_redraw()
	stop_button_.queue_redraw()


func terminate_current_query_() -> void:
	if current_query_id_.is_empty() or service_ == null:
		return
	var _terminated: bool = service_.terminate_query(current_query_id_)


func stop_batch_query_() -> void:
	if batch_query_id_.is_empty() or service_ == null:
		return
	for member_id: String in batch_member_ids_:
		var _terminated: bool = service_.terminate_query(member_id)
		query_turn_uids_.erase(member_id)
	batch_member_ids_.clear()
	batch_query_id_ = ""
	batch_pending_turns_.clear()
	analyze_game_button_.text = tr("分析整条播放路径")
	status_label_.text = tr("整局分析已取消")
	update_controls_()


func stop_all_queries_() -> void:
	terminate_current_query_()
	stop_batch_query_()
	query_turn_uids_.erase(current_query_id_)
	current_query_id_ = ""
	current_max_playouts_ = 0
	paused_result_.clear()
	state_ = kStateIdle


func on_service_error_(message: String) -> void:
	status_label_.text = compact_status_message_(message)
	continuous_.set_pressed_no_signal(false)
	state_ = kStateIdle
	current_query_id_ = ""
	current_max_playouts_ = 0
	batch_query_id_ = ""
	batch_member_ids_.clear()
	query_turn_uids_.clear()
	batch_pending_turns_.clear()
	analyze_game_button_.text = tr("分析整条播放路径")
	update_controls_()


func on_query_error_(query_id: String, message: String) -> void:
	if query_id == current_query_id_:
		query_turn_uids_.erase(query_id)
		current_query_id_ = ""
		current_max_playouts_ = 0
		continuous_.set_pressed_no_signal(false)
		state_ = kStateIdle
	elif batch_member_ids_.has(query_id):
		stop_batch_query_()
	else:
		return
	status_label_.text = compact_status_message_(message)
	update_controls_()


func on_service_warning_(message: String) -> void:
	status_label_.text = compact_status_message_(tr("KataGo警告：%s") % message)


func batch_result_key_(query_id: String, turn: int) -> String:
	return "%s:%d" % [query_id, turn]


func truncate_pv_(pv: Array) -> Array:
	var result: Array = []
	for move_value: Variant in pv:
		if result.size() >= SettingsStore.get_katago_analysis_pv_length():
			break
		var move: String = str(move_value).strip_edges()
		if move.to_upper() == "PASS" or move.to_upper() == "RESIGN":
			break
		result.append(move)
	return result


func on_analysis_settings_changed_() -> void:
	var signature: String = request_settings_signature_()
	if signature == cached_request_settings_signature_:
		refresh_candidates_(latest_move_infos_)
		refresh_curve_()
		status_label_.text = tr("分析显示设置已更新")
		return
	cached_request_settings_signature_ = signature
	clear_analysis_cache_(tr("分析设置已更新"))


func on_analysis_paths_changed_() -> void:
	if service_ != null:
		service_.shutdown()
	clear_analysis_cache_(tr("KataGo引擎设置已更新"))


func refresh_localized_texts() -> void:
	refresh_candidates_(latest_move_infos_)
	if batch_query_id_.is_empty():
		analyze_game_button_.text = tr("分析整条播放路径")
	else:
		analyze_game_button_.text = tr("取消整局分析")


func clear_analysis_cache_(message: String) -> void:
	stop_all_queries_()
	results_by_uid_.clear()
	latest_move_infos_.clear()
	refresh_candidates_([])
	refresh_curve_()
	status_label_.text = message
	update_controls_()


func request_settings_signature_() -> String:
	return "%d|%.3f|%d|%d" % [
		SettingsStore.get_katago_max_visits(),
		SettingsStore.get_katago_report_interval_seconds(),
		SettingsStore.get_katago_analysis_pv_length(),
		SettingsStore.get_katago_game_analysis_visits()
	]


func compact_status_message_(message: String) -> String:
	var result: String = message.replace("\r", " ").replace("\n", " ")
	while "  " in result:
		result = result.replace("  ", " ")
	result = result.strip_edges()
	if result.length() > 96:
		return result.substr(0, 95) + "…"
	return result
