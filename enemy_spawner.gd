extends Node2D

# ─── CONSTANTS ────────────────────────────────────────────────────────────────
const ENEMY_SPEED := 80.0
const BOSS_SPEED := 35.0
const BOSS_FIRE_INTERVAL := 2.0
const TOWER_HP_BASE := 50.0
const TOWERS_TOTAL := 5
const TOWER_RING_RADIUS := 1200.0   # pushed out for big map
const SPAWN_RADIUS       := 900.0

# ─── WAVE VARS ────────────────────────────────────────────────────────────────
var castle_pos := Vector2(3330.0, 2100.0)  # matches hex_map.MAP_CENTER
var wave_number := 0
var enemies_to_spawn := 0
var enemies_spawned := 0
var enemies_alive := 0
var state := "IDLE"
var cooldown_timer := 0.0
var cooldown_duration := 30.0   # overridden per wave in start_wave
var spawn_delay := 0.0
var spawn_delay_interval := 2.5
var debug_speed_mult: float = 1.0   # GMP enemy speed multiplier

# ─── S5: Enemy tower vars ──────────────────────────────────────────────────────
var towers_destroyed := 0
var tower_level := 1

# ─── S5: Boss vars ────────────────────────────────────────────────────────────
var boss_rank := 0
var boss_alive := false
var boss_node = null

# ─── READY ────────────────────────────────────────────────────────────────────
func _ready() -> void:
	# Defer so HexMap._ready() has run and terrain is generated before we place towers
	call_deferred("_deferred_start")

func _deferred_start() -> void:
	# Snap Castle to exact hex-grid center
	var castle_node = get_parent().get_node_or_null("Castle")
	if castle_node != null:
		(castle_node as Node2D).global_position = castle_pos
	_spawn_enemy_towers()
	start_wave()

# ─── PROCESS — wave state machine ─────────────────────────────────────────────
func _process(delta: float) -> void:
	if state == "SPAWNING":
		spawn_delay += delta
		if spawn_delay >= spawn_delay_interval:
			spawn_delay = 0.0
			spawn_enemy()
			enemies_spawned += 1
			if enemies_spawned >= enemies_to_spawn:
				state = "WAITING"
	elif state == "WAITING":
		if enemies_spawned >= enemies_to_spawn and enemies_alive <= 0:
			state = "COOLDOWN"
			# Wave cooldown schedule: 60/120/180/240/300s (1-5 min, locks at wave 5+)
			cooldown_duration = minf(float(wave_number) * 60.0, 300.0)
			cooldown_timer = cooldown_duration
			get_parent().get_node("Hud").start_cooldown(cooldown_duration)
	elif state == "COOLDOWN":
		cooldown_timer -= delta
		get_parent().get_node("Hud").update_cooldown(cooldown_timer)
		if cooldown_timer <= 0.0:
			start_wave()

func start_wave() -> void:
	wave_number += 1
	enemies_to_spawn = 10 + (wave_number - 1) * 5
	enemies_spawned = 0
	enemies_alive = 0
	state = "SPAWNING"
	spawn_delay_interval = max(0.8, 2.5 - (wave_number - 1) * 0.2)
	spawn_delay = spawn_delay_interval
	if wave_number > 1:
		get_parent().get_node("Hud").update_wave_info(wave_number, false, 0, 0)

# ─── PHYSICS PROCESS ──────────────────────────────────────────────────────────
func _physics_process(delta: float) -> void:
	# Freeze during Tron Flip cascade
	if GameState.boss_flip_active: return

	var player: Node2D = get_parent().get_node_or_null("Player") as Node2D

	_move_enemies(delta, player)
	_move_boss(delta, player)
	_check_boss_bullets(player)
	_check_bullet_hits_enemies()
	_check_bullet_hits_towers()
	_check_bullet_hits_boss()
	_tick_spike_traps(delta, player)

# ─── S5: Enemy movement — player-priority targeting ───────────────────────────
# ─── Path replan interval — don't recalc every frame, tune as needed ─────────
const PATH_REPLAN_INTERVAL := 0.6   # seconds between A* replans per enemy
const DETECT_RANGE      := 600.0   # pixels — enemy pursues when player within this range (~10 hexes)
const WANDER_CHANGE_INT := 2.0     # seconds between wander direction changes

func _move_enemies(delta: float, player: Node2D) -> void:
	for enemy in get_children():
		if not enemy is Area2D:
			continue
		if not enemy.is_in_group("enemies"):
			continue
		if not is_instance_valid(enemy):
			continue
		if (enemy as Area2D).get_meta("arriving", false):
			continue   # mid spawn-in animation — do not move yet

		var en: Area2D = enemy as Area2D

		# ── State: WANDER or PURSUE ──────────────────────────────────────────
		var dist_to_player: float = 99999.0
		if is_instance_valid(player):
			dist_to_player = en.position.distance_to(player.global_position)
		var dist_to_tower: float = en.position.distance_to(castle_pos)
		# Artifact aggro — 1.8× detection range while player carries a treasure
		var carrying: bool = is_instance_valid(player) and (player as Node).get("carrying_artifact") == true
		var active_range: float = DETECT_RANGE * 1.8 if carrying else DETECT_RANGE
		var in_range: bool = dist_to_player < active_range or dist_to_tower < DETECT_RANGE

		if not in_range and state == "COOLDOWN":
			# ── WANDER — drift randomly, avoid pits/blocks ────────────────────
			var wander_timer: float = en.get_meta("wander_timer") if en.has_meta("wander_timer") else 0.0
			var wander_dir: Vector2 = en.get_meta("wander_dir") if en.has_meta("wander_dir") else Vector2(randf_range(-1,1), randf_range(-1,1)).normalized()
			wander_timer -= delta
			if wander_timer <= 0.0:
				# Pick new random direction, bias slightly toward center
				var center_pull: Vector2 = (castle_pos - en.position).normalized() * 0.15
				wander_dir = (Vector2(randf_range(-1,1), randf_range(-1,1)).normalized() + center_pull).normalized()
				wander_timer = randf_range(1.5, WANDER_CHANGE_INT)
				en.set_meta("wander_timer", wander_timer)
				en.set_meta("wander_dir", wander_dir)
			else:
				en.set_meta("wander_timer", wander_timer)
			# Move wander — check passability ahead
			var next_pos: Vector2 = en.position + wander_dir * en.get_meta("speed") * delta
			var hex_map = get_parent().get_node_or_null("HexMap")
			if hex_map != null and not hex_map.is_passable(next_pos):
				# Bounce off wall
				wander_dir = Vector2(randf_range(-1,1), randf_range(-1,1)).normalized()
				en.set_meta("wander_dir", wander_dir)
			else:
				en.position = next_pos
			en.rotation = wander_dir.angle() + PI / 2.0
			continue   # skip pursue logic

		# ── PURSUE — pick target (player if closer, else tower) ──────────────
		var target_pos: Vector2 = castle_pos
		if is_instance_valid(player):
			var dp: float = en.position.distance_to(player.global_position)
			var dt: float = en.position.distance_to(castle_pos)
			if dp < dt:
				target_pos = player.global_position

		# ── Replan path on interval or when target changed ────────────────────
		var replan_timer: float = en.get_meta("replan_timer") if en.has_meta("replan_timer") else 0.0
		var last_target: Vector2 = en.get_meta("last_target") if en.has_meta("last_target") else Vector2.ZERO
		replan_timer -= delta
		if replan_timer <= 0.0 or last_target.distance_to(target_pos) > 120.0:
			var new_path = HexPathfinder.find_path(en.position, target_pos)
			en.set_meta("path", new_path)
			en.set_meta("path_idx", 0)
			en.set_meta("replan_timer", PATH_REPLAN_INTERVAL)
			en.set_meta("last_target", target_pos)
		else:
			en.set_meta("replan_timer", replan_timer)

		# ── Follow current path waypoint ──────────────────────────────────────
		var path = en.get_meta("path") if en.has_meta("path") else []
		var path_idx = en.get_meta("path_idx") if en.has_meta("path_idx") else 0
		var dir: Vector2 = Vector2.ZERO
		if path.size() > 0 and path_idx < path.size():
			var waypoint: Vector2 = path[path_idx]
			if en.position.distance_to(waypoint) < 18.0:
				path_idx += 1
				en.set_meta("path_idx", path_idx)
			if path_idx < path.size():
				dir = (path[path_idx] - en.position).normalized()
			else:
				dir = (target_pos - en.position).normalized()
		else:
			dir = (target_pos - en.position).normalized()

		# ── Slow modifier ─────────────────────────────────────────────────────
		var slow: float = en.get_meta("slow") if en.has_meta("slow") else 0.0
		var slow_timer: float = en.get_meta("slow_timer") if en.has_meta("slow_timer") else 0.0
		if slow_timer > 0.0:
			slow_timer -= delta
			en.set_meta("slow_timer", slow_timer)
		else:
			slow = 0.0
			en.set_meta("slow", 0.0)

		var spd: float = en.get_meta("speed")
		en.position += dir * spd * debug_speed_mult * (1.0 - slow) * delta
		if dir != Vector2.ZERO:
			en.rotation = dir.angle() + PI / 2.0

		if is_instance_valid(player) and en.position.distance_to(player.global_position) < 20.0:
			player.take_damage(1.0)
			enemies_alive -= 1
			_spawn_crater(en.position)
			_spawn_shockwave(en.position)
			enemy.queue_free()
			continue
		if is_instance_valid(enemy) and en.position.distance_to(castle_pos) < 20.0:
			get_parent().get_node("Castle").take_damage(10)
			enemies_alive -= 1
			_spawn_crater(en.position)
			_spawn_shockwave(en.position)
			enemy.queue_free()

# ─── S5: Boss movement + turret ───────────────────────────────────────────────
func _move_boss(delta: float, player: Node2D) -> void:
	# Update cyber eye tracking
	if boss_alive and is_instance_valid(boss_node) and is_instance_valid(player):
		var bn2: Area2D = boss_node as Area2D
		if bn2.has_meta("pupil") and bn2.has_meta("iris"):
			var to_player: Vector2 = (player.global_position - bn2.global_position).normalized()
			var pupil2: Polygon2D = bn2.get_meta("pupil") as Polygon2D
			pupil2.position = to_player * 3.5
			# HP-based pulse
			var hp_ratio: float = (bn2.get_meta("hp") as float) / (bn2.get_meta("max_hp") as float)
			var pulse: float = 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.006)
			var iris2: Polygon2D = bn2.get_meta("iris") as Polygon2D
			var glow2: Polygon2D = bn2.get_meta("glow") as Polygon2D
			if hp_ratio > 0.5:
				iris2.color = Color(0.85, 0.0, 0.05)
				glow2.color = Color(0.85, 0.0, 0.05, 0.18 + pulse * 0.10)
			elif hp_ratio > 0.25:
				iris2.color = Color(1.0, 0.35 + pulse * 0.2, 0.0)
				glow2.color = Color(1.0, 0.3, 0.0, 0.25 + pulse * 0.15)
			else:
				# White-hot panic
				iris2.color = Color(1.0, 0.8 + pulse * 0.2, 0.8 + pulse * 0.2)
				glow2.color = Color(1.0, 0.5, 0.3, 0.35 + pulse * 0.25)
	if not boss_alive or not is_instance_valid(boss_node):
		return
	var bn: Area2D = boss_node as Area2D
	var btarget: Vector2 = castle_pos
	if is_instance_valid(player):
		btarget = player.global_position
	# Boss uses pathfinder too — replans every 0.8s
	var boss_replan: float = bn.get_meta("replan_timer") if bn.has_meta("replan_timer") else 0.0
	boss_replan -= delta
	if boss_replan <= 0.0:
		var new_bpath = HexPathfinder.find_path(bn.position, btarget)
		bn.set_meta("bpath", new_bpath)
		bn.set_meta("bpath_idx", 0)
		bn.set_meta("replan_timer", 0.8)
	else:
		bn.set_meta("replan_timer", boss_replan)
	var bpath = bn.get_meta("bpath") if bn.has_meta("bpath") else []
	var bpath_idx = bn.get_meta("bpath_idx") if bn.has_meta("bpath_idx") else 0
	var bdir: Vector2 = Vector2.ZERO
	if bpath.size() > 0 and bpath_idx < bpath.size():
		var bwp: Vector2 = bpath[bpath_idx]
		if bn.position.distance_to(bwp) < 28.0:
			bpath_idx += 1
			bn.set_meta("bpath_idx", bpath_idx)
		if bpath_idx < bpath.size():
			bdir = (bpath[bpath_idx] - bn.position).normalized()
		else:
			bdir = (btarget - bn.position).normalized()
	else:
		bdir = (btarget - bn.position).normalized()
	bn.position += bdir * BOSS_SPEED * delta
	if bdir != Vector2.ZERO:
		bn.rotation = bdir.angle() + PI / 2.0
	if is_instance_valid(player) and bn.position.distance_to(player.global_position) < 35.0:
		player.take_damage(5.0)
	var bft: float = bn.get_meta("fire_timer")
	bft += delta
	bn.set_meta("fire_timer", bft)
	if bft >= BOSS_FIRE_INTERVAL:
		bn.set_meta("fire_timer", 0.0)
		_fire_boss_bullet(player)

# ─── Spike trap tick — recharge timers + proximity trigger ───────────────────
func _tick_spike_traps(delta: float, player: Node2D) -> void:
	var hex_map = get_parent().get_node_or_null("HexMap")
	if hex_map == null or not hex_map.has_method("tick_spike_traps"): return
	hex_map.tick_spike_traps(delta)
	# Proximity trigger — player or enemies within 1 hex of a trap set it off
	var trigger_range: float = hex_map.HEX_SIZE * 2.2
	for trap_node in get_tree().get_nodes_in_group("spike_trap"):
		if not is_instance_valid(trap_node): continue
		var tpos: Vector2 = (trap_node as Node2D).global_position
		var hk: Vector2i = (trap_node as Node).get_meta("hex_key")
		# Player proximity
		if is_instance_valid(player):
			if player.global_position.distance_to(tpos) < trigger_range:
				hex_map.trigger_spike_trap(hk, trap_node as Node2D)
				continue
		# Enemy proximity
		for enemy in get_children():
			if not enemy is Area2D: continue
			if not (enemy as Area2D).is_in_group("enemies"): continue
			if (enemy as Node2D).global_position.distance_to(tpos) < trigger_range:
				hex_map.trigger_spike_trap(hk, trap_node as Node2D)
				break


# ─── Boss bullet ──────────────────────────────────────────────────────────────
func _fire_boss_bullet(player: Node2D) -> void:
	if not is_instance_valid(player) or not is_instance_valid(boss_node):
		return
	var bn: Area2D = boss_node as Area2D
	var blt := Area2D.new()
	blt.add_to_group("boss_bullet")
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 9.0
	shape.shape = circle
	blt.add_child(shape)
	var poly := Polygon2D.new()
	poly.polygon = PackedVector2Array([Vector2(0, -9), Vector2(8, 7), Vector2(-8, 7)])
	poly.color = Color(0.85, 0.0, 0.0)
	blt.add_child(poly)
	blt.global_position = bn.global_position
	get_parent().add_child(blt)
	var dir: Vector2 = (player.global_position - bn.global_position).normalized()
	var target: Vector2 = bn.global_position + dir * 550.0
	var tween := get_tree().create_tween()
	tween.tween_property(blt, "global_position", target, 1.8)
	tween.tween_callback(blt.queue_free)

# ─── Boss bullets hit player ──────────────────────────────────────────────────
func _check_boss_bullets(player: Node2D) -> void:
	if not is_instance_valid(player):
		return
	for blt in get_parent().get_children():
		if not is_instance_valid(blt):
			continue
		if not blt.is_in_group("boss_bullet"):
			continue
		if (blt as Node2D).global_position.distance_to(player.global_position) < 22.0:
			player.take_damage(2.0)
			blt.queue_free()

# ─── Bullets hit enemies ──────────────────────────────────────────────────────
func _check_bullet_hits_enemies() -> void:
	for child in get_parent().get_children():
		if not child is Area2D:
			continue
		if not child.is_in_group("bullet"):
			continue
		if not is_instance_valid(child):
			continue
		var cblt: Area2D = child as Area2D
		if cblt.has_meta("hit"):
			continue
		for enemy in get_children():
			if not enemy is Area2D:
				continue
			if not enemy.is_in_group("enemies"):
				continue
			if not is_instance_valid(enemy):
				continue
			if cblt.global_position.distance_to((enemy as Area2D).global_position) < 15.0:
				cblt.set_meta("hit", true)
				on_bullet_hit(enemy as Area2D, cblt)
				break

# ─── S5: Bullets hit enemy towers ─────────────────────────────────────────────
func _check_bullet_hits_towers() -> void:
	for child in get_parent().get_children():
		if not child is Area2D:
			continue
		if not child.is_in_group("bullet"):
			continue
		if not is_instance_valid(child):
			continue
		var cblt: Area2D = child as Area2D
		if cblt.has_meta("hit"):
			continue
		for t in get_children():
			if not t is Area2D:
				continue
			if not t.is_in_group("enemy_towers"):
				continue
			if not is_instance_valid(t):
				continue
			if cblt.global_position.distance_to((t as Area2D).global_position) < 22.0:
				cblt.set_meta("hit", true)
				_on_tower_hit(t as Area2D, cblt)
				break

# ─── S5: Bullets hit boss ─────────────────────────────────────────────────────
func _check_bullet_hits_boss() -> void:
	# Scan group directly — handles multiple bosses and stale boss_node refs
	var bosses := get_tree().get_nodes_in_group("boss_enemy")
	if bosses.is_empty():
		return
	for bullet in get_parent().get_children():
		if not bullet is Area2D: continue
		if not bullet.is_in_group("bullet"): continue
		if not is_instance_valid(bullet): continue
		var cblt: Area2D = bullet as Area2D
		if cblt.has_meta("hit"): continue
		for boss in bosses:
			if not is_instance_valid(boss): continue
			if cblt.global_position.distance_to((boss as Node2D).global_position) < 32.0:
				cblt.set_meta("hit", true)
				# Temporarily set boss_node so _on_boss_hit has the right reference
				var prev_boss_node = boss_node
				boss_node = boss
				_on_boss_hit(cblt)
				if boss_node == boss and is_instance_valid(boss):
					boss_node = prev_boss_node
				break

# ─── Tower hit ────────────────────────────────────────────────────────────────
func _on_tower_hit(t: Area2D, blt: Area2D) -> void:
	var dmg: float = blt.get_meta("damage") if blt.has_meta("damage") else 1.0
	if not blt.has_meta("piercing"): blt.queue_free()
	# Wall hex blocks center — can't damage center while wall lives
	if t.get_meta("is_et_center", false):
		var wall_alive := false
		for sib in get_children():
			if sib is Area2D and sib.is_in_group("et_wall") and is_instance_valid(sib):
				if sib.get_meta("et_center_ref", null) == t:
					wall_alive = true;  break
		if wall_alive: return
	var hp: float = t.get_meta("hp")
	hp -= dmg
	t.set_meta("hp", hp)
	var max_hp: float = t.get_meta("max_hp")
	var ratio: float = maxf(hp / max_hp, 0.0)
	# Update health bar fill width
	if t.has_meta("hbar_fill") and t.has_meta("hbar_max_w"):
		var hf: ColorRect = t.get_meta("hbar_fill") as ColorRect
		var mw: float = t.get_meta("hbar_max_w") as float
		hf.size.x = mw * ratio
		if ratio > 0.5:
			hf.color = Color(1.0, 0.13, 0.00)
		elif ratio > 0.25:
			hf.color = Color(1.0, 0.55, 0.0)
		else:
			hf.color = Color(1.0, 0.9, 0.1)
	var is_center: bool = t.get_meta("is_et_center") if t.has_meta("is_et_center") else false
	if hp <= 0.0:
		var death_pos: Vector2 = t.position
		t.queue_free()
		if is_center:
			_on_et_center_destroyed(death_pos)
		else:
			_on_et_outer_destroyed(death_pos)

func _on_et_outer_destroyed(pos: Vector2) -> void:
	# Rubble pile with continuous smoke — 3 enemies per second until all 5 emerge
	var total: int = 5
	var emerged: int = 0

	# ── Rubble pile base ─────────────────────────────────────────────────────
	var rubble := Node2D.new()
	rubble.global_position = pos
	rubble.z_index = 2;  rubble.z_as_relative = false
	var rpts := PackedVector2Array()
	for ri in 12:
		var ra: float = TAU * float(ri) / 12.0
		rpts.append(Vector2(cos(ra), sin(ra)) * randf_range(14.0, 26.0))
	var rpoly := Polygon2D.new()
	rpoly.polygon = rpts;  rpoly.color = Color(0.35, 0.26, 0.18, 0.92)
	rubble.add_child(rpoly)
	rubble.scale = Vector2(0.2, 0.2)
	get_parent().add_child(rubble)
	get_tree().create_tween().tween_property(rubble, "scale", Vector2(1.0, 1.0), 0.18)

	# ── Continuous smoke loop — one puff every 0.12s while rubble alive ───────
	var _smoke: Callable
	_smoke = func():
		if not is_instance_valid(self) or not is_instance_valid(rubble): return
		var puff := Node2D.new()
		puff.global_position = pos + Vector2(randf_range(-14.0, 14.0), randf_range(-14.0, 14.0))
		puff.z_index = 3;  puff.z_as_relative = false
		var ppts := PackedVector2Array()
		for pi in 8:
			var pa: float = TAU * float(pi) / 8.0
			ppts.append(Vector2(cos(pa), sin(pa)) * randf_range(5.0, 11.0))
		var ppoly := Polygon2D.new()
		ppoly.polygon = ppts;  ppoly.color = Color(0.40, 0.32, 0.22, 0.68)
		puff.scale = Vector2(0.3, 0.3);  puff.add_child(ppoly)
		get_parent().add_child(puff)
		var ptw := get_tree().create_tween()
		ptw.set_parallel(true)
		ptw.tween_property(puff,  "scale", Vector2(2.0, 2.0), 0.55)
		ptw.tween_property(ppoly, "color", Color(0.40, 0.32, 0.22, 0.0), 0.55)
		ptw.set_parallel(false);  ptw.tween_callback(puff.queue_free)
		if is_inside_tree(): get_tree().create_timer(0.12).timeout.connect(_smoke)
	if is_inside_tree(): get_tree().create_timer(0.05).timeout.connect(_smoke)

	# ── Enemy emergence — 3 per second, one at a time ────────────────────────
	var _emit: Callable
	_emit = func():
		if not is_instance_valid(self) or not is_instance_valid(rubble): return
		emerged += 1
		var angle: float = randf() * TAU
		var raw: Vector2 = pos + Vector2(cos(angle), sin(angle)) * randf_range(30.0, 80.0)
		var snap_pos: Vector2 = _snap_to_valid_hex(raw)
		var e := _create_enemy_at(snap_pos)
		if e != null:
			add_child(e);  enemies_alive += 1
			_animate_enemy_arrival(e, snap_pos)
		if emerged < total:
			if is_inside_tree(): get_tree().create_timer(0.333).timeout.connect(_emit)
		else:
			# All out — let smoke thin then fade rubble
			get_tree().create_timer(0.8).timeout.connect(func():
				if is_instance_valid(rubble):
					var ftw := get_tree().create_tween()
					ftw.tween_property(rpoly, "color", Color(0.35, 0.26, 0.18, 0.0), 0.7)
					ftw.tween_callback(rubble.queue_free)
			)
	if is_inside_tree(): get_tree().create_timer(0.2).timeout.connect(_emit)
func _on_et_center_destroyed(pos: Vector2) -> void:
	# Guard — each ET center counts exactly once
	if towers_destroyed >= TOWERS_TOTAL:
		return
	# Count as tower destroyed for wave progression
	towers_destroyed += 1
	var hud = get_parent().get_node("Hud")
	hud.update_tower_count(towers_destroyed, TOWERS_TOTAL)
	# Spawn the Castle Warden — heavy guardian who emerges to investigate
	_spawn_castle_warden(pos)
	# 7-second fireworks celebration
	var player = get_parent().get_node_or_null("Player")
	if player != null and player.has_method("_spawn_fireworks"):
		var celebration_end: float = Time.get_ticks_msec() / 1000.0 + 7.0
		_boss_celebration(player, pos, 180.0, celebration_end)
	# Check for main boss spawn
	if towers_destroyed >= TOWERS_TOTAL and not boss_alive and get_tree().get_nodes_in_group("boss_enemy").is_empty():
		spawn_boss()

func _create_enemy_at(pos: Vector2) -> Area2D:
	var max_tier: int = _get_max_tier()
	var tier: int = randi_range(1, max_tier) - 1
	var td: Array = ENEMY_TIERS[tier]
	var hp_mult: float = get_meta("enemy_hp_mult") if has_meta("enemy_hp_mult") else 1.0
	var hp: float = td[0] * pow(1.15, float(wave_number - 1)) * hp_mult
	var spd: float = td[1] * debug_speed_mult
	var sz: float = td[2];  var col: Color = Color("#" + td[3]);  var sides: int = td[4]
	var enemy := Area2D.new()
	enemy.set_meta("hp", hp);  enemy.set_meta("max_hp", hp)
	enemy.set_meta("speed", spd);  enemy.set_meta("tier", tier + 1)
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new();  circle.radius = 10.0 * sz;  shape.shape = circle
	enemy.add_child(shape)
	var poly := Polygon2D.new()
	var base_r: float = 12.0 * sz
	var pts := PackedVector2Array()
	if sides == 3:
		pts = PackedVector2Array([Vector2(0,-base_r),Vector2(base_r*0.85,base_r*0.65),Vector2(-base_r*0.85,base_r*0.65)])
	elif sides == 4:
		pts = PackedVector2Array([Vector2(0,-base_r),Vector2(base_r,0),Vector2(0,base_r),Vector2(-base_r,0)])
	else:
		for j in sides:
			var a: float = TAU * float(j) / float(sides) - PI / 2.0
			pts.append(Vector2(cos(a),sin(a)) * base_r)
	poly.polygon = pts;  poly.color = col
	enemy.add_child(poly);  enemy.set_meta("poly", poly)
	_apply_dark_future_skin(enemy, tier, base_r)
	enemy.position = pos
	enemy.add_to_group("enemies")
	enemy.area_entered.connect(func(area):
		if is_instance_valid(enemy): on_bullet_hit(enemy, area)
	)
	return enemy

# ─── Castle Warden — heavy guardian spawned on ET center destruction ─────────
func _spawn_castle_warden(pos: Vector2) -> void:
	# Brief gate-opening delay before warden emerges
	get_tree().create_timer(0.4).timeout.connect(func():
		var snap_pos: Vector2 = _snap_to_valid_hex(pos)

		# ── Warden stats — slow, iron-plated, high HP ────────────────────────
		var warden_hp: float = 280.0 * float(maxi(boss_rank + 1, 1)) * pow(1.12, float(wave_number - 1))
		var warden := Area2D.new()
		warden.add_to_group("enemies")
		warden.add_to_group("castle_warden")

		# Collision
		var wshape := CollisionShape2D.new()
		var wcirc  := CircleShape2D.new();  wcirc.radius = 26.0;  wshape.shape = wcirc
		warden.add_child(wshape)

		# ── Octagonal body — dark gunmetal iron ──────────────────────────────
		var base_r: float = 26.0
		var body_pts := PackedVector2Array()
		for j in 8:
			var a: float = TAU * float(j) / 8.0 - PI / 8.0
			body_pts.append(Vector2(cos(a), sin(a)) * base_r)
		var body_poly := Polygon2D.new()
		body_poly.polygon = body_pts
		body_poly.color   = Color(0.12, 0.12, 0.17)   # dark iron
		warden.add_child(body_poly)
		warden.set_meta("poly", body_poly)

		# Armor plates — 4 inner facets slightly inset
		for ap in 4:
			var a0: float = TAU * float(ap * 2) / 8.0 - PI / 8.0
			var a1: float = TAU * float(ap * 2 + 1) / 8.0 - PI / 8.0
			var plate_pts := PackedVector2Array()
			plate_pts.append(Vector2(cos(a0), sin(a0)) * base_r * 0.88)
			plate_pts.append(Vector2(cos(a1), sin(a1)) * base_r * 0.88)
			plate_pts.append(Vector2(cos(a1), sin(a1)) * base_r * 0.55)
			plate_pts.append(Vector2(cos(a0), sin(a0)) * base_r * 0.55)
			var plate := Polygon2D.new()
			plate.polygon = plate_pts
			plate.color   = Color(0.18, 0.16, 0.24)   # slightly lighter plate
			warden.add_child(plate)

		# Red eye — single threatening center dot
		var eye_pts := PackedVector2Array()
		for j in 8:
			var a: float = TAU * float(j) / 8.0
			eye_pts.append(Vector2(cos(a), sin(a)) * 5.0)
		var eye := Polygon2D.new()
		eye.polygon = eye_pts;  eye.color = Color(0.85, 0.05, 0.05, 0.95)
		warden.add_child(eye)

		# Outer threat ring — dark red pulse border
		var ring_pts := PackedVector2Array()
		for j in 12:
			var a: float = TAU * float(j) / 12.0
			ring_pts.append(Vector2(cos(a), sin(a)) * 30.0)
		var wring := Polygon2D.new()
		wring.polygon = ring_pts;  wring.color = Color(0.6, 0.0, 0.0, 0.35)
		warden.add_child(wring)

		warden.set_meta("hp",    warden_hp)
		warden.set_meta("max_hp", warden_hp)
		warden.set_meta("speed",  48.0)      # slow and deliberate
		warden.set_meta("tier",   10)        # top tier for loot/kill logic
		warden.position = snap_pos
		add_child(warden)
		enemies_alive += 1

		warden.area_entered.connect(func(area):
			if is_instance_valid(warden): on_bullet_hit(warden, area)
		)

		# Big portal entrance + spin-in
		_spawn_portal(snap_pos)
		_animate_enemy_arrival(warden, snap_pos)
	)


func _spawn_mini_boss(pos: Vector2) -> void:
	var mini_hp: float = 100.0 * float(maxi(boss_rank, 1)) * 0.4
	var mb := Area2D.new()
	mb.add_to_group("enemies")
	mb.add_to_group("mini_boss")
	var pts := PackedVector2Array()
	for j in 7:
		var a: float = TAU * float(j) / 7.0
		pts.append(Vector2(cos(a), sin(a)) * 20.0)
	var ms := CollisionShape2D.new()
	var mc := CircleShape2D.new();  mc.radius = 20.0;  ms.shape = mc
	mb.add_child(ms)
	var poly := Polygon2D.new()
	poly.polygon = pts
	poly.color = Color(1.0, 0.4, 0.0)
	mb.add_child(poly)
	# Glow ring
	var ring := Polygon2D.new()
	var rpts := PackedVector2Array()
	for j in 12:
		var a: float = TAU * float(j) / 12.0
		rpts.append(Vector2(cos(a), sin(a)) * 26.0)
	ring.polygon = rpts;  ring.color = Color(1.0, 0.6, 0.0, 0.4)
	mb.add_child(ring)
	mb.set_meta("poly", poly)
	mb.set_meta("hp", mini_hp);  mb.set_meta("max_hp", mini_hp)
	mb.set_meta("speed", 65.0)
	mb.set_meta("tier", 10)
	mb.position = pos
	add_child(mb)
	enemies_alive += 1
	mb.area_entered.connect(func(area):
		if is_instance_valid(mb): on_bullet_hit(mb, area)
	)

# ─── Boss hit ─────────────────────────────────────────────────────────────────
func _on_boss_hit(blt: Area2D) -> void:
	if not is_instance_valid(boss_node):
		return
	var bn: Area2D = boss_node as Area2D
	var dmg: float = blt.get_meta("damage") if blt.has_meta("damage") else 1.0
	blt.queue_free()
	var hp: float = bn.get_meta("hp")
	hp -= dmg
	bn.set_meta("hp", hp)
	var max_hp: float = bn.get_meta("max_hp")
	var poly: Polygon2D = bn.get_meta("poly")
	var ratio: float = maxf(hp / max_hp, 0.0)
	poly.color = Color(0.3 + (1.0 - ratio) * 0.5, 0.0, ratio * 0.8)
	get_parent().get_node("Hud").update_boss_hp(maxf(hp, 0.0), max_hp)
	if hp <= 0.0:
		_on_boss_defeated()

# ─── Boss defeated ────────────────────────────────────────────────────────────
func _on_boss_defeated() -> void:
	var boss_pos: Vector2 = (boss_node as Node2D).global_position if is_instance_valid(boss_node) else castle_pos
	boss_alive = false
	if is_instance_valid(boss_node):
		(boss_node as Node).queue_free()
	boss_node = null
	var hud = get_parent().get_node("Hud")
	hud.hide_boss_bar()
	hud.add_kill()
	# Save checkpoint on every boss kill
	if hud.has_method("save_checkpoint"): hud.save_checkpoint()


	var player = get_parent().get_node_or_null("Player")

	# ── Boss death celebration — random fireworks for 3 seconds ──────────────
	if player != null and player.has_method("_spawn_fireworks"):
		var celebration_end: float = Time.get_ticks_msec() / 1000.0 + 5.0
		var hex_radius := 180.0   # ~3 hexes
		_boss_celebration(player, boss_pos, hex_radius, celebration_end)

	# ── Missile tree burst on boss kill — 3 waves if Heat Seeker + Explosive active
	if player != null and player.has_method("get_heat_seeker_level"):
		var hs_lvl: int  = player.get_heat_seeker_level()
		var exp_lvl: int = hud.skill_levels[7]
		if hs_lvl > 0 and exp_lvl > 0:
			for wave in range(3):
				var wcount: int = maxi(1, exp_lvl / 2)
				for i in wcount:
					var t: float = float(i) / float(maxi(wcount - 1, 1))
					var angle: float = lerp(0.0, 360.0, t) + float(wave) * 120.0
					var child_dir: Vector2 = Vector2.from_angle(deg_to_rad(angle + randf_range(-12.0, 12.0)))
					var hb := Area2D.new()
					hb.set_script(load("res://homing_bullet.gd"))
					hb.homing_level     = hs_lvl
					hb.bullet_speed     = 320.0
					hb.bullet_range     = 600.0
					hb.bullet_damage    = player.get_damage() * 0.8
					hb.initial_dir      = child_dir
					hb.explosive_radius = 0.0
					hb.explosive_lvl    = 0
					hb.bullet_color     = Color.from_hsv(float(i) / float(wcount), 1.0, 1.0)
					hb._coast_dist      = 60.0 + float(wave) * 30.0
					var hs := CollisionShape2D.new()
					var hc := CircleShape2D.new();  hc.radius = 4.0;  hs.shape = hc
					hb.add_child(hs)
					var hp2 := Polygon2D.new()
					hp2.color   = hb.bullet_color
					hp2.polygon = PackedVector2Array([Vector2(0,-5),Vector2(3,5),Vector2(-3,5)])
					hb.add_child(hp2)
					hb.global_position = boss_pos
					hb.rotation = child_dir.angle() + PI / 2.0
					get_parent().add_child(hb)

	if boss_rank >= 10:
		hud.show_you_win()
	else:
		towers_destroyed = 0
		tower_level += 1
		_spawn_enemy_towers()
		hud.update_tower_count(0, TOWERS_TOTAL)

# ─── Spawn enemy towers ───────────────────────────────────────────────────────
func _snap_to_valid_hex(world_pos: Vector2) -> Vector2:
	# Returns the nearest passable (NORMAL) hex center, searching outward ring by ring
	var hex_map = get_parent().get_node_or_null("HexMap")
	if hex_map == null:
		return world_pos
	var origin: Vector2i = hex_map.pixel_to_hex(world_pos)
	# Hex ring directions (cube coords)
	var ring_dirs := [
		Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(0, -1),
		Vector2i(1, -1), Vector2i(1,  0), Vector2i(0,  1)
	]
	for radius in range(0, 10):
		if radius == 0:
			if hex_map.get_hex_type(origin.x, origin.y) == 0:
				return hex_map.hex_to_pixel(origin.x, origin.y)
			continue
		# Start at the top of this ring
		var cur := Vector2i(origin.x + radius, origin.y - radius)
		for side in 6:
			for _step in radius:
				if hex_map.get_hex_type(cur.x, cur.y) == 0:
					return hex_map.hex_to_pixel(cur.x, cur.y)
				cur += ring_dirs[side]
	return world_pos   # fallback — shouldn't happen

func _make_et_hex(pos: Vector2, hp: float, is_center: bool, center_ref,
				  is_wall: bool = false) -> Area2D:
	return _make_et_outpost(pos, hp, is_center, center_ref, is_wall)

func _make_et_outpost(pos: Vector2, hp: float, is_center: bool, center_ref,
					  is_wall: bool = false) -> Area2D:
	# ── Color palette — dark slate / red / orange ────────────────────────────
	const SLATE_DARK  := Color(0.10, 0.11, 0.13, 1.0)
	const SLATE_MID   := Color(0.16, 0.17, 0.20, 1.0)
	const SLATE_LIGHT := Color(0.22, 0.23, 0.27, 1.0)
	const LED_RED     := Color(1.00, 0.13, 0.00, 0.95)
	const LED_ORANGE  := Color(1.00, 0.40, 0.00, 0.85)
	const LED_DIM     := Color(0.55, 0.10, 0.00, 0.45)
	const WALL_SLAB   := Color(0.07, 0.07, 0.09, 1.0)

	var t := Area2D.new()
	t.add_to_group("enemy_towers")
	if is_center:
		t.add_to_group("et_center")
	else:
		t.add_to_group("et_outer")
		if center_ref != null: t.set_meta("et_center_ref", center_ref)
	if is_wall:
		t.add_to_group("et_wall")

	var hs: float = 35.0   # HEX_SIZE
	var circ_shape := CollisionShape2D.new()
	var circ := CircleShape2D.new()
	circ.radius = hs - 2.0
	circ_shape.shape = circ
	t.add_child(circ_shape)

	var draw := Node2D.new()
	t.add_child(draw)

	var pts6 := func(r: float) -> PackedVector2Array:
		var p := PackedVector2Array()
		for j in 6:
			var a: float = deg_to_rad(60.0 * float(j) - 30.0)
			p.append(Vector2(cos(a), sin(a)) * r)
		return p

	if is_wall:
		# Solid reinforced wall slab
		var base_pts: PackedVector2Array = pts6.call(hs - 1.5)
		var d1 := Polygon2D.new();  d1.polygon = base_pts;  d1.color = WALL_SLAB
		draw.add_child(d1)
		var rim := Polygon2D.new();  rim.polygon = pts6.call(hs - 6.0)
		rim.color = Color(0.12, 0.12, 0.14)
		draw.add_child(rim)
		# Heavy orange border
		for i in 6:
			var a0 := deg_to_rad(60.0*float(i)-30.0)
			var a1 := deg_to_rad(60.0*float(i+1)-30.0)
			var v0 := Vector2(cos(a0),sin(a0))*(hs-2.0)
			var v1 := Vector2(cos(a1),sin(a1))*(hs-2.0)
			var ln := Line2D.new()
			ln.points = PackedVector2Array([v0,v1])
			ln.width = 3.0
			ln.default_color = LED_ORANGE if i%2==0 else LED_DIM
			draw.add_child(ln)
		# Wall cross hatching
		for xi in [-8, 0, 8]:
			var xl := Line2D.new()
			xl.points = PackedVector2Array([Vector2(float(xi),-20.0),Vector2(float(xi),20.0)])
			xl.width = 1.0;  xl.default_color = Color(0.18,0.18,0.22,0.6)
			draw.add_child(xl)
		# Wall label
		var wl := Label.new();  wl.text = "▦"
		wl.add_theme_font_size_override("font_size", 16)
		wl.add_theme_color_override("font_color", LED_ORANGE)
		wl.position = Vector2(-8, -10);  wl.size = Vector2(16, 20)
		draw.add_child(wl)
	elif is_center:
		# Center keep — same layered structure as player castle, dark palette
		var base_r: float = hs + 2.0
		var base_pts: PackedVector2Array = pts6.call(base_r)
		var bd := Polygon2D.new();  bd.polygon = base_pts;  bd.color = SLATE_DARK
		draw.add_child(bd)
		for layer in 3:
			var lr: float = base_r - 5.0 - float(layer)*6.0
			if lr < 7.0: break
			var lp := Polygon2D.new();  lp.polygon = pts6.call(lr)
			lp.color = SLATE_MID if layer==0 else SLATE_LIGHT if layer==1 else SLATE_MID
			draw.add_child(lp)
			var gap := Line2D.new()
			var gpts: PackedVector2Array = pts6.call(lr)
			gpts.append(gpts[0])
			gap.points = gpts;  gap.width = 1.2;  gap.default_color = SLATE_DARK
			draw.add_child(gap)
		# LED strips alternating red/orange
		for i in 6:
			var a0 := deg_to_rad(60.0*float(i)-30.0)
			var a1 := deg_to_rad(60.0*float(i+1)-30.0)
			var v0 := Vector2(cos(a0),sin(a0))*(base_r-0.5)
			var v1 := Vector2(cos(a1),sin(a1))*(base_r-0.5)
			var ln := Line2D.new()
			ln.points = PackedVector2Array([v0,v1])
			ln.width = 2.2
			ln.default_color = LED_RED if i%2==0 else LED_ORANGE
			draw.add_child(ln)
			var dot := Node2D.new();  draw.add_child(dot)
			var dc := Polygon2D.new()
			var dp := PackedVector2Array()
			for k in 6:
				var da := TAU*float(k)/6.0
				dp.append(Vector2(cos(da),sin(da))*2.2)
			dc.polygon = dp;  dc.color = LED_RED if i%2==0 else LED_ORANGE
			dot.position = v0;  dot.add_child(dc)
		# Power core — deep red
		var core_outer := Polygon2D.new();  core_outer.polygon = pts6.call(6.0)
		core_outer.color = SLATE_DARK;  draw.add_child(core_outer)
		var core_mid := Polygon2D.new();  core_mid.polygon = pts6.call(4.5)
		core_mid.color = LED_RED;  draw.add_child(core_mid)
		var core_in := Polygon2D.new();  core_in.polygon = pts6.call(2.2)
		core_in.color = Color(1.0, 0.7, 0.3, 0.95);  draw.add_child(core_in)
	else:
		# Outer turret hex — foundation + turret ring
		var fpts: PackedVector2Array = pts6.call(hs - 1.5)
		var fp := Polygon2D.new();  fp.polygon = fpts;  fp.color = SLATE_DARK
		draw.add_child(fp)
		# Inner plate
		var ip := Polygon2D.new();  ip.polygon = pts6.call(hs - 8.0);  ip.color = SLATE_MID
		draw.add_child(ip)
		# LED rim — alternate red/dim per edge
		for i in 6:
			var a0 := deg_to_rad(60.0*float(i)-30.0)
			var a1 := deg_to_rad(60.0*float(i+1)-30.0)
			var v0 := Vector2(cos(a0),sin(a0))*(hs-2.0)
			var v1 := Vector2(cos(a1),sin(a1))*(hs-2.0)
			var ln := Line2D.new()
			ln.points = PackedVector2Array([v0,v1])
			ln.width = 1.8
			ln.default_color = LED_RED if i%2==0 else LED_DIM
			draw.add_child(ln)
		# Turret barrel — small triangle pointing outward (random direction)
		var barrel_angle: float = randf() * TAU
		var bl := Line2D.new()
		bl.points = PackedVector2Array([Vector2.ZERO,
			Vector2(cos(barrel_angle),sin(barrel_angle))*14.0])
		bl.width = 3.5;  bl.default_color = LED_ORANGE
		draw.add_child(bl)
		var tip := Polygon2D.new()
		var tip_pts := PackedVector2Array()
		for k in 3:
			var ta := barrel_angle + deg_to_rad(90.0 + float(k)*120.0)
			tip_pts.append(Vector2(cos(barrel_angle),sin(barrel_angle))*14.0 + Vector2(cos(ta),sin(ta))*4.0)
		tip.polygon = tip_pts;  tip.color = LED_RED;  draw.add_child(tip)

	# Health bar (small, above hex)
	var hbar_bg := ColorRect.new()
	hbar_bg.size = Vector2(36.0, 4.0);  hbar_bg.position = Vector2(-18.0, -(hs+10.0))
	hbar_bg.color = Color(0.08,0.04,0.04)
	draw.add_child(hbar_bg)
	var hbar_fill := ColorRect.new()
	hbar_fill.size = Vector2(36.0, 4.0);  hbar_fill.position = Vector2(-18.0, -(hs+10.0))
	hbar_fill.color = LED_RED if not is_wall else LED_ORANGE
	draw.add_child(hbar_fill)
	t.set_meta("hbar_fill", hbar_fill)
	t.set_meta("hbar_max_w", 36.0)

	t.set_meta("poly", draw)
	t.set_meta("hp", hp)
	t.set_meta("max_hp", hp)
	t.set_meta("is_et_center", is_center)
	t.set_meta("is_wall", is_wall)
	t.position = pos
	add_child(t)
	return t

func _spawn_enemy_towers() -> void:
	for child in get_children():
		if child is Area2D and child.is_in_group("enemy_towers"):
			child.queue_free()
	var base_hp: float = TOWER_HP_BASE
	for _i in range(tower_level - 1):
		base_hp *= 1.5
	var outer_hp: float = base_hp * 0.6
	var center_hp: float = base_hp * 1.5
	# Pointy-top axial neighbor directions
	var hex_neighbors := [
		Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 1),
		Vector2i(-1, 0), Vector2i(0, -1), Vector2i(1, -1)
	]
	var hex_map = get_parent().get_node_or_null("HexMap")
	# ── Ring 2 neighbors (distance 2 from center in hex space) ───────────────
	var ring2_dirs: Array = []
	for q in range(-2, 3):
		for r in range(-2, 3):
			var d: int = maxi(abs(q), maxi(abs(r), abs(q+r)))
			if d == 2: ring2_dirs.append(Vector2i(q, r))

	# ── Border-proximity target positions (evenly around border) ─────────────
	var border_targets: Array = []
	if hex_map != null:
		var qr: int = hex_map.Q_RANGE;  var rr: int = hex_map.R_RANGE
		var BORDER_INSET := 10   # hexes inside the border
		# 5 cardinal/diagonal positions near the border
		var border_anchors := [
			Vector2i(qr - BORDER_INSET, -(rr - BORDER_INSET) / 2),    # NE
			Vector2i(qr - BORDER_INSET,  (rr - BORDER_INSET) / 2),    # SE
			Vector2i(0,                   rr - BORDER_INSET),          # S
			Vector2i(-(qr - BORDER_INSET),(rr - BORDER_INSET) / 2),   # SW
			Vector2i(-(qr - BORDER_INSET),-(rr - BORDER_INSET) / 2),  # NW
		]
		border_targets = border_anchors
		# Validate each anchor — find nearest NORMAL hex
		for ai in border_targets.size():
			var raw_hex: Vector2i = border_targets[ai]
			var best := raw_hex;  var found := false
			for radius in range(0, 14):
				if radius == 0:
					if hex_map.get_hex_type(raw_hex.x, raw_hex.y) == 0:
						best = raw_hex;  found = true;  break
				else:
					var rdirs := [Vector2i(-1,1),Vector2i(-1,0),Vector2i(0,-1),
								  Vector2i(1,-1),Vector2i(1,0),Vector2i(0,1)]
					var cur := Vector2i(raw_hex.x+radius, raw_hex.y-radius)
					for side in 6:
						for _step in radius:
							if hex_map.get_hex_type(cur.x, cur.y) == 0:
								best = cur;  found = true;  break
							cur += rdirs[side]
						if found: break
					if found: break
			border_targets[ai] = best
	else:
		# Fallback if no hex_map
		for i in TOWERS_TOTAL:
			var angle := TAU * float(i) / float(TOWERS_TOTAL)
			border_targets.append(Vector2i(0,0))

	for i in range(TOWERS_TOTAL):
		var center_hex: Vector2i = border_targets[i]
		var center_pos: Vector2 = hex_map.hex_to_pixel(center_hex.x, center_hex.y) if hex_map != null 			else castle_pos + Vector2(cos(TAU*float(i)/float(TOWERS_TOTAL)),
									 sin(TAU*float(i)/float(TOWERS_TOTAL)))*TOWER_RING_RADIUS

		# ── Variable turret count: 3–18 ─────────────────────────────────────
		var turret_count: int = randi_range(3, 18)
		# 20% chance one ring-1 slot is a wall
		var has_wall: bool = randf() < 0.20
		var wall_slot: int = randi() % 6 if has_wall else -1

		var center_node := _make_et_hex(center_pos, center_hp, true, null)

		# ── Ring 1 — fill random subset ─────────────────────────────────────
		var r1_slots := hex_neighbors.duplicate();  r1_slots.shuffle()
		var r1_fill: int = mini(turret_count, 6)
		var r1_placed: int = 0
		for ni in 6:
			if r1_placed >= r1_fill: break
			var nb: Vector2i = r1_slots[ni]
			var nb_hex: Vector2i = center_hex + nb
			if hex_map != null and hex_map.get_hex_type(nb_hex.x, nb_hex.y) != 0: continue
			var nb_pos: Vector2 = hex_map.hex_to_pixel(nb_hex.x, nb_hex.y) if hex_map != null 				else center_pos + Vector2(cos(TAU*float(ni)/6.0),sin(TAU*float(ni)/6.0))*60.0
			var is_wall_slot: bool = has_wall and ni == wall_slot
			var slot_hp: float = outer_hp * 3.0 if is_wall_slot else outer_hp
			_make_et_hex(nb_pos, slot_hp, false, center_node, is_wall_slot)
			r1_placed += 1

		# ── Ring 2 — fill remaining count ───────────────────────────────────
		if turret_count > 6 and hex_map != null:
			var r2_need: int = turret_count - r1_placed
			var r2_slots := ring2_dirs.duplicate();  r2_slots.shuffle()
			var r2_placed: int = 0
			for r2nb in r2_slots:
				if r2_placed >= r2_need: break
				var r2_hex: Vector2i = center_hex + (r2nb as Vector2i)
				if hex_map.get_hex_type(r2_hex.x, r2_hex.y) != 0: continue
				var r2_pos: Vector2 = hex_map.hex_to_pixel(r2_hex.x, r2_hex.y)
				_make_et_hex(r2_pos, outer_hp * 0.7, false, center_node)
				r2_placed += 1

		# ── Crescent arena — carve pits on flanks ───────────────────────────
		if hex_map != null and hex_map.has_method("carve_et_arena"):
			hex_map.carve_et_arena(center_hex)

# ─── Spawn boss ───────────────────────────────────────────────────────────────
func spawn_boss() -> void:
	boss_rank += 1
	var max_hp: float = 100.0 * float(boss_rank)
	var bn := Area2D.new()
	bn.add_to_group("boss_enemy")
	var pts := PackedVector2Array()
	for j in range(8):
		var a: float = TAU * float(j) / 8.0
		pts.append(Vector2(cos(a), sin(a)) * 28.0)
	var boss_shape := CollisionShape2D.new()
	var boss_circ := CircleShape2D.new()
	boss_circ.radius = 28.0
	boss_shape.shape = boss_circ
	bn.add_child(boss_shape)
	var poly := Polygon2D.new()
	poly.polygon = pts
	poly.color = Color(0.5, 0.0, 0.85)
	bn.add_child(poly)
	bn.set_meta("poly", poly)

	# ── Cyber eye ──────────────────────────────────────────────────────────────
	var eye_node := Node2D.new()
	eye_node.z_index = 2;  eye_node.z_as_relative = true
	bn.add_child(eye_node)
	# Outer eye ring
	var eye_ring := Polygon2D.new()
	var er_pts := PackedVector2Array()
	for i in 14:
		var a: float = TAU * float(i) / 14.0
		er_pts.append(Vector2(cos(a), sin(a)) * 11.0)
	eye_ring.polygon = er_pts;  eye_ring.color = Color(0.08, 0.0, 0.12)
	eye_node.add_child(eye_ring)
	# Iris
	var iris := Polygon2D.new()
	var iris_pts := PackedVector2Array()
	for i in 12:
		var a: float = TAU * float(i) / 12.0
		iris_pts.append(Vector2(cos(a), sin(a)) * 7.5)
	iris.polygon = iris_pts;  iris.color = Color(0.85, 0.0, 0.05)
	eye_node.add_child(iris)
	# Pupil (moves to track player)
	var pupil := Polygon2D.new()
	var pu_pts := PackedVector2Array()
	for i in 8:
		var a: float = TAU * float(i) / 8.0
		pu_pts.append(Vector2(cos(a), sin(a)) * 3.2)
	pupil.polygon = pu_pts;  pupil.color = Color(1.0, 0.9, 0.9)
	eye_node.add_child(pupil)
	# Glow ring
	var glow := Polygon2D.new()
	var glow_pts := PackedVector2Array()
	for i in 14:
		var a: float = TAU * float(i) / 14.0
		glow_pts.append(Vector2(cos(a), sin(a)) * 14.0)
	glow.polygon = glow_pts;  glow.color = Color(0.85, 0.0, 0.05, 0.25)
	eye_node.add_child(glow)
	bn.set_meta("eye_node", eye_node)
	bn.set_meta("iris",     iris)
	bn.set_meta("pupil",    pupil)
	bn.set_meta("glow",     glow)
	# Aura rings
	for ar in 3:
		var aura := Polygon2D.new()
		var aura_pts := PackedVector2Array()
		for i in 16:
			var a: float = TAU * float(i) / 16.0
			aura_pts.append(Vector2(cos(a), sin(a)) * (32.0 + float(ar) * 12.0))
		aura.polygon = aura_pts
		aura.color = Color(0.5, 0.0, 0.85, 0.08 - float(ar) * 0.02)
		bn.add_child(aura)
	bn.set_meta("hp", max_hp)
	bn.set_meta("max_hp", max_hp)
	bn.set_meta("fire_timer", 0.0)
	var angle: float = randf() * TAU
	bn.position = castle_pos + Vector2(cos(angle), sin(angle)) * 460.0
	add_child(bn)
	boss_node = bn
	boss_alive = true

	var hud = get_parent().get_node("Hud")
	hud.update_boss_hp(max_hp, max_hp)
	hud.show_boss_warning(boss_rank)

	# ── Trigger Tron Flip cascade ─────────────────────────────────────────
	# Boss stays hidden until cascade wave passes its hex — then reveals
	bn.visible = false
	var hex_map = get_parent().get_node_or_null("HexMap")
	var player  = get_parent().get_node_or_null("Player")
	if hex_map != null and hex_map.has_method("trigger_tron_flip") and player != null:
		var boss_world_pos: Vector2 = (castle_pos + Vector2(cos(angle), sin(angle)) * 460.0)
		var player_hex = hex_map.pixel_to_hex(player.global_position)
		var boss_hex   = hex_map.pixel_to_hex(boss_world_pos)
		var boss_ring: int = hex_map._hex_dist_vi(boss_hex, player_hex)

		# Reveal boss when cascade ring reaches its position
		# Ring fires at delay = (ring/max_ring) × 10s — approximate with timer
		var reveal_delay: float = float(boss_ring) / float(maxi(1, 50)) * 10.0
		reveal_delay = clampf(reveal_delay, 0.5, 9.5)
		get_tree().create_timer(reveal_delay).timeout.connect(func():
			if is_instance_valid(bn): bn.visible = true
		)

		hex_map.trigger_tron_flip(player.global_position, func():
			# Cascade complete — boss already visible, combat resumes
			pass
		)
	else:
		# Fallback — no HexMap, just show boss immediately
		bn.visible = true

# ─── Spawn enemy ──────────────────────────────────────────────────────────────
# ─── Enemy tier data ─────────────────────────────────────────────────────────
# [hp, speed, size_mult, color, shape_sides]
# shape_sides: 3=triangle, 4=diamond, 5=pentagon, 6=hexagon
const ENEMY_TIERS: Array = [
	[  3.0,  80.0, 1.0, "ff2222", 3],   # tier 1 — red triangle
	[  4.0,  85.0, 1.0, "ff5511", 3],   # tier 2 — orange-red
	[  6.0,  88.0, 1.1, "ff7700", 3],   # tier 3 — orange
	[  8.0,  92.0, 1.1, "ffaa00", 3],   # tier 4 — amber
	[ 12.0,  95.0, 1.2, "dddd00", 4],   # tier 5 — yellow diamond
	[ 16.0,  98.0, 1.2, "88dd00", 4],   # tier 6 — yellow-green diamond
	[ 22.0, 102.0, 1.3, "00ddcc", 5],   # tier 7 — cyan pentagon
	[ 30.0, 106.0, 1.3, "0088ff", 5],   # tier 8 — blue pentagon
	[ 40.0, 110.0, 1.5, "aa00ff", 6],   # tier 9 — purple hexagon
	[ 55.0, 115.0, 1.6, "ff00cc", 6],   # tier 10 — magenta elite hexagon
]

func _get_max_tier() -> int:
	# Tier pool grows with boss rank: rank 0→2, 1→4, 2→6, 3→8, 4+→10
	return mini(10, 2 + boss_rank * 2)

func spawn_enemy() -> void:
	# Pick spawn origin — random living ET hex or fallback to center ring
	var et_list: Array = get_tree().get_nodes_in_group("enemy_towers")
	var spawn_origin: Vector2 = castle_pos
	if et_list.size() > 0:
		var et = et_list[randi() % et_list.size()]
		if is_instance_valid(et): spawn_origin = (et as Node2D).position
	var angle: float = randf() * TAU
	var raw_pos: Vector2 = spawn_origin + Vector2(cos(angle), sin(angle)) * randf_range(180.0, 280.0)
	var snap_pos: Vector2 = _snap_to_valid_hex(raw_pos)
	var enemy = _create_enemy_at(snap_pos)
	if enemy != null:
		_spawn_portal(snap_pos)
		add_child(enemy)
		enemies_alive += 1
		_animate_enemy_arrival(enemy, snap_pos)

func on_bullet_hit(enemy: Area2D, area: Area2D) -> void:
	if not area.is_in_group("bullet"):
		return
	if area.has_meta("no_hit"):
		return
	if not is_instance_valid(enemy):
		return
	if not enemy.has_meta("hp"):
		return
	# Piercing frags keep flying — mark hit on this enemy to avoid double damage
	if area.has_meta("piercing"):
		var hit_key: String = "pierced_" + str(enemy.get_instance_id())
		if area.has_meta(hit_key):
			return
		area.set_meta(hit_key, true)
	else:
		area.queue_free()
	var dmg: float = area.get_meta("damage") if area.has_meta("damage") else 1.0
	var hp: float = enemy.get_meta("hp")
	hp -= dmg
	enemy.set_meta("hp", hp)
	var poly: Polygon2D = enemy.get_meta("poly")
	var max_hp: float = enemy.get_meta("max_hp") if enemy.has_meta("max_hp") else 3.0
	var ratio: float = clampf(hp / max_hp, 0.0, 1.0)
	poly.color = poly.color.lerp(Color.WHITE, 0.5 * (1.0 - ratio))   # brightens as damaged
	if area.has_meta("knockback"):
		var kb: Dictionary = area.get_meta("knockback")
		var kb_dir: Vector2 = (enemy.position - castle_pos).normalized()
		enemy.set_meta("slow", kb["slow"])
		enemy.set_meta("slow_timer", kb["duration"])
		if kb["push"] > 0:
			enemy.position += kb_dir * float(kb["push"])
	if hp <= 0.0:
		var hud = get_parent().get_node("Hud")
		hud.add_kill()
		enemies_alive -= 1
		# FURY power-up — set speed burst timer on player
		var _player_fury = get_parent().get_node_or_null("Player")
		if _player_fury != null and _player_fury.has_meta("fury_active"):
			_player_fury.set_meta("fury_timer", 0.8)
		var gm_lvl: int = hud.skill_levels[10]
		var coins := 1
		if gm_lvl <= 3:
			coins = 1 + gm_lvl
		var gold_mult: float = 1.0 + (gm_lvl * 0.25)
		hud.add_gold(ceili(coins * gold_mult))
		if gm_lvl >= 7:
			var drop_chance: float = 0.05 + (gm_lvl - 7) * 0.05
			if randf() < drop_chance:
				hud.add_node_fragment(1)
		if area.has_meta("split_level") and area.get_meta("split_level") > 0:
			spawn_fragment(enemy.position, (enemy.position - castle_pos).normalized(), dmg, area.get_meta("split_level"))
		if area.has_meta("explosive_radius"):
			var chain: bool = area.get_meta("explosive_lvl") == 10
			trigger_explosion(enemy.position, area.get_meta("explosive_radius"), dmg / 2.0, chain)
		# ── Heat Seeker LV10 — big rainbow explosion on kill ─────────────────
		if area.has_meta("homing_level") and area.get_meta("homing_level") == 10:
			var player = get_parent().get_node_or_null("Player")
			if player != null and player.has_method("_spawn_homing_explosion"):
				player._spawn_homing_explosion(enemy.position, dmg)
		_spawn_crater(enemy.position)
		_spawn_shockwave(enemy.position)
		enemy.queue_free()

# ─── Spawn fragment ───────────────────────────────────────────────────────────
func spawn_fragment(pos: Vector2, dir: Vector2, dmg: float, split_level: int) -> void:
	if split_level <= 0:
		return

	# ── Tier logic ────────────────────────────────────────────────────────────
	# LV1-3: BURST  — tight cone ±15°, frag count = 2 + (lvl-1)
	# LV4-6: SHOTGUN — random ±60°, also chains split on frag hit
	# LV7-9: PIERCING — even 180° arc spread, frags pierce
	# LV10:  HEAT SYNC — frags become mini homing bullets
	var frag_count: int
	var is_burst:    bool = split_level <= 3
	var is_shotgun:  bool = split_level >= 4 and split_level <= 6
	var is_piercing: bool = split_level >= 7 and split_level <= 9
	var is_heatsync: bool = split_level == 10

	if is_burst:
		frag_count = 1 + split_level   # LV1=2, LV2=3, LV3=4
	elif is_shotgun:
		frag_count = 2 + (split_level - 4)   # LV4=2, LV5=3, LV6=4
	elif is_piercing:
		frag_count = 2 + (split_level - 7)   # LV7=2, LV8=3, LV9=4
	else:
		frag_count = 4   # HEAT SYNC always 4

	var frag_dmg: float = dmg * 0.5
	var next_split: int = split_level - 1 if not is_heatsync else 0

	for i in range(frag_count):
		# ── Direction per tier ────────────────────────────────────────────────
		var spread_dir: Vector2
		if is_burst:
			var a: float = randf_range(-15.0, 15.0)
			spread_dir = dir.rotated(deg_to_rad(a))
		elif is_shotgun:
			var a: float = randf_range(-60.0, 60.0)
			spread_dir = dir.rotated(deg_to_rad(a))
		elif is_piercing:
			# Evenly spread across 180° arc
			var step: float = 180.0 / float(frag_count - 1) if frag_count > 1 else 0.0
			var a: float = -90.0 + step * float(i)
			spread_dir = dir.rotated(deg_to_rad(a))
		else:
			# HEAT SYNC — equal spacing, homing handles targeting
			var a: float = (360.0 / float(frag_count)) * float(i)
			spread_dir = dir.rotated(deg_to_rad(a))

		# ── HEAT SYNC: spawn as homing bullet ────────────────────────────────
		if is_heatsync:
			var hb := Area2D.new()
			hb.set_script(load("res://homing_bullet.gd"))
			hb.homing_level  = 10
			hb.bullet_speed  = 320.0
			hb.bullet_range  = 300.0
			hb.bullet_damage = frag_dmg
			hb.initial_dir   = spread_dir
			var hs := CollisionShape2D.new()
			var hc := CircleShape2D.new();  hc.radius = 4.0;  hs.shape = hc
			hb.add_child(hs)
			var hp2 := Polygon2D.new()
			hp2.polygon = PackedVector2Array([Vector2(0,-4),Vector2(3,4),Vector2(-3,4)])
			hp2.color = Color.from_hsv(randf(), 1.0, 1.0)
			hb.add_child(hp2)
			hb.global_position = pos
			get_parent().add_child(hb)
			continue

		# ── Standard fragment ─────────────────────────────────────────────────
		var frag := Area2D.new()
		frag.add_to_group("bullet")
		frag.set_meta("damage", frag_dmg)
		frag.set_meta("split_level", next_split)
		frag.set_meta("explosive_radius", 0.0)
		frag.set_meta("explosive_lvl", 0)
		frag.set_meta("knockback", {"slow": 0.0, "duration": 0.0, "push": 0})
		# Piercing frags marked so on_bullet_hit skips queue_free
		if is_piercing:
			frag.set_meta("piercing", true)
		var shape := CollisionShape2D.new()
		var circle := CircleShape2D.new();  circle.radius = 4.0;  shape.shape = circle
		frag.add_child(shape)
		var poly := Polygon2D.new()
		poly.polygon = PackedVector2Array([Vector2(0,-5), Vector2(3,5), Vector2(-3,5)])
		# Color by tier
		if is_burst:    poly.color = Color(0.4, 0.9, 1.0)    # cyan
		elif is_shotgun: poly.color = Color(1.0, 0.6, 0.1)   # orange
		else:           poly.color = Color(0.7, 0.3, 1.0)    # purple pierce
		frag.add_child(poly)
		frag.position = pos
		get_parent().add_child(frag)
		# BURST fires in rapid staggered succession — small delay per frag
		var delay: float = float(i) * 0.04 if is_burst else 0.0
		var travel_dist: float = 250.0 + float(split_level) * 20.0
		var travel_time: float = 0.35
		var tween := get_tree().create_tween()
		if delay > 0.0:
			tween.tween_interval(delay)
		tween.tween_property(frag, "global_position", pos + spread_dir * travel_dist, travel_time)
		tween.tween_callback(frag.queue_free)
		var captured_frag = frag
		captured_frag.area_entered.connect(func(area):
			if is_instance_valid(captured_frag): on_bullet_hit(captured_frag, area)
		)

# ─── Boss celebration fireworks ───────────────────────────────────────────────
func _boss_celebration(player: Node, origin: Vector2, radius: float, end_time: float) -> void:
	if Time.get_ticks_msec() / 1000.0 >= end_time:
		return
	if not is_instance_valid(player):
		return
	# Random position within radius of origin
	var angle: float = randf() * TAU
	var dist: float  = randf() * radius
	var bpos: Vector2 = origin + Vector2(cos(angle), sin(angle)) * dist
	var bcolor: Color = Color.from_hsv(randf(), 1.0, 1.0)
	player._spawn_fireworks(bpos, 10, bcolor, randf_range(60.0, 140.0))
	# Schedule next burst at a random short interval (0.15–0.35s)
	var next_delay: float = randf_range(0.15, 0.35)
	if is_inside_tree():
		get_tree().create_timer(next_delay).timeout.connect(func():
			if not is_instance_valid(self): return
			_boss_celebration(player, origin, radius, end_time)
		)

# ─── Trigger explosion ────────────────────────────────────────────────────────
func trigger_explosion(pos: Vector2, radius: float, dmg: float, chain: bool) -> void:
	if radius <= 0.0:
		return
	for enemy in get_children():
		if not enemy is Area2D:
			continue
		if not enemy.is_in_group("enemies"):
			continue
		if (enemy as Area2D).position.distance_to(pos) <= radius:
			var hp: float = (enemy as Area2D).get_meta("hp")
			hp -= dmg
			(enemy as Area2D).set_meta("hp", hp)
			if hp <= 0.0:
				var hud = get_parent().get_node("Hud")
				hud.add_kill()
				enemies_alive -= 1
				if chain:
					trigger_explosion((enemy as Area2D).position, radius, dmg / 2.0, false)
				enemy.queue_free()

# ─── Turret kill ──────────────────────────────────────────────────────────────
func handle_turret_kill(enemy: Area2D) -> void:
	if not is_instance_valid(enemy):
		return
	var hud = get_parent().get_node("Hud")
	hud.add_kill()
	enemies_alive -= 1
	var gm_lvl: int = hud.skill_levels[10]
	var coins := 1
	if gm_lvl <= 3:
		coins = 1 + gm_lvl
	var gold_mult: float = 1.0 + (gm_lvl * 0.25)
	hud.add_gold(ceili(coins * gold_mult))
	_spawn_crater(enemy.position)
	_spawn_shockwave(enemy.position)
	enemy.queue_free()

# ─── Enemy death crater (starburst) ──────────────────────────────────────────
func _spawn_crater(pos: Vector2) -> void:
	var crater := Node2D.new()
	# Starburst — alternating spike points, charred colors
	var spikes := 10
	var r_outer := 32.0
	var r_inner := 14.0
	var pts := PackedVector2Array()
	for i in spikes * 2:
		var a: float = TAU * float(i) / float(spikes * 2) - PI / 2.0
		var r: float = r_outer if i % 2 == 0 else r_inner
		pts.append(Vector2(cos(a), sin(a)) * r)
	var star := Polygon2D.new()
	star.polygon = pts
	star.color = Color(0.10, 0.05, 0.03, 0.9)   # charred dark brown
	crater.add_child(star)
	# Ember glow center
	var cpts := PackedVector2Array()
	for i in 8:
		var a: float = TAU * float(i) / 8.0
		cpts.append(Vector2(cos(a), sin(a)) * 8.0)
	var center := Polygon2D.new()
	center.polygon = cpts
	center.color = Color(0.7, 0.18, 0.02, 0.85)   # deep ember orange
	crater.add_child(center)
	crater.global_position = pos
	crater.z_index = -10
	crater.z_as_relative = false
	get_parent().add_child(crater)
	var tween := get_tree().create_tween()
	tween.tween_property(crater, "modulate:a", 0.0, 10.0)
	tween.tween_callback(crater.queue_free)

# ─── Kill shockwave ───────────────────────────────────────────────────────────
func _spawn_shockwave(pos: Vector2) -> void:
	var wave := Node2D.new()
	var seg := 18
	var pts := PackedVector2Array()
	for i in seg:
		var a: float = TAU * float(i) / float(seg)
		pts.append(Vector2(cos(a), sin(a)) * 10.0)
	var poly := Polygon2D.new()
	poly.polygon = pts
	poly.color = Color(1.0, 0.6, 0.15, 0.75)
	wave.add_child(poly)
	wave.global_position = pos
	wave.z_index = 6
	wave.z_as_relative = false
	get_parent().add_child(wave)
	var tween := get_tree().create_tween()
	tween.set_parallel(true)
	tween.tween_property(wave, "scale", Vector2(4.5, 4.5), 0.3)
	tween.tween_property(poly, "color", Color(1.0, 0.6, 0.15, 0.0), 0.3)
	tween.set_parallel(false)
	tween.tween_callback(wave.queue_free)

# ─── Spawn portal — enemy arrives from the future ────────────────────────────
func _spawn_portal(pos: Vector2) -> void:
	# ── Neighboring tile flash — void pulse on surrounding hexes ─────────────
	var hex_map = get_parent().get_node_or_null("HexMap")
	if hex_map != null:
		var center_hex: Vector2i = hex_map.pixel_to_hex(pos)
		for nb in [Vector2i(1,0), Vector2i(0,1), Vector2i(-1,1),
				Vector2i(-1,0), Vector2i(0,-1), Vector2i(1,-1)]:
			var nhpos: Vector2 = hex_map.hex_to_pixel(
				(center_hex + nb).x, (center_hex + nb).y)
			var tf_node := Node2D.new()
			tf_node.z_index = 1;  tf_node.z_as_relative = false
			var tpoly := Polygon2D.new()
			var tpts := PackedVector2Array()
			for i in 6:
				var a: float = deg_to_rad(60.0 * float(i) - 30.0)
				tpts.append(Vector2(cos(a), sin(a)) * 32.0)
			tpoly.polygon = tpts;  tpoly.color = Color(0.0, 0.0, 0.0, 0.0)
			tf_node.add_child(tpoly);  tf_node.global_position = nhpos
			get_parent().add_child(tf_node)
			var tf := get_tree().create_tween()
			tf.tween_property(tpoly, "color", Color(0.30, 0.0, 0.60, 0.75), 0.15)
			tf.tween_property(tpoly, "color", Color(0.02, 0.0, 0.06, 0.88), 0.30)
			tf.tween_property(tpoly, "color", Color(0.0,  0.0, 0.0,  0.0),  0.55)
			tf.tween_callback(tf_node.queue_free)

	# ── Portal node ───────────────────────────────────────────────────────────
	var portal := Node2D.new()
	portal.global_position = pos
	portal.z_index = 4;  portal.z_as_relative = false
	portal.scale = Vector2(0.08, 0.08)
	get_parent().add_child(portal)

	# Black void center
	var void_pts := PackedVector2Array()
	for i in 14:
		var a: float = TAU * float(i) / 14.0
		void_pts.append(Vector2(cos(a), sin(a)) * 11.0)
	var void_poly := Polygon2D.new()
	void_poly.polygon = void_pts
	void_poly.color   = Color(0.0, 0.0, 0.0, 1.0)
	portal.add_child(void_poly)

	# 4 spiral arc blades — thick arc bands at 90° offsets, alternating purple/black
	# Each blade is a partial ring arc (inner r=13, outer r=38, 90° sweep)
	var blade_colors := [
		Color(0.42, 0.0, 0.82, 0.92),   # deep purple
		Color(0.04, 0.0, 0.10, 0.96),   # near-black
		Color(0.42, 0.0, 0.82, 0.92),
		Color(0.04, 0.0, 0.10, 0.96),
	]
	var blade_polys: Array = []
	for bi in 4:
		var base_angle: float = TAU * float(bi) / 4.0 + PI / 8.0
		var arc_span: float   = PI * 0.52   # ~94 degrees
		var r_in  := 13.0
		var r_out := 38.0
		var steps := 10
		var bpts  := PackedVector2Array()
		for si in steps + 1:
			var a: float = base_angle + arc_span * float(si) / steps
			bpts.append(Vector2(cos(a), sin(a)) * r_out)
		for si in steps + 1:
			var a: float = base_angle + arc_span * float(steps - si) / steps
			bpts.append(Vector2(cos(a), sin(a)) * r_in)
		var bp := Polygon2D.new()
		bp.polygon = bpts
		bp.color   = blade_colors[bi]
		portal.add_child(bp)
		blade_polys.append(bp)

	# Outer accent ring (thin, always purple, provides edge definition)
	var oring_pts := PackedVector2Array()
	for i in 20:
		var a: float = TAU * float(i) / 20.0
		oring_pts.append(Vector2(cos(a), sin(a)) * 40.0)
	var oring := Polygon2D.new()
	oring.polygon = oring_pts
	oring.color   = Color(0.35, 0.0, 0.65, 0.55)
	portal.add_child(oring)

	# Pop in fast
	var pop := get_tree().create_tween()
	pop.tween_property(portal, "scale", Vector2(1.0, 1.0), 0.20)

	# Blade pulse — each blade alternates between its color and near-black
	# with a 0.15s phase offset, creating a rolling wave from blade to blade
	for bi in blade_polys.size():
		var bp: Polygon2D = blade_polys[bi]
		var full_col: Color  = blade_colors[bi]
		var dark_col: Color  = Color(0.02, 0.0, 0.05, 0.94)
		var phase_off: float = float(bi) * 0.15
		var _pulse: Callable
		var going_dark: bool = (bi % 2 == 0)
		_pulse = func():
			if not is_instance_valid(self) or not is_instance_valid(portal): return
			var target: Color = dark_col if going_dark else full_col
			going_dark = not going_dark
			var pt := get_tree().create_tween()
			pt.tween_property(bp, "color", target, 0.4)
			pt.tween_callback(_pulse)
		if is_inside_tree(): get_tree().create_timer(phase_off).timeout.connect(_pulse)

	# After SPIN_DURATION the enemy leaves — portal converts to corruption crater
	var SPIN_DURATION: float = 0.52
	get_tree().create_timer(SPIN_DURATION + 0.1).timeout.connect(func():
		if not is_instance_valid(self) or not is_instance_valid(portal): return
		# Quick fade-out of portal visual
		var ftw := get_tree().create_tween()
		ftw.tween_property(portal, "modulate:a", 0.0, 0.3)
		ftw.tween_callback(portal.queue_free)
		# Spawn lingering corruption crater at the same position
		_spawn_corruption_crater(pos)
	)

# ─── Corruption crater — trans-dimensional void scar left after portal ────────
func _spawn_corruption_crater(pos: Vector2) -> void:
	var crater := Node2D.new()
	crater.global_position = pos
	crater.z_index = 2;  crater.z_as_relative = false
	get_parent().add_child(crater)

	# Dark void center — solid black circle (3× larger than before)
	var vpts := PackedVector2Array()
	for i in 10:
		var a: float = TAU * float(i) / 10.0
		vpts.append(Vector2(cos(a), sin(a)) * 27.0)
	var vpoly := Polygon2D.new()
	vpoly.polygon = vpts;  vpoly.color = Color(0.0, 0.0, 0.0, 0.95)
	crater.add_child(vpoly)

	# 7 void crack lines — jagged, long
	var crack_dirs := [0.0, 0.9, 1.8, 2.7, 3.6, 4.5, 5.4]
	for cd in crack_dirs:
		var crack_pts := PackedVector2Array()
		# Start at void edge
		crack_pts.append(Vector2(cos(cd), sin(cd)) * 24.0)
		var seg_len: float = randf_range(54.0, 96.0)
		var jag: float = randf_range(-0.22, 0.22)
		crack_pts.append(Vector2(cos(cd + jag), sin(cd + jag)) * seg_len)
		# Secondary fork on half the cracks
		if randf() > 0.5:
			var fork_pts := PackedVector2Array()
			fork_pts.append(crack_pts[0].lerp(crack_pts[1], 0.55))
			var fork_jag: float = randf_range(-0.4, 0.4)
			fork_pts.append(Vector2(cos(cd + fork_jag), sin(cd + fork_jag)) * randf_range(30.0, 55.0))
			var fline := Line2D.new()
			fline.points = fork_pts
			fline.width  = randf_range(1.5, 2.8)
			fline.default_color = Color(0.22, 0.0, 0.42, 0.65)
			crater.add_child(fline)
		var cline := Line2D.new()
		cline.points = crack_pts
		cline.width  = randf_range(3.5, 6.5)
		cline.default_color = Color(0.30, 0.0, 0.55, 0.82)
		crater.add_child(cline)

	# Mid glow ring
	var gpts := PackedVector2Array()
	for i in 20:
		var a: float = TAU * float(i) / 20.0
		gpts.append(Vector2(cos(a), sin(a)) * 42.0)
	var gpoly := Polygon2D.new()
	gpoly.polygon = gpts;  gpoly.color = Color(0.28, 0.0, 0.50, 0.42)
	crater.add_child(gpoly)

	# Outer diffuse ring
	var opts := PackedVector2Array()
	for i in 24:
		var a: float = TAU * float(i) / 24.0
		opts.append(Vector2(cos(a), sin(a)) * 68.0)
	var opoly := Polygon2D.new()
	opoly.polygon = opts;  opoly.color = Color(0.18, 0.0, 0.34, 0.22)
	crater.add_child(opoly)

	# Flicker then long slow fade over ~10 seconds
	var ftw := get_tree().create_tween()
	ftw.tween_property(crater, "modulate:a", 0.6, 0.35)
	ftw.tween_property(crater, "modulate:a", 1.0, 0.2)
	ftw.tween_property(crater, "modulate:a", 0.7, 0.3)
	ftw.tween_property(crater, "modulate:a", 0.0, 9.5)
	ftw.tween_callback(crater.queue_free)

# ─── Enemy arrival animation: spin-in → stop → light shockwave ───────────────
func _animate_enemy_arrival(enemy: Area2D, portal_pos: Vector2) -> void:
	if not is_instance_valid(enemy): return
	enemy.set_meta("arriving", true)
	enemy.scale    = Vector2(0.05, 0.05)
	enemy.rotation = 0.0
	var SPIN: float = 0.50
	var tw := get_tree().create_tween()
	tw.set_parallel(true)
	tw.tween_property(enemy, "scale",    Vector2(1.0, 1.0), SPIN)
	tw.tween_property(enemy, "rotation", TAU * 2.5,          SPIN)
	tw.set_parallel(false)
	tw.tween_property(enemy, "rotation", 0.0, 0.05)
	tw.tween_callback(func():
		if is_instance_valid(enemy):
			enemy.set_meta("arriving", false)
			_spawn_arrival_flash(portal_pos)
	)

func _spawn_arrival_flash(pos: Vector2) -> void:
	# Two white light shockwave rings expanding from portal position
	for wave in 2:
		var delay: float = float(wave) * 0.09
		get_tree().create_timer(delay).timeout.connect(func():
			var ring := Node2D.new()
			ring.global_position = pos
			ring.z_index = 6;  ring.z_as_relative = false
			var rpts := PackedVector2Array()
			var base_r: float = 10.0 + float(wave) * 7.0
			for i in 22:
				var a: float = TAU * float(i) / 22.0
				rpts.append(Vector2(cos(a), sin(a)) * base_r)
			var rpoly := Polygon2D.new()
			rpoly.polygon = rpts
			rpoly.color   = Color(1.0, 1.0, 1.0, 0.88)
			ring.add_child(rpoly)
			get_parent().add_child(ring)
			var tw := get_tree().create_tween()
			tw.set_parallel(true)
			tw.tween_property(ring,  "scale", Vector2(4.0, 4.0), 0.40)
			tw.tween_property(rpoly, "color", Color(1.0, 1.0, 1.0, 0.0), 0.40)
			tw.set_parallel(false)
			tw.tween_callback(ring.queue_free)
		)

# ─── Dark Future enemy skins ──────────────────────────────────────────────────
# Applies visual detail layers on top of the base polygon for selected tiers.
# All other tiers keep their original color and shape untouched.
func _apply_dark_future_skin(enemy: Area2D, tier: int, base_r: float) -> void:
	var poly: Polygon2D = enemy.get_meta("poly")
	var CYAN    := Color(0.0,  0.8,  1.0,  1.0)
	var MAGENTA := Color(0.85, 0.0,  0.7,  1.0)
	var RED     := Color(0.85, 0.08, 0.08, 1.0)
	var PURPLE  := Color(0.2,  0.0,  0.35, 0.6)
	var GRAY    := Color(0.15, 0.2,  0.28, 1.0)
	var BLACK   := Color(0.024, 0.039, 0.063, 1.0)

	# ── Tier 1 (T2) — Scout Hunter ──────────────────────────────────────────
	if tier == 1:
		poly.color = BLACK
		# Cyan outline
		var ol := Line2D.new()
		ol.points = PackedVector2Array([
			Vector2(0, -base_r),
			Vector2(base_r * 0.85, base_r * 0.65),
			Vector2(-base_r * 0.85, base_r * 0.65)
		])
		ol.closed = true;  ol.width = 1.2;  ol.default_color = CYAN
		enemy.add_child(ol)
		# Gray armor bar across mid
		var bar_y: float = base_r * 0.1
		var bar := Polygon2D.new()
		bar.polygon = PackedVector2Array([
			Vector2(-base_r * 0.55, bar_y - 1.6),
			Vector2( base_r * 0.55, bar_y - 1.6),
			Vector2( base_r * 0.55, bar_y + 1.6),
			Vector2(-base_r * 0.55, bar_y + 1.6),
		])
		bar.color = GRAY;  enemy.add_child(bar)
		# Twin red headlights
		for sx in [-1.0, 1.0]:
			var ex: float = sx * base_r * 0.28
			var epts := PackedVector2Array()
			for j in 7:
				var a: float = TAU * float(j) / 7.0
				epts.append(Vector2(ex + cos(a) * 2.0, bar_y + 2.2 + sin(a) * 2.0))
			var eye := Polygon2D.new();  eye.polygon = epts;  eye.color = RED
			enemy.add_child(eye)
		# Spine line from apex to base
		var spine := Line2D.new()
		spine.points = PackedVector2Array([Vector2(0, -base_r), Vector2(0, base_r * 0.65)])
		spine.width = 0.8;  spine.default_color = Color(0.0, 0.8, 1.0, 0.35)
		enemy.add_child(spine)

	# ── Tier 4 (T5) — Interceptor Vector ─────────────────────────────────
	elif tier == 4:
		poly.color = BLACK
		# Cyan diamond outline
		var ol := Line2D.new()
		ol.points = PackedVector2Array([
			Vector2(0, -base_r), Vector2(base_r, 0),
			Vector2(0, base_r),  Vector2(-base_r, 0)
		])
		ol.closed = true;  ol.width = 1.2;  ol.default_color = CYAN
		enemy.add_child(ol)
		# Axis cross lines
		for cpts in [
			PackedVector2Array([Vector2(-base_r, 0), Vector2(base_r, 0)]),
			PackedVector2Array([Vector2(0, -base_r), Vector2(0, base_r)])
		]:
			var cl := Line2D.new();  cl.points = cpts;  cl.width = 0.8
			cl.default_color = Color(0.0, 0.8, 1.0, 0.4);  enemy.add_child(cl)
		# Purple quadrant fills (top-right and bottom-left)
		var q1 := Polygon2D.new()
		q1.polygon = PackedVector2Array([Vector2(0, 0), Vector2(0, -base_r), Vector2(base_r, 0)])
		q1.color = PURPLE;  enemy.add_child(q1)
		var q2 := Polygon2D.new()
		q2.polygon = PackedVector2Array([Vector2(0, 0), Vector2(0, base_r), Vector2(-base_r, 0)])
		q2.color = PURPLE;  enemy.add_child(q2)
		# Magenta center ring
		var ring_pts := PackedVector2Array()
		for j in 14:
			var a: float = TAU * float(j) / 14.0
			ring_pts.append(Vector2(cos(a), sin(a)) * base_r * 0.38)
		var ring := Line2D.new();  ring.points = ring_pts;  ring.closed = true
		ring.width = 1.2;  ring.default_color = MAGENTA;  enemy.add_child(ring)
		# Center dot
		var dot_pts := PackedVector2Array()
		for j in 8:
			var a: float = TAU * float(j) / 8.0
			dot_pts.append(Vector2(cos(a), sin(a)) * base_r * 0.14)
		var dot := Polygon2D.new();  dot.polygon = dot_pts;  dot.color = MAGENTA
		enemy.add_child(dot)

	# ── Tier 5 (T6) — Interceptor Wedge ──────────────────────────────────
	elif tier == 5:
		poly.color = BLACK
		# Cyan diamond outline
		var ol := Line2D.new()
		ol.points = PackedVector2Array([
			Vector2(0, -base_r), Vector2(base_r, 0),
			Vector2(0, base_r),  Vector2(-base_r, 0)
		])
		ol.closed = true;  ol.width = 1.2;  ol.default_color = CYAN
		enemy.add_child(ol)
		# Gray side wing stubs
		for sx in [-1.0, 1.0]:
			var wx: float = sx * (base_r + 1.5)
			var wing := Polygon2D.new()
			wing.polygon = PackedVector2Array([
				Vector2(wx,             -3.0),
				Vector2(wx + sx * 5.0,  -3.0),
				Vector2(wx + sx * 5.0,   3.0),
				Vector2(wx,              3.0),
			])
			wing.color = GRAY;  enemy.add_child(wing)
			var wo := Line2D.new()
			wo.points = wing.polygon;  wo.closed = true
			wo.width = 0.7;  wo.default_color = CYAN;  enemy.add_child(wo)
		# Visor strip background
		var visor := Polygon2D.new()
		visor.polygon = PackedVector2Array([
			Vector2(-base_r * 0.6, -2.5), Vector2(base_r * 0.6, -2.5),
			Vector2(base_r * 0.6,   2.5), Vector2(-base_r * 0.6,  2.5),
		])
		visor.color = Color(0.04, 0.04, 0.1, 1.0);  enemy.add_child(visor)
		var vo := Line2D.new();  vo.points = visor.polygon;  vo.closed = true
		vo.width = 0.8;  vo.default_color = CYAN;  enemy.add_child(vo)
		# 3 red eyes
		for i in 3:
			var ex: float = (float(i) - 1.0) * base_r * 0.38
			var epts := PackedVector2Array()
			for j in 8:
				var a: float = TAU * float(j) / 8.0
				epts.append(Vector2(ex + cos(a) * 2.1, sin(a) * 2.1))
			var eye := Polygon2D.new();  eye.polygon = epts;  eye.color = RED
			enemy.add_child(eye)

	# ── Tier 8 (T9) — Commander Nexus ─────────────────────────────────────
	elif tier == 8:
		poly.color = BLACK
		# Cyan hexagon outline
		var hex_pts := PackedVector2Array()
		for j in 6:
			var a: float = TAU * float(j) / 6.0 - PI / 2.0
			hex_pts.append(Vector2(cos(a), sin(a)) * base_r)
		var ol := Line2D.new();  ol.points = hex_pts;  ol.closed = true
		ol.width = 1.2;  ol.default_color = CYAN;  enemy.add_child(ol)
		# Inner hex ring
		var inner_pts := PackedVector2Array()
		for j in 6:
			var a: float = TAU * float(j) / 6.0 - PI / 2.0
			inner_pts.append(Vector2(cos(a), sin(a)) * base_r * 0.55)
		var inner := Line2D.new();  inner.points = inner_pts;  inner.closed = true
		inner.width = 0.8;  inner.default_color = Color(0.0, 0.8, 1.0, 0.55)
		enemy.add_child(inner)
		# 6 vertex nodes
		for j in 6:
			var va: float = TAU * float(j) / 6.0 - PI / 2.0
			var vx: float = cos(va) * base_r;  var vy: float = sin(va) * base_r
			var npts := PackedVector2Array()
			for k in 6:
				var na: float = TAU * float(k) / 6.0
				npts.append(Vector2(vx + cos(na) * 2.2, vy + sin(na) * 2.2))
			var node := Polygon2D.new();  node.polygon = npts;  node.color = CYAN
			enemy.add_child(node)
		# Center ring
		var ring_pts := PackedVector2Array()
		for j in 14:
			var a: float = TAU * float(j) / 14.0
			ring_pts.append(Vector2(cos(a), sin(a)) * base_r * 0.28)
		var cring := Line2D.new();  cring.points = ring_pts;  cring.closed = true
		cring.width = 1.2;  cring.default_color = CYAN;  enemy.add_child(cring)
		# Center dot
		var dot_pts := PackedVector2Array()
		for j in 8:
			var a: float = TAU * float(j) / 8.0
			dot_pts.append(Vector2(cos(a), sin(a)) * base_r * 0.1)
		var dot := Polygon2D.new();  dot.polygon = dot_pts;  dot.color = CYAN
		enemy.add_child(dot)

	# ── Tier 9 (T10) — Commander Sovereign ───────────────────────────────
	elif tier == 9:
		# ── Commander Voidgate — void interior, 6 magenta tick marks, it IS the eye
		poly.color = BLACK
		# Cyan hexagon outline
		var hex_pts := PackedVector2Array()
		for j in 6:
			var a: float = TAU * float(j) / 6.0 - PI / 2.0
			hex_pts.append(Vector2(cos(a), sin(a)) * base_r)
		var ol := Line2D.new();  ol.points = hex_pts;  ol.closed = true
		ol.width = 1.3;  ol.default_color = CYAN;  enemy.add_child(ol)
		# Inner void hex (darker)
		var inner_pts := PackedVector2Array()
		for j in 6:
			var a: float = TAU * float(j) / 6.0 - PI / 2.0
			inner_pts.append(Vector2(cos(a), sin(a)) * base_r * 0.62)
		var inner_fill := Polygon2D.new()
		inner_fill.polygon = inner_pts
		inner_fill.color = Color(0.01, 0.0, 0.015, 1.0)
		enemy.add_child(inner_fill)
		var inner_ol := Line2D.new();  inner_ol.points = inner_pts;  inner_ol.closed = true
		inner_ol.width = 0.9;  inner_ol.default_color = MAGENTA;  enemy.add_child(inner_ol)
		# Innermost void hex
		var void_pts := PackedVector2Array()
		for j in 6:
			var a: float = TAU * float(j) / 6.0 - PI / 2.0
			void_pts.append(Vector2(cos(a), sin(a)) * base_r * 0.34)
		var void_fill := Polygon2D.new()
		void_fill.polygon = void_pts
		void_fill.color = Color(0.0, 0.0, 0.008, 1.0)
		enemy.add_child(void_fill)
		# 6 magenta tick marks at each vertex — pointing inward
		for j in 6:
			var a: float = TAU * float(j) / 6.0 - PI / 2.0
			var vx: float = cos(a);  var vy: float = sin(a)
			var tick := Line2D.new()
			tick.points = PackedVector2Array([
				Vector2(vx * base_r, vy * base_r),
				Vector2(vx * base_r * 0.66, vy * base_r * 0.66)
			])
			tick.width = 1.6;  tick.default_color = MAGENTA;  enemy.add_child(tick)
		# Center void dot — glows magenta
		var cdot_pts := PackedVector2Array()
		for j in 8:
			var a: float = TAU * float(j) / 8.0
			cdot_pts.append(Vector2(cos(a), sin(a)) * base_r * 0.12)
		var cdot := Polygon2D.new();  cdot.polygon = cdot_pts
		cdot.color = Color(0.85, 0.0, 0.7, 0.75);  enemy.add_child(cdot)

	# ── Tier 0 (T1) — Scout Dart ──────────────────────────────────────────────
	elif tier == 0:
		# Extremely thin elongated triangle, magenta tip cap, speed-line etches, dim glow slit
		poly.color = BLACK
		# Cyan outline
		var dart_ol := Line2D.new()
		dart_ol.points = PackedVector2Array([
			Vector2(0, -base_r),
			Vector2(base_r * 0.5, base_r * 0.65),
			Vector2(-base_r * 0.5, base_r * 0.65)
		])
		dart_ol.closed = true;  dart_ol.width = 1.1;  dart_ol.default_color = CYAN
		enemy.add_child(dart_ol)
		# Magenta tip cap
		var tip := Polygon2D.new()
		tip.polygon = PackedVector2Array([
			Vector2(0, -base_r),
			Vector2(base_r * 0.12, -base_r + base_r * 0.22),
			Vector2(-base_r * 0.12, -base_r + base_r * 0.22)
		])
		tip.color = MAGENTA;  enemy.add_child(tip)
		# Speed-line etches — 3 each side
		for i in 3:
			var ly: float = -base_r * 0.1 + float(i) * base_r * 0.22
			var lx_inner: float = float(i + 1) * base_r * 0.08
			for sx in [-1.0, 1.0]:
				var etch := Line2D.new()
				etch.points = PackedVector2Array([
					Vector2(sx * lx_inner, ly),
					Vector2(sx * (lx_inner + base_r * 0.14), ly + base_r * 0.1)
				])
				etch.width = 0.7;  etch.default_color = Color(0.0, 0.8, 1.0, 0.45)
				enemy.add_child(etch)
		# Dim glow slit (no distinct eye)
		var slit := Polygon2D.new()
		slit.polygon = PackedVector2Array([
			Vector2(-base_r * 0.18, base_r * 0.12),
			Vector2( base_r * 0.18, base_r * 0.12),
			Vector2( base_r * 0.18, base_r * 0.17),
			Vector2(-base_r * 0.18, base_r * 0.17)
		])
		slit.color = Color(0.85, 0.0, 0.7, 0.4);  enemy.add_child(slit)

	# ── Tier 2 & 3 (T3-T4) — Scout Razor ─────────────────────────────────────
	elif tier == 2 or tier == 3:
		# Wide flat triangle, swept-back side fins, magenta glow core, thin slit eye
		poly.color = BLACK
		# Wider flat triangle outline
		var razor_ol := Line2D.new()
		razor_ol.points = PackedVector2Array([
			Vector2(0, -base_r),
			Vector2(base_r * 1.1, base_r * 0.7),
			Vector2(-base_r * 1.1, base_r * 0.7)
		])
		razor_ol.closed = true;  razor_ol.width = 1.1;  razor_ol.default_color = CYAN
		enemy.add_child(razor_ol)
		# Swept-back side fins
		for sx in [-1.0, 1.0]:
			var fin := Polygon2D.new()
			fin.polygon = PackedVector2Array([
				Vector2(sx * base_r * 0.7,  base_r * 0.3),
				Vector2(sx * base_r * 1.35, base_r * 0.5),
				Vector2(sx * base_r * 1.1,  base_r * 0.7),
				Vector2(sx * base_r * 0.7,  base_r * 0.6),
			])
			fin.color = Color(0.1, 0.14, 0.2, 1.0);  enemy.add_child(fin)
			var fin_ol := Line2D.new();  fin_ol.points = fin.polygon;  fin_ol.closed = true
			fin_ol.width = 0.8;  fin_ol.default_color = CYAN;  enemy.add_child(fin_ol)
		# Magenta glow core
		var core_ring_pts := PackedVector2Array()
		for j in 12:
			var a: float = TAU * float(j) / 12.0
			core_ring_pts.append(Vector2(cos(a), sin(a)) * base_r * 0.28)
		var core_ring := Line2D.new();  core_ring.points = core_ring_pts;  core_ring.closed = true
		core_ring.width = 1.0;  core_ring.default_color = Color(0.85, 0.0, 0.7, 0.8)
		enemy.add_child(core_ring)
		var core_pts := PackedVector2Array()
		for j in 8:
			var a: float = TAU * float(j) / 8.0
			core_pts.append(Vector2(cos(a), sin(a)) * base_r * 0.12)
		var core_dot := Polygon2D.new();  core_dot.polygon = core_pts
		core_dot.color = Color(0.85, 0.0, 0.7, 0.7);  enemy.add_child(core_dot)
		# Thin slit eye
		var eye_slit := Polygon2D.new()
		eye_slit.polygon = PackedVector2Array([
			Vector2(-base_r * 0.22, -base_r * 0.08),
			Vector2( base_r * 0.22, -base_r * 0.08),
			Vector2( base_r * 0.22, -base_r * 0.03),
			Vector2(-base_r * 0.22, -base_r * 0.03)
		])
		eye_slit.color = RED;  enemy.add_child(eye_slit)

	# ── Tier 6 (T7) — Heavy Siege ─────────────────────────────────────────────
	elif tier == 6:
		# Thick segmented armor border in 5 plates, top sensor dome, center vertical slit
		poly.color = BLACK
		# Pentagon outline
		var pent_pts := PackedVector2Array()
		for j in 5:
			var a: float = TAU * float(j) / 5.0 - PI / 2.0
			pent_pts.append(Vector2(cos(a), sin(a)) * base_r)
		var pent_ol := Line2D.new();  pent_ol.points = pent_pts;  pent_ol.closed = true
		pent_ol.width = 1.3;  pent_ol.default_color = CYAN;  enemy.add_child(pent_ol)
		# 5 armor plate segments — thick gray fill just inside each edge
		for j in 5:
			var a0: float = TAU * float(j) / 5.0 - PI / 2.0
			var a1: float = TAU * float(j + 1) / 5.0 - PI / 2.0
			var mid_a: float = (a0 + a1) / 2.0
			var plate := Polygon2D.new()
			var p0_o := Vector2(cos(a0), sin(a0)) * base_r
			var p1_o := Vector2(cos(a1), sin(a1)) * base_r
			var p0_i := Vector2(cos(a0), sin(a0)) * (base_r * 0.78)
			var p1_i := Vector2(cos(a1), sin(a1)) * (base_r * 0.78)
			plate.polygon = PackedVector2Array([p0_o, p1_o, p1_i, p0_i])
			plate.color = Color(0.12, 0.16, 0.22, 1.0);  enemy.add_child(plate)
			# Plate seam — cyan dot at midpoint
			var seam_dot_pts := PackedVector2Array()
			for k in 5:
				var sa: float = TAU * float(k) / 5.0
				seam_dot_pts.append(Vector2(
					cos(mid_a) * base_r * 0.88 + cos(sa) * 1.5,
					sin(mid_a) * base_r * 0.88 + sin(sa) * 1.5
				))
			var seam_dot := Polygon2D.new();  seam_dot.polygon = seam_dot_pts
			seam_dot.color = Color(0.0, 0.8, 1.0, 0.55);  enemy.add_child(seam_dot)
		# Top sensor dome (small circle above top vertex)
		var dome_cx: float = 0.0;  var dome_cy: float = -(base_r + 3.5)
		var dome_pts := PackedVector2Array()
		for j in 10:
			var a: float = TAU * float(j) / 10.0
			dome_pts.append(Vector2(dome_cx + cos(a) * 4.0, dome_cy + sin(a) * 4.0))
		var dome_fill := Polygon2D.new();  dome_fill.polygon = dome_pts
		dome_fill.color = Color(0.04, 0.06, 0.1, 1.0);  enemy.add_child(dome_fill)
		var dome_ol := Line2D.new();  dome_ol.points = dome_pts;  dome_ol.closed = true
		dome_ol.width = 0.9;  dome_ol.default_color = CYAN;  enemy.add_child(dome_ol)
		var dome_eye_pts := PackedVector2Array()
		for j in 6:
			var a: float = TAU * float(j) / 6.0
			dome_eye_pts.append(Vector2(dome_cx + cos(a) * 1.5, dome_cy + sin(a) * 1.5))
		var dome_eye := Polygon2D.new();  dome_eye.polygon = dome_eye_pts
		dome_eye.color = RED;  enemy.add_child(dome_eye)
		# Center vertical slit
		var vslit := Polygon2D.new()
		vslit.polygon = PackedVector2Array([
			Vector2(-1.2, -base_r * 0.38),
			Vector2( 1.2, -base_r * 0.38),
			Vector2( 1.2,  base_r * 0.42),
			Vector2(-1.2,  base_r * 0.42)
		])
		vslit.color = RED;  enemy.add_child(vslit)

	# ── Tier 7 (T8) — Heavy Golem ─────────────────────────────────────────────
	elif tier == 7:
		# Outer ring of 6 bolt-circles, hollow center void, 3 stacked eye slits
		poly.color = BLACK
		# Pentagon outline
		var gol_pts := PackedVector2Array()
		for j in 5:
			var a: float = TAU * float(j) / 5.0 - PI / 2.0
			gol_pts.append(Vector2(cos(a), sin(a)) * base_r)
		var gol_ol := Line2D.new();  gol_ol.points = gol_pts;  gol_ol.closed = true
		gol_ol.width = 1.3;  gol_ol.default_color = CYAN;  enemy.add_child(gol_ol)
		# Inner pentagon ring
		var inner_pts := PackedVector2Array()
		for j in 5:
			var a: float = TAU * float(j) / 5.0 - PI / 2.0
			inner_pts.append(Vector2(cos(a), sin(a)) * base_r * 0.65)
		var inner_ol := Line2D.new();  inner_ol.points = inner_pts;  inner_ol.closed = true
		inner_ol.width = 0.7;  inner_ol.default_color = Color(0.0, 0.8, 1.0, 0.4)
		enemy.add_child(inner_ol)
		# 6 bolt circles around the body
		for j in 6:
			var a: float = TAU * float(j) / 6.0 - PI / 2.0
			var bx: float = cos(a) * base_r * 0.82
			var by: float = sin(a) * base_r * 0.82
			var bolt_pts := PackedVector2Array()
			for k in 7:
				var ba: float = TAU * float(k) / 7.0
				bolt_pts.append(Vector2(bx + cos(ba) * 2.0, by + sin(ba) * 2.0))
			var bolt := Line2D.new();  bolt.points = bolt_pts;  bolt.closed = true
			bolt.width = 0.8;  bolt.default_color = Color(0.2, 0.28, 0.38, 1.0)
			enemy.add_child(bolt)
		# Hollow center void circle
		var void_pts := PackedVector2Array()
		for j in 14:
			var a: float = TAU * float(j) / 14.0
			void_pts.append(Vector2(cos(a), sin(a)) * base_r * 0.34)
		var void_fill := Polygon2D.new();  void_fill.polygon = void_pts
		void_fill.color = Color(0.015, 0.015, 0.022, 1.0);  enemy.add_child(void_fill)
		var void_ol := Line2D.new();  void_ol.points = void_pts;  void_ol.closed = true
		void_ol.width = 0.9;  void_ol.default_color = CYAN;  enemy.add_child(void_ol)
		# 3 stacked eye slits inside the void
		for i in 3:
			var sy: float = -base_r * 0.13 + float(i) * base_r * 0.13
			var slit_pts := PackedVector2Array()
			var sw: float = base_r * (0.22 - float(i) * 0.04)
			slit_pts.append(Vector2(-sw, sy - 1.2))
			slit_pts.append(Vector2( sw, sy - 1.2))
			slit_pts.append(Vector2( sw, sy + 1.2))
			slit_pts.append(Vector2(-sw, sy + 1.2))
			var slit := Polygon2D.new();  slit.polygon = slit_pts
			slit.color = Color(0.85, 0.08, 0.08, 0.85 - float(i) * 0.25)
			enemy.add_child(slit)
