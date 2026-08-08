class_name GoBoardView
extends Sprite2D

signal board_texture_changed
signal cut_branch_mode_changed(enabled: bool)
signal find_mode_changed(direction: int)
signal next_color_changed(color: int)
signal preset_mode_changed(enabled: bool)
signal preset_edit_replay_failed(failed_uid: int)
signal note_mark_cancel_requested
signal note_mark_draft_changed
signal setup_branches_changed(branches: Array[Dictionary])
signal variation_mode_changed(enabled: bool)
signal position_changed(uid: int)

const kBlack: int = 1
const kWhite: int = 2
const kGridColor: Color = Color(0.12, 0.08, 0.035, 0.9)
const kCoordinateLetters: String = "ABCDEFGHJKLMNOPQRSTUVWXYZ"
const kSequentialMarkLetters: String = \
	"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
const kCoordinateOffsetCellRatio: float = 0.70
const kCoordinateFontCellRatio: float = 0.30
const kCoordinateColor: Color = Color(0.08, 0.045, 0.015, 0.92)
const kCoordinateOutlineColor: Color = Color(1.0, 0.88, 0.62, 0.58)
const kCoordinateOutlineFontRatio: float = 0.10
const kGridLineCellRatio: float = 0.03
const kOuterGridLineWidthRatio: float = 2.0
const kMinGridLinePixels: float = 1.0
const kMaxGridLinePixels: float = 2.5
const kStarRadiusCellRatio: float = 0.085
const kMinStarRadiusPixels: float = 3.0
const kMaxStarRadiusPixels: float = 8.0
const kStoneDiameterCellRatio: float = 0.98
const kIntersectionHitRadiusRatio: float = 0.62
const kHoverStoneOpacity: float = 0.40
const kFindHoverOpacity: float = 1.0
const kFindHoverDiameterCellRatio: float = 0.78
const kCutBranchHoverDiameterCellRatio: float = 0.86
const kFindTowardParent: int = -1
const kFindDisabled: int = 0
const kFindTowardFirstChild: int = 1
const kMoveNumberFontCellRatio: float = 0.42
const kMoveNumberMaxTextWidthRatio: float = 1.15
const kBranchMarkerSizeCellRatio: float = 0.40
const kBranchMarkerHitHalfCellRatio: float = 0.46
const kBranchMarkerFillColor: Color = Color(1.0, 1.0, 1.0, 0.16)
const kBranchMarkerBorderColor: Color = Color(1.0, 1.0, 1.0, 0.30)
const kNoteMarkDisabled: int = 0
const kNoteSequentialMarkMode: int = 1
const kNoteSymbolMarkMode: int = 2
const kStoneScene: PackedScene = preload("res://scene/stone.tscn")
const kStoneSound0: AudioStream = preload(
	"res://assets/audio/place_stone_0.mp3"
)
const kStoneSound1: AudioStream = preload(
	"res://assets/audio/place_stone_1.mp3"
)
const kStoneSound2: AudioStream = preload(
	"res://assets/audio/place_stone_2.mp3"
)
const kStoneSound3: AudioStream = preload(
	"res://assets/audio/place_stone_3.mp3"
)
const kStoneSound4: AudioStream = preload(
	"res://assets/audio/place_stone_4.mp3"
)

@export_range(1, 52, 1) var initial_board_size: int = 19

@onready var stones_: Node2D = $Stones
@onready var stone_sound_player_: AudioStreamPlayer = $StoneSoundPlayer
@onready var note_marks_overlay_: Node2D = $NoteMarksOverlay
@onready var analysis_candidates_overlay_: AnalysisCandidatesOverlay = \
	$AnalysisCandidatesOverlay
@onready var hover_stone_: Sprite2D = $HoverStone
@onready var find_hover_: Sprite2D = $FindHover
@onready var cut_branch_hover_: Sprite2D = $CutBranchHover
@onready var setup_branch_preview_: SetupBranchPreviewOverlay = \
	$SetupBranchPreview
@onready var takeback_confirmation_: ConfirmationDialog = $TakebackConfirmation
@onready var cut_branch_confirmation_: ConfirmationDialog = \
	$CutBranchConfirmation
@onready var find_result_dialog_: AcceptDialog = $FindResultDialog
@onready var preset_edit_error_dialog_: AcceptDialog = $PresetEditErrorDialog
@onready var playback_bar_: HSlider = $PlaybackBar
@onready var playback_hover_bubble_: PanelContainer = $PlaybackHoverBubble
@onready var playback_hover_label_: Label = $PlaybackHoverBubble/Label
@onready var playback_previous_button_: Button = $PlaybackPreviousButton
@onready var playback_next_button_: Button = $PlaybackNextButton
@onready var playback_button_: Button = $PlaybackButton
@onready var playback_timer_: Timer = $PlaybackTimer
@onready var preset_button_: Button = $PresetButton

var board_size_: int = 19
var black_texture_: Texture2D
var white_texture_: Texture2D
var go_notes_: GoNotes
var next_color_: int = kBlack
var position_states_: PackedInt32Array = PackedInt32Array()
var move_numbers_: PackedInt32Array = PackedInt32Array()
var stone_nodes_: Array[Sprite2D] = []
var move_number_labels_: Array[Label] = []
var playback_path_: PackedInt64Array = PackedInt64Array()
var playback_move_numbers_: PackedInt32Array = PackedInt32Array()
var branch_moves_: Array[Dictionary] = []
var setup_branches_: Array[Dictionary] = []
var setup_preview_uid_: int = -1
var view_uid_: int = 0
var follow_current_: bool = true
var playback_navigation_: bool = false
var updating_playback_bar_: bool = false
var playback_playing_: bool = false
var interactions_locked_: bool = false
var preset_mode_: bool = false
var preset_editing_current_: bool = false
var preset_original_states_: PackedInt32Array = PackedInt32Array()
var preset_original_move_numbers_: PackedInt32Array = PackedInt32Array()
var preset_draft_states_: PackedInt32Array = PackedInt32Array()
var hover_screen_position_: Vector2 = Vector2.ZERO
var has_hover_position_: bool = false
var find_direction_: int = kFindDisabled
var cut_branch_mode_: bool = false
var pending_cut_branch_uid_: int = -1
var variation_mode_: bool = false
var variation_original_notes_: GoNotes
var variation_original_follow_current_: bool = true
var variation_original_view_uid_: int = 0
var variation_original_next_color_: int = kBlack
var variation_original_locked_: bool = false
var variation_start_color_: int = kBlack
var variation_base_uid_: int = 0
var edit_sensitive_action_gate_: Callable
var note_numbering_preview_enabled_: bool = false
var note_numbering_preview_uid_: int = -1
var note_numbering_preview_index_: int = -1
var displayed_note_sequential_marks_: Array[Dictionary] = []
var displayed_note_symbol_marks_: Array[Dictionary] = []
var note_mark_mode_: int = kNoteMarkDisabled
var active_note_symbol_: String = ""


func _ready() -> void:
	connect_settings_signal_()
	apply_configured_textures_()
	set_process_unhandled_input(true)
	takeback_confirmation_.confirmed.connect(on_takeback_confirmed_)
	cut_branch_confirmation_.confirmed.connect(on_cut_branch_confirmed_)
	cut_branch_confirmation_.canceled.connect(on_cut_branch_canceled_)
	playback_bar_.value_changed.connect(on_playback_value_changed_)
	playback_bar_.gui_input.connect(on_playback_bar_gui_input_)
	playback_bar_.mouse_exited.connect(on_playback_bar_mouse_exited_)
	playback_previous_button_.pressed.connect(on_playback_previous_pressed_)
	playback_next_button_.pressed.connect(on_playback_next_pressed_)
	playback_button_.pressed.connect(on_playback_button_pressed_)
	playback_timer_.timeout.connect(on_playback_timer_timeout_)
	if go_notes_ == null:
		go_notes_ = GoNotes.new()
		follow_current_ = true
		view_uid_ = 0
	connect_go_notes_signal_()
	if initial_board_size != int(go_notes_.get_board_size()):
		if not initialize_board(initial_board_size):
			return
	elif not refresh_view_():
		push_error("Failed to read the initial board position.")


func initialize_board(board_size: int) -> bool:
	if not is_supported_board_size_(board_size):
		push_error("Unsupported board size: %d" % board_size)
		return false
	if go_notes_ == null:
		push_error("GoBoardView has no GoNotes document.")
		return false

	follow_current_ = true
	var reset_succeeded: bool = go_notes_.reset(board_size)
	if not reset_succeeded:
		push_error("Failed to initialize board: %s" % go_notes_.get_message())
		return false
	return refresh_view_()


func bind_go_notes(notes: GoNotes, view_uid: int = -1) -> bool:
	if notes == null:
		push_error("Cannot bind a null GoNotes document.")
		return false
	disconnect_go_notes_signal_()
	go_notes_ = notes
	follow_current_ = view_uid < 0
	view_uid_ = 0 if follow_current_ else view_uid
	connect_go_notes_signal_()
	if is_node_ready():
		return refresh_view_()
	return true


func set_view_uid(view_uid: int) -> bool:
	if view_uid < 0 or go_notes_ == null:
		return false
	follow_current_ = false
	view_uid_ = view_uid
	return refresh_view_()


func follow_current_position() -> bool:
	if go_notes_ == null:
		return false
	follow_current_ = true
	return refresh_view_()


func is_following_current_position() -> bool:
	return follow_current_


func get_view_uid() -> int:
	return view_uid_


func get_setup_branches() -> Array[Dictionary]:
	return setup_branches_.duplicate(true)


func set_setup_branch_preview(uid: int) -> bool:
	if go_notes_ == null or setup_branch_preview_ == null:
		return false
	var found: bool = false
	for branch: Dictionary in setup_branches_:
		if int(branch.get("uid", -1)) == uid:
			found = true
			break
	if not found:
		return false
	var target_states: PackedInt32Array = PackedInt32Array(
		go_notes_.call(&"get_position_at", uid)
	)
	if target_states.size() != position_states_.size():
		return false
	var changes: Array[Dictionary] = []
	var radius: float = cell_size_() * kStoneDiameterCellRatio * 0.5
	for index in range(target_states.size()):
		var target: int = target_states[index]
		if target == position_states_[index]:
			continue
		var row: int = floori(float(index) / float(board_size_)) + 1
		var column: int = index % board_size_ + 1
		changes.append({
			"center": Vector2(
				grid_coordinate_(float(column - 1)),
				grid_coordinate_(float(row - 1))
			),
			"radius": radius,
			"target": target,
		})
	setup_preview_uid_ = uid
	setup_branch_preview_.show_changes(changes)
	refresh_hover_stone_()
	return true


func clear_setup_branch_preview() -> void:
	setup_preview_uid_ = -1
	if setup_branch_preview_ != null:
		setup_branch_preview_.clear_changes()
	refresh_hover_stone_()


func roam_to_setup_branch(uid: int) -> bool:
	var exists: bool = false
	for branch: Dictionary in setup_branches_:
		if int(branch.get("uid", -1)) == uid:
			exists = true
			break
	if not exists:
		return false
	clear_setup_branch_preview()
	set_playback_playing_(false)
	return execute_roaming_to_(uid)


func get_go_notes() -> GoNotes:
	return go_notes_


func get_board_size() -> int:
	return board_size_


func get_next_color() -> int:
	return next_color_


func get_next_color_texture() -> Texture2D:
	return black_texture_ if next_color_ == kBlack else white_texture_


func get_find_direction() -> int:
	return find_direction_


func is_cut_branch_mode() -> bool:
	return cut_branch_mode_


func get_playback_path() -> PackedInt64Array:
	return playback_path_.duplicate()


func set_edit_sensitive_action_gate(gate: Callable) -> void:
	edit_sensitive_action_gate_ = gate


func stop_playback() -> void:
	set_playback_playing_(false)


func restore_playback_position() -> void:
	refresh_playback_path_()


func set_note_numbering_preview(
		enabled: bool,
		uid: int,
		note_index: int
) -> void:
	note_numbering_preview_enabled_ = enabled and uid >= 0 and note_index >= 0
	note_numbering_preview_uid_ = uid if note_numbering_preview_enabled_ else -1
	note_numbering_preview_index_ = \
		note_index if note_numbering_preview_enabled_ else -1
	if not position_states_.is_empty() and not refresh_position_():
		push_error("Failed to refresh note move-number preview.")


func roam_to_playback_uid(uid: int) -> bool:
	if go_notes_ == null or not follow_current_ or playback_path_.find(uid) < 0:
		return false
	if uid == int(go_notes_.get_current_uid()):
		return true
	var path_index: int = playback_path_.find(uid)
	on_playback_value_changed_(float(path_index))
	return uid == int(go_notes_.get_current_uid())


func set_analysis_candidates(move_infos: Array) -> void:
	if analysis_candidates_overlay_ == null:
		return
	var candidates: Array[Dictionary] = []
	for info_value: Variant in move_infos:
		if candidates.size() >= 3:
			break
		var info: Dictionary = Dictionary(info_value)
		var intersection: Vector2i = gtp_coordinate_to_intersection_(
			str(info.get("move", "")).strip_edges().to_upper()
		)
		if intersection == Vector2i.ZERO:
			continue
		var candidate_winrate: float = float(info.get("winrate", 0.0))
		if next_color_ == kWhite:
			candidate_winrate = 1.0 - candidate_winrate
		candidates.append({
			"row": intersection.y,
			"column": intersection.x,
			"winrate": candidate_winrate,
		})
	analysis_candidates_overlay_.configure(
		candidates, board_size_, cell_size_()
	)


func clear_analysis_candidates() -> void:
	if analysis_candidates_overlay_ != null:
		analysis_candidates_overlay_.clear_candidates()


func is_variation_mode() -> bool:
	return variation_mode_


func enter_variation_mode() -> bool:
	if variation_mode_ or go_notes_ == null \
			or position_states_.size() != board_size_ * board_size_:
		return false
	var temporary_notes: GoNotes = create_variation_notes_()
	if temporary_notes == null:
		return false

	variation_original_notes_ = go_notes_
	variation_original_follow_current_ = follow_current_
	variation_original_view_uid_ = view_uid_
	variation_original_next_color_ = next_color_
	variation_original_locked_ = interactions_locked_
	variation_start_color_ = next_color_
	variation_base_uid_ = int(temporary_notes.get_current_uid())
	set_find_mode_(kFindDisabled)
	set_cut_branch_mode_(false)
	set_preset_mode_(false)
	set_playback_playing_(false)
	set_variation_navigation_mode_(true)
	variation_mode_ = true
	set_interactions_locked(false)
	if not bind_go_notes(temporary_notes):
		variation_mode_ = false
		var _rollback_bound: bool = bind_go_notes(variation_original_notes_)
		set_interactions_locked(variation_original_locked_)
		set_variation_navigation_mode_(false)
		clear_variation_restore_state_()
		return false
	set_next_color_(variation_start_color_)
	variation_mode_changed.emit(true)
	return true


func enter_analysis_variation(pv: Array) -> bool:
	if pv.is_empty() or not enter_variation_mode():
		return false
	var color: int = variation_start_color_
	var placed_moves: int = 0
	for move_value: Variant in pv:
		var move: String = str(move_value).strip_edges().to_upper()
		if move == "PASS" or move == "RESIGN":
			break
		var intersection: Vector2i = gtp_coordinate_to_intersection_(move)
		if intersection == Vector2i.ZERO:
			break
		var command: String = "PLACESTONE,%d,%d,%d;" % [
			color, intersection.y, intersection.x
		]
		if int(go_notes_.execute_command(command)) != 0:
			break
		placed_moves += 1
		color = kWhite if color == kBlack else kBlack
	if placed_moves <= 0:
		var _exited: bool = exit_variation_mode()
		return false
	set_next_color_(color)
	return true


func gtp_coordinate_to_intersection_(coordinate: String) -> Vector2i:
	if coordinate.length() < 2:
		return Vector2i.ZERO
	var column_index: int = kCoordinateLetters.find(coordinate.substr(0, 1))
	var row_text: String = coordinate.substr(1)
	if column_index < 0 or not row_text.is_valid_int():
		return Vector2i.ZERO
	var row_from_bottom: int = int(row_text)
	var row: int = board_size_ - row_from_bottom + 1
	var column: int = column_index + 1
	if row < 1 or row > board_size_ or column < 1 or column > board_size_:
		return Vector2i.ZERO
	return Vector2i(column, row)


func exit_variation_mode() -> bool:
	if not variation_mode_ or variation_original_notes_ == null:
		return false
	var original_notes: GoNotes = variation_original_notes_
	var original_follow: bool = variation_original_follow_current_
	var original_view_uid: int = variation_original_view_uid_
	var original_next_color: int = variation_original_next_color_
	var original_locked: bool = variation_original_locked_
	variation_mode_ = false
	var restored: bool = bind_go_notes(
		original_notes, -1 if original_follow else original_view_uid
	)
	if not restored and not original_follow:
		restored = bind_go_notes(original_notes)
	set_interactions_locked(original_locked)
	set_next_color_(original_next_color)
	set_variation_navigation_mode_(false)
	clear_variation_restore_state_()
	variation_mode_changed.emit(false)
	return restored


func keep_variation_branch() -> bool:
	if not variation_mode_ or variation_original_notes_ == null:
		return false
	var variation_moves: Array[Dictionary] = variation_path_moves_()
	if variation_moves.is_empty() \
			and int(go_notes_.get_current_uid()) != variation_base_uid_:
		return false
	var original_notes: GoNotes = variation_original_notes_
	var base_uid: int = variation_original_view_uid_
	if not exit_variation_mode():
		return false
	if int(original_notes.get_current_uid()) != base_uid:
		var roam_result: int = int(original_notes.execute_command(
			"ROAMING,%d;" % base_uid
		))
		if roam_result != 0:
			push_warning(CommandMessages.localize(original_notes.get_message()))
			return false
	for index in range(variation_moves.size()):
		var move: Dictionary = variation_moves[index]
		var command: String = "PLACESTONE,%d,%d,%d;" % [
			int(move.get("color", 0)),
			int(move.get("row", 0)),
			int(move.get("column", 0))
		]
		if int(original_notes.execute_command(command)) != 0:
			push_warning(CommandMessages.localize(original_notes.get_message()))
			return false
	return true


func variation_path_moves_() -> Array[Dictionary]:
	var moves: Array[Dictionary] = []
	var path: PackedInt64Array = PackedInt64Array(
		go_notes_.call(&"get_straightforward_path")
	)
	var base_index: int = path.find(variation_base_uid_)
	if base_index < 0:
		return moves
	for index in range(base_index + 1, path.size()):
		var node_data: Dictionary = Dictionary(
			go_notes_.call(&"get_node_at", int(path[index]))
		)
		var color: int = int(node_data.get("color", 0))
		if node_data.is_empty() or (color != kBlack and color != kWhite):
			moves.clear()
			return moves
		moves.append(node_data)
	return moves


func set_variation_navigation_mode_(enabled: bool) -> void:
	playback_bar_.show()
	playback_previous_button_.show()
	playback_next_button_.show()
	playback_button_.visible = not enabled
	if enabled:
		playback_hover_bubble_.hide()


func create_variation_notes_() -> GoNotes:
	var temporary_notes: GoNotes = GoNotes.new()
	if not temporary_notes.reset(board_size_):
		push_warning(temporary_notes.get_message())
		return null
	var empty_position := PackedInt32Array()
	empty_position.resize(position_states_.size())
	var command: String = build_preset_command_(
		empty_position, position_states_
	)
	if not command.is_empty() \
			and int(temporary_notes.execute_command(command)) != 0:
		push_warning(CommandMessages.localize(
			temporary_notes.get_message()
		))
		return null
	return temporary_notes


func clear_variation_restore_state_() -> void:
	variation_original_notes_ = null
	variation_original_follow_current_ = true
	variation_original_view_uid_ = 0
	variation_original_next_color_ = kBlack
	variation_base_uid_ = 0
	variation_original_locked_ = false


func toggle_next_color() -> void:
	var color: int = kWhite if next_color_ == kBlack else kBlack
	set_next_color_(color)


func toggle_preset_mode() -> void:
	if preset_mode_:
		set_preset_mode_(false)
		return
	if interactions_locked_ or not follow_current_ or go_notes_ == null:
		return
	if int(go_notes_.call(&"can_preset_stone")) != 0:
		return
	set_preset_mode_(true)


func is_preset_mode() -> bool:
	return preset_mode_


func set_displayed_note_marks(
	sequential_marks: Array[Dictionary],
	symbol_marks: Array[Dictionary]
) -> void:
	displayed_note_sequential_marks_ = sequential_marks.duplicate(true)
	displayed_note_symbol_marks_ = symbol_marks.duplicate(true)
	refresh_note_marks_overlay_()


func refresh_note_marks_overlay_() -> void:
	if not is_node_ready() or note_marks_overlay_ == null:
		return
	note_marks_overlay_.call(
		&"configure",
		displayed_note_sequential_marks_,
		displayed_note_symbol_marks_,
		board_size_,
		cell_size_()
	)


func begin_note_sequential_mark_mode(
	sequential_marks: Array[Dictionary],
	symbol_marks: Array[Dictionary]
) -> void:
	set_displayed_note_marks(sequential_marks, symbol_marks)
	note_mark_mode_ = kNoteSequentialMarkMode
	begin_note_mark_mode_()


func begin_note_symbol_mark_mode(
	sequential_marks: Array[Dictionary],
	symbol_marks: Array[Dictionary],
	initial_symbol: String
) -> void:
	set_displayed_note_marks(sequential_marks, symbol_marks)
	active_note_symbol_ = initial_symbol
	note_mark_mode_ = kNoteSymbolMarkMode
	begin_note_mark_mode_()


func set_active_note_symbol(symbol: String) -> void:
	active_note_symbol_ = symbol
	note_mark_draft_changed.emit()


func get_note_sequential_mark_draft() -> Array[Dictionary]:
	return displayed_note_sequential_marks_.duplicate(true)


func get_note_symbol_mark_draft() -> Array[Dictionary]:
	return displayed_note_symbol_marks_.duplicate(true)


func get_note_sequential_mark_count() -> int:
	return displayed_note_sequential_marks_.size()


func end_note_mark_mode() -> void:
	note_mark_mode_ = kNoteMarkDisabled
	active_note_symbol_ = ""
	set_note_board_controls_visible_(true)
	refresh_hover_stone_()
	queue_redraw()


func is_note_mark_mode() -> bool:
	return note_mark_mode_ != kNoteMarkDisabled


func begin_note_mark_mode_() -> void:
	set_find_mode_(kFindDisabled)
	set_cut_branch_mode_(false)
	set_playback_playing_(false)
	set_note_board_controls_visible_(false)
	refresh_hover_stone_()
	queue_redraw()


func set_note_board_controls_visible_(visible: bool) -> void:
	preset_button_.visible = visible
	playback_bar_.visible = visible
	playback_previous_button_.visible = visible
	playback_next_button_.visible = visible
	playback_button_.visible = visible
	if not visible:
		playback_hover_bubble_.hide()


func accept_preset_mode() -> bool:
	if not preset_mode_:
		return false
	set_preset_mode_(false)
	return not preset_mode_


func cancel_preset_mode() -> bool:
	if not preset_mode_:
		return false
	position_states_ = PackedInt32Array(preset_original_states_)
	move_numbers_ = PackedInt32Array(preset_original_move_numbers_)
	preset_mode_ = false
	preset_editing_current_ = false
	clear_preset_draft_()
	infer_next_color_()
	preset_mode_changed.emit(false)
	refresh_stones_()
	refresh_hover_stone_()
	return true


func set_interactions_locked(locked: bool) -> void:
	if locked and preset_mode_:
		set_preset_mode_(false)
		if preset_mode_:
			return
	interactions_locked_ = locked
	if not is_node_ready():
		return
	if locked and takeback_confirmation_.visible:
		takeback_confirmation_.hide()
	update_playback_editable_()
	refresh_hover_stone_()


func is_interactions_locked() -> bool:
	return interactions_locked_


func toggle_find_mode(direction: int) -> void:
	if direction != kFindTowardParent \
			and direction != kFindTowardFirstChild:
		push_error("Unsupported find direction: %d" % direction)
		return
	var new_direction: int = kFindDisabled \
		if find_direction_ == direction else direction
	set_find_mode_(new_direction)


func toggle_cut_branch_mode() -> void:
	if not follow_current_ or go_notes_ == null:
		return
	set_cut_branch_mode_(not cut_branch_mode_)


func connect_settings_signal_() -> void:
	var callback: Callable = Callable(self, "on_configured_textures_changed_")
	if not SettingsStore.is_connected(&"textures_changed", callback):
		SettingsStore.connect(&"textures_changed", callback)
	var numbers_callback: Callable = Callable(self, "on_move_number_settings_changed_")
	if not SettingsStore.is_connected(&"move_numbers_changed", numbers_callback):
		SettingsStore.connect(&"move_numbers_changed", numbers_callback)

	var playback_callback: Callable = Callable(self, "on_playback_interval_changed_")
	if not SettingsStore.is_connected(&"playback_interval_changed", playback_callback):
		SettingsStore.connect(&"playback_interval_changed", playback_callback)


func apply_configured_textures_() -> void:
	var configured_board_texture: Texture2D = \
		SettingsStore.get_board_texture()
	var configured_black_texture: Texture2D = \
		SettingsStore.get_black_stone_texture()
	var configured_white_texture: Texture2D = \
		SettingsStore.get_white_stone_texture()
	if configured_board_texture == null or configured_black_texture == null:
		push_error("Configured board or black stone texture is unavailable.")
		return
	if configured_white_texture == null:
		push_error("Configured white stone texture is unavailable.")
		return

	texture = configured_board_texture
	black_texture_ = configured_black_texture
	white_texture_ = configured_white_texture
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	board_texture_changed.emit()
	queue_redraw()


func on_configured_textures_changed_() -> void:
	apply_configured_textures_()
	if not position_states_.is_empty():
		refresh_stones_()
	refresh_hover_stone_()


func on_move_number_settings_changed_() -> void:
	if not position_states_.is_empty() and not refresh_position_():
		push_error("Failed to refresh move numbers.")


func on_playback_interval_changed_() -> void:
	if playback_playing_:
		schedule_playback_step_()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var mouse_event: InputEventMouseMotion = \
			event as InputEventMouseMotion
		hover_screen_position_ = mouse_event.position
		has_hover_position_ = true
		refresh_hover_stone_()
		return
	if event is not InputEventKey:
		return

	if not is_node_ready():
		return
	var key_event: InputEventKey = event as InputEventKey
	if not key_event.pressed:
		return
	if cut_branch_confirmation_.visible:
		return
	if key_event.keycode == KEY_ESCAPE and is_note_mark_mode():
		note_mark_cancel_requested.emit()
		get_viewport().set_input_as_handled()
		return
	if key_event.keycode == KEY_ESCAPE and preset_mode_:
		var _preset_canceled: bool = cancel_preset_mode()
		get_viewport().set_input_as_handled()
		return
	if key_event.keycode == KEY_ESCAPE and variation_mode_:
		var _variation_exited: bool = exit_variation_mode()
		get_viewport().set_input_as_handled()
		return
	if variation_mode_:
		return
	if is_note_mark_mode():
		return
	if key_event.keycode == KEY_ESCAPE:
		var escape_handled: bool = false
		if find_direction_ != kFindDisabled:
			set_find_mode_(kFindDisabled)
			escape_handled = true
		if cut_branch_mode_:
			set_cut_branch_mode_(false)
			escape_handled = true
		if playback_playing_:
			set_playback_playing_(false)
			escape_handled = true
		if escape_handled:
			get_viewport().set_input_as_handled()
			return
	if key_event.ctrl_pressed \
			or key_event.alt_pressed or key_event.meta_pressed:
		return

	var direction: int = 0
	match key_event.keycode:
		KEY_LEFT:
			direction = -1
		KEY_RIGHT:
			direction = 1
		_:
			return

	if takeback_confirmation_.visible or cut_branch_confirmation_.visible:
		return
	var focus_owner: Control = get_viewport().gui_get_focus_owner()
	if focus_owner is OptionButton or focus_owner is LineEdit \
			or focus_owner is TextEdit or focus_owner is Tree \
			or focus_owner is ItemList:
		return

	if navigate_playback_by_(direction):
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if not follow_current_ or go_notes_ == null \
			or takeback_confirmation_.visible \
			or cut_branch_confirmation_.visible:
		return
	if event is not InputEventMouseButton:
		return

	var mouse_event: InputEventMouseButton = event as InputEventMouseButton
	if not mouse_event.pressed:
		return
	if is_note_mark_mode():
		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			toggle_note_mark_at_(mouse_event.position)
			get_viewport().set_input_as_handled()
		return

	var playback_direction: int = 0
	if mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP:
		playback_direction = -1
	elif mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		playback_direction = 1
	if playback_direction != 0:
		if is_screen_position_on_board_(mouse_event.position) \
				and navigate_playback_by_(playback_direction):
			get_viewport().set_input_as_handled()
		return

	if mouse_event.button_index == MOUSE_BUTTON_LEFT:
		if find_direction_ != kFindDisabled:
			if try_find_at_(mouse_event.position):
				get_viewport().set_input_as_handled()
			return
		if cut_branch_mode_:
			if try_cut_branch_at_(mouse_event.position):
				get_viewport().set_input_as_handled()
			return
		if not variation_mode_ and not preset_mode_ \
				and try_activate_branch_at_(mouse_event.position):
			get_viewport().set_input_as_handled()
			return
		if interactions_locked_:
			return
		if variation_mode_ and not is_variation_terminal_position_():
			return
		place_stone_at_screen_position_(mouse_event.position)
	elif mouse_event.button_index == MOUSE_BUTTON_RIGHT:
		if variation_mode_:
			request_takeback_()
			return
		if find_direction_ != kFindDisabled:
			set_find_mode_(kFindDisabled)
			get_viewport().set_input_as_handled()
			return
		if cut_branch_mode_:
			set_cut_branch_mode_(false)
			get_viewport().set_input_as_handled()
			return
		if preset_mode_:
			place_stone_at_screen_position_(mouse_event.position, 0)
			return
		if interactions_locked_:
			if navigate_playback_by_(-1):
				get_viewport().set_input_as_handled()
			return
		request_takeback_()


func is_screen_position_on_board_(screen_position: Vector2) -> bool:
	var inverse_canvas_transform: Transform2D = \
		get_global_transform_with_canvas().affine_inverse()
	var local_position: Vector2 = inverse_canvas_transform * screen_position
	return get_rect().has_point(local_position)


func intersection_at_screen_position_(
		screen_position: Vector2
) -> Vector2i:
	var inverse_canvas_transform: Transform2D = \
		get_global_transform_with_canvas().affine_inverse()
	var local_position: Vector2 = inverse_canvas_transform * screen_position
	var cell_size: float = cell_size_()
	var grid_half_extent: float = grid_half_extent_()
	var column_index: int = roundi(
		(local_position.x + grid_half_extent) / cell_size
	)
	var row_index: int = roundi(
		(local_position.y + grid_half_extent) / cell_size
	)
	if row_index < 0 or row_index >= board_size_:
		return Vector2i.ZERO
	if column_index < 0 or column_index >= board_size_:
		return Vector2i.ZERO

	var intersection: Vector2 = Vector2(
		grid_coordinate_(float(column_index)),
		grid_coordinate_(float(row_index))
	)
	if local_position.distance_to(intersection) > \
			cell_size * kIntersectionHitRadiusRatio:
		return Vector2i.ZERO
	return Vector2i(column_index + 1, row_index + 1)


func refresh_hover_stone_() -> void:
	if not is_node_ready() or hover_stone_ == null or find_hover_ == null \
			or cut_branch_hover_ == null:
		return
	hover_stone_.hide()
	find_hover_.hide()
	cut_branch_hover_.hide()
	if is_note_mark_mode():
		return
	if setup_preview_uid_ >= 0:
		return
	if not follow_current_ or go_notes_ == null or not has_hover_position_:
		return

	var intersection: Vector2i = intersection_at_screen_position_(
		hover_screen_position_
	)
	if intersection == Vector2i.ZERO:
		return
	if find_direction_ != kFindDisabled:
		show_find_hover_(intersection)
		return
	if cut_branch_mode_:
		show_cut_branch_hover_(intersection)
		return
	if interactions_locked_:
		return
	if variation_mode_ and not is_variation_terminal_position_():
		return
	var row: int = intersection.y
	var column: int = intersection.x
	var can_place: bool = int(go_notes_.call(&"can_preset_stone")) == 0 \
		if preset_mode_ else bool(
			go_notes_.call(&"can_place_stone", next_color_, row, column)
		)
	if not can_place:
		return

	var hover_texture: Texture2D = stone_texture_(
		next_color_, row, column
	)
	if hover_texture == null:
		return
	hover_stone_.texture = hover_texture
	hover_stone_.position = Vector2(
		grid_coordinate_(float(column - 1)),
		grid_coordinate_(float(row - 1))
	)
	var texture_size: Vector2 = hover_texture.get_size()
	var texture_extent: float = maxf(texture_size.x, texture_size.y)
	var scale_factor: float = \
		cell_size_() * kStoneDiameterCellRatio / texture_extent
	hover_stone_.scale = Vector2.ONE * scale_factor
	hover_stone_.modulate = Color(1.0, 1.0, 1.0, kHoverStoneOpacity)
	hover_stone_.texture_filter = \
		CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	hover_stone_.show()


func show_find_hover_(intersection: Vector2i) -> void:
	var find_texture: Texture2D = find_hover_.texture
	if find_texture == null:
		return
	find_hover_.position = Vector2(
		grid_coordinate_(float(intersection.x - 1)),
		grid_coordinate_(float(intersection.y - 1))
	)
	var texture_size: Vector2 = find_texture.get_size()
	var texture_extent: float = maxf(texture_size.x, texture_size.y)
	var scale_factor: float = \
		cell_size_() * kFindHoverDiameterCellRatio / texture_extent
	find_hover_.scale = Vector2.ONE * scale_factor
	find_hover_.modulate = Color(1.0, 1.0, 1.0, kFindHoverOpacity)
	find_hover_.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	find_hover_.show()


func show_cut_branch_hover_(intersection: Vector2i) -> void:
	var hover_texture: Texture2D = cut_branch_hover_.texture
	if hover_texture == null:
		return
	cut_branch_hover_.position = Vector2(
		grid_coordinate_(float(intersection.x - 1)),
		grid_coordinate_(float(intersection.y - 1))
	)
	var texture_size: Vector2 = hover_texture.get_size()
	var texture_extent: float = maxf(texture_size.x, texture_size.y)
	var scale_factor: float = \
		cell_size_() * kCutBranchHoverDiameterCellRatio / texture_extent
	cut_branch_hover_.scale = Vector2.ONE * scale_factor
	cut_branch_hover_.texture_filter = \
		CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	cut_branch_hover_.show()


func set_find_mode_(direction: int) -> void:
	if find_direction_ == direction:
		return
	if direction != kFindDisabled and preset_mode_:
		set_preset_mode_(false)
		if preset_mode_:
			return
	find_direction_ = direction
	if find_direction_ != kFindDisabled:
		set_cut_branch_mode_(false)
		set_playback_playing_(false)
	find_mode_changed.emit(find_direction_)
	refresh_hover_stone_()


func set_cut_branch_mode_(enabled: bool) -> void:
	if cut_branch_mode_ == enabled:
		return
	if enabled and preset_mode_:
		set_preset_mode_(false)
		if preset_mode_:
			return
	cut_branch_mode_ = enabled
	if cut_branch_mode_:
		set_find_mode_(kFindDisabled)
		set_playback_playing_(false)
	cut_branch_mode_changed.emit(cut_branch_mode_)
	refresh_hover_stone_()


func set_next_color_(color: int) -> void:
	if next_color_ == color:
		return
	next_color_ = color
	next_color_changed.emit(next_color_)
	refresh_hover_stone_()


func set_preset_mode_(enabled: bool) -> void:
	if preset_mode_ == enabled:
		return
	if not enabled and preset_mode_ and not commit_preset_draft_():
		refresh_hover_stone_()
		return

	preset_mode_ = enabled
	if preset_mode_:
		var current_node: Dictionary = Dictionary(
			go_notes_.call(&"get_node_at", view_uid_)
		)
		preset_editing_current_ = view_uid_ > 0 \
				and int(current_node.get("color", -1)) == 0
		preset_original_states_ = PackedInt32Array(position_states_)
		preset_original_move_numbers_ = PackedInt32Array(move_numbers_)
		preset_draft_states_ = PackedInt32Array(position_states_)
		set_find_mode_(kFindDisabled)
		set_cut_branch_mode_(false)
		set_playback_playing_(false)
	else:
		preset_editing_current_ = false
		clear_preset_draft_()
		infer_next_color_()
	preset_mode_changed.emit(preset_mode_)
	refresh_hover_stone_()


func commit_preset_draft_() -> bool:
	var command: String = build_preset_command_(
		preset_original_states_, preset_draft_states_
	)
	if command.is_empty():
		return true
	var result: int = int(go_notes_.execute_command(command))
	if result == 0:
		return true
	var native_message: String = go_notes_.get_message()
	var localized_message: String = CommandMessages.localize(native_message)
	push_warning(localized_message)
	if native_message.begins_with("[GNE0037]"):
		var failed_uid: int = int(go_notes_.call(&"get_error_uid"))
		position_states_ = PackedInt32Array(preset_original_states_)
		move_numbers_ = PackedInt32Array(preset_original_move_numbers_)
		preset_edit_error_dialog_.dialog_text = (
			"修改后的预置局面无法重放后续棋局（首个冲突节点 UID：%d）。\n"
			+ "本次修改已放弃。如需修改，请先剪掉与新局面冲突的后续分支。"
		) % failed_uid
		preset_edit_error_dialog_.popup_centered()
		preset_edit_replay_failed.emit(failed_uid)
		refresh_stones_()
		return true
	preset_mode_changed.emit(true)
	return false


func build_preset_command_(
		original_states: PackedInt32Array,
		final_states: PackedInt32Array
) -> String:
	if original_states.size() != final_states.size() \
			or final_states.size() != board_size_ * board_size_:
		return ""
	var command_name: String = "EDITPRESET" if preset_editing_current_ \
			else "PRESET"
	var fields := PackedStringArray([command_name])
	for index in range(final_states.size()):
		if original_states[index] == final_states[index]:
			continue
		var row: int = floori(float(index) / float(board_size_)) + 1
		var column: int = index % board_size_ + 1
		fields.append(str(final_states[index]))
		fields.append(str(row))
		fields.append(str(column))
	return "" if fields.size() == 1 else ",".join(fields) + ";"


func clear_preset_draft_() -> void:
	preset_original_states_ = PackedInt32Array()
	preset_original_move_numbers_ = PackedInt32Array()
	preset_draft_states_ = PackedInt32Array()


func infer_next_color_() -> void:
	if go_notes_ == null:
		return
	var latest_color: int = int(go_notes_.call(&"get_latest_move_color"))
	set_next_color_(kWhite if latest_color == kBlack else kBlack)

func try_find_at_(screen_position: Vector2) -> bool:
	var intersection: Vector2i = intersection_at_screen_position_(
		screen_position
	)
	if intersection == Vector2i.ZERO:
		return false
	var direction: int = find_direction_
	request_edit_sensitive_action_(
		Callable(self, "execute_find_now_").bind(direction, intersection)
	)
	return true


func execute_find_now_(direction: int, intersection: Vector2i) -> void:
	set_find_mode_(kFindDisabled)
	var command: String = "FIND,%d,%d,%d;" % [
		direction, intersection.y, intersection.x
	]
	var result: int = int(go_notes_.execute_command(command))
	if result != 0:
		var message: String = CommandMessages.localize(
			go_notes_.get_message()
		)
		if message.is_empty():
			message = "没有在指定方向找到这颗棋子。"
		find_result_dialog_.dialog_text = message
		find_result_dialog_.popup_centered(Vector2i(420, 160))

func _draw() -> void:
	var canvas_transform: Transform2D = get_global_transform_with_canvas()
	var inverse_canvas_transform: Transform2D = canvas_transform.affine_inverse()
	var canvas_scale: float = maxf(canvas_transform.x.length(), 0.001)
	var cell_size: float = cell_size_()
	var grid_half_extent: float = grid_half_extent_()
	var screen_line_width: float = clampf(
		cell_size * canvas_scale * kGridLineCellRatio,
		kMinGridLinePixels,
		kMaxGridLinePixels
	)
	var local_line_width: float = screen_line_width / canvas_scale

	for index in range(board_size_):
		var coordinate: float = grid_coordinate_(float(index))
		var line_width: float = local_line_width
		if index == 0 or index == board_size_ - 1:
			line_width *= kOuterGridLineWidthRatio
		var horizontal_begin := snap_to_pixel_center_(
			Vector2(-grid_half_extent, coordinate),
			canvas_transform,
			inverse_canvas_transform
		)
		var horizontal_end := snap_to_pixel_center_(
			Vector2(grid_half_extent, coordinate),
			canvas_transform,
			inverse_canvas_transform
		)
		var vertical_begin := snap_to_pixel_center_(
			Vector2(coordinate, -grid_half_extent),
			canvas_transform,
			inverse_canvas_transform
		)
		var vertical_end := snap_to_pixel_center_(
			Vector2(coordinate, grid_half_extent),
			canvas_transform,
			inverse_canvas_transform
		)
		draw_line(
			horizontal_begin,
			horizontal_end,
			kGridColor,
			line_width,
			true
		)
		draw_line(
			vertical_begin,
			vertical_end,
			kGridColor,
			line_width,
			true
		)

	var star_radius_pixels: float = clampf(
		cell_size * canvas_scale * kStarRadiusCellRatio,
		kMinStarRadiusPixels,
		kMaxStarRadiusPixels
	)
	var local_star_radius: float = star_radius_pixels / canvas_scale
	for star_position in get_star_positions_():
		var star_point := snap_to_pixel_center_(
			Vector2(
				grid_coordinate_(star_position.x),
				grid_coordinate_(star_position.y)
			),
			canvas_transform,
			inverse_canvas_transform
		)
		draw_circle(
			star_point,
			local_star_radius,
			kGridColor,
			true,
			-1.0,
			true
		)


	draw_coordinates_(cell_size)
	if not is_note_mark_mode():
		draw_branch_markers_(canvas_scale, cell_size)
	if note_marks_overlay_ != null:
		note_marks_overlay_.queue_redraw()


func draw_coordinates_(cell_size: float) -> void:
	var font: Font = ThemeDB.fallback_font
	if font == null:
		return
	var font_size: int = maxi(
		roundi(cell_size * kCoordinateFontCellRatio), 1
	)
	var outline_size: int = maxi(
		roundi(float(font_size) * kCoordinateOutlineFontRatio), 1
	)
	var label_offset: float = grid_half_extent_() + \
		cell_size * kCoordinateOffsetCellRatio

	for index in range(board_size_):
		var coordinate: float = grid_coordinate_(float(index))
		var letter: String = kCoordinateLetters.substr(index, 1)
		var number: String = str(board_size_ - index)
		draw_centered_coordinate_(
			font,
			letter,
			Vector2(coordinate, -label_offset),
			font_size,
			outline_size
		)
		draw_centered_coordinate_(
			font,
			letter,
			Vector2(coordinate, label_offset),
			font_size,
			outline_size
		)
		draw_centered_coordinate_(
			font,
			number,
			Vector2(-label_offset, coordinate),
			font_size,
			outline_size
		)
		draw_centered_coordinate_(
			font,
			number,
			Vector2(label_offset, coordinate),
			font_size,
			outline_size
		)


func draw_centered_coordinate_(
		font: Font,
		text: String,
		center: Vector2,
		font_size: int,
		outline_size: int
) -> void:
	var text_size: Vector2 = font.get_string_size(
		text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size
	)
	var baseline: Vector2 = Vector2(
		center.x - text_size.x * 0.5,
		center.y + (
			font.get_ascent(font_size) - font.get_descent(font_size)
		) * 0.5
	)
	draw_string_outline(
		font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0,
		font_size, outline_size, kCoordinateOutlineColor
	)
	draw_string(
		font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0,
		font_size, kCoordinateColor
	)


func draw_branch_markers_(canvas_scale: float, cell_size: float) -> void:
	var marker_size: float = cell_size * kBranchMarkerSizeCellRatio
	var marker_half_size: float = marker_size * 0.5
	var outline_width: float = 1.0 / canvas_scale
	var playback_next_uid: int = playback_next_uid_()
	for index in range(branch_moves_.size()):
		var branch: Dictionary = branch_moves_[index]
		var center: Vector2 = branch_local_position_(branch)
		var branch_uid: int = int(branch.get("uid", -1))
		if branch_uid != playback_next_uid:
			draw_circle(
				center,
				marker_half_size,
				kBranchMarkerFillColor,
				true,
				-1.0,
				true
			)
			draw_circle(
				center,
				marker_half_size,
				kBranchMarkerBorderColor,
				false,
				outline_width,
				true
			)
			continue
		var marker_rect: Rect2 = Rect2(
			center - Vector2.ONE * marker_half_size,
			Vector2.ONE * marker_size
		)
		draw_rect(marker_rect, kBranchMarkerFillColor, true)
		draw_rect(
			marker_rect,
			kBranchMarkerBorderColor,
			false,
			outline_width,
			true
		)


func playback_next_uid_() -> int:
	var current_index: int = playback_path_.find(view_uid_)
	if current_index < 0 or current_index >= playback_path_.size() - 1:
		return -1
	return int(playback_path_[current_index + 1])


func toggle_note_mark_at_(screen_position: Vector2) -> void:
	var intersection: Vector2i = intersection_at_screen_position_(
		screen_position
	)
	if intersection == Vector2i.ZERO:
		return
	if note_mark_mode_ == kNoteSequentialMarkMode:
		toggle_sequential_note_mark_(intersection)
	elif note_mark_mode_ == kNoteSymbolMarkMode:
		toggle_symbol_note_mark_(intersection)
	note_mark_draft_changed.emit()
	refresh_note_marks_overlay_()


func toggle_sequential_note_mark_(intersection: Vector2i) -> void:
	var existing_index: int = note_mark_index_at_(
		displayed_note_sequential_marks_, intersection
	)
	if existing_index >= 0:
		displayed_note_sequential_marks_.remove_at(existing_index)
		return
	if displayed_note_sequential_marks_.size() >= \
			kSequentialMarkLetters.length():
		return
	displayed_note_sequential_marks_.append({
		"row": intersection.y,
		"column": intersection.x
	})


func toggle_symbol_note_mark_(intersection: Vector2i) -> void:
	var existing_index: int = note_mark_index_at_(
		displayed_note_symbol_marks_, intersection
	)
	if active_note_symbol_.is_empty():
		if existing_index >= 0:
			displayed_note_symbol_marks_.remove_at(existing_index)
		return
	var mark: Dictionary = {
		"row": intersection.y,
		"column": intersection.x,
		"symbol": active_note_symbol_
	}
	if existing_index >= 0:
		displayed_note_symbol_marks_[existing_index] = mark
	else:
		displayed_note_symbol_marks_.append(mark)


func note_mark_index_at_(
	marks: Array[Dictionary],
	intersection: Vector2i
) -> int:
	for index in range(marks.size()):
		var mark: Dictionary = marks[index]
		if int(mark.get("row", 0)) == intersection.y \
				and int(mark.get("column", 0)) == intersection.x:
			return index
	return -1


func try_activate_branch_at_(screen_position: Vector2) -> bool:
	var branch: Dictionary = branch_at_screen_position_(screen_position)
	if branch.is_empty():
		return false
	if interactions_locked_:
		var target_uid: int = int(branch.get("uid", -1))
		var _roam_succeeded: bool = execute_roaming_to_(target_uid)
		return true
	var row: int = int(branch.get("row", 0))
	var column: int = int(branch.get("column", 0))
	if row < 1 or row > board_size_ \
			or column < 1 or column > board_size_:
		return false
	var _placed_or_roamed: bool = execute_place_stone_(
		next_color_, row, column
	)
	return true


func try_cut_branch_at_(screen_position: Vector2) -> bool:
	var branch: Dictionary = branch_at_screen_position_(screen_position)
	if branch.is_empty():
		return false
	request_edit_sensitive_action_(
		Callable(self, "show_cut_branch_confirmation_").bind(
			int(branch.get("uid", -1))
		)
	)
	return true


func show_cut_branch_confirmation_(target_uid: int) -> void:
	pending_cut_branch_uid_ = target_uid
	set_playback_playing_(false)
	cut_branch_confirmation_.popup_centered(Vector2i(460, 180))


func on_cut_branch_confirmed_() -> void:
	var target_uid: int = pending_cut_branch_uid_
	pending_cut_branch_uid_ = -1
	if not has_branch_uid_(target_uid):
		push_warning("所选分支已不存在。")
		return
	var command: String = "CUTBRANCH,%d;" % target_uid
	var result: int = int(go_notes_.execute_command(command))
	if result != 0:
		push_warning(CommandMessages.localize(go_notes_.get_message()))
		return
	set_cut_branch_mode_(false)


func on_cut_branch_canceled_() -> void:
	pending_cut_branch_uid_ = -1


func has_branch_uid_(target_uid: int) -> bool:
	for index in range(branch_moves_.size()):
		if int(branch_moves_[index].get("uid", -1)) == target_uid:
			return true
	return false


func branch_at_screen_position_(screen_position: Vector2) -> Dictionary:
	var inverse_canvas_transform: Transform2D = \
		get_global_transform_with_canvas().affine_inverse()
	var local_position: Vector2 = inverse_canvas_transform * screen_position
	var hit_half_size: float = cell_size_() * kBranchMarkerHitHalfCellRatio
	for index in range(branch_moves_.size()):
		var branch: Dictionary = branch_moves_[index]
		var center: Vector2 = branch_local_position_(branch)
		if absf(local_position.x - center.x) <= hit_half_size \
				and absf(local_position.y - center.y) <= hit_half_size:
			return branch
	return {}


func execute_roaming_to_(target_uid: int) -> bool:
	var outcome: Dictionary = {"completed": false, "success": true}
	request_edit_sensitive_action_(
		Callable(self, "execute_roaming_to_now_").bind(target_uid, outcome)
	)
	return bool(outcome.success) if bool(outcome.completed) else true


func execute_roaming_to_now_(target_uid: int, outcome: Dictionary) -> void:
	var command: String = "ROAMING,%d;" % target_uid
	var result: int = int(go_notes_.execute_command(command))
	outcome.completed = true
	if result != 0:
		outcome.success = false
		push_warning(CommandMessages.localize(go_notes_.get_message()))
		return
	outcome.success = true


func branch_local_position_(branch: Dictionary) -> Vector2:
	var row: int = int(branch.get("row", 0))
	var column: int = int(branch.get("column", 0))
	return Vector2(
		grid_coordinate_(float(column - 1)),
		grid_coordinate_(float(row - 1))
	)


func place_stone_at_screen_position_(
		screen_position: Vector2,
		preset_color: int = -1
) -> void:
	if interactions_locked_:
		return
	if variation_mode_ and not is_variation_terminal_position_():
		return
	var inverse_canvas_transform := get_global_transform_with_canvas().affine_inverse()
	var local_position: Vector2 = inverse_canvas_transform * screen_position
	var cell_size: float = cell_size_()
	var grid_half_extent: float = grid_half_extent_()
	var column_index: int = roundi(
		(local_position.x + grid_half_extent) / cell_size
	)
	var row_index: int = roundi(
		(local_position.y + grid_half_extent) / cell_size
	)
	if row_index < 0 or row_index >= board_size_:
		return
	if column_index < 0 or column_index >= board_size_:
		return

	var intersection := Vector2(
		grid_coordinate_(float(column_index)),
		grid_coordinate_(float(row_index))
	)
	if local_position.distance_to(intersection) > \
			cell_size * kIntersectionHitRadiusRatio:
		return

	var row: int = row_index + 1
	var column: int = column_index + 1
	var command_color: int = preset_color if preset_color >= 0 else next_color_
	if preset_mode_:
		var position_index: int = row_index * board_size_ + column_index
		if position_index < 0 or position_index >= preset_draft_states_.size():
			return
		if preset_draft_states_[position_index] == command_color:
			return
		preset_draft_states_[position_index] = command_color
		position_states_[position_index] = command_color
		move_numbers_[position_index] = preset_original_move_numbers_[position_index] \
			if command_color == preset_original_states_[position_index] else 0
		refresh_stones_()
		refresh_hover_stone_()
		get_viewport().set_input_as_handled()
		return

	if execute_place_stone_(command_color, row, column):
		get_viewport().set_input_as_handled()


func execute_place_stone_(color: int, row: int, column: int) -> bool:
	var outcome: Dictionary = {"completed": false, "success": true}
	request_edit_sensitive_action_(
		Callable(self, "execute_place_stone_now_").bind(
			color, row, column, outcome
		)
	)
	return bool(outcome.success) if bool(outcome.completed) else true


func execute_place_stone_now_(
		color: int,
		row: int,
		column: int,
		outcome: Dictionary
) -> void:
	var enters_existing_branch: bool = has_move_branch_(color, row, column)
	var command: String = "PLACESTONE,%d,%d,%d;" % [color, row, column]
	var result: int = int(go_notes_.execute_command(command))
	outcome.completed = true
	if result != 0:
		outcome.success = false
		push_warning(CommandMessages.localize(go_notes_.get_message()))
		return
	outcome.success = true
	if not enters_existing_branch:
		play_stone_sound_()


func has_move_branch_(color: int, row: int, column: int) -> bool:
	for branch: Dictionary in branch_moves_:
		if int(branch.get("color", 0)) == color \
				and int(branch.get("row", 0)) == row \
				and int(branch.get("column", 0)) == column:
			return true
	return false


func play_stone_sound_() -> void:
	var volume: int = SettingsStore.get_stone_sound_volume()
	if volume <= SettingsStore.kStoneSoundVolumeMinimum:
		return
	stone_sound_player_.stream = random_stone_sound_()
	stone_sound_player_.volume_db = linear_to_db(float(volume) / 100.0)
	stone_sound_player_.play()


func random_stone_sound_() -> AudioStream:
	match randi_range(0, 4):
		0:
			return kStoneSound0
		1:
			return kStoneSound1
		2:
			return kStoneSound2
		3:
			return kStoneSound3
		_:
			return kStoneSound4


func request_takeback_() -> void:
	if interactions_locked_:
		return
	if variation_mode_ and not can_takeback_variation_move_():
		return
	if not variation_mode_ and int(go_notes_.get_current_uid()) == 0:
		return
	request_edit_sensitive_action_(Callable(self, "show_takeback_confirmation_"))


func show_takeback_confirmation_() -> void:
	takeback_confirmation_.popup_centered(Vector2i(360, 160))
	get_viewport().set_input_as_handled()


func on_takeback_confirmed_() -> void:
	if interactions_locked_:
		return
	if variation_mode_ and not can_takeback_variation_move_():
		return
	takeback_last_move_()


func takeback_last_move_() -> void:
	if interactions_locked_:
		return
	if variation_mode_ and not can_takeback_variation_move_():
		return
	if not variation_mode_ and int(go_notes_.get_current_uid()) == 0:
		return

	var result: int = int(
		go_notes_.execute_command("TAKEBACK;")
	)
	if result != 0:
		push_warning(CommandMessages.localize(go_notes_.get_message()))
		return

	get_viewport().set_input_as_handled()


func is_variation_terminal_position_() -> bool:
	if not variation_mode_ or go_notes_ == null or playback_path_.is_empty():
		return false
	return int(go_notes_.get_current_uid()) == int(
		playback_path_[playback_path_.size() - 1]
	)


func can_takeback_variation_move_() -> bool:
	if not is_variation_terminal_position_():
		return false
	return int(go_notes_.get_current_uid()) != variation_base_uid_


func connect_go_notes_signal_() -> void:
	if go_notes_ == null:
		return
	var changed_callback: Callable = Callable(self, "on_go_notes_changed_")
	if not go_notes_.is_connected(&"changed", changed_callback):
		go_notes_.connect(&"changed", changed_callback)


func disconnect_go_notes_signal_() -> void:
	if go_notes_ == null:
		return
	var changed_callback: Callable = Callable(self, "on_go_notes_changed_")
	if go_notes_.is_connected(&"changed", changed_callback):
		go_notes_.disconnect(&"changed", changed_callback)


func on_go_notes_changed_() -> void:
	var previous_view_uid: int = view_uid_
	if preset_mode_ and int(go_notes_.call(&"can_preset_stone")) != 0:
		set_preset_mode_(false)
	if not playback_navigation_:
		set_playback_playing_(false)
	if not refresh_position_():
		follow_current_ = true
		if not refresh_position_():
			push_error("The shared GoNotes document has no readable position.")
			return
	if playback_navigation_:
		update_playback_position_()
		update_playback_editable_()
	else:
		refresh_playback_path_()
	if view_uid_ != previous_view_uid:
		position_changed.emit(view_uid_)


func refresh_view_() -> bool:
	if not refresh_position_():
		return false
	if not refresh_playback_path_():
		return false
	position_changed.emit(view_uid_)
	return true


func refresh_playback_path_() -> bool:
	playback_hover_bubble_.hide()
	if go_notes_ == null or playback_bar_ == null:
		return false
	var path: PackedInt64Array = PackedInt64Array(
		go_notes_.call(&"get_straightforward_path")
	)
	if path.is_empty():
		return false
	if variation_mode_:
		var base_index: int = path.find(variation_base_uid_)
		if base_index < 0:
			return false
		path = path.slice(base_index)
	var playback_move_numbers: PackedInt32Array = \
		build_playback_move_numbers_(path)
	if playback_move_numbers.size() != path.size():
		return false

	playback_path_ = path
	playback_move_numbers_ = playback_move_numbers
	queue_redraw()
	updating_playback_bar_ = true
	playback_bar_.min_value = 0.0
	playback_bar_.max_value = float(maxi(path.size() - 1, 0))
	playback_bar_.step = 1.0
	update_playback_position_()
	if playback_playing_ and not can_advance_playback_():
		set_playback_playing_(false)
	update_playback_editable_()
	updating_playback_bar_ = false
	return true


func build_playback_move_numbers_(
	path: PackedInt64Array
) -> PackedInt32Array:
	var result: PackedInt32Array = PackedInt32Array()
	var move_number: int = 0
	for uid: int in path:
		var node_data: Dictionary = Dictionary(
			go_notes_.call(&"get_node_at", uid)
		)
		if node_data.is_empty():
			return PackedInt32Array()
		var color: int = int(node_data.get("color", 0))
		if color == kBlack or color == kWhite:
			move_number += 1
		result.append(move_number)
	return result


func update_playback_position_() -> void:
	if playback_path_.is_empty():
		return
	var current_uid: int = int(go_notes_.get_current_uid()) \
		if follow_current_ else view_uid_
	var path_index: int = playback_path_.find(current_uid)
	if path_index >= 0:
		playback_bar_.set_value_no_signal(float(path_index))


func update_playback_editable_() -> void:
	playback_bar_.editable = follow_current_ and playback_path_.size() > 1
	var current_index: int = -1
	if follow_current_ and go_notes_ != null:
		current_index = playback_path_.find(int(go_notes_.get_current_uid()))
	playback_previous_button_.disabled = current_index <= 0
	playback_next_button_.disabled = current_index < 0 \
		or current_index >= playback_path_.size() - 1
	playback_previous_button_.queue_redraw()
	playback_next_button_.queue_redraw()
	playback_button_.disabled = not follow_current_ \
		or playback_path_.size() <= 1 \
		or (not playback_playing_ and not can_advance_playback_())
	playback_button_.queue_redraw()


func navigate_playback_by_(
	direction: int,
	user_initiated: bool = true
) -> bool:
	if user_initiated:
		set_playback_playing_(false)
	if not follow_current_ or go_notes_ == null or playback_path_.is_empty():
		return false
	var current_uid: int = int(go_notes_.get_current_uid())
	var current_index: int = playback_path_.find(current_uid)
	if current_index < 0:
		return false
	var target_index: int = clampi(
		current_index + direction, 0, playback_path_.size() - 1
	)
	if target_index == current_index:
		return true
	on_playback_value_changed_(float(target_index), user_initiated)
	return true


func on_playback_bar_gui_input_(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var motion_event: InputEventMouseMotion = event as InputEventMouseMotion
		update_playback_hover_bubble_(motion_event.position.x)
	elif event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event as InputEventMouseButton
		if mouse_event.pressed:
			set_playback_playing_(false)
			var playback_direction: int = 0
			if mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP:
				playback_direction = -1
			elif mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				playback_direction = 1
			if playback_direction != 0 \
					and navigate_playback_by_(playback_direction):
				playback_bar_.accept_event()
	elif event is InputEventKey:
		var key_event: InputEventKey = event as InputEventKey
		if key_event.pressed and (
				key_event.keycode == KEY_LEFT or key_event.keycode == KEY_RIGHT
		):
			set_playback_playing_(false)


func on_playback_bar_mouse_exited_() -> void:
	playback_hover_bubble_.hide()


func update_playback_hover_bubble_(mouse_x: float) -> void:
	if playback_path_.is_empty() or playback_bar_.size.x <= 0.0:
		playback_hover_bubble_.hide()
		return
	var grabber: Texture2D = playback_bar_.get_theme_icon(&"grabber")
	var grabber_half_width: float = 0.0 \
		if grabber == null else grabber.get_width() * 0.5
	var track_width: float = maxf(
		playback_bar_.size.x - grabber_half_width * 2.0,
		1.0
	)
	var track_x: float = clampf(
		mouse_x - grabber_half_width,
		0.0,
		track_width
	)
	var ratio: float = track_x / track_width
	var hovered_index: int = clampi(
		roundi(ratio * float(playback_path_.size() - 1)),
		0,
		playback_path_.size() - 1
	)
	var point_x: float = grabber_half_width
	if playback_path_.size() > 1:
		point_x += track_width * float(hovered_index) \
			/ float(playback_path_.size() - 1)
	var move_number: int = playback_move_numbers_[hovered_index] \
		if hovered_index < playback_move_numbers_.size() else 0
	playback_hover_label_.text = "%d" % move_number
	var bubble_x: float = playback_bar_.position.x + point_x \
		- playback_hover_bubble_.size.x * 0.5
	bubble_x = clampf(
		bubble_x,
		playback_bar_.position.x,
		playback_bar_.position.x + playback_bar_.size.x \
			- playback_hover_bubble_.size.x
	)
	playback_hover_bubble_.position = Vector2(
		bubble_x,
		playback_bar_.position.y - playback_hover_bubble_.size.y - 8.0
	)
	playback_hover_bubble_.show()


func on_playback_previous_pressed_() -> void:
	var _navigated: bool = navigate_playback_by_(-1)


func on_playback_next_pressed_() -> void:
	var _navigated: bool = navigate_playback_by_(1)


func on_playback_button_pressed_() -> void:
	if playback_playing_:
		set_playback_playing_(false)
		return
	if not can_advance_playback_():
		return
	set_playback_playing_(true)
	schedule_playback_step_()


func on_playback_timer_timeout_() -> void:
	if not playback_playing_ or not can_advance_playback_():
		set_playback_playing_(false)
		return
	var previous_uid: int = int(go_notes_.get_current_uid())
	if not navigate_playback_by_(1, false) \
			or int(go_notes_.get_current_uid()) == previous_uid:
		set_playback_playing_(false)
		return
	if can_advance_playback_():
		schedule_playback_step_()
	else:
		set_playback_playing_(false)


func can_advance_playback_() -> bool:
	if not follow_current_ or go_notes_ == null or playback_path_.is_empty():
		return false
	var current_index: int = playback_path_.find(
		int(go_notes_.get_current_uid())
	)
	return current_index >= 0 and current_index < playback_path_.size() - 1


func schedule_playback_step_() -> void:
	playback_timer_.start(SettingsStore.get_playback_interval_seconds())


func set_playback_playing_(playing: bool) -> void:
	playback_playing_ = playing
	if not playback_playing_:
		playback_timer_.stop()
	playback_button_.call(&"set_playing", playback_playing_)
	update_playback_editable_()


func on_playback_value_changed_(
		value: float,
		user_initiated: bool = true
) -> void:
	if updating_playback_bar_ or not follow_current_:
		return
	request_edit_sensitive_action_(
		Callable(self, "apply_playback_value_").bind(value, user_initiated)
	)


func apply_playback_value_(value: float, user_initiated: bool) -> void:
	if updating_playback_bar_ or not follow_current_:
		return
	if user_initiated:
		set_playback_playing_(false)
	if go_notes_ == null or playback_path_.is_empty():
		return
	var path_index: int = clampi(roundi(value), 0, playback_path_.size() - 1)
	playback_bar_.set_value_no_signal(float(path_index))
	var target_uid: int = int(playback_path_[path_index])
	if target_uid == int(go_notes_.get_current_uid()):
		return

	playback_navigation_ = true
	var roam_succeeded: bool = execute_roaming_to_(target_uid)
	playback_navigation_ = false
	if not roam_succeeded:
		set_playback_playing_(false)
		refresh_playback_path_()
	elif playback_playing_ and not can_advance_playback_():
		set_playback_playing_(false)


func request_edit_sensitive_action_(action: Callable) -> void:
	if edit_sensitive_action_gate_.is_valid():
		edit_sensitive_action_gate_.call(action)
	elif action.is_valid():
		action.call()


func refresh_position_() -> bool:
	branch_moves_.clear()
	setup_branches_.clear()
	if setup_preview_uid_ >= 0:
		clear_setup_branch_preview()
	if go_notes_ == null or stones_ == null:
		return false
	var target_uid: int = int(go_notes_.get_current_uid()) \
		if follow_current_ else view_uid_
	var snapshot: Dictionary = {}
	if note_numbering_preview_enabled_ \
			and target_uid == note_numbering_preview_uid_:
		snapshot = Dictionary(go_notes_.call(
			&"get_note_position_snapshot_at",
			target_uid,
			note_numbering_preview_index_
		))
	if snapshot.is_empty():
		snapshot = Dictionary(go_notes_.call(
			&"get_position_snapshot_at",
			target_uid,
			move_number_query_count_()
		))
	if snapshot.is_empty():
		return false
	var states: PackedInt32Array = PackedInt32Array(
		snapshot.get("states", PackedInt32Array())
	)
	var move_numbers: PackedInt32Array = PackedInt32Array(
		snapshot.get("move_numbers", PackedInt32Array())
	)
	var new_board_size: int = int(snapshot.get("board_size", 0))
	if states.size() != new_board_size * new_board_size \
			or move_numbers.size() != states.size():
		return false
	var node_data: Dictionary = Dictionary(
		go_notes_.call(&"get_node_at", target_uid)
	)
	if node_data.is_empty():
		return false

	board_size_ = new_board_size
	position_states_ = states
	move_numbers_ = move_numbers
	view_uid_ = target_uid
	if not preset_mode_:
		var last_color: int = int(node_data.get("color", 0))
		var inferred_next_color: int = variation_start_color_ \
			if variation_mode_ and target_uid == variation_base_uid_ \
			else (kWhite if last_color == kBlack else kBlack)
		set_next_color_(inferred_next_color)
	refresh_branch_moves_(node_data)
	setup_branches_changed.emit(get_setup_branches())
	refresh_stones_()
	refresh_note_marks_overlay_()
	refresh_hover_stone_()
	queue_redraw()
	return true


func refresh_branch_moves_(node_data: Dictionary) -> void:
	var children_value: Variant = node_data.get("children", [])
	if children_value is not Array:
		return
	var children: Array = Array(children_value)
	if children.is_empty():
		return
	for index in range(children.size()):
		var child_value: Variant = children[index]
		if child_value is not Dictionary:
			continue
		var branch: Dictionary = Dictionary(child_value)
		var color: int = int(branch.get("color", -1))
		var preset_stones: Array = Array(
			branch.get("preset_stones", [])
		)
		if color == 0 and not preset_stones.is_empty():
			setup_branches_.append(branch)
			continue
		var uid: int = int(branch.get("uid", -1))
		var row: int = int(branch.get("row", 0))
		var column: int = int(branch.get("column", 0))
		if uid <= 0 or row < 1 or row > board_size_ \
				or column < 1 or column > board_size_:
			continue
		branch_moves_.append(branch)


func refresh_stones_() -> void:
	if not ensure_stone_pool_():
		return
	var position_count: int = board_size_ * board_size_
	if position_states_.size() != position_count \
			or move_numbers_.size() != position_count:
		return

	var cell_size: float = cell_size_()
	var first_displayed_move: int = 1
	var note_preview_active: bool = note_numbering_preview_enabled_ \
		and view_uid_ == note_numbering_preview_uid_
	if not note_preview_active and SettingsStore.get_absolute_move_numbers():
		var displayed_move_count: int = displayed_move_count_()
		if displayed_move_count > 0:
			var latest_move_number: int = 0
			for number_index in range(move_numbers_.size()):
				latest_move_number = maxi(
					latest_move_number, move_numbers_[number_index]
				)
			first_displayed_move = maxi(
				latest_move_number - displayed_move_count + 1, 1
			)
	for index in range(position_count):
		var row: int = floori(float(index) / float(board_size_)) + 1
		var column: int = index % board_size_ + 1
		var state: int = position_states_[index]
		var stone: Sprite2D = stone_nodes_[index]
		var label: Label = move_number_labels_[index]
		if state != kBlack and state != kWhite:
			stone.visible = false
			label.visible = false
			continue

		update_stone_(stone, state, row, column, cell_size)
		var move_number: int = move_numbers_[index]
		if move_number >= first_displayed_move and move_number > 0:
			update_move_number_label_(
				label, state, move_number, row, column, cell_size
			)
		else:
			label.visible = false


func ensure_stone_pool_() -> bool:
	var position_count: int = board_size_ * board_size_
	if stone_nodes_.size() == position_count \
			and move_number_labels_.size() == position_count:
		return true

	for child in stones_.get_children():
		stones_.remove_child(child)
		child.queue_free()
	stone_nodes_.clear()
	move_number_labels_.clear()

	for index in range(position_count):
		var stone: Sprite2D = kStoneScene.instantiate() as Sprite2D
		if stone == null:
			push_error("Stone scene root must be Sprite2D.")
			return false
		var row: int = floori(float(index) / float(board_size_)) + 1
		var column: int = index % board_size_ + 1
		stone.name = "Stone_%d_%d" % [row, column]
		stone.visible = false
		stone.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		stones_.add_child(stone)
		stone_nodes_.append(stone)

	for index in range(position_count):
		var label: Label = Label.new()
		label.name = "MoveNumber_%d" % index
		label.visible = false
		label.z_index = 1
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stones_.add_child(label)
		move_number_labels_.append(label)
	return true


func update_stone_(
		stone: Sprite2D,
		state: int,
		row: int,
		column: int,
		cell_size: float
) -> void:
	stone.texture = stone_texture_(state, row, column)
	if stone.texture == null:
		push_error("Configured stone texture is unavailable.")
		stone.visible = false
		return
	stone.position = Vector2(
		grid_coordinate_(float(column - 1)),
		grid_coordinate_(float(row - 1))
	)
	var texture_size: Vector2 = stone.texture.get_size()
	var texture_extent: float = maxf(texture_size.x, texture_size.y)
	var scale_factor: float = \
		cell_size * kStoneDiameterCellRatio / texture_extent
	stone.scale = Vector2.ONE * scale_factor
	stone.visible = true


func move_number_query_count_() -> int:
	if SettingsStore.get_absolute_move_numbers():
		return 0
	return displayed_move_count_()


func displayed_move_count_() -> int:
	match SettingsStore.get_move_number_mode():
		SettingsStore.kMoveNumberModeTen:
			return 10
		SettingsStore.kMoveNumberModeAll:
			return 0
		SettingsStore.kMoveNumberModeCustom:
			return SettingsStore.get_move_number_count()
		_:
			return 1


func update_move_number_label_(
		label: Label,
		state: int,
		move_number: int,
		row: int,
		column: int,
		cell_size: float
) -> void:
	label.text = str(move_number)
	var stone_position: Vector2 = Vector2(
		grid_coordinate_(float(column - 1)),
		grid_coordinate_(float(row - 1))
	)
	label.position = stone_position - Vector2.ONE * cell_size * 0.5
	label.size = Vector2.ONE * cell_size
	var digit_count: int = label.text.length()
	var font_ratio: float = minf(
		kMoveNumberFontCellRatio,
		kMoveNumberMaxTextWidthRatio / float(maxi(digit_count, 1))
	)
	label.add_theme_font_size_override(
		"font_size",
		maxi(roundi(cell_size * font_ratio), 1)
	)
	var font_color: Color = Color.WHITE if state == kBlack else Color.BLACK
	var outline_color: Color = Color(0.0, 0.0, 0.0, 0.55) \
		if state == kBlack else Color(1.0, 1.0, 1.0, 0.55)
	label.add_theme_color_override("font_color", font_color)
	label.add_theme_color_override("font_outline_color", outline_color)
	label.add_theme_constant_override(
		"outline_size",
		maxi(roundi(cell_size * 0.02), 1)
	)
	label.visible = true

func stone_texture_(state: int, _row: int, _column: int) -> Texture2D:
	if state == kBlack:
		return black_texture_
	if state == kWhite:
		return white_texture_
	return null


func cell_size_() -> float:
	if texture == null:
		return 1.0
	var texture_size: Vector2 = texture.get_size()
	var board_extent: float = minf(texture_size.x, texture_size.y)
	return board_extent / float(board_size_ + 1)


func grid_half_extent_() -> float:
	return cell_size_() * float(board_size_ - 1) * 0.5


func grid_coordinate_(index: float) -> float:
	return -grid_half_extent_() + cell_size_() * index


func snap_to_pixel_center_(
		local_point: Vector2,
		canvas_transform: Transform2D,
		inverse_canvas_transform: Transform2D
) -> Vector2:
	var screen_point: Vector2 = canvas_transform * local_point
	screen_point.x = floorf(screen_point.x) + 0.5
	screen_point.y = floorf(screen_point.y) + 0.5
	return inverse_canvas_transform * screen_point


func get_star_positions_() -> PackedVector2Array:
	match board_size_:
		9:
			return PackedVector2Array([
				Vector2(2, 2), Vector2(2, 6), Vector2(4, 4),
				Vector2(6, 2), Vector2(6, 6)
			])
		11:
			return PackedVector2Array([
				Vector2(2, 2), Vector2(2, 8), Vector2(5, 5),
				Vector2(8, 2), Vector2(8, 8)
			])
		13:
			return PackedVector2Array([
				Vector2(3, 3), Vector2(3, 9), Vector2(6, 6),
				Vector2(9, 3), Vector2(9, 9)
			])
		15:
			return PackedVector2Array([
				Vector2(3, 3), Vector2(3, 11), Vector2(7, 7),
				Vector2(11, 3), Vector2(11, 11)
			])
		19:
			return PackedVector2Array([
				Vector2(3, 3), Vector2(3, 9), Vector2(3, 15),
				Vector2(9, 3), Vector2(9, 9), Vector2(9, 15),
				Vector2(15, 3), Vector2(15, 9), Vector2(15, 15)
			])
	return PackedVector2Array()


func is_supported_board_size_(board_size: int) -> bool:
	return board_size == 9 or board_size == 11 or board_size == 13 \
		or board_size == 15 or board_size == 19
