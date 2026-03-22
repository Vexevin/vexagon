## WorldSpawner.gd  — v2
## Generic world spawn engine. Called by HexMap after terrain generation.
## HexMap._ready() replaces _spawn_treasure_nodes() with:
##   $WorldSpawner.spawn_all(self)
##
## Migration status:
##   ✅ Crystals
##   ✅ Treasure Nodes
##   🔲 Spike Traps  (next)
##   🔲 Living World (last)
extends Node2D

const HEX_SIZE:   float   = 35.0
const MAP_CENTER: Vector2 = Vector2(3330.0, 2100.0)

signal crystal_collected()

var _hud:     Node = null
var _hex_map: Node = null

# ── Player-following god ray ──────────────────────────────────────────────────
var _player_ray:        Node2D = null
var _player_ray_target: Node2D = null

func _process(_delta: float) -> void:
	# Keep god ray positioned above player while carrying artifact
	if _player_ray != null and is_instance_valid(_player_ray) \
	and _player_ray_target != null and is_instance_valid(_player_ray_target):
		_player_ray.global_position = _player_ray_target.global_position

func dismiss_player_ray() -> void:
	if _player_ray != null and is_instance_valid(_player_ray):
		var rf := get_tree().create_tween()
		rf.tween_property(_player_ray, "modulate:a", 0.0, 0.8)
		rf.tween_callback(_player_ray.queue_free)
		_player_ray        = null
		_player_ray_target = null

# ── Called by HexMap._ready() AFTER terrain generation ────────────────────────
func spawn_all(hex_map: Node) -> void:
	_hex_map = hex_map
	_hud     = hex_map.get_node_or_null("Hud")
	_run_def(_make_crystal_def())
	_run_def(_make_treasure_def())
	_run_def(_make_crystal_node_def())
	_spawn_spikes()
	_spawn_living_world()

# ── SpawnDef factories ────────────────────────────────────────────────────────
func _make_crystal_def() -> SpawnDef:
	var d := SpawnDef.new()
	d.id                  = "crystal"
	d.display_name        = "Crystal"
	d.group               = "crystal"
	d.count_min           = 6
	d.count_max           = 6
	d.min_hex_from_center = 2
	d.min_hex_between     = 0
	d.search_radius       = 5
	d.valid_hex_types     = [0]
	d.one_shot            = true
	d.base_color          = Color(0.2, 0.75, 1.0)
	d.glow_color          = Color(0.2, 0.75, 1.0, 0.30)
	d.accent_color        = Color(1.0, 1.0, 1.0, 0.55)
	d.size                = 16.0
	d.z_index             = 2
	d.on_collect_signal   = "crystal_collected"
	return d

func _make_treasure_def() -> SpawnDef:
	var d := SpawnDef.new()
	d.id                  = "treasure_node"
	d.display_name        = "Treasure Node"
	d.group               = "treasure_node"
	d.count_min           = 18
	d.count_max           = 18
	d.min_hex_from_center = 12
	d.min_hex_between     = 8
	d.search_radius       = 0      # full-map scan
	d.valid_hex_types     = [0]
	d.one_shot            = true
	d.base_color          = Color(0.88, 0.72, 0.15)
	d.glow_color          = Color(0.85, 0.62, 0.08, 0.30)
	d.accent_color        = Color(1.0, 0.92, 0.45, 1.0)
	d.size                = 13.0
	d.z_index             = 2
	return d

func _make_crystal_node_def() -> SpawnDef:
	var d := SpawnDef.new()
	d.id                  = "crystal_node"
	d.display_name        = "Crystal Node"
	d.group               = "crystal_node_marker"
	d.count_min           = 8
	d.count_max           = 12
	d.min_hex_from_center = 14
	d.min_hex_between     = 10
	d.search_radius       = 0
	d.valid_hex_types     = [0]
	d.one_shot            = false
	d.base_color          = Color(0.55, 0.15, 0.95)
	d.glow_color          = Color(0.65, 0.20, 1.0, 0.35)
	d.accent_color        = Color(0.90, 0.70, 1.0, 0.80)
	d.size                = 14.0
	d.z_index             = 2
	return d
func _run_def(def: SpawnDef) -> void:
	var count: int = randi_range(def.count_min, def.count_max)
	var positions: Array = _find_positions(def, count)
	for hex_pos in positions:
		var world_pos: Vector2 = hex_to_pixel(hex_pos.x, hex_pos.y)
		_instantiate(def, hex_pos, world_pos)

func _find_positions(def: SpawnDef, count: int) -> Array:
	var candidates: Array = []

	if def.search_radius > 0:
		var rv: int = def.search_radius
		for q in range(-rv, rv + 1):
			for r in range(-rv, rv + 1):
				if abs(q + r) <= rv:
					var dist: int = maxi(abs(q), maxi(abs(r), abs(q + r)))
					if dist >= def.min_hex_from_center:
						candidates.append(Vector2i(q, r))
	else:
		if _hex_map == null:
			push_error("WorldSpawner: spawn_all() must be called before _find_positions()")
			return []
		var hex_types: Dictionary = {}
		var ht = _hex_map.get("hex_types")
		if ht != null: hex_types = ht as Dictionary
		var q_range: int = 75
		var r_range: int = 40
		var qr = _hex_map.get("Q_RANGE"); if qr != null: q_range = qr as int
		var rr = _hex_map.get("R_RANGE"); if rr != null: r_range = rr as int

		for q in range(-q_range + 6, q_range - 6):
			for r in range(-r_range + 4, r_range - 4):
				var key := Vector2i(q, r)
				var htype: int = hex_types.get(key, 0)
				if not (htype in def.valid_hex_types): continue
				var dist: int = maxi(abs(q), maxi(abs(r), abs(q + r)))
				if dist < def.min_hex_from_center: continue
				candidates.append(key)

	candidates.shuffle()

	var placed: Array = []
	for candidate in candidates:
		if placed.size() >= count: break
		if def.min_hex_between > 0:
			var too_close := false
			for p in placed:
				var cq: int = (candidate as Vector2i).x
				var cr: int = (candidate as Vector2i).y
				var pq: int = (p as Vector2i).x
				var pr: int = (p as Vector2i).y
				var d: int = maxi(abs(cq - pq), maxi(abs(cr - pr),
						abs((cq + cr) - (pq + pr))))
				if d < def.min_hex_between:
					too_close = true; break
			if too_close: continue
		placed.append(candidate)

	return placed

func _instantiate(def: SpawnDef, hex_pos: Vector2i, world_pos: Vector2) -> Node2D:
	match def.id:
		"crystal":       return _make_crystal_node(def, hex_pos, world_pos)
		"treasure_node": return _make_treasure_node(def, hex_pos, world_pos)
		"crystal_node":  return _make_crystal_node_marker(def, hex_pos, world_pos)
		_:
			push_warning("WorldSpawner: no builder for id=" + def.id)
			return Node2D.new()

# ── Crystal builder ───────────────────────────────────────────────────────────
func _make_crystal_node(def: SpawnDef, _hex_pos: Vector2i, world_pos: Vector2) -> Node2D:
	var crystal := Area2D.new()
	crystal.add_to_group(def.group)
	crystal.set_meta("hp", 4)
	crystal.position      = world_pos
	crystal.z_index       = def.z_index
	crystal.z_as_relative = false

	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = def.size
	shape.shape   = circle
	crystal.add_child(shape)

	var gpts := PackedVector2Array()
	for i in 20:
		var a: float = TAU * float(i) / 20.0
		gpts.append(Vector2(cos(a), sin(a)) * (def.size + 6.0))
	var gpoly := Polygon2D.new()
	gpoly.polygon = gpts
	gpoly.color   = def.glow_color
	crystal.add_child(gpoly)

	var s: float = def.size
	var body_pts := PackedVector2Array([
		Vector2( 0.0,        -s        ),
		Vector2( s * 0.52,   -s * 0.38 ),
		Vector2( s * 0.78,    s * 0.14 ),
		Vector2( s * 0.42,    s * 0.72 ),
		Vector2( 0.0,         s * 0.90 ),
		Vector2(-s * 0.42,    s * 0.72 ),
		Vector2(-s * 0.78,    s * 0.14 ),
		Vector2(-s * 0.52,   -s * 0.38 ),
	])
	var body := Polygon2D.new()
	body.polygon = body_pts
	body.color   = def.base_color
	crystal.add_child(body)

	var mid_pts := PackedVector2Array([
		Vector2( 0.0,        -s * 0.75 ),
		Vector2( s * 0.38,   -s * 0.22 ),
		Vector2( s * 0.55,    s * 0.20 ),
		Vector2( 0.0,         s * 0.60 ),
		Vector2(-s * 0.55,    s * 0.20 ),
		Vector2(-s * 0.38,   -s * 0.22 ),
	])
	var mid := Polygon2D.new()
	mid.polygon = mid_pts
	mid.color   = Color(def.base_color.r + 0.15, def.base_color.g + 0.10,
						def.base_color.b + 0.05, 0.55)
	crystal.add_child(mid)

	var facet_pts := PackedVector2Array([
		Vector2( 0.0,        -s * 0.42 ),
		Vector2( s * 0.30,    0.0      ),
		Vector2( 0.0,         s * 0.38 ),
		Vector2(-s * 0.30,    0.0      ),
	])
	var facet := Polygon2D.new()
	facet.polygon = facet_pts
	facet.color   = def.accent_color
	crystal.add_child(facet)

	var ba: Color = def.accent_color
	var tw := get_tree().create_tween().set_loops()
	tw.tween_property(facet, "color", Color(ba.r, ba.g, ba.b, 1.0),  0.75)
	tw.tween_property(facet, "color", Color(ba.r, ba.g, ba.b, 0.40), 0.75)

	crystal.set_meta("body_poly",   body)
	crystal.set_meta("facet_poly",  facet)
	crystal.set_meta("glow_poly",   gpoly)
	crystal.set_meta("base_color",  def.base_color)
	crystal.set_meta("pulse_tween", tw)
	crystal.area_entered.connect(_on_crystal_hit.bind(crystal))
	add_child(crystal)
	return crystal

func _on_crystal_hit(area: Area2D, crystal: Area2D) -> void:
	if not area.is_in_group("bullet"): return
	if not is_instance_valid(crystal): return
	area.queue_free()

	var hp: int = crystal.get_meta("hp") - 1
	crystal.set_meta("hp", hp)
	var ratio: float = float(hp) / 4.0

	var body  = crystal.get_meta("body_poly")
	var facet = crystal.get_meta("facet_poly")
	var glow  = crystal.get_meta("glow_poly")
	var bc: Color = crystal.get_meta("base_color")

	if is_instance_valid(body):
		(body  as Polygon2D).color = Color(bc.r, bc.g, bc.b, bc.a * ratio)
	if is_instance_valid(glow):
		(glow  as Polygon2D).color = Color(glow.color.r, glow.color.g,
										   glow.color.b, 0.30 * ratio)
	if is_instance_valid(facet) and hp <= 1:
		var pt = crystal.get_meta("pulse_tween") as Tween
		if is_instance_valid(pt): pt.kill()

	if hp <= 0:
		_on_crystal_destroyed(crystal)

func _on_crystal_destroyed(crystal: Area2D) -> void:
	var burst := Node2D.new()
	burst.global_position = crystal.global_position
	burst.z_index = 10
	add_child(burst)
	for i in 4:
		var angle: float = PI / 4.0 + (PI / 2.0 * float(i))
		var line := Line2D.new()
		line.add_point(Vector2.ZERO)
		line.add_point(Vector2(cos(angle), sin(angle)) * 18.0)
		line.width         = 2.5
		line.default_color = Color(0.4, 0.9, 1.0, 1.0)
		burst.add_child(line)
	var bt := get_tree().create_tween()
	bt.tween_property(burst, "modulate:a", 0.0, 0.25)
	bt.tween_callback(burst.queue_free)
	if _hud != null and _hud.has_method("add_node_fragment"):
		_hud.add_node_fragment(1)
	crystal_collected.emit()
	crystal.queue_free()

# ── Treasure node builder ─────────────────────────────────────────────────────
func _make_treasure_node(def: SpawnDef, hex_pos: Vector2i, world_pos: Vector2) -> Node2D:
	var n := Node2D.new()
	n.global_position = world_pos
	n.z_index         = def.z_index
	n.z_as_relative   = false
	n.add_to_group(def.group)
	n.set_meta("hex_key", hex_pos)
	n.set_meta("iris_open", false)

	# Outer glow ring — amber breathe pulse
	var gpts := PackedVector2Array()
	for i in 20:
		var a: float = TAU * float(i) / 20.0
		gpts.append(Vector2(cos(a), sin(a)) * 22.0)
	var gpoly := Polygon2D.new()
	gpoly.polygon = gpts
	gpoly.color   = def.glow_color
	n.add_child(gpoly)
	n.set_meta("glow_poly", gpoly)

	# Hex body
	var hpts := PackedVector2Array()
	for i in 6:
		var a: float = deg_to_rad(60.0 * float(i) - 30.0)
		hpts.append(Vector2(cos(a), sin(a)) * def.size)
	var hpoly := Polygon2D.new()
	hpoly.polygon = hpts
	hpoly.color   = def.base_color
	n.add_child(hpoly)

	# ── Iris petals — 6 camera-aperture blades ─────────────────────────────
	# Each petal is a Node2D at hex center, rotated to its sector.
	# Shape: skewed parallelogram — asymmetric so petals overlap at center.
	# Closed: tips meet at center, covering the hex interior.
	# Open: each petal rotates +52° outward, clearing the center.
	var PETAL_COL := Color(
		def.base_color.r * 0.45,
		def.base_color.g * 0.45,
		def.base_color.b * 0.45, 0.96)
	var PETAL_EDGE := Color(
		def.base_color.r * 0.70,
		def.base_color.g * 0.70,
		def.base_color.b * 0.70, 0.6)

	var petals: Array = []
	for i in 6:
		var pc := Node2D.new()
		pc.rotation = deg_to_rad(60.0 * float(i))
		n.add_child(pc)

		# Parallelogram blade: skewed so tip sweeps center on rotation
		# local +y = outward from center after pc.rotation applied
		var ppts := PackedVector2Array([
			Vector2(-2.0,  1.5),   # inner-left (near center)
			Vector2( 5.5,  1.5),   # inner-right (near center, offset)
			Vector2( 9.0, 13.0),   # outer-right
			Vector2(-1.5, 13.0),   # outer-left
		])
		var ppoly := Polygon2D.new()
		ppoly.polygon = ppts
		ppoly.color   = PETAL_COL
		pc.add_child(ppoly)

		# Leading edge highlight
		var eline := Line2D.new()
		eline.add_point(Vector2(5.5, 1.5))
		eline.add_point(Vector2(9.0, 13.0))
		eline.width         = 1.2
		eline.default_color = PETAL_EDGE
		pc.add_child(eline)

		petals.append(pc)

	n.set_meta("iris_petals", petals)

	# Idle breathe pulse on glow ring
	var pulse := get_tree().create_tween().set_loops()
	pulse.tween_property(gpoly, "color",
		Color(def.glow_color.r, def.glow_color.g, def.glow_color.b, 0.65), 1.1)
	pulse.tween_property(gpoly, "color",
		Color(def.glow_color.r, def.glow_color.g, def.glow_color.b, 0.12), 1.1)
	n.set_meta("pulse_tween", pulse)

	add_child(n)

	# Register in hex_map so spike trap biasing + pickup logic still work
	if _hex_map != null and _hex_map.has_method("register_treasure_node"):
		_hex_map.register_treasure_node(hex_pos, n)

	return n

# ── Iris open — called by player.gd on pickup ─────────────────────────────────
# on_reveal_callback fires at the 4s mark — player.gd passes its _reveal_artifact func
func open_treasure_box(node: Node2D, player: Node2D, on_reveal_callback: Callable) -> void:
	if not is_instance_valid(node): return
	if node.get_meta("iris_open", false): return
	node.set_meta("iris_open", true)

	# Stop idle pulse
	var pt = node.get_meta("pulse_tween", null)
	if pt != null and is_instance_valid(pt): (pt as Tween).kill()

	var box_pos: Vector2 = node.global_position
	var petals: Array    = node.get_meta("iris_petals", [])

	# ── Iris opens slowly over 4.0s ───────────────────────────────────────
	var open_tween := get_tree().create_tween().set_parallel(true)
	for petal in petals:
		if not is_instance_valid(petal): continue
		open_tween.tween_property(petal as Node2D, "rotation",
			(petal as Node2D).rotation + deg_to_rad(52.0), 4.0)

	# ── God Ray at box — spawns immediately ───────────────────────────────
	var god_ray := _make_god_ray(box_pos)
	add_child(god_ray)

	# ── Dust particles rising from box ────────────────────────────────────
	_spawn_dust_particles(box_pos)

	# ── Golden bloom ring at center ───────────────────────────────────────
	const GOLD := Color(1.0, 0.88, 0.30)
	var bloom := Node2D.new()
	bloom.global_position = box_pos
	bloom.z_index = node.z_index + 1
	bloom.z_as_relative = false
	add_child(bloom)
	for ci in 3:
		var radii := [4.0, 10.0, 18.0]; var alphas := [1.0, 0.65, 0.30]
		var cpts := PackedVector2Array()
		for j in 16:
			var a: float = TAU * float(j) / 16.0
			cpts.append(Vector2(cos(a), sin(a)) * radii[ci])
		var cpoly := Polygon2D.new()
		cpoly.polygon = cpts
		cpoly.color   = Color(GOLD.r, GOLD.g, GOLD.b, alphas[ci])
		bloom.add_child(cpoly)
	for si in 4:
		var sa: float = PI / 4.0 + PI / 2.0 * float(si)
		var sline := Line2D.new()
		sline.add_point(Vector2(cos(sa), sin(sa)) * 3.0)
		sline.add_point(Vector2(cos(sa), sin(sa)) * 10.0)
		sline.width = 2.0;  sline.default_color = Color(GOLD.r, GOLD.g, GOLD.b, 0.85)
		bloom.add_child(sline)

	# Bloom fades over 3s starting at 0.5s
	var bfade := get_tree().create_tween()
	bfade.tween_interval(0.5)
	bfade.tween_property(bloom, "modulate:a", 0.0, 3.0)
	bfade.tween_callback(bloom.queue_free)

	# ── At 4.0s: grant artifact, transfer god ray to player ───────────────
	get_tree().create_timer(4.0).timeout.connect(func():
		# God ray at box fades out
		if is_instance_valid(god_ray):
			var fade := get_tree().create_tween()
			fade.tween_property(god_ray, "modulate:a", 0.0, 0.5)
			fade.tween_callback(god_ray.queue_free)

		# Create player-following ray FIRST, register it, THEN grant artifact
		# (so _reveal_artifact cleanup can find it if delivery is instant)
		if is_instance_valid(player):
			_player_ray_target = player
			_player_ray = _make_god_ray(player.global_position)
			add_child(_player_ray)

		# Grant artifact — loot rolls, fireworks, HUD popup
		on_reveal_callback.call()
	)

	# ── Node fades after 4.5s ─────────────────────────────────────────────
	get_tree().create_timer(4.5).timeout.connect(func():
		if is_instance_valid(node):
			var nf := get_tree().create_tween()
			nf.tween_property(node, "modulate:a", 0.0, 0.3)
			nf.tween_callback(node.queue_free)
	)

# ── God Ray builder ───────────────────────────────────────────────────────────
func _make_god_ray(world_pos: Vector2) -> Node2D:
	var ray := Node2D.new()
	ray.global_position = world_pos
	ray.z_index = 20;  ray.z_as_relative = false

	# Main shaft — wide golden trapezoid fanning upward
	const RAY_W_BOT := 14.0   # width at source
	const RAY_W_TOP := 55.0   # width at top
	const RAY_H     := 160.0  # height of shaft
	const GOLD_RAY  := Color(1.0, 0.92, 0.40, 0.22)

	var shaft_pts := PackedVector2Array([
		Vector2(-RAY_W_BOT, 0.0),
		Vector2( RAY_W_BOT, 0.0),
		Vector2( RAY_W_TOP, -RAY_H),
		Vector2(-RAY_W_TOP, -RAY_H),
	])
	var shaft := Polygon2D.new()
	shaft.polygon = shaft_pts;  shaft.color = GOLD_RAY
	ray.add_child(shaft)

	# Two thinner bright inner shafts for depth
	for inner in [[6.0, 22.0, 0.32], [3.0, 12.0, 0.44]]:
		var ipts := PackedVector2Array([
			Vector2(-inner[0], 0.0),
			Vector2( inner[0], 0.0),
			Vector2( inner[1], -RAY_H),
			Vector2(-inner[1], -RAY_H),
		])
		var ipoly := Polygon2D.new()
		ipoly.polygon = ipts
		ipoly.color   = Color(1.0, 0.96, 0.60, inner[2])
		ray.add_child(ipoly)

	# Soft glow circle at base
	var gpts := PackedVector2Array()
	for i in 20:
		var a: float = TAU * float(i) / 20.0
		gpts.append(Vector2(cos(a), sin(a)) * 22.0)
	var glow := Polygon2D.new()
	glow.polygon = gpts;  glow.color = Color(1.0, 0.90, 0.30, 0.28)
	ray.add_child(glow)

	# Gentle alpha pulse on the whole ray
	var pulse := get_tree().create_tween().set_loops()
	pulse.tween_property(ray, "modulate:a", 1.15, 1.4)
	pulse.tween_property(ray, "modulate:a", 0.75, 1.4)

	return ray

# ── Dust particles ────────────────────────────────────────────────────────────
func _spawn_dust_particles(world_pos: Vector2) -> void:
	const PARTICLE_COUNT := 18
	const DUST := Color(1.0, 0.92, 0.65, 0.55)

	for i in PARTICLE_COUNT:
		var p := Node2D.new()
		p.global_position = world_pos + Vector2(randf_range(-16.0, 16.0), randf_range(-8.0, 8.0))
		p.z_index = 19;  p.z_as_relative = false
		add_child(p)

		# Tiny dot
		var dot_pts := PackedVector2Array()
		var dot_r := randf_range(1.2, 2.8)
		for j in 6:
			var a: float = TAU * float(j) / 6.0
			dot_pts.append(Vector2(cos(a), sin(a)) * dot_r)
		var dot := Polygon2D.new()
		dot.polygon = dot_pts
		dot.color   = Color(DUST.r, DUST.g, DUST.b, randf_range(0.3, 0.65))
		p.add_child(dot)

		# Each particle drifts up + sideways over a random duration
		var drift_x   := randf_range(-18.0, 18.0)
		var drift_y   := randf_range(-55.0, -20.0)
		var duration  := randf_range(1.8, 4.0)
		var delay     := randf_range(0.0, 1.5)

		var tw := get_tree().create_tween().set_parallel(true)
		tw.tween_interval(delay)
		tw.tween_property(p, "position",
			p.position + Vector2(drift_x, drift_y), duration)
		tw.tween_property(dot, "color",
			Color(DUST.r, DUST.g, DUST.b, 0.0), duration)
		tw.set_parallel(false)
		tw.tween_callback(p.queue_free)

# ── Utility ───────────────────────────────────────────────────────────────────
func hex_to_pixel(q: int, r: int) -> Vector2:
	var x: float = HEX_SIZE * (sqrt(3.0) * float(q) + sqrt(3.0) / 2.0 * float(r))
	var y: float = HEX_SIZE * (3.0 / 2.0 * float(r))
	return Vector2(x, y) + MAP_CENTER

# ── Crystal Node Marker builder ───────────────────────────────────────────────
func _make_crystal_node_marker(def: SpawnDef, hex_pos: Vector2i, world_pos: Vector2) -> Node2D:
	var n := Node2D.new()
	n.global_position = world_pos
	n.z_index         = def.z_index
	n.z_as_relative   = false
	n.add_to_group(def.group)
	n.set_meta("hex_key", hex_pos)

	# Outer glow ring — violet pulse
	var gpts := PackedVector2Array()
	for i in 20:
		var a: float = TAU * float(i) / 20.0
		gpts.append(Vector2(cos(a), sin(a)) * (def.size + 8.0))
	var gpoly := Polygon2D.new()
	gpoly.polygon = gpts
	gpoly.color   = def.glow_color
	n.add_child(gpoly)

	# Hex body — violet
	var hpts := PackedVector2Array()
	for i in 6:
		var a: float = deg_to_rad(60.0 * float(i) - 30.0)
		hpts.append(Vector2(cos(a), sin(a)) * def.size)
	var hpoly := Polygon2D.new()
	hpoly.polygon = hpts
	hpoly.color   = def.base_color
	n.add_child(hpoly)

	# Inner gem shard — tall skinny crystal shape
	var s: float = def.size * 0.65
	var shard_pts := PackedVector2Array([
		Vector2( 0.0,        -s        ),
		Vector2( s * 0.38,  -s * 0.15 ),
		Vector2( s * 0.25,   s * 0.60 ),
		Vector2( 0.0,        s * 0.40 ),
		Vector2(-s * 0.25,   s * 0.60 ),
		Vector2(-s * 0.38,  -s * 0.15 ),
	])
	var shard := Polygon2D.new()
	shard.polygon = shard_pts
	shard.color   = def.accent_color
	n.add_child(shard)

	# Pulse — glow ring breathes
	var pulse := get_tree().create_tween().set_loops()
	pulse.tween_property(gpoly, "color",
		Color(def.glow_color.r, def.glow_color.g, def.glow_color.b, 0.70), 1.2)
	pulse.tween_property(gpoly, "color",
		Color(def.glow_color.r, def.glow_color.g, def.glow_color.b, 0.15), 1.2)

	# Shard sparkle
	var ac: Color = def.accent_color
	var stween := get_tree().create_tween().set_loops()
	stween.tween_property(shard, "color", Color(ac.r, ac.g, ac.b, 1.0), 0.9)
	stween.tween_property(shard, "color", Color(ac.r, ac.g, ac.b, 0.45), 0.9)

	add_child(n)

	# Register with NodeManager so crystal mines know where to snap
	var node_manager = _hex_map.get_node_or_null("NodeManager") if _hex_map else null
	if node_manager != null and node_manager.has_method("register_crystal_node"):
		node_manager.register_crystal_node(hex_pos)

	return n

# ══════════════════════════════════════════════════════════════════════════════
# SPIKE TRAPS
# ══════════════════════════════════════════════════════════════════════════════
func _spawn_spikes() -> void:
	if _hex_map == null: return
	var treasure_nodes: Dictionary = {}
	var tn = _hex_map.get("treasure_nodes"); if tn != null: treasure_nodes = tn as Dictionary
	var hex_types: Dictionary = {}
	var ht = _hex_map.get("hex_types"); if ht != null: hex_types = ht as Dictionary

	const SPIKE_TRAP_COUNT := 12
	const SPIKE_BASE_HP    := 6
	const SAFE_RADIUS      := 4

	var candidates: Array = []
	for key in treasure_nodes.keys():
		var q0: int = (key as Vector2i).x;  var r0: int = (key as Vector2i).y
		for dq in range(-3, 4):
			for dr in range(-3, 4):
				var dist: int = maxi(abs(dq), maxi(abs(dr), abs(dq + dr)))
				if dist < 1 or dist > 3: continue
				var nk := Vector2i(q0 + dq, r0 + dr)
				if hex_types.get(nk, 0) != 0: continue  # 0 = NORMAL
				if maxi(abs(nk.x), maxi(abs(nk.y), abs(nk.x + nk.y))) < SAFE_RADIUS + 8: continue
				if not candidates.has(nk): candidates.append(nk)

	candidates.shuffle()
	var placed: Array = []
	for key in candidates:
		if placed.size() >= SPIKE_TRAP_COUNT: break
		if treasure_nodes.has(key): continue
		var hk := key as Vector2i
		var wp: Vector2 = hex_to_pixel(hk.x, hk.y)
		var node := _make_spike_trap(wp, hk)
		add_child(node)
		placed.append(key)
		if _hex_map.has_method("register_spike_trap"):
			_hex_map.register_spike_trap(hk, node, SPIKE_BASE_HP)

func _make_spike_trap(wp: Vector2, hk: Vector2i) -> Node2D:
	var n := Node2D.new()
	n.global_position = wp
	n.z_index         = 3;  n.z_as_relative = false
	n.add_to_group("spike_trap")
	n.set_meta("hex_key", hk)

	var bpts := PackedVector2Array()
	for i in 6:
		var a: float = deg_to_rad(60.0 * float(i) - 30.0)
		bpts.append(Vector2(cos(a), sin(a)) * 30.0)
	var bpoly := Polygon2D.new();  bpoly.polygon = bpts
	bpoly.color = Color(0.12, 0.10, 0.08);  n.add_child(bpoly)

	for si in 8:
		var a: float = TAU * float(si) / 8.0
		var tip: Vector2   = Vector2(cos(a), sin(a)) * 18.0
		var base1: Vector2 = Vector2(cos(a + 0.28), sin(a + 0.28)) * 6.0
		var base2: Vector2 = Vector2(cos(a - 0.28), sin(a - 0.28)) * 6.0
		var spoly := Polygon2D.new()
		spoly.polygon = PackedVector2Array([tip, base1, Vector2.ZERO, base2])
		spoly.color   = Color(0.65, 0.55, 0.40)
		n.add_child(spoly)

	var gpts := PackedVector2Array()
	for i in 16:
		var a: float = TAU * float(i) / 16.0
		gpts.append(Vector2(cos(a), sin(a)) * 22.0)
	var gring := Polygon2D.new();  gring.polygon = gpts
	gring.color = Color(0.8, 0.35, 0.05, 0.30)
	n.add_child(gring)
	n.set_meta("glow_ring", gring)

	var pulse := get_tree().create_tween().set_loops()
	pulse.tween_property(gring, "color", Color(0.8, 0.35, 0.05, 0.55), 1.0)
	pulse.tween_property(gring, "color", Color(0.8, 0.35, 0.05, 0.08), 1.0)
	n.set_meta("pulse_tween", pulse)
	return n

# ══════════════════════════════════════════════════════════════════════════════
# LIVING WORLD — spawn/batch/helpers/makers
# Scatter / return / flip behavior stays in hex_map.gd
# ══════════════════════════════════════════════════════════════════════════════
func _spawn_living_world() -> void:
	if _hex_map == null: return
	var hex_types: Dictionary = {}
	var ht = _hex_map.get("hex_types"); if ht != null: hex_types = ht as Dictionary
	var q_range: int = 75
	var r_range: int = 40
	var qr = _hex_map.get("Q_RANGE"); if qr != null: q_range = qr as int
	var rr = _hex_map.get("R_RANGE"); if rr != null: r_range = rr as int

	var candidates: Array = []
	for q in range(-q_range + 5, q_range - 5):
		for r in range(-r_range + 5, r_range - 5):
			if hex_types.get(Vector2i(q, r), 0) != 0: continue
			if maxi(abs(q), maxi(abs(r), abs(q + r))) < 6: continue
			candidates.append(Vector2i(q, r))
	candidates.shuffle()

	var used: Array = []
	_lw_batch(candidates, used, 4, _make_bog_mushrooms, false, "mushroom", 130.0)
	_lw_batch(candidates, used, 4, _make_hex_reeds,     false, "reeds",    110.0)
	_lw_batch(candidates, used, 3, _make_twisted_shrub, false, "shrub",    140.0)
	_lw_batch(candidates, used, 4, _make_stone_moss,    false, "moss",     120.0)
	_lw_batch(candidates, used, 2, _make_glowfly,       true,  "glowfly",  155.0)
	_lw_batch(candidates, used, 2, _make_hex_snail,     true,  "snail",    145.0)
	_lw_batch(candidates, used, 2, _make_marsh_frog,    true,  "frog",     160.0)
	_lw_batch(candidates, used, 2, _make_hex_crow,      true,  "crow",     160.0)

func _lw_batch(candidates: Array, used: Array, count: int, maker: Callable, is_fauna: bool, lw_type: String, min_dist: float) -> void:
	var placed := 0
	for c in candidates:
		if placed >= count: break
		var wp: Vector2 = hex_to_pixel((c as Vector2i).x, (c as Vector2i).y)
		var ok := true
		for p in used:
			if wp.distance_to(p as Vector2) < min_dist: ok = false; break
		if not ok: continue
		used.append(wp)
		var node: Node2D = maker.call(wp)
		node.z_index = -5;  node.z_as_relative = false
		node.set_meta("lw_is_fauna",     is_fauna)
		node.set_meta("lw_type",         lw_type)
		node.set_meta("lw_base_pos",     wp)
		node.set_meta("lw_scattered",    false)
		node.set_meta("lw_return_timer", 0.0)
		node.add_to_group("living_world")
		add_child(node)
		placed += 1

# ── LW helpers ────────────────────────────────────────────────────────────────
func _lw_make(wp: Vector2) -> Array:
	var co := Node2D.new();  co.global_position = wp
	var me := Node2D.new();  me.name = "Medieval"
	var fu := Node2D.new();  fu.name = "Future";  fu.visible = false
	co.add_child(me);  co.add_child(fu)
	return [co, me, fu]

func _lw_poly(parent: Node2D, pts: PackedVector2Array, col: Color) -> Polygon2D:
	var p := Polygon2D.new();  p.polygon = pts;  p.color = col
	parent.add_child(p);  return p

func _lw_line(parent: Node2D, pts: PackedVector2Array, col: Color, w: float, closed: bool = false) -> Line2D:
	var l := Line2D.new();  l.points = pts;  l.default_color = col;  l.width = w
	l.closed = closed;  parent.add_child(l);  return l

func _lw_circle_pts(cx: float, cy: float, rx: float, ry: float, n: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for j in n:
		var a: float = TAU * float(j) / float(n)
		pts.append(Vector2(cx + cos(a) * rx, cy + sin(a) * ry))
	return pts

# ── FL-A: Bog Mushrooms ───────────────────────────────────────────────────────
func _make_bog_mushrooms(wp: Vector2) -> Node2D:
	var res := _lw_make(wp);  var co: Node2D = res[0]; var me: Node2D = res[1]; var fu: Node2D = res[2]
	var CAP_DARK  := Color(0.30, 0.18, 0.07)
	var CAP_MID   := Color(0.48, 0.30, 0.13)
	var CAP_LIGHT := Color(0.55, 0.36, 0.16)
	var SPORE     := Color(0.06, 0.03, 0.01, 0.8)
	var GCYAN     := Color(0.0, 0.8, 0.6, 0.9)
	var GPHOSPHOR := Color(0.0, 0.95, 0.7, 0.9)
	var caps := [[ 0.0, 0.0, 11.0, 7.0, 8], [-9.5, -5.0, 7.0, 4.5, 6], [ 8.5, 6.5, 6.0, 3.5, 5]]
	for cap in caps:
		var cx: float = cap[0]; var cy: float = cap[1]
		var ro: float = cap[2]; var ri: float = cap[3]; var ns: int = cap[4]
		_lw_poly(me, _lw_circle_pts(cx, cy, ro, ro, 12), CAP_DARK)
		_lw_poly(me, _lw_circle_pts(cx, cy, ri, ri, 12), CAP_MID)
		_lw_poly(me, _lw_circle_pts(cx, cy, ri * 0.45, ri * 0.45, 8), CAP_LIGHT)
		for sj in ns:
			var sa: float = TAU * float(sj) / float(ns)
			_lw_poly(me, _lw_circle_pts(cx + cos(sa)*(ro*0.88), cy + sin(sa)*(ro*0.88), 1.0, 1.0, 5), SPORE)
	var idle := get_tree().create_tween().set_loops()
	idle.tween_property(me, "scale", Vector2(1.03, 1.03), 2.0)
	idle.tween_property(me, "scale", Vector2(1.0, 1.0), 2.0)
	for cap in caps:
		var cx: float = cap[0]; var cy: float = cap[1]; var ro: float = cap[2]; var ri: float = cap[3]
		_lw_line(fu, _lw_circle_pts(cx, cy, ro, ro, 12), GCYAN, 0.9, true)
		_lw_line(fu, _lw_circle_pts(cx, cy, ri, ri, 12), Color(0.0, 0.8, 0.6, 0.5), 0.6, true)
		_lw_poly(fu, _lw_circle_pts(cx, cy, 1.5, 1.5, 6), GPHOSPHOR)
	return co

# ── FL-B: Hex Reeds ───────────────────────────────────────────────────────────
func _make_hex_reeds(wp: Vector2) -> Node2D:
	var res := _lw_make(wp);  var co: Node2D = res[0]; var me: Node2D = res[1]; var fu: Node2D = res[2]
	var TIP    := Color(0.27, 0.34, 0.17);  var TIP_LT := Color(0.35, 0.44, 0.22)
	var SHADOW := Color(0.08, 0.10, 0.05, 0.5);  var GNODE := Color(0.0, 0.88, 0.5, 0.9)
	var GRING  := Color(0.0, 0.65, 0.35, 0.7)
	var tips := [[-8.0,-7.0,2.8,3.8],[-2.0,-12.0,3.2,4.5],[6.0,-9.0,2.5,3.5],[-6.5,1.0,2.2,3.2],[2.0,3.0,3.0,4.0],[9.0,0.0,2.0,3.0]]
	for td in tips:
		var cx: float = td[0]; var cy: float = td[1]; var rx: float = td[2]; var ry: float = td[3]
		_lw_poly(me, _lw_circle_pts(cx+0.8, cy+1.0, rx*0.7, ry*0.5, 8), SHADOW)
		_lw_poly(me, _lw_circle_pts(cx, cy, rx, ry, 10), TIP)
		_lw_poly(me, _lw_circle_pts(cx, cy, rx*0.45, ry*0.45, 6), TIP_LT)
		_lw_line(fu, _lw_circle_pts(cx, cy, rx, ry, 10), GRING, 0.8, true)
		_lw_poly(fu, _lw_circle_pts(cx, cy, 1.4, 1.4, 6), GNODE)
	return co

# ── FL-D: Twisted Shrub ───────────────────────────────────────────────────────
func _make_twisted_shrub(wp: Vector2) -> Node2D:
	var res := _lw_make(wp);  var co: Node2D = res[0]; var me: Node2D = res[1]; var fu: Node2D = res[2]
	var CANOPY_DARK := Color(0.10,0.14,0.06);  var CANOPY_MID := Color(0.16,0.23,0.10)
	var CANOPY_LT   := Color(0.22,0.32,0.14);  var BARK_CENTER := Color(0.14,0.10,0.05)
	var CTRACE      := Color(0.0,0.60,0.32,0.65);  var CPAD := Color(0.0,0.78,0.42,0.85)
	var lobes := [[0.0,-13.0,7.5,6.5],[11.5,-7.5,6.5,6.0],[13.5,4.5,6.0,5.5],[5.5,13.0,6.5,5.5],[-6.5,12.5,6.0,5.5],[-13.5,4.0,6.0,5.5],[-11.5,-8.0,6.5,6.0]]
	for lb in lobes: _lw_poly(me, _lw_circle_pts(lb[0],lb[1],lb[2],lb[3],10), CANOPY_DARK)
	for lb in lobes: _lw_poly(me, _lw_circle_pts(lb[0],lb[1],lb[2]*0.65,lb[3]*0.65,9), CANOPY_MID)
	_lw_poly(me, _lw_circle_pts(0.0,0.0,5.5,5.5,9), BARK_CENTER)
	_lw_poly(me, _lw_circle_pts(0.0,0.0,2.5,2.5,7), Color(0.08,0.06,0.03))
	for lb in lobes: _lw_poly(me, _lw_circle_pts(lb[0]*0.85,lb[1]*0.85,2.2,2.0,6), CANOPY_LT)
	for lb in lobes:
		var lx: float = lb[0]; var ly: float = lb[1]
		_lw_line(fu, _lw_circle_pts(lx,ly,3.5,3.5,6), CPAD, 0.85, true)
		_lw_poly(fu, _lw_circle_pts(lx,ly,1.4,1.4,6), CPAD)
		_lw_line(fu, PackedVector2Array([Vector2(lx*0.88,ly*0.88), Vector2(0.0,0.0)]), CTRACE, 0.75)
	_lw_poly(fu, _lw_circle_pts(0.0,0.0,2.8,2.8,7), Color(0.0,0.05,0.03))
	_lw_poly(fu, _lw_circle_pts(0.0,0.0,1.6,1.6,6), CPAD)
	return co

# ── FL-C: Stone Moss ──────────────────────────────────────────────────────────
func _make_stone_moss(wp: Vector2) -> Node2D:
	var res := _lw_make(wp);  var co: Node2D = res[0]; var me: Node2D = res[1]; var fu: Node2D = res[2]
	var MOSS_DARK  := Color(0.13,0.18,0.09);  var MOSS_MID := Color(0.17,0.24,0.12)
	var MOSS_LT    := Color(0.22,0.31,0.15);  var SPECK    := Color(0.28,0.40,0.18)
	var SCAN_GREEN := Color(0.0,0.80,0.42,0.72);  var NODE_GREEN := Color(0.0,0.95,0.55,0.90)
	_lw_poly(me, _lw_circle_pts(0.0,0.0,18.0,11.5,14), MOSS_DARK)
	_lw_poly(me, _lw_circle_pts(-3.5,-2.0,13.0,8.0,12), MOSS_MID)
	_lw_poly(me, _lw_circle_pts(4.0,2.0,8.0,5.5,10), MOSS_LT)
	_lw_poly(me, _lw_circle_pts(-14.0,-5.0,7.0,4.5,10), MOSS_DARK)
	_lw_poly(me, _lw_circle_pts(12.0,6.0,6.0,4.0,9), MOSS_MID)
	_lw_poly(me, _lw_circle_pts(-4.0,10.5,6.5,4.0,9), MOSS_DARK)
	var speckles := [Vector2(-8,-4),Vector2(-2,-7),Vector2(5,-4),Vector2(10,0),Vector2(7,6),Vector2(0,5),Vector2(-6,5),Vector2(-12,1),Vector2(-10,-9)]
	for sp in speckles: _lw_poly(me, _lw_circle_pts(sp.x,sp.y,1.2,1.2,5), SPECK)
	_lw_line(fu, _lw_circle_pts(0.0,0.0,18.0,11.5,14), SCAN_GREEN, 0.85, true)
	_lw_line(fu, _lw_circle_pts(0.0,0.0,12.0,7.5,12), Color(0.0,0.65,0.35,0.55), 0.65, true)
	_lw_line(fu, _lw_circle_pts(0.0,0.0,7.0,4.5,10), Color(0.0,0.55,0.28,0.4), 0.5, true)
	for iy in [-4,-1,2,5]:
		var sweep_w: float = sqrt(maxf(0.0, 18.0*18.0 - float(iy)*float(iy))) * 0.9
		_lw_line(fu, PackedVector2Array([Vector2(-sweep_w,float(iy)), Vector2(sweep_w,float(iy))]), Color(0.0,0.72,0.38,0.3), 0.5)
	for sp in speckles: _lw_poly(fu, _lw_circle_pts(sp.x,sp.y,1.4,1.4,5), NODE_GREEN)
	for sv in [Vector2(-14,-5), Vector2(12,6), Vector2(-4,10.5)]:
		_lw_line(fu, _lw_circle_pts(sv.x,sv.y,6.0,4.0,9), Color(0.0,0.65,0.35,0.5), 0.6, true)
	return co

# ── FA-A: Hex Crow ────────────────────────────────────────────────────────────
func _make_hex_crow(wp: Vector2) -> Node2D:
	var res := _lw_make(wp);  var co: Node2D = res[0]; var me: Node2D = res[1]
	var BLACK := Color(0.08,0.08,0.07);  var DKGRAY := Color(0.12,0.12,0.11)
	_lw_poly(me, _lw_circle_pts(0.0,0.0,7.5,4.5,10), BLACK)
	_lw_poly(me, PackedVector2Array([Vector2(0,0),Vector2(-12,-3),Vector2(-10,3),Vector2(-3,4)]), DKGRAY)
	_lw_poly(me, PackedVector2Array([Vector2(0,0),Vector2(10,-3),Vector2(8,3),Vector2(3,4)]), BLACK)
	_lw_poly(me, _lw_circle_pts(0.0,-6.0,5.0,4.5,9), BLACK)
	_lw_poly(me, PackedVector2Array([Vector2(2.5,-7.0),Vector2(8.5,-6.0),Vector2(5.0,-4.5)]), DKGRAY)
	_lw_poly(me, _lw_circle_pts(1.5,-7.0,1.2,1.2,6), Color(0.3,0.22,0.1,0.8))
	for sx in [-1.0,1.0]:
		_lw_line(me, PackedVector2Array([Vector2(sx*2.5,4.5),Vector2(sx*3.5,9.0)]), DKGRAY, 1.2)
		_lw_line(me, PackedVector2Array([Vector2(sx*3.5,9.0),Vector2(sx*6.0,11.0)]), DKGRAY, 0.9)
		_lw_line(me, PackedVector2Array([Vector2(sx*3.5,9.0),Vector2(sx*2.0,11.5)]), DKGRAY, 0.9)
	return co

# ── FA-C: Marsh Frog ──────────────────────────────────────────────────────────
func _make_marsh_frog(wp: Vector2) -> Node2D:
	var res := _lw_make(wp);  var co: Node2D = res[0]; var me: Node2D = res[1]; var fu: Node2D = res[2]
	var BODY  := Color(0.17,0.26,0.11);  var BELLY := Color(0.22,0.34,0.14)
	var SKIN  := Color(0.28,0.42,0.18);  var EYE   := Color(0.04,0.06,0.02)
	var GWIRE := Color(0.0,0.8,0.45,0.8);  var GEYE := Color(0.0,0.95,0.6,0.95)
	_lw_poly(me, _lw_circle_pts(0.0,2.0,13.0,9.0,14), BODY)
	_lw_poly(me, _lw_circle_pts(0.0,1.0,9.5,6.5,12), BELLY)
	_lw_poly(me, _lw_circle_pts(0.0,0.0,6.0,4.0,10), SKIN)
	_lw_poly(me, _lw_circle_pts(0.0,-9.5,5.5,5.0,10), BODY)
	for sx in [-1.0,1.0]:
		_lw_line(me, PackedVector2Array([Vector2(sx*7,-4),Vector2(sx*13,-8),Vector2(sx*15.5,-5)]), BODY, 2.8)
		_lw_line(me, PackedVector2Array([Vector2(sx*8,6),Vector2(sx*16,4),Vector2(sx*18.5,10),Vector2(sx*14,14)]), BODY, 2.8)
	for sx in [-1.0,1.0]:
		_lw_poly(me, _lw_circle_pts(sx*3.2,-11.5,3.0,3.0,8), BODY)
		_lw_poly(me, _lw_circle_pts(sx*3.2,-11.5,1.8,1.8,7), EYE)
	_lw_line(fu, _lw_circle_pts(0.0,2.0,13.0,9.0,14), GWIRE, 0.9, true)
	_lw_line(fu, _lw_circle_pts(0.0,-9.5,5.5,5.0,10), Color(0.0,0.65,0.35,0.65), 0.7, true)
	for sx in [-1.0,1.0]:
		for i in 2: _lw_line(fu, PackedVector2Array([Vector2(sx*7,-4),Vector2(sx*13,-8)]), Color(0.0,0.65,0.35,0.55), 0.8)
		for i in 3: _lw_line(fu, PackedVector2Array([Vector2(sx*8,6),Vector2(sx*16,4)]), Color(0.0,0.65,0.35,0.55), 0.8)
		_lw_line(fu, _lw_circle_pts(sx*3.2,-11.5,3.0,3.0,8), GWIRE, 0.8, true)
		_lw_poly(fu, _lw_circle_pts(sx*3.2,-11.5,1.5,1.5,6), GEYE)
	_lw_line(fu, _lw_circle_pts(0.0,2.0,17.5,13.0,18), Color(0.0,0.7,0.4,0.3), 0.7, true)
	return co

# ── FA-N1: Glowfly ────────────────────────────────────────────────────────────
func _make_glowfly(wp: Vector2) -> Node2D:
	var res := _lw_make(wp);  var co: Node2D = res[0]; var me: Node2D = res[1]; var fu: Node2D = res[2]
	var WING   := Color(0.10,0.17,0.10,0.68);  var WING2 := Color(0.09,0.15,0.09,0.58)
	var BODY   := Color(0.16,0.24,0.11);        var BODY_D := Color(0.12,0.18,0.08)
	var EYE    := Color(0.05,0.08,0.03)
	var GWIRE  := Color(0.0,0.82,0.46,0.80);   var GEYE  := Color(0.0,0.96,0.58,0.95)
	var GNODE  := Color(0.0,0.78,0.42,0.70)
	_lw_poly(me, _lw_circle_pts(-12,-6,11,6,10), WING);  _lw_poly(me, _lw_circle_pts(12,-6,11,6,10), WING)
	_lw_poly(me, _lw_circle_pts(-10,5,9,5,10), WING2);   _lw_poly(me, _lw_circle_pts(10,5,9,5,10), WING2)
	_lw_poly(me, _lw_circle_pts(0,0,3.5,14,12), BODY);   _lw_poly(me, _lw_circle_pts(0,0,2,9,10), BODY_D)
	for sy in [-6.0,-2.0,2.0,6.0,10.0]:
		_lw_line(me, PackedVector2Array([Vector2(-2.5,sy),Vector2(2.5,sy)]), Color(0.22,0.34,0.16,0.5), 0.6)
	_lw_poly(me, _lw_circle_pts(0,-14,3,3,8), BODY)
	_lw_poly(me, _lw_circle_pts(-2.2,-15.5,1.8,1.8,6), EYE);  _lw_poly(me, _lw_circle_pts(2.2,-15.5,1.8,1.8,6), EYE)
	_lw_line(fu, _lw_circle_pts(0,0,20,18,20), Color(0.0,0.72,0.40,0.28), 0.6, true)
	_lw_line(fu, _lw_circle_pts(-12,-6,11,6,10), GWIRE, 0.8, true);  _lw_line(fu, _lw_circle_pts(12,-6,11,6,10), GWIRE, 0.8, true)
	_lw_line(fu, _lw_circle_pts(-10,5,9,5,10), Color(0.0,0.65,0.35,0.6), 0.7, true);  _lw_line(fu, _lw_circle_pts(10,5,9,5,10), Color(0.0,0.65,0.35,0.6), 0.7, true)
	_lw_poly(fu, _lw_circle_pts(-22,-6,1.5,1.5,5), GNODE);  _lw_poly(fu, _lw_circle_pts(22,-6,1.5,1.5,5), GNODE)
	_lw_line(fu, _lw_circle_pts(0,0,3.5,14,12), GWIRE, 0.85, true)
	for sx in [-1,1]:
		_lw_poly(fu, _lw_circle_pts(sx*2.2,-15.5,2.2,2.2,6), GEYE)
		_lw_poly(fu, _lw_circle_pts(sx*2.2,-15.5,0.8,0.8,5), Color(0.0,1.0,0.65))
	return co

# ── FA-N2: Hex Snail ──────────────────────────────────────────────────────────
func _make_hex_snail(wp: Vector2) -> Node2D:
	var res := _lw_make(wp);  var co: Node2D = res[0]; var me: Node2D = res[1]; var fu: Node2D = res[2]
	var SHELL_D := Color(0.28,0.20,0.11);  var SHELL_M := Color(0.36,0.26,0.14)
	var SHELL_L := Color(0.44,0.32,0.17);  var SHELL_C := Color(0.18,0.12,0.06)
	var BODY    := Color(0.32,0.26,0.16);  var BODY_L  := Color(0.42,0.34,0.20)
	var EYE     := Color(0.06,0.04,0.02)
	var GWIRE   := Color(0.0,0.80,0.44,0.82);  var GEYE := Color(0.0,0.96,0.58,0.95)
	_lw_poly(me, _lw_circle_pts(-12,3,10,6,12), BODY);  _lw_poly(me, _lw_circle_pts(-12,2,7,4,10), BODY_L)
	_lw_poly(me, _lw_circle_pts(5,0,14,14,14), SHELL_D);  _lw_poly(me, _lw_circle_pts(5,0,9.5,9.5,12), SHELL_M)
	_lw_poly(me, _lw_circle_pts(5,0,5.5,5.5,10), SHELL_L);  _lw_poly(me, _lw_circle_pts(5,0,2.5,2.5,8), SHELL_M)
	_lw_poly(me, _lw_circle_pts(5,0,1,1,6), SHELL_C)
	_lw_line(me, PackedVector2Array([Vector2(-18,-1),Vector2(-22,-5)]), BODY, 1.0)
	_lw_line(me, PackedVector2Array([Vector2(-18,5),Vector2(-22,9)]), BODY, 1.0)
	_lw_poly(me, _lw_circle_pts(-22.5,-5.5,1.8,1.8,6), EYE);  _lw_poly(me, _lw_circle_pts(-22.5,9.5,1.8,1.8,6), EYE)
	_lw_line(fu, _lw_circle_pts(-12,3,10,6,12), Color(0.0,0.65,0.35,0.55), 0.7, true)
	for ri in 4:
		var rads := [14.0,9.5,5.5,2.5];  var alphas := [0.45,0.58,0.72,0.88]
		_lw_line(fu, _lw_circle_pts(5,0,rads[ri],rads[ri],14-ri*2), Color(0.0,0.72+ri*0.07,0.40+ri*0.06,alphas[ri]), 0.7+ri*0.05, true)
	var spiral_pts := PackedVector2Array()
	for si in 20:
		var sa: float = TAU*float(si)/20.0*1.5;  var sr: float = 13.5*(1.0-float(si)/28.0)
		spiral_pts.append(Vector2(5.0+cos(sa)*sr, sin(sa)*sr))
	_lw_line(fu, spiral_pts, Color(0.0,0.60,0.32,0.28), 0.5)
	_lw_poly(fu, _lw_circle_pts(5,0,1.4,1.4,6), Color(0.0,0.95,0.58,0.9))
	for sv in [Vector2(-22.5,-5.5), Vector2(-22.5,9.5)]:
		_lw_poly(fu, _lw_circle_pts(sv.x,sv.y,2.2,2.2,6), GEYE)
		_lw_poly(fu, _lw_circle_pts(sv.x,sv.y,0.8,0.8,5), Color(0.0,1.0,0.65))
	return co
