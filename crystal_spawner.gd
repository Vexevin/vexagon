extends Node2D

const HEX_SIZE     := 35.0
const MAP_RADIUS   := 5
const CRYSTAL_COUNT := 6
var tower_pos := Vector2(3330.0, 2100.0)   # ← fixed: matches MAP_CENTER

func _ready() -> void:
	var valid_cells: Array[Vector2i] = []
	for q in range(-MAP_RADIUS, MAP_RADIUS + 1):
		for r in range(-MAP_RADIUS, MAP_RADIUS + 1):
			if abs(q + r) <= MAP_RADIUS:
				var dist: int = max(abs(q), abs(r), abs(q + r))
				if dist >= 2:
					valid_cells.append(Vector2i(q, r))

	valid_cells.shuffle()
	var count: int = min(CRYSTAL_COUNT, valid_cells.size())
	for i in range(count):
		var cell: Vector2i = valid_cells[i]
		spawn_crystal(hex_to_pixel(cell.x, cell.y))

func hex_to_pixel(q: int, r: int) -> Vector2:
	var x: float = HEX_SIZE * (sqrt(3.0) * q + sqrt(3.0) / 2.0 * r)
	var y: float = HEX_SIZE * (3.0 / 2.0 * r)
	return Vector2(x, y) + tower_pos

# ── Crystal spawner ────────────────────────────────────────────────────────────
func spawn_crystal(pos: Vector2) -> void:
	var crystal := Area2D.new()
	crystal.add_to_group("crystal")
	crystal.set_meta("hp", 4)

	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 14.0
	shape.shape = circle
	crystal.add_child(shape)

	# ── Multi-layer spike-ball stack: big→small, bottom→top ─────────────────
	# Each layer: [outer_radius, y_offset, Color(r,g,b,a)]
	var layer_defs: Array = [
		[14.0,  5.0, Color(0.50, 0.03, 0.80, 0.38)],   # bottom — largest, darkest
		[11.0,  1.0, Color(0.60, 0.08, 0.90, 0.48)],
		[ 8.0, -3.0, Color(0.70, 0.18, 0.98, 0.56)],
		[ 5.0, -7.0, Color(0.82, 0.38, 1.00, 0.64)],
		[ 3.0,-10.0, Color(0.94, 0.62, 1.00, 0.74)],   # top — smallest, brightest
	]

	const SPIKE_COUNT := 8          # 8-pointed star per layer
	const INNER_RATIO := 0.42       # inner radius = outer * this

	var polys_list: Array  = []
	var base_colors: Array = []

	for ld in layer_defs:
		var outer: float = ld[0]
		var y_off: float = ld[1]
		var col: Color   = ld[2]
		var inner: float = outer * INNER_RATIO

		var pts := PackedVector2Array()
		for k in SPIKE_COUNT * 2:
			# Start spike from top (-PI/2) so crystal points upward
			var a: float = deg_to_rad(360.0 / float(SPIKE_COUNT * 2) * float(k)) - PI / 2.0
			var r: float = outer if k % 2 == 0 else inner
			pts.append(Vector2(cos(a), sin(a)) * r + Vector2(0.0, y_off))

		var poly := Polygon2D.new()
		poly.polygon = pts
		poly.color   = col
		crystal.add_child(poly)
		polys_list.append(poly)
		base_colors.append(col)

	crystal.set_meta("polys",       polys_list)
	crystal.set_meta("base_colors", base_colors)
	crystal.position = pos
	crystal.area_entered.connect(func(area): on_hit(crystal, area))
	add_child(crystal)

# ── Bullet hit ────────────────────────────────────────────────────────────────
func on_hit(crystal: Area2D, area: Area2D) -> void:
	if not area.is_in_group("bullet"):
		return
	if not is_instance_valid(crystal):
		return
	area.queue_free()
	var hp: int = crystal.get_meta("hp") - 1
	crystal.set_meta("hp", hp)

	# Fade all layers proportionally — each retains its own base alpha
	var ratio: float = float(hp) / 4.0
	var polys: Array      = crystal.get_meta("polys")
	var base_colors: Array = crystal.get_meta("base_colors")
	for i in polys.size():
		if not is_instance_valid(polys[i]):
			continue
		var p: Polygon2D = polys[i] as Polygon2D
		var bc: Color    = base_colors[i]
		p.color = Color(bc.r, bc.g, bc.b, bc.a * ratio)

	if hp <= 0:
		get_parent().get_node("Hud").add_node_fragment(1)
		crystal.queue_free()
