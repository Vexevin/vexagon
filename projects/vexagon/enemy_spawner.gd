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
var spawn_delay_interval := 1.5

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
	spawn_delay = spawn_delay_interval

func spawn_enemy() -> void:
	var enemy := Area2D.new()
	enemy.set_meta("hp", 3)
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
		enemy.position += dir * enemy.get_meta("speed") * delta
		enemy.rotation = dir.angle() + PI / 2.0
		if enemy.position.distance_to(tower_pos) < 20.0:
			var tower = get_parent().get_node("Tower")
			tower.take_damage(10)
			enemies_alive -= 1
			enemy.queue_free()

func on_bullet_hit(enemy: Area2D, area: Area2D) -> void:
	if not area.is_in_group("bullet"):
		return
	if not is_instance_valid(enemy):
		return
	area.queue_free()
	var hp: int = enemy.get_meta("hp") - 1
	enemy.set_meta("hp", hp)
	var poly: Polygon2D = enemy.get_meta("poly")
	poly.color = Color(1.0, hp / 3.0, hp / 3.0)
	if hp <= 0:
		var hud = get_parent().get_node("Hud")
		hud.add_kill()
		enemies_alive -= 1
		var gold_mult: float = 1.0 + (hud.skill_levels[10] * 0.25)
		hud.add_gold(ceili(gold_mult))
		enemy.queue_free()
