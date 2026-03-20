extends Node2D

const ENEMY_SPEED := 80.0
var tower_pos := Vector2(576, 324)

var wave_number := 0
var enemies_to_spawn := 0
var enemies_spawned := 0
var enemies_alive := 0
var state := "IDLE"
var cooldown_timer := 0.0
var cooldown_duration := 10.0
var spawn_delay := 0.0
var spawn_delay_interval := 2.5

func _ready() -> void:
	start_wave()
	
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
		if enemies_alive <= 0:
			state = "COOLDOWN"
			cooldown_timer = cooldown_duration
			var hud = get_parent().get_node("Hud")
			hud.start_cooldown(cooldown_duration)
	elif state == "COOLDOWN":
		cooldown_timer -= delta
		var hud = get_parent().get_node("Hud")
		hud.update_cooldown(cooldown_timer)
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
	poly.polygon = PackedVector2Array([
		Vector2(0, -12), Vector2(10, 8), Vector2(-10, 8)
	])
	poly.color = Color.RED
	enemy.add_child(poly)
	enemy.set_meta("poly", poly)

	var angle := randf() * TAU
	enemy.position = tower_pos + Vector2(cos(angle), sin(angle)) * 480.0
	add_child(enemy)
	enemies_alive += 1
	enemy.area_entered.connect(func(area): on_bullet_hit(enemy, area))

func _physics_process(delta: float) -> void:
	for enemy in get_children():
		if not enemy is Area2D:
			continue
		var dir: Vector2 = (tower_pos - (enemy as Area2D).position).normalized()
		var slow = enemy.get_meta("slow") if enemy.has_meta("slow") else 0.0
		var slow_timer = enemy.get_meta("slow_timer") if enemy.has_meta("slow_timer") else 0.0
		if slow_timer > 0:
			slow_timer -= delta
			enemy.set_meta("slow_timer", slow_timer)
		else:
			slow = 0.0
			enemy.set_meta("slow", 0.0)
		var effective_speed = enemy.get_meta("speed") * (1.0 - slow)
		enemy.position += dir * effective_speed * delta
		enemy.rotation = dir.angle() + PI / 2.0
		var player = get_parent().get_node("Player")
		if is_instance_valid(player):
			if enemy.position.distance_to(player.global_position) < 20.0:
				player.take_damage(1.0)
				enemies_alive -= 1
				enemy.queue_free()
				if enemy.position.distance_to(tower_pos) < 20.0:
					var tower = get_parent().get_node("Tower")
					tower.take_damage(10)
					enemies_alive -= 1
					enemy.queue_free()
	for child in get_parent().get_children():
		if not child is Area2D:
			continue
		if not child.is_in_group("bullet"):
			continue
		if not is_instance_valid(child):
			continue
		for enemy in get_children():
			if not enemy is Area2D:
				continue
			if not is_instance_valid(enemy):
				continue
			if child.global_position.distance_to(enemy.global_position) < 15.0:
				if not child.has_meta("hit"):
					child.set_meta("hit", true)
					on_bullet_hit(enemy, child)
					break

func on_bullet_hit(enemy: Area2D, area: Area2D) -> void:
	if not area.is_in_group("bullet"):
		return
	if not is_instance_valid(enemy):
		return
	if not enemy.has_meta("hp"):
		return
	area.queue_free()
	var dmg = area.get_meta("damage") if area.has_meta("damage") else 1.0
	var hp: float = enemy.get_meta("hp") - dmg
	enemy.set_meta("hp", hp)
	var poly: Polygon2D = enemy.get_meta("poly")
	poly.color = Color(1.0, hp / 3.0, hp / 3.0)
	if area.has_meta("knockback"):
		var kb = area.get_meta("knockback")
		var kb_dir = (enemy.position - tower_pos).normalized()
		enemy.set_meta("slow", kb["slow"])
		enemy.set_meta("slow_timer", kb["duration"])
		if kb["push"] > 0:
			enemy.position += kb_dir * kb["push"]
	if hp <= 0:
		var hud = get_parent().get_node("Hud")
		hud.add_kill()
		enemies_alive -= 1
		var gm_lvl = hud.skill_levels[10]
		var coins = 1
		if gm_lvl <= 3:
			coins = 1 + gm_lvl
		var gold_mult: float = 1.0 + (gm_lvl * 0.25)
		hud.add_gold(ceili(coins * gold_mult))
		if gm_lvl >= 7:
			var drop_chance = 0.05 + (gm_lvl - 7) * 0.05
			if randf() < drop_chance:
				hud.add_node_fragment(1)
		if area.has_meta("split_level") and area.get_meta("split_level") > 0:
			spawn_fragment(enemy.position, (enemy.position - tower_pos).normalized(), dmg, area.get_meta("split_level"))
		if area.has_meta("explosive_radius"):
			var chain = area.get_meta("explosive_lvl") == 10
			trigger_explosion(enemy.position, area.get_meta("explosive_radius"), dmg / 2.0, chain)
		enemy.queue_free()
		
func spawn_fragment(pos: Vector2, dir: Vector2, dmg: float, split_level: int) -> void:
	if split_level <= 0:
		return
	var _piercing = split_level >= 7
	for i in 2:
		var frag := Area2D.new()
		frag.add_to_group("bullet")
		frag.set_meta("damage", dmg / 2.0)
		frag.set_meta("split_level", split_level - 1)
		var spread_dir = dir.rotated(deg_to_rad(45.0 if i == 0 else -45.0))
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

func trigger_explosion(pos: Vector2, radius: float, dmg: float, chain: bool) -> void:
	if radius <= 0:
		return
	for enemy in get_children():
		if not enemy is Area2D:
			continue
		if enemy.position.distance_to(pos) <= radius:
			var hp: float = enemy.get_meta("hp") - dmg
			enemy.set_meta("hp", hp)
			if hp <= 0:
				var hud = get_parent().get_node("Hud")
				hud.add_kill()
				enemies_alive -= 1
				if chain:
					trigger_explosion(enemy.position, radius, dmg / 2.0, false)
				enemy.queue_free()
