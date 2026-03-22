extends Node2D

# ── Fortress of Solitude — tech-philanthropist castle ─────────────────────────
# 7-hex footprint (center + 6 neighbors).
# Gray stone foundation tiles with LED strips.
# Cutouts where player-placed towers sit.
# LED bridges connecting all 6 neighbor hexes into one compound structure.

const MAX_HEALTH := 100
var health := MAX_HEALTH
var invincible: bool = false
var level := 1

const HEX_SIZE   := 35.0
const LED_CYAN   := Color(0.0,  0.90, 1.0,  0.90)
const LED_DIM    := Color(0.0,  0.55, 0.75, 0.40)
const WALL_DARK  := Color(0.14, 0.15, 0.18, 1.0)
const WALL_MID   := Color(0.22, 0.24, 0.29, 1.0)
const WALL_LIGHT := Color(0.32, 0.34, 0.40, 1.0)
const STONE_BASE := Color(0.20, 0.21, 0.24, 1.0)   # gray foundation
const STONE_RIM  := Color(0.28, 0.30, 0.35, 1.0)   # lighter stone rim
const CUTOUT_COL := Color(0.12, 0.13, 0.16, 1.0)   # darker inset for tower slots
const ACCENT     := Color(0.08, 0.12, 0.20, 1.0)
const BRIDGE_COL := Color(0.18, 0.20, 0.26, 1.0)   # bridge stone
const BRIDGE_LED := Color(0.0,  0.70, 0.90, 0.70)  # bridge LED strip

# Axial neighbor directions (same order as node_manager)
const NB_DIRS := [
	Vector2i(1,0), Vector2i(0,1), Vector2i(-1,1),
	Vector2i(-1,0), Vector2i(0,-1), Vector2i(1,-1)
]

func _ready() -> void:
	position = Vector2(3330.0, 2100.0)
	z_index = 1
	queue_redraw()
	# ── Artifact magnet — catches player when carrying ─────────────────────
	var zone := Area2D.new()
	zone.monitoring = true
	zone.monitorable = false
	zone.collision_layer = 0      # zone doesn't need to be detected
	zone.collision_mask  = 0xFFFFFFFF  # detect everything
	zone.add_to_group("castle_zone")
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 110.0
	shape.shape = circle
	zone.add_child(shape)
	add_child(zone)
	zone.body_entered.connect(func(body: Node):
		if not (body is CharacterBody2D): return
		if not body.get("carrying_artifact"): return
		if body.has_method("_reveal_artifact"):
			body.call("_reveal_artifact")
			_play_receive_flash()
	)

func _play_receive_flash() -> void:
	var flash := Node2D.new()
	flash.z_index = 5;  flash.z_as_relative = false
	get_parent().add_child(flash)
	flash.global_position = global_position
	var fpts := PackedVector2Array()
	for i in 8:
		var a: float = TAU * float(i) / 8.0
		fpts.append(Vector2(cos(a), sin(a)) * 55.0)
	var fpoly := Polygon2D.new()
	fpoly.polygon = fpts;  fpoly.color = Color(0.0, 0.9, 1.0, 0.7)
	flash.add_child(fpoly)
	var tw := get_tree().create_tween()
	tw.set_parallel(true)
	tw.tween_property(flash, "scale", Vector2(2.2, 2.2), 0.35)
	tw.tween_property(fpoly, "color", Color(0.0, 0.9, 1.0, 0.0), 0.35)
	tw.set_parallel(false)
	tw.tween_callback(flash.queue_free)

func _hex_pts(cx: float, cy: float, r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 6:
		var a: float = deg_to_rad(60.0 * float(i) - 30.0)
		pts.append(Vector2(cx + cos(a) * r, cy + sin(a) * r))
	return pts

func _nb_local(nb: Vector2i) -> Vector2:
	return Vector2(
		HEX_SIZE * (sqrt(3.0) * float(nb.x) + sqrt(3.0)/2.0 * float(nb.y)),
		HEX_SIZE * 1.5 * float(nb.y)
	)

func _get_placed_hexes() -> Array:
	var nm = get_parent().get_node_or_null("NodeManager")
	if nm == null: return []
	return nm.placed_nodes.keys()

func _draw() -> void:
	var placed: Array = _get_placed_hexes()

	# ── 1. Gray stone foundation — all 7 hexes ───────────────────────────────
	# Center foundation (always drawn — castle always here)
	var center_pts := _hex_pts(0, 0, HEX_SIZE + 6.0)
	draw_colored_polygon(center_pts, STONE_BASE)
	draw_polyline(center_pts + PackedVector2Array([center_pts[0]]), STONE_RIM, 1.5)

	# Outer 6 foundation tiles
	for i in 6:
		var nb: Vector2i = NB_DIRS[i]
		var np: Vector2 = _nb_local(nb)
		var is_occupied: bool = placed.has(nb)

		if is_occupied:
			# Cutout: darker inset ring — shows the slot is taken by a tower
			var outer := _hex_pts(np.x, np.y, HEX_SIZE - 1.0)
			var inner := _hex_pts(np.x, np.y, HEX_SIZE - 8.0)
			draw_colored_polygon(outer, CUTOUT_COL)
			# Dashed LED border around cutout
			draw_polyline(outer + PackedVector2Array([outer[0]]), LED_DIM, 1.0)
			draw_polyline(inner + PackedVector2Array([inner[0]]), LED_DIM, 0.8)
		else:
			# Empty tower slot: stone foundation with LED rim
			var fpts := _hex_pts(np.x, np.y, HEX_SIZE - 1.0)
			draw_colored_polygon(fpts, STONE_BASE)
			draw_polyline(fpts + PackedVector2Array([fpts[0]]), STONE_RIM, 1.2)
			# Subtle inner ring marks it as a valid build spot
			var inner := _hex_pts(np.x, np.y, HEX_SIZE - 7.0)
			draw_polyline(inner + PackedVector2Array([inner[0]]), LED_DIM, 0.8)

	# ── 2. Bridges between adjacent neighbor hexes ───────────────────────────
	# Each adjacent pair in the ring gets a stone bridge with LED edge strips
	for i in 6:
		var a_dir: Vector2i = NB_DIRS[i]
		var b_dir: Vector2i = NB_DIRS[(i + 1) % 6]
		var ap: Vector2 = _nb_local(a_dir)
		var bp: Vector2 = _nb_local(b_dir)

		# Direction and perpendicular for the bridge rectangle
		var ab: Vector2 = (bp - ap).normalized()
		var perp: Vector2 = Vector2(-ab.y, ab.x)
		var hw: float = 6.5   # half-width of bridge

		# Inset bridge endpoints to not overdraw the hex bodies
		var inset: float = HEX_SIZE - 8.0
		var a_edge: Vector2 = ap + ab * inset
		var b_edge: Vector2 = bp - ab * inset

		# Bridge quad
		var bq := PackedVector2Array([
			a_edge + perp * hw,
			b_edge + perp * hw,
			b_edge - perp * hw,
			a_edge - perp * hw,
		])
		draw_colored_polygon(bq, BRIDGE_COL)
		# LED strip along both long edges
		draw_line(a_edge + perp * (hw - 1.5), b_edge + perp * (hw - 1.5), BRIDGE_LED, 1.2)
		draw_line(a_edge - perp * (hw - 1.5), b_edge - perp * (hw - 1.5), BRIDGE_LED, 1.2)

	# ── 3. Center fortress structure (on top of foundation) ───────────────────
	var base_r: float = HEX_SIZE + 4.0
	var base_pts := _hex_pts(0, 0, base_r)
	draw_colored_polygon(base_pts, WALL_DARK)

	# Wall concentric rings
	for layer in 3:
		var lr: float = base_r - 6.0 - float(layer) * 7.0
		if lr < 8.0: break
		var lpts := _hex_pts(0, 0, lr)
		var lcolor: Color = WALL_MID if layer == 0 else (WALL_LIGHT if layer == 1 else WALL_MID)
		draw_colored_polygon(lpts, lcolor)
		draw_polyline(lpts + PackedVector2Array([lpts[0]]), WALL_DARK, 1.5)

	# Inner keep
	var keep_r: float = 14.0
	var keep_pts := _hex_pts(0, 0, keep_r)
	draw_colored_polygon(keep_pts, WALL_DARK)
	var inner_pts := _hex_pts(0, 0, keep_r - 3.5)
	draw_colored_polygon(inner_pts, WALL_MID)

	# LED strips on outer wall rim
	for i in 6:
		var a0: float = deg_to_rad(60.0 * float(i) - 30.0)
		var a1: float = deg_to_rad(60.0 * float(i + 1) - 30.0)
		var v0 := Vector2(cos(a0), sin(a0)) * (base_r - 0.5)
		var v1 := Vector2(cos(a1), sin(a1)) * (base_r - 0.5)
		draw_line(v0, v1, LED_CYAN if i % 2 == 0 else LED_DIM, 2.2)
		draw_circle(v0, 2.0, LED_CYAN if i % 2 == 0 else LED_DIM)

	# LED strips on inner keep
	for i in 6:
		var a0: float = deg_to_rad(60.0 * float(i) - 30.0)
		var a1: float = deg_to_rad(60.0 * float(i + 1) - 30.0)
		var v0 := Vector2(cos(a0), sin(a0)) * (keep_r - 0.5)
		var v1 := Vector2(cos(a1), sin(a1)) * (keep_r - 0.5)
		draw_line(v0, v1, LED_CYAN if i % 2 == 1 else LED_DIM, 1.6)

	# Power core
	draw_circle(Vector2.ZERO, 6.5, WALL_DARK)
	draw_circle(Vector2.ZERO, 4.5, LED_CYAN)
	draw_circle(Vector2.ZERO, 2.2, Color(1.0, 1.0, 1.0, 0.95))

	# ── 4. Health bar ─────────────────────────────────────────────────────────
	var bar_w := 54.0;  var bar_h := 5.0
	var bx := -bar_w / 2.0;  var by := -(base_r + 14.0)
	draw_rect(Rect2(bx - 1.0, by - 1.0, bar_w + 2.0, bar_h + 2.0), WALL_DARK)
	draw_rect(Rect2(bx, by, bar_w, bar_h), Color(0.1, 0.06, 0.06))
	var ratio: float = float(health) / float(MAX_HEALTH)
	var fill_col := LED_CYAN if ratio > 0.5 else (Color(0.9,0.8,0.1) if ratio > 0.25 else Color(0.9,0.15,0.15))
	draw_rect(Rect2(bx, by, bar_w * ratio, bar_h), fill_col)
	if ratio > 0.02:
		draw_circle(Vector2(bx + bar_w * ratio, by + bar_h / 2.0), 2.5, fill_col)

func take_damage(amount: int) -> void:
	if invincible: return
	health -= amount
	health = max(health, 0)
	queue_redraw()
	if health <= 0:
		get_parent().get_node("Hud").show_game_over()

func level_up() -> void:
	level += 1
	queue_redraw()
