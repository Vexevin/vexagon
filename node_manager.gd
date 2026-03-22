extends Node2D

var hovered_hex := Vector2i(-999, -999)
var turret_timers    := {}
var turret_rotations := {}   # hex -> float (radians, current cannon rotation)
var mine_smoke_phase := {}   # hex -> float (smoke animation offset)
var turret_fire_rate := 1.5
var turret_range := 600.0
var turret_damage := 1.0   # base — boosted by Tower Upgrades
var shield_strength := 1.0  # future shield HP multiplier   # ~17 hexes — meaningful coverage on big map

# Gold Mine income
var mine_income_timer := 0.0
var mine_income_rate := 3.0
var mine_gold_per_tick := 10

# Crystal Mine income
const CRYSTAL_MINE_GOLD_COST   := 75
const CRYSTAL_MINE_CRYSTAL_RATE := 2
const CRYSTAL_MINE_TICK_RATE   := 4.0
var crystal_mine_income_timer  := 0.0
var crystal_node_hexes: Dictionary = {}   # Vector2i → true — hexes with crystal node markers

# Ghost / drag-to-place state
var _ghost_hex: Vector2i      = Vector2i(-999, -999)
var _ghost_valid: bool        = false
var _ghost_affordable: bool   = false

const HEX_SIZE := 35.0
var map_center := Vector2(3330.0, 2100.0)   # must match hex_map.MAP_CENTER
var placed_nodes := {}
var node_costs := [10, 25, 65, 150, 300, 600, 777, 800, 900, 10000]

var HEX_NEIGHBORS := [
	Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 1),
	Vector2i(-1, 0), Vector2i(0, -1), Vector2i(1, -1)
]

func _ready() -> void:
	z_index = 5
	z_as_relative = false

func hex_to_pixel(q: int, r: int) -> Vector2:
	var x := HEX_SIZE * (sqrt(3.0) * q + sqrt(3.0) / 2.0 * r)
	var y := HEX_SIZE * (3.0 / 2.0 * r)
	return Vector2(x, y) + map_center

func get_placement_cost() -> int:
	return node_costs[min(placed_nodes.size(), node_costs.size() - 1)]

func get_available_hexes() -> Array:
	var available := []
	var occupied := placed_nodes.keys()
	occupied.append(Vector2i(0, 0))
	for cell in occupied:
		for neighbor in HEX_NEIGHBORS:
			var adj = Vector2i(cell.x + neighbor.x, cell.y + neighbor.y)
			if adj not in occupied and adj not in available:
				if abs(adj.x) <= 5 and abs(adj.y) <= 5 and abs(adj.x + adj.y) <= 5:
					available.append(adj)
	return available

func place_node(hex: Vector2i, type: String) -> void:
	placed_nodes[hex] = type
	queue_redraw()
	# Tell castle to redraw so cutouts update
	var castle = get_parent().get_node_or_null("Castle")
	if castle != null and castle.has_method("queue_redraw"):
		castle.queue_redraw()

func _draw() -> void:
	for hex in placed_nodes.keys():
		var pos = hex_to_pixel(hex.x, hex.y)
		var type = placed_nodes[hex]
		match type:
			"turret":        _draw_turret(pos, hex)
			"shield":        _draw_shield_node(pos)
			"mine":          _draw_mine(pos, hex)
			"crystal_mine":  _draw_crystal_mine(pos, hex)
			_:
				var pts := PackedVector2Array()
				for i in 6:
					var a := deg_to_rad(60.0*float(i)-30.0)
					pts.append(pos + Vector2(cos(a),sin(a)) * HEX_SIZE * 0.7)
				draw_colored_polygon(pts, Color.GRAY)

	# Ghost preview — drawn on top
	if _ghost_hex != Vector2i(-999, -999):
		var gpos := hex_to_pixel(_ghost_hex.x, _ghost_hex.y)
		var hud = get_parent().get_node_or_null("Hud")
		if hud != null:
			_draw_ghost(gpos, hud.selected_node_type)

func _draw_turret(pos: Vector2, hex: Vector2i) -> void:
	const BASE_R    := 20.0
	const CANNON_L  := 22.0
	const CANNON_W  :=  5.0
	const BARREL_L  := 14.0
	const BARREL_W  :=  3.5
	var STEEL       := Color(0.28, 0.30, 0.35)
	var STEEL_LIGHT := Color(0.42, 0.45, 0.52)
	var BARREL_COL  := Color(0.18, 0.20, 0.24)
	var MUZZLE      := Color(1.0,  0.75, 0.2,  0.9)

	# Hex foundation plate
	var base_pts := PackedVector2Array()
	for i in 6:
		var a := deg_to_rad(60.0*float(i)-30.0)
		base_pts.append(pos + Vector2(cos(a),sin(a)) * BASE_R)
	draw_colored_polygon(base_pts, STEEL)
	draw_polyline(base_pts + PackedVector2Array([base_pts[0]]), STEEL_LIGHT, 1.5)

	# Turret dome (octagon)
	var dome_pts := PackedVector2Array()
	for i in 8:
		var a := TAU * float(i) / 8.0
		dome_pts.append(pos + Vector2(cos(a),sin(a)) * 12.0)
	draw_colored_polygon(dome_pts, STEEL_LIGHT)

	# 3 rotating cannons — 120° apart, rotate together
	var rot: float = turret_rotations.get(hex, 0.0)
	for c in 3:
		var base_angle: float = rot + TAU * float(c) / 3.0
		var cdir := Vector2(cos(base_angle), sin(base_angle))
		var cperp := Vector2(-cdir.y, cdir.x)
		# Cannon arm base
		var c0 := pos + cperp * CANNON_W
		var c1 := pos - cperp * CANNON_W
		var c2 := pos + cdir * CANNON_L - cperp * CANNON_W
		var c3 := pos + cdir * CANNON_L + cperp * CANNON_W
		draw_colored_polygon(PackedVector2Array([c0,c1,c2,c3]), BARREL_COL)
		# Barrel tip
		var tip_start := pos + cdir * CANNON_L
		var tip_end   := pos + cdir * (CANNON_L + BARREL_L)
		draw_line(tip_start - cperp*BARREL_W, tip_end - cperp*BARREL_W, STEEL_LIGHT, 2.0)
		draw_line(tip_start + cperp*BARREL_W, tip_end + cperp*BARREL_W, STEEL_LIGHT, 2.0)
		draw_line(tip_start, tip_end, BARREL_COL, BARREL_W*2.0)
		# Muzzle flash dot
		draw_circle(tip_end, 3.0, MUZZLE)

	# Center pivot cap
	draw_circle(pos, 5.5, STEEL_LIGHT)
	draw_circle(pos, 3.0, MUZZLE)

func _draw_shield_node(pos: Vector2) -> void:
	# Shield tower — glowing blue hex with inner power core
	const HS := 22.0
	var SHIELD_BLUE  := Color(0.15, 0.55, 1.0, 0.85)
	var SHIELD_INNER := Color(0.4,  0.75, 1.0, 0.95)
	var SHIELD_CORE  := Color(0.85, 0.95, 1.0, 1.0)
	var base_pts := PackedVector2Array()
	for i in 6:
		var a := deg_to_rad(60.0*float(i)-30.0)
		base_pts.append(pos + Vector2(cos(a),sin(a)) * HS)
	draw_colored_polygon(base_pts, Color(0.05, 0.12, 0.28))
	draw_polyline(base_pts + PackedVector2Array([base_pts[0]]), SHIELD_BLUE, 2.5)
	var inner_pts := PackedVector2Array()
	for i in 6:
		var a := deg_to_rad(60.0*float(i)-30.0)
		inner_pts.append(pos + Vector2(cos(a),sin(a)) * (HS - 7.0))
	draw_polyline(inner_pts + PackedVector2Array([inner_pts[0]]), SHIELD_INNER, 1.5)
	draw_circle(pos, 7.0, SHIELD_BLUE)
	draw_circle(pos, 4.5, SHIELD_INNER)
	draw_circle(pos, 2.0, SHIELD_CORE)

func _draw_mine(pos: Vector2, hex: Vector2i) -> void:
	# Mine node — dark hex body + animated smoke stack
	const HS   := 18.0
	var MINE   := Color(0.12, 0.14, 0.18)
	var MINE_R := Color(0.8,  0.25, 0.1,  0.9)
	var SMOKE  := Color(0.55, 0.55, 0.60, 0.55)
	# Base hex
	var base_pts := PackedVector2Array()
	for i in 6:
		var a := deg_to_rad(60.0*float(i)-30.0)
		base_pts.append(pos + Vector2(cos(a),sin(a)) * HS)
	draw_colored_polygon(base_pts, MINE)
	draw_polyline(base_pts + PackedVector2Array([base_pts[0]]), MINE_R, 2.0)
	# Danger ring
	var ring_pts := PackedVector2Array()
	for i in 8:
		var a := TAU * float(i) / 8.0
		ring_pts.append(pos + Vector2(cos(a),sin(a)) * 10.0)
	draw_polyline(ring_pts + PackedVector2Array([ring_pts[0]]), MINE_R, 1.5)
	# Smoke stack tube
	var stack_top := pos + Vector2(0.0, -HS - 12.0)
	var stack_bot := pos + Vector2(0.0, -HS + 2.0)
	draw_line(stack_bot + Vector2(-3.5,0), stack_top + Vector2(-3.5,0), Color(0.25,0.25,0.28), 1.0)
	draw_line(stack_bot + Vector2( 3.5,0), stack_top + Vector2( 3.5,0), Color(0.25,0.25,0.28), 1.0)
	draw_line(stack_bot, stack_top, Color(0.18,0.18,0.20), 5.0)
	# Smoke puffs — offset by per-hex phase so each mine looks independent
	var phase: float = mine_smoke_phase.get(hex, 0.0)
	for p in 3:
		var t: float = fmod(phase + float(p) * 0.33, 1.0)
		var puff_y: float = stack_top.y - t * 20.0
		var puff_r: float = 3.0 + t * 6.0
		var puff_a: float = (1.0 - t) * 0.55
		draw_circle(Vector2(stack_top.x + sin(t * TAU) * 2.5, puff_y),
			puff_r, Color(SMOKE.r, SMOKE.g, SMOKE.b, puff_a))
	# Center hazard dot
	draw_circle(pos, 4.5, MINE)
	draw_circle(pos, 2.5, MINE_R)
	if hovered_hex != Vector2i(-999, -999):
		var hover_pos := hex_to_pixel(hovered_hex.x, hovered_hex.y)
		var hover_pts := PackedVector2Array()
		for i in 6:
			var angle := deg_to_rad(60.0 * i - 30.0)
			hover_pts.append(hover_pos + Vector2(cos(angle), sin(angle)) * HEX_SIZE)
		draw_polyline(hover_pts + PackedVector2Array([hover_pts[0]]), Color.HOT_PINK, 3.0)

# ─── CRYSTAL MINE ─────────────────────────────────────────────────────────────
func _draw_crystal_mine(pos: Vector2, _hex: Vector2i, alpha: float = 1.0) -> void:
	const HS   := 20.0
	var DARK   := Color(0.06, 0.08, 0.14, alpha)
	var RIM    := Color(0.25, 0.65, 1.0,  alpha)
	var SHARD  := Color(0.2,  0.75, 1.0,  alpha * 0.9)
	var FACET  := Color(0.85, 0.95, 1.0,  alpha * 0.7)

	# Dark hex base
	var base_pts := PackedVector2Array()
	for i in 6:
		var a := deg_to_rad(60.0*float(i)-30.0)
		base_pts.append(pos + Vector2(cos(a),sin(a)) * HS)
	draw_colored_polygon(base_pts, DARK)
	draw_polyline(base_pts + PackedVector2Array([base_pts[0]]), RIM, 2.0)

	# Crystal shard — tall gem shape growing from center
	var s := HS * 0.75
	var shard_pts := PackedVector2Array([
		Vector2( 0.0,        -s        ),
		Vector2( s * 0.40,  -s * 0.20 ),
		Vector2( s * 0.28,   s * 0.55 ),
		Vector2( 0.0,        s * 0.40 ),
		Vector2(-s * 0.28,   s * 0.55 ),
		Vector2(-s * 0.40,  -s * 0.20 ),
	])
	for i in shard_pts.size():
		shard_pts[i] += pos
	draw_colored_polygon(shard_pts, SHARD)

	# Inner facet line
	draw_line(pos + Vector2(0, -s * 0.8), pos + Vector2(0, s * 0.3), FACET, 1.5)

	# Rim circle glow
	draw_arc(pos, HS * 0.45, 0.0, TAU, 16, Color(0.3, 0.8, 1.0, alpha * 0.5), 1.5)

# ─── GHOST PREVIEW ────────────────────────────────────────────────────────────
func _draw_ghost(pos: Vector2, type: String) -> void:
	var alpha: float  = 0.60 if _ghost_affordable else 0.28
	var outline_col   := Color(0.3, 1.0, 0.4, 0.9) if _ghost_affordable else Color(1.0, 0.2, 0.2, 0.8)

	# Hex outline showing valid placement
	var out_pts := PackedVector2Array()
	for i in 6:
		var a := deg_to_rad(60.0*float(i)-30.0)
		out_pts.append(pos + Vector2(cos(a),sin(a)) * HEX_SIZE)
	draw_polyline(out_pts + PackedVector2Array([out_pts[0]]), outline_col, 2.5)

	# Node preview — desaturate if not affordable
	match type:
		"turret":
			var dummy_hex := _ghost_hex
			if _ghost_affordable:
				_draw_turret_alpha(pos, dummy_hex, alpha)
			else:
				_draw_gray_hex(pos, alpha)
		"shield":
			if _ghost_affordable:
				_draw_shield_alpha(pos, alpha)
			else:
				_draw_gray_hex(pos, alpha)
		"mine":
			if _ghost_affordable:
				_draw_mine_alpha(pos, alpha)
			else:
				_draw_gray_hex(pos, alpha)
		"crystal_mine":
			if _ghost_affordable:
				_draw_crystal_mine(pos, _ghost_hex, alpha)
			else:
				_draw_gray_hex(pos, alpha)

	# Cost label above ghost
	var hud = get_parent().get_node_or_null("Hud")
	if hud != null:
		var cost_str := _get_cost_label(type, hud)
		var cost_col := Color(0.3, 1.0, 0.4) if _ghost_affordable else Color(1.0, 0.35, 0.35)
		draw_string(ThemeDB.fallback_font, pos + Vector2(-20, -HEX_SIZE - 6), cost_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, cost_col)

func _get_cost_label(type: String, hud: Node) -> String:
	if type == "crystal_mine":
		return str(CRYSTAL_MINE_GOLD_COST) + "g"
	return str(get_placement_cost()) + "💎"

func _draw_gray_hex(pos: Vector2, alpha: float) -> void:
	var pts := PackedVector2Array()
	for i in 6:
		var a := deg_to_rad(60.0*float(i)-30.0)
		pts.append(pos + Vector2(cos(a),sin(a)) * HEX_SIZE * 0.75)
	draw_colored_polygon(pts, Color(0.4, 0.4, 0.45, alpha))

func _draw_turret_alpha(pos: Vector2, hex: Vector2i, alpha: float) -> void:
	var STEEL       := Color(0.28, 0.30, 0.35, alpha)
	var STEEL_LIGHT := Color(0.42, 0.45, 0.52, alpha)
	var BARREL_COL  := Color(0.18, 0.20, 0.24, alpha)
	var MUZZLE      := Color(1.0,  0.75, 0.2,  alpha * 0.9)
	var base_pts := PackedVector2Array()
	for i in 6:
		var a := deg_to_rad(60.0*float(i)-30.0)
		base_pts.append(pos + Vector2(cos(a),sin(a)) * 20.0)
	draw_colored_polygon(base_pts, STEEL)
	var dome_pts := PackedVector2Array()
	for i in 8:
		var a := TAU * float(i) / 8.0
		dome_pts.append(pos + Vector2(cos(a),sin(a)) * 12.0)
	draw_colored_polygon(dome_pts, STEEL_LIGHT)
	draw_circle(pos, 5.5, STEEL_LIGHT)
	draw_circle(pos, 3.0, MUZZLE)

func _draw_shield_alpha(pos: Vector2, alpha: float) -> void:
	const HS := 22.0
	var SHIELD_BLUE  := Color(0.15, 0.55, 1.0, alpha * 0.85)
	var SHIELD_INNER := Color(0.4,  0.75, 1.0, alpha * 0.95)
	var base_pts := PackedVector2Array()
	for i in 6:
		var a := deg_to_rad(60.0*float(i)-30.0)
		base_pts.append(pos + Vector2(cos(a),sin(a)) * HS)
	draw_colored_polygon(base_pts, Color(0.05, 0.12, 0.28, alpha))
	draw_polyline(base_pts + PackedVector2Array([base_pts[0]]), SHIELD_BLUE, 2.5)
	draw_circle(pos, 7.0, SHIELD_BLUE)
	draw_circle(pos, 4.5, SHIELD_INNER)

func _draw_mine_alpha(pos: Vector2, alpha: float) -> void:
	const HS   := 18.0
	var MINE   := Color(0.12, 0.14, 0.18, alpha)
	var MINE_R := Color(0.8,  0.25, 0.1,  alpha * 0.9)
	var base_pts := PackedVector2Array()
	for i in 6:
		var a := deg_to_rad(60.0*float(i)-30.0)
		base_pts.append(pos + Vector2(cos(a),sin(a)) * HS)
	draw_colored_polygon(base_pts, MINE)
	draw_polyline(base_pts + PackedVector2Array([base_pts[0]]), MINE_R, 2.0)
	draw_circle(pos, 4.5, MINE)
	draw_circle(pos, 2.5, MINE_R)

func pixel_to_hex(pos: Vector2) -> Vector2i:
	var p = pos - map_center
	var q = int(round((sqrt(3.0) / 3.0 * p.x - 1.0 / 3.0 * p.y) / HEX_SIZE))
	var r = int(round((2.0 / 3.0 * p.y) / HEX_SIZE))
	return Vector2i(q, r)

func try_place_node(screen_pos: Vector2, type: String) -> bool:
	var hex = pixel_to_hex(screen_pos)
	var hud = get_parent().get_node("Hud")

	if type == "crystal_mine":
		# Crystal mines only go on crystal node hexes
		if not crystal_node_hexes.has(hex): return false
		if placed_nodes.has(hex): return false
		if hud.gold < CRYSTAL_MINE_GOLD_COST: return false
		hud.gold -= CRYSTAL_MINE_GOLD_COST
		hud.gold_label.text = "Gold: " + str(hud.gold)
		# Remove the crystal node marker visual
		_consume_crystal_node(hex)
		place_node(hex, type)
		return true

	var available = get_available_hexes()
	if hex not in available: return false
	var cost = get_placement_cost()
	if hud.node_fragments < cost: return false
	hud.add_node_fragment(-cost)
	place_node(hex, type)
	return true

func _consume_crystal_node(hex: Vector2i) -> void:
	# Hide and free the WorldSpawner crystal_node_marker at this hex
	for node in get_tree().get_nodes_in_group("crystal_node_marker"):
		if not is_instance_valid(node): continue
		if (node as Node2D).get_meta("hex_key", Vector2i(-999,-999)) == hex:
			node.queue_free()
			break
	crystal_node_hexes.erase(hex)

func register_crystal_node(hex: Vector2i) -> void:
	crystal_node_hexes[hex] = true


func _update_node_animations(delta: float) -> void:
	var needs_redraw := false
	for hex in placed_nodes.keys():
		var type: String = placed_nodes[hex]
		if type == "turret":
			# Rotate cannons — faster when enemy in range, slow idle otherwise
			var has_target := false
			for group in ["enemies","boss_enemy","enemy_towers"]:
				for e in get_tree().get_nodes_in_group(group):
					if not is_instance_valid(e): continue
					var tp := to_global(hex_to_pixel(hex.x, hex.y))
					if tp.distance_to((e as Node2D).global_position) < turret_range:
						has_target = true; break
				if has_target: break
			var rot_speed: float = 1.8 if has_target else 0.35
			turret_rotations[hex] = fmod(
				turret_rotations.get(hex, 0.0) + rot_speed * delta, TAU)
			needs_redraw = true
		elif type == "mine":
			mine_smoke_phase[hex] = fmod(
				mine_smoke_phase.get(hex, randf()) + 0.55 * delta, 1.0)
			needs_redraw = true
	if needs_redraw:
		queue_redraw()

# ─── INPUT ────────────────────────────────────────────────────────────────────
func _input(event: InputEvent) -> void:
	var hud = get_parent().get_node("Hud")
	if hud.selected_node_type == "":
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			var mouse_pos = get_global_mouse_position()
			if try_place_node(mouse_pos, hud.selected_node_type):
				hud.selected_node_type = ""
		if event.button_index == MOUSE_BUTTON_RIGHT:
			hud.selected_node_type = ""
			return

# ─── PROCESS ──────────────────────────────────────────────────────────────────
func _process(_delta: float) -> void:
	_update_node_animations(_delta)
	var hud = get_parent().get_node("Hud")

	# ── Ghost / hover state ───────────────────────────────────────────────────
	var sel: String = hud.selected_node_type
	if sel == "":
		_ghost_hex  = Vector2i(-999, -999)
		hovered_hex = Vector2i(-999, -999)
	else:
		var mouse_pos = get_global_mouse_position()
		var hex = pixel_to_hex(mouse_pos)

		if sel == "crystal_mine":
			_ghost_valid      = crystal_node_hexes.has(hex) and not placed_nodes.has(hex)
			_ghost_affordable = hud.gold >= CRYSTAL_MINE_GOLD_COST
		else:
			var available = get_available_hexes()
			_ghost_valid      = hex in available
			_ghost_affordable = hud.node_fragments >= get_placement_cost()

		_ghost_hex  = hex if _ghost_valid else Vector2i(-999, -999)
		hovered_hex = Vector2i(-999, -999)   # disable old pink outline
	queue_redraw()

	# ── Turret shooting ───────────────────────────────────────────────────────
	for hex in placed_nodes.keys():
		if placed_nodes[hex] != "turret":
			continue
		if not turret_timers.has(hex):
			turret_timers[hex] = 0.0
		turret_timers[hex] -= _delta
		if turret_timers[hex] <= 0.0:
			turret_timers[hex] = turret_fire_rate
			fire_turret(hex)

	# ── Gold Mine income ──────────────────────────────────────────────────────
	mine_income_timer -= _delta
	if mine_income_timer <= 0.0:
		mine_income_timer = mine_income_rate
		var mine_count := 0
		for hex in placed_nodes.keys():
			if placed_nodes[hex] == "mine":
				mine_count += 1
		if mine_count > 0:
			hud.gold += mine_count * mine_gold_per_tick
			hud.gold_label.text = "Gold: " + str(hud.gold)

	# ── Crystal Mine income ───────────────────────────────────────────────────
	crystal_mine_income_timer -= _delta
	if crystal_mine_income_timer <= 0.0:
		crystal_mine_income_timer = CRYSTAL_MINE_TICK_RATE
		var cm_count := 0
		for hex in placed_nodes.keys():
			if placed_nodes[hex] == "crystal_mine":
				cm_count += 1
		if cm_count > 0:
			hud.add_node_fragment(cm_count * CRYSTAL_MINE_CRYSTAL_RATE)

# ─── TURRET LOGIC ─────────────────────────────────────────────────────────────
func fire_turret(hex: Vector2i) -> void:
	var turret_pos := to_global(hex_to_pixel(hex.x, hex.y))
	var closest_enemy: Area2D = null
	var closest_dist := turret_range

	# Priority pass 1: enemies + boss — preferred targets
	for group in ["enemies", "boss_enemy"]:
		for enemy in get_tree().get_nodes_in_group(group):
			if not is_instance_valid(enemy):
				continue
			var dist := turret_pos.distance_to(enemy.global_position)
			if dist < closest_dist:
				closest_dist = dist
				closest_enemy = enemy

	# Priority pass 2: enemy towers — only if no enemies/boss in range
	if closest_enemy == null:
		for t in get_tree().get_nodes_in_group("enemy_towers"):
			if not is_instance_valid(t):
				continue
			var dist := turret_pos.distance_to(t.global_position)
			if dist < closest_dist:
				closest_dist = dist
				closest_enemy = t

	if closest_enemy == null:
		return
	if is_path_shielded(turret_pos, closest_enemy.global_position):
		return

	# ── Spawn visible projectile ──────────────────────────────────────────────
	var proj := Area2D.new()
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()

	# Big and slow at base — shrinks and speeds up as turret_range increases
	var size := clampf(18.0 - turret_range * 0.04, 5.0, 18.0)
	var speed := clampf(80.0 + turret_range * 0.6, 80.0, 400.0)

	circle.radius = size
	shape.shape = circle
	proj.add_child(shape)

	var poly := Polygon2D.new()
	var pts := PackedVector2Array()
	for i in 8:
		var a := deg_to_rad(45.0 * i)
		pts.append(Vector2(cos(a), sin(a)) * size)
	poly.polygon = pts
	poly.color = Color(1.0, 0.5, 0.1)  # orange
	proj.add_child(poly)
	proj.global_position = turret_pos
	get_parent().add_child(proj)

	var target := closest_enemy
	var dist_to_target := turret_pos.distance_to(target.global_position)
	var travel_time := dist_to_target / speed
	var tween := get_tree().create_tween()
	tween.tween_property(proj, "global_position", target.global_position, travel_time)
	tween.tween_callback(func():
		if is_instance_valid(target) and target.has_meta("hp"):
			var hp: float = target.get_meta("hp") - turret_damage
			target.set_meta("hp", hp)
			if target.has_meta("poly"):
				var p: Polygon2D = target.get_meta("poly")
				p.color = Color(1.0, hp / 3.0, hp / 3.0)
			if hp <= 0:
				var spawner = get_parent().get_node("EnemySpawner")
				spawner.handle_turret_kill(target)
		proj.queue_free()
	)

# ─── SHIELD BLOCKING ──────────────────────────────────────────────────────────
func is_hex_shielded(world_pos: Vector2) -> bool:
	var hex := pixel_to_hex(world_pos)
	return placed_nodes.has(hex) and placed_nodes[hex] == "shield"

func is_path_shielded(from: Vector2, to: Vector2) -> bool:
	var dist := from.distance_to(to)
	var steps := int(dist / HEX_SIZE) + 1
	for i in range(1, steps):
		var t := float(i) / float(steps)
		var sample := from.lerp(to, t)
		if is_hex_shielded(sample):
			return true
	return false

func can_enemy_enter(world_pos: Vector2) -> bool:
	return not is_hex_shielded(world_pos)

func get_shield_positions() -> Array[Vector2]:
	var positions: Array[Vector2] = []
	for hex in placed_nodes.keys():
		if placed_nodes[hex] == "shield":
			positions.append(hex_to_pixel(hex.x, hex.y))
	return positions
