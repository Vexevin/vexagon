extends Node2D

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
	
func _input(event: InputEvent) -> void:
	var hud = get_parent().get_node("Hud")
	if hud.selected_node_type == "":
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			var mouse_pos = get_global_mouse_position()
			if try_place_node(mouse_pos, hud.selected_node_type):
				hud.selected_node_type = ""
				hud.show_placement_panel()
