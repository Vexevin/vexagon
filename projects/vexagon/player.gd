extends CharacterBody2D

const SPEED := 200.0
const BULLET_SPEED := 500.0
const FIRE_RATE := 1.0 / 7.0

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
			fire_timer = FIRE_RATE
			shoot()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			fire_timer = 0.0

func shoot() -> void:
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
	poly.color = Color.WHITE
	bullet.global_position = global_position
	bullet.rotation = rotation
	bullet.add_child(poly)
	get_parent().add_child(bullet)
	
	var dir := (get_global_mouse_position() - global_position).normalized()
	var tween := get_tree().create_tween()
	tween.tween_property(bullet, "global_position",
		global_position + dir * 800.0, 0.8)
	tween.tween_callback(bullet.queue_free)
