extends Area2D

# ── Set these before adding to scene ─────────────────────────────────────────
var homing_level: int      = 1
var bullet_speed: float    = 300.0
var bullet_range: float    = 800.0
var bullet_damage: float   = 1.0
var initial_dir: Vector2   = Vector2.UP
var explosive_radius: float = 0.0   # 0 = no explosion
var explosive_lvl: int      = 0
var bullet_color: Color     = Color.WHITE

# ── Internal ──────────────────────────────────────────────────────────────────
var _dir: Vector2 = Vector2.UP
var _dist_traveled: float = 0.0
var _lifetime: float = 0.0
const MAX_LIFETIME := 4.0   # seconds before self-destruct regardless of range
var _coast_dist: float = 0.0   # travel this far before homing kicks in
var _trail_frame: int = 0        # skip odd frames to halve trail instance count
var _spawner: Node = null
var _player: Node = null

func _ready() -> void:
	_dir = initial_dir.normalized()
	add_to_group("bullet")
	set_meta("damage", bullet_damage)
	set_meta("homing_level", homing_level)
	set_meta("explosive_radius", explosive_radius)
	set_meta("explosive_lvl", explosive_lvl)
	set_meta("split_level", 0)
	set_meta("knockback", {"slow": 0.0, "duration": 0.0, "push": 0})
	# Cache scene references
	var root = get_tree().get_root()
	_spawner = root.find_child("EnemySpawner", true, false)
	_player  = root.find_child("Player", true, false)

func _physics_process(delta: float) -> void:
	# ── Steer toward nearest target — coast first if _coast_dist > 0 ─────────
	var turn_rate: float = deg_to_rad(lerp(30.0, 360.0, float(homing_level - 1) / 9.0))
	if _coast_dist > 0.0:
		_coast_dist -= bullet_speed * delta
	else:
		var nearest_dir: Vector2 = Vector2.ZERO
		var nearest_dist: float  = 99999.0
		for group in ["enemies", "enemy_towers", "boss_enemy"]:
			for target in get_tree().get_nodes_in_group(group):
				if not is_instance_valid(target):
					continue
				var d: float = global_position.distance_to((target as Node2D).global_position)
				if d < nearest_dist:
					nearest_dist = d
					nearest_dir  = ((target as Node2D).global_position - global_position).normalized()
		if nearest_dir != Vector2.ZERO:
			var angle_diff: float  = _dir.angle_to(nearest_dir)
			var actual_turn: float = clampf(angle_diff, -turn_rate * delta, turn_rate * delta)
			_dir = _dir.rotated(actual_turn).normalized()

	# ── Move ──────────────────────────────────────────────────────────────────
	var move: float = bullet_speed * delta
	global_position += _dir * move
	rotation = _dir.angle() + PI / 2.0
	_dist_traveled += move
	_lifetime += delta
	if _dist_traveled >= bullet_range or _lifetime >= MAX_LIFETIME:
		queue_free()
		return

	# ── Trail — spawn every 2nd frame (halves instance count) ────────────────
	_trail_frame += 1
	if _trail_frame % 2 == 0:
		var is_rainbow: bool = homing_level == 10
		var trail := Node2D.new()
		var tp    := Polygon2D.new()
		var tpts  := PackedVector2Array()
		for ti in 8:
			var ta: float = TAU * float(ti) / 8.0
			tpts.append(Vector2(cos(ta), sin(ta)) * 3.5)
		tp.polygon = tpts
		if is_rainbow:
			tp.color = Color.from_hsv(fmod(Time.get_ticks_msec() / 300.0 + randf() * 0.5, 1.0), 1.0, 1.0, 0.75)
		else:
			tp.color = Color(0.72, 0.72, 0.72, 0.72)
		trail.add_child(tp)
		trail.scale = Vector2(0.3, 0.3)
		trail.global_position = global_position
		get_parent().add_child(trail)
		# Grow outward while fading — cloud dissolve effect
		var tw := get_tree().create_tween()
		tw.set_parallel(true)
		tw.tween_property(trail, "scale",    Vector2(1.5, 1.5), 0.45)
		tw.tween_property(tp,    "color",    Color(tp.color.r, tp.color.g, tp.color.b, 0.0), 0.45)
		tw.set_parallel(false)
		tw.tween_callback(trail.queue_free)

	# ── Collision: only enemies via on_hit_enemy ─────────────────────────────
	# Towers and boss are handled by _check_bullet_hits_towers/boss in the
	# spawner's _physics_process — homing bullets are in "bullet" group so
	# those checks find us automatically. Only call _on_hit_enemy for enemies.
	for target in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(target):
			continue
		if global_position.distance_to((target as Node2D).global_position) < 18.0:
			_on_hit_enemy(target as Area2D)
			return

func _on_hit_enemy(enemy: Area2D) -> void:
	if not is_instance_valid(enemy) or not enemy.has_meta("hp"):
		queue_free()
		return
	if is_instance_valid(_spawner):
		_spawner.on_bullet_hit(enemy, self)

	# ── Heat Seeker + Explosive = MISSILE TREE ───────────────────────────────
	# Instead of detonating, spawn child seekers perpendicular to travel dir.
	# Children have explosive_radius=0 so no further branching.
	if explosive_radius > 0.0 and homing_level > 0:
		_spawn_perpendicular_seekers()
	elif explosive_radius > 0.0 and is_instance_valid(_spawner):
		# Explosive only (no heat seeker) — normal detonation
		var chain: bool = explosive_lvl == 10
		_spawner.trigger_explosion(global_position, explosive_radius, bullet_damage / 2.0, chain)
		if is_instance_valid(_player) and _player.has_method("_spawn_fireworks"):
			_player._spawn_fireworks(global_position, explosive_lvl, bullet_color, explosive_radius)

	# LV10 homing explosion (fires even alongside tree — the leader always pops)
	if homing_level == 10 and is_instance_valid(_player) and _player.has_method("_spawn_homing_explosion"):
		_player._spawn_homing_explosion(global_position, bullet_damage)

	if is_instance_valid(self):
		queue_free()

func _spawn_perpendicular_seekers() -> void:
	if not is_instance_valid(get_parent()):
		return
	# Number of children = explosive_lvl (1-10)
	var child_count: int = explosive_lvl
	# Perpendicular axis — 90° from travel direction
	var perp: Vector2 = _dir.rotated(PI / 2.0)
	# Spread children evenly across a 180° arc centered on perp axis
	for i in child_count:
		var t: float = float(i) / float(maxi(child_count - 1, 1))  # 0.0 to 1.0
		var spread_angle: float = lerp(-90.0, 90.0, t)             # -90° to +90° off perp axis
		var jitter: float = randf_range(-10.0, 10.0)               # organic feel
		var child_dir: Vector2 = perp.rotated(deg_to_rad(spread_angle + jitter)).normalized()

		var hb := Area2D.new()
		hb.set_script(load("res://homing_bullet.gd"))
		hb.homing_level     = homing_level
		hb.bullet_speed     = bullet_speed * 0.9
		hb.bullet_range     = 400.0                 # shorter range than parent
		hb.bullet_damage    = bullet_damage * 0.6
		hb.initial_dir      = child_dir
		hb.explosive_radius = 0.0                   # no further branching
		hb.explosive_lvl    = 0
		hb.bullet_color     = bullet_color

		var hs := CollisionShape2D.new()
		var hc := CircleShape2D.new();  hc.radius = 4.0;  hs.shape = hc
		hb.add_child(hs)
		var hp := Polygon2D.new()
		hp.color = Color.from_hsv(float(i) / float(child_count), 1.0, 1.0)
		hp.polygon = PackedVector2Array([Vector2(0,-5),Vector2(3,5),Vector2(-3,5)])
		hb.add_child(hp)
		hb.global_position = global_position
		hb.rotation = child_dir.angle() + PI / 2.0
		# Coast 80px before homing kicks in — lets children spread sideways visibly
		hb._coast_dist = 80.0
		get_parent().add_child(hb)
