class_name TerritoryScoring
extends RefCounted

const kEmpty: int = 0
const kBlack: int = 1
const kWhite: int = 2
const kDirections: Array[Vector2i] = [
	Vector2i(-1, 0), Vector2i(1, 0),
	Vector2i(0, -1), Vector2i(0, 1),
]


static func score_chinese(
		states: PackedInt32Array,
		ownership: PackedInt32Array,
		board_size: int,
		komi: float
) -> Dictionary:
	var point_count: int = board_size * board_size
	if states.size() != point_count or ownership.size() != point_count:
		return {}
	var cleaned: PackedInt32Array = states.duplicate()
	for index: int in range(point_count):
		var stone: int = cleaned[index]
		if (stone == kBlack or stone == kWhite) and ownership[index] != stone:
			cleaned[index] = kEmpty

	var black_stones: int = 0
	var white_stones: int = 0
	for stone: int in cleaned:
		if stone == kBlack:
			black_stones += 1
		elif stone == kWhite:
			white_stones += 1

	var black_territory: int = 0
	var white_territory: int = 0
	var neutral_points: int = 0
	var visited: PackedByteArray = PackedByteArray()
	visited.resize(point_count)
	for start: int in range(point_count):
		if cleaned[start] != kEmpty or visited[start] != 0:
			continue
		var region: Array[int] = []
		var queue: Array[int] = [start]
		var queue_index: int = 0
		var borders_black: bool = false
		var borders_white: bool = false
		visited[start] = 1
		while queue_index < queue.size():
			var index: int = queue[queue_index]
			queue_index += 1
			region.append(index)
			var row: int = floori(float(index) / float(board_size))
			var column: int = index % board_size
			for direction: Vector2i in kDirections:
				var next_row: int = row + direction.y
				var next_column: int = column + direction.x
				if next_row < 0 or next_row >= board_size \
						or next_column < 0 or next_column >= board_size:
					continue
				var next_index: int = next_row * board_size + next_column
				var next_state: int = cleaned[next_index]
				if next_state == kBlack:
					borders_black = true
				elif next_state == kWhite:
					borders_white = true
				elif visited[next_index] == 0:
					visited[next_index] = 1
					queue.append(next_index)
		if borders_black and not borders_white:
			black_territory += region.size()
		elif borders_white and not borders_black:
			white_territory += region.size()
		else:
			neutral_points += region.size()

	var black_total: float = float(black_stones + black_territory)
	var white_total: float = float(white_stones + white_territory) + komi
	var winner: int = kEmpty
	if not is_equal_approx(black_total, white_total):
		winner = kBlack if black_total > white_total else kWhite
	return {
		"cleaned_states": cleaned,
		"black_stones": black_stones,
		"white_stones": white_stones,
		"black_territory": black_territory,
		"white_territory": white_territory,
		"neutral_points": neutral_points,
		"komi": komi,
		"black_total": black_total,
		"white_total": white_total,
		"winner": winner,
		"margin": absf(black_total - white_total),
	}
