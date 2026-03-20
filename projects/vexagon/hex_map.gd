extends Node2D

const HEX_SIZE   := 35.0
const R_RANGE    := 40
const Q_RANGE    := 75
const MAP_CENTER := Vector2(3330.0, 2100.0)
const WORLD_W    := 6660.0
const WORLD_H    := 4200.0

func _ready() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)

	# SubViewport bakes the grid into a texture exactly once
	var sv := SubViewport.new()
	sv.size = Vector2i(int(WORLD_W), int(WORLD_H))
	sv.render_target_update_mode = SubViewport.UPDATE_ONCE
	sv.render_target_clear_mode  = SubViewport.CLEAR_MODE_ONCE
	sv.transparent_bg = false
	add_child(sv)
	sv.add_child(_GridDrawer.new())

	# Sprite hidden until texture is ready — no white flash
	var spr       := Sprite2D.new()
	spr.texture    = sv.get_texture()
	spr.position   = MAP_CENTER
	spr.centered   = true
	spr.z_index    = -100
	spr.z_as_relative = false
	spr.visible    = false          # ← hidden on frame 0
	add_child(spr)

	# Wait two frames for SubViewport to finish render, then show
	await get_tree().process_frame
	await get_tree().process_frame
	spr.visible = true
	sv.render_target_update_mode = SubViewport.UPDATE_DISABLED

func hex_to_pixel(q: int, r: int) -> Vector2:
	return Vector2(
		HEX_SIZE * (sqrt(3.0) * float(q) + sqrt(3.0) / 2.0 * float(r)),
		HEX_SIZE * 1.5 * float(r)
	) + MAP_CENTER

# ── Inner class draws the grid inside the SubViewport ─────────────────────────
class _GridDrawer extends Node2D:
	const S    = 35.0
	const Q    = 75
	const R    = 40
	const W    = 6660.0
	const H    = 4200.0
	const CX   = W / 2.0
	const CY   = H / 2.0
	const FILL = Color(0.10, 0.40, 0.60, 1.0)
	const EDGE = Color(0.00, 0.75, 0.95, 1.0)

	var _lines := PackedVector2Array()

	func _ready() -> void:
		for q in range(-Q, Q + 1):
			for r in range(-R, R + 1):
				var c := _p(q, r)
				if c.x < 0.0 or c.x > W or c.y < 0.0 or c.y > H:
					continue
				for i in 6:
					var a0 := deg_to_rad(60.0 * float(i)     - 30.0)
					var a1 := deg_to_rad(60.0 * float(i + 1) - 30.0)
					_lines.append(c + Vector2(cos(a0), sin(a0)) * S)
					_lines.append(c + Vector2(cos(a1), sin(a1)) * S)
		queue_redraw()

	func _draw() -> void:
		draw_rect(Rect2(0.0, 0.0, W, H), FILL)
		draw_multiline(_lines, EDGE, 1.0)

	func _p(q: int, r: int) -> Vector2:
		return Vector2(
			S * (sqrt(3.0)*float(q) + sqrt(3.0)/2.0*float(r)) + CX,
			S * 1.5 * float(r) + CY
		)
