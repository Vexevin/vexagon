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

# ─── SKILL GETTERS ────────────────────────────────────────────────────────────

func get_fire_rate() -> float:
	var lvl = get_parent().get_node("Hud").skill_levels[0]
	var shots_per_sec := 1.0
	if lvl <= 3:
		shots_per_sec = 1.0 + lvl * 1.0
	elif lvl <= 6:
		shots_per_sec = 4.0 + (lvl - 3) * 2.0
	elif lvl <= 9:
		shots_per_sec = 10.0 + (lvl - 6) * 3.0
	elif lvl == 10:
		shots_per_sec = 19.0
	return 1.0 / shots_per_sec

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
		color = Color.BLUE_VIOLET
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

# ─── SETUP ────────────────────────────────────────────────────────────────────

@onready var polygon: Polygon2D = $Polygon2D

var fire_timer := 0.0
var firing := false

func _ready() -> void:
	polygon.polygon = PackedVector2Array([
		Vector2(0, -14),
		Vector2(10, 8),
		Vector2(-10, 8)
	])
	polygon.color = Color.YELLOW
	position = get_parent().MAP_CENTER

	# Camera2D — follows player, clamped to world bounds
	var cam := Camera2D.new()
	cam.position_smoothing_enabled = true
	cam.position_smoothing_speed = 6.0
	cam.limit_left   = -35
	cam.limit_top    = -35
	cam.limit_right  = 6695
	cam.limit_bottom = 4235
	add_child(cam)
	Engine.time_scale = 1.0

	var pickup_area := Area2D.new()
	pickup_area.add_to_group("player")
	var pickup_shape := CollisionShape2D.new()
	var pickup_circle := CircleShape2D.new()
	pickup_circle.radius = 20.0
	pickup_shape.shape = pickup_circle
	pickup_area.add_child(pickup_shape)
	add_child(pickup_area)

# ─── PROCESS ──────────────────────────────────────────────────────────────────

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
	if sim_lvl == 10:
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
				get_parent().get_node("Hud").update_wave_info(
					get_parent().get_node("EnemySpawner").wave_number,
					bullet_time_active, bullet_time_timer, bullet_time_recharge)
	apply_regen(delta)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			fire_timer = 0.0

# ─── SHOOT ────────────────────────────────────────────────────────────────────

func shoot() -> void:
	var shot_data = get_extra_shots()
	var shot_count = shot_data["count"]
	var bullet_color = shot_data["color"]
	var exp_radius := get_explosive_radius()
	var exp_lvl: int = get_parent().get_node("Hud").skill_levels[7]

	for _i in range(shot_count):
		var bullet := Area2D.new()
		bullet.add_to_group("bullet")

		var shape := CollisionShape2D.new()
		var circle := CircleShape2D.new()
		circle.radius = 5.0
		shape.shape = circle
		bullet.add_child(shape)

		var poly := Polygon2D.new()
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
		bullet.set_meta("explosive_radius", exp_radius)
		bullet.set_meta("explosive_lvl", exp_lvl)
		bullet.set_meta("split_level", get_split_level())
		bullet.set_meta("knockback", get_knockback())
		bullet.set_meta("size_level", get_parent().get_node("Hud").skill_levels[1] / 3)

		# Explosive bullets skip on_bullet_hit collision — detonation handles damage
		if exp_lvl > 0:
			bullet.set_meta("explosive_bullet", true)

		# ── Spread cone ───────────────────────────────────────────────────────
		var base_dir := (get_global_mouse_position() - global_position).normalized()
		var lvl_shots: int = get_parent().get_node("Hud").skill_levels[5]
		var max_half: float = maxf(8.0, 45.0 - float(lvl_shots) * 4.0)
		var spread_angle := randf_range(-max_half, max_half)
		var dir := base_dir.rotated(deg_to_rad(spread_angle))

		var bullet_range := get_range()
		var lvl2 = get_parent().get_node("Hud").skill_levels[2]

		# ── Firework explosive detonation ─────────────────────────────────────
		if exp_lvl > 0:
			var min_dist := 60.0
			var max_dist := 60.0 + float(exp_lvl) * 30.0
			var det_dist := randf_range(min_dist, max_dist)
			det_dist = minf(det_dist, bullet_range)
			var det_pos := global_position + dir * det_dist
			var det_time := det_dist / (get_proj_speed() * 60.0)
			var tween := get_tree().create_tween()
			tween.tween_property(bullet, "global_position", det_pos, det_time)
			tween.tween_callback(func():
				if not is_instance_valid(bullet):
					return
				var boom_pos := bullet.global_position
				var spawner = get_parent().get_node("EnemySpawner")
				var chain = exp_lvl == 10
				spawner.trigger_explosion(boom_pos, exp_radius, get_damage() / 2.0, chain)
				_spawn_fireworks(boom_pos, exp_lvl, bullet_color, exp_radius)
				bullet.queue_free()
			)
		else:
			var travel_time := bullet_range / (get_proj_speed() * 60.0)
			var tween := get_tree().create_tween()
			tween.tween_property(bullet, "global_position", global_position + dir * bullet_range, travel_time)
			if lvl2 == 10:
				get_tree().create_timer(10.0).timeout.connect(bullet.queue_free)
			else:
				tween.tween_callback(bullet.queue_free)

# ─── FIREWORKS ────────────────────────────────────────────────────────────────

func _spawn_fireworks(pos: Vector2, lvl: int, base_color: Color, radius: float) -> void:
	var spark_count := mini(6 + lvl, 16)
	var spark_dist := 120.0 + float(lvl) * 18.0
	var spark_duration := 0.35

	# ── Colored sparks ────────────────────────────────────────────────────────
	for i in spark_count:
		var spark := Node2D.new()
		var spark_poly := Polygon2D.new()
		var hue := randf()
		var spark_color := Color.from_hsv(hue, 1.0, 1.0, 1.0)
		var s := randf_range(2.5, 5.0)
		spark_poly.polygon = PackedVector2Array([
			Vector2(0, -s), Vector2(s * 0.5, 0),
			Vector2(0, s), Vector2(-s * 0.5, 0)
		])
		spark_poly.color = spark_color
		spark.add_child(spark_poly)
		spark.global_position = pos
		get_parent().add_child(spark)
		var base_angle := (TAU / float(spark_count)) * float(i)
		var jitter := randf_range(-0.3, 0.3)
		var spark_dir := Vector2(cos(base_angle + jitter), sin(base_angle + jitter))
		var target := pos + spark_dir * spark_dist
		var tween := get_tree().create_tween()
		tween.set_parallel(true)
		tween.tween_property(spark, "global_position", target, spark_duration)
		tween.tween_property(spark_poly, "color",
			Color(spark_color.r, spark_color.g, spark_color.b, 0.0), spark_duration)
		tween.set_parallel(false)
		tween.tween_callback(spark.queue_free)

	# ── 7 starburst flashes with matching colored glow shadows ────────────────
	var flash_spread := maxf(30.0, radius * 0.6)
	var spike_count := 8

	for _f in 7:
		var flash := Node2D.new()

		var flash_r := randf_range(2.0, 5.0)
		var fade_time := randf_range(0.1, 0.3)
		# Each flash + glow gets its own random vivid color
		var flash_hue := randf()
		var flash_color := Color.from_hsv(flash_hue, 0.6, 1.0, 1.0)
		var glow_color := Color.from_hsv(flash_hue, 1.0, 1.0, 0.2)

		# Small starburst
		var flash_poly := Polygon2D.new()
		var flash_pts := PackedVector2Array()
		for j in spike_count * 2:
			var a := deg_to_rad((360.0 / float(spike_count * 2)) * float(j))
			if j % 2 == 0:
				flash_pts.append(Vector2(cos(a), sin(a)) * flash_r)
			else:
				flash_pts.append(Vector2(cos(a), sin(a)) * flash_r * randf_range(2.0, 3.0))
		flash_poly.polygon = flash_pts
		flash_poly.color = flash_color
		flash.add_child(flash_poly)

		# Large glow shadow — same spike pattern, 3× size, random matching color
		var glow_poly := Polygon2D.new()
		var glow_pts := PackedVector2Array()
		var glow_r := flash_r * 3.0
		for k in spike_count * 2:
			var ga := deg_to_rad((360.0 / float(spike_count * 2)) * float(k))
			if k % 2 == 0:
				glow_pts.append(Vector2(cos(ga), sin(ga)) * glow_r)
			else:
				glow_pts.append(Vector2(cos(ga), sin(ga)) * glow_r * randf_range(2.0, 3.0))
		glow_poly.polygon = glow_pts
		glow_poly.color = glow_color
		flash.add_child(glow_poly)

		var offset := Vector2(
			randf_range(-flash_spread, flash_spread),
			randf_range(-flash_spread, flash_spread)
		)
		flash.global_position = pos + offset
		get_parent().add_child(flash)

		var ftween := get_tree().create_tween()
		ftween.set_parallel(true)
		ftween.tween_property(flash_poly, "color",
			Color(flash_color.r, flash_color.g, flash_color.b, 0.0), fade_time)
		ftween.tween_property(glow_poly, "color",
			Color(glow_color.r, glow_color.g, glow_color.b, 0.0), fade_time)
		ftween.set_parallel(false)
		ftween.tween_callback(flash.queue_free)

# ─── DAMAGE / REGEN ───────────────────────────────────────────────────────────

func take_damage(amount: float) -> void:
	if max_hp >= 99999.0:
		return
	current_hp -= amount
	get_parent().get_node("Hud").update_health(current_hp, max_hp)
	if current_hp <= 0:
		current_hp = 0
		Engine.time_scale = 1.0
		bullet_time_active = false
		get_parent().get_node("Hud").show_game_over()

func apply_regen(delta: float) -> void:
	if get_regen() > 0:
		regen_timer += delta
		if regen_timer >= 1.0:
			regen_timer = 0.0
			current_hp = min(current_hp + 1.0, get_max_hp())
			get_parent().get_node("Hud").update_health(current_hp, max_hp)
