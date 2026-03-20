extends Node2D

var hovered_hex := Vector2i(-999, -999)
var turret_timers := {}
var turret_fire_rate := 1.5
var turret_range := 200.0

# Mine income
var mine_income_timer := 0.0
var mine_income_rate := 3.0
var mine_gold_per_tick := 10

const HEX_SIZE := 35.0
var map_center := Vector2.ZERO
var placed_nodes := {}
var node_costs := [10, 25, 65, 150, 300, 600, 777, 800, 900, 10000]

var HEX_NEIGHBORS := [
	Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 1),
	Vector2i(-1, 0), Vector2i(0, -1), Vector2i(1, -1)
]

func _ready() -> void:
	map_center = get_viewport_rect().size / 2.0

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

func _draw() -> void:
	for hex in placed_nodes.keys():
		var pos = hex_to_pixel(hex.x, hex.y)
		var type = placed_nodes[hex]
		var color = Color.RED
		if type == "shield":
			color = Color(0.2, 0.4, 1.0)
		elif type == "mine":
			color = Color.CYAN
		var points := PackedVector2Array()
		for i in 6:
			var angle := deg_to_rad(60.0 * i - 30.0)
			points.append(pos + Vector2(cos(angle), sin(angle)) * HEX_SIZE * 0.7)
		draw_colored_polygon(points, color)
	if hovered_hex != Vector2i(-999, -999):
		var pos = hex_to_pixel(hovered_hex.x, hovered_hex.y)
		var points := PackedVector2Array()
		for i in 6:
			var angle := deg_to_rad(60.0 * i - 30.0)
			points.append(pos + Vector2(cos(angle), sin(angle)) * HEX_SIZE)
		draw_polyline(points + PackedVector2Array([points[0]]), Color.HOT_PINK, 3.0)

func pixel_to_hex(pos: Vector2) -> Vector2i:
	var p = pos - map_center
	var q = int(round((sqrt(3.0) / 3.0 * p.x - 1.0 / 3.0 * p.y) / HEX_SIZE))
	var r = int(round((2.0 / 3.0 * p.y) / HEX_SIZE))
	return Vector2i(q, r)

func try_place_node(screen_pos: Vector2, type: String) -> bool:
	var hex = pixel_to_hex(screen_pos)
	var available = get_available_hexes()
	if hex not in available:
		return false
	var hud = get_parent().get_node("Hud")
	var cost = get_placement_cost()
	if hud.gold < cost:
		return false
	hud.gold -= cost
	hud.gold_label.text = "Gold: " + str(hud.gold)
	place_node(hex, type)
	return true

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
	var hud = get_parent().get_node("Hud")

	# Hover highlight
	if hud.selected_node_type == "":
		hovered_hex = Vector2i(-999, -999)
	else:
		var mouse_pos = get_global_mouse_position()
		var hex = pixel_to_hex(mouse_pos)
		var available = get_available_hexes()
		if hex in available:
			hovered_hex = hex
		else:
			hovered_hex = Vector2i(-999, -999)
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

	# ── Mine income ───────────────────────────────────────────────────────────
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

# ─── TURRET LOGIC ─────────────────────────────────────────────────────────────
func fire_turret(hex: Vector2i) -> void:
	var turret_pos := to_global(hex_to_pixel(hex.x, hex.y))
	var closest_enemy: Area2D = null
	var closest_dist := turret_range

	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy):
			continue
		var dist := turret_pos.distance_to(enemy.global_position)
		if dist < closest_dist:
			closest_dist = dist
			closest_enemy = enemy

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
			var hp: float = target.get_meta("hp") - 1.0
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
