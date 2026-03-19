extends CharacterBody2D

const SPEED := 200.0
const BULLET_SPEED := 500.0
var max_hp := 10.0
var current_hp := 10.0
var hp_regen := 0.0
var regen_timer := 0.0
var bullet_time_active := false
var bullet_time_timer := 0.0
var bullet_time_recharge := 0.0

func get_fire_rate() -> float:
	var lvl = get_parent().get_node("Hud").skill_levels[0]
	var shots_per_sec := 1.0
	if lvl <= 3:
		shots_per_sec = 1.0 + lvl * 1.0
	elif lvl <= 6:
		shots_per_sec = 4.0 + (lvl - 3) * 2.0
	elif lvl <= 9:
		shots_per_sec = 10.0 + (lvl - 6) * 3.0
	return 1.0 / shots_per_sec

@onready var polygon: Polygon2D = $Polygon2D

var fire_timer := 0.0
var firing := false

func get_sim_speed() -> float:
	var lvl = get_parent().get_node("Hud").skill_levels[9]
	return 1.0 + lvl * 0.5

func get_damage() -> float:
	var lvl = get_parent().get_node("Hud").skill_levels[1]
	var dmg := 1.0
	if lvl <= 3:
		dmg = 1.0 + lvl * 0.5
	elif lvl <= 6:
		dmg = 2.5 + (lvl - 3) * 1.0
	elif lvl <= 9:
		dmg = 5.5 + (lvl - 6) * 2.0
	return dmg
	
func get_range() -> float:
	var lvl = get_parent().get_node("Hud").skill_levels[2]
	if lvl == 10:
		return 99999.0
	var hex_dist := 3.0
	if lvl <= 3:
		hex_dist = 3.0 + lvl * 0.5
	elif lvl <= 6:
		hex_dist = 4.5 + (lvl - 3) * 1.0
	elif lvl <= 9:
		hex_dist = 7.5 + (lvl - 6) * 2.0
	return hex_dist * 60.0
	
func get_knockback() -> Dictionary:
	var lvl = get_parent().get_node("Hud").skill_levels[4]
	var slow_pct := 0.0
	var duration := 0.0
	var push_dist := 0.0
	if lvl <= 4:
		slow_pct = 0.25 + lvl * 0.25
		duration = 0.25 + lvl * 0.25
	elif lvl <= 9:
		slow_pct = 1.0
		duration = 0.5
		push_dist = 0.5 * get_parent().get_node("Hud").skill_levels[1] * 60.0
	return {"slow": slow_pct, "duration": duration, "push": push_dist}

func get_extra_shots() -> Dictionary:
	var lvl = get_parent().get_node("Hud").skill_levels[5]
	var count := 1
	var color := Color.WHITE
	if lvl <= 3:
		count = 1 + lvl
	elif lvl <= 6:
		count = 1 + (lvl - 3)
		color = Color.GREEN
	elif lvl < 10:
		count = 1 + (lvl - 6)
		color = Color.RED
	elif lvl == 10:
		count = 6
		color = Color.WHITE
	return {"count": count, "color": color}
	
func get_split_level() -> int:
	return get_parent().get_node("Hud").skill_levels[6]
	
func get_explosive_radius() -> float:
	var lvl = get_parent().get_node("Hud").skill_levels[7]
	if lvl == 0:
		return 0.0
	elif lvl <= 3:
		return lvl * 0.1 * 60.0
	elif lvl <= 6:
		return 0.3 * 60.0
	elif lvl <= 9:
		return (0.3 + (lvl - 6) * 1.0) * 60.0
	return 0.0
	
func _ready() -> void:
	polygon.polygon = PackedVector2Array([
		Vector2(0, -14),
		Vector2(10, 8),
		Vector2(-10, 8)
	])
	polygon.color = Color.YELLOW
	position = Vector2(476, 324)
	
	var pickup_area := Area2D.new()
	pickup_area.add_to_group("player")
	var pickup_shape := CollisionShape2D.new()
	var pickup_circle := CircleShape2D.new()
	pickup_circle.radius = 20.0
	pickup_shape.shape = pickup_circle
	pickup_area.add_child(pickup_shape)
	add_child(pickup_area)

func _physics_process(delta: float) -> void:
	var mouse := get_global_mouse_position()
	max_hp = get_max_hp()
		

	var aim_dir := (mouse - global_position).normalized()
	rotation = aim_dir.angle() + PI / 2.0
	
	var forward := aim_dir
	var right := Vector2(-aim_dir.y, aim_dir.x)
	
	var direction := Vector2.ZERO
	if Input.is_key_pressed(KEY_W): direction += forward
	if Input.is_key_pressed(KEY_S): direction -= forward
	if Input.is_key_pressed(KEY_D): direction += right
	if Input.is_key_pressed(KEY_A): direction -= right
	
	velocity = direction.normalized() * SPEED
	move_and_slide()
	
	firing = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	if firing:
		fire_timer -= delta
		if fire_timer <= 0.0:
			fire_timer = get_fire_rate()
			shoot()
			var sim_lvl = get_parent().get_node("Hud").skill_levels[9]
	if bullet_time_recharge > 0:
		bullet_time_recharge -= delta
	if Input.is_key_pressed(KEY_SPACE) and not bullet_time_active and bullet_time_recharge <= 0:
		bullet_time_active = true
		bullet_time_timer = 10.0
		Engine.time_scale = 0.1
	if bullet_time_active:
		bullet_time_timer -= delta * 10.0
		if bullet_time_timer <= 0:
			bullet_time_active = false
			bullet_time_recharge = 15.0
			Engine.time_scale = 1.0
			apply_regen(delta)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			fire_timer = 0.0

func shoot() -> void:
	var shot_data = get_extra_shots()
	var _shot_count = shot_data["count"]
	var bullet_color = shot_data["color"]
	var bullet := Area2D.new()
	bullet.add_to_group("bullet")
	
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 5.0
	shape.shape = circle
	bullet.add_child(shape)
	
	var poly := Polygon2D.new()
	poly.polygon = PackedVector2Array([
		Vector2(0, -6), Vector2(3, 6), Vector2(-3, 6)
	])
	poly.color = bullet_color
	var sz = 1.0 + get_parent().get_node("Hud").skill_levels[1] / 3 * 0.5
	poly.polygon = PackedVector2Array([
	Vector2(0, -6 * sz), Vector2(3 * sz, 6 * sz), Vector2(-3 * sz, 6 * sz)
])
	bullet.global_position = global_position
	bullet.rotation = rotation
	bullet.add_child(poly)
	get_parent().add_child(bullet)
	bullet.set_meta("damage", get_damage())
	bullet.set_meta("explosive_radius", get_explosive_radius())
	bullet.set_meta("explosive_lvl", get_parent().get_node("Hud").skill_levels[7])
	bullet.set_meta("split_level", get_split_level())
	bullet.set_meta("knockback", get_knockback())
	bullet.set_meta("size_level", get_parent().get_node("Hud").skill_levels[1] / 3)
	var dir := (get_global_mouse_position() - global_position).normalized()
	var bullet_range := get_range()
	var travel_time := bullet_range / (get_proj_speed() * 60.0)
	var tween := get_tree().create_tween()
	tween.tween_property(bullet, "global_position", global_position + dir * bullet_range, travel_time)
	var lvl2 = get_parent().get_node("Hud").skill_levels[2]
	if lvl2 == 10:
		get_tree().create_timer(10.0).timeout.connect(bullet.queue_free)
	else:
		tween.tween_callback(bullet.queue_free)
	if get_parent().get_node("Hud").skill_levels[5] == 10:
		var back_dir = -dir
		var back_bullet := Area2D.new()
		back_bullet.add_to_group("bullet")
		back_bullet.set_meta("damage", get_damage())
		back_bullet.set_meta("knockback", get_knockback())
		var bs = CollisionShape2D.new()
		var bc = CircleShape2D.new()
		bc.radius = 5.0
		bs.shape = bc
		back_bullet.add_child(bs)
		var bp := Polygon2D.new()
		bp.color = Color.WHITE
		bp.polygon = PackedVector2Array([Vector2(0, -6), Vector2(3, 6), Vector2(-3, 6)])
		back_bullet.add_child(bp)
		back_bullet.global_position = global_position
		get_parent().add_child(back_bullet)
		var br := get_range()
		var bt := br / (get_proj_speed() * 60.0)
		var btween := get_tree().create_tween()
		btween.tween_property(back_bullet, "global_position", global_position + back_dir * br, bt)
		btween.tween_callback(back_bullet.queue_free)
		
func get_proj_speed() -> float:
	
	var lvl = get_parent().get_node("Hud").skill_levels[3]
	return 3.0 + lvl * 0.5
func get_max_hp() -> float:
	var lvl = get_parent().get_node("Hud").skill_levels[8]
	var hp := 10.0
	if lvl <= 3:
		hp = 10.0 + lvl * 5.0
	elif lvl <= 6:
		hp = 25.0 + (lvl - 3) * 10.0
	elif lvl <= 9:
		hp = 55.0 + (lvl - 6) * 10.0
	return hp

func get_regen() -> float:
	var lvl = get_parent().get_node("Hud").skill_levels[8]
	if lvl >= 7:
		return 1.0
	return 0.0
func take_damage(amount: float) -> void:
	current_hp -= amount
	if current_hp <= 0:
		current_hp = 0
		Engine.time_scale = 1.0
		bullet_time_active = false
		print("PLAYER DEAD")

func apply_regen(delta: float) -> void:
	if get_regen() > 0:
		regen_timer += delta
		if regen_timer >= 1.0:
			regen_timer = 0.0
			current_hp = min(current_hp + 1.0, get_max_hp())
