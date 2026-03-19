extends Node2D

const HEX_SIZE := 35.0
const MAP_RADIUS := 5

var map_center := Vector2.ZERO

func _ready() -> void:
	map_center = get_viewport_rect().size / 2.0
	queue_redraw()

func _draw() -> void:
	for q in range(-MAP_RADIUS, MAP_RADIUS + 1):
		for r in range(-MAP_RADIUS, MAP_RADIUS + 1):
			if abs(q + r) <= MAP_RADIUS:
				var center := hex_to_pixel(q, r)
				draw_hex(center)

func hex_to_pixel(q: int, r: int) -> Vector2:
	var x := HEX_SIZE * (sqrt(3.0) * q + sqrt(3.0) / 2.0 * r)
	var y := HEX_SIZE * (3.0 / 2.0 * r)
	return Vector2(x, y) + map_center

func draw_hex(center: Vector2) -> void:
	var points := PackedVector2Array()
	for i in 6:
		var angle := deg_to_rad(60.0 * i - 30.0)
		points.append(center + Vector2(cos(angle), sin(angle)) * HEX_SIZE)
	draw_colored_polygon(points, Color(0.1, 0.4, 0.6, 0.8))
	draw_polyline(points + PackedVector2Array([points[0]]), Color.CYAN, 1.0)
