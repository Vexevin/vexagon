extends Node

# ── Hex A* Pathfinder ──────────────────────────────────────────────────────────
# Autoload as "HexPathfinder" in Project Settings → AutoLoad
# Usage:
#   var path = HexPathfinder.find_path(from_world, to_world)
#   Returns Array[Vector2] world positions to walk through, empty if no path.

const HEX_SIZE   := 35.0
const MAP_CENTER := Vector2(3330.0, 2100.0)
const MAX_SEARCH := 2000   # safety cap — prevents runaway search on bad inputs

# Six axial neighbors for pointy-top hex grid
const NEIGHBORS := [
	Vector2i( 1,  0), Vector2i(-1,  0),
	Vector2i( 0,  1), Vector2i( 0, -1),
	Vector2i( 1, -1), Vector2i(-1,  1),
]

var _hex_map: Node = null   # cached reference to HexMap node

# ── Public API ────────────────────────────────────────────────────────────────
func find_path(from_world: Vector2, to_world: Vector2) -> Array:
	var start: Vector2i = _pixel_to_hex(from_world)
	var goal:  Vector2i = _pixel_to_hex(to_world)
	if start == goal:
		return [to_world]
	var result: Array = _astar(start, goal)
	return result

# ── Internal A* ───────────────────────────────────────────────────────────────
func _astar(start: Vector2i, goal: Vector2i) -> Array:
	# open set: Array of [f_score, Vector2i]
	var open: Array = []
	open.append([_h(start, goal), start])

	var came_from: Dictionary = {}
	var g_score: Dictionary   = {}
	g_score[start] = 0.0

	var visited: int = 0

	while open.size() > 0:
		# Pop lowest f_score
		var best_idx: int = 0
		for i in range(1, open.size()):
			if open[i][0] < open[best_idx][0]:
				best_idx = i
		var current: Vector2i = open[best_idx][1]
		open.remove_at(best_idx)

		if current == goal:
			return _reconstruct(came_from, current)

		visited += 1
		if visited > MAX_SEARCH:
			# Couldn't reach goal — return best partial path to goal direction
			return [_hex_to_pixel(goal)]

		for nb in NEIGHBORS:
			var neighbor: Vector2i = Vector2i(current.x + nb.x, current.y + nb.y)
			if not _is_walkable(neighbor):
				continue
			var tentative_g: float = g_score[current] + 1.0
			if not g_score.has(neighbor) or tentative_g < g_score[neighbor]:
				came_from[neighbor] = current
				g_score[neighbor]   = tentative_g
				var f: float        = tentative_g + _h(neighbor, goal)
				open.append([f, neighbor])

	# No path found — move directly toward goal
	return [_hex_to_pixel(goal)]

func _reconstruct(came_from: Dictionary, current: Vector2i) -> Array:
	var path: Array = []
	var node: Vector2i = current
	while came_from.has(node):
		path.append(_hex_to_pixel(node))
		node = came_from[node]
	path.reverse()
	return path

# ── Terrain check ─────────────────────────────────────────────────────────────
func _is_walkable(hex: Vector2i) -> bool:
	if _hex_map == null:
		_hex_map = get_tree().get_root().find_child("HexMap", true, false)
	if _hex_map == null:
		return true   # no map ref — treat everything as walkable
	var t = _hex_map.get_hex_type(hex.x, hex.y)
	# HexType.PIT = 1, HexType.BLOCK = 2 — neither is walkable
	return t == 0

# ── Heuristic — hex distance ──────────────────────────────────────────────────
func _h(a: Vector2i, b: Vector2i) -> float:
	return float(maxi(abs(a.x - b.x), maxi(abs(a.y - b.y), abs((a.x + a.y) - (b.x + b.y)))))

# ── Coordinate conversion ─────────────────────────────────────────────────────
func _pixel_to_hex(world: Vector2) -> Vector2i:
	var p: Vector2 = world - MAP_CENTER
	var q: int = int(round((sqrt(3.0) / 3.0 * p.x - 1.0 / 3.0 * p.y) / HEX_SIZE))
	var r: int = int(round((2.0 / 3.0 * p.y) / HEX_SIZE))
	return Vector2i(q, r)

func _hex_to_pixel(hex: Vector2i) -> Vector2:
	return Vector2(
		HEX_SIZE * (sqrt(3.0) * float(hex.x) + sqrt(3.0) / 2.0 * float(hex.y)),
		HEX_SIZE * 1.5 * float(hex.y)
	) + MAP_CENTER
