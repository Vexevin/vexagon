extends Node2D

# ─── CONSTANTS ────────────────────────────────────────────────────────────────
const ENEMY_SPEED := 80.0
const BOSS_SPEED := 35.0
const BOSS_FIRE_INTERVAL := 2.0
const TOWER_HP_BASE := 50.0
const TOWERS_TOTAL := 5
const TOWER_RING_RADIUS := 280.0
const SPAWN_RADIUS       := 900.0

# ─── WAVE VARS ────────────────────────────────────────────────────────────────
var tower_pos := Vector2(3330.0, 2100.0)  # matches hex_map.MAP_CENTER
var wave_number := 0
var enemies_to_spawn := 0
var enemies_spawned := 0
var enemies_alive := 0
var state := "IDLE"
var cooldown_timer := 0.0
var cooldown_duration := 30.0
var spawn_delay := 0.0
var spawn_delay_interval := 2.5

# ─── S5: Enemy tower vars ──────────────────────────────────────────────────────
var towers_destroyed := 0
var tower_level := 1

# ─── S5: Boss vars ────────────────────────────────────────────────────────────
var boss_rank := 0
var boss_alive := false
var boss_node = null

# ─── READY ────────────────────────────────────────────────────────────────────
func _ready() -> void:
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
	var player: Node2D = get_parent().get_node_or_null("Player") as Node2D

	_move_enemies(delta, player)
	_move_boss(delta, player)
	_check_boss_bullets(player)
	_check_bullet_hits_enemies()
	_check_bullet_hits_towers()
	_check_bullet_hits_boss()

# ─── S5: Enemy movement — player-priority targeting ───────────────────────────
func _move_enemies(delta: float, player: Node2D) -> void:
	for enemy in get_children():
		if not enemy is Area2D:
			continue
		if not enemy.is_in_group("enemies"):
			continue
		if not is_instance_valid(enemy):
			continue

		var target_pos: Vector2 = tower_pos
		if is_instance_valid(player):
			var dp: float = (enemy as Area2D).position.distance_to(player.global_position)
			var dt: float = (enemy as Area2D).position.distance_to(tower_pos)
			if dp < dt:
				target_pos = player.global_position

		var dir: Vector2 = (target_pos - (enemy as Area2D).position).normalized()
		var slow: float = (enemy as Area2D).get_meta("slow") if (enemy as Area2D).has_meta("slow") else 0.0
		var slow_timer: float = (enemy as Area2D).get_meta("slow_timer") if (enemy as Area2D).has_meta("slow_timer") else 0.0
		if slow_timer > 0.0:
			slow_timer -= delta
			(enemy as Area2D).set_meta("slow_timer", slow_timer)
		else:
			slow = 0.0
			(enemy as Area2D).set_meta("slow", 0.0)
		var spd: float = (enemy as Area2D).get_meta("speed")
		(enemy as Area2D).position += dir * spd * (1.0 - slow) * delta
		(enemy as Area2D).rotation = dir.angle() + PI / 2.0

		if is_instance_valid(player) and (enemy as Area2D).position.distance_to(player.global_position) < 20.0:
			player.take_damage(1.0)
			enemies_alive -= 1
			enemy.queue_free()
			continue
		if is_instance_valid(enemy) and (enemy as Area2D).position.distance_to(tower_pos) < 20.0:
			get_parent().get_node("Tower").take_damage(10)
			enemies_alive -= 1
			enemy.queue_free()

# ─── S5: Boss movement + turret ───────────────────────────────────────────────
func _move_boss(delta: float, player: Node2D) -> void:
	if not boss_alive or not is_instance_valid(boss_node):
		return
	var bn: Area2D = boss_node as Area2D
	var btarget: Vector2 = tower_pos
	if is_instance_valid(player):
		btarget = player.global_position
	var bdir: Vector2 = (btarget - bn.position).normalized()
	bn.position += bdir * BOSS_SPEED * delta
	bn.rotation = bdir.angle() + PI / 2.0
	if is_instance_valid(player) and bn.position.distance_to(player.global_position) < 35.0:
		player.take_damage(5.0)
	var bft: float = bn.get_meta("fire_timer")
	bft += delta
	bn.set_meta("fire_timer", bft)
	if bft >= BOSS_FIRE_INTERVAL:
		bn.set_meta("fire_timer", 0.0)
		_fire_boss_bullet(player)

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
	if not boss_alive or not is_instance_valid(boss_node):
		return
	var bn: Area2D = boss_node as Area2D
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
		if cblt.global_position.distance_to(bn.global_position) < 32.0:
			cblt.set_meta("hit", true)
			_on_boss_hit(cblt)

# ─── Tower hit ────────────────────────────────────────────────────────────────
func _on_tower_hit(t: Area2D, blt: Area2D) -> void:
	var dmg: float = blt.get_meta("damage") if blt.has_meta("damage") else 1.0
	blt.queue_free()
	var hp: float = t.get_meta("hp")
	hp -= dmg
	t.set_meta("hp", hp)
	var max_hp: float = t.get_meta("max_hp")
	var poly: Polygon2D = t.get_meta("poly")
	var ratio: float = maxf(hp / max_hp, 0.0)
	poly.color = Color(0.8 * ratio + 0.2, 0.2 * ratio, 0.0)
	if hp <= 0.0:
		towers_destroyed += 1
		get_parent().get_node("Hud").update_tower_count(towers_destroyed, TOWERS_TOTAL)
		t.queue_free()
		if towers_destroyed >= TOWERS_TOTAL and not boss_alive:
			spawn_boss()

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
	boss_alive = false
	if is_instance_valid(boss_node):
		(boss_node as Node).queue_free()
	boss_node = null
	var hud = get_parent().get_node("Hud")
	hud.hide_boss_bar()
	hud.add_kill()
	if boss_rank >= 10:
		hud.show_you_win()
	else:
		towers_destroyed = 0
		tower_level += 1
		_spawn_enemy_towers()
		hud.update_tower_count(0, TOWERS_TOTAL)

# ─── Spawn enemy towers ───────────────────────────────────────────────────────
func _spawn_enemy_towers() -> void:
	for child in get_children():
		if child is Area2D and child.is_in_group("enemy_towers"):
			child.queue_free()
	var tower_hp: float = TOWER_HP_BASE
	for _i in range(tower_level - 1):
		tower_hp *= 1.5
	for i in range(TOWERS_TOTAL):
		var angle: float = TAU * float(i) / float(TOWERS_TOTAL)
		var t_pos: Vector2 = tower_pos + Vector2(cos(angle), sin(angle)) * TOWER_RING_RADIUS
		var t := Area2D.new()
		t.add_to_group("enemy_towers")
		var pts := PackedVector2Array()
		for j in range(5):
			var a: float = TAU * float(j) / 5.0 - PI / 2.0
			pts.append(Vector2(cos(a), sin(a)) * 14.0)
		var circ_shape := CollisionShape2D.new()
		var circ := CircleShape2D.new()
		circ.radius = 14.0
		circ_shape.shape = circ
		t.add_child(circ_shape)
		var poly := Polygon2D.new()
		poly.polygon = pts
		poly.color = Color(0.8, 0.25, 0.0)
		t.add_child(poly)
		t.set_meta("poly", poly)
		t.set_meta("hp", tower_hp)
		t.set_meta("max_hp", tower_hp)
		t.position = t_pos
		add_child(t)

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
	bn.set_meta("hp", max_hp)
	bn.set_meta("max_hp", max_hp)
	bn.set_meta("fire_timer", 0.0)
	var angle: float = randf() * TAU
	bn.position = tower_pos + Vector2(cos(angle), sin(angle)) * 460.0
	add_child(bn)
	boss_node = bn
	boss_alive = true
	var hud = get_parent().get_node("Hud")
	hud.show_boss_warning(boss_rank)
	hud.update_boss_hp(max_hp, max_hp)

# ─── Spawn enemy ──────────────────────────────────────────────────────────────
func spawn_enemy() -> void:
	var enemy := Area2D.new()
	enemy.set_meta("hp", 3.0)
	enemy.set_meta("speed", ENEMY_SPEED)
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 10.0
	shape.shape = circle
	enemy.add_child(shape)
	var poly := Polygon2D.new()
	poly.polygon = PackedVector2Array([Vector2(0, -12), Vector2(10, 8), Vector2(-10, 8)])
	poly.color = Color.RED
	enemy.add_child(poly)
	enemy.set_meta("poly", poly)
	var angle: float = randf() * TAU
	enemy.position = tower_pos + Vector2(cos(angle), sin(angle)) * SPAWN_RADIUS
	add_child(enemy)
	enemy.add_to_group("enemies")
	enemies_alive += 1
	enemy.area_entered.connect(func(area): on_bullet_hit(enemy, area))

# ─── On bullet hit (regular enemies) ─────────────────────────────────────────
func on_bullet_hit(enemy: Area2D, area: Area2D) -> void:
	if not area.is_in_group("bullet"):
		return
	if area.has_meta("no_hit"):
		return
	if not is_instance_valid(enemy):
		return
	if not enemy.has_meta("hp"):
		return
	area.queue_free()
	var dmg: float = area.get_meta("damage") if area.has_meta("damage") else 1.0
	var hp: float = enemy.get_meta("hp")
	hp -= dmg
	enemy.set_meta("hp", hp)
	var poly: Polygon2D = enemy.get_meta("poly")
	poly.color = Color(1.0, hp / 3.0, hp / 3.0)
	if area.has_meta("knockback"):
		var kb: Dictionary = area.get_meta("knockback")
		var kb_dir: Vector2 = (enemy.position - tower_pos).normalized()
		enemy.set_meta("slow", kb["slow"])
		enemy.set_meta("slow_timer", kb["duration"])
		if kb["push"] > 0:
			enemy.position += kb_dir * float(kb["push"])
	if hp <= 0.0:
		var hud = get_parent().get_node("Hud")
		hud.add_kill()
		enemies_alive -= 1
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
			spawn_fragment(enemy.position, (enemy.position - tower_pos).normalized(), dmg, area.get_meta("split_level"))
		if area.has_meta("explosive_radius"):
			var chain: bool = area.get_meta("explosive_lvl") == 10
			trigger_explosion(enemy.position, area.get_meta("explosive_radius"), dmg / 2.0, chain)
		enemy.queue_free()

# ─── Spawn fragment ───────────────────────────────────────────────────────────
func spawn_fragment(pos: Vector2, dir: Vector2, dmg: float, split_level: int) -> void:
	if split_level <= 0:
		return
	var _piercing: bool = split_level >= 7
	for i in range(2):
		var frag := Area2D.new()
		frag.add_to_group("bullet")
		frag.set_meta("damage", dmg / 2.0)
		frag.set_meta("split_level", split_level - 1)
		var is_shotgun: bool = split_level >= 4
		var spread_angle: float
		if is_shotgun:
			spread_angle = randf_range(15.0, 90.0)
			if i == 1:
				spread_angle = -randf_range(15.0, 90.0)
		else:
			spread_angle = 20.0 if i == 0 else -20.0
		var spread_dir: Vector2 = dir.rotated(deg_to_rad(spread_angle))
		var shape := CollisionShape2D.new()
		var circle := CircleShape2D.new()
		circle.radius = 4.0
		shape.shape = circle
		frag.add_child(shape)
		var poly := Polygon2D.new()
		poly.polygon = PackedVector2Array([Vector2(0, -4), Vector2(3, 4), Vector2(-3, 4)])
		poly.color = Color.CYAN
		frag.add_child(poly)
		frag.position = pos
		get_parent().add_child(frag)
		var tween := get_tree().create_tween()
		tween.tween_property(frag, "global_position", pos + spread_dir * 200.0, 0.4)
		tween.tween_callback(frag.queue_free)
		frag.area_entered.connect(func(area): on_bullet_hit(frag, area))

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
	enemy.queue_free()
