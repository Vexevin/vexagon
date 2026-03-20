extends Node2D

const MAX_HEALTH := 100
var health := MAX_HEALTH
var level := 1

func _ready() -> void:
	position = Vector2(3330.0, 2100.0)
	queue_redraw()

func _draw() -> void:
	# Tower base — hexagon
	var points := PackedVector2Array()
	for i in 6:
		var angle := deg_to_rad(60.0 * i - 30.0)
		var size := 18.0 + (level * 4.0)
		points.append(Vector2(cos(angle), sin(angle)) * size)
	draw_colored_polygon(points, Color(0.8, 0.3, 0.1))
	draw_polyline(points + PackedVector2Array([points[0]]), Color.ORANGE, 2.0)
	
	# Level indicator
	draw_circle(Vector2.ZERO, 6.0, Color.YELLOW)
	
	# Health bar above tower
	var bar_width := 40.0
	var bar_height := 6.0
	var bar_x := -bar_width / 2.0
	var bar_y := -36.0
	draw_rect(Rect2(bar_x, bar_y, bar_width, bar_height), Color(0.3, 0.0, 0.0))
	draw_rect(Rect2(bar_x, bar_y, bar_width * (float(health) / MAX_HEALTH), bar_height), Color.RED)

func take_damage(amount: int) -> void:
	health -= amount
	health = max(health, 0)
	queue_redraw()
	if health <= 0:
		get_parent().get_node("Hud").show_game_over()

func level_up() -> void:
	level += 1
	queue_redraw()
	print("Tower level: ", level)
