class_name FoxwqHistoryDialogs
extends Node

signal sgf_load_requested(content: String, fallback_title: String)

enum Request { NONE, PROFILE, PAGE, SGF }

const kRequestedPageSize: int = 20
const kSearchDialogSize: Vector2i = Vector2i(420, 196)
const kSearchDialogMaxHeight: int = 300
const kSearchLayoutMaxPasses: int = 4
const kSearchLayoutStablePasses: int = 2
const kProfileUrl: String = "https://newframe.foxwq.com/cgi/QueryUserInfoPanel"
const kChessbookUrl: String = "https://h5.foxwq.com/yehuDiamond/chessbook_local/"
const kColumnWidths: Array[int] = [175, 140, 140, 96, 68, 84, 62, 220]
const kSgfRoot: String = r"^\s*\(\s*;"
const kSgfProperty: String = r"\G\s*([A-Za-z]+)\s*((?:\[(?:\\[\s\S]|[^\\\]])*\]\s*)+)"

var nickname_: String = ""
var uid_: String = ""
var cursor_: String = "0"
var page_index_: int = -1
var reached_end_: bool = false
var request_: Request = Request.NONE
var search_layout_version_: int = 0
var pages_: Array[Array] = []
var requested_game_: Dictionary = {}
var sgf_root_: RegEx = RegEx.create_from_string(kSgfRoot)
var sgf_property_: RegEx = RegEx.create_from_string(kSgfProperty)

@onready var search_dialog_: Window = $SearchDialog
@onready var search_margin_: MarginContainer = $SearchDialog/Margin
@onready var results_dialog_: Window = $ResultsDialog
@onready var http_: HTTPRequest = $HTTPRequest
@onready var id_input_: LineEdit = %IdInput
@onready var nickname_input_: LineEdit = %NicknameInput
@onready var search_status_: Label = %SearchStatus
@onready var table_: Tree = %Table
@onready var results_status_: Label = %ResultsStatus
@onready var previous_button_: Button = %PreviousButton
@onready var next_button_: Button = %NextButton
@onready var load_button_: Button = %LoadButton


func _ready() -> void:
	for dialog: Window in [search_dialog_, results_dialog_]:
		dialog.close_requested.connect(dialog.hide)
		dialog.window_input.connect(on_dialog_input_.bind(dialog))
	results_dialog_.visibility_changed.connect(on_results_visibility_changed_)
	%QueryButton.pressed.connect(on_query_pressed_)
	id_input_.text_submitted.connect(on_query_text_submitted_)
	nickname_input_.text_submitted.connect(on_query_text_submitted_)
	previous_button_.pressed.connect(on_previous_pressed_)
	next_button_.pressed.connect(on_next_pressed_)
	load_button_.pressed.connect(on_load_pressed_)
	table_.item_selected.connect(update_buttons_)
	table_.nothing_selected.connect(update_buttons_)
	http_.request_completed.connect(on_request_completed_)
	for column: int in range(kColumnWidths.size()):
		table_.set_column_custom_minimum_width(column, kColumnWidths[column])
		table_.set_column_clip_content(column, true)
		table_.set_column_expand(column, column in [1, 2, 7])


func open_search() -> void:
	search_dialog_.title = tr("搜索野狐棋谱")
	search_status_.hide()
	search_dialog_.popup_centered_clamped(kSearchDialogSize, 0.92)
	settle_search_dialog_height_()
	if not OS.has_feature("mobile"):
		id_input_.grab_focus()


func settle_search_dialog_height_() -> void:
	search_layout_version_ += 1
	var version: int = search_layout_version_
	var content_height: int = 0
	var stable_passes: int = 0
	# 窗口先取得最终宽度，等容器和换行标签跨帧排版后再采用表单高度。
	for _pass_index: int in range(kSearchLayoutMaxPasses):
		await get_tree().process_frame
		if not search_dialog_.visible or version != search_layout_version_:
			return
		var measured_height: int = clampi(
			ceili(search_margin_.get_combined_minimum_size().y),
			kSearchDialogSize.y, kSearchDialogMaxHeight
		)
		if content_height == measured_height:
			stable_passes += 1
			if stable_passes >= kSearchLayoutStablePasses:
				break
		else:
			content_height = measured_height
			stable_passes = 0

	var dialog_size: Vector2i = search_dialog_.size
	if dialog_size.y != content_height:
		dialog_size.y = content_height
		search_dialog_.size = dialog_size
		search_dialog_.move_to_center()


func is_open() -> bool:
	return search_dialog_.visible or results_dialog_.visible


func close_dialogs() -> void:
	search_dialog_.hide()
	results_dialog_.hide()


func show_load_error(message: String) -> void:
	results_status_.text = tr("无法加载野狐棋谱：%s") % message
	update_buttons_()


func on_dialog_input_(event: InputEvent, dialog: Window) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		dialog.set_input_as_handled()
		dialog.hide()


func on_query_text_submitted_(_value: String) -> void:
	on_query_pressed_()


func show_search_error_(message: String) -> void:
	search_status_.text = message
	search_status_.show()
	settle_search_dialog_height_()


func on_query_pressed_() -> void:
	if not search_dialog_.visible:
		return
	var uid: String = id_input_.text.strip_edges()
	var nickname: String = nickname_input_.text.strip_edges()
	if uid.is_empty() == nickname.is_empty():
		show_search_error_(tr("请填写用户 ID 或昵称中的一项。"))
		return
	if not uid.is_empty() and not is_decimal_id_(uid):
		show_search_error_(tr("请输入有效的野狐用户 ID。"))
		return

	uid_ = uid
	nickname_ = nickname
	search_dialog_.hide()
	results_dialog_.title = tr("野狐棋谱搜索结果")
	var titles: Array[String] = [
		tr("开局时间"), tr("黑方"), tr("白方"), tr("比赛结果"), tr("棋盘"),
		tr("让子数"), tr("贴目"), tr("赛事标题"),
	]
	for column: int in range(titles.size()):
		table_.set_column_title(column, titles[column])
	results_dialog_.popup_centered_clamped(Vector2i(1080, 620), 0.92)
	on_next_pressed_()


func on_previous_pressed_() -> void:
	if request_ == Request.NONE and page_index_ > 0:
		show_page_(page_index_ - 1)


func on_next_pressed_() -> void:
	if not results_dialog_.visible or request_ != Request.NONE:
		return
	if page_index_ + 1 < pages_.size():
		show_page_(page_index_ + 1)
	elif not reached_end_:
		results_status_.text = tr("正在查询野狐棋谱…")
		if uid_.is_empty():
			request_url_(Request.PROFILE, "%s?srcuid=0&username=%s" % [
				kProfileUrl, nickname_.uri_encode(),
			])
		else:
			fetch_next_page_()


func fetch_next_page_() -> void:
	request_url_(Request.PAGE,
		kChessbookUrl + "YHWQFetchChessList?srcuid=0&dstuid=%s&type=1&lastCode=%s&fetchnum=%d" % [
			uid_, cursor_, kRequestedPageSize,
		]
	)


func on_load_pressed_() -> void:
	var selected: TreeItem = table_.get_selected()
	if request_ != Request.NONE or selected == null:
		return
	requested_game_ = selected.get_metadata(0)
	results_status_.text = tr("正在下载野狐棋谱…")
	request_url_(Request.SGF, kChessbookUrl + "YHWQFetchChess?chessid=%s" %
		requested_game_["chessid"])


func request_url_(kind: Request, url: String) -> void:
	request_ = kind
	if http_.request(url) != OK:
		request_ = Request.NONE
		results_status_.text = tr("无法向野狐发送请求，请重试。")
	update_buttons_()


func on_request_completed_(
		result: int, status: int, _headers: PackedStringArray, body: PackedByteArray
) -> void:
	var kind: Request = request_
	request_ = Request.NONE
	if kind == Request.NONE or not results_dialog_.visible:
		return
	if result != HTTPRequest.RESULT_SUCCESS or status != 200:
		results_status_.text = tr("无法连接野狐或获取数据，请重试。")
		update_buttons_()
		return
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not parsed is Dictionary:
		show_invalid_response_()
		return
	var code: int = int_field_(parsed.get("result"))
	if kind == Request.PROFILE and code == 104013:
		reached_end_ = true
		results_status_.text = tr("未找到该野狐昵称。")
		update_buttons_()
		return
	if code != 0:
		show_invalid_response_()
		return
	match kind:
		Request.PROFILE:
			var returned_uid: Variant = parsed.get("uid")
			var numeric_uid: int = int_field_(returned_uid)
			if returned_uid is String and is_decimal_id_(returned_uid):
				uid_ = returned_uid
			elif numeric_uid > 0:
				uid_ = str(numeric_uid)
			else:
				show_invalid_response_()
				return
			fetch_next_page_()
		Request.PAGE:
			consume_page_(parsed.get("chesslist"))
		Request.SGF:
			accept_sgf_(parsed)


func show_invalid_response_() -> void:
	results_status_.text = tr("野狐返回的数据无法读取，请重试。")
	update_buttons_()


func consume_page_(response: Variant) -> void:
	if not response is Array:
		show_invalid_response_()
		return
	var response_games: Array = response
	for game: Variant in response_games:
		if not game is Dictionary or not is_decimal_id_(game.get("chessid")):
			show_invalid_response_()
			return
	if response_games.is_empty() or response_games.back()["chessid"] == cursor_:
		reached_end_ = true
		results_status_.text = tr("未找到公开对局。") if pages_.is_empty() \
			else tr("没有更多棋谱。")
		update_buttons_()
		return

	# 每次响应独立成页，以返回的最后一局作为继续查询的游标。
	cursor_ = response_games.back()["chessid"]
	pages_.append(response_games)
	show_page_(pages_.size() - 1)


func show_page_(index: int) -> void:
	page_index_ = index
	table_.clear()
	var root: TreeItem = table_.create_item()
	for game: Dictionary in pages_[index]:
		var cells: Array[String] = [
			optional_text_(game.get("starttime")),
			player_text_(game, "black"), player_text_(game, "white"),
			result_text_(game.get("winner")),
			integer_text_(game.get("boardsize")),
			integer_text_(game.get("handicap")),
			optional_text_(komi_text_(game)),
			optional_text_(game.get("title")),
		]
		var row: TreeItem = table_.create_item(root)
		row.set_metadata(0, game)
		for column: int in range(cells.size()):
			row.set_text(column, cells[column])
			row.set_tooltip_text(column, cells[column])
			if column in [3, 4, 5, 6]:
				row.set_text_alignment(column, HORIZONTAL_ALIGNMENT_CENTER)
	table_.scroll_to_item(root.get_first_child())
	results_status_.text = tr("第 %d 批") % (index + 1)
	update_buttons_()


func update_buttons_() -> void:
	var busy: bool = request_ != Request.NONE
	previous_button_.disabled = busy or page_index_ <= 0
	next_button_.disabled = busy or (reached_end_ and page_index_ + 1 >= pages_.size())
	next_button_.text = tr("重试") if not busy and page_index_ < 0 and not reached_end_ \
		else tr("下一批")
	load_button_.disabled = busy or table_.get_selected() == null


func on_results_visibility_changed_() -> void:
	if results_dialog_.visible:
		return
	request_ = Request.NONE
	http_.cancel_request()
	pages_.clear()
	requested_game_ = {}
	uid_ = ""
	nickname_ = ""
	cursor_ = "0"
	page_index_ = -1
	reached_end_ = false
	table_.clear()
	results_status_.text = ""
	update_buttons_()


func accept_sgf_(response: Dictionary) -> void:
	var game: Dictionary = requested_game_
	requested_game_ = {}
	var content: Variant = response.get("chess")
	if response.get("chessid") != game.get("chessid") \
			or not content is String or sgf_root_.search(content) == null:
		show_invalid_response_()
		return
	var title: String = str(game.get("title", "")).strip_edges()
	if title.is_empty():
		title = "%s - %s" % [game.get("blacknick", ""), game.get("whitenick", "")]
	sgf_load_requested.emit(normalize_sgf_komi_(content, game), title)


func normalize_sgf_komi_(content: String, game: Dictionary) -> String:
	var komi: String = komi_text_(game)
	if komi.is_empty():
		return content
	# 只扫描根节点属性，避免把注释或变化中的 KM 文本当成贴目。
	var root: RegExMatch = sgf_root_.search(content)
	var offset: int = root.get_end()
	var property: RegExMatch = sgf_property_.search(content, offset)
	while property != null and property.get_start() == offset:
		if property.get_string(1) == "KM":
			var value: String = property.get_string(2).strip_edges()
			var raw: String = value.substr(1, value.length() - 2).strip_edges()
			if not raw.is_empty() and (not raw.is_valid_float()
					or raw.to_float() != float(game["komi"])):
				return content
			return content.substr(0, property.get_start(2)) + "[%s]" % komi \
				+ content.substr(property.get_end(2))
		offset = property.get_end()
		property = sgf_property_.search(content, offset)
	return content.insert(root.get_end(), "KM[%s]" % komi)


func player_text_(game: Dictionary, color: String) -> String:
	var name: String = optional_text_(game.get(color + "nick"))
	var rank: int = int_field_(game.get(color + "dan"))
	if rank >= 100 and rank <= 109:
		return "%s (%s)" % [name, tr("职业 %d 段") % (rank - 99)]
	if rank >= 18 and rank <= 27:
		return "%s (%s)" % [name, tr("%d 段") % (rank - 17)]
	if rank >= 0 and rank < 18:
		return "%s (%s)" % [name, tr("%d 级") % (18 - rank)]
	return name


func result_text_(winner: Variant) -> String:
	match int_field_(winner):
		0:
			return tr("和棋")
		1:
			return tr("黑胜")
		2:
			return tr("白胜")
	return "—"


func komi_text_(game: Dictionary) -> String:
	var raw: int = int_field_(game.get("komi"))
	if raw < 0:
		return ""
	if raw == 0:
		return "0"
	match int_field_(game.get("rule")):
		0: # 日本规则，以百分之一目记录。
			return String.num(float(raw) / 100.0, 2)
		1: # 中国规则，以百分之一子记录，换算为目。
			return String.num(float(raw) / 50.0, 2)
	return ""


func integer_text_(value: Variant) -> String:
	var number: int = int_field_(value)
	return str(number) if number >= 0 else "—"


func optional_text_(value: Variant) -> String:
	return value if value is String and not value.is_empty() else "—"


func int_field_(value: Variant) -> int:
	if value is float or value is int:
		return int(value)
	if value is String and value.is_valid_int():
		return value.to_int()
	return -1


func is_decimal_id_(value: Variant) -> bool:
	if not value is String or value.lstrip("0").is_empty():
		return false
	for character: String in value:
		if character < "0" or character > "9":
			return false
	return true
