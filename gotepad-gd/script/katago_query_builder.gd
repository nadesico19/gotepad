class_name KataGoQueryBuilder
extends RefCounted

const kBlack: int = 1
const kWhite: int = 2
const kGtpColumns: String = "ABCDEFGHJKLMNOPQRSTUVWXYZ"


static func build_context(
		go_notes: GoNotes, path: PackedInt64Array, end_index: int = -1
) -> Dictionary:
	if go_notes == null or path.is_empty():
		return {}
	var last_index: int = path.size() - 1 if end_index < 0 \
		else clampi(end_index, 0, path.size() - 1)
	var setup_index: int = find_last_setup_index_(go_notes, path, last_index)
	var base_uid: int = int(path[setup_index])
	var board_size: int = int(go_notes.call(&"get_board_size"))
	var initial_stones: Array = initial_stones_at_(
		go_notes, base_uid, board_size
	)
	var moves: Array = []
	var analyze_turns: Array[int] = [0]
	var turn_uids: Array[int] = [base_uid]
	var expected_color: int = 0
	for index in range(setup_index + 1, last_index + 1):
		var uid: int = int(path[index])
		var node: Dictionary = Dictionary(go_notes.call(&"get_node_at", uid))
		var color: int = int(node.get("color", 0))
		if color != kBlack and color != kWhite:
			continue
		if expected_color != 0 and color != expected_color:
			moves.append([color_name_(expected_color), "pass"])
		var coordinate: String = to_gtp_coordinate_(
			int(node.get("row", 0)), int(node.get("column", 0)), board_size
		)
		if coordinate.is_empty():
			continue
		moves.append([color_name_(color), coordinate])
		expected_color = kWhite if color == kBlack else kBlack
		analyze_turns.append(moves.size())
		turn_uids.append(uid)
	var metadata: Dictionary = Dictionary(go_notes.call(&"get_sgf_metadata"))
	var komi: float = parse_komi_(str(metadata.get("komi", "")))
	var player_to_play: String = str(
		metadata.get("player_to_play", "")
	).strip_edges().to_upper()
	var initial_player: String = "W" if player_to_play == "W" else "B"
	if not moves.is_empty():
		initial_player = str(Array(moves[0])[0])
	return {
		"board_size": board_size,
		"base_uid": base_uid,
		"initialStones": initial_stones,
		"initialPlayer": initial_player,
		"moves": moves,
		"analyze_turns": analyze_turns,
		"turn_uids": turn_uids,
		"rules": normalize_rules_(str(metadata.get("rules", ""))),
		"komi": komi
	}


static func build_path_contexts(
		go_notes: GoNotes, path: PackedInt64Array
) -> Array[Dictionary]:
	var contexts: Array[Dictionary] = []
	if go_notes == null or path.is_empty():
		return contexts
	for index in range(1, path.size()):
		var node: Dictionary = Dictionary(
			go_notes.call(&"get_node_at", int(path[index]))
		)
		if int(node.get("color", -1)) != 0:
			continue
		var previous_context: Dictionary = build_context(
			go_notes, path, index - 1
		)
		if not previous_context.is_empty():
			contexts.append(previous_context)
	var final_context: Dictionary = build_context(
		go_notes, path, path.size() - 1
	)
	if not final_context.is_empty():
		contexts.append(final_context)
	return contexts


static func build_query(
		context: Dictionary,
		query_id: String,
		turns: Array,
		max_visits: int,
		report_interval: float,
		pv_length: int,
		max_playouts: int = 0
) -> Dictionary:
	var query: Dictionary = {
		"id": query_id,
		"moves": context.get("moves", []),
		"initialStones": context.get("initialStones", []),
		"initialPlayer": context.get("initialPlayer", "B"),
		"rules": context.get("rules", "chinese"),
		"komi": context.get("komi", 7.5),
		"boardXSize": context.get("board_size", 19),
		"boardYSize": context.get("board_size", 19),
		"analyzeTurns": turns,
		"maxVisits": maxi(max_visits, 1),
		"reportDuringSearchEvery": maxf(report_interval, 0.1),
		# KataGo 的 analysisPVLen 不包含候选第一手；界面设置表示总手数。
		"analysisPVLen": maxi(pv_length - 1, 1)
	}
	if max_playouts > 0:
		# Analysis Engine 没有独立的顶层 maxPlayouts 字段，需要通过
		# overrideSettings 覆盖；同时解除较小的 maxVisits 限制，避免请求
		# 在达到指定 playouts 前就提前结束。
		query["maxVisits"] = 1000000000
		query["overrideSettings"] = {"maxPlayouts": max_playouts}
	return query


static func find_last_setup_index_(
		go_notes: GoNotes, path: PackedInt64Array, last_index: int
) -> int:
	var result: int = 0
	for index in range(last_index + 1):
		var node: Dictionary = Dictionary(
			go_notes.call(&"get_node_at", int(path[index]))
		)
		if int(node.get("color", -1)) == 0:
			result = index
	return result


static func initial_stones_at_(
		go_notes: GoNotes, uid: int, board_size: int
) -> Array:
	var snapshot: Dictionary = Dictionary(
		go_notes.call(&"get_position_snapshot_at", uid, 0)
	)
	var states: PackedInt32Array = PackedInt32Array(
		snapshot.get("states", PackedInt32Array())
	)
	var result: Array = []
	for index in range(states.size()):
		var color: int = states[index]
		if color != kBlack and color != kWhite:
			continue
		var row: int = floori(float(index) / float(board_size)) + 1
		var column: int = index % board_size + 1
		result.append([
			color_name_(color), to_gtp_coordinate_(row, column, board_size)
		])
	return result


static func to_gtp_coordinate_(row: int, column: int, board_size: int) -> String:
	if row < 1 or row > board_size or column < 1 \
			or column > board_size or column > kGtpColumns.length():
		return ""
	return "%s%d" % [
		kGtpColumns.substr(column - 1, 1), board_size - row + 1
	]


static func color_name_(color: int) -> String:
	return "W" if color == kWhite else "B"


static func parse_komi_(value: String) -> float:
	var normalized: String = value.strip_edges()
	if not normalized.is_valid_float():
		return 7.5
	var parsed: float = float(normalized)
	if not is_finite(parsed) or parsed < 0.0 or parsed > 100.0:
		return 7.5
	if not is_equal_approx(parsed * 2.0, roundf(parsed * 2.0)):
		return 7.5
	return parsed


static func normalize_rules_(value: String) -> String:
	var normalized: String = value.strip_edges().to_lower() \
		.replace("_", "-").replace(" ", "-")
	while "--" in normalized:
		normalized = normalized.replace("--", "-")
	match normalized:
		"japanese", "japanese-rules", "japan", "日本规则", "日本規則":
			return "japanese"
		"korean", "korean-rules", "korea", "韩国规则", "韓國規則":
			return "korean"
		"aga", "aga-rules":
			return "aga"
		"new-zealand", "newzealand":
			return "new-zealand"
		"tromp-taylor":
			return "tromp-taylor"
		"chinese-ogs":
			return "chinese-ogs"
		"chinese-kgs":
			return "chinese-kgs"
		"stone-scoring":
			return "stone-scoring"
		"ancient-territory":
			return "ancient-territory"
		"bga":
			return "bga"
		"aga-button":
			return "aga-button"
	return "chinese"
