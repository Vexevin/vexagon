extends Node2D

const HEX_SIZE := 35.0
const MAP_RADIUS := 5
const CRYSTAL_COUNT := 6
var tower_pos := Vector2(576, 324)

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

func spawn_crystal(pos: Vector2) -> void:
	var crystal := Area2D.new()
	crystal.add_to_group("crystal")
	crystal.set_meta("hp", 4)
	
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 14.0
	shape.shape = circle
	crystal.add_child(shape)
	
	var poly := Polygon2D.new()
	var points := PackedVector2Array()
	for j in 6:
		var angle: float = deg_to_rad(60.0 * j)
		points.append(Vector2(cos(angle), sin(angle)) * 14.0)
	poly.polygon = points
	poly.color = Color(0.2, 0.9, 0.9, 0.9)
	crystal.add_child(poly)
	crystal.set_meta("poly", poly)
	crystal.position = pos
	crystal.area_entered.connect(func(area): on_hit(crystal, area))
	add_child(crystal)

func on_hit(crystal: Area2D, area: Area2D) -> void:
	if not area.is_in_group("bullet"):
		return
	if not is_instance_valid(crystal):
		return
	area.queue_free()
	var hp: int = crystal.get_meta("hp") - 1
	crystal.set_meta("hp", hp)
	var poly: Polygon2D = crystal.get_meta("poly")
	poly.color = Color(0.2, 0.9, 0.9, hp / 4.0)
	if hp <= 0:
		spawn_pickup(crystal.position)
		crystal.queue_free()

func spawn_pickup(pos: Vector2) -> void:
	var pickup := Area2D.new()
	pickup.add_to_group("pickup")
	
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 12.0
	shape.shape = circle
	pickup.add_child(shape)
	
	var poly := Polygon2D.new()
	poly.polygon = PackedVector2Array([
		Vector2(0, -10), Vector2(10, 5),
		Vector2(0, 2), Vector2(-10, 5)
	])
	poly.color = Color.YELLOW
	pickup.add_child(poly)
	pickup.position = pos
	pickup.area_entered.connect(func(area): on_pickup(pickup, area))
	get_parent().call_deferred("add_child", pickup)

func on_pickup(pickup: Area2D, area: Area2D) -> void:
	if not area.is_in_group("player"):
		return
	if not is_instance_valid(pickup):
		return
	var hud = get_parent().get_node("Hud")
	hud.add_node_fragment(1)
	pickup.queue_free()
