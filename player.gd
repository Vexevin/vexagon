extends CharacterBody2D

const SPEED := 200.0
const BULLET_SPEED := 500.0
# Bullets converge at this distance before spreading — keeps aim tight at close range
const SPREAD_CONVERGENCE := 180.0   # ≈ 3 hexes
var max_hp := 10.0
var current_hp := 10.0
var _god_mode: bool = false
var hp_regen := 0.0
var regen_timer := 0.0
var bullet_time_active := false
var bullet_time_timer := 0.0
var bullet_time_recharge := 0.0
var _bt_layer:     CanvasLayer = null   # bullet time screen-space layer
var _bt_container: Node2D      = null   # modulate target inside layer

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

func get_heat_seeker_level() -> int:
	return get_parent().get_node("Hud").skill_levels[11]

func get_range() -> float:
	var lvl = get_parent().get_node("Hud").skill_levels[2]
	if lvl == 10:
		return 99999.0
	var hex_dist := 12.0   # base range — 12 hexes (~720px), usable on big map
	if lvl <= 3:
		hex_dist = 12.0 + lvl * 2.0    # 12 → 18 hexes
	elif lvl <= 6:
		hex_dist = 18.0 + (lvl - 3) * 3.0   # 18 → 27 hexes
	elif lvl <= 9:
		hex_dist = 27.0 + (lvl - 6) * 3.0   # 27 → 36 hexes
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
		return lvl * 0.05 * 60.0
	elif lvl <= 6:
		return 0.15 * 60.0
	elif lvl <= 9:
		return (0.15 + (lvl - 6) * 0.5) * 60.0
	else:   # lvl == 10
		return (0.15 + 2.0) * 60.0   # same as LV9 max — radius handled by child count

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
var _homing_bullets: Array = []
var _rmb_walk: bool = false
var _cam: Camera2D = null          # camera ref for zoom
var _nav_line: Line2D = null       # castle navigation line
var _nav_active: bool = false      # toggled by N key
var _nav_dot_offset: float = 0.0   # animation phase
var _zoom_level: float = 1.0       # current zoom (1.0 = default)
const ZOOM_MIN   := 0.25           # most zoomed out
const ZOOM_MAX   := 2.5            # most zoomed in
const ZOOM_STEP  := 0.08           # per scroll tick   # right-click walk mode active   # tracks live homing bullets for concurrent cap
var carrying_artifact: bool = false   # true while holding a treasure artifact
var artifact_count:    int  = 0        # total artifacts revealed at castle this run
var barrel_level:      int  = 1        # 1=single 2=double 3=triple
var shield_unlocked:   bool  = false
var _shield_hp:        float = 0.0
var _shield_max:       float = 0.0
var _shield_recharge:  float = 0.0
const SHIELD_REGEN_DELAY := 5.0
const SHIELD_REGEN_RATE  := 8.0
var _artifact_hex: Vector2i = Vector2i(-999, -999)  # which hex was picked up from

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
	_cam = cam
	# Start slightly zoomed out on 5K — players can adjust
	_zoom_level = 0.75
	cam.zoom = Vector2(_zoom_level, _zoom_level)
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
	if not _god_mode:
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

	# ── Right-click walk — hold RMB, steer with mouse, release to stop ───────
	_rmb_walk = Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	if _rmb_walk and direction == Vector2.ZERO:
		var rmb_target: Vector2 = get_global_mouse_position()
		var rmb_dist: float = global_position.distance_to(rmb_target)
		if rmb_dist > 8.0:
			direction = (rmb_target - global_position).normalized()

	var speed_mult: float = get_meta("speed_mult") if has_meta("speed_mult") else 1.0
	# FURY — speed burst after kill (timer set by enemy_spawner)
	if has_meta("fury_timer"):
		var ft: float = get_meta("fury_timer") - get_physics_process_delta_time()
		if ft > 0:
			speed_mult *= 1.5
			set_meta("fury_timer", ft)
		else:
			remove_meta("fury_timer")
	# Berserker: extra speed below 50% HP
	if has_meta("berserker_active") and current_hp < max_hp * 0.5:
		speed_mult *= 1.5
	# During bullet time the engine delta shrinks with time_scale —
	# compensate so the player moves at full real-time speed
	var ts: float = Engine.time_scale if Engine.time_scale > 0.0 else 1.0
	velocity = direction.normalized() * SPEED * speed_mult / ts
	move_and_slide()
	_update_nav_line(get_physics_process_delta_time())
	# ── Cracked hex — break into pit on step ─────────────────────────────────
	var hex_map = get_parent().get_node_or_null("HexMap")
	if hex_map != null and hex_map.has_method("crack_hex"):
		hex_map.crack_hex(global_position)

	# ── Treasure node pickup — proximity to any node in group ───────────────
	if not carrying_artifact:
		_check_treasure_pickup(hex_map)

	if hex_map != null:
		var cur_hex: Vector2i = hex_map.pixel_to_hex(global_position)
		# Castle reveal handled by tower.gd Area2D magnet — nothing to poll here
		# ── Pit fall — drop artifact on pit step ─────────────────────────────
		if carrying_artifact:
			if hex_map.get_hex_type(cur_hex.x, cur_hex.y) == hex_map.HexType.PIT:
				_drop_artifact_on_pit(hex_map)



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
			_spawn_bullet_time_overlay()
		if bullet_time_active:
			bullet_time_timer -= delta * 10.0
			if bullet_time_timer <= 0:
				bullet_time_active = false
				bullet_time_recharge = 15.0
				Engine.time_scale = 1.0
				_teardown_bullet_time_overlay()
				get_parent().get_node("Hud").update_wave_info(
					get_parent().get_node("EnemySpawner").wave_number,
					bullet_time_active, bullet_time_timer, bullet_time_recharge)
	apply_regen(delta)
	if shield_unlocked and _shield_hp < _shield_max:
		if _shield_recharge > 0.0:
			_shield_recharge -= delta
		else:
			_shield_hp = minf(_shield_hp + SHIELD_REGEN_RATE * delta, _shield_max)
			_update_shield_hud()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			fire_timer = 0.0
		# ── Mouse scroll — zoom ────────────────────────────────────────────────
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_set_zoom(_zoom_level + ZOOM_STEP)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_set_zoom(_zoom_level - ZOOM_STEP)
	# ── Middle mouse / Z key — reset zoom to default ─────────────────────────
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_Z:
			_set_zoom(0.75)
		if event.keycode == KEY_N:
			_nav_active = not _nav_active
			if not _nav_active and _nav_line != null:
				_nav_line.visible = false

# ─── SHOOT ────────────────────────────────────────────────────────────────────

func _all_skills_maxed() -> bool:
	# Checks only the original 11 skills (0-10) — Heat Seeker is its own bonus
	var levels = get_parent().get_node("Hud").skill_levels
	for i in range(mini(11, levels.size())):
		if levels[i] < 10:
			return false
	return true

func shoot() -> void:
	var shot_data = get_extra_shots()
	var shot_count = shot_data["count"]
	var bullet_color = shot_data["color"]
	var exp_radius := get_explosive_radius()
	var exp_lvl: int = get_parent().get_node("Hud").skill_levels[7]

	# ── Rainbow mode — all 11 skills at LV10 ─────────────────────────────────
	if _all_skills_maxed():
		bullet_color = Color.from_hsv(fmod(Time.get_ticks_msec() / 800.0, 1.0), 1.0, 1.0)

	for _i in range(shot_count):
		# ── Barrel loop — each shot fires barrel_level parallel bullets ───────
		const BARREL_GAP := 11.0   # pixels between parallel barrels
		var base_dir := (get_global_mouse_position() - global_position).normalized()
		var right_dir := Vector2(-base_dir.y, base_dir.x)  # perpendicular to aim
		var lvl_shots: int = get_parent().get_node("Hud").skill_levels[5]
		var max_half: float = maxf(8.0, 45.0 - float(lvl_shots) * 4.0)
		var spread_angle := randf_range(-max_half, max_half)
		var dir := base_dir.rotated(deg_to_rad(spread_angle))
		var bullet_range := get_range()
		var lvl2 = get_parent().get_node("Hud").skill_levels[2]

		for bi in barrel_level:
			# Lateral offset: center barrels around aim line
			var b_offset: Vector2 = right_dir * (float(bi) - float(barrel_level - 1) / 2.0) * BARREL_GAP
			var b_spawn: Vector2 = global_position + b_offset

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
			bullet.global_position = b_spawn
			bullet.rotation = rotation
			bullet.add_child(poly)
			get_parent().add_child(bullet)
			bullet.set_meta("damage", get_damage())
			bullet.set_meta("explosive_radius", exp_radius)
			bullet.set_meta("explosive_lvl", exp_lvl)
			bullet.set_meta("split_level", get_split_level())
			bullet.set_meta("knockback", get_knockback())
			bullet.set_meta("size_level", get_parent().get_node("Hud").skill_levels[1] / 3)

			# Explosive bullets skip on_bullet_hit collision
			if exp_lvl > 0:
				bullet.set_meta("explosive_bullet", true)

			# ── Route: Heat Seeker > Explosive > Normal ──────────────────────────
			var hs_lvl: int = get_heat_seeker_level()
			if hs_lvl > 0:
				# Homing bullet (carries explosive data if Explode also active)
				var hud_ref = get_parent().get_node("Hud")
				var max_homing: int = hud_ref.max_homing_bullets if "max_homing_bullets" in hud_ref else 25
				var live_count: int = 0
				for hb_check in _homing_bullets:
					if is_instance_valid(hb_check): live_count += 1
				if live_count >= max_homing:
					bullet.queue_free()
					continue
				bullet.queue_free()
				var hb := Area2D.new()
				hb.set_script(load("res://homing_bullet.gd"))
				hb.homing_level	  = hs_lvl
				hb.bullet_speed	  = maxf(280.0, get_proj_speed() * 60.0)
				hb.bullet_range	  = bullet_range
				hb.bullet_damage	 = get_damage()
				hb.initial_dir	   = dir
				hb.explosive_radius  = exp_radius
				hb.explosive_lvl	 = exp_lvl
				hb.bullet_color	  = bullet_color
				var hshape := CollisionShape2D.new()
				var hcircle := CircleShape2D.new();  hcircle.radius = 5.0;  hshape.shape = hcircle
				hb.add_child(hshape)
				var hpoly := Polygon2D.new()
				var sz2 = 1.0 + get_parent().get_node("Hud").skill_levels[1] / 3 * 0.5
				hpoly.color   = bullet_color
				hpoly.polygon = PackedVector2Array([Vector2(0,-6*sz2),Vector2(3*sz2,6*sz2),Vector2(-3*sz2,6*sz2)])
				hb.add_child(hpoly)
				hb.global_position = b_spawn
				hb.rotation		= dir.angle() + PI / 2.0
				get_parent().add_child(hb)
				_homing_bullets.append(hb)

			elif exp_lvl > 0:
				# Explosive tween bullet
				var min_dist := 180.0
				var max_dist := 180.0 + float(exp_lvl) * 80.0
				var det_dist := randf_range(min_dist, max_dist)
				det_dist = minf(det_dist, bullet_range)
				var conv := minf(SPREAD_CONVERGENCE, det_dist)
				var det_pos := b_spawn + base_dir * conv + dir * (det_dist - conv)
				var det_time := det_dist / (get_proj_speed() * 60.0)
				var tween := get_tree().create_tween()
				tween.tween_property(bullet, "global_position", det_pos, det_time)
				tween.tween_callback(func():
					if not is_instance_valid(bullet): return
					var boom_pos := bullet.global_position
					var spawner = get_parent().get_node("EnemySpawner")
					var chain = exp_lvl == 10
					spawner.trigger_explosion(boom_pos, exp_radius, get_damage() / 2.0, chain)
					_spawn_fireworks(boom_pos, exp_lvl, bullet_color, exp_radius)
					bullet.queue_free()
				)

			else:
				# Normal tween bullet
				var travel_time := bullet_range / (get_proj_speed() * 60.0)
				var tween := get_tree().create_tween()
				var bullet_target := b_spawn + base_dir * SPREAD_CONVERGENCE + dir * (bullet_range - SPREAD_CONVERGENCE)
				tween.tween_property(bullet, "global_position", bullet_target, travel_time)
				if lvl2 == 10:
					get_tree().create_timer(10.0).timeout.connect(bullet.queue_free)
				else:
					tween.tween_callback(bullet.queue_free)



# ─── FIREWORKS ────────────────────────────────────────────────────────────────

func _spawn_fireworks(pos: Vector2, lvl: int, _base_color: Color, radius: float) -> void:
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

	for _f in 3:
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
	if _god_mode:
		return
	# Shield absorbs first
	if shield_unlocked and _shield_hp > 0.0:
		_shield_recharge = SHIELD_REGEN_DELAY
		if amount <= _shield_hp:
			_shield_hp -= amount
			_update_shield_hud()
			return
		else:
			amount -= _shield_hp
			_shield_hp = 0.0
			_update_shield_hud()
	var resist: float = get_meta("damage_resist") if has_meta("damage_resist") else 0.0
	var final_dmg: float = amount * (1.0 - resist)
	# Fury burst on taking damage — tracked separately
	current_hp -= final_dmg
	get_parent().get_node("Hud").update_health(current_hp, max_hp)
	if current_hp <= 0:
		current_hp = 0
		Engine.time_scale = 1.0
		bullet_time_active = false
		_teardown_bullet_time_overlay()
		get_parent().get_node("Hud").show_game_over()

func apply_regen(delta: float) -> void:
	if get_regen() > 0:
		regen_timer += delta
		if regen_timer >= 1.0:
			regen_timer = 0.0
			current_hp = min(current_hp + 1.0, get_max_hp())
			get_parent().get_node("Hud").update_health(current_hp, max_hp)

# ─── Camera Zoom ──────────────────────────────────────────────────────────────
func _set_zoom(target: float) -> void:
	_zoom_level = clampf(target, ZOOM_MIN, ZOOM_MAX)
	if _cam == null: return
	var tw := get_tree().create_tween()
	tw.tween_property(_cam, "zoom",
		Vector2(_zoom_level, _zoom_level), 0.12)

func get_zoom() -> float:
	return _zoom_level


func _update_nav_line(delta: float) -> void:
	var show := _nav_active or carrying_artifact
	# Lazy create
	if _nav_line == null:
		_nav_line = Line2D.new()
		_nav_line.width = 3.0
		_nav_line.z_index = 12;  _nav_line.z_as_relative = false
		_nav_line.default_color = Color(0.0, 0.85, 1.0, 0.75)
		get_parent().add_child(_nav_line)
	if not show:
		_nav_line.visible = false;  return
	_nav_line.visible = true
	var castle_pos: Vector2 = get_parent().MAP_CENTER
	var dist: float = global_position.distance_to(castle_pos)
	# Color: amber when carrying, cyan when just navigating
	var line_col: Color = Color(1.0, 0.75, 0.1, 0.80) if carrying_artifact else Color(0.0, 0.85, 1.0, 0.65)
	_nav_line.default_color = line_col
	# Animated dashes — rebuild point array each frame
	_nav_dot_offset = fmod(_nav_dot_offset + delta * 80.0, 20.0)
	var dir_vec: Vector2 = (castle_pos - global_position).normalized()
	var pts := PackedVector2Array()
	var step: float = 20.0
	var dash: float = 10.0
	var travelled: float = _nav_dot_offset
	var drawing := true
	while travelled < dist - 28.0:
		var p: Vector2 = global_position + dir_vec * travelled
		if drawing:
			pts.append(p)
			var p2: Vector2 = global_position + dir_vec * minf(travelled + dash, dist - 28.0)
			pts.append(p2)
			pts.append(p2)  # degenerate segment = gap
		travelled += step
		drawing = not drawing
	_nav_line.points = pts


func _update_shield_hud() -> void:
	var hud = get_parent().get_node_or_null("Hud")
	if hud != null and hud.has_method("update_shield"):
		hud.update_shield(_shield_hp, _shield_max)


# ─── Bullet Time Overlay — expanding rings + star streaks ────────────────────
func _spawn_bullet_time_overlay() -> void:
	_teardown_bullet_time_overlay()
	# CanvasLayer = screen-space, always on top of world geometry
	_bt_layer = CanvasLayer.new()
	_bt_layer.layer = 100
	get_tree().current_scene.add_child(_bt_layer)
	_bt_container = Node2D.new()
	_bt_container.modulate.a = 0.0
	_bt_layer.add_child(_bt_container)

	var vp_size: Vector2 = get_viewport_rect().size
	var center:  Vector2 = vp_size / 2.0
	const PORTHOLE_R := 230.0   # clear circle — player is visible inside here
	const OUTER_R    := 3000.0  # large enough to cover any corner at any res
	const N_SECTORS  := 20      # color wheel slices
	const STEPS      := 12      # arc smoothness per slice

	# ── Spinning color wheel — covers screen outside porthole ─────────────────
	var wheel := Node2D.new()
	wheel.position = center
	_bt_container.add_child(wheel)
	for si in N_SECTORS:
		var hue: float    = float(si) / float(N_SECTORS)
		var a_start: float = TAU * float(si)      / float(N_SECTORS)
		var a_end:   float = TAU * float(si + 1) / float(N_SECTORS)
		var pts := PackedVector2Array()
		# Outer arc (screen edge)
		for ai in STEPS + 1:
			var a: float = lerp(a_start, a_end, float(ai) / float(STEPS))
			pts.append(Vector2(cos(a), sin(a)) * OUTER_R)
		# Inner arc reversed (porthole edge — creates the clear center hole)
		for ai in STEPS + 1:
			var a: float = lerp(a_end, a_start, float(ai) / float(STEPS))
			pts.append(Vector2(cos(a), sin(a)) * PORTHOLE_R)
		var sp := Polygon2D.new()
		sp.polygon = pts
		# Alternating sat/val for a rich color wheel that reads at a glance
		var sat: float = 0.95 if si % 2 == 0 else 0.70
		var val: float = 0.80 if si % 2 == 0 else 0.65
		sp.color = Color.from_hsv(hue, sat, val, 0.82)
		wheel.add_child(sp)
	# Continuous spin — one full rotation every 4s
	var spin := get_tree().create_tween().set_loops()
	spin.tween_property(wheel, "rotation", TAU, 4.0)

	# ── Soft glow ring at porthole edge ──────────────────────────────────────
	var gpts := PackedVector2Array()
	for i in 48:
		var a: float = TAU * float(i) / 48.0
		gpts.append(center + Vector2(cos(a), sin(a)) * PORTHOLE_R)
	for i in 48:
		var a: float = TAU * float(47 - i) / 48.0
		gpts.append(center + Vector2(cos(a), sin(a)) * (PORTHOLE_R + 38.0))
	var glow := Polygon2D.new()
	glow.polygon = gpts
	glow.color = Color(1.0, 1.0, 1.0, 0.30)
	_bt_container.add_child(glow)

	# ── Hyperspace streaks — outward from porthole, bright snowstorm feel ─────
	var _emit: Callable
	_emit = func():
		if not is_instance_valid(_bt_layer): return
		for _si in randi_range(5, 10):
			var streak := Line2D.new()
			# Spawn just outside porthole edge, spread over the whole screen
			var ang:  float   = randf() * TAU
			var dist: float   = randf_range(PORTHOLE_R + 15.0,
										minf(vp_size.x, vp_size.y) * 0.72)
			var spos: Vector2 = center + Vector2(cos(ang), sin(ang)) * dist
			var mdir: Vector2 = Vector2(cos(ang), sin(ang))
			var slen: float   = randf_range(8.0, 58.0)
			streak.add_point(Vector2.ZERO)
			streak.add_point(mdir * slen)
			streak.position       = spos
			streak.width          = randf_range(0.7, 2.6)
			# Mostly white/near-white with rare color tints
			var c: Color
			if randf() < 0.65:
				c = Color(randf_range(0.85, 1.0), randf_range(0.85, 1.0), randf_range(0.85, 1.0), 0.94)
			else:
				c = Color.from_hsv(randf(), randf_range(0.3, 0.7), 1.0, 0.90)
			streak.default_color = c
			_bt_container.add_child(streak)
			var fly: float = randf_range(80.0, 320.0)
			var dur: float = randf_range(0.06, 0.20)
			var stw := get_tree().create_tween()
			stw.set_parallel(true)
			stw.tween_property(streak, "position", spos + mdir * fly, dur)
			stw.tween_property(streak, "default_color",
				Color(c.r, c.g, c.b, 0.0), dur)
			stw.set_parallel(false)
			stw.tween_callback(streak.queue_free)
		get_tree().create_timer(0.055).timeout.connect(_emit)
	get_tree().create_timer(0.02).timeout.connect(_emit)

	# Fade the whole overlay in
	var tw_in := get_tree().create_tween()
	tw_in.tween_property(_bt_container, "modulate:a", 1.0, 0.45)

func _teardown_bullet_time_overlay() -> void:
	if _bt_layer == null or not is_instance_valid(_bt_layer): return
	var layer_ref: CanvasLayer = _bt_layer
	var cont_ref:  Node2D      = _bt_container
	_bt_layer = null;  _bt_container = null
	if cont_ref == null or not is_instance_valid(cont_ref):
		layer_ref.queue_free();  return
	var tw := get_tree().create_tween()
	tw.tween_property(cont_ref, "modulate:a", 0.0, 0.55)
	tw.tween_callback(layer_ref.queue_free)

# ─── Artifact carry system ────────────────────────────────────────────────────
func _check_treasure_pickup(hex_map: Node) -> void:
	# Check if player is close enough to any treasure node
	for node in get_tree().get_nodes_in_group("treasure_node"):
		if not is_instance_valid(node): continue
		var dist: float = global_position.distance_to((node as Node2D).global_position)
		if dist < 40.0:
			var hkey: Vector2i = (node as Node).get_meta("hex_key")
			_pick_up_artifact(hkey, node as Node2D)
			break

func _pick_up_artifact(hex_key: Vector2i, node: Node2D) -> void:
	carrying_artifact = true
	_artifact_hex = hex_key
	# Detach node visually — quick scale-up then vanish
	var tw := get_tree().create_tween()
	tw.set_parallel(true)
	tw.tween_property(node, "scale", Vector2(2.0, 2.0), 0.18)
	tw.tween_property(node, "modulate:a", 0.0, 0.18)
	tw.set_parallel(false)
	tw.tween_callback(func():
		var hex_map = get_parent().get_node_or_null("HexMap")
		if hex_map != null and hex_map.has_method("remove_treasure_node"):
			hex_map.remove_treasure_node(_artifact_hex)
	)
	# HUD notify
	var hud = get_parent().get_node_or_null("Hud")
	if hud != null and hud.has_method("show_artifact_carrying"):
		hud.show_artifact_carrying(true)
	_nav_active = true   # auto-show nav when carrying

func _reveal_artifact() -> void:
	carrying_artifact = false
	artifact_count += 1
	_nav_active = false
	if _nav_line != null: _nav_line.visible = false
	# Roll loot table
	var rolls := [35, 25, 18, 8, 4, 5, 5]   # weights matching order below
	var total_w: int = 0
	for w in rolls: total_w += w
	var pick: int = randi() % total_w
	var acc: int = 0
	var reward_idx: int = 0
	for i in rolls.size():
		acc += rolls[i]
		if pick < acc:
			reward_idx = i;  break
	# Apply reward
	var hud = get_parent().get_node_or_null("Hud")
	var reward_gold: int    = ([5, 10, 25, 50, 100, 0, 0] as Array)[reward_idx]
	var reward_type: int    = ([0,  0,  0,  0,   0, 1, 2] as Array)[reward_idx]
	var reward_name: String = ["5 Gold","10 Gold","25 Gold","50 Gold","100 Gold",
						"Free Skill Upgrade","Free Tower Upgrade"][reward_idx]
	if reward_gold > 0 and hud != null:
		hud.add_gold(reward_gold)
	if reward_type == 1 and hud != null:
		# Free skill point
		hud.skill_points += 1
		hud.call_deferred("refresh_panel")
	if reward_type == 2 and hud != null:
		# Free tower upgrade point
		hud.add_gold(50)   # fallback gold until tower upgrade currency exists
	# Tell HUD
	if hud != null and hud.has_method("show_artifact_reveal"):
		hud.show_artifact_reveal(reward_name, artifact_count)
	# Check milestones
	_check_artifact_milestones()

func _drop_artifact_on_pit(hex_map: Node) -> void:
	# Player fell into a pit while carrying — artifact respawns randomly on map
	carrying_artifact = false
	var hud = get_parent().get_node_or_null("Hud")
	if hud != null and hud.has_method("show_artifact_carrying"):
		hud.show_artifact_carrying(false)
	# Visual pop at drop point
	_spawn_artifact_drop_burst()
	# Find a random valid hex far from castle (min 10 hexes)
	var candidates: Array = []
	for q in range(-60, 61):
		for r in range(-35, 36):
			if maxi(abs(q), maxi(abs(r), abs(q+r))) < 10: continue
			if hex_map.get_hex_type(q, r) != 0: continue  # 0 = NORMAL
			candidates.append(Vector2i(q, r))
	candidates.shuffle()
	if candidates.size() == 0: return
	var respawn_hex: Vector2i = candidates[0]
	var respawn_pos: Vector2 = hex_map.hex_to_pixel(respawn_hex.x, respawn_hex.y)
	# Spawn a new glowing dropped artifact marker at that position
	_spawn_dropped_artifact_marker(respawn_hex, respawn_pos, hex_map)
	# Notify HUD
	if hud != null and hud.has_method("show_artifact_dropped"):
		hud.show_artifact_dropped()

func _spawn_artifact_drop_burst() -> void:
	# Small burst of sparks at the pit position — visual feedback for the loss
	for i in 8:
		var angle: float = TAU * float(i) / 8.0
		var spark := Node2D.new()
		spark.global_position = global_position
		spark.z_index = 10;  spark.z_as_relative = false
		var spts := PackedVector2Array()
		spts.append(Vector2.ZERO)
		spts.append(Vector2(cos(angle), sin(angle)) * 14.0)
		var sline := Line2D.new()
		sline.points = spts;  sline.width = 2.0
		sline.default_color = Color(0.95, 0.75, 0.1, 0.9)
		spark.add_child(sline)
		get_parent().add_child(spark)
		var tw := get_tree().create_tween()
		tw.set_parallel(true)
		tw.tween_property(spark, "position",
			Vector2(cos(angle), sin(angle)) * randf_range(30.0, 60.0), 0.4)
		tw.tween_property(sline, "default_color",
			Color(0.95, 0.75, 0.1, 0.0), 0.4)
		tw.set_parallel(false)
		tw.tween_callback(spark.queue_free)

func _spawn_dropped_artifact_marker(hex_key: Vector2i, pos: Vector2, hex_map: Node) -> void:
	# A slightly dimmer/different version of the normal treasure node — marks the dropped artifact
	var node := Node2D.new()
	node.global_position = pos
	node.z_index = 2;  node.z_as_relative = false
	node.add_to_group("treasure_node")
	node.set_meta("hex_key", hex_key)
	# Outer ring — red-tinted to signal it was dropped
	var gpts := PackedVector2Array()
	for i in 18:
		var a: float = TAU * float(i) / 18.0
		gpts.append(Vector2(cos(a), sin(a)) * 20.0)
	var gpoly := Polygon2D.new()
	gpoly.polygon = gpts;  gpoly.color = Color(1.0, 0.30, 0.1, 0.35)
	node.add_child(gpoly)
	# Hex body — dimmer amber, slightly smaller
	var hpts := PackedVector2Array()
	for i in 6:
		var a: float = deg_to_rad(60.0 * float(i) - 30.0)
		hpts.append(Vector2(cos(a), sin(a)) * 11.0)
	var hpoly := Polygon2D.new()
	hpoly.polygon = hpts;  hpoly.color = Color(0.75, 0.55, 0.10, 0.85)
	node.add_child(hpoly)
	# Center dot
	var jpts := PackedVector2Array()
	for i in 8:
		var a: float = TAU * float(i) / 8.0
		jpts.append(Vector2(cos(a), sin(a)) * 4.0)
	var jpoly := Polygon2D.new()
	jpoly.polygon = jpts;  jpoly.color = Color(1.0, 0.5, 0.2, 1.0)
	node.add_child(jpoly)
	# Anxious faster pulse — this one wants to be found
	var pulse := get_tree().create_tween().set_loops()
	pulse.tween_property(gpoly, "color", Color(1.0, 0.30, 0.1, 0.70), 0.55)
	pulse.tween_property(gpoly, "color", Color(1.0, 0.30, 0.1, 0.10), 0.55)
	# Also register in hex_map's treasure_nodes dict so it can be removed on pickup
	if hex_map.has_method("register_treasure_node"):
		hex_map.register_treasure_node(hex_key, node)
	get_parent().add_child(node)


func _check_artifact_milestones() -> void:
	var hud = get_parent().get_node_or_null("Hud")
	if artifact_count == 10:
		barrel_level = 2
		if hud != null and hud.has_method("show_milestone"):
			hud.show_milestone("DOUBLE BARREL  UNLOCKED")
	elif artifact_count == 25:
		barrel_level = 3
		if hud != null and hud.has_method("show_milestone"):
			hud.show_milestone("TRIPLE BARREL  UNLOCKED")
	elif artifact_count == 50:
		shield_unlocked = true
		_shield_max = max_hp * 0.5
		_shield_hp  = _shield_max
		if hud != null and hud.has_method("show_milestone"):
			hud.show_milestone("PERSONAL SHIELD  UNLOCKED")
