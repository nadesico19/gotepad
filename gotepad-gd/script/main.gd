extends Node2D

const kBoardToolbarGap: float = 8.0
const kBlack: int = 1
const kWhite: int = 2
const kNoteMarkDisabled: int = 0
const kNoteSequentialMarkMode: int = 1
const kNoteSymbolMarkMode: int = 2
const kPendingPanelNone: int = 0
const kPendingPanelNotes: int = 1
const kPendingPanelSgfMetadata: int = 2
const kPendingPanelKatago: int = 3
const kToolKeepMainLine: int = 0
const kToolClearNotes: int = 1
const kSgfRecoveryIdentifierSanitized: int = 1
const kSgfRecoveryEmptyIdentifierDiscarded: int = 2
const kSgfRecoveryIdentifierCollisionDiscarded: int = 3
const kSgfRecoveryInvalidRulesDefaulted: int = 4
const kSgfRecoveryInvalidKomiDefaulted: int = 5
const kSgfRecoverySubunitKomiDefaulted: int = 6
const kToolMenuGap: float = 6.0
const kUiScaleMinimumHeight: float = 900.0
const kUiScaleMaximumHeight: float = 2000.0
const kUiScaleMinimum: float = 1.0
const kUiScaleMaximum: float = 2.0
const kWindowStateDebounceSeconds: float = 0.35
const kWindowMinimumRestoreSize: Vector2i = Vector2i(800, 600)
const kWindowMinimumVisibleSize: Vector2i = Vector2i(64, 32)
const kSequentialMarkLetters: String = \
	"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
const kPptxTemplatePath: String = \
	"res://assets/publication/go_book_b5_landscape_template.pptx"
const kPptxCopyBytesPerFrame: int = 1024 * 1024
const kAndroidHostClass: StringName = &"com.godot.game.GodotApp"
const kAndroidOpenIntentPollSeconds: float = 0.25


class DocumentState extends RefCounted:
	var notes: GoNotes
	var title: String = ""
	var file_path: String = ""
	var initialized: bool = false
	var interactions_locked: bool = false
	var source_writable: bool = true


@onready var board_: GoBoardView = $Board
@onready var camera_: Camera2D = $Camera
@onready var background_layer_: CanvasLayer = $Background
@onready var interface_layer_: CanvasLayer = $Interface
@onready var interface_safe_area_: Control = $Interface/SafeArea
@onready var branch_visualization_layer_: CanvasLayer = \
	$BranchVisualizationLayer
@onready var branch_visualization_safe_area_: Control = \
	$BranchVisualizationLayer/SafeArea
@onready var branch_visualization_: Control = \
	$BranchVisualizationLayer/SafeArea/BranchVisualization
@onready var note_mark_layer_: CanvasLayer = $NoteMarkLayer
@onready var note_mark_safe_area_: Control = $NoteMarkLayer/SafeArea
@onready var note_mark_toolbar_: VBoxContainer = \
	$NoteMarkLayer/SafeArea/NoteMarkToolBar
@onready var next_mark_label_: Label = \
	$NoteMarkLayer/SafeArea/NoteMarkToolBar/NextMarkLabel
@onready var note_triangle_button_: Button = \
	$NoteMarkLayer/SafeArea/NoteMarkToolBar/Triangle
@onready var note_square_button_: Button = \
	$NoteMarkLayer/SafeArea/NoteMarkToolBar/Square
@onready var note_circle_button_: Button = \
	$NoteMarkLayer/SafeArea/NoteMarkToolBar/Circle
@onready var note_cross_button_: Button = \
	$NoteMarkLayer/SafeArea/NoteMarkToolBar/Cross
@onready var note_erase_button_: Button = \
	$NoteMarkLayer/SafeArea/NoteMarkToolBar/Erase
@onready var note_mark_accept_button_: Button = \
	$NoteMarkLayer/SafeArea/NoteMarkToolBar/Accept
@onready var note_mark_cancel_button_: Button = \
	$NoteMarkLayer/SafeArea/NoteMarkToolBar/Cancel
@onready var board_size_dialog_: BoardSizeDialog = $Interface/SafeArea/BoardSizeDialog
@onready var board_toolbar_: AdaptiveToolbar = $Interface/SafeArea/BoardToolBar
@onready var variation_toolbar_: VBoxContainer = \
	$Interface/SafeArea/VariationToolBar
@onready var variation_exit_button_: Button = \
	$Interface/SafeArea/VariationToolBar/ExitButton
@onready var variation_keep_button_: Button = \
	$Interface/SafeArea/VariationToolBar/KeepBranchButton
@onready var variation_takeback_button_: Button = \
	$Interface/SafeArea/VariationToolBar/TakebackButton
@onready var pending_move_accept_button_: Button = \
	$Interface/SafeArea/BoardToolBar/PendingMoveAcceptButton
@onready var pending_move_cancel_button_: Button = \
	$Interface/SafeArea/BoardToolBar/PendingMoveCancelButton
@onready var variation_pending_move_accept_button_: Button = \
	$Interface/SafeArea/VariationToolBar/PendingMoveAcceptButton
@onready var variation_pending_move_cancel_button_: Button = \
	$Interface/SafeArea/VariationToolBar/PendingMoveCancelButton
@onready var undo_button_: Button = $Interface/SafeArea/BoardToolBar/UndoButton
@onready var redo_button_: Button = $Interface/SafeArea/BoardToolBar/RedoButton
@onready var find_previous_button_: Button = \
	$Interface/SafeArea/BoardToolBar/FindPreviousButton
@onready var find_next_button_: Button = \
	$Interface/SafeArea/BoardToolBar/FindNextButton
@onready var reorder_branch_button_: Button = \
	$Interface/SafeArea/BoardToolBar/ReorderBranchButton
@onready var variation_button_: Button = \
	$Interface/SafeArea/BoardToolBar/VariationButton
@onready var branch_visualization_button_: Button = \
	$Interface/SafeArea/BoardToolBar/BranchVisualizationButton
@onready var notes_button_: Button = $Interface/SafeArea/BoardToolBar/NotesButton
@onready var notes_panel_: NotesPanel = $Interface/SafeArea/NotesPanel
@onready var sgf_metadata_button_: Button = \
	$Interface/SafeArea/BoardToolBar/SgfMetadataButton
@onready var sgf_metadata_panel_: SgfMetadataPanel = \
	$Interface/SafeArea/SgfMetadataPanel
@onready var katago_analysis_service_: KataGoAnalysisService = \
	$KataGoAnalysisService
@onready var katago_human_analysis_service_: KataGoHumanAnalysisService = \
	$KataGoHumanAnalysisService
@onready var katago_analysis_button_: Button = \
	$Interface/SafeArea/BoardToolBar/KatagoAnalysisButton
@onready var human_play_button_: Button = \
	$Interface/SafeArea/BoardToolBar/HumanPlayButton
@onready var katago_analysis_panel_: KataGoAnalysisPanel = \
	$Interface/SafeArea/KatagoAnalysisPanel
@onready var territory_scoring_button_: Button = \
	$Interface/SafeArea/BoardToolBar/TerritoryScoringButton
@onready var human_play_takeback_button_: Button = \
	$Interface/SafeArea/BoardToolBar/HumanPlayTakebackButton
@onready var human_play_accept_button_: Button = \
	$Interface/SafeArea/BoardToolBar/HumanPlayAcceptButton
@onready var human_play_cancel_button_: Button = \
	$Interface/SafeArea/BoardToolBar/HumanPlayCancelButton
@onready var territory_toolbar_: VBoxContainer = \
	$Interface/SafeArea/TerritoryToolBar
@onready var territory_accept_button_: Button = \
	$Interface/SafeArea/TerritoryToolBar/AcceptButton
@onready var territory_cancel_button_: Button = \
	$Interface/SafeArea/TerritoryToolBar/CancelButton
@onready var territory_log_panel_: PanelContainer = \
	$Interface/SafeArea/TerritoryLogPanel
@onready var territory_log_output_: TextEdit = \
	$Interface/SafeArea/TerritoryLogPanel/Margin/Output
@onready var settings_ui_: Control = $Interface/SafeArea/SettingsUI
@onready var undo_unavailable_mark_: TextureRect = \
	$Interface/SafeArea/BoardToolBar/UndoButton/UnavailableMark
@onready var redo_unavailable_mark_: TextureRect = \
	$Interface/SafeArea/BoardToolBar/RedoButton/UnavailableMark
@onready var board_lock_checkbox_: CheckBox = \
	$Interface/SafeArea/BoardToolBar/BoardLockControl/CheckBox
@onready var next_color_button_: Button = \
	$Interface/SafeArea/BoardToolBar/NextColorButton
@onready var preset_black_button_: Button = \
	$Interface/SafeArea/BoardToolBar/PresetBlackButton
@onready var preset_black_active_mark_: Label = \
	$Interface/SafeArea/BoardToolBar/PresetBlackButton/ActiveMark
@onready var preset_white_button_: Button = \
	$Interface/SafeArea/BoardToolBar/PresetWhiteButton
@onready var preset_white_active_mark_: Label = \
	$Interface/SafeArea/BoardToolBar/PresetWhiteButton/ActiveMark
@onready var preset_accept_button_: Button = \
	$Interface/SafeArea/BoardToolBar/PresetAcceptButton
@onready var preset_cancel_button_: Button = \
	$Interface/SafeArea/BoardToolBar/PresetCancelButton
@onready var preset_erase_button_: Button = \
	$Interface/SafeArea/BoardToolBar/PresetEraseButton
@onready var setup_branch_button_: Button = \
	$Interface/SafeArea/BoardToolBar/SetupBranchButton
@onready var setup_branch_count_: Label = \
	$Interface/SafeArea/BoardToolBar/SetupBranchButton/CountBadge
@onready var setup_branch_popup_: SetupBranchPopup = \
	$Interface/SafeArea/SetupBranchPopup
@onready var branch_order_popup_: BranchOrderPopup = \
	$Interface/SafeArea/BranchOrderPopup
@onready var document_tab_bar_: DocumentTabBar = $Interface/SafeArea/DocumentTabBar
@onready var new_tab_button_: Button = $Interface/SafeArea/NewTabButton
@onready var save_button_: Button = $Interface/SafeArea/SaveButton
@onready var save_as_button_: Button = $Interface/SafeArea/SaveAsButton
@onready var export_button_: Button = $Interface/SafeArea/ExportButton
@onready var tool_button_: MenuButton = $Interface/SafeArea/ToolButton
@onready var mobile_playback_buttons_: VBoxContainer = \
	$Interface/SafeArea/MobilePlaybackButtons
@onready var mobile_playback_next_button_: Button = \
	$Interface/SafeArea/MobilePlaybackButtons/NextButton
@onready var mobile_playback_previous_button_: Button = \
	$Interface/SafeArea/MobilePlaybackButtons/PreviousButton
@onready var tool_menu_: PopupMenu = tool_button_.get_popup()
@onready var keep_main_line_confirmation_: ConfirmationDialog = \
	$Interface/SafeArea/KeepMainLineConfirmation
@onready var clear_notes_confirmation_: ConfirmationDialog = \
	$Interface/SafeArea/ClearNotesConfirmation
@onready var tool_error_dialog_: AcceptDialog = $Interface/SafeArea/ToolErrorDialog
@onready var sgf_load_warning_dialog_: AcceptDialog = \
	$Interface/SafeArea/SgfLoadWarningDialog
@onready var territory_mode_confirmation_: ConfirmationDialog = \
	$Interface/SafeArea/TerritoryModeConfirmation
@onready var territory_result_dialog_: AcceptDialog = \
	$Interface/SafeArea/TerritoryResultDialog
@onready var territory_error_dialog_: AcceptDialog = \
	$Interface/SafeArea/TerritoryErrorDialog
@onready var save_file_dialog_: FileDialog = $Interface/SafeArea/SaveFileDialog
@onready var save_error_dialog_: AcceptDialog = $Interface/SafeArea/SaveErrorDialog
@onready var save_confirmation_: ConfirmationDialog = \
	$Interface/SafeArea/SaveConfirmation
@onready var export_file_dialog_: FileDialog = $Interface/SafeArea/ExportFileDialog
@onready var export_error_dialog_: AcceptDialog = \
	$Interface/SafeArea/ExportErrorDialog
@onready var export_success_dialog_: AcceptDialog = \
	$Interface/SafeArea/ExportSuccessDialog
@onready var export_progress_dialog_: AcceptDialog = \
	$Interface/SafeArea/ExportProgressDialog
@onready var export_progress_bar_: ProgressBar = \
	$Interface/SafeArea/ExportProgressDialog/ProgressBar
@onready var close_tab_confirmation_: ConfirmationDialog = \
	$Interface/SafeArea/CloseTabConfirmation
@onready var human_play_options_dialog_: Window = \
	$Interface/SafeArea/HumanPlayOptionsDialog
@onready var human_play_current_turn_: Label = \
	$Interface/SafeArea/HumanPlayOptionsDialog/Margin/Content/CurrentTurn
@onready var human_play_ai_color_option_: OptionButton = \
	$Interface/SafeArea/HumanPlayOptionsDialog/Margin/Content/Options/AiColor
@onready var human_play_style_option_: OptionButton = \
	$Interface/SafeArea/HumanPlayOptionsDialog/Margin/Content/Options/Style
@onready var human_play_rank_option_: OptionButton = \
	$Interface/SafeArea/HumanPlayOptionsDialog/Margin/Content/Options/Rank
@onready var human_play_visits_input_: SpinBox = \
	$Interface/SafeArea/HumanPlayOptionsDialog/Margin/Content/Options/Visits
@onready var human_play_start_button_: Button = \
	$Interface/SafeArea/HumanPlayOptionsDialog/Margin/Content/Actions/Start
@onready var human_play_options_cancel_button_: Button = \
	$Interface/SafeArea/HumanPlayOptionsDialog/Margin/Content/Actions/Cancel
@onready var human_play_pass_dialog_: ConfirmationDialog = \
	$Interface/SafeArea/HumanPlayPassDialog
@onready var human_play_discard_dialog_: ConfirmationDialog = \
	$Interface/SafeArea/HumanPlayDiscardDialog
@onready var human_play_accept_dialog_: ConfirmationDialog = \
	$Interface/SafeArea/HumanPlayAcceptDialog
@onready var human_play_error_dialog_: AcceptDialog = \
	$Interface/SafeArea/HumanPlayErrorDialog
@onready var preset_button_: Button = $Board/PresetButton
@onready var preset_unavailable_mark_: TextureRect = \
	$Board/PresetButton/UnavailableMark

var go_notes_: GoNotes
var setup_branches_: Array[Dictionary] = []
var documents_: Array[DocumentState] = []
var active_document_index_: int = -1
var pending_close_index_: int = -1
var note_mark_mode_: int = kNoteMarkDisabled
var note_mark_note_index_: int = -1
var note_mark_original_sequential_: Array[Dictionary] = []
var note_mark_original_symbols_: Array[Dictionary] = []
var pending_save_path_: String = ""
var pending_side_panel_: int = kPendingPanelNone
var side_panel_after_variation_: int = kPendingPanelNone
var restore_katago_panel_after_branch_visualization_: bool = false
var branch_popup_command_in_progress_: bool = false
var active_file_dialog_: FileDialog
var export_thread_: Thread
var export_notes_: GoNotes
var export_in_progress_: bool = false
var export_target_path_: String = ""
var export_temporary_path_: String = ""
var export_copy_source_: FileAccess
var export_copy_target_: FileAccess
var export_copy_total_: int = 0
var export_copy_current_: int = 0
var window_state_save_timer_: Timer
var last_windowed_position_: Vector2i = Vector2i.ZERO
var last_windowed_size_: Vector2i = Vector2i(1600, 900)
var last_window_maximized_: bool = false
var android_host_class_: Variant
var android_open_intent_timer_: Timer
var android_open_requests_: Array[String] = []
var android_open_action_pending_: bool = false
var territory_mode_active_: bool = false
var territory_query_id_: String = ""
var territory_side_panel_to_restore_: int = kPendingPanelNone
var human_play_mode_active_: bool = false
var human_play_ai_color_: int = kWhite
var human_play_profile_: String = "rank_1d"
var human_play_max_visits_: int = 500
var human_play_query_id_: String = ""
var human_play_query_uid_: int = -1
var human_play_turns_: Array[Dictionary] = []
var human_play_ai_placing_: bool = false
var human_play_takeback_in_progress_: bool = false
var human_play_finished_: bool = false
var human_play_panel_was_open_: bool = false
var human_play_toolbar_visibility_: Dictionary = {}
var human_play_discard_paused_ai_: bool = false


func _enter_tree() -> void:
	var document: DocumentState = DocumentState.new()
	document.notes = GoNotes.new()
	document.title = unique_document_title_(tr("新建笔记"))
	documents_.append(document)
	active_document_index_ = 0
	go_notes_ = document.notes
	var board: GoBoardView = get_node("Board") as GoBoardView
	if board == null or not board.bind_go_notes(go_notes_):
		push_error("Failed to bind the main board to GoNotes.")


func _ready() -> void:
	get_tree().auto_accept_quit = false
	export_progress_dialog_.get_ok_button().hide()
	export_progress_dialog_.close_requested.connect(
		on_export_progress_close_requested_
	)
	restore_window_state_()
	configure_ui_scaling_()
	board_toolbar_.move_child(
		preset_black_button_, next_color_button_.get_index() + 1
	)
	board_toolbar_.move_child(
		preset_white_button_, preset_black_button_.get_index() + 1
	)
	board_toolbar_.move_child(
		preset_erase_button_, preset_white_button_.get_index() + 1
	)
	reorder_board_toolbar_buttons_()
	window_state_save_timer_ = Timer.new()
	window_state_save_timer_.one_shot = true
	window_state_save_timer_.wait_time = kWindowStateDebounceSeconds
	window_state_save_timer_.timeout.connect(save_window_state_now_)
	add_child(window_state_save_timer_)
	configure_android_open_intents_()
	board_size_dialog_.create_requested.connect(on_create_requested_)
	board_size_dialog_.sgf_load_requested.connect(on_sgf_load_requested_)
	board_size_dialog_.image_create_requested.connect(
		on_image_create_requested_
	)
	board_size_dialog_.cancel_requested.connect(
		on_board_creation_cancel_requested_
	)
	undo_button_.pressed.connect(on_undo_requested_)
	redo_button_.pressed.connect(on_redo_requested_)
	find_previous_button_.pressed.connect(on_find_previous_requested_)
	find_next_button_.pressed.connect(on_find_next_requested_)
	reorder_branch_button_.pressed.connect(on_reorder_branch_requested_)
	variation_button_.pressed.connect(on_variation_requested_)
	branch_visualization_button_.pressed.connect(
		on_branch_visualization_requested_
	)
	notes_button_.pressed.connect(on_notes_requested_)
	notes_panel_.panel_visibility_changed.connect(
		on_notes_panel_visibility_changed_
	)
	sgf_metadata_button_.pressed.connect(on_sgf_metadata_requested_)
	sgf_metadata_panel_.panel_visibility_changed.connect(
		on_sgf_metadata_panel_visibility_changed_
	)
	katago_analysis_button_.pressed.connect(on_katago_analysis_requested_)
	katago_analysis_panel_.bind_service(katago_analysis_service_)
	katago_analysis_service_.transport_starting.connect(
		on_normal_katago_transport_starting_
	)
	SettingsStore.katago_paths_changed.connect(
		on_human_katago_runtime_settings_changed_
	)
	SettingsStore.katago_human_paths_changed.connect(
		on_human_katago_runtime_settings_changed_
	)
	katago_analysis_panel_.panel_visibility_changed.connect(
		on_katago_analysis_panel_visibility_changed_
	)
	katago_analysis_panel_.variation_requested.connect(
		on_katago_variation_requested_
	)
	human_play_button_.pressed.connect(on_human_play_requested_)
	human_play_takeback_button_.pressed.connect(
		on_human_play_takeback_requested_
	)
	human_play_accept_button_.pressed.connect(on_human_play_accept_requested_)
	human_play_cancel_button_.pressed.connect(on_human_play_cancel_requested_)
	human_play_start_button_.pressed.connect(on_human_play_start_requested_)
	human_play_options_cancel_button_.pressed.connect(
		Callable(human_play_options_dialog_, "hide")
	)
	human_play_options_dialog_.close_requested.connect(
		Callable(human_play_options_dialog_, "hide")
	)
	human_play_pass_dialog_.confirmed.connect(on_human_play_pass_accepted_)
	human_play_pass_dialog_.canceled.connect(on_human_play_pass_rejected_)
	human_play_discard_dialog_.confirmed.connect(discard_human_play_)
	human_play_discard_dialog_.canceled.connect(
		on_human_play_discard_canceled_
	)
	human_play_accept_dialog_.confirmed.connect(keep_human_play_)
	katago_human_analysis_service_.result_received.connect(
		on_human_play_analysis_result_
	)
	katago_human_analysis_service_.query_error.connect(
		on_human_play_query_error_
	)
	katago_human_analysis_service_.service_error.connect(
		on_human_play_service_error_
	)
	katago_human_analysis_service_.result_received.connect(
		on_territory_analysis_result_
	)
	katago_human_analysis_service_.query_error.connect(
		on_territory_query_error_
	)
	katago_human_analysis_service_.log_received.connect(
		on_territory_log_received_
	)
	katago_human_analysis_service_.service_warning.connect(
		on_territory_service_warning_
	)
	configure_human_play_options_()
	territory_scoring_button_.pressed.connect(
		on_territory_scoring_requested_
	)
	territory_mode_confirmation_.confirmed.connect(
		enter_territory_scoring_mode_
	)
	territory_accept_button_.pressed.connect(
		on_territory_scoring_accept_requested_
	)
	territory_cancel_button_.pressed.connect(
		exit_territory_scoring_mode_
	)
	board_.territory_cancel_requested.connect(
		exit_territory_scoring_mode_
	)
	katago_analysis_service_.result_received.connect(
		on_territory_analysis_result_
	)
	katago_analysis_service_.query_error.connect(
		on_territory_query_error_
	)
	katago_analysis_service_.log_received.connect(
		on_territory_log_received_
	)
	katago_analysis_service_.service_warning.connect(
		on_territory_service_warning_
	)
	katago_analysis_service_.service_error.connect(
		on_territory_service_error_
	)
	notes_panel_.displayed_marks_changed.connect(
		on_displayed_note_marks_changed_
	)
	notes_panel_.mark_mode_requested.connect(on_note_mark_mode_requested_)
	notes_panel_.text_edit_became_dirty.connect(board_.stop_playback)
	notes_panel_.edit_resolution_canceled.connect(
		on_note_edit_resolution_canceled_
	)
	notes_panel_.numbering_preview_changed.connect(
		board_.set_note_numbering_preview
	)
	board_.set_edit_sensitive_action_gate(
		Callable(self, "request_after_note_edit_resolution_")
	)
	branch_visualization_.connect(
		&"exit_requested",
		Callable(self, "on_branch_visualization_exit_requested_")
	)
	variation_exit_button_.pressed.connect(on_variation_exit_requested_)
	variation_keep_button_.pressed.connect(on_variation_keep_requested_)
	variation_takeback_button_.pressed.connect(on_variation_takeback_requested_)
	pending_move_accept_button_.pressed.connect(on_pending_move_accept_requested_)
	pending_move_cancel_button_.pressed.connect(on_pending_move_cancel_requested_)
	variation_pending_move_accept_button_.pressed.connect(
		on_pending_move_accept_requested_
	)
	variation_pending_move_cancel_button_.pressed.connect(
		on_pending_move_cancel_requested_
	)
	board_.find_mode_changed.connect(on_find_mode_changed_)
	board_.variation_mode_changed.connect(on_variation_mode_changed_)
	board_.human_play_cancel_requested.connect(
		on_human_play_cancel_requested_
	)
	board_.position_changed.connect(on_board_position_changed_)
	board_.playback_navigation_changed.connect(
		on_playback_navigation_changed_
	)
	board_.next_color_changed.connect(on_next_color_changed_)
	board_.pending_move_changed.connect(on_pending_move_changed_)
	board_.preset_mode_changed.connect(on_preset_mode_changed_)
	board_.note_mark_cancel_requested.connect(on_note_mark_cancel_requested_)
	board_.note_mark_draft_changed.connect(on_note_mark_draft_changed_)
	board_.setup_branches_changed.connect(on_setup_branches_changed_)
	setup_branch_button_.pressed.connect(on_setup_branch_requested_)
	document_tab_bar_.tab_selected.connect(on_document_tab_selected_)
	document_tab_bar_.tab_close_requested.connect(
		on_document_tab_close_requested_
	)
	new_tab_button_.pressed.connect(on_new_tab_requested_)
	save_button_.pressed.connect(on_save_requested_)
	save_as_button_.pressed.connect(on_save_as_requested_)
	export_button_.pressed.connect(on_export_requested_)
	mobile_playback_next_button_.pressed.connect(
		on_mobile_playback_requested_.bind(1)
	)
	mobile_playback_previous_button_.pressed.connect(
		on_mobile_playback_requested_.bind(-1)
	)
	refresh_tool_menu_()
	refresh_file_dialog_filters_()
	tool_menu_.id_pressed.connect(on_tool_menu_id_pressed_)
	tool_menu_.about_to_popup.connect(on_tool_menu_about_to_popup_)
	keep_main_line_confirmation_.confirmed.connect(
		on_keep_main_line_confirmed_
	)
	clear_notes_confirmation_.confirmed.connect(on_clear_notes_confirmed_)
	save_file_dialog_.file_selected.connect(on_save_file_selected_)
	save_file_dialog_.canceled.connect(on_file_dialog_canceled_)
	save_confirmation_.confirmed.connect(on_save_confirmed_)
	save_confirmation_.canceled.connect(on_save_canceled_)
	export_file_dialog_.file_selected.connect(on_export_file_selected_)
	export_file_dialog_.canceled.connect(on_file_dialog_canceled_)
	close_tab_confirmation_.confirmed.connect(on_close_tab_confirmed_)
	close_tab_confirmation_.canceled.connect(on_close_tab_canceled_)
	setup_branch_popup_.branch_hovered.connect(
		on_setup_branch_hovered_
	)
	setup_branch_popup_.preview_cleared.connect(
		on_setup_branch_preview_cleared_
	)
	setup_branch_popup_.branch_selected.connect(
		on_setup_branch_selected_
	)
	branch_order_popup_.order_accepted.connect(
		on_branch_order_accepted_
	)
	branch_order_popup_.branch_delete_requested.connect(
		on_branch_delete_requested_
	)
	branch_order_popup_.branch_enter_requested.connect(
		on_branch_enter_requested_
	)
	var changed_callback: Callable = Callable(
		self, "on_go_notes_history_changed_"
	)
	go_notes_.connect(&"changed", changed_callback)
	board_lock_checkbox_.toggled.connect(on_board_lock_toggled_)
	next_color_button_.pressed.connect(on_next_color_requested_)
	preset_black_button_.pressed.connect(
		on_preset_color_requested_.bind(kBlack)
	)
	preset_white_button_.pressed.connect(
		on_preset_color_requested_.bind(kWhite)
	)
	note_triangle_button_.pressed.connect(
		on_note_symbol_selected_.bind("TR")
	)
	note_square_button_.pressed.connect(
		on_note_symbol_selected_.bind("SQ")
	)
	note_circle_button_.pressed.connect(
		on_note_symbol_selected_.bind("CR")
	)
	note_cross_button_.pressed.connect(
		on_note_symbol_selected_.bind("MA")
	)
	note_erase_button_.pressed.connect(
		on_note_symbol_selected_.bind("")
	)
	note_mark_accept_button_.pressed.connect(on_note_mark_accept_requested_)
	note_mark_cancel_button_.pressed.connect(on_note_mark_cancel_requested_)
	preset_accept_button_.pressed.connect(on_preset_accept_requested_)
	preset_cancel_button_.pressed.connect(on_preset_cancel_requested_)
	preset_erase_button_.toggled.connect(on_preset_erase_toggled_)
	preset_button_.pressed.connect(on_preset_requested_)
	get_window().size_changed.connect(on_window_size_changed_)
	SettingsStore.horizontal_safe_margin_changed.connect(
		apply_horizontal_safe_margin_
	)
	SettingsStore.board_width_percentage_changed.connect(
		apply_board_width_percentage_
	)
	SettingsStore.large_ui_changed.connect(on_large_ui_changed_)
	apply_horizontal_safe_margin_(SettingsStore.get_horizontal_safe_margin())
	apply_board_width_percentage_(SettingsStore.get_board_width_percentage())
	board_.board_texture_changed.connect(on_board_assets_changed_)
	board_.set_interactions_locked(
		board_lock_checkbox_.button_pressed
	)
	update_history_buttons_()
	update_variation_takeback_button_()
	update_preset_button_()
	update_next_color_button_(board_.get_next_color())
	on_pending_move_changed_(board_.has_pending_move())
	on_setup_branches_changed_(board_.get_setup_branches())
	update_reorder_branch_button_()
	on_playback_navigation_changed_(
		board_.can_navigate_playback(-1),
		board_.can_navigate_playback(1)
	)
	update_mobile_playback_visibility_()
	refresh_document_tabs_()
	on_board_layout_changed_()
	call_deferred(&"open_startup_sgf_files_")
	call_deferred(&"poll_android_open_intents_")


func configure_android_open_intents_() -> void:
	if OS.get_name() != "Android":
		return
	android_host_class_ = JavaClassWrapper.wrap(kAndroidHostClass)
	if android_host_class_ == null:
		push_warning("Unable to connect the Android document intent bridge.")
		return
	android_open_intent_timer_ = Timer.new()
	android_open_intent_timer_.wait_time = kAndroidOpenIntentPollSeconds
	android_open_intent_timer_.timeout.connect(poll_android_open_intents_)
	add_child(android_open_intent_timer_)
	android_open_intent_timer_.start()


func poll_android_open_intents_() -> void:
	if android_host_class_ == null:
		return
	var values: Variant = android_host_class_.pollOpenSgfUris()
	if values != null:
		for value: Variant in values:
			var uri: String = str(value)
			if not uri.is_empty() and not android_open_requests_.has(uri):
				android_open_requests_.append(uri)
	dispatch_next_android_open_request_()


func dispatch_next_android_open_request_() -> void:
	if android_open_action_pending_ or android_open_requests_.is_empty():
		return
	android_open_action_pending_ = true
	var uri: String = android_open_requests_.pop_front()
	request_after_note_edit_resolution_(
		Callable(self, "open_android_sgf_uri_now_").bind(uri)
	)


func open_android_sgf_uri_now_(uri: String) -> void:
	android_open_action_pending_ = false
	if active_document_index_ >= 0 \
			and active_document_index_ < documents_.size() \
			and documents_[active_document_index_].initialized:
		create_new_tab_()
	var source_writable: bool = false
	if android_host_class_ != null:
		source_writable = bool(android_host_class_.canWriteDocument(uri))
	on_sgf_load_requested_(uri, source_writable)
	call_deferred(&"dispatch_next_android_open_request_")


func open_startup_sgf_files_() -> void:
	if OS.get_name() != "Windows":
		return
	var paths: PackedStringArray = get_startup_sgf_paths_()
	for index: int in range(paths.size()):
		if index > 0:
			create_new_tab_()
		on_sgf_load_requested_(paths[index])


func get_startup_sgf_paths_() -> PackedStringArray:
	var paths: PackedStringArray = PackedStringArray()
	var seen_paths: Dictionary = {}
	for argument: String in OS.get_cmdline_user_args():
		append_startup_sgf_path_(argument, paths, seen_paths)
	for argument: String in OS.get_cmdline_args():
		append_startup_sgf_path_(argument, paths, seen_paths)
	return paths


func append_startup_sgf_path_(
	argument: String,
	paths: PackedStringArray,
	seen_paths: Dictionary
) -> void:
	var candidate: String = argument.strip_edges()
	if candidate.get_extension().to_lower() != "sgf":
		return
	var load_path: String = ProjectSettings.globalize_path(
		candidate
	).simplify_path()
	var normalized_path: String = normalized_file_path_(load_path)
	if normalized_path.is_empty() or seen_paths.has(normalized_path):
		return
	seen_paths[normalized_path] = true
	paths.append(load_path)


func uses_desktop_window_state_() -> bool:
	return not OS.has_feature("mobile") and not OS.has_feature("web")


func restore_window_state_() -> void:
	var window: Window = get_window()
	last_windowed_position_ = window.position
	last_windowed_size_ = window.size
	last_window_maximized_ = window.mode == Window.MODE_MAXIMIZED
	if not uses_desktop_window_state_():
		return
	var state: Dictionary = SettingsStore.get_saved_window_state()
	if state.is_empty():
		return
	var position_value: Variant = state.get(
		"position", last_windowed_position_
	)
	var size_value: Variant = state.get("size", last_windowed_size_)
	if position_value is not Vector2i or size_value is not Vector2i:
		return
	var saved_position: Vector2i = position_value as Vector2i
	var saved_size: Vector2i = size_value as Vector2i
	var usable_rect: Rect2i = restore_usable_rect_(
		Rect2i(saved_position, saved_size)
	)
	var minimum_size: Vector2i = Vector2i(
		mini(kWindowMinimumRestoreSize.x, usable_rect.size.x),
		mini(kWindowMinimumRestoreSize.y, usable_rect.size.y)
	)
	var restored_size: Vector2i = Vector2i(
		clampi(saved_size.x, minimum_size.x, usable_rect.size.x),
		clampi(saved_size.y, minimum_size.y, usable_rect.size.y)
	)
	var overlap: Rect2i = usable_rect.intersection(
		Rect2i(saved_position, restored_size)
	)
	var sufficiently_visible: bool = \
		overlap.size.x >= kWindowMinimumVisibleSize.x \
		and overlap.size.y >= kWindowMinimumVisibleSize.y
	var restored_position: Vector2i
	if sufficiently_visible:
		restored_position = Vector2i(
			clampi(
				saved_position.x,
				usable_rect.position.x,
				usable_rect.end.x - restored_size.x
			),
			clampi(
				saved_position.y,
				usable_rect.position.y,
				usable_rect.end.y - restored_size.y
			)
		)
	else:
		restored_position = usable_rect.position + Vector2i(
			floori(float(usable_rect.size.x - restored_size.x) / 2.0),
			floori(float(usable_rect.size.y - restored_size.y) / 2.0)
		)
	window.mode = Window.MODE_WINDOWED
	window.size = restored_size
	window.position = restored_position
	last_windowed_position_ = restored_position
	last_windowed_size_ = restored_size
	last_window_maximized_ = bool(state.get("maximized", false))
	if last_window_maximized_:
		call_deferred(&"restore_maximized_window_")


func restore_usable_rect_(saved_rect: Rect2i) -> Rect2i:
	var screen_count: int = DisplayServer.get_screen_count()
	if screen_count <= 0:
		return Rect2i(Vector2i.ZERO, Vector2i(1600, 900))
	var primary_screen: int = clampi(
		DisplayServer.get_primary_screen(), 0, screen_count - 1
	)
	var selected_rect: Rect2i = DisplayServer.screen_get_usable_rect(
		primary_screen
	)
	var largest_overlap_area: int = 0
	for screen: int in range(screen_count):
		var usable_rect: Rect2i = DisplayServer.screen_get_usable_rect(screen)
		var overlap: Rect2i = usable_rect.intersection(saved_rect)
		var overlap_area: int = overlap.size.x * overlap.size.y
		if overlap_area > largest_overlap_area:
			largest_overlap_area = overlap_area
			selected_rect = usable_rect
	return selected_rect


func restore_maximized_window_() -> void:
	get_window().mode = Window.MODE_MAXIMIZED


func schedule_window_state_save_() -> void:
	if not uses_desktop_window_state_() \
			or window_state_save_timer_ == null:
		return
	window_state_save_timer_.start()


func save_window_state_now_() -> void:
	if not uses_desktop_window_state_():
		return
	if window_state_save_timer_ != null:
		window_state_save_timer_.stop()
	var window: Window = get_window()
	if window.mode == Window.MODE_WINDOWED:
		last_windowed_position_ = window.position
		last_windowed_size_ = window.size
		last_window_maximized_ = false
	elif window.mode == Window.MODE_MAXIMIZED:
		last_window_maximized_ = true
	var error: Error = SettingsStore.save_window_state(
		last_windowed_position_,
		last_windowed_size_,
		last_window_maximized_
	)
	if error != OK:
		push_warning("Failed to save window state: %s" % error_string(error))


func configure_ui_scaling_() -> void:
	var window: Window = get_window()
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	window.content_scale_size = Vector2i.ZERO
	window.content_scale_stretch = Window.CONTENT_SCALE_STRETCH_FRACTIONAL
	update_ui_scale_()


func update_ui_scale_() -> void:
	var window: Window = get_window()
	var current_scale: float = maxf(window.content_scale_factor, 0.01)
	var logical_height: float = window.get_visible_rect().size.y
	var physical_height: float = logical_height * current_scale
	var height_ratio: float = clampf(
		(physical_height - kUiScaleMinimumHeight)
		/ (kUiScaleMaximumHeight - kUiScaleMinimumHeight),
		0.0,
		1.0
	)
	var target_scale: float = lerpf(
		kUiScaleMinimum,
		kUiScaleMaximum,
		height_ratio
	)
	if SettingsStore.get_large_ui_enabled():
		target_scale *= SettingsStore.get_large_ui_multiplier()
	if not is_equal_approx(current_scale, target_scale):
		window.content_scale_factor = target_scale


func on_large_ui_changed_(_enabled: bool, _multiplier: float) -> void:
	update_ui_scale_()
	apply_horizontal_safe_margin_(SettingsStore.get_horizontal_safe_margin())
	on_board_layout_changed_()


func on_window_size_changed_() -> void:
	update_ui_scale_()
	apply_horizontal_safe_margin_(SettingsStore.get_horizontal_safe_margin())
	on_board_layout_changed_()
	schedule_window_state_save_()


func apply_horizontal_safe_margin_(requested_margin: int) -> void:
	var viewport_width: float = get_viewport_rect().size.x
	var maximum_margin: float = maxf((viewport_width - 320.0) * 0.5, 0.0)
	var applied_margin: float = minf(float(maxi(requested_margin, 0)), maximum_margin)
	for safe_area: Control in [
		interface_safe_area_,
		branch_visualization_safe_area_,
		note_mark_safe_area_,
	]:
		safe_area.offset_left = applied_margin
		safe_area.offset_right = -applied_margin
	camera_.set(&"horizontal_safe_margin", applied_margin)
	camera_.call(&"update_zoom_")
	call_deferred(&"on_board_layout_changed_")


func apply_board_width_percentage_(percentage: int) -> void:
	camera_.set(
		&"board_width_percentage",
		clampi(
			percentage,
			SettingsStore.kBoardWidthPercentageMinimum,
			SettingsStore.kBoardWidthPercentageMaximum
		)
	)
	camera_.call(&"update_zoom_")
	call_deferred(&"on_board_layout_changed_")


func _input(event: InputEvent) -> void:
	if export_in_progress_:
		return
	if export_success_dialog_.visible and event is InputEventKey:
		var success_key_event: InputEventKey = event as InputEventKey
		if success_key_event.pressed and not success_key_event.echo \
				and success_key_event.keycode in [
					KEY_SPACE, KEY_ESCAPE, KEY_ENTER, KEY_KP_ENTER
				]:
			export_success_dialog_.hide()
			get_viewport().set_input_as_handled()
			return
	if save_confirmation_.visible:
		if event is InputEventKey:
			var save_key_event: InputEventKey = event as InputEventKey
			if save_key_event.pressed and not save_key_event.echo \
					and save_key_event.keycode == KEY_ESCAPE:
				save_confirmation_.hide()
				on_save_canceled_()
				get_viewport().set_input_as_handled()
		return
	if close_tab_confirmation_.visible:
		return
	if setup_branch_popup_.visible and event is InputEventKey:
		var popup_key_event: InputEventKey = event as InputEventKey
		if popup_key_event.pressed and not popup_key_event.echo \
				and popup_key_event.keycode == KEY_ESCAPE:
			setup_branch_popup_.hide()
			get_viewport().set_input_as_handled()
			return
	if branch_order_popup_.visible and event is InputEventKey:
		var order_key_event: InputEventKey = event as InputEventKey
		if order_key_event.pressed and not order_key_event.echo \
				and order_key_event.keycode == KEY_ESCAPE:
			branch_order_popup_.cancel()
			get_viewport().set_input_as_handled()
			return
	if branch_visualization_layer_.visible:
		if event is InputEventKey:
			var branch_key_event: InputEventKey = event as InputEventKey
			if branch_key_event.pressed and not branch_key_event.echo \
					and branch_key_event.keycode == KEY_ESCAPE:
				var dialog_canceled: bool = bool(
					branch_visualization_.call(&"cancel_dialog")
				)
				if not dialog_canceled:
					on_branch_visualization_exit_requested_()
				get_viewport().set_input_as_handled()
		return
	if note_mark_mode_ != kNoteMarkDisabled:
		return
	if territory_mode_active_:
		return
	if event is not InputEventKey or board_.is_variation_mode():
		return
	var key_event: InputEventKey = event as InputEventKey
	if not key_event.pressed or key_event.echo \
			or not key_event.ctrl_pressed \
			or key_event.alt_pressed or key_event.meta_pressed:
		return
	if key_event.shift_pressed:
		return

	var focus_owner: Control = get_viewport().gui_get_focus_owner()
	# 文本编辑器拥有焦点时，仅保留与常规编辑操作冲突的组合键；其余
	# 应用快捷键仍按全局快捷键处理。未在下方匹配的复制、粘贴、重做等
	# 组合键会继续传递给文本控件。
	var text_editor_focused: bool = focus_owner is LineEdit \
			or focus_owner is TextEdit
	if text_editor_focused and key_event.keycode in [KEY_A, KEY_X, KEY_Z]:
		return
	if board_.is_preset_mode() and key_event.keycode != KEY_Q:
		return

	var handled: bool = false
	match key_event.keycode:
		KEY_N:
			on_new_tab_requested_()
			handled = true
		KEY_S:
			on_save_requested_()
			handled = true
		KEY_A:
			on_save_as_requested_()
			handled = true
		KEY_O:
			settings_ui_.call(&"toggle_panel")
			handled = true
		KEY_Z:
			handled = perform_undo_()
		KEY_R:
			handled = perform_redo_()
		KEY_G:
			on_find_previous_requested_()
			handled = true
		KEY_F:
			on_find_next_requested_()
			handled = true
		KEY_X:
			on_reorder_branch_requested_()
			handled = true
		KEY_E:
			on_board_lock_toggled_(not board_.is_interactions_locked())
			handled = true
		KEY_Q:
			on_next_color_requested_()
			handled = true
		KEY_H:
			on_preset_requested_()
			handled = true
		KEY_T:
			on_variation_requested_()
			handled = true
		KEY_M:
			on_notes_requested_()
			handled = true
		KEY_W:
			on_branch_visualization_requested_()
			handled = true
		_:
			return
	if handled:
		get_viewport().set_input_as_handled()


func on_undo_requested_() -> void:
	var _succeeded: bool = perform_undo_()


func on_redo_requested_() -> void:
	var _succeeded: bool = perform_redo_()


func on_find_previous_requested_() -> void:
	request_after_note_edit_resolution_(
		Callable(board_, "toggle_find_mode").bind(-1)
	)


func on_find_next_requested_() -> void:
	request_after_note_edit_resolution_(
		Callable(board_, "toggle_find_mode").bind(1)
	)


func on_find_mode_changed_(direction: int) -> void:
	find_previous_button_.set_pressed_no_signal(direction == -1)
	find_next_button_.set_pressed_no_signal(direction == 1)


func on_reorder_branch_requested_() -> void:
	request_after_note_edit_resolution_(
		Callable(self, "open_reorder_branch_popup_")
	)


func open_reorder_branch_popup_() -> void:
	board_.cancel_pending_move()
	var typed_branches: Array[Dictionary] = current_next_branches_()
	if typed_branches.is_empty():
		return
	if setup_branch_popup_.visible:
		setup_branch_popup_.hide()
	if board_.is_cut_branch_mode():
		board_.toggle_cut_branch_mode()
	if find_previous_button_.button_pressed:
		board_.toggle_find_mode(-1)
	if find_next_button_.button_pressed:
		board_.toggle_find_mode(1)
	branch_order_popup_.rebuild(
		go_notes_,
		int(go_notes_.get_current_uid()),
		typed_branches
	)
	var popup_size: Vector2i = Vector2i(
		548,
		clampi(92 + typed_branches.size() * 132, 260, 560)
	)
	var viewport_size: Vector2i = Vector2i(get_viewport_rect().size)
	var safe_left: float = interface_safe_area_.global_position.x
	var safe_right: float = safe_left + interface_safe_area_.size.x
	var popup_position: Vector2 = Vector2(
		reorder_branch_button_.global_position.x \
			+ reorder_branch_button_.size.x + 8.0,
		reorder_branch_button_.global_position.y
	)
	if popup_position.x + popup_size.x > safe_right - 8.0:
		popup_position.x = reorder_branch_button_.global_position.x \
			- float(popup_size.x) - 8.0
	popup_position.x = clampf(
		popup_position.x,
		safe_left + 8.0,
		maxf(safe_right - float(popup_size.x) - 8.0, safe_left + 8.0)
	)
	popup_position.y = clampf(
		popup_position.y,
		8.0,
		maxf(float(viewport_size.y - popup_size.y - 8), 8.0)
	)
	branch_order_popup_.popup(Rect2i(
		Vector2i(roundi(popup_position.x), roundi(popup_position.y)),
		popup_size
	))


func on_branch_order_accepted_(
	parent_uid: int,
	ordered_uids: PackedInt64Array
) -> void:
	if parent_uid != int(go_notes_.get_current_uid()):
		push_warning(tr("当前局面已经改变，分支顺序调整已放弃。"))
		return
	var result: int = int(
		go_notes_.call(&"reorder_branches", parent_uid, ordered_uids)
	)
	if result != 0:
		push_warning(CommandMessages.localize(go_notes_.get_message()))


func on_branch_delete_requested_(parent_uid: int, branch_uid: int) -> void:
	if parent_uid != int(go_notes_.get_current_uid()):
		push_warning(tr("当前局面已经改变，分支删除已放弃。"))
		branch_order_popup_.cancel()
		return
	if not current_next_branch_exists_(branch_uid):
		push_warning(tr("所选分支已不存在。"))
		branch_order_popup_.cancel()
		return

	branch_popup_command_in_progress_ = true
	var result: int = int(
		go_notes_.execute_command("CUTBRANCH,%d;" % branch_uid)
	)
	branch_popup_command_in_progress_ = false
	if result != 0:
		push_warning(CommandMessages.localize(go_notes_.get_message()))
		return
	branch_order_popup_.apply_deleted_branch(branch_uid)


func on_branch_enter_requested_(parent_uid: int, branch_uid: int) -> void:
	if parent_uid != int(go_notes_.get_current_uid()):
		push_warning(tr("当前局面已经改变，无法进入所选分支。"))
		branch_order_popup_.cancel()
		return
	if not current_next_branch_exists_(branch_uid):
		push_warning(tr("所选分支已不存在。"))
		branch_order_popup_.cancel()
		return

	branch_popup_command_in_progress_ = true
	var succeeded: bool = board_.roam_to_next_branch(branch_uid)
	branch_popup_command_in_progress_ = false
	if not succeeded:
		push_warning(CommandMessages.localize(go_notes_.get_message()))
		return
	branch_order_popup_.rebuild(
		go_notes_,
		int(go_notes_.get_current_uid()),
		current_next_branches_()
	)


func current_next_branch_exists_(branch_uid: int) -> bool:
	for branch: Dictionary in current_next_branches_():
		if int(branch.get("uid", -1)) == branch_uid:
			return true
	return false


func current_next_branches_() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for value: Variant in Array(go_notes_.call(&"get_next_moves")):
		if value is Dictionary:
			result.append(Dictionary(value))
	return result


func update_reorder_branch_button_() -> void:
	var branch_count: int = Array(
		go_notes_.call(&"get_next_moves")
	).size()
	reorder_branch_button_.disabled = branch_count < 1
	reorder_branch_button_.tooltip_text = \
		tr("调整或删除下一手分支（%d，Ctrl+X）") % branch_count \
		if branch_count >= 1 \
		else tr("当前局面没有可调整或删除的下一手分支")


func on_setup_branches_changed_(branches: Array[Dictionary]) -> void:
	setup_branches_ = branches.duplicate(true)
	var available: bool = not setup_branches_.is_empty() \
		and not board_.is_variation_mode() \
		and not board_.is_preset_mode()
	setup_branch_button_.visible = available
	setup_branch_count_.text = str(setup_branches_.size())
	setup_branch_button_.tooltip_text = tr("选择下一步的预置棋子分支（%d）") \
		% setup_branches_.size()
	if setup_branch_popup_.visible:
		setup_branch_popup_.hide()
	update_reorder_branch_button_()
	call_deferred(&"position_board_toolbar_")


func on_setup_branch_requested_() -> void:
	board_.cancel_pending_move()
	if setup_branches_.is_empty():
		return
	setup_branch_popup_.rebuild(go_notes_, setup_branches_)
	var popup_size: Vector2i = Vector2i(
		356,
		clampi(76 + setup_branches_.size() * 132, 220, 520)
	)
	var viewport_size: Vector2i = Vector2i(get_viewport_rect().size)
	var safe_left: float = interface_safe_area_.global_position.x
	var safe_right: float = safe_left + interface_safe_area_.size.x
	var popup_position: Vector2 = Vector2(
		setup_branch_button_.global_position.x \
			+ setup_branch_button_.size.x + 8.0,
		setup_branch_button_.global_position.y
	)
	if popup_position.x + popup_size.x > safe_right - 8.0:
		popup_position.x = setup_branch_button_.global_position.x \
			- float(popup_size.x) - 8.0
	popup_position.x = clampf(
		popup_position.x,
		safe_left + 8.0,
		maxf(safe_right - float(popup_size.x) - 8.0, safe_left + 8.0)
	)
	popup_position.y = clampf(
		popup_position.y,
		8.0,
		maxf(float(viewport_size.y - popup_size.y - 8), 8.0)
	)
	setup_branch_popup_.popup(Rect2i(
		Vector2i(roundi(popup_position.x), roundi(popup_position.y)),
		popup_size
	))


func on_setup_branch_hovered_(uid: int) -> void:
	var _previewed: bool = board_.set_setup_branch_preview(uid)


func on_setup_branch_preview_cleared_() -> void:
	board_.clear_setup_branch_preview()


func on_setup_branch_selected_(uid: int) -> void:
	if not board_.roam_to_setup_branch(uid):
		push_warning(tr("所选预置棋子分支已经不存在。"))


func on_new_tab_requested_() -> void:
	request_after_note_edit_resolution_(Callable(self, "create_new_tab_"))


func create_new_tab_() -> void:
	var document: DocumentState = DocumentState.new()
	document.notes = GoNotes.new()
	document.title = unique_document_title_(tr("新建笔记"))
	documents_.append(document)
	switch_document_(documents_.size() - 1)


func on_save_requested_() -> void:
	request_after_note_edit_resolution_(Callable(self, "request_save_"))


func request_save_() -> void:
	if active_document_index_ < 0 \
			or active_document_index_ >= documents_.size():
		return
	var document: DocumentState = documents_[active_document_index_]
	if document.file_path.is_empty() or not document.source_writable:
		show_save_dialog_()
		return
	request_save_confirmation_(document.file_path)


func on_save_as_requested_() -> void:
	request_after_note_edit_resolution_(Callable(self, "request_save_as_"))


func request_save_as_() -> void:
	if active_document_index_ < 0 \
			or active_document_index_ >= documents_.size():
		return
	show_save_dialog_()


func show_save_dialog_() -> void:
	if focus_active_file_dialog_():
		return
	var document: DocumentState = documents_[active_document_index_]
	if document.file_path.is_empty() or not document.source_writable:
		var suggested_name: String = document.title
		if suggested_name.get_extension().to_lower() != "sgf":
			suggested_name += ".sgf"
		save_file_dialog_.current_file = suggested_name
	else:
		save_file_dialog_.current_path = document.file_path
	active_file_dialog_ = save_file_dialog_
	save_file_dialog_.popup_centered_ratio(0.72)


func on_save_file_selected_(path: String) -> void:
	active_file_dialog_ = null
	var save_path: String = path
	if not save_path.begins_with("content://") \
			and save_path.get_extension().to_lower() != "sgf":
		save_path += ".sgf"
	request_save_confirmation_(save_path)


func request_save_confirmation_(path: String) -> void:
	pending_save_path_ = path
	var display_path: String = DocumentDisplayName.from_path(path)
	if display_path.is_empty():
		display_path = path
	save_confirmation_.dialog_text = tr("DIALOG_SAVE_TO_PATH") % display_path
	save_confirmation_.popup_centered(Vector2i(520, 190))


func on_save_confirmed_() -> void:
	var save_path: String = pending_save_path_
	pending_save_path_ = ""
	if save_path.is_empty():
		return
	save_document_to_(save_path)


func on_save_canceled_() -> void:
	pending_save_path_ = ""


func save_document_to_(path: String) -> bool:
	if active_document_index_ < 0 \
			or active_document_index_ >= documents_.size():
		return false
	var saved: bool = bool(go_notes_.call(&"save_sgf_file", path))
	if not saved:
		save_error_dialog_.dialog_text = CommandMessages.localize(
			go_notes_.get_message()
		)
		save_error_dialog_.popup_centered(Vector2i(480, 180))
		return false

	var document: DocumentState = documents_[active_document_index_]
	document.file_path = path
	document.source_writable = true
	var file_name: String = DocumentDisplayName.from_path(path)
	if file_name.is_empty():
		file_name = tr("新建笔记.sgf")
	document.title = unique_document_title_(
		file_name, active_document_index_
	)
	refresh_document_tabs_()
	return true


func on_export_requested_() -> void:
	request_after_note_edit_resolution_(Callable(self, "request_export_"))


func on_tool_menu_id_pressed_(item_id: int) -> void:
	match item_id:
		kToolKeepMainLine:
			request_after_note_edit_resolution_(
				Callable(self, "request_keep_main_line_")
			)
		kToolClearNotes:
			request_after_note_edit_resolution_(
				Callable(self, "request_clear_notes_")
			)


func refresh_tool_menu_() -> void:
	tool_menu_.clear()
	tool_menu_.add_item(tr("保留主干"), kToolKeepMainLine)
	tool_menu_.add_item(tr("清除笔记"), kToolClearNotes)


func refresh_file_dialog_filters_() -> void:
	save_file_dialog_.filters = PackedStringArray([
		"*.sgf ; %s" % tr("SGF 棋谱"),
	])
	export_file_dialog_.filters = PackedStringArray([
		"*.pptx ; %s" % tr("PowerPoint 演示文稿"),
	])


func refresh_localized_ui_() -> void:
	refresh_tool_menu_()
	refresh_file_dialog_filters_()
	configure_human_play_options_()
	var used_titles: Dictionary = {}
	for document: DocumentState in documents_:
		if not document.file_path.is_empty():
			used_titles[document.title] = true
	var untitled_base: String = tr("新建笔记")
	var untitled_suffix: int = 1
	for document: DocumentState in documents_:
		if not document.file_path.is_empty():
			continue
		var candidate: String = untitled_base if untitled_suffix == 1 \
			else "%s %d" % [untitled_base, untitled_suffix]
		while used_titles.has(candidate):
			untitled_suffix += 1
			candidate = "%s %d" % [untitled_base, untitled_suffix]
		document.title = candidate
		used_titles[candidate] = true
		untitled_suffix += 1
	refresh_document_tabs_()
	update_reorder_branch_button_()
	if not setup_branches_.is_empty():
		setup_branch_button_.tooltip_text = tr(
			"选择下一步的预置棋子分支（%d）"
		) % setup_branches_.size()
	update_next_color_button_(board_.get_next_color())
	on_preset_mode_changed_(board_.is_preset_mode())
	for localized_node: Node in [
		board_,
		board_size_dialog_,
		notes_panel_,
		sgf_metadata_panel_,
		katago_analysis_panel_,
		branch_order_popup_,
		setup_branch_popup_,
		branch_visualization_,
	]:
		if localized_node.has_method(&"refresh_localized_texts"):
			localized_node.call(&"refresh_localized_texts")


func on_tool_menu_about_to_popup_() -> void:
	call_deferred(&"position_tool_menu_")


func position_tool_menu_() -> void:
	if not tool_menu_.visible:
		return
	var button_rect: Rect2 = tool_button_.get_global_rect()
	var menu_size: Vector2i = tool_menu_.size
	tool_menu_.position = Vector2i(
		roundi(maxf(
			button_rect.position.x - float(menu_size.x) - kToolMenuGap,
			interface_safe_area_.global_position.x
		)),
		roundi(button_rect.position.y)
	)


func request_keep_main_line_() -> void:
	keep_main_line_confirmation_.popup_centered(Vector2i(560, 220))


func on_keep_main_line_confirmed_() -> void:
	var result: int = int(go_notes_.execute_command("KEEPMAINLINE;"))
	if result == 0:
		return
	tool_error_dialog_.dialog_text = CommandMessages.localize(
		str(go_notes_.get_message())
	)
	tool_error_dialog_.popup_centered(Vector2i(440, 170))


func request_clear_notes_() -> void:
	clear_notes_confirmation_.popup_centered(Vector2i(560, 220))


func on_clear_notes_confirmed_() -> void:
	var result: int = int(go_notes_.execute_command("CLEARNOTES;"))
	if result == 0:
		return
	tool_error_dialog_.dialog_text = CommandMessages.localize(
		str(go_notes_.get_message())
	)
	tool_error_dialog_.popup_centered(Vector2i(440, 170))


func request_export_() -> void:
	if active_document_index_ < 0 \
			or active_document_index_ >= documents_.size():
		return
	if focus_active_file_dialog_():
		return
	if android_png_export_unavailable_():
		show_android_png_export_unavailable_()
		return
	var document: DocumentState = documents_[active_document_index_]
	export_file_dialog_.current_file = "%s.pptx" % document.title
	active_file_dialog_ = export_file_dialog_
	export_file_dialog_.popup_centered_ratio(0.72)


func on_export_file_selected_(path: String) -> void:
	active_file_dialog_ = null
	var export_path: String = path
	if not export_path.begins_with("content://") \
			and export_path.get_extension().to_lower() != "pptx":
		export_path += ".pptx"
	start_pptx_export_(export_path)


func start_pptx_export_(path: String) -> void:
	if export_in_progress_:
		return
	if android_png_export_unavailable_():
		show_android_png_export_unavailable_()
		return
	var template_file: FileAccess = FileAccess.open(
		kPptxTemplatePath, FileAccess.READ
	)
	if template_file == null:
		on_pptx_export_finished_(
			false, "[GNE0026] cannot read PPTX template"
		)
		return
	var template_data: PackedByteArray = template_file.get_buffer(
		template_file.get_length()
	)
	template_file.close()
	if template_data.is_empty():
		on_pptx_export_finished_(
			false, "[GNE0027] invalid PPTX template"
		)
		return
	var temporary_file: FileAccess = FileAccess.create_temp(
		FileAccess.WRITE_READ, "gotepad-pptx-", "pptx", true
	)
	if temporary_file == null:
		on_pptx_export_finished_(false, tr("无法创建 PPTX 临时文件。"))
		return
	export_temporary_path_ = temporary_file.get_path_absolute()
	temporary_file.close()
	var snapshot_value: Variant = go_notes_.call(
		&"create_pptx_export_snapshot"
	)
	export_notes_ = snapshot_value as GoNotes
	if export_notes_ == null:
		on_pptx_export_finished_(false, tr("无法创建 PPTX 导出快照。"))
		return
	export_in_progress_ = true
	export_target_path_ = path
	export_progress_bar_.min_value = 0.0
	export_progress_bar_.max_value = 1.0
	export_progress_bar_.value = 0.0
	export_progress_dialog_.dialog_text = tr("正在准备导出…")
	export_progress_dialog_.popup_centered(Vector2i(520, 190))
	export_thread_ = Thread.new()
	var start_error: Error = export_thread_.start(
		Callable(self, "export_pptx_worker_").bind(
			export_notes_,
			export_temporary_path_,
			template_data,
			SettingsStore.get_pptx_image_format_name(),
			SettingsStore.get_pptx_board_coordinates()
		)
	)
	if start_error != OK:
		on_pptx_export_finished_(
			false, "Unable to start PPTX export thread: %s" \
				% error_string(start_error)
		)


func android_png_export_unavailable_() -> bool:
	return OS.get_name() == "Android" \
		and SettingsStore.get_pptx_image_format_name().to_lower() == "png"


func show_android_png_export_unavailable_() -> void:
	export_error_dialog_.dialog_text = tr(
		"目前安卓端由于技术原因，不支持将棋盘导出为PNG图片，请切换至SVG模式再导出。SVG图片版的PPTX可使用Microsoft官方版Powerpoint App浏览编辑，请注意WPS可能无法显示SVG图片。"
	)
	export_error_dialog_.popup_centered(Vector2i(640, 240))


func export_pptx_worker_(
	notes: GoNotes,
	path: String,
	template_data: PackedByteArray,
	image_format: String,
	show_board_coordinates: bool
) -> bool:
	return bool(notes.call(
		&"export_pptx_local_file",
		path,
		template_data,
		image_format,
		show_board_coordinates
	))


func on_pptx_export_finished_(exported: bool, message: String) -> void:
	export_thread_ = null
	if export_copy_source_ != null:
		export_copy_source_.close()
	if export_copy_target_ != null:
		export_copy_target_.close()
	export_copy_source_ = null
	export_copy_target_ = null
	if not export_temporary_path_.is_empty():
		DirAccess.remove_absolute(export_temporary_path_)
	export_notes_ = null
	export_in_progress_ = false
	export_target_path_ = ""
	export_temporary_path_ = ""
	export_copy_total_ = 0
	export_copy_current_ = 0
	export_progress_dialog_.hide()
	if not exported:
		export_error_dialog_.dialog_text = CommandMessages.localize(message)
		export_error_dialog_.popup_centered(Vector2i(480, 180))
		return
	export_success_dialog_.popup_centered(Vector2i(360, 150))


func on_export_progress_close_requested_() -> void:
	if export_in_progress_:
		export_progress_dialog_.call_deferred(
			&"popup_centered", Vector2i(520, 190)
		)


func _process(_delta: float) -> void:
	if not export_in_progress_:
		return
	if export_copy_source_ != null:
		copy_pptx_output_chunk_()
		return
	if export_thread_ != null and not export_thread_.is_alive():
		var exported: bool = bool(export_thread_.wait_to_finish())
		export_thread_ = null
		var message: String = "" if exported \
			else str(export_notes_.get_message())
		if not exported:
			on_pptx_export_finished_(false, message)
			return
		begin_pptx_output_copy_()
		return
	if export_notes_ == null:
		return
	var progress: PackedInt64Array = PackedInt64Array(
		export_notes_.call(&"get_pptx_export_progress")
	)
	if progress.size() < 2:
		return
	var current: int = maxi(int(progress[0]), 0)
	var total: int = maxi(int(progress[1]), 0)
	export_progress_bar_.max_value = float(maxi(total, 1))
	export_progress_bar_.value = float(current)
	if total > 0:
		export_progress_dialog_.dialog_text = tr(
			"正在导出第 %d / %d 页…"
		) % [current, total]
	else:
		export_progress_dialog_.dialog_text = tr("正在准备导出…")


func begin_pptx_output_copy_() -> void:
	export_copy_source_ = FileAccess.open(
		export_temporary_path_, FileAccess.READ
	)
	if export_copy_source_ == null:
		on_pptx_export_finished_(false, tr("无法读取已生成的 PPTX 临时文件。"))
		return
	export_copy_target_ = FileAccess.open(export_target_path_, FileAccess.WRITE)
	if export_copy_target_ == null:
		on_pptx_export_finished_(false, tr("无法写入所选的 PPTX 文件。"))
		return
	export_copy_total_ = int(export_copy_source_.get_length())
	export_copy_current_ = 0
	export_progress_bar_.max_value = float(maxi(export_copy_total_, 1))
	export_progress_bar_.value = 0.0
	export_progress_dialog_.dialog_text = tr("正在写入目标文件…")


func copy_pptx_output_chunk_() -> void:
	var remaining: int = export_copy_total_ - export_copy_current_
	if remaining <= 0:
		export_copy_target_.flush()
		var write_error: Error = export_copy_target_.get_error()
		export_copy_source_.close()
		export_copy_target_.close()
		export_copy_source_ = null
		export_copy_target_ = null
		if write_error != OK:
			on_pptx_export_finished_(false, tr("无法写入所选的 PPTX 文件。"))
			return
		on_pptx_export_finished_(true, "")
		return
	var bytes_to_copy: int = mini(remaining, kPptxCopyBytesPerFrame)
	var data: PackedByteArray = export_copy_source_.get_buffer(bytes_to_copy)
	if data.size() != bytes_to_copy \
			or not export_copy_target_.store_buffer(data):
		on_pptx_export_finished_(false, tr("无法写入所选的 PPTX 文件。"))
		return
	export_copy_current_ += bytes_to_copy
	export_progress_bar_.value = float(export_copy_current_)


func on_file_dialog_canceled_() -> void:
	active_file_dialog_ = null


func focus_active_file_dialog_() -> bool:
	if active_file_dialog_ != null:
		active_file_dialog_.grab_focus()
		return true
	for dialog: FileDialog in [save_file_dialog_, export_file_dialog_]:
		if dialog.visible:
			active_file_dialog_ = dialog
			dialog.grab_focus()
			return true
	return false


func on_document_tab_close_requested_(index: int) -> void:
	request_after_note_edit_resolution_(
		Callable(self, "request_document_tab_close_").bind(index)
	)


func request_document_tab_close_(index: int) -> void:
	if index < 0 or index >= documents_.size():
		return
	pending_close_index_ = index
	close_tab_confirmation_.dialog_text = tr("是否关闭标签“%s”？") \
		% documents_[index].title
	close_tab_confirmation_.popup_centered()


func on_close_tab_confirmed_() -> void:
	var index: int = pending_close_index_
	pending_close_index_ = -1
	if index < 0 or index >= documents_.size():
		return

	if index == active_document_index_:
		leave_transient_modes_()
		disconnect_history_signal_(go_notes_)
		documents_.remove_at(index)
		active_document_index_ = -1
		if documents_.is_empty():
			var replacement: DocumentState = DocumentState.new()
			replacement.notes = GoNotes.new()
			replacement.title = unique_document_title_(tr("新建笔记"))
			documents_.append(replacement)
		switch_document_(mini(index, documents_.size() - 1))
		return

	documents_.remove_at(index)
	if index < active_document_index_:
		active_document_index_ -= 1
	refresh_document_tabs_()


func on_close_tab_canceled_() -> void:
	pending_close_index_ = -1


func on_branch_visualization_requested_() -> void:
	request_after_note_edit_resolution_(
		Callable(self, "open_branch_visualization_")
	)


func open_branch_visualization_() -> void:
	board_.cancel_pending_move()
	if setup_branch_popup_.visible:
		setup_branch_popup_.hide()
	restore_katago_panel_after_branch_visualization_ = \
		katago_analysis_panel_.is_panel_open()
	if katago_analysis_panel_.is_panel_open():
		katago_analysis_panel_.suspend_panel()
	background_layer_.visible = false
	board_.hide()
	interface_layer_.visible = false
	branch_visualization_layer_.visible = true
	branch_visualization_.call(&"rebuild", go_notes_)


func on_branch_visualization_exit_requested_() -> void:
	branch_visualization_.call(&"cancel_generation")
	branch_visualization_layer_.visible = false
	background_layer_.visible = true
	board_.show()
	interface_layer_.visible = true
	if restore_katago_panel_after_branch_visualization_:
		restore_katago_panel_after_branch_visualization_ = false
		katago_analysis_panel_.open_panel(go_notes_, board_)
	call_deferred(&"position_board_toolbar_")
	call_deferred(&"position_side_panels_")


func on_notes_requested_() -> void:
	if notes_panel_.is_panel_open():
		pending_side_panel_ = kPendingPanelNone
		notes_panel_.close_panel()
		return
	if sgf_metadata_panel_.is_panel_open():
		pending_side_panel_ = kPendingPanelNotes
		sgf_metadata_panel_.close_panel()
		return
	if katago_analysis_panel_.is_panel_open():
		pending_side_panel_ = kPendingPanelNotes
		katago_analysis_panel_.close_panel()
		return
	pending_side_panel_ = kPendingPanelNone
	notes_panel_.open_panel(go_notes_)


func on_notes_panel_visibility_changed_(opened: bool) -> void:
	notes_button_.set_pressed_no_signal(opened)
	if opened:
		pending_side_panel_ = kPendingPanelNone
		sgf_metadata_button_.set_pressed_no_signal(false)
		katago_analysis_button_.set_pressed_no_signal(false)
	elif pending_side_panel_ == kPendingPanelSgfMetadata:
		pending_side_panel_ = kPendingPanelNone
		sgf_metadata_panel_.open_panel(go_notes_)
	elif pending_side_panel_ == kPendingPanelKatago:
		pending_side_panel_ = kPendingPanelNone
		katago_analysis_panel_.open_panel(go_notes_, board_)
	call_deferred(&"position_side_panels_")


func on_sgf_metadata_requested_() -> void:
	if sgf_metadata_panel_.is_panel_open():
		pending_side_panel_ = kPendingPanelNone
		sgf_metadata_panel_.close_panel()
		return
	if notes_panel_.is_panel_open():
		pending_side_panel_ = kPendingPanelSgfMetadata
		notes_panel_.close_panel()
		return
	if katago_analysis_panel_.is_panel_open():
		pending_side_panel_ = kPendingPanelSgfMetadata
		katago_analysis_panel_.close_panel()
		return
	pending_side_panel_ = kPendingPanelNone
	sgf_metadata_panel_.open_panel(go_notes_)


func on_sgf_metadata_panel_visibility_changed_(opened: bool) -> void:
	sgf_metadata_button_.set_pressed_no_signal(opened)
	if opened:
		pending_side_panel_ = kPendingPanelNone
		notes_button_.set_pressed_no_signal(false)
		katago_analysis_button_.set_pressed_no_signal(false)
	elif pending_side_panel_ == kPendingPanelNotes:
		pending_side_panel_ = kPendingPanelNone
		notes_panel_.open_panel(go_notes_)
	elif pending_side_panel_ == kPendingPanelKatago:
		pending_side_panel_ = kPendingPanelNone
		katago_analysis_panel_.open_panel(go_notes_, board_)
	call_deferred(&"position_side_panels_")


func on_katago_analysis_requested_() -> void:
	if human_play_mode_active_:
		katago_analysis_panel_.show_human_play_panel(
			not katago_analysis_panel_.is_panel_open()
		)
		return
	if katago_analysis_panel_.is_panel_open():
		pending_side_panel_ = kPendingPanelNone
		katago_analysis_panel_.close_panel()
		return
	if notes_panel_.is_panel_open():
		pending_side_panel_ = kPendingPanelKatago
		notes_panel_.close_panel()
		return
	if sgf_metadata_panel_.is_panel_open():
		pending_side_panel_ = kPendingPanelKatago
		sgf_metadata_panel_.close_panel()
		return
	pending_side_panel_ = kPendingPanelNone
	katago_analysis_panel_.open_panel(go_notes_, board_)


func on_katago_analysis_panel_visibility_changed_(opened: bool) -> void:
	katago_analysis_button_.set_pressed_no_signal(opened)
	if human_play_mode_active_ and not territory_mode_active_:
		human_play_panel_was_open_ = opened
	if opened:
		pending_side_panel_ = kPendingPanelNone
		notes_button_.set_pressed_no_signal(false)
		sgf_metadata_button_.set_pressed_no_signal(false)
	elif pending_side_panel_ == kPendingPanelNotes:
		pending_side_panel_ = kPendingPanelNone
		notes_panel_.open_panel(go_notes_)
	elif pending_side_panel_ == kPendingPanelSgfMetadata:
		pending_side_panel_ = kPendingPanelNone
		sgf_metadata_panel_.open_panel(go_notes_)
	call_deferred(&"position_side_panels_")


func on_katago_variation_requested_(pv: Array) -> void:
	request_after_note_edit_resolution_(
		Callable(self, "enter_katago_variation_").bind(pv)
	)


func enter_katago_variation_(pv: Array) -> void:
	side_panel_after_variation_ = kPendingPanelKatago
	katago_analysis_panel_.suspend_panel()
	if not board_.enter_analysis_variation(pv):
		side_panel_after_variation_ = kPendingPanelNone
		katago_analysis_panel_.open_panel(go_notes_, board_)
		push_warning(tr("无法根据KataGo候选进入变化图。"))


func configure_human_play_options_() -> void:
	human_play_ai_color_option_.clear()
	human_play_ai_color_option_.add_item(tr("AI执黑"), kBlack)
	human_play_ai_color_option_.add_item(tr("AI执白"), kWhite)
	human_play_style_option_.clear()
	human_play_style_option_.add_item(tr("现代棋风"), 0)
	human_play_style_option_.add_item(tr("AlphaGo前棋风"), 1)
	human_play_rank_option_.clear()
	for rank_number: int in range(20, 0, -1):
		human_play_rank_option_.add_item("%dk" % rank_number)
	for rank_number: int in range(1, 10):
		human_play_rank_option_.add_item("%dd" % rank_number)
	human_play_rank_option_.select(20)


func on_human_play_requested_() -> void:
	if human_play_mode_active_:
		return
	request_after_note_edit_resolution_(Callable(
		self, "show_human_play_options_"
	))


func show_human_play_options_() -> void:
	if not SettingsStore.has_valid_katago_human_paths():
		show_human_play_error_(tr(
			"KataGo人类模仿棋模型或分析配置无效，请先打开设置检查。"
		))
		return
	var next_color: int = board_.get_next_color()
	human_play_visits_input_.value = float(
		SettingsStore.get_katago_human_max_visits()
	)
	human_play_current_turn_.text = tr("当前由黑方先行") \
		if next_color == kBlack else tr("当前由白方先行")
	var suggested_ai_color: int = kWhite if next_color == kBlack else kBlack
	for index: int in range(human_play_ai_color_option_.item_count):
		if human_play_ai_color_option_.get_item_id(index) == suggested_ai_color:
			human_play_ai_color_option_.select(index)
			break
	human_play_options_dialog_.popup_centered()
	prewarm_human_play_service_()


func prewarm_human_play_service_() -> void:
	if OS.get_name() == "Android" or OS.get_name() == "iOS" \
			or katago_analysis_service_.is_running():
		return
	var _started: bool = katago_human_analysis_service_.ensure_running()


func on_normal_katago_transport_starting_() -> void:
	# 普通分析真正需要启动时再释放桌面端保温中的 Human SL 进程，
	# 避免两套模型同时长期占用 GPU 显存。
	katago_human_analysis_service_.shutdown()


func on_human_katago_runtime_settings_changed_() -> void:
	# 模型、程序或配置变化后不能继续复用按旧设置启动的进程。
	katago_human_analysis_service_.shutdown()


func on_human_play_start_requested_() -> void:
	human_play_options_dialog_.hide()
	var selected_ai_id: int = human_play_ai_color_option_.get_selected_id()
	human_play_ai_color_ = kBlack if selected_ai_id == kBlack else kWhite
	var rank_text: String = human_play_rank_option_.get_item_text(
		human_play_rank_option_.selected
	).to_lower()
	var style_prefix: String = "preaz_" \
		if human_play_style_option_.selected == 1 else "rank_"
	human_play_profile_ = style_prefix + rank_text
	human_play_max_visits_ = maxi(
		roundi(human_play_visits_input_.value), 1
	)
	start_human_play_mode_()


func start_human_play_mode_() -> void:
	human_play_panel_was_open_ = katago_analysis_panel_.is_panel_open()
	if notes_panel_.is_panel_open():
		notes_panel_.close_panel()
	if sgf_metadata_panel_.is_panel_open():
		sgf_metadata_panel_.close_panel()
	if katago_analysis_panel_.is_panel_open():
		katago_analysis_panel_.suspend_panel()
	human_play_mode_active_ = true
	human_play_turns_.clear()
	human_play_finished_ = false
	human_play_ai_placing_ = false
	human_play_takeback_in_progress_ = false
	if not board_.enter_human_play_mode():
		human_play_mode_active_ = false
		show_human_play_error_(tr("无法从当前盘面进入人类模仿棋模式。"))
		if human_play_panel_was_open_:
			call_deferred(
				&"restore_katago_panel_after_human_play_", go_notes_
			)
		human_play_panel_was_open_ = false
		return
	# Android 的 OpenCL 桥和远端 Service 是进程级单例，不能跨模式
	# 保温。桌面端则复用已经预热或上一局留下的 Human SL 进程。
	if OS.get_name() == "Android" or OS.get_name() == "iOS":
		katago_human_analysis_service_.shutdown()
	katago_analysis_service_.shutdown()
	katago_analysis_panel_.begin_human_play_mode(
		board_.get_go_notes(), board_, true
	)
	apply_human_play_toolbar_()
	if board_.get_next_color() == human_play_ai_color_:
		call_deferred(&"request_human_play_ai_move_")
	else:
		set_human_play_waiting_for_human_()


func request_human_play_ai_move_() -> void:
	if not human_play_mode_active_ or human_play_finished_ \
			or not human_play_query_id_.is_empty():
		return
	board_.cancel_pending_move()
	board_.set_human_play_interactions_enabled(false)
	human_play_takeback_button_.disabled = true
	human_play_accept_button_.disabled = true
	territory_scoring_button_.disabled = true
	set_human_play_status_(tr("AI正在思考…"))
	var path: PackedInt64Array = board_.get_playback_path()
	var current_index: int = path.find(board_.get_view_uid())
	var context: Dictionary = {}
	if current_index >= 0:
		context = KataGoQueryBuilder.build_context(
			board_.get_go_notes(), path, current_index
		)
	if context.is_empty():
		on_human_play_service_error_(tr("无法构造当前局面的KataGo请求。"))
		return
	human_play_query_uid_ = board_.get_view_uid()
	human_play_query_id_ = katago_human_analysis_service_.next_query_id(
		"human-play"
	)
	var query: Dictionary = KataGoQueryBuilder.build_human_query(
		context,
		human_play_query_id_,
		human_play_profile_,
		human_play_max_visits_,
		SettingsStore.get_katago_report_interval_seconds(),
		SettingsStore.get_katago_analysis_pv_length()
	)
	# initialPlayer 表示第 0 手的行棋方，不是最终局面的行棋方。只有
	# 没有任何历史着手时，才需要用当前 AI 颜色指定初始行棋方。
	if Array(context.get("moves", [])).is_empty():
		query["initialPlayer"] = \
			"B" if human_play_ai_color_ == kBlack else "W"
	if not katago_human_analysis_service_.submit_query(query):
		human_play_query_id_ = ""
		if not human_play_error_dialog_.visible:
			on_human_play_service_error_(tr(
				"无法向KataGo发送仿人棋请求。"
			))


func on_human_play_analysis_result_(result: Dictionary) -> void:
	if not human_play_mode_active_ \
			or str(result.get("id", "")) != human_play_query_id_:
		return
	var root_info: Dictionary = Dictionary(result.get("rootInfo", {}))
	if not root_info.is_empty():
		katago_analysis_panel_.record_human_play_result(
			human_play_query_uid_, root_info
		)
	if bool(result.get("isDuringSearch", false)):
		return
	human_play_query_id_ = ""
	var selected: Dictionary = select_human_policy_move_(result)
	if selected.is_empty():
		on_human_play_service_error_(tr("无法取得Human SL落子策略。"))
		return
	if bool(selected.get("pass", false)):
		human_play_pass_dialog_.popup_centered(Vector2i(560, 230))
		return
	var row: int = int(selected.get("row", 0))
	var column: int = int(selected.get("column", 0))
	human_play_ai_placing_ = true
	var placed: bool = board_.place_human_ai_stone(
		human_play_ai_color_, row, column
	)
	human_play_ai_placing_ = false
	if not placed:
		on_human_play_service_error_(tr("AI落子失败。"))
		return
	human_play_turns_.append({
		"actor": "ai",
		"uid": board_.get_view_uid(),
		"color": human_play_ai_color_,
	})
	var move_info: Dictionary = Dictionary(selected.get("move_info", {}))
	if not move_info.is_empty():
		katago_analysis_panel_.record_human_play_result(
			board_.get_view_uid(), move_info
		)
	set_human_play_waiting_for_human_()


func select_human_policy_move_(result: Dictionary) -> Dictionary:
	var searched_choice: Dictionary = \
		select_evaluated_human_move_(result)
	if not searched_choice.is_empty():
		return searched_choice
	return select_raw_human_policy_move_(result)


func select_evaluated_human_move_(result: Dictionary) -> Dictionary:
	var move_infos: Array = Array(result.get("moveInfos", []))
	if move_infos.is_empty():
		return {}
	# Human SL 对停一手的原始概率在部分棋谱中不够可靠。按照 KataGo
	# 的建议，仅在主模型搜索结果也将 pass 判为第一选择时才停一手。
	for value: Variant in move_infos:
		var ordered_info: Dictionary = Dictionary(value)
		if int(ordered_info.get("order", -1)) == 0 \
				and str(ordered_info.get("move", "")).to_lower() == "pass":
			return {"pass": true, "move_info": ordered_info}
	var choices: Array[Dictionary] = []
	var total_weight: float = 0.0
	var notes: GoNotes = board_.get_go_notes()
	for value: Variant in move_infos:
		var info: Dictionary = Dictionary(value)
		var move: String = str(info.get("move", "")).strip_edges().to_upper()
		if move == "PASS":
			continue
		var intersection: Vector2i = human_gtp_coordinate_to_intersection_(move)
		if intersection == Vector2i.ZERO:
			continue
		var row: int = intersection.y
		var column: int = intersection.x
		if not bool(notes.call(
				&"can_place_stone", human_play_ai_color_, row, column
		)):
			continue
		var human_prior: float = maxf(float(info.get("humanPrior", 0.0)), 0.0)
		if human_prior <= 0.0:
			continue
		# KataGo 配置统一以黑方视角报告 utility；白方行棋时反向。
		var utility: float = float(info.get("utility", 0.0))
		var ai_utility: float = utility \
			if human_play_ai_color_ == kBlack else -utility
		# 官方建议以 humanPrior * exp(utility / 0.5) 混合人类棋风与
		# 主模型判断。限制指数范围以抵御异常返回值。
		var weight: float = human_prior * exp(clampf(ai_utility / 0.5, -20.0, 20.0))
		if weight <= 0.0 or not is_finite(weight):
			continue
		choices.append({
			"weight": weight,
			"row": row,
			"column": column,
			"move_info": info,
		})
		total_weight += weight
	return choose_weighted_human_move_(choices, total_weight)


func select_raw_human_policy_move_(result: Dictionary) -> Dictionary:
	var policy: Array = Array(result.get("humanPolicy", []))
	var board_size: int = board_.get_board_size()
	if policy.size() < board_size * board_size + 1:
		return {}
	var choices: Array[Dictionary] = []
	var total_weight: float = 0.0
	var notes: GoNotes = board_.get_go_notes()
	for index: int in range(board_size * board_size):
		var weight: float = maxf(float(policy[index]), 0.0)
		if weight <= 0.0:
			continue
		var row: int = board_size - floori(float(index) / float(board_size))
		var column: int = index % board_size + 1
		if not bool(notes.call(
			&"can_place_stone", human_play_ai_color_, row, column
		)):
			continue
		choices.append({
			"weight": weight, "row": row, "column": column,
			"move_info": find_human_move_info_(result, row, column),
		})
		total_weight += weight
	var pass_weight: float = maxf(float(policy[board_size * board_size]), 0.0)
	if pass_weight > 0.0:
		choices.append({"weight": pass_weight, "pass": true})
		total_weight += pass_weight
	if choices.is_empty() or total_weight <= 0.0:
		return {}
	return choose_weighted_human_move_(choices, total_weight)


func choose_weighted_human_move_(
		choices: Array[Dictionary], total_weight: float
) -> Dictionary:
	if choices.is_empty() or total_weight <= 0.0:
		return {}
	var target: float = randf() * total_weight
	for choice: Dictionary in choices:
		target -= float(choice.get("weight", 0.0))
		if target <= 0.0:
			return choice
	return Dictionary(choices[-1])


func human_gtp_coordinate_to_intersection_(coordinate: String) -> Vector2i:
	const coordinate_letters: String = "ABCDEFGHJKLMNOPQRSTUVWXYZ"
	if coordinate.length() < 2:
		return Vector2i.ZERO
	var column_index: int = coordinate_letters.find(coordinate.substr(0, 1))
	var row_text: String = coordinate.substr(1)
	if column_index < 0 or not row_text.is_valid_int():
		return Vector2i.ZERO
	var board_size: int = board_.get_board_size()
	var row: int = board_size - int(row_text) + 1
	var column: int = column_index + 1
	if row < 1 or row > board_size or column < 1 or column > board_size:
		return Vector2i.ZERO
	return Vector2i(column, row)


func find_human_move_info_(
		result: Dictionary, row: int, column: int
) -> Dictionary:
	var coordinate: String = board_coordinate_to_gtp_(row, column)
	for value: Variant in Array(result.get("moveInfos", [])):
		var info: Dictionary = Dictionary(value)
		if str(info.get("move", "")).to_upper() == coordinate:
			return info
	return {}


func board_coordinate_to_gtp_(row: int, column: int) -> String:
	const coordinate_letters: String = "ABCDEFGHJKLMNOPQRSTUVWXYZ"
	if column < 1 or column > coordinate_letters.length():
		return ""
	return "%s%d" % [
		coordinate_letters.substr(column - 1, 1),
		board_.get_board_size() - row + 1,
	]


func set_human_play_waiting_for_human_() -> void:
	if not human_play_mode_active_ or human_play_finished_:
		return
	var human_color: int = kWhite if human_play_ai_color_ == kBlack else kBlack
	board_.set_human_play_next_color(human_color)
	board_.set_human_play_interactions_enabled(true)
	human_play_takeback_button_.disabled = not has_human_play_takeback_()
	human_play_accept_button_.disabled = false
	territory_scoring_button_.disabled = false
	set_human_play_status_(tr("等待您落子"))


func on_human_play_pass_accepted_() -> void:
	if not human_play_mode_active_:
		return
	human_play_finished_ = true
	board_.set_human_play_interactions_enabled(false)
	human_play_takeback_button_.disabled = true
	human_play_accept_button_.disabled = false
	territory_scoring_button_.disabled = false
	set_human_play_status_(tr(
		"双方已停一手，可进行终局数目或保存棋局。"
	))


func on_human_play_pass_rejected_() -> void:
	set_human_play_waiting_for_human_()


func set_human_play_status_(message: String) -> void:
	katago_analysis_panel_.set_human_play_status(
		"[%s] %s" % [human_play_profile_, message]
	)


func on_human_play_takeback_requested_() -> void:
	if not human_play_mode_active_ or human_play_finished_ \
			or not human_play_query_id_.is_empty():
		return
	var human_index: int = -1
	for index: int in range(human_play_turns_.size() - 1, -1, -1):
		if str(human_play_turns_[index].get("actor", "")) == "human":
			human_index = index
			break
	if human_index < 0:
		return
	var remove_count: int = human_play_turns_.size() - human_index
	human_play_takeback_in_progress_ = true
	var succeeded: bool = board_.takeback_human_play_moves(remove_count)
	human_play_takeback_in_progress_ = false
	if not succeeded:
		show_human_play_error_(tr("无法悔棋到上一次人类行棋前。"))
		return
	human_play_turns_.resize(human_index)
	set_human_play_waiting_for_human_()
	katago_analysis_panel_.on_board_position_changed(board_.get_view_uid())


func has_human_play_takeback_() -> bool:
	for turn: Dictionary in human_play_turns_:
		if str(turn.get("actor", "")) == "human":
			return true
	return false


func on_human_play_accept_requested_() -> void:
	if not human_play_mode_active_ or not human_play_query_id_.is_empty() \
			or human_play_accept_dialog_.visible:
		return
	human_play_accept_dialog_.popup_centered(Vector2i(600, 240))


func keep_human_play_() -> void:
	if not human_play_mode_active_ or not human_play_query_id_.is_empty():
		return
	stop_human_play_query_()
	if not board_.keep_human_play_mode():
		show_human_play_error_(tr("无法将仿人棋对局保留到主棋谱。"))
		return
	finish_human_play_mode_()


func on_human_play_cancel_requested_() -> void:
	if human_play_mode_active_ and not human_play_discard_dialog_.visible:
		human_play_discard_paused_ai_ = not human_play_query_id_.is_empty()
		if human_play_discard_paused_ai_:
			stop_human_play_query_()
		human_play_discard_dialog_.popup_centered(Vector2i(560, 230))


func on_human_play_discard_canceled_() -> void:
	if not human_play_mode_active_:
		return
	var resume_ai: bool = human_play_discard_paused_ai_
	human_play_discard_paused_ai_ = false
	if resume_ai:
		call_deferred(&"request_human_play_ai_move_")


func discard_human_play_() -> void:
	if not human_play_mode_active_:
		return
	stop_human_play_query_()
	var _discarded: bool = board_.discard_human_play_mode()
	finish_human_play_mode_()


func finish_human_play_mode_() -> void:
	# 移动端必须释放独占的嵌入式后端；桌面端保留已加载模型的进程，
	# 下一局可直接复用。普通分析真正启动时会再释放该进程。
	if OS.get_name() == "Android" or OS.get_name() == "iOS":
		katago_human_analysis_service_.shutdown()
	katago_analysis_panel_.end_human_play_mode()
	human_play_mode_active_ = false
	human_play_turns_.clear()
	human_play_query_id_ = ""
	human_play_query_uid_ = -1
	human_play_finished_ = false
	human_play_discard_paused_ai_ = false
	restore_human_play_toolbar_()
	if human_play_panel_was_open_:
		call_deferred(
			&"restore_katago_panel_after_human_play_", go_notes_
		)
	human_play_panel_was_open_ = false
	update_mobile_playback_visibility_()
	call_deferred(&"position_board_toolbar_")


func restore_katago_panel_after_human_play_(expected_notes: GoNotes) -> void:
	if not human_play_mode_active_ and go_notes_ == expected_notes:
		katago_analysis_panel_.open_panel(expected_notes, board_)


func stop_human_play_query_() -> void:
	if not human_play_query_id_.is_empty():
		var _terminated: bool = katago_human_analysis_service_.terminate_query(
			human_play_query_id_
		)
	human_play_query_id_ = ""


func on_human_play_query_error_(query_id: String, message: String) -> void:
	if query_id == human_play_query_id_:
		human_play_query_id_ = ""
		on_human_play_service_error_(message)


func on_human_play_service_error_(message: String) -> void:
	if not human_play_mode_active_:
		return
	if territory_mode_active_:
		on_territory_service_error_(message)
		return
	human_play_query_id_ = ""
	board_.set_human_play_interactions_enabled(false)
	human_play_takeback_button_.disabled = not has_human_play_takeback_()
	human_play_accept_button_.disabled = false
	territory_scoring_button_.disabled = false
	show_human_play_error_(message)


func show_human_play_error_(message: String) -> void:
	human_play_error_dialog_.dialog_text = message
	human_play_error_dialog_.popup_centered(Vector2i(600, 240))


func on_territory_scoring_requested_() -> void:
	if territory_mode_active_ or (human_play_mode_active_ \
			and not human_play_query_id_.is_empty()):
		return
	request_after_note_edit_resolution_(
		Callable(self, "show_territory_scoring_confirmation_")
	)


func show_territory_scoring_confirmation_() -> void:
	territory_mode_confirmation_.dialog_text = tr(
		"终局数目目前只支持中国规则。请先收完所有单官，再开始所属判定。"
	)
	territory_mode_confirmation_.popup_centered(Vector2i(620, 220))


func enter_territory_scoring_mode_() -> void:
	if territory_mode_active_:
		return
	territory_side_panel_to_restore_ = kPendingPanelNone
	if notes_panel_.is_panel_open():
		territory_side_panel_to_restore_ = kPendingPanelNotes
		notes_panel_.close_panel()
		if notes_panel_.is_panel_open():
			return
	elif sgf_metadata_panel_.is_panel_open():
		territory_side_panel_to_restore_ = kPendingPanelSgfMetadata
		sgf_metadata_panel_.close_panel()
		if sgf_metadata_panel_.is_panel_open():
			return
	elif katago_analysis_panel_.is_panel_open():
		territory_side_panel_to_restore_ = kPendingPanelKatago
		katago_analysis_panel_.suspend_panel()
		if human_play_mode_active_:
			human_play_panel_was_open_ = true
	if not board_.enter_territory_mode():
		show_territory_error_(tr("无法开始终局数目模式。"))
		restore_side_panel_after_territory_()
		return
	territory_mode_active_ = true
	board_toolbar_.hide()
	territory_toolbar_.show()
	territory_log_output_.text = ""
	territory_log_panel_.show()
	preset_button_.hide()
	mobile_playback_buttons_.hide()
	territory_accept_button_.disabled = true
	append_territory_log_(tr("正在请求 KataGo 所属判定…"))
	call_deferred(&"position_board_toolbar_")

	var path: PackedInt64Array = board_.get_playback_path()
	var current_index: int = path.find(board_.get_view_uid())
	var context: Dictionary = {}
	if current_index >= 0:
		context = KataGoQueryBuilder.build_context(
			board_.get_go_notes(), path, current_index
		)
	if context.is_empty():
		show_territory_error_(tr("无法构造当前局面的KataGo请求。"))
		exit_territory_scoring_mode_()
		return
	var territory_service: KataGoAnalysisService = territory_analysis_service_()
	territory_query_id_ = territory_service.next_query_id(
		"territory"
	)
	var turns: Array = Array(context.get("analyze_turns", []))
	var target_turn: int = int(turns[-1]) if not turns.is_empty() else 0
	var query: Dictionary = KataGoQueryBuilder.build_query(
		context,
		territory_query_id_,
		[target_turn],
		SettingsStore.get_katago_max_visits(),
		SettingsStore.get_katago_report_interval_seconds(),
		2
	)
	query["rules"] = "chinese"
	query["initialPlayer"] = "W" \
		if board_.get_next_color() == kWhite else "B"
	query["includeOwnership"] = true
	if not territory_service.submit_query(query):
		if not territory_mode_active_:
			return
		territory_query_id_ = ""
		show_territory_error_(tr("无法向KataGo发送终局数目请求。"))
		exit_territory_scoring_mode_()


func on_territory_analysis_result_(result: Dictionary) -> void:
	if not territory_mode_active_ \
			or str(result.get("id", "")) != territory_query_id_:
		return
	var during_search: bool = bool(result.get("isDuringSearch", false))
	if during_search:
		var root_info: Dictionary = Dictionary(result.get("rootInfo", {}))
		append_territory_log_(tr("所属判定中 · %d visits") % int(
			root_info.get("visits", 0)
		))
		return
	var ownership: Array = Array(result.get("ownership", []))
	if ownership.size() == board_.get_board_size() * board_.get_board_size():
		var _applied: bool = board_.apply_territory_ownership(ownership)
	territory_query_id_ = ""
	if board_.get_territory_marks().size() \
			!= board_.get_board_size() * board_.get_board_size():
		show_territory_error_(tr("KataGo没有返回有效的所属判定。"))
		exit_territory_scoring_mode_()
		return
	append_territory_log_(tr(
		"所属判定完成，可点击棋盘修正错误地域。"
	))
	territory_accept_button_.disabled = false


func on_territory_query_error_(query_id: String, message: String) -> void:
	if not territory_mode_active_ or query_id != territory_query_id_:
		return
	territory_query_id_ = ""
	append_territory_log_("[ERROR] %s" % message)
	show_territory_error_(message)
	exit_territory_scoring_mode_()


func on_territory_log_received_(line: String) -> void:
	if territory_mode_active_:
		append_territory_log_(line)


func on_territory_service_warning_(message: String) -> void:
	if territory_mode_active_:
		append_territory_log_("[WARNING] %s" % message)


func on_territory_service_error_(message: String) -> void:
	if not territory_mode_active_:
		return
	territory_query_id_ = ""
	append_territory_log_("[ERROR] %s" % message)
	show_territory_error_(message)
	exit_territory_scoring_mode_()


func append_territory_log_(message: String) -> void:
	var normalized: String = message.strip_edges()
	if normalized.is_empty():
		return
	if not territory_log_output_.text.is_empty():
		territory_log_output_.text += "\n"
	territory_log_output_.text += normalized
	territory_log_output_.scroll_vertical = \
		territory_log_output_.get_line_count()


func on_territory_scoring_accept_requested_() -> void:
	if not territory_mode_active_ or territory_accept_button_.disabled:
		return
	var metadata: Dictionary = Dictionary(
		board_.get_go_notes().call(&"get_sgf_metadata")
	)
	var komi_text: String = str(metadata.get("komi", "7.5")).strip_edges()
	var komi: float = float(komi_text) if komi_text.is_valid_float() else 7.5
	var score: Dictionary = TerritoryScoring.score_chinese(
		board_.get_position_states(),
		board_.get_territory_marks(),
		board_.get_board_size(),
		komi
	)
	if score.is_empty():
		show_territory_error_(tr("无法根据当前所属标记完成数目。"))
		return
	var lines: PackedStringArray = PackedStringArray([
		tr("黑方：%d 子 + %d 空 = %.1f") % [
			int(score.black_stones), int(score.black_territory),
			float(score.black_total)
		],
		tr("白方：%d 子 + %d 空 + 贴目 %.1f = %.1f") % [
			int(score.white_stones), int(score.white_territory),
			float(score.komi), float(score.white_total)
		],
		tr("中立点：%d") % int(score.neutral_points),
	])
	var winner: int = int(score.winner)
	if winner == kBlack:
		lines.append(tr("结果：黑方胜 %.1f 目") % float(score.margin))
	elif winner == kWhite:
		lines.append(tr("结果：白方胜 %.1f 目") % float(score.margin))
	else:
		lines.append(tr("结果：和棋"))
	exit_territory_scoring_mode_()
	territory_result_dialog_.dialog_text = "\n".join(lines)
	territory_result_dialog_.popup_centered(Vector2i(560, 280))


func exit_territory_scoring_mode_() -> void:
	if not territory_mode_active_:
		return
	if not territory_query_id_.is_empty():
		var _terminated: bool = territory_analysis_service_().terminate_query(
			territory_query_id_
		)
	territory_query_id_ = ""
	territory_mode_active_ = false
	board_.exit_territory_mode()
	territory_toolbar_.hide()
	territory_log_panel_.hide()
	board_toolbar_.show()
	if human_play_mode_active_:
		apply_human_play_toolbar_()
	update_preset_button_()
	update_mobile_playback_visibility_()
	call_deferred(&"position_board_toolbar_")
	restore_side_panel_after_territory_()


func territory_analysis_service_() -> KataGoAnalysisService:
	return katago_human_analysis_service_ if human_play_mode_active_ \
		else katago_analysis_service_


func restore_side_panel_after_territory_() -> void:
	var panel: int = territory_side_panel_to_restore_
	territory_side_panel_to_restore_ = kPendingPanelNone
	if panel == kPendingPanelNotes:
		notes_panel_.open_panel(go_notes_)
	elif panel == kPendingPanelSgfMetadata:
		sgf_metadata_panel_.open_panel(go_notes_)
	elif panel == kPendingPanelKatago:
		if human_play_mode_active_:
			katago_analysis_panel_.show_human_play_panel(true)
		else:
			katago_analysis_panel_.open_panel(go_notes_, board_)
	call_deferred(&"position_side_panels_")


func show_territory_error_(message: String) -> void:
	territory_error_dialog_.dialog_text = message
	territory_error_dialog_.popup_centered(Vector2i(560, 220))


func on_board_position_changed_(uid: int) -> void:
	update_variation_takeback_button_()
	if human_play_mode_active_:
		katago_analysis_panel_.on_board_position_changed(uid)
		if human_play_ai_placing_ or human_play_takeback_in_progress_ \
				or human_play_finished_:
			return
		var node: Dictionary = Dictionary(
			board_.get_go_notes().call(&"get_node_at", uid)
		)
		var human_color: int = kWhite \
			if human_play_ai_color_ == kBlack else kBlack
		if int(node.get("color", 0)) != human_color:
			return
		human_play_turns_.append({
			"actor": "human", "uid": uid, "color": human_color,
		})
		board_.set_human_play_interactions_enabled(false)
		human_play_takeback_button_.disabled = true
		call_deferred(&"request_human_play_ai_move_")
		return
	if board_.is_variation_mode():
		return
	katago_analysis_panel_.on_board_position_changed(uid)


func on_playback_navigation_changed_(
		can_previous: bool,
		can_next: bool
) -> void:
	mobile_playback_previous_button_.disabled = not can_previous
	mobile_playback_next_button_.disabled = not can_next


func on_mobile_playback_requested_(direction: int) -> void:
	var _navigated: bool = board_.navigate_playback(direction)


func update_mobile_playback_visibility_() -> void:
	var document_initialized: bool = active_document_index_ >= 0 \
		and active_document_index_ < documents_.size() \
		and documents_[active_document_index_].initialized
	mobile_playback_buttons_.visible = OS.has_feature("android") \
		and document_initialized and not board_.is_preset_mode() \
		and not territory_mode_active_ and not human_play_mode_active_


func on_displayed_note_marks_changed_(
	sequential_marks: Array[Dictionary],
	symbol_marks: Array[Dictionary]
) -> void:
	board_.set_displayed_note_marks(sequential_marks, symbol_marks)


func on_note_mark_mode_requested_(
	mode: int,
	note_index: int,
	sequential_marks: Array[Dictionary],
	symbol_marks: Array[Dictionary],
	initial_symbol: String
) -> void:
	if mode != kNoteSequentialMarkMode and mode != kNoteSymbolMarkMode:
		return
	note_mark_mode_ = mode
	note_mark_note_index_ = note_index
	note_mark_original_sequential_ = sequential_marks.duplicate(true)
	note_mark_original_symbols_ = symbol_marks.duplicate(true)
	interface_layer_.visible = false
	note_mark_layer_.visible = true
	if mode == kNoteSequentialMarkMode:
		board_.begin_note_sequential_mark_mode(
			sequential_marks, symbol_marks
		)
	else:
		board_.begin_note_symbol_mark_mode(
			sequential_marks, symbol_marks, initial_symbol
		)
		set_note_symbol_selection_(initial_symbol)
	update_note_mark_toolbar_()
	call_deferred(&"position_note_mark_toolbar_")


func on_note_symbol_selected_(symbol: String) -> void:
	if note_mark_mode_ != kNoteSymbolMarkMode:
		return
	board_.set_active_note_symbol(symbol)
	set_note_symbol_selection_(symbol)


func set_note_symbol_selection_(symbol: String) -> void:
	var selections: Dictionary = {
		"TR": note_triangle_button_,
		"SQ": note_square_button_,
		"CR": note_circle_button_,
		"MA": note_cross_button_,
		"": note_erase_button_
	}
	for key: String in selections:
		var button: Button = selections[key] as Button
		var selected: bool = key == symbol
		button.set_pressed_no_signal(selected)
		if key.is_empty():
			button.add_theme_font_size_override(
				&"font_size", 40 if selected else 34
			)
			button.add_theme_constant_override(
				&"outline_size", 3 if selected else 0
			)
		else:
			button.queue_redraw()


func on_note_mark_draft_changed_() -> void:
	update_note_mark_toolbar_()


func update_note_mark_toolbar_() -> void:
	var sequential: bool = note_mark_mode_ == kNoteSequentialMarkMode
	next_mark_label_.visible = sequential
	note_triangle_button_.visible = not sequential
	note_square_button_.visible = not sequential
	note_circle_button_.visible = not sequential
	note_cross_button_.visible = not sequential
	note_erase_button_.visible = not sequential
	if sequential:
		var mark_count: int = board_.get_note_sequential_mark_count()
		next_mark_label_.text = kSequentialMarkLetters.substr(
			clampi(mark_count, 0, kSequentialMarkLetters.length() - 1), 1
		) if mark_count < kSequentialMarkLetters.length() else tr("满")


func on_note_mark_accept_requested_() -> void:
	if note_mark_mode_ == kNoteMarkDisabled or note_mark_note_index_ < 0:
		return
	var result: int = -1
	if note_mark_mode_ == kNoteSequentialMarkMode:
		var sequential_draft: Array[Dictionary] = \
			board_.get_note_sequential_mark_draft()
		if sequential_draft == note_mark_original_sequential_:
			finish_note_mark_mode_()
			return
		result = int(go_notes_.call(
			&"replace_note_sequential_marks",
			note_mark_note_index_,
			sequential_draft
		))
	else:
		var symbol_draft: Array[Dictionary] = \
			board_.get_note_symbol_mark_draft()
		if symbol_draft == note_mark_original_symbols_:
			finish_note_mark_mode_()
			return
		result = int(go_notes_.call(
			&"replace_note_symbol_marks",
			note_mark_note_index_,
			symbol_draft
		))
	if result != 0:
		push_warning(CommandMessages.localize(go_notes_.get_message()))
		return
	finish_note_mark_mode_()


func on_note_mark_cancel_requested_() -> void:
	if note_mark_mode_ == kNoteMarkDisabled:
		return
	finish_note_mark_mode_()


func finish_note_mark_mode_() -> void:
	board_.end_note_mark_mode()
	note_mark_mode_ = kNoteMarkDisabled
	note_mark_note_index_ = -1
	note_mark_original_sequential_.clear()
	note_mark_original_symbols_.clear()
	note_mark_layer_.visible = false
	interface_layer_.visible = true
	notes_panel_.refresh_current_position()
	call_deferred(&"position_board_toolbar_")
	call_deferred(&"position_side_panels_")


func on_variation_requested_() -> void:
	request_after_note_edit_resolution_(Callable(self, "enter_variation_"))


func enter_variation_() -> void:
	if not board_.enter_variation_mode():
		push_warning(tr("无法从当前盘面进入变化图。"))


func on_variation_exit_requested_() -> void:
	var _variation_exited: bool = board_.exit_variation_mode()


func on_variation_keep_requested_() -> void:
	if not board_.keep_variation_branch():
		push_warning(tr("无法将当前变化图保留到主棋谱。"))


func on_variation_takeback_requested_() -> void:
	board_.request_takeback()


func on_pending_move_accept_requested_() -> void:
	request_after_note_edit_resolution_(Callable(board_, "accept_pending_move"))


func on_pending_move_cancel_requested_() -> void:
	board_.cancel_pending_move()


func on_pending_move_changed_(active: bool) -> void:
	pending_move_accept_button_.visible = active \
		and (not board_.is_variation_mode() or human_play_mode_active_) \
		and not board_.is_preset_mode()
	pending_move_cancel_button_.visible = pending_move_accept_button_.visible
	variation_pending_move_accept_button_.visible = active \
		and board_.is_variation_mode() and not human_play_mode_active_
	variation_pending_move_cancel_button_.visible = \
		variation_pending_move_accept_button_.visible
	if human_play_mode_active_:
		human_play_accept_button_.disabled = active \
			or not human_play_query_id_.is_empty()
		human_play_takeback_button_.disabled = active \
			or human_play_finished_ \
			or not human_play_query_id_.is_empty() \
			or not has_human_play_takeback_()
	call_deferred(&"position_board_toolbar_")


func update_variation_takeback_button_() -> void:
	variation_takeback_button_.disabled = not board_.can_request_takeback()


func on_variation_mode_changed_(enabled: bool) -> void:
	if human_play_mode_active_:
		board_toolbar_.show()
		variation_toolbar_.hide()
		preset_button_.hide()
		update_mobile_playback_visibility_()
		apply_human_play_toolbar_()
		return
	if enabled and katago_analysis_panel_.is_panel_open():
		side_panel_after_variation_ = kPendingPanelKatago
		katago_analysis_panel_.suspend_panel()
	board_toolbar_.visible = not enabled
	variation_toolbar_.visible = enabled
	update_mobile_playback_visibility_()
	update_variation_takeback_button_()
	preset_button_.visible = not enabled
	setup_branch_button_.visible = not enabled \
		and not setup_branches_.is_empty()
	if enabled and setup_branch_popup_.visible:
		setup_branch_popup_.hide()
	if not enabled:
		update_history_buttons_()
		update_preset_button_()
		update_next_color_button_(board_.get_next_color())
		call_deferred(&"position_board_toolbar_")
		restore_side_panel_after_variation_()


func restore_side_panel_after_variation_() -> void:
	var panel_to_restore: int = side_panel_after_variation_
	side_panel_after_variation_ = kPendingPanelNone
	if panel_to_restore == kPendingPanelKatago:
		katago_analysis_panel_.open_panel(go_notes_, board_)
		call_deferred(&"position_side_panels_")


func on_next_color_requested_() -> void:
	if board_.is_preset_erase_mode():
		preset_erase_button_.set_pressed_no_signal(false)
		board_.set_preset_erase_mode(false)
	board_.toggle_next_color()


func on_next_color_changed_(color: int) -> void:
	update_next_color_button_(color)
	update_preset_tool_selection_()


func on_preset_requested_() -> void:
	if board_.is_preset_mode():
		preset_button_.set_pressed_no_signal(true)
		return
	request_after_note_edit_resolution_(Callable(self, "enter_preset_mode_"))


func enter_preset_mode_() -> void:
	board_.toggle_preset_mode()


func on_preset_accept_requested_() -> void:
	request_after_note_edit_resolution_(Callable(self, "accept_preset_mode_"))


func accept_preset_mode_() -> void:
	var _accepted: bool = board_.accept_preset_mode()


func on_preset_cancel_requested_() -> void:
	var _canceled: bool = board_.cancel_preset_mode()


func on_preset_erase_toggled_(enabled: bool) -> void:
	board_.set_preset_erase_mode(enabled)
	update_preset_tool_selection_()


func on_preset_color_requested_(color: int) -> void:
	preset_erase_button_.set_pressed_no_signal(false)
	board_.set_preset_erase_mode(false)
	board_.select_next_color(color)
	update_preset_tool_selection_()


func update_preset_tool_selection_() -> void:
	var erasing: bool = board_.is_preset_erase_mode()
	var color: int = board_.get_next_color()
	var black_active: bool = not erasing and color == kBlack
	var white_active: bool = not erasing and color == kWhite
	preset_black_button_.set_pressed_no_signal(black_active)
	preset_white_button_.set_pressed_no_signal(white_active)
	preset_black_active_mark_.visible = black_active
	preset_white_active_mark_.visible = white_active
	preset_erase_button_.set_pressed_no_signal(erasing)


func on_preset_mode_changed_(enabled: bool) -> void:
	if enabled and katago_analysis_panel_.is_panel_open():
		katago_analysis_panel_.close_panel()
	preset_button_.set_pressed_no_signal(enabled)
	if not enabled:
		preset_erase_button_.set_pressed_no_signal(false)
	preset_button_.tooltip_text = tr("正在预置棋子（Esc 取消）") \
		if enabled else tr("预置棋子（Ctrl+H）")
	update_preset_toolbar_(enabled)
	update_preset_tool_selection_()
	update_preset_button_()
	update_mobile_playback_visibility_()


func update_preset_toolbar_(enabled: bool) -> void:
	for child: Node in board_toolbar_.get_children():
		if child is Control:
			(child as Control).visible = not enabled
	next_color_button_.visible = not enabled
	preset_black_button_.visible = enabled
	preset_white_button_.visible = enabled
	preset_erase_button_.visible = enabled
	preset_accept_button_.visible = enabled
	preset_cancel_button_.visible = enabled
	if not enabled:
		setup_branch_button_.visible = not setup_branches_.is_empty() \
			and not board_.is_variation_mode()
	on_pending_move_changed_(board_.has_pending_move())
	call_deferred(&"position_board_toolbar_")


func update_next_color_button_(color: int) -> void:
	next_color_button_.icon = board_.get_next_color_texture()
	preset_black_button_.icon = board_.get_stone_texture(kBlack)
	preset_white_button_.icon = board_.get_stone_texture(kWhite)
	if color == kBlack:
		next_color_button_.tooltip_text = tr(
			"当前黑方落子；点击或按 Ctrl+Q 切换为白方"
		)
	elif color == kWhite:
		next_color_button_.tooltip_text = tr(
			"当前白方落子；点击或按 Ctrl+Q 切换为黑方"
		)


func perform_undo_() -> bool:
	if not go_notes_.can_undo():
		return false
	request_after_note_edit_resolution_(Callable(self, "perform_undo_now_"))
	return true


func perform_undo_now_() -> void:
	var result: int = int(go_notes_.undo())
	if result != 0:
		push_warning(CommandMessages.localize(go_notes_.get_message()))
		update_history_buttons_()
		return


func perform_redo_() -> bool:
	if not go_notes_.can_redo():
		return false
	request_after_note_edit_resolution_(Callable(self, "perform_redo_now_"))
	return true


func perform_redo_now_() -> void:
	var result: int = int(go_notes_.redo())
	if result != 0:
		push_warning(CommandMessages.localize(go_notes_.get_message()))
		update_history_buttons_()
		return


func on_go_notes_history_changed_() -> void:
	if branch_order_popup_.visible and not branch_popup_command_in_progress_:
		branch_order_popup_.cancel()
	update_history_buttons_()
	update_preset_button_()
	update_reorder_branch_button_()
	notes_panel_.refresh_current_position()
	sgf_metadata_panel_.refresh_metadata()


func update_history_buttons_() -> void:
	var undo_unavailable: bool = not go_notes_.can_undo()
	var redo_unavailable: bool = not go_notes_.can_redo()
	undo_button_.disabled = undo_unavailable
	redo_button_.disabled = redo_unavailable
	undo_unavailable_mark_.visible = undo_unavailable
	redo_unavailable_mark_.visible = redo_unavailable


func update_preset_button_() -> void:
	var unavailable: bool = board_.is_interactions_locked() \
		or int(go_notes_.call(&"can_preset_stone")) != 0
	preset_button_.disabled = unavailable
	preset_unavailable_mark_.visible = unavailable
	if unavailable:
		if board_.is_preset_mode():
			board_.toggle_preset_mode()
		preset_button_.set_pressed_no_signal(false)


func on_document_tab_selected_(index: int) -> void:
	request_after_note_edit_resolution_(
		Callable(self, "switch_document_").bind(index)
	)


func request_after_note_edit_resolution_(action: Callable) -> void:
	notes_panel_.request_action_after_edit_resolution(action)


func on_note_edit_resolution_canceled_() -> void:
	if android_open_action_pending_:
		android_open_action_pending_ = false
		call_deferred(&"dispatch_next_android_open_request_")
	pending_side_panel_ = kPendingPanelNone
	board_.restore_playback_position()
	refresh_document_tabs_()
	update_history_buttons_()
	update_preset_button_()
	notes_button_.set_pressed_no_signal(notes_panel_.is_panel_open())
	find_previous_button_.set_pressed_no_signal(
		board_.get_find_direction() == -1
	)
	find_next_button_.set_pressed_no_signal(board_.get_find_direction() == 1)
	preset_button_.set_pressed_no_signal(board_.is_preset_mode())


func _notification(what: int) -> void:
	if not is_node_ready():
		return
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		refresh_localized_ui_()
		return
	if what == NOTIFICATION_WM_POSITION_CHANGED:
		schedule_window_state_save_()
		return
	if what != NOTIFICATION_WM_CLOSE_REQUEST:
		return
	if export_in_progress_:
		return
	save_window_state_now_()
	request_after_note_edit_resolution_(Callable(self, "quit_application_"))


func quit_application_() -> void:
	save_window_state_now_()
	get_tree().quit()


func switch_document_(index: int) -> void:
	if index < 0 or index >= documents_.size():
		return
	if index == active_document_index_:
		document_tab_bar_.set_selected(index)
		return

	leave_transient_modes_()
	if active_document_index_ >= 0:
		var outgoing: DocumentState = documents_[active_document_index_]
		outgoing.interactions_locked = board_.is_interactions_locked()
		disconnect_history_signal_(outgoing.notes)

	var incoming: DocumentState = documents_[index]
	var previous_index: int = active_document_index_
	var previous_notes: GoNotes = go_notes_
	active_document_index_ = index
	go_notes_ = incoming.notes
	if not board_.bind_go_notes(go_notes_):
		push_error(tr("无法切换到所选棋局标签。"))
		active_document_index_ = previous_index
		go_notes_ = previous_notes
		var _restored: bool = board_.bind_go_notes(go_notes_)
		connect_history_signal_(go_notes_)
		refresh_document_tabs_()
		return

	connect_history_signal_(go_notes_)
	board_lock_checkbox_.set_pressed_no_signal(
		incoming.interactions_locked
	)
	board_.set_interactions_locked(incoming.interactions_locked)
	if incoming.initialized:
		board_size_dialog_.hide()
	else:
		board_size_dialog_.show_dialog()
	update_mobile_playback_visibility_()
	update_history_buttons_()
	update_preset_button_()
	update_next_color_button_(board_.get_next_color())
	if notes_panel_.is_panel_open():
		notes_panel_.open_panel(go_notes_)
	if sgf_metadata_panel_.is_panel_open():
		sgf_metadata_panel_.open_panel(go_notes_)
	if katago_analysis_panel_.is_panel_open():
		katago_analysis_panel_.open_panel(go_notes_, board_)
	refresh_document_tabs_()
	call_deferred(&"position_board_toolbar_")


func leave_transient_modes_() -> void:
	if territory_mode_active_:
		exit_territory_scoring_mode_()
	if human_play_mode_active_:
		stop_human_play_query_()
		var _human_play_discarded: bool = board_.discard_human_play_mode()
		finish_human_play_mode_()
	if note_mark_mode_ != kNoteMarkDisabled:
		on_note_mark_cancel_requested_()
	if branch_visualization_layer_.visible:
		on_branch_visualization_exit_requested_()
	if board_.is_variation_mode():
		var _variation_exited: bool = board_.exit_variation_mode()
	if board_.is_preset_mode():
		var _preset_canceled: bool = board_.cancel_preset_mode()
	if find_previous_button_.button_pressed:
		board_.toggle_find_mode(-1)
	if find_next_button_.button_pressed:
		board_.toggle_find_mode(1)
	if board_.is_cut_branch_mode():
		board_.toggle_cut_branch_mode()
	if setup_branch_popup_.visible:
		setup_branch_popup_.hide()
	if branch_order_popup_.visible:
		branch_order_popup_.cancel()


func connect_history_signal_(notes: GoNotes) -> void:
	var changed_callback: Callable = Callable(
		self, "on_go_notes_history_changed_"
	)
	if not notes.is_connected(&"changed", changed_callback):
		notes.connect(&"changed", changed_callback)


func disconnect_history_signal_(notes: GoNotes) -> void:
	var changed_callback: Callable = Callable(
		self, "on_go_notes_history_changed_"
	)
	if notes.is_connected(&"changed", changed_callback):
		notes.disconnect(&"changed", changed_callback)


func refresh_document_tabs_() -> void:
	var titles: PackedStringArray = PackedStringArray()
	for document: DocumentState in documents_:
		titles.append(document.title)
	document_tab_bar_.set_tabs(titles, active_document_index_)


func unique_document_title_(
	base_title: String,
	excluded_index: int = -1
) -> String:
	var used_titles: Dictionary = {}
	for index: int in range(documents_.size()):
		if index != excluded_index:
			used_titles[documents_[index].title] = true
	if not used_titles.has(base_title):
		return base_title
	var suffix: int = 2
	while used_titles.has("%s %d" % [base_title, suffix]):
		suffix += 1
	return "%s %d" % [base_title, suffix]




func get_go_notes() -> GoNotes:
	return go_notes_


func bind_board_view(board_view: GoBoardView, view_uid: int = -1) -> bool:
	if board_view == null:
		return false
	return board_view.bind_go_notes(go_notes_, view_uid)


func on_create_requested_(board_size: int) -> void:
	if board_.initialize_board(board_size):
		if active_document_index_ >= 0:
			documents_[active_document_index_].initialized = true
		update_mobile_playback_visibility_()
		board_size_dialog_.hide()
	else:
		board_size_dialog_.show_dialog()


func on_image_create_requested_(
	board_size: int, cells: PackedInt32Array, source_path: String
) -> void:
	if cells.size() != board_size * board_size \
			or not board_.initialize_board(board_size):
		board_size_dialog_.show_load_error(
			tr("无法根据图片创建棋盘。")
		)
		board_size_dialog_.show_dialog()
		return

	var command_fields: PackedStringArray = PackedStringArray(["PRESET"])
	for index: int in range(cells.size()):
		var color: int = cells[index]
		if color != kBlack and color != kWhite:
			continue
		var row: int = floori(float(index) / float(board_size)) + 1
		var column: int = index % board_size + 1
		command_fields.append(str(color))
		command_fields.append(str(row))
		command_fields.append(str(column))

	if command_fields.size() > 1:
		var command: String = ",".join(command_fields) + ";"
		if int(go_notes_.execute_command(command)) != 0:
			board_size_dialog_.show_load_error(
				tr("识别盘面无法作为预置棋子创建：%s") %
				CommandMessages.localize(go_notes_.get_message())
			)
			board_size_dialog_.show_dialog()
			return

	if active_document_index_ >= 0:
		var document: DocumentState = documents_[active_document_index_]
		var image_name: String = DocumentDisplayName.from_path(source_path)
		if image_name.is_empty():
			image_name = tr("图片棋盘")
		document.title = unique_document_title_(
			image_name, active_document_index_
		)
		document.file_path = ""
		document.source_writable = true
		document.initialized = true
		document.interactions_locked = true
		refresh_document_tabs_()
	board_lock_checkbox_.set_pressed_no_signal(true)
	board_.set_interactions_locked(true)
	update_history_buttons_()
	update_preset_button_()
	update_mobile_playback_visibility_()
	board_size_dialog_.hide()


func on_board_creation_cancel_requested_() -> void:
	if documents_.size() <= 1 or active_document_index_ < 0:
		return
	var document: DocumentState = documents_[active_document_index_]
	if document.initialized:
		return

	var closing_index: int = active_document_index_
	leave_transient_modes_()
	disconnect_history_signal_(go_notes_)
	documents_.remove_at(closing_index)
	active_document_index_ = -1
	switch_document_(
		clampi(closing_index - 1, 0, documents_.size() - 1)
	)


func on_board_lock_toggled_(locked: bool) -> void:
	board_.set_interactions_locked(locked)
	if active_document_index_ >= 0:
		documents_[active_document_index_].interactions_locked = \
			board_.is_interactions_locked()
	board_lock_checkbox_.set_pressed_no_signal(
		board_.is_interactions_locked()
	)
	update_preset_button_()


func on_board_layout_changed_() -> void:
	call_deferred(&"position_board_toolbar_")
	call_deferred(&"position_side_panels_")
	call_deferred(&"position_note_mark_toolbar_")


func on_board_assets_changed_() -> void:
	update_next_color_button_(board_.get_next_color())
	on_board_layout_changed_()


func apply_human_play_toolbar_() -> void:
	if not human_play_mode_active_:
		return
	if human_play_toolbar_visibility_.is_empty():
		for child: Node in board_toolbar_.get_children():
			if child is Control:
				human_play_toolbar_visibility_[child.name] = \
					(child as Control).visible
	for child: Node in board_toolbar_.get_children():
		if child is Control:
			(child as Control).hide()
	katago_analysis_button_.show()
	human_play_takeback_button_.show()
	human_play_accept_button_.show()
	human_play_cancel_button_.show()
	territory_scoring_button_.show()
	human_play_takeback_button_.disabled = human_play_finished_ \
		or not human_play_query_id_.is_empty() \
		or not has_human_play_takeback_()
	on_pending_move_changed_(board_.has_pending_move())
	call_deferred(&"position_board_toolbar_")


func restore_human_play_toolbar_() -> void:
	for child: Node in board_toolbar_.get_children():
		if child is Control and human_play_toolbar_visibility_.has(child.name):
			(child as Control).visible = bool(
				human_play_toolbar_visibility_[child.name]
			)
	human_play_toolbar_visibility_.clear()
	human_play_takeback_button_.hide()
	human_play_accept_button_.hide()
	human_play_cancel_button_.hide()
	update_history_buttons_()
	update_preset_button_()
	update_next_color_button_(board_.get_next_color())
	on_pending_move_changed_(board_.has_pending_move())


func reorder_board_toolbar_buttons_() -> void:
	# 落子确认和预置分支是临时入口，仍保留在常驻按钮之前。
	var insertion_index: int = setup_branch_button_.get_index() + 1
	var ordered_buttons: Array[Control] = [
		undo_button_,
		redo_button_,
		reorder_branch_button_,
		branch_visualization_button_,
		variation_button_,
		board_lock_checkbox_.get_parent() as Control,
		next_color_button_,
		notes_button_,
		sgf_metadata_button_,
		katago_analysis_button_,
		human_play_button_,
		find_previous_button_,
		find_next_button_,
		territory_scoring_button_,
		human_play_takeback_button_,
		human_play_accept_button_,
		human_play_cancel_button_,
	]
	for button: Control in ordered_buttons:
		board_toolbar_.move_child(button, insertion_index)
		insertion_index += 1


func position_board_toolbar_() -> void:
	if board_.texture == null:
		return
	var board_rect: Rect2 = board_.get_rect()
	var canvas_transform: Transform2D = \
		board_.get_global_transform_with_canvas()
	var board_top_right: Vector2 = canvas_transform * Vector2(
		board_rect.end.x,
		board_rect.position.y
	)
	var toolbar_position: Vector2 = Vector2(
		roundf(
			board_top_right.x + kBoardToolbarGap
			- interface_safe_area_.global_position.x
		),
		get_board_side_controls_top_()
	)
	var viewport_size: Vector2 = interface_safe_area_.size
	board_toolbar_.set_available_height(
		maxf(viewport_size.y - toolbar_position.y - kBoardToolbarGap, 56.0)
	)
	var required_toolbar_size: Vector2 = board_toolbar_.get_required_size()
	var active_toolbar_width: float = required_toolbar_size.x
	if territory_mode_active_:
		active_toolbar_width = maxf(
			territory_toolbar_.get_combined_minimum_size().x, 72.0
		) + kBoardToolbarGap + maxf(
			territory_log_panel_.get_combined_minimum_size().x, 300.0
		)
	var required_right_reserve: float = maxf(
		96.0,
		active_toolbar_width + kBoardToolbarGap * 2.0
	)
	var current_right_reserve: float = float(
		camera_.get("right_ui_reserve")
	)
	if not is_equal_approx(current_right_reserve, required_right_reserve):
		camera_.set("right_ui_reserve", required_right_reserve)
		camera_.call(&"update_zoom_")
		call_deferred(&"position_board_toolbar_")
		return
	board_toolbar_.size = required_toolbar_size
	board_toolbar_.queue_sort()
	board_toolbar_.position = toolbar_position
	variation_toolbar_.position = toolbar_position
	territory_toolbar_.position = toolbar_position
	position_territory_log_panel_()
	position_side_panels_()
	position_note_mark_toolbar_()


func position_territory_log_panel_() -> void:
	if not territory_log_panel_.visible:
		return
	var viewport_size: Vector2 = interface_safe_area_.size
	var left: float = territory_toolbar_.position.x \
		+ maxf(territory_toolbar_.size.x, 72.0) + kBoardToolbarGap
	var right: float = viewport_size.x - 96.0
	if right - left < 240.0:
		left = maxf(12.0, right - 240.0)
	var top: float = get_board_side_controls_top_()
	territory_log_panel_.position = Vector2(left, top)
	territory_log_panel_.size = Vector2(
		maxf(right - left, 240.0),
		maxf(viewport_size.y - top - 12.0, 240.0)
	)


func get_board_side_controls_top_() -> float:
	return roundf(
		document_tab_bar_.position.y + document_tab_bar_.size.y
		+ kBoardToolbarGap
	)


func position_side_panels_() -> void:
	if not notes_panel_.is_panel_open() \
			and not sgf_metadata_panel_.is_panel_open() \
			and not katago_analysis_panel_.is_panel_open():
		return
	var viewport_size: Vector2 = interface_safe_area_.size
	var right: float = viewport_size.x - 96.0
	var left: float = board_toolbar_.position.x \
		+ board_toolbar_.size.x + kBoardToolbarGap
	if right - left < 280.0:
		left = maxf(12.0, right - 280.0)
	var top: float = maxf(board_toolbar_.position.y, 12.0)
	var panel_rect: Rect2 = Rect2(
		Vector2(left, top),
		Vector2(
			maxf(right - left, 240.0),
			maxf(viewport_size.y - top - 12.0, 280.0)
		)
	)
	if notes_panel_.is_panel_open():
		notes_panel_.set_panel_rect(panel_rect)
	if sgf_metadata_panel_.is_panel_open():
		sgf_metadata_panel_.set_panel_rect(panel_rect)
	if katago_analysis_panel_.is_panel_open():
		katago_analysis_panel_.set_panel_rect(panel_rect)


func position_note_mark_toolbar_() -> void:
	if not note_mark_layer_.visible or board_.texture == null:
		return
	var board_rect: Rect2 = board_.get_rect()
	var canvas_transform: Transform2D = \
		board_.get_global_transform_with_canvas()
	var board_top_right: Vector2 = canvas_transform * Vector2(
		board_rect.end.x, board_rect.position.y
	)
	note_mark_toolbar_.position = Vector2(
		roundf(
			board_top_right.x + kBoardToolbarGap
			- note_mark_safe_area_.global_position.x
		),
		get_board_side_controls_top_()
	)


func on_sgf_load_requested_(path: String, source_writable: bool = true) -> void:
	if activate_existing_sgf_document_(path):
		return
	var load_succeeded: bool = bool(
		go_notes_.call(&"load_sgf_file", path)
	)
	if load_succeeded:
		if active_document_index_ >= 0:
			var document: DocumentState = documents_[active_document_index_]
			var file_name: String = DocumentDisplayName.from_path(path)
			if file_name.is_empty():
				var metadata: Dictionary = Dictionary(
					go_notes_.call(&"get_sgf_metadata")
				)
				file_name = DocumentDisplayName.sanitize(
					str(metadata.get("game_name", ""))
				)
			if file_name.is_empty():
				file_name = tr("新建笔记")
			document.title = unique_document_title_(
				file_name, active_document_index_
			)
			document.file_path = path
			document.source_writable = source_writable
			document.initialized = true
			document.interactions_locked = true
			refresh_document_tabs_()
		board_lock_checkbox_.set_pressed_no_signal(true)
		board_.set_interactions_locked(true)
		update_history_buttons_()
		update_preset_button_()
		update_mobile_playback_visibility_()
		board_size_dialog_.hide()
		show_sgf_import_recovery_warnings_()
	else:
		board_size_dialog_.show_load_error(go_notes_.get_message())


func show_sgf_import_recovery_warnings_() -> void:
	var recovery_codes: PackedInt32Array = PackedInt32Array(
		go_notes_.call(&"get_sgf_import_recovery_codes")
	)
	if recovery_codes.is_empty():
		return
	var messages: PackedStringArray = PackedStringArray()
	for code: int in recovery_codes:
		match code:
			kSgfRecoveryIdentifierSanitized:
				messages.append(tr(
					"棋谱中存在不符合 SGF 规范的属性名，程序已删除其中的非法字符。"
				))
			kSgfRecoveryEmptyIdentifierDiscarded:
				messages.append(tr(
					"部分属性名在删除非法字符后为空，对应属性已被丢弃。"
				))
			kSgfRecoveryIdentifierCollisionDiscarded:
				messages.append(tr(
					"部分修复后的属性名与已有属性冲突，对应异常属性已被丢弃。"
				))
			kSgfRecoveryInvalidRulesDefaulted:
				messages.append(tr(
					"棋谱中的规则名称无法被 KataGo 识别，可能影响分析结果；程序已改用 Chinese 规则。"
				))
			kSgfRecoveryInvalidKomiDefaulted:
				messages.append(tr(
					"棋谱中的贴目必须是 0 到 100 之间、以 0.5 递增的数值，否则可能影响 KataGo 分析；程序已改用 7.5。"
				))
			kSgfRecoverySubunitKomiDefaulted:
				messages.append(tr(
					"棋谱中的贴目使用了 0.25 或 0.75 小数，可能混用了“子”和“目”单位；KataGo 使用目数，3.75 子应填写为 7.5，程序现已改用 7.5。"
				))
	if messages.is_empty():
		return
	messages.append(tr("再次保存后，相关内容将按 Gotepad 的兼容格式写出。"))
	sgf_load_warning_dialog_.dialog_text = "\n".join(messages)
	sgf_load_warning_dialog_.popup_centered()


func activate_existing_sgf_document_(path: String) -> bool:
	var normalized_path: String = normalized_file_path_(path)
	if normalized_path.is_empty():
		return false
	var existing_index: int = -1
	for index in range(documents_.size()):
		if index == active_document_index_:
			continue
		var document: DocumentState = documents_[index]
		if document.file_path.is_empty():
			continue
		if normalized_file_path_(document.file_path) == normalized_path:
			existing_index = index
			break
	if existing_index < 0:
		return false

	var closing_index: int = active_document_index_
	if closing_index < 0 or closing_index >= documents_.size():
		switch_document_(existing_index)
		return true
	leave_transient_modes_()
	disconnect_history_signal_(go_notes_)
	documents_.remove_at(closing_index)
	if closing_index < existing_index:
		existing_index -= 1
	active_document_index_ = -1
	switch_document_(existing_index)
	return true


func normalized_file_path_(path: String) -> String:
	if path.is_empty():
		return ""
	if path.begins_with("content://"):
		# Android 文档 URI 是访问身份，不可做路径简化或百分号解码。
		return path
	var normalized: String = ProjectSettings.globalize_path(
		path
	).simplify_path().replace("\\", "/")
	if OS.get_name() == "Windows":
		normalized = normalized.to_lower()
	return normalized
