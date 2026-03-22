extends Node2D

const HEX_SIZE   := 35.0
const R_RANGE    := 40
const Q_RANGE    := 75
const MAP_CENTER := Vector2(3330.0, 2100.0)
const WORLD_W    := 6660.0
const WORLD_H    := 4200.0

# ── Hex terrain types ──────────────────────────────────────────────────────────
enum HexType { NORMAL, PIT, BLOCK, CRACKED }

# ── Two sealed worlds ─────────────────────────────────────────────────────────
enum OverworldBiome { GRASSLAND, MARSH, FOREST, ASH_PLAIN, SAND, MAGMA, ICE, WATER }
enum FutureBiome    { GRID_BASE, CIRCUIT, CORRUPTED, VOID_RIFT, STATIC_FIELD, FROZEN_DATA, DARK_POOL, DEAD_SAND }

# ── Terrain config — tune these to taste ──────────────────────────────────────
const PIT_CHANCE   := 0.008  # 0.8% — sparse pits, biome fills dominate
const BLOCK_CHANCE := 0.008  # 0.8% — sparse rocks, biome fills dominate
const SAFE_RADIUS  := 4      # hex distance from center kept clear of hazards

# ── Tile PNG paths — drop PNGs into res://art/vextiles/ ───────────────────────
const TILE_PIT     := "res://art/vextiles/hex_pit.png"
const TILE_CRACKED := "res://art/vextiles/hex_block.png"   # reuse block art until cracked sprite exists
const TILE_BLOCK := "res://art/vextiles/hex_block.png"

# ── Live terrain map: Vector2i(q,r) → HexType ─────────────────────────────────
var hex_types: Dictionary = {}
var hex_states: Dictionary = {}      # Vector2i(q,r) -> int  0=pristine … 4=critical
var hex_rotations: Dictionary = {}   # Vector2i(q,r) -> int  0-5  (×60°)
var _overlay_drawer = null
var _biome_spr_ow   = null   # Sprite2D — overworld biome fill layer
var _biome_spr_fut  = null   # Sprite2D — future biome fill layer (hidden until flip)
var _grid_spr_ow    = null   # Sprite2D — OW grid lines (dark stone mortar)
var _grid_spr_fut   = null   # Sprite2D — Future grid lines (bright neon, hidden until flip)
var hex_biomes_ow:  Dictionary = {}
var treasure_nodes: Dictionary = {}  # Vector2i(q,r) → Node2D (cleared on pickup)
var spike_traps:     Dictionary = {}  # Vector2i(q,r) → {node, hp, recharge_timer, active}  # Vector2i(q,r) → Node2D (cleared on pickup)   # Vector2i(q,r) → OverworldBiome int
var hex_biomes_fut: Dictionary = {}   # Vector2i(q,r) → FutureBiome int
var hex_blend_ow:   Dictionary = {}   # Vector2i(q,r) → {neighbor:int, intensity:float}
var hex_blend_fut:  Dictionary = {}   # same for dark future world
var is_future_mode: bool = false

func _ready() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)

	# 1. Generate terrain + biomes before any baking
	_generate_terrain()
	_generate_biomes()

	# 2. Bake overworld biome fill layer (z=-101)
	var sv_ow := SubViewport.new()
	sv_ow.size = Vector2i(int(WORLD_W), int(WORLD_H))
	sv_ow.render_target_update_mode = SubViewport.UPDATE_ONCE
	sv_ow.render_target_clear_mode  = SubViewport.CLEAR_MODE_ONCE
	sv_ow.transparent_bg = false
	add_child(sv_ow)
	var bd_ow := _BiomeDrawer.new()
	bd_ow.hex_biomes = hex_biomes_ow
	bd_ow.hex_blend  = hex_blend_ow
	bd_ow.is_future  = false
	sv_ow.add_child(bd_ow)

	# 3. Bake dark future biome fill layer (z=-101, hidden until flip)
	var sv_fut := SubViewport.new()
	sv_fut.size = Vector2i(int(WORLD_W), int(WORLD_H))
	sv_fut.render_target_update_mode = SubViewport.UPDATE_ONCE
	sv_fut.render_target_clear_mode  = SubViewport.CLEAR_MODE_ONCE
	sv_fut.transparent_bg = false
	add_child(sv_fut)
	var bd_fut := _BiomeDrawer.new()
	bd_fut.hex_biomes = hex_biomes_fut
	bd_fut.hex_blend  = hex_blend_fut
	bd_fut.is_future  = true
	sv_fut.add_child(bd_fut)

	# 4. Bake OW grid lines — dark stone mortar, transparent bg
	var sv_grid_ow := SubViewport.new()
	sv_grid_ow.size = Vector2i(int(WORLD_W), int(WORLD_H))
	sv_grid_ow.render_target_update_mode = SubViewport.UPDATE_ONCE
	sv_grid_ow.render_target_clear_mode  = SubViewport.CLEAR_MODE_ONCE
	sv_grid_ow.transparent_bg = true
	add_child(sv_grid_ow)
	var drawer_ow := _GridDrawer.new()
	drawer_ow.hex_types   = hex_types
	drawer_ow.hex_biomes  = hex_biomes_ow
	drawer_ow.is_future   = false
	sv_grid_ow.add_child(drawer_ow)

	# 5. Bake Future grid lines — bright neon, transparent bg
	var sv_grid_fut := SubViewport.new()
	sv_grid_fut.size = Vector2i(int(WORLD_W), int(WORLD_H))
	sv_grid_fut.render_target_update_mode = SubViewport.UPDATE_ONCE
	sv_grid_fut.render_target_clear_mode  = SubViewport.CLEAR_MODE_ONCE
	sv_grid_fut.transparent_bg = true
	add_child(sv_grid_fut)
	var drawer_fut := _GridDrawer.new()
	drawer_fut.hex_types  = hex_types
	drawer_fut.hex_biomes = hex_biomes_fut
	drawer_fut.is_future  = true
	sv_grid_fut.add_child(drawer_fut)

	# 6. Biome fill sprites (z=-101)
	var biome_spr_ow := Sprite2D.new()
	biome_spr_ow.texture       = sv_ow.get_texture()
	biome_spr_ow.position      = MAP_CENTER
	biome_spr_ow.centered      = true
	biome_spr_ow.z_index       = -101
	biome_spr_ow.z_as_relative = false
	add_child(biome_spr_ow)
	_biome_spr_ow = biome_spr_ow

	var biome_spr_fut := Sprite2D.new()
	biome_spr_fut.texture       = sv_fut.get_texture()
	biome_spr_fut.position      = MAP_CENTER
	biome_spr_fut.centered      = true
	biome_spr_fut.z_index       = -101
	biome_spr_fut.z_as_relative = false
	biome_spr_fut.visible       = false
	add_child(biome_spr_fut)
	_biome_spr_fut = biome_spr_fut

	# 7. Grid line sprites (z=-100) — OW visible, Future hidden
	var grid_spr_ow := Sprite2D.new()
	grid_spr_ow.texture       = sv_grid_ow.get_texture()
	grid_spr_ow.position      = MAP_CENTER
	grid_spr_ow.centered      = true
	grid_spr_ow.z_index       = -100
	grid_spr_ow.z_as_relative = false
	grid_spr_ow.visible       = false
	add_child(grid_spr_ow)
	_grid_spr_ow = grid_spr_ow

	var grid_spr_fut := Sprite2D.new()
	grid_spr_fut.texture       = sv_grid_fut.get_texture()
	grid_spr_fut.position      = MAP_CENTER
	grid_spr_fut.centered      = true
	grid_spr_fut.z_index       = -100
	grid_spr_fut.z_as_relative = false
	grid_spr_fut.visible       = false
	add_child(grid_spr_fut)
	_grid_spr_fut = grid_spr_fut

	# 8. Wait two frames for all five SubViewports to bake
	await get_tree().process_frame
	await get_tree().process_frame
	grid_spr_ow.visible = true   # OW grid starts visible
	sv_grid_ow.render_target_update_mode  = SubViewport.UPDATE_DISABLED
	sv_grid_fut.render_target_update_mode = SubViewport.UPDATE_DISABLED
	sv_ow.render_target_update_mode       = SubViewport.UPDATE_DISABLED
	sv_fut.render_target_update_mode      = SubViewport.UPDATE_DISABLED

	# 8. Spawn tile sprites for special hexes on top of the baked grid
	_spawn_tile_sprites()
	# 9. WorldSpawner handles: crystals, treasure nodes, crystal node markers,
	#    spike traps, and living world
	$WorldSpawner.spawn_all(self)
	# 10. Reactive tile overlay system
	_overlay_drawer = _OverlayDrawer.new()
	_overlay_drawer.hex_states    = hex_states
	_overlay_drawer.hex_rotations = hex_rotations
	_overlay_drawer.z_index       = -8
	_overlay_drawer.z_as_relative = false
	add_child(_overlay_drawer)

# ── Terrain generation ────────────────────────────────────────────────────────
# ── Border + clump settings ──────────────────────────────────────────────────
const BORDER_THICKNESS := 3     # hexes of solid rock around the edge
const CLUMP_CHANCE     := 0.35  # reduced — keeps border natural without heavy scatter
const CLUMP_RADIUS     := 2     # how far clumping can spread inward from border

# ── Border helper: true rectangular boundary check ───────────────────────────
# A hex is "on border" if it's within BORDER_THICKNESS of the grid edge.
# Uses the actual q/r rectangle, not hex-distance, so all 4 sides are uniform.
func _is_border(q: int, r: int, thickness: int) -> bool:
	return (abs(q) >= Q_RANGE - thickness or
		abs(r) >= R_RANGE - thickness or
		abs(q + r) >= Q_RANGE + R_RANGE - thickness)

func _generate_terrain() -> void:
	hex_types.clear()
	hex_rotations.clear()
	hex_states.clear()

	# ── Pass 1: scatter interior terrain ─────────────────────────────────────
	for q in range(-Q_RANGE, Q_RANGE + 1):
		for r in range(-R_RANGE, R_RANGE + 1):
			var hex_dist: int = maxi(abs(q), maxi(abs(r), abs(q + r)))
			if hex_dist <= SAFE_RADIUS:
				continue
			if _is_border(q, r, BORDER_THICKNESS + CLUMP_RADIUS):
				continue   # reserve full border+clump zone
			var roll: float = randf()
			if roll < PIT_CHANCE:
				hex_types[Vector2i(q, r)] = HexType.PIT
			elif roll < PIT_CHANCE + BLOCK_CHANCE:
				hex_types[Vector2i(q, r)] = HexType.BLOCK
			elif roll < PIT_CHANCE + BLOCK_CHANCE + 0.003:
				hex_types[Vector2i(q, r)] = HexType.CRACKED

	# ── Seed random rotations for every hex (NORMAL gets 0-5, others ignored visually) ──
	for q2 in range(-Q_RANGE, Q_RANGE + 1):
		for r2 in range(-R_RANGE, R_RANGE + 1):
			hex_rotations[Vector2i(q2, r2)] = randi() % 6

	# ── Pass 2: solid rock border ring — full perimeter ──────────────────────
	for q in range(-Q_RANGE, Q_RANGE + 1):
		for r in range(-R_RANGE, R_RANGE + 1):
			if _is_border(q, r, BORDER_THICKNESS):
				hex_types[Vector2i(q, r)] = HexType.BLOCK

	# ── Pass 3: natural clumping inward from border ───────────────────────────
	for q in range(-Q_RANGE, Q_RANGE + 1):
		for r in range(-R_RANGE, R_RANGE + 1):
			if hex_types.has(Vector2i(q, r)):
				continue   # already assigned
			if not _is_border(q, r, BORDER_THICKNESS + CLUMP_RADIUS):
				continue   # outside clump zone
			# Measure how deep inside the clump zone this hex is (0=right at border)
			# Count how many border-thickness steps away from the solid ring
			var depth: int = 0
			for d in range(1, CLUMP_RADIUS + 1):
				if _is_border(q, r, BORDER_THICKNESS + d - 1):
					depth = d - 1
					break
			var chance: float = CLUMP_CHANCE * (1.0 - float(depth) / float(CLUMP_RADIUS))
			if randf() < chance:
				hex_types[Vector2i(q, r)] = HexType.BLOCK

# ── Terrain query — call from player.gd / enemy_spawner.gd ───────────────────
func get_hex_type(q: int, r: int) -> HexType:
	var key := Vector2i(q, r)
	if hex_types.has(key):
		return hex_types[key] as HexType
	return HexType.NORMAL

func crack_hex(world_pos: Vector2) -> void:
	# Call when player steps on a cracked hex — converts to pit
	var h: Vector2i = pixel_to_hex(world_pos)
	if hex_types.get(h, HexType.NORMAL) == HexType.CRACKED:
		hex_types[h] = HexType.PIT
		# Update any existing sprite at this hex to pit texture
		for child in get_children():
			if child is Sprite2D and child.position.distance_to(hex_to_pixel(h.x, h.y)) < 5.0:
				if ResourceLoader.exists(TILE_PIT):
					child.texture = load(TILE_PIT)
				break

func pixel_to_hex(world_pos: Vector2) -> Vector2i:
	var p: Vector2 = world_pos - MAP_CENTER
	var q: int = int(round((sqrt(3.0) / 3.0 * p.x - 1.0 / 3.0 * p.y) / HEX_SIZE))
	var r: int = int(round((2.0 / 3.0 * p.y) / HEX_SIZE))
	return Vector2i(q, r)

func is_passable(world_pos: Vector2) -> bool:
	var h: Vector2i = pixel_to_hex(world_pos)
	return get_hex_type(h.x, h.y) != HexType.BLOCK

# ── Spawn Sprite2D tiles for Pit and Block hexes ──────────────────────────────
func _spawn_tile_sprites() -> void:
	# Pre-biome PNG sprites removed — biome fill layers and _GridDrawer
	# handle all tile visuals. PIT/BLOCK/CRACKED gameplay types are intact;
	# only the old texture overlays are gone.
	pass

func hex_to_pixel(q: int, r: int) -> Vector2:
	return Vector2(
		HEX_SIZE * (sqrt(3.0) * float(q) + sqrt(3.0) / 2.0 * float(r)),
		HEX_SIZE * 1.5 * float(r)
	) + MAP_CENTER

# ── Inner class draws the grid inside the SubViewport ─────────────────────────
class _GridDrawer extends Node2D:
	const S    = 35.0
	const Q    = 75
	const R    = 40
	const W    = 6660.0
	const H    = 4200.0
	const CX   = W / 2.0
	const CY   = H / 2.0
	const FILL        = Color(0.10, 0.40, 0.60, 1.0)
	const EDGE        = Color(0.00, 0.75, 0.95, 1.0)
	const FILL_PIT    = Color(0.04, 0.04, 0.06, 1.0)   # near-black void
	const FILL_BLOCK  = Color(0.20, 0.15, 0.10, 1.0)   # warm dark earth — fits biome palette
	const EDGE_PIT    = Color(0.10, 0.10, 0.15, 1.0)
	const EDGE_BLOCK  = Color(0.28, 0.22, 0.16, 1.0)

	var _lines      := PackedVector2Array()
	var _pit_polys  : Array = []   # Array of PackedVector2Array
	var _block_polys: Array = []
	var hex_types:  Dictionary = {}
	var hex_biomes: Dictionary = {}   # OW or Future biome dict injected at bake time
	var is_future:  bool = false
	# Pointy-top axial neighbor directions per edge index 0-5
	const NB_DIRS := [
		Vector2i( 1,  0), Vector2i( 0,  1), Vector2i(-1,  1),
		Vector2i(-1,  0), Vector2i( 0, -1), Vector2i( 1, -1)
	]

	func _ready() -> void:
		for q in range(-Q, Q + 1):
			for r in range(-R, R + 1):
				var c := _p(q, r)
				if c.x < 0.0 or c.x > W or c.y < 0.0 or c.y > H:
					continue
				var key := Vector2i(q, r)
				var htype: int = hex_types.get(key, 0)   # 0 = NORMAL

				# Build hex polygon for pit/block/cracked coloring
				if htype == 1 or htype == 2 or htype == 3:   # PIT, BLOCK, CRACKED
					var pts := PackedVector2Array()
					for i in 6:
						var a: float = deg_to_rad(60.0 * float(i) - 30.0)
						pts.append(c + Vector2(cos(a), sin(a)) * S)
					if htype == 1:
						_pit_polys.append(pts)
					else:
						_block_polys.append(pts)

				# Grid lines — shared edge suppression:
				# Only draw an edge if the neighbor differs in type OR biome,
				# or is outside the map. NORMAL hexes may not be in hex_types
				# dict so we default to 0 (NORMAL), not -1.
				var my_biome: int = hex_biomes.get(key, -1)
				for i in 6:
					var nb_key: Vector2i = key + NB_DIRS[i]
					# Hard boundary — always draw map-edge lines
					if nb_key.x < -Q or nb_key.x > Q or nb_key.y < -R or nb_key.y > R:
						var a0 := deg_to_rad(60.0 * float(i)     - 30.0)
						var a1 := deg_to_rad(60.0 * float(i + 1) - 30.0)
						_lines.append(c + Vector2(cos(a0), sin(a0)) * S)
						_lines.append(c + Vector2(cos(a1), sin(a1)) * S)
						continue
					# Default 0 = NORMAL for hexes not explicitly stored
					var nb_type: int  = hex_types.get(nb_key, 0)
					var nb_biome: int = hex_biomes.get(nb_key, -2)
					# Same type AND same biome → shared interior edge, suppress
					if nb_type == htype and nb_biome == my_biome and my_biome != -1:
						continue
					var a0 := deg_to_rad(60.0 * float(i)     - 30.0)
					var a1 := deg_to_rad(60.0 * float(i + 1) - 30.0)
					_lines.append(c + Vector2(cos(a0), sin(a0)) * S)
					_lines.append(c + Vector2(cos(a1), sin(a1)) * S)
		queue_redraw()

	func _draw() -> void:
		# Base fill is now drawn by _BiomeDrawer — grid is transparent
		# Grid line colour: OW = dark stone mortar, Future = bright neon cyan
		var edge_col: Color = Color(0.14, 0.11, 0.08, 0.85) if not is_future else Color(0.0, 0.88, 1.0, 1.0)
		var line_w: float   = 0.8 if not is_future else 1.2
		# Draw pit / block fills
		for pts in _pit_polys:
			draw_colored_polygon(pts, FILL_PIT)
			draw_polyline(pts, EDGE_PIT, line_w)
		for pts in _block_polys:
			draw_colored_polygon(pts, FILL_BLOCK)
			draw_polyline(pts, EDGE_BLOCK, line_w)
		# Grid lines
		draw_multiline(_lines, edge_col, line_w)

	func _p(q: int, r: int) -> Vector2:
		return Vector2(
			S * (sqrt(3.0)*float(q) + sqrt(3.0)/2.0*float(r)) + CX,
			S * 1.5 * float(r) + CY
		)

# ─── Treasure Nodes ───────────────────────────────────────────────────────────
const TREASURE_NODE_COUNT := 18     # nodes placed per run
const TREASURE_MIN_DIST   := 8      # min hex distance between nodes
const TREASURE_MIN_CASTLE := 12     # must be this far from castle center

func _spawn_treasure_nodes() -> void:
	treasure_nodes.clear()
	var candidates: Array = []
	for q in range(-Q_RANGE + 6, Q_RANGE - 6):
		for r in range(-R_RANGE + 4, R_RANGE - 4):
			var key := Vector2i(q, r)
			if hex_types.get(key, HexType.NORMAL) != HexType.NORMAL:
				continue
			var d: int = maxi(abs(q), maxi(abs(r), abs(q + r)))
			if d < TREASURE_MIN_CASTLE:
				continue
			candidates.append(key)
	candidates.shuffle()
	var placed: Array = []
	for key in candidates:
		if placed.size() >= TREASURE_NODE_COUNT:
			break
		var wp: Vector2 = hex_to_pixel((key as Vector2i).x, (key as Vector2i).y)
		var too_close := false
		for p in placed:
			var pq: int = (p as Vector2i).x;  var pr: int = (p as Vector2i).y
			var dist: int = maxi(abs((key as Vector2i).x - pq),
								maxi(abs((key as Vector2i).y - pr),
								abs((key as Vector2i).x + (key as Vector2i).y - pq - pr)))
			if dist < TREASURE_MIN_DIST:
				too_close = true;  break
		if too_close:
			continue
		placed.append(key)
		var node := _make_treasure_node(wp)
		node.set_meta("hex_key", key)
		treasure_nodes[key] = node
		add_child(node)

func _make_treasure_node(wp: Vector2) -> Node2D:
	var n := Node2D.new()
	n.global_position = wp
	n.z_index = 2;  n.z_as_relative = false
	n.add_to_group("treasure_node")

	# Outer glow ring — soft amber pulse
	var gpts := PackedVector2Array()
	for i in 18:
		var a: float = TAU * float(i) / 18.0
		gpts.append(Vector2(cos(a), sin(a)) * 20.0)
	var gpoly := Polygon2D.new()
	gpoly.polygon = gpts;  gpoly.color = Color(0.85, 0.62, 0.08, 0.30)
	n.add_child(gpoly)

	# Main hex body
	var hpts := PackedVector2Array()
	for i in 6:
		var a: float = deg_to_rad(60.0 * float(i) - 30.0)
		hpts.append(Vector2(cos(a), sin(a)) * 13.0)
	var hpoly := Polygon2D.new()
	hpoly.polygon = hpts;  hpoly.color = Color(0.88, 0.72, 0.15, 0.95)
	n.add_child(hpoly)

	# Inner jewel dot
	var jpts := PackedVector2Array()
	for i in 8:
		var a: float = TAU * float(i) / 8.0
		jpts.append(Vector2(cos(a), sin(a)) * 5.0)
	var jpoly := Polygon2D.new()
	jpoly.polygon = jpts;  jpoly.color = Color(1.0, 0.92, 0.45, 1.0)
	n.add_child(jpoly)
	n.set_meta("glow_poly", gpoly)

	# Idle breathe pulse on glow ring
	var pulse := get_tree().create_tween().set_loops()
	pulse.tween_property(gpoly, "color",
		Color(0.85, 0.62, 0.08, 0.65), 1.1)
	pulse.tween_property(gpoly, "color",
		Color(0.85, 0.62, 0.08, 0.15), 1.1)
	return n

func remove_treasure_node(hex_key: Vector2i) -> void:
	if not treasure_nodes.has(hex_key): return
	var node = treasure_nodes[hex_key]
	if is_instance_valid(node):
		(node as Node).queue_free()
	treasure_nodes.erase(hex_key)


func register_treasure_node(hex_key: Vector2i, node: Node2D) -> void:
	treasure_nodes[hex_key] = node

func register_spike_trap(hex_key: Vector2i, node: Node2D, hp: int) -> void:
	spike_traps[hex_key] = {"node": node, "hp": hp, "recharge": 0.0, "alive": true}

# ─── Spike Trap System ────────────────────────────────────────────────────────
const SPIKE_TRAP_COUNT    := 12     # total traps per map
const SPIKE_NEEDLE_RANGE  := 3      # hexes needles travel
const SPIKE_RECHARGE_TIME := 3.0    # seconds between fires
const SPIKE_BASE_HP       := 6      # hits to destroy a trap

func _spawn_spike_traps() -> void:
	spike_traps.clear()
	# Bias placement: near treasure nodes + open terrain
	var candidates: Array = []
	for key in treasure_nodes.keys():
		# Ring of hexes 1-3 distance from each treasure node
		var q0: int = (key as Vector2i).x;  var r0: int = (key as Vector2i).y
		for dq in range(-3, 4):
			for dr in range(-3, 4):
				var dist: int = maxi(abs(dq), maxi(abs(dr), abs(dq+dr)))
				if dist < 1 or dist > 3: continue
				var nk := Vector2i(q0+dq, r0+dr)
				if hex_types.get(nk, HexType.NORMAL) != HexType.NORMAL: continue
				if maxi(abs(nk.x), maxi(abs(nk.y), abs(nk.x+nk.y))) < SAFE_RADIUS + 8: continue
				if not candidates.has(nk): candidates.append(nk)
	candidates.shuffle()
	var placed: Array = []
	for key in candidates:
		if placed.size() >= SPIKE_TRAP_COUNT: break
		if treasure_nodes.has(key): continue  # don't overlap treasure node hex
		var wp: Vector2 = hex_to_pixel((key as Vector2i).x, (key as Vector2i).y)
		var node := _make_spike_trap(wp, key as Vector2i)
		spike_traps[key] = {"node": node, "hp": SPIKE_BASE_HP,
							"recharge": 0.0, "alive": true}
		placed.append(key)
		add_child(node)

func _make_spike_trap(wp: Vector2, hk: Vector2i) -> Node2D:
	var n := Node2D.new()
	n.global_position = wp
	n.z_index = 3;  n.z_as_relative = false
	n.add_to_group("spike_trap")
	n.set_meta("hex_key", hk)

	# Base hex floor — dark charcoal
	var bpts := PackedVector2Array()
	for i in 6:
		var a: float = deg_to_rad(60.0*float(i)-30.0)
		bpts.append(Vector2(cos(a),sin(a))*30.0)
	var bpoly := Polygon2D.new();  bpoly.polygon = bpts
	bpoly.color = Color(0.12, 0.10, 0.08);  n.add_child(bpoly)

	# 8 spike points radiating from center
	for si in 8:
		var a: float = TAU * float(si) / 8.0
		var tip: Vector2  = Vector2(cos(a), sin(a)) * 18.0
		var base1: Vector2 = Vector2(cos(a + 0.28), sin(a + 0.28)) * 6.0
		var base2: Vector2 = Vector2(cos(a - 0.28), sin(a - 0.28)) * 6.0
		var spoly := Polygon2D.new()
		spoly.polygon = PackedVector2Array([tip, base1, Vector2.ZERO, base2])
		spoly.color = Color(0.65, 0.55, 0.40)
		n.add_child(spoly)

	# Armed glow ring
	var gpts := PackedVector2Array()
	for i in 16:
		var a: float = TAU * float(i) / 16.0
		gpts.append(Vector2(cos(a),sin(a))*22.0)
	var gring := Polygon2D.new();  gring.polygon = gpts
	gring.color = Color(0.8, 0.35, 0.05, 0.30)
	n.add_child(gring)
	n.set_meta("glow_ring", gring)

	# Idle pulse on armed glow
	var pulse := get_tree().create_tween().set_loops()
	pulse.tween_property(gring, "color", Color(0.8,0.35,0.05,0.55), 1.0)
	pulse.tween_property(gring, "color", Color(0.8,0.35,0.05,0.08), 1.0)
	n.set_meta("pulse_tween", pulse)
	return n

# Called each physics frame from enemy_spawner and player
func trigger_spike_trap(hex_key: Vector2i, source_node: Node2D) -> void:
	if not spike_traps.has(hex_key): return
	var trap = spike_traps[hex_key]
	if not (trap["alive"] as bool): return
	if (trap["recharge"] as float) > 0.0: return
	var trap_node: Node2D = trap["node"] as Node2D
	if not is_instance_valid(trap_node): return
	trap["recharge"] = SPIKE_RECHARGE_TIME
	_fire_spike_trap(hex_key, trap_node)

func _fire_spike_trap(hex_key: Vector2i, trap_node: Node2D) -> void:
	# Flash the trap
	var gring = trap_node.get_meta("glow_ring") as Polygon2D
	var flash_tw := get_tree().create_tween()
	flash_tw.tween_property(gring, "color", Color(1.0, 0.6, 0.1, 0.95), 0.06)
	flash_tw.tween_property(gring, "color", Color(0.8, 0.35, 0.05, 0.30), 0.25)

	# Fire 20 needles in all directions
	var needle_range_px: float = SPIKE_NEEDLE_RANGE * HEX_SIZE * 2.0
	var trap_pos: Vector2 = trap_node.global_position
	for ni in 20:
		var angle: float = TAU * float(ni) / 20.0 + randf_range(-0.1, 0.1)
		var needle := Node2D.new()
		needle.global_position = trap_pos
		needle.z_index = 5;  needle.z_as_relative = false
		var nline := Line2D.new()
		nline.points = PackedVector2Array([Vector2.ZERO, Vector2(cos(angle),sin(angle))*12.0])
		nline.width = 2.5
		nline.default_color = Color(0.80, 0.65, 0.35, 0.95)
		needle.add_child(nline)
		get_parent().add_child(needle) if get_parent() != null else add_child(needle)
		var tw := get_tree().create_tween()
		tw.set_parallel(true)
		tw.tween_property(needle, "position",
			Vector2(cos(angle),sin(angle)) * needle_range_px, 0.28)
		tw.tween_property(nline, "default_color",
			Color(0.80,0.65,0.35,0.0), 0.28)
		tw.set_parallel(false)
		tw.tween_callback(needle.queue_free)

	# Hit detection — damage player, enemies, and chain to adjacent traps
	_spike_hit_check(hex_key, trap_pos)

func _spike_hit_check(origin_hex: Vector2i, trap_pos: Vector2) -> void:
	var needle_px: float = SPIKE_NEEDLE_RANGE * HEX_SIZE * 2.2

	# Hit player
	var player = get_parent().get_node_or_null("Player")
	if player != null and is_instance_valid(player):
		if (player as Node2D).global_position.distance_to(trap_pos) <= needle_px:
			if (player as Node).has_method("take_damage"):
				(player as Node).call("take_damage", 1.0)

	# Hit enemies
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy): continue
		if (enemy as Node2D).global_position.distance_to(trap_pos) <= needle_px:
			var spawner = get_parent().get_node_or_null("EnemySpawner")
			if spawner != null and spawner.has_method("on_bullet_hit"):
				# Create a dummy area or just damage directly via meta
				var hp: float = (enemy as Area2D).get_meta("hp")
				hp -= 2.0
				(enemy as Area2D).set_meta("hp", hp)
				if hp <= 0:
					spawner.call("handle_turret_kill", enemy as Area2D)

	# Chain to adjacent traps within needle range
	for tk in spike_traps.keys():
		if (tk as Vector2i) == origin_hex: continue
		var other = spike_traps[tk]
		if not (other["alive"] as bool): continue
		var other_node: Node2D = other["node"] as Node2D
		if not is_instance_valid(other_node): continue
		if other_node.global_position.distance_to(trap_pos) <= needle_px:
			# Needle hit — damage and potentially trigger
			other["hp"] = (other["hp"] as int) - 1
			if (other["hp"] as int) <= 0:
				_destroy_spike_trap(tk as Vector2i)
			else:
				# Chain fire (override recharge)
				other["recharge"] = 0.0
				if is_inside_tree(): get_tree().create_timer(0.12).timeout.connect(func():
					if is_instance_valid(self) and spike_traps.has(tk):
						_fire_spike_trap(tk as Vector2i, other["node"] as Node2D)
				)

func _destroy_spike_trap(hex_key: Vector2i) -> void:
	if not spike_traps.has(hex_key): return
	var trap = spike_traps[hex_key]
	trap["alive"] = false
	var trap_node: Node2D = trap["node"] as Node2D
	if is_instance_valid(trap_node):
		if trap_node.has_meta("pulse_tween"):
			(trap_node.get_meta("pulse_tween") as Tween).kill()
		var dtw := get_tree().create_tween()
		dtw.tween_property(trap_node, "modulate:a", 0.0, 0.35)
		dtw.tween_callback(trap_node.queue_free)
	spike_traps.erase(hex_key)

func damage_spike_trap(hex_key: Vector2i) -> void:
	# Called when a player bullet hits a spike trap
	if not spike_traps.has(hex_key): return
	var trap = spike_traps[hex_key]
	if not (trap["alive"] as bool): return
	trap["hp"] = (trap["hp"] as int) - 1
	if (trap["hp"] as int) <= 0:
		_destroy_spike_trap(hex_key)
	else:
		# Bullet hit triggers the trap
		trap["recharge"] = 0.0
		_fire_spike_trap(hex_key, trap["node"] as Node2D)

func tick_spike_traps(delta: float) -> void:
	# Called from enemy_spawner _physics_process
	for key in spike_traps.keys():
		var trap = spike_traps[key]
		if not (trap["alive"] as bool): continue
		if (trap["recharge"] as float) > 0.0:
			trap["recharge"] = maxf((trap["recharge"] as float) - delta, 0.0)


# ─── ET Crescent Arena Carver ─────────────────────────────────────────────────
func carve_et_arena(center_hex: Vector2i) -> void:
	# Direction from ET toward map center (castle) — front gap faces this way
	var to_castle: Vector2 = -Vector2(float(center_hex.x), float(center_hex.y)).normalized()
	var to_castle_angle: float = atan2(to_castle.y, to_castle.x)

	# Carve two crescent arcs on the flanks (perpendicular to castle direction)
	for flank in [-1, 1]:  # left and right flanks
		for arc_step in range(0, 14):
			# Arc spans ~150° centered on the flank direction
			var arc_angle: float = to_castle_angle + flank * PI / 2.0 + 				(float(arc_step) - 6.5) * deg_to_rad(12.0)
			# Vary radius between 4 and 7 hexes for organic crescent shape
			var noise_r: float = 5.0 + sin(float(arc_step) * 0.7) * 1.5 + randf() * 1.0
			var qf: float = float(center_hex.x) + cos(arc_angle) * noise_r
			var rf: float = float(center_hex.y) + sin(arc_angle) * noise_r
			var target := Vector2i(int(round(qf)), int(round(rf)))
			# Bounds check
			if abs(target.x) >= Q_RANGE - 2 or abs(target.y) >= R_RANGE - 2: continue
			var hex_dist: int = maxi(abs(center_hex.x - target.x),
					maxi(abs(center_hex.y - target.y),
					abs((center_hex.x + center_hex.y) - (target.x + target.y))))
			# Don't carve too close to ET center or too far
			if hex_dist < 3 or hex_dist > 9: continue
			# Set to pit
			hex_types[target] = HexType.PIT
	# Rebake to show new pits
	call_deferred("_rebake_overworld")

func _rebake_overworld() -> void:
	# Lightweight rebake — just update the static draw overlay
	queue_redraw()


# ─── Biome Generation ─────────────────────────────────────────────
func _generate_biomes() -> void:
	hex_biomes_ow.clear()
	hex_biomes_fut.clear()
	hex_blend_ow.clear()
	hex_blend_fut.clear()
	_fill_base_ground()
	var seeds := _place_biome_seeds()
	_expand_biome_clusters(seeds)
	_derive_future_biomes()
	_calculate_blend_zones()

func _fill_base_ground() -> void:
	# Every passable hex starts as GRASSLAND (OW) — non-passable hexes get no biome
	for q in range(-Q_RANGE, Q_RANGE + 1):
		for r in range(-R_RANGE, R_RANGE + 1):
			if hex_types.get(Vector2i(q, r), HexType.NORMAL) == HexType.NORMAL:
				hex_biomes_ow[Vector2i(q, r)] = OverworldBiome.GRASSLAND

func _place_biome_seeds() -> Array:
	var seeds: Array = []
	var non_base := [
		OverworldBiome.MARSH, OverworldBiome.FOREST, OverworldBiome.ASH_PLAIN,
		OverworldBiome.SAND,  OverworldBiome.MAGMA,  OverworldBiome.ICE, OverworldBiome.WATER
	]
	for biome in non_base:
		var cmin: int = 2; var cmax: int = 3
		match biome:
			OverworldBiome.MARSH, OverworldBiome.FOREST, OverworldBiome.ASH_PLAIN, OverworldBiome.SAND:
				cmin = 3; cmax = 4
			OverworldBiome.WATER:
				cmin = 1; cmax = 2
		var count: int = cmin + randi() % (cmax - cmin + 1)
		var placed: int = 0; var attempts: int = 0
		while placed < count and attempts < 400:
			attempts += 1
			var q: int = randi_range(-Q_RANGE + 12, Q_RANGE - 12)
			var r: int = randi_range(-R_RANGE + 12, R_RANGE - 12)
			var key := Vector2i(q, r)
			if maxi(abs(q), maxi(abs(r), abs(q + r))) < SAFE_RADIUS + 10:
				continue
			if hex_types.get(key, HexType.NORMAL) != HexType.NORMAL:
				continue
			var too_close := false
			for sd in seeds:
				var min_d: int = 20 if (sd as Dictionary)["biome"] == biome else 12
				if _hex_dist_vi((sd as Dictionary)["pos"], key) < min_d:
					too_close = true; break
			if too_close: continue
			seeds.append({"pos": key, "biome": biome})
			placed += 1
	return seeds

func _expand_biome_clusters(seeds: Array) -> void:
	seeds.shuffle()
	for sd in seeds:
		var seed_pos: Vector2i = (sd as Dictionary)["pos"]
		var biome: int = (sd as Dictionary)["biome"]
		var max_r: int = _biome_max_radius(biome)
		var max_s: int = _biome_max_size(biome)
		hex_biomes_ow[seed_pos] = biome
		var frontier: Array = [seed_pos]
		var claimed: int = 1
		while frontier.size() > 0 and claimed < max_s:
			# Pick random from frontier — produces organic blob shapes
			var idx: int = randi() % frontier.size()
			var current: Vector2i = frontier[idx]
			frontier.remove_at(idx)
			for nb in _hex_neighbors_vi(current):
				if not _in_map_bounds(nb): continue
				if hex_types.get(nb, HexType.NORMAL) != HexType.NORMAL: continue
				if hex_biomes_ow.get(nb, OverworldBiome.GRASSLAND) != OverworldBiome.GRASSLAND: continue
				var dist: int = _hex_dist_vi(nb, seed_pos)
				if dist > max_r: continue
				# Claim probability falls off with distance, jittered for organic edges
				var prob: float = 0.72 * (1.0 - float(dist) / float(max_r)) * randf_range(0.55, 1.0)
				if prob > 0.38:
					hex_biomes_ow[nb] = biome
					frontier.append(nb)
					claimed += 1
					if claimed >= max_s: break

func _derive_future_biomes() -> void:
	# Each organic biome has a direct digital counterpart
	for key in hex_biomes_ow.keys():
		hex_biomes_fut[key] = _ow_to_fut(hex_biomes_ow[key])

func _calculate_blend_zones() -> void:
	# Hard-border biomes never receive or produce blend tints
	# MAGMA uses a transition cascade: r=1→ASH_PLAIN, r=2→SAND
	# WATER has hard borders everywhere — no bleed in or out
	# ASH_PLAIN (rocky) blends as patchy grass/sand mix at 50% chance per hex
	for key in hex_biomes_ow.keys():
		var my_ow: int = hex_biomes_ow[key]
		# Water is always a hard border — never blends
		if my_ow == OverworldBiome.WATER:
			continue
		var my_str: int = _biome_strength(my_ow)
		# Radius-1 check
		for nb in _hex_neighbors_vi(key as Vector2i):
			var nb_ow: int = hex_biomes_ow.get(nb, OverworldBiome.GRASSLAND)
			if nb_ow == my_ow: continue
			# Water neighbor → hard cut, no blend
			if nb_ow == OverworldBiome.WATER: continue
			if _biome_strength(nb_ow) > my_str:
				var tint: int = _biome_blend_tint(nb_ow, 1)
				# ASH_PLAIN (rocky) applies 50% chance per hex for patchy look
				var inten: float = 0.9 if nb_ow != OverworldBiome.ASH_PLAIN else (0.85 if randf() > 0.5 else 0.0)
				if inten > 0.0:
					hex_blend_ow[key]  = {"neighbor": tint,            "intensity": inten}
					hex_blend_fut[key] = {"neighbor": _ow_to_fut(tint), "intensity": inten}
				break
		if hex_blend_ow.has(key): continue
		# Radius-2 check
		for dq in range(-2, 3):
			for dr in range(-2, 3):
				var ds: int = -dq - dr
				if (abs(dq) + abs(dr) + abs(ds)) != 4: continue
				var nb2: Vector2i = (key as Vector2i) + Vector2i(dq, dr)
				if not hex_biomes_ow.has(nb2): continue
				var nb_ow2: int = hex_biomes_ow[nb2]
				if nb_ow2 == my_ow: continue
				if nb_ow2 == OverworldBiome.WATER: continue
				if _biome_strength(nb_ow2) > my_str:
					var tint2: int = _biome_blend_tint(nb_ow2, 2)
					var inten2: float = 0.45 if nb_ow2 != OverworldBiome.ASH_PLAIN else (0.4 if randf() > 0.4 else 0.0)
					if inten2 > 0.0:
						hex_blend_ow[key]  = {"neighbor": tint2,            "intensity": inten2}
						hex_blend_fut[key] = {"neighbor": _ow_to_fut(tint2), "intensity": inten2}
					break
			if hex_blend_ow.has(key): break

func _biome_blend_tint(neighbor: int, dist: int) -> int:
	# Returns the effective OW biome used as the blend tint color
	# MAGMA uses a transition cascade instead of raw magma color
	match neighbor:
		OverworldBiome.MAGMA:
			return OverworldBiome.ASH_PLAIN if dist == 1 else OverworldBiome.SAND
		OverworldBiome.ICE:
			return OverworldBiome.ICE   # ICE blends directly but faint
		OverworldBiome.WATER:
			return OverworldBiome.WATER # caller already skips water
		_: return neighbor

# ─── Biome helpers ───────────────────────────────────────────────────────
func _hex_neighbors_vi(pos: Vector2i) -> Array:
	var dirs := [Vector2i(1,0), Vector2i(0,1), Vector2i(-1,1),
				 Vector2i(-1,0), Vector2i(0,-1), Vector2i(1,-1)]
	var out: Array = []
	for d in dirs: out.append(pos + d)
	return out

func _hex_dist_vi(a: Vector2i, b: Vector2i) -> int:
	var dq: int = a.x - b.x; var dr: int = a.y - b.y
	return (abs(dq) + abs(dr) + abs(dq + dr)) / 2

func _in_map_bounds(pos: Vector2i) -> bool:
	return (abs(pos.x) <= Q_RANGE - 2 and abs(pos.y) <= R_RANGE - 2
			and abs(pos.x + pos.y) <= Q_RANGE + R_RANGE - 2)

func _ow_to_fut(biome: int) -> int:
	match biome:
		OverworldBiome.GRASSLAND: return FutureBiome.GRID_BASE
		OverworldBiome.MARSH:     return FutureBiome.CORRUPTED
		OverworldBiome.FOREST:    return FutureBiome.CIRCUIT
		OverworldBiome.ASH_PLAIN: return FutureBiome.STATIC_FIELD
		OverworldBiome.SAND:      return FutureBiome.DEAD_SAND
		OverworldBiome.MAGMA:     return FutureBiome.VOID_RIFT
		OverworldBiome.ICE:       return FutureBiome.FROZEN_DATA
		OverworldBiome.WATER:     return FutureBiome.DARK_POOL
		_: return FutureBiome.GRID_BASE

func _biome_strength(biome: int) -> int:
	# Stronger biomes bleed INTO weaker neighbours.
	# WATER = 0 so it never bleeds into others (hard border logic in blend calc).
	# MAGMA = highest so cascade tints always point toward magma.
	match biome:
		OverworldBiome.WATER:     return 0   # hard border — excluded in blend calc
		OverworldBiome.GRASSLAND: return 1
		OverworldBiome.FOREST:    return 2
		OverworldBiome.MARSH:     return 3
		OverworldBiome.SAND:      return 4
		OverworldBiome.ASH_PLAIN: return 5   # rocky — patchy blend
		OverworldBiome.ICE:       return 6
		OverworldBiome.MAGMA:     return 7
		_: return 1

func _biome_max_radius(biome: int) -> int:
	match biome:
		OverworldBiome.MARSH:     return 9
		OverworldBiome.FOREST:    return 10
		OverworldBiome.ASH_PLAIN: return 8
		OverworldBiome.SAND:      return 9
		OverworldBiome.MAGMA:     return 7
		OverworldBiome.ICE:       return 7
		OverworldBiome.WATER:     return 5
		_: return 6

func _biome_max_size(biome: int) -> int:
	match biome:
		OverworldBiome.MARSH:     return 42
		OverworldBiome.FOREST:    return 48
		OverworldBiome.ASH_PLAIN: return 32
		OverworldBiome.SAND:      return 40
		OverworldBiome.MAGMA:     return 28
		OverworldBiome.ICE:       return 26
		OverworldBiome.WATER:     return 20
		_: return 20

# ─── Reactive Tile API ───────────────────────────────────────────────────────
func set_hex_state(q: int, r: int, state: int) -> void:
	# Advance a tile's damage state (0=pristine … 4=critical)
	var key := Vector2i(q, r)
	if hex_types.get(key, HexType.NORMAL) != HexType.NORMAL:
		return   # only NORMAL tiles have reactive states
	hex_states[key] = clampi(state, 0, 4)
	if _overlay_drawer != null:
		(_overlay_drawer as Node2D).queue_redraw()

func get_hex_state(q: int, r: int) -> int:
	return hex_states.get(Vector2i(q, r), 0)

func damage_hex_at(world_pos: Vector2, amount: int = 1) -> void:
	# Call this on projectile impact / enemy traffic
	var h: Vector2i = pixel_to_hex(world_pos)
	var cur: int = get_hex_state(h.x, h.y)
	set_hex_state(h.x, h.y, cur + amount)

# ─── Living World ─────────────────────────────────────────────────────────────
var _lw_future_mode: bool = false

func _process(_delta: float) -> void:
	if _lw_future_mode: return
	var player = get_parent().get_node_or_null("Player")
	if player == null: return
	var pp: Vector2 = (player as Node2D).global_position
	var sr: float = HEX_SIZE * 4.0   # scatter range ~140px
	for node in get_tree().get_nodes_in_group("living_world"):
		if not is_instance_valid(node): continue
		if not node.get_meta("lw_is_fauna", false): continue
		var scattered: bool = node.get_meta("lw_scattered", false)
		if not scattered:
			if (node as Node2D).global_position.distance_to(pp) < sr:
				_lw_scatter(node as Node2D, pp)
		else:
			var rt: float = node.get_meta("lw_return_timer", 0.0) - _delta
			node.set_meta("lw_return_timer", rt)
			if rt <= 0.0:
				_lw_return(node as Node2D)

func _lw_scatter(node: Node2D, player_pos: Vector2) -> void:
	node.set_meta("lw_scattered", true)
	var away: Vector2 = (node.global_position - player_pos).normalized()
	if away == Vector2.ZERO:
		away = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)).normalized()
	var lw_type: String = node.get_meta("lw_type", "")
	var dist: float = HEX_SIZE * randf_range(2.2, 3.2)
	var dur:  float = 0.55
	var ret:  float = 8.0
	if lw_type == "crow":
		dist = HEX_SIZE * randf_range(5.5, 8.0)
		dur  = 0.22
		ret  = 15.0
	elif lw_type == "frog":
		dist = HEX_SIZE * randf_range(1.8, 2.5)
		dur  = 0.35
		ret  = 6.0
	var target: Vector2 = node.global_position + away * dist
	var tw := get_tree().create_tween()
	tw.tween_property(node, "global_position", target, dur)
	node.set_meta("lw_return_timer", ret)

func _lw_return(node: Node2D) -> void:
	var base_pos: Vector2 = node.get_meta("lw_base_pos", node.global_position)
	var tw := get_tree().create_tween()
	tw.tween_property(node, "global_position", base_pos, 2.2)
	tw.tween_callback(func(): node.set_meta("lw_scattered", false))

func flip_living_world(is_future: bool) -> void:
	# Instant swap — used internally; for player-facing trigger use cascade_world_flip()
	_lw_future_mode = is_future
	is_future_mode  = is_future
	if _biome_spr_ow != null:
		(_biome_spr_ow  as Sprite2D).visible = not is_future
		(_biome_spr_fut as Sprite2D).visible = is_future
		(_grid_spr_ow   as Sprite2D).visible = not is_future
		(_grid_spr_fut  as Sprite2D).visible = is_future
	for node in get_tree().get_nodes_in_group("living_world"):
		if not is_instance_valid(node): continue
		var m = (node as Node).get_node_or_null("Medieval")
		var f = (node as Node).get_node_or_null("Future")
		if m != null: (m as Node2D).visible = not is_future
		if f != null: (f as Node2D).visible = is_future

# ─── Cascading world transformation ──────────────────────────────────────────
# Sweeps a dimensional rift wave outward from MAP_CENTER over ~1.4s.
# Sprite cross-fade hidden behind the ring. Living world staggers by distance.
func cascade_world_flip(going_future: bool) -> void:
	if is_future_mode == going_future: return   # already in target state
	_lw_future_mode = going_future
	is_future_mode  = going_future

	const DURATION   := 1.4     # seconds for wave to cross full map
	const MAX_RADIUS := 4200.0  # large enough to cover map diagonal
	const RING_WIDTH := 240.0   # thickness of the sweeping band

	var ring_col_a: Color = Color(0.0, 0.85, 1.0, 0.85) if going_future else Color(0.85, 0.55, 0.1, 0.80)
	var ring_col_b: Color = Color(0.30, 0.0, 0.65, 0.60) if going_future else Color(0.9, 0.8, 0.3, 0.50)

	# ── Sweeping ring node ────────────────────────────────────────────────────
	var ring_node := Node2D.new()
	ring_node.global_position = MAP_CENTER
	ring_node.z_index = 10;  ring_node.z_as_relative = false
	add_child(ring_node)

	# Build annulus polygon — outer ring at r, inner at r-RING_WIDTH
	var SEGS := 36
	var outer_pts := PackedVector2Array()
	var inner_pts := PackedVector2Array()
	for i in SEGS:
		var a: float = TAU * float(i) / SEGS
		outer_pts.append(Vector2(cos(a), sin(a)) * 1.0)  # scaled by tween
		inner_pts.append(Vector2(cos(a), sin(a)) * max(0.01, (1.0 - RING_WIDTH)))

	# Two overlapping annulus polys for depth
	var rp_a := Polygon2D.new();  rp_a.color = ring_col_a
	var rp_b := Polygon2D.new();  rp_b.color = ring_col_b
	var annulus_pts := PackedVector2Array()
	for i in SEGS:
		annulus_pts.append(Vector2(cos(TAU*float(i)/SEGS), sin(TAU*float(i)/SEGS)))
	# Use polygon for the leading disc (inner will be masked by scale approach below)
	rp_a.polygon = annulus_pts;  rp_b.polygon = annulus_pts
	rp_a.scale   = Vector2(0.1, 0.1);  rp_b.scale = Vector2(0.1, 0.1)
	ring_node.add_child(rp_b);  ring_node.add_child(rp_a)

	# Tween the ring outward
	var rtw := get_tree().create_tween()
	rtw.set_parallel(true)
	rtw.tween_property(rp_a, "scale", Vector2(MAX_RADIUS, MAX_RADIUS), DURATION)
	rtw.tween_property(rp_a, "color", Color(ring_col_a.r, ring_col_a.g, ring_col_a.b, 0.0), DURATION)
	rtw.tween_property(rp_b, "scale", Vector2(MAX_RADIUS * 0.88, MAX_RADIUS * 0.88), DURATION)
	rtw.tween_property(rp_b, "color", Color(ring_col_b.r, ring_col_b.g, ring_col_b.b, 0.0), DURATION)
	rtw.set_parallel(false)
	rtw.tween_callback(ring_node.queue_free)

	# ── Sprite cross-fade — OW ↔ Future behind the ring ──────────────────────
	if _biome_spr_ow != null:
		var fade_in  = (_biome_spr_fut as Sprite2D) if going_future else (_biome_spr_ow as Sprite2D)
		var fade_out = (_biome_spr_ow  as Sprite2D) if going_future else (_biome_spr_fut as Sprite2D)
		var gfade_in  = (_grid_spr_fut as Sprite2D) if going_future else (_grid_spr_ow as Sprite2D)
		var gfade_out = (_grid_spr_ow  as Sprite2D) if going_future else (_grid_spr_fut as Sprite2D)
		fade_in.modulate  = Color(1, 1, 1, 0);  fade_in.visible  = true
		fade_out.modulate = Color(1, 1, 1, 1);  fade_out.visible = true
		gfade_in.modulate  = Color(1, 1, 1, 0);  gfade_in.visible  = true
		gfade_out.modulate = Color(1, 1, 1, 1);  gfade_out.visible = true
		var spr_tween := get_tree().create_tween()
		spr_tween.set_parallel(true)
		spr_tween.tween_property(fade_out,  "modulate:a", 0.0, DURATION * 0.7).set_delay(DURATION * 0.15)
		spr_tween.tween_property(fade_in,   "modulate:a", 1.0, DURATION * 0.7).set_delay(DURATION * 0.15)
		spr_tween.tween_property(gfade_out, "modulate:a", 0.0, DURATION * 0.7).set_delay(DURATION * 0.15)
		spr_tween.tween_property(gfade_in,  "modulate:a", 1.0, DURATION * 0.7).set_delay(DURATION * 0.15)

	# ── Staggered hex flash rings — 8 distance bands ──────────────────────────
	# Collect hexes, sort by distance from origin hex (0,0)
	var bands: Array = []
	for _i in 8: bands.append([])
	var max_dist_f: float = float(Q_RANGE + R_RANGE)
	for key in hex_biomes_ow.keys():
		var qi: int = (key as Vector2i).x;  var ri: int = (key as Vector2i).y
		var d: float = float(maxi(abs(qi), maxi(abs(ri), abs(qi + ri))))
		var band_idx: int = clampi(int(d / max_dist_f * 8.0), 0, 7)
		if bands[band_idx].size() < 60:   # cap per band — sparse flash looks better
			bands[band_idx].append(key)

	var flash_col: Color = Color(0.0, 0.9, 1.0, 0.9) if going_future else Color(1.0, 0.75, 0.2, 0.9)

	for bi in 8:
		var band_delay: float = float(bi) / 8.0 * DURATION
		var band_keys: Array = bands[bi]
		get_tree().create_timer(band_delay).timeout.connect(func():
			for hkey in band_keys:
				var hq: int = (hkey as Vector2i).x;  var hr: int = (hkey as Vector2i).y
				var hpos: Vector2 = hex_to_pixel(hq, hr)
				var fnode := Node2D.new()
				fnode.global_position = hpos
				fnode.z_index = 9;  fnode.z_as_relative = false
				var fpts := PackedVector2Array()
				for fi in 6:
					var fa: float = deg_to_rad(60.0 * float(fi) - 30.0)
					fpts.append(Vector2(cos(fa), sin(fa)) * 33.0)
				var fpoly := Polygon2D.new()
				fpoly.polygon = fpts;  fpoly.color = flash_col
				fnode.add_child(fpoly)
				add_child(fnode)
				var ftw := get_tree().create_tween()
				ftw.set_parallel(true)
				ftw.tween_property(fnode,  "scale", Vector2(1.3, 1.3), 0.25)
				ftw.tween_property(fpoly, "color", Color(flash_col.r, flash_col.g, flash_col.b, 0.0), 0.25)
				ftw.set_parallel(false)
				ftw.tween_callback(fnode.queue_free)
		)

	# ── Living world — stagger flip by distance ──────────────────────────────
	for lw_node in get_tree().get_nodes_in_group("living_world"):
		if not is_instance_valid(lw_node): continue
		var lw_pos: Vector2 = (lw_node as Node2D).global_position
		var lw_dist: float  = lw_pos.distance_to(MAP_CENTER)
		var lw_delay: float = (lw_dist / MAX_RADIUS) * DURATION
		var captured := lw_node
		get_tree().create_timer(lw_delay).timeout.connect(func():
			if not is_instance_valid(captured): return
			var m = (captured as Node).get_node_or_null("Medieval")
			var f = (captured as Node).get_node_or_null("Future")
			if m != null: (m as Node2D).visible = not going_future
			if f != null: (f as Node2D).visible = going_future
		)

# ─── Placement helpers ────────────────────────────────────────────────────────
func _spawn_living_world() -> void:
	var candidates: Array = []
	for q in range(-Q_RANGE + 5, Q_RANGE - 5):
		for r in range(-R_RANGE + 5, R_RANGE - 5):
			if hex_types.get(Vector2i(q, r), HexType.NORMAL) != HexType.NORMAL:
				continue
			if maxi(abs(q), maxi(abs(r), abs(q + r))) < 6:
				continue
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
		node.set_meta("lw_is_fauna", is_fauna);  node.set_meta("lw_type", lw_type)
		node.set_meta("lw_base_pos", wp);        node.set_meta("lw_scattered", false)
		node.set_meta("lw_return_timer", 0.0);   node.add_to_group("living_world")
		add_child(node)
		placed += 1

func _lw_make(wp: Vector2) -> Array:
	# Returns [container, medieval Node2D, future Node2D]
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

# ─── FL-A: Bog Mushrooms ──────────────────────────────────────────────────────
func _make_bog_mushrooms(wp: Vector2) -> Node2D:
	# TOP-DOWN: 3 filled circle cap silhouettes from above
	var res := _lw_make(wp);  var co: Node2D = res[0]; var me: Node2D = res[1]; var fu: Node2D = res[2]
	var CAP_DARK  := Color(0.30, 0.18, 0.07)
	var CAP_MID   := Color(0.48, 0.30, 0.13)
	var CAP_LIGHT := Color(0.55, 0.36, 0.16)
	var SPORE     := Color(0.06, 0.03, 0.01, 0.8)
	var GCYAN     := Color(0.0, 0.8, 0.6, 0.9)
	var GPHOSPHOR := Color(0.0, 0.95, 0.7, 0.9)
	# cap defs: [cx, cy, outer_r, inner_r, spore_count]
	var caps := [
		[ 0.0,  0.0, 11.0, 7.0, 8],   # large center cap
		[-9.5, -5.0,  7.0, 4.5, 6],   # small offset cap
		[ 8.5,  6.5,  6.0, 3.5, 5],   # small offset cap
	]
	for cap in caps:
		var cx: float = cap[0]; var cy: float = cap[1]
		var ro: float = cap[2]; var ri: float = cap[3]; var ns: int = cap[4]
		_lw_poly(me, _lw_circle_pts(cx, cy, ro, ro, 12), CAP_DARK)
		_lw_poly(me, _lw_circle_pts(cx, cy, ri, ri, 12), CAP_MID)
		_lw_poly(me, _lw_circle_pts(cx, cy, ri * 0.45, ri * 0.45, 8), CAP_LIGHT)
		# Spore frill dots around outer rim
		for sj in ns:
			var sa: float = TAU * float(sj) / float(ns)
			var sdx: float = cx + cos(sa) * (ro * 0.88)
			var sdy: float = cy + sin(sa) * (ro * 0.88)
			_lw_poly(me, _lw_circle_pts(sdx, sdy, 1.0, 1.0, 5), SPORE)
	# Idle scale pulse
	var idle := get_tree().create_tween().set_loops()
	idle.tween_property(me, "scale", Vector2(1.03, 1.03), 2.0)
	idle.tween_property(me, "scale", Vector2(1.0, 1.0), 2.0)
	# DF-A: Ghost Mushroom — cyan ring outlines, phosphor center dot, no fill, no spore dots
	for cap in caps:
		var cx: float = cap[0]; var cy: float = cap[1]
		var ro: float = cap[2]; var ri: float = cap[3]
		_lw_line(fu, _lw_circle_pts(cx, cy, ro, ro, 12), GCYAN, 0.9, true)
		_lw_line(fu, _lw_circle_pts(cx, cy, ri, ri, 12), Color(0.0, 0.8, 0.6, 0.5), 0.6, true)
		_lw_poly(fu, _lw_circle_pts(cx, cy, 1.5, 1.5, 6), GPHOSPHOR)
	return co

# ─── FL-B: Hex Reeds ──────────────────────────────────────────────────────────
func _make_hex_reeds(wp: Vector2) -> Node2D:
	# TOP-DOWN: cluster of 6 reed tips seen from directly above — small ovals with shadow base
	var res := _lw_make(wp);  var co: Node2D = res[0]; var me: Node2D = res[1]; var fu: Node2D = res[2]
	var TIP    := Color(0.27, 0.34, 0.17)
	var TIP_LT := Color(0.35, 0.44, 0.22)
	var SHADOW := Color(0.08, 0.10, 0.05, 0.5)
	var GNODE  := Color(0.0, 0.88, 0.5, 0.9)
	var GRING  := Color(0.0, 0.65, 0.35, 0.7)
	# reed tip defs: [cx, cy, rx, ry] — irregular loose cluster
	var tips := [
		[-8.0, -7.0, 2.8, 3.8],
		[-2.0,-12.0, 3.2, 4.5],
		[ 6.0, -9.0, 2.5, 3.5],
		[-6.5,  1.0, 2.2, 3.2],
		[ 2.0,  3.0, 3.0, 4.0],
		[ 9.0,  0.0, 2.0, 3.0],
	]
	for td in tips:
		var cx: float = td[0]; var cy: float = td[1]
		var rx: float = td[2]; var ry: float = td[3]
		# Shadow just below tip
		_lw_poly(me, _lw_circle_pts(cx + 0.8, cy + 1.0, rx * 0.7, ry * 0.5, 8), SHADOW)
		# Tip oval
		_lw_poly(me, _lw_circle_pts(cx, cy, rx, ry, 10), TIP)
		_lw_poly(me, _lw_circle_pts(cx, cy, rx * 0.45, ry * 0.45, 6), TIP_LT)
		# DF-B: ring outline + bright data node
		_lw_line(fu, _lw_circle_pts(cx, cy, rx, ry, 10), GRING, 0.8, true)
		_lw_poly(fu, _lw_circle_pts(cx, cy, 1.4, 1.4, 6), GNODE)
	return co

# ─── FL-D: Twisted Shrub ──────────────────────────────────────────────────────
func _make_twisted_shrub(wp: Vector2) -> Node2D:
	# TOP-DOWN: canopy seen from above — dense dark center with lobe clusters radiating out
	var res := _lw_make(wp);  var co: Node2D = res[0]; var me: Node2D = res[1]; var fu: Node2D = res[2]
	var CANOPY_DARK := Color(0.10, 0.14, 0.06)
	var CANOPY_MID  := Color(0.16, 0.23, 0.10)
	var CANOPY_LT   := Color(0.22, 0.32, 0.14)
	var BARK_CENTER := Color(0.14, 0.10, 0.05)
	var CTRACE      := Color(0.0, 0.60, 0.32, 0.65)
	var CPAD        := Color(0.0, 0.78, 0.42, 0.85)
	# 7 canopy lobes radiating from center: [cx, cy, rx, ry]
	var lobes := [
		[ 0.0, -13.0, 7.5, 6.5],
		[11.5,  -7.5, 6.5, 6.0],
		[13.5,   4.5, 6.0, 5.5],
		[ 5.5,  13.0, 6.5, 5.5],
		[ -6.5, 12.5, 6.0, 5.5],
		[-13.5,  4.0, 6.0, 5.5],
		[-11.5,  -8.0, 6.5, 6.0],
	]
	for lb in lobes:
		_lw_poly(me, _lw_circle_pts(lb[0], lb[1], lb[2], lb[3], 10), CANOPY_DARK)
	# Overlap lighter fill
	for lb in lobes:
		_lw_poly(me, _lw_circle_pts(lb[0], lb[1], lb[2]*0.65, lb[3]*0.65, 9), CANOPY_MID)
	# Dense center blob (bark visible from above)
	_lw_poly(me, _lw_circle_pts(0.0, 0.0, 5.5, 5.5, 9), BARK_CENTER)
	_lw_poly(me, _lw_circle_pts(0.0, 0.0, 2.5, 2.5, 7), Color(0.08, 0.06, 0.03))
	# Highlight lobe tips
	for lb in lobes:
		_lw_poly(me, _lw_circle_pts(lb[0]*0.85, lb[1]*0.85, 2.2, 2.0, 6), CANOPY_LT)
	# DF-D: Circuit Shrub — lobe positions become hex-pad rings, radial trace lines to center node
	for lb in lobes:
		var lx: float = lb[0]; var ly: float = lb[1]
		var pr: float = 3.5
		_lw_line(fu, _lw_circle_pts(lx, ly, pr, pr, 6), CPAD, 0.85, true)
		_lw_poly(fu, _lw_circle_pts(lx, ly, 1.4, 1.4, 6), CPAD)
		_lw_line(fu, PackedVector2Array([Vector2(lx * 0.88, ly * 0.88), Vector2(0.0, 0.0)]), CTRACE, 0.75)
	# Center node
	_lw_poly(fu, _lw_circle_pts(0.0, 0.0, 2.8, 2.8, 7), Color(0.0, 0.05, 0.03))
	_lw_poly(fu, _lw_circle_pts(0.0, 0.0, 1.6, 1.6, 6), CPAD)
	return co

# ─── FA-A: Hex Beetle ─────────────────────────────────────────────────────────
func _make_hex_beetle(wp: Vector2) -> Node2D:
	var res := _lw_make(wp);  var co: Node2D = res[0]; var me: Node2D = res[1]; var fu: Node2D = res[2]
	var SHELL := Color(0.11, 0.18, 0.09);  var DARK  := Color(0.06, 0.09, 0.04)
	var EDGE  := Color(0.18, 0.28, 0.14)
	# Hex carapace
	_lw_poly(me, _lw_circle_pts(0.0, 0.0, 8.0, 8.0, 6), SHELL)
	# Head cap
	_lw_poly(me, _lw_circle_pts(0.0, -7.5, 4.0, 2.8, 8), DARK)
	# 6 legs
	for lj in 3:
		var ly: float = -3.0 + float(lj) * 3.5
		for sx in [-1.0, 1.0]:
			_lw_line(me, PackedVector2Array([Vector2(sx*8.0, ly), Vector2(sx*16.0, ly - 1.5), Vector2(sx*18.0, ly+3.0)]), EDGE, 0.9)
	# 2 antennae
	_lw_line(me, PackedVector2Array([Vector2(-2.5,-8.0), Vector2(-7.0,-16.0)]), EDGE, 0.8)
	_lw_line(me, PackedVector2Array([Vector2( 2.5,-8.0), Vector2( 7.0,-16.0)]), EDGE, 0.8)
	# Shell seam line
	_lw_line(me, PackedVector2Array([Vector2(0.0,-8.0), Vector2(0.0, 7.0)]), Color(0.15,0.24,0.12,0.4), 0.7)
	# DF-E: Scan Beetle — wireframe hex, trace legs, scan ring
	var GWIRE := Color(0.0, 0.8, 0.45, 0.8);  var GFAINT := Color(0.0, 0.7, 0.35, 0.5)
	_lw_line(fu, _lw_circle_pts(0.0, 0.0, 8.0, 8.0, 6), GWIRE, 1.0, true)
	_lw_line(fu, _lw_circle_pts(0.0, 0.0, 5.0, 5.0, 6), GFAINT, 0.6, true)
	# Scan ring above
	_lw_line(fu, _lw_circle_pts(0.0, -14.0, 9.0, 2.0, 16), Color(0.0,0.8,0.45,0.4), 0.7, true)
	for lj in 3:
		var ly: float = -3.0 + float(lj) * 3.5
		for sx in [-1.0, 1.0]:
			_lw_line(fu, PackedVector2Array([Vector2(sx*8.0,ly), Vector2(sx*14.0,ly-1.0)]), GFAINT, 0.7)
	_lw_line(fu, PackedVector2Array([Vector2(-2.5,-8.0), Vector2(-6.0,-14.0)]), GFAINT, 0.7)
	_lw_line(fu, PackedVector2Array([Vector2( 2.5,-8.0), Vector2( 6.0,-14.0)]), GFAINT, 0.7)
	# Eye scan dots
	_lw_poly(fu, _lw_circle_pts(-2.5, -7.5, 1.2, 1.2, 6), Color(0.0,0.9,0.55,0.85))
	_lw_poly(fu, _lw_circle_pts( 2.5, -7.5, 1.2, 1.2, 6), Color(0.0,0.9,0.55,0.85))
	return co

# ─── FA-B: Field Mouse ────────────────────────────────────────────────────────
func _make_field_mouse(wp: Vector2) -> Node2D:
	var res := _lw_make(wp);  var co: Node2D = res[0]; var me: Node2D = res[1]; var fu: Node2D = res[2]
	var FUR  := Color(0.29, 0.22, 0.15);  var DARK := Color(0.15, 0.11, 0.07)
	var EAR  := Color(0.24, 0.17, 0.11);  var PINK := Color(0.55, 0.28, 0.22, 0.5)
	# Body
	_lw_poly(me, _lw_circle_pts(0.0, 0.0, 9.0, 6.5, 12), FUR)
	# Head
	_lw_poly(me, _lw_circle_pts(8.5, -2.0, 5.5, 4.5, 10), FUR)
	# Snout
	_lw_poly(me, _lw_circle_pts(13.0,-1.5, 2.5, 1.8, 8), DARK)
	# Ears
	_lw_poly(me, _lw_circle_pts(7.0, -7.5, 2.8, 4.0, 8), EAR)
	_lw_poly(me, _lw_circle_pts(7.0, -7.5, 1.5, 2.2, 6), PINK)
	# Tail
	var tail_pts := PackedVector2Array([Vector2(-9.0,2.0),Vector2(-14.0,-1.0),Vector2(-16.0,4.0),Vector2(-18.0,0.0)])
	_lw_line(me, tail_pts, DARK, 1.2)
	# Eye
	_lw_poly(me, _lw_circle_pts(10.5,-3.5, 1.2, 1.2, 6), Color(0.06,0.04,0.02))
	# DF-F: Trace Mouse — outline only, scan eye dots, trailing data tail
	var GOUT := Color(0.0, 0.8, 0.45, 0.75);  var GDIM := Color(0.0, 0.65, 0.35, 0.5)
	_lw_line(fu, _lw_circle_pts(0.0, 0.0, 9.0, 6.5, 12), GOUT, 0.9, true)
	_lw_line(fu, _lw_circle_pts(8.5,-2.0, 5.5, 4.5, 10), GDIM, 0.8, true)
	_lw_line(fu, _lw_circle_pts(7.0,-7.5, 2.8, 4.0,  8), GDIM, 0.7, true)
	# Scan eye dot
	_lw_poly(fu, _lw_circle_pts(10.5,-3.5, 2.0, 2.0, 6), Color(0.0,0.9,0.55,0.85))
	_lw_poly(fu, _lw_circle_pts(10.5,-3.5, 0.8, 0.8, 5), Color(0.0,1.0,0.65))
	# Data tail — dashed via short segments
	for si in 4:
		var st: float = float(si) / 4.0;  var en: float = float(si + 1) / 4.0 - 0.05
		var ts: Vector2 = tail_pts[0].lerp(tail_pts[3], st)
		var te: Vector2 = tail_pts[0].lerp(tail_pts[3], en)
		_lw_line(fu, PackedVector2Array([ts, te]), GDIM, 0.7)
	return co

# ─── FA-C: Marsh Frog ─────────────────────────────────────────────────────────
func _make_marsh_frog(wp: Vector2) -> Node2D:
	# TOP-DOWN: wide flat frog seen from directly above — 4 legs splayed outward
	var res := _lw_make(wp);  var co: Node2D = res[0]; var me: Node2D = res[1]; var fu: Node2D = res[2]
	var BODY  := Color(0.17, 0.26, 0.11)
	var BELLY := Color(0.22, 0.34, 0.14)
	var SKIN  := Color(0.28, 0.42, 0.18)
	var EYE   := Color(0.04, 0.06, 0.02)
	var GWIRE := Color(0.0, 0.8, 0.45, 0.8)
	var GEYE  := Color(0.0, 0.95, 0.6, 0.95)
	# Main body oval (wide, flat from above)
	_lw_poly(me, _lw_circle_pts(0.0, 2.0, 13.0, 9.0, 14), BODY)
	_lw_poly(me, _lw_circle_pts(0.0, 1.0,  9.5, 6.5, 12), BELLY)
	_lw_poly(me, _lw_circle_pts(0.0, 0.0,  6.0, 4.0, 10), SKIN)
	# Head — small circle forward (negative Y = up/forward in top-down)
	_lw_poly(me, _lw_circle_pts(0.0, -9.5, 5.5, 5.0, 10), BODY)
	# Front legs — short, splayed forward-outward
	for sx in [-1.0, 1.0]:
		_lw_line(me, PackedVector2Array([
			Vector2(sx * 7.0, -4.0),
			Vector2(sx * 13.0, -8.0),
			Vector2(sx * 15.5, -5.0),
		]), BODY, 2.8)
	# Back legs — long, bent outward and back
	for sx in [-1.0, 1.0]:
		_lw_line(me, PackedVector2Array([
			Vector2(sx * 8.0,  6.0),
			Vector2(sx * 16.0, 4.0),
			Vector2(sx * 18.5, 10.0),
			Vector2(sx * 14.0, 14.0),
		]), BODY, 2.8)
	# Eye bumps on top of head
	for sx in [-1.0, 1.0]:
		_lw_poly(me, _lw_circle_pts(sx * 3.2, -11.5, 3.0, 3.0, 8), BODY)
		_lw_poly(me, _lw_circle_pts(sx * 3.2, -11.5, 1.8, 1.8, 7), EYE)
	# DF-G: Data Frog — wireframe outlines, bright eye nodes, scan ring under body
	# Body outline
	_lw_line(fu, _lw_circle_pts(0.0, 2.0, 13.0, 9.0, 14), GWIRE, 0.9, true)
	_lw_line(fu, _lw_circle_pts(0.0, -9.5, 5.5, 5.0, 10), Color(0.0, 0.65, 0.35, 0.65), 0.7, true)
	# Leg outlines — dashed
	for sx in [-1.0, 1.0]:
		var fleg := PackedVector2Array([Vector2(sx*7.0,-4.0), Vector2(sx*13.0,-8.0), Vector2(sx*15.5,-5.0)])
		var bleg := PackedVector2Array([Vector2(sx*8.0,6.0), Vector2(sx*16.0,4.0), Vector2(sx*18.5,10.0), Vector2(sx*14.0,14.0)])
		for i in fleg.size() - 1:
			_lw_line(fu, PackedVector2Array([fleg[i], fleg[i+1]]), Color(0.0, 0.65, 0.35, 0.55), 0.8)
		for i in bleg.size() - 1:
			_lw_line(fu, PackedVector2Array([bleg[i], bleg[i+1]]), Color(0.0, 0.65, 0.35, 0.55), 0.8)
	# Eye nodes
	for sx in [-1.0, 1.0]:
		_lw_line(fu, _lw_circle_pts(sx * 3.2, -11.5, 3.0, 3.0, 8), GWIRE, 0.8, true)
		_lw_poly(fu, _lw_circle_pts(sx * 3.2, -11.5, 1.5, 1.5, 6), GEYE)
	# Scan ring beneath body
	_lw_line(fu, _lw_circle_pts(0.0, 2.0, 17.5, 13.0, 18), Color(0.0, 0.7, 0.4, 0.3), 0.7, true)
	return co

# ─── FA-D: Hex Crow ────────────────────────────────────────────────────────────
func _make_hex_crow(wp: Vector2) -> Node2D:
	var res := _lw_make(wp);  var co: Node2D = res[0]; var me: Node2D = res[1]
	var BLACK := Color(0.08, 0.08, 0.07);  var DKGRAY := Color(0.12, 0.12, 0.11)
	# Body
	_lw_poly(me, _lw_circle_pts(0.0, 0.0, 7.5, 4.5, 10), BLACK)
	# Wings folded
	_lw_poly(me, PackedVector2Array([Vector2(0,0),Vector2(-12,-3),Vector2(-10,3),Vector2(-3,4)]), DKGRAY)
	_lw_poly(me, PackedVector2Array([Vector2(0,0),Vector2( 10,-3),Vector2( 8, 3),Vector2( 3,4)]), BLACK)
	# Head
	_lw_poly(me, _lw_circle_pts(0.0,-6.0, 5.0, 4.5, 9), BLACK)
	# Beak
	_lw_poly(me, PackedVector2Array([Vector2(2.5,-7.0),Vector2(8.5,-6.0),Vector2(5.0,-4.5)]), DKGRAY)
	# Eye
	_lw_poly(me, _lw_circle_pts(1.5,-7.0, 1.2, 1.2, 6), Color(0.3,0.22,0.1,0.8))
	# Feet
	for sx in [-1.0, 1.0]:
		_lw_line(me, PackedVector2Array([Vector2(sx*2.5,4.5),Vector2(sx*3.5,9.0)]), DKGRAY, 1.2)
		_lw_line(me, PackedVector2Array([Vector2(sx*3.5,9.0),Vector2(sx*6.0,11.0)]), DKGRAY, 0.9)
		_lw_line(me, PackedVector2Array([Vector2(sx*3.5,9.0),Vector2(sx*2.0,11.5)]), DKGRAY, 0.9)
	# No future counterpart picked — crow vanishes during flip
	return co

# ─── FL-C: Stone Moss ─────────────────────────────────────────────────────────
func _make_stone_moss(wp: Vector2) -> Node2D:
	# TOP-DOWN: flat irregular ground-cover blob — large ellipse, satellite blobs, speckle dots
	var res := _lw_make(wp);  var co: Node2D = res[0]; var me: Node2D = res[1]; var fu: Node2D = res[2]
	var MOSS_DARK  := Color(0.13, 0.18, 0.09)
	var MOSS_MID   := Color(0.17, 0.24, 0.12)
	var MOSS_LT    := Color(0.22, 0.31, 0.15)
	var SPECK      := Color(0.28, 0.40, 0.18)
	var SCAN_GREEN := Color(0.0, 0.80, 0.42, 0.72)
	var NODE_GREEN := Color(0.0, 0.95, 0.55, 0.90)
	# Main blob
	_lw_poly(me, _lw_circle_pts( 0.0,  0.0, 18.0, 11.5, 14), MOSS_DARK)
	_lw_poly(me, _lw_circle_pts(-3.5, -2.0, 13.0,  8.0, 12), MOSS_MID)
	_lw_poly(me, _lw_circle_pts( 4.0,  2.0,  8.0,  5.5, 10), MOSS_LT)
	# 3 satellite blobs touching edge
	_lw_poly(me, _lw_circle_pts(-14.0, -5.0,  7.0, 4.5, 10), MOSS_DARK)
	_lw_poly(me, _lw_circle_pts( 12.0,  6.0,  6.0, 4.0,  9), MOSS_MID)
	_lw_poly(me, _lw_circle_pts( -4.0, 10.5,  6.5, 4.0,  9), MOSS_DARK)
	# Speckle dots
	var speckles := [
		Vector2(-8.0,-4.0), Vector2(-2.0,-7.0), Vector2( 5.0,-4.0),
		Vector2(10.0, 0.0), Vector2( 7.0, 6.0), Vector2( 0.0, 5.0),
		Vector2(-6.0, 5.0), Vector2(-12.0,1.0), Vector2(-10.0,-9.0),
	]
	for sp in speckles:
		_lw_poly(me, _lw_circle_pts(sp.x, sp.y, 1.2, 1.2, 5), SPECK)
	# DF-C: Scan Moss — 3 nested outline ellipses, horizontal sweep lines, data-node dots
	_lw_line(fu, _lw_circle_pts( 0.0,  0.0, 18.0, 11.5, 14), SCAN_GREEN, 0.85, true)
	_lw_line(fu, _lw_circle_pts( 0.0,  0.0, 12.0,  7.5, 12), Color(0.0, 0.65, 0.35, 0.55), 0.65, true)
	_lw_line(fu, _lw_circle_pts( 0.0,  0.0,  7.0,  4.5, 10), Color(0.0, 0.55, 0.28, 0.4), 0.5, true)
	# Horizontal sweep lines
	for iy in [-4, -1, 2, 5]:
		var sweep_w: float = sqrt(maxf(0.0, 18.0*18.0 - float(iy)*float(iy))) * 0.9
		_lw_line(fu, PackedVector2Array([Vector2(-sweep_w, float(iy)), Vector2(sweep_w, float(iy))]),
			Color(0.0, 0.72, 0.38, 0.3), 0.5)
	# Data-node dots at speckle positions
	for sp in speckles:
		_lw_poly(fu, _lw_circle_pts(sp.x, sp.y, 1.4, 1.4, 5), NODE_GREEN)
	# Satellite outline rings
	for sv in [Vector2(-14.0,-5.0), Vector2(12.0,6.0), Vector2(-4.0,10.5)]:
		_lw_line(fu, _lw_circle_pts(sv.x, sv.y, 6.0, 4.0, 9), Color(0.0,0.65,0.35,0.5), 0.6, true)
	return co

# ─── FA-N1: Glowfly ───────────────────────────────────────────────────────────
func _make_glowfly(wp: Vector2) -> Node2D:
	# TOP-DOWN: dragonfly from above — thin oval body, 4 wing ovals, eye dots, segment lines
	var res := _lw_make(wp);  var co: Node2D = res[0]; var me: Node2D = res[1]; var fu: Node2D = res[2]
	var WING   := Color(0.10, 0.17, 0.10, 0.68)
	var WING2  := Color(0.09, 0.15, 0.09, 0.58)
	var BODY   := Color(0.16, 0.24, 0.11)
	var BODY_D := Color(0.12, 0.18, 0.08)
	var EYE    := Color(0.05, 0.08, 0.03)
	var GWIRE  := Color(0.0, 0.82, 0.46, 0.80)
	var GEYE   := Color(0.0, 0.96, 0.58, 0.95)
	var GNODE  := Color(0.0, 0.78, 0.42, 0.70)
	# 4 wings — 2 forward (larger), 2 rear (slightly smaller, offset back)
	_lw_poly(me, _lw_circle_pts(-12.0, -6.0, 11.0, 6.0, 10), WING)
	_lw_poly(me, _lw_circle_pts( 12.0, -6.0, 11.0, 6.0, 10), WING)
	_lw_poly(me, _lw_circle_pts(-10.0,  5.0,  9.0, 5.0, 10), WING2)
	_lw_poly(me, _lw_circle_pts( 10.0,  5.0,  9.0, 5.0, 10), WING2)
	# Thin body — long narrow oval
	_lw_poly(me, _lw_circle_pts(0.0, 0.0, 3.5, 14.0, 12), BODY)
	_lw_poly(me, _lw_circle_pts(0.0, 0.0, 2.0,  9.0, 10), BODY_D)
	# Body segment lines
	for sy in [-6.0, -2.0, 2.0, 6.0, 10.0]:
		_lw_line(me, PackedVector2Array([Vector2(-2.5, sy), Vector2(2.5, sy)]),
			Color(0.22, 0.34, 0.16, 0.5), 0.6)
	# Head — small circle at top of body
	_lw_poly(me, _lw_circle_pts(0.0, -14.0, 3.0, 3.0, 8), BODY)
	# Compound eyes
	_lw_poly(me, _lw_circle_pts(-2.2, -15.5, 1.8, 1.8, 6), EYE)
	_lw_poly(me, _lw_circle_pts( 2.2, -15.5, 1.8, 1.8, 6), EYE)
	# DF-N1: Scan Glowfly — wireframe body, wing ring outlines, eye nodes, orbit scan ring
	# Scan orbit ring
	_lw_line(fu, _lw_circle_pts(0.0, 0.0, 20.0, 18.0, 20),
		Color(0.0, 0.72, 0.40, 0.28), 0.6, true)
	# Wing ring outlines
	_lw_line(fu, _lw_circle_pts(-12.0, -6.0, 11.0, 6.0, 10), GWIRE, 0.8, true)
	_lw_line(fu, _lw_circle_pts( 12.0, -6.0, 11.0, 6.0, 10), GWIRE, 0.8, true)
	_lw_line(fu, _lw_circle_pts(-10.0,  5.0,  9.0, 5.0, 10), Color(0.0,0.65,0.35,0.6), 0.7, true)
	_lw_line(fu, _lw_circle_pts( 10.0,  5.0,  9.0, 5.0, 10), Color(0.0,0.65,0.35,0.6), 0.7, true)
	# Wing tip data nodes
	_lw_poly(fu, _lw_circle_pts(-22.0, -6.0, 1.5, 1.5, 5), GNODE)
	_lw_poly(fu, _lw_circle_pts( 22.0, -6.0, 1.5, 1.5, 5), GNODE)
	_lw_poly(fu, _lw_circle_pts(-18.0,  5.0, 1.2, 1.2, 5), Color(0.0,0.65,0.35,0.6))
	_lw_poly(fu, _lw_circle_pts( 18.0,  5.0, 1.2, 1.2, 5), Color(0.0,0.65,0.35,0.6))
	# Body outline
	_lw_line(fu, _lw_circle_pts(0.0, 0.0, 3.5, 14.0, 12), GWIRE, 0.85, true)
	# Eye nodes
	_lw_poly(fu, _lw_circle_pts(-2.2, -15.5, 2.2, 2.2, 6), GEYE)
	_lw_poly(fu, _lw_circle_pts(-2.2, -15.5, 0.8, 0.8, 5), Color(0.0, 1.0, 0.65))
	_lw_poly(fu, _lw_circle_pts( 2.2, -15.5, 2.2, 2.2, 6), GEYE)
	_lw_poly(fu, _lw_circle_pts( 2.2, -15.5, 0.8, 0.8, 5), Color(0.0, 1.0, 0.65))
	return co

# ─── FA-N2: Hex Snail ─────────────────────────────────────────────────────────
func _make_hex_snail(wp: Vector2) -> Node2D:
	# TOP-DOWN: snail from above — concentric spiral shell, soft body blob, stalk eyes
	var res := _lw_make(wp);  var co: Node2D = res[0]; var me: Node2D = res[1]; var fu: Node2D = res[2]
	var SHELL_D := Color(0.28, 0.20, 0.11)
	var SHELL_M := Color(0.36, 0.26, 0.14)
	var SHELL_L := Color(0.44, 0.32, 0.17)
	var SHELL_C := Color(0.18, 0.12, 0.06)
	var BODY    := Color(0.32, 0.26, 0.16)
	var BODY_L  := Color(0.42, 0.34, 0.20)
	var EYE     := Color(0.06, 0.04, 0.02)
	var GWIRE   := Color(0.0, 0.80, 0.44, 0.82)
	var GEYE    := Color(0.0, 0.96, 0.58, 0.95)
	# Body blob — extends to the left of shell
	_lw_poly(me, _lw_circle_pts(-12.0, 3.0, 10.0, 6.0, 12), BODY)
	_lw_poly(me, _lw_circle_pts(-12.0, 2.0,  7.0, 4.0, 10), BODY_L)
	# Shell — 4 concentric circles (top-down spiral suggestion)
	_lw_poly(me, _lw_circle_pts(5.0, 0.0, 14.0, 14.0, 14), SHELL_D)
	_lw_poly(me, _lw_circle_pts(5.0, 0.0,  9.5,  9.5, 12), SHELL_M)
	_lw_poly(me, _lw_circle_pts(5.0, 0.0,  5.5,  5.5, 10), SHELL_L)
	_lw_poly(me, _lw_circle_pts(5.0, 0.0,  2.5,  2.5,  8), SHELL_M)
	_lw_poly(me, _lw_circle_pts(5.0, 0.0,  1.0,  1.0,  6), SHELL_C)
	# Stalk eyes at body end
	_lw_line(me, PackedVector2Array([Vector2(-18.0, -1.0), Vector2(-22.0, -5.0)]), BODY, 1.0)
	_lw_line(me, PackedVector2Array([Vector2(-18.0,  5.0), Vector2(-22.0,  9.0)]), BODY, 1.0)
	_lw_poly(me, _lw_circle_pts(-22.5, -5.5, 1.8, 1.8, 6), EYE)
	_lw_poly(me, _lw_circle_pts(-22.5,  9.5, 1.8, 1.8, 6), EYE)
	# Scatter behaviour: snail shrinks scale on proximity (handled in _process override via meta)
	# DF-N2: Shell Data — concentric ring outlines brightening inward, spiral hint, body outline, eye nodes
	# Body outline
	_lw_line(fu, _lw_circle_pts(-12.0, 3.0, 10.0, 6.0, 12), Color(0.0,0.65,0.35,0.55), 0.7, true)
	# Shell rings — progressively brighter toward center
	for ri in 4:
		var rads := [14.0, 9.5, 5.5, 2.5]
		var alphas := [0.45, 0.58, 0.72, 0.88]
		_lw_line(fu, _lw_circle_pts(5.0, 0.0, rads[ri], rads[ri], 14 - ri*2),
			Color(0.0, 0.72 + ri*0.07, 0.40 + ri*0.06, alphas[ri]), 0.7 + ri*0.05, true)
	# Faint spiral hint line
	var spiral_pts := PackedVector2Array()
	for si in 20:
		var sa: float = TAU * float(si) / 20.0 * 1.5
		var sr: float = 13.5 * (1.0 - float(si) / 28.0)
		spiral_pts.append(Vector2(5.0 + cos(sa) * sr, sin(sa) * sr))
	_lw_line(fu, spiral_pts, Color(0.0, 0.60, 0.32, 0.28), 0.5)
	# Center node
	_lw_poly(fu, _lw_circle_pts(5.0, 0.0, 1.4, 1.4, 6), Color(0.0, 0.95, 0.58, 0.9))
	# Stalk eye nodes
	_lw_poly(fu, _lw_circle_pts(-22.5, -5.5, 2.2, 2.2, 6), GEYE)
	_lw_poly(fu, _lw_circle_pts(-22.5, -5.5, 0.8, 0.8, 5), Color(0.0, 1.0, 0.65))
	_lw_poly(fu, _lw_circle_pts(-22.5,  9.5, 2.2, 2.2, 6), GEYE)
	_lw_poly(fu, _lw_circle_pts(-22.5,  9.5, 0.8, 0.8, 5), Color(0.0, 1.0, 0.65))
	return co

# ─── Tron Flip — Boss Mode Cascade ───────────────────────────────────────────
## Triggers the 10s per-ring black cascade from the player's hex position.
## Flips the world from Overworld to Dark Future tile by tile (ring by ring).
## Sets GameState.boss_flip_active = true for the duration.
## Calls on_complete when the last ring flips — enemy_spawner uses this to
## reveal the boss and resume the encounter.
func trigger_tron_flip(player_world_pos: Vector2, on_complete: Callable) -> void:
	if is_future_mode: return   # already in Dark Future
	if GameState.boss_flip_active: return   # flip already in progress

	GameState.boss_flip_active = true

	var player_hex: Vector2i = pixel_to_hex(player_world_pos)

	# ── Build ring buckets: ring_idx → [Vector2i, ...] ────────────────────
	# ring_idx = hex distance from player hex
	var ring_buckets: Dictionary = {}   # int → Array[Vector2i]
	var max_ring: int = 0

	for key in hex_biomes_ow.keys():
		var d: int = _hex_dist_vi(key as Vector2i, player_hex)
		if not ring_buckets.has(d):
			ring_buckets[d] = []
		ring_buckets[d].append(key)
		if d > max_ring:
			max_ring = d

	if max_ring == 0: max_ring = 1   # guard against empty map

	const FLIP_DURATION  := 10.0   # seconds for wave to cross full map
	const HOLD_TIME      := 0.20   # seconds black hex is fully opaque
	const FADE_OUT_TIME  := 0.35   # seconds black hex fades out to reveal neon

	# ── Show HUD warning overlay ──────────────────────────────────────────
	var hud = get_parent().get_node_or_null("Hud")
	if hud != null and hud.has_method("show_flip_warning"):
		hud.show_flip_warning()

	# ── Swap biome sprites at the halfway point ───────────────────────────
	# Black hexes cover the transition — sprites swap behind them
	get_tree().create_timer(FLIP_DURATION * 0.5).timeout.connect(func():
		flip_living_world(true)
	)

	# ── Per-ring cascade ──────────────────────────────────────────────────
	for ring_idx in ring_buckets.keys():
		var delay: float = (float(ring_idx) / float(max_ring)) * FLIP_DURATION
		var hexes: Array = ring_buckets[ring_idx]

		get_tree().create_timer(delay).timeout.connect(func():
			for hkey in hexes:
				var hq: int = (hkey as Vector2i).x
				var hr: int = (hkey as Vector2i).y
				var hpos: Vector2 = hex_to_pixel(hq, hr)

				# Black hex polygon
				var bnode := Node2D.new()
				bnode.global_position = hpos
				bnode.z_index          = 8;  bnode.z_as_relative = false
				var bpts := PackedVector2Array()
				for fi in 6:
					var fa: float = deg_to_rad(60.0 * float(fi) - 30.0)
					bpts.append(Vector2(cos(fa), sin(fa)) * (HEX_SIZE + 1.0))
				var bpoly := Polygon2D.new()
				bpoly.polygon = bpts
				bpoly.color   = Color(0.0, 0.0, 0.0, 1.0)
				bnode.add_child(bpoly)
				add_child(bnode)

				# Hold then fade out
				var btw := get_tree().create_tween()
				btw.tween_interval(HOLD_TIME)
				btw.tween_property(bpoly, "color",
					Color(0.0, 0.0, 0.0, 0.0), FADE_OUT_TIME)
				btw.tween_callback(bnode.queue_free)
		)

	# ── Cascade complete ──────────────────────────────────────────────────
	var total_time: float = FLIP_DURATION + HOLD_TIME + FADE_OUT_TIME + 0.1
	get_tree().create_timer(total_time).timeout.connect(func():
		GameState.boss_flip_active = false
		GameState.flip_complete.emit()
		if hud != null and hud.has_method("hide_flip_warning"):
			hud.hide_flip_warning()
		on_complete.call()
	)

func trigger_tron_flipback(on_complete: Callable = Callable()) -> void:
	## Reverses the flip — cascades from castle outward back to Overworld.
	if not is_future_mode: return

	const FLIP_DURATION := 6.0

	var hud = get_parent().get_node_or_null("Hud")

	# Ring buckets from castle center (pixel_to_hex of MAP_CENTER = Vector2i(0,0))
	var origin_hex := Vector2i(0, 0)
	var ring_buckets: Dictionary = {}
	var max_ring: int = 0
	for key in hex_biomes_fut.keys():
		var d: int = _hex_dist_vi(key as Vector2i, origin_hex)
		if not ring_buckets.has(d): ring_buckets[d] = []
		ring_buckets[d].append(key)
		if d > max_ring: max_ring = d
	if max_ring == 0: max_ring = 1

	# Biome swap at halfway
	get_tree().create_timer(FLIP_DURATION * 0.5).timeout.connect(func():
		flip_living_world(false)
	)

	# Per-ring black hexes sweeping outward
	for ring_idx in ring_buckets.keys():
		var delay: float = (float(ring_idx) / float(max_ring)) * FLIP_DURATION
		var hexes: Array = ring_buckets[ring_idx]
		get_tree().create_timer(delay).timeout.connect(func():
			for hkey in hexes:
				var hpos: Vector2 = hex_to_pixel(
					(hkey as Vector2i).x, (hkey as Vector2i).y)
				var bnode := Node2D.new()
				bnode.global_position = hpos
				bnode.z_index = 8;  bnode.z_as_relative = false
				var bpts := PackedVector2Array()
				for fi in 6:
					var fa: float = deg_to_rad(60.0 * float(fi) - 30.0)
					bpts.append(Vector2(cos(fa), sin(fa)) * (HEX_SIZE + 1.0))
				var bpoly := Polygon2D.new()
				bpoly.polygon = bpts;  bpoly.color = Color(0.0, 0.0, 0.0, 1.0)
				bnode.add_child(bpoly);  add_child(bnode)
				var btw := get_tree().create_tween()
				btw.tween_interval(0.20)
				btw.tween_property(bpoly, "color", Color(0.0, 0.0, 0.0, 0.0), 0.35)
				btw.tween_callback(bnode.queue_free)
		)

	get_tree().create_timer(FLIP_DURATION + 0.6).timeout.connect(func():
		if not on_complete.is_null(): on_complete.call()
	)

# ─── Reactive Tile Overlay Drawer ────────────────────────────────────────────
# Sits above the baked SubViewport sprite (z=-8), redraws on state change.
# hex_states / hex_rotations are shared Dictionary references from HexMap.
class _OverlayDrawer extends Node2D:
	const S    := 35.0
	const Q    := 75
	const R    := 40
	const CX   := 6660.0 / 2.0
	const CY   := 4200.0 / 2.0

	var hex_states: Dictionary    = {}
	var hex_rotations: Dictionary = {}

	# ── Grid Base colours ───────────────────────────────────────────────────
	const SCUFF      := Color(0.28, 0.32, 0.38, 0.42)
	const CRACK      := Color(0.0,  0.13, 0.26, 0.92)
	const CRACK_BR   := Color(0.0,  0.09, 0.18, 0.72)
	const VOID_PATCH := Color(0.01, 0.03, 0.07, 0.68)
	const NODE_DEAD  := Color(0.02, 0.04, 0.08, 0.96)

	func _draw() -> void:
		for key in hex_states.keys():
			var state: int = hex_states[key]
			if state <= 0:
				continue
			var q: int = (key as Vector2i).x
			var r: int = (key as Vector2i).y
			var c: Vector2 = _p(q, r)
			var rot_idx: int = hex_rotations.get(key, 0)
			_draw_grid_base(c, state, rot_idx)

	func _draw_grid_base(center: Vector2, state: int, rot_idx: int) -> void:
		# Apply rotation transform — all subsequent draw calls centred at (0,0),
		# mapped to hex centre with rotation.
		draw_set_transform(center, deg_to_rad(float(rot_idx) * 60.0), Vector2.ONE)

		# ── Vertex positions at unit hex (pre-rotate) ─────────────────────────
		var verts := PackedVector2Array()
		for i in 6:
			var a: float = deg_to_rad(60.0 * float(i) - 30.0)
			verts.append(Vector2(cos(a), sin(a)) * S)

		# ─── State 1 — Worn ───────────────────────────────────────────────────
		# Two faint scuff lines across face; one dead vertex node.
		if state >= 1:
			draw_line(Vector2(-7.0, -13.0), Vector2( 7.0,  13.0), SCUFF, 0.9)
			draw_line(Vector2(-13.0, 2.0),  Vector2( 5.0, -10.0), SCUFF, 0.7)
			# Kill vertex 0 (top)
			draw_circle(verts[0], 2.0, NODE_DEAD)

		# ─── State 2 — Stressed ───────────────────────────────────────────────
		# Hairline crack from center toward vertex 0; 2 dead nodes.
		if state >= 2:
			draw_line(Vector2.ZERO, verts[0] * 0.92, CRACK, 1.1)
			draw_line(verts[0] * 0.92, verts[0], CRACK_BR, 0.8)
			# Kill vertices 0 and 5
			draw_circle(verts[0], 2.0, NODE_DEAD)
			draw_circle(verts[5], 2.0, NODE_DEAD)

		# ─── State 3 — Damaged ────────────────────────────────────────────────
		# Crack branches; secondary crack toward vertex 2; dark fill patches;
		# 4 dead nodes.
		if state >= 3:
			# Branch off main crack
			var branch_start := verts[0] * 0.55
			draw_line(branch_start, verts[1] * 0.80, CRACK, 1.0)
			# Secondary crack
			draw_line(Vector2.ZERO, verts[2] * 0.88, CRACK, 1.1)
			# Void patch at crack junction
			var patch1 := PackedVector2Array([
				Vector2.ZERO,
				verts[0] * 0.38,
				verts[1] * 0.30
			])
			draw_colored_polygon(patch1, VOID_PATCH)
			# Kill 0,1,4,5
			for vi in [0, 1, 4, 5]:
				draw_circle(verts[vi], 2.0, NODE_DEAD)
			# Partial edge gap on side 0 (top-right edge)
			draw_line(verts[0] * 0.7, verts[1] * 0.7,
				Color(0.02, 0.05, 0.09, 0.65), 2.5)

		# ─── State 4 — Critical ───────────────────────────────────────────────
		# Heavy fracture; 3rd crack toward vertex 3; large void patches;
		# 5 dead nodes (1 weak dim).
		if state >= 4:
			# Third crack
			draw_line(Vector2.ZERO, verts[3] * 0.90, CRACK, 1.2)
			# Fork on second crack
			draw_line(verts[2] * 0.60, verts[3] * 0.45, CRACK_BR, 0.9)
			# Large void patches
			var patch2 := PackedVector2Array([
				Vector2.ZERO,
				verts[2] * 0.52,
				verts[3] * 0.48,
				verts[4] * 0.35
			])
			draw_colored_polygon(patch2, Color(0.01, 0.02, 0.05, 0.72))
			var patch3 := PackedVector2Array([
				Vector2.ZERO,
				verts[4] * 0.35,
				verts[5] * 0.42
			])
			draw_colored_polygon(patch3, Color(0.01, 0.02, 0.05, 0.58))
			# Kill 0,1,2,3,4 — leave 5 dimmed
			for vi in [0, 1, 2, 3, 4]:
				draw_circle(verts[vi], 2.0, NODE_DEAD)
			draw_circle(verts[5], 2.0, Color(0.0, 0.15, 0.25, 0.75))
			# Edge erasure on cracked sides
			for side in [0, 3, 4]:
				var ep0: Vector2 = verts[side]
				var ep1: Vector2 = verts[(side + 1) % 6]
				draw_line(ep0 * 0.82, ep1 * 0.82,
					Color(0.01, 0.03, 0.06, 0.78), 3.0)

		# Reset transform
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	func _p(q: int, r: int) -> Vector2:
		return Vector2(
			S * (sqrt(3.0) * float(q) + sqrt(3.0) / 2.0 * float(r)) + CX,
			S * 1.5 * float(r) + CY
		)

# ─── Biome Fill Baker ─────────────────────────────────────────────────────────
# Runs inside a SubViewport — bakes ONCE. Two instances: one OW, one Future.
# The baked textures sit at z=-101, below the transparent grid sprite at z=-100.
class _BiomeDrawer extends Node2D:
	const S  := 35.0
	const Q  := 75
	const R  := 40
	const W  := 6660.0
	const H  := 4200.0
	const CX := W / 2.0
	const CY := H / 2.0

	var hex_biomes: Dictionary = {}   # Vector2i -> biome int
	var hex_blend:  Dictionary = {}   # Vector2i -> {neighbor:int, intensity:float}
	var is_future:  bool = false

	func _ready() -> void:
		queue_redraw()

	func _draw() -> void:
		# Background — base biome fill for the whole world
		if not is_future:
			draw_rect(Rect2(0.0, 0.0, W, H), Color(0.24, 0.56, 0.18))    # GRASSLAND — bright grass
		else:
			draw_rect(Rect2(0.0, 0.0, W, H), Color(0.012, 0.020, 0.038)) # GRID_BASE — near-black

		# Per-hex fills — only non-base biomes (base is covered by background rect)
		for q in range(-Q, Q + 1):
			for r in range(-R, R + 1):
				var c := _p(q, r)
				if c.x < 0.0 or c.x > W or c.y < 0.0 or c.y > H:
					continue
				var key := Vector2i(q, r)
				var biome: int = hex_biomes.get(key, 0)
				if biome == 0:
					continue   # GRASSLAND / GRID_BASE already covered by bg rect
				var pts := _hex_pts(c)
				draw_colored_polygon(pts, _fill(biome))

		# Blend tint overlays at biome borders
		for key in hex_blend.keys():
			var bd   = hex_blend[key]
			var nb   : int   = (bd as Dictionary)["neighbor"]
			var inten: float = (bd as Dictionary)["intensity"]
			if nb == 0: continue
			var kv: Vector2i = key as Vector2i
			var c := _p(kv.x, kv.y)
			if c.x < 0.0 or c.x > W or c.y < 0.0 or c.y > H: continue
			var pts := _hex_pts(c)
			var col: Color = _fill(nb)
			col.a = inten * (0.35 if not is_future else 0.18)
			draw_colored_polygon(pts, col)

	func _fill(biome: int) -> Color:
		if not is_future:
			# OVERWORLD — bright warm fills, dark mortar grid lines show the tile
			match biome:
				1: return Color(0.18, 0.50, 0.35)   # MARSH — mid teal-green
				2: return Color(0.08, 0.36, 0.10)   # FOREST — rich dark green
				3: return Color(0.56, 0.52, 0.44)   # ASH_PLAIN — warm stone gray
				4: return Color(0.72, 0.60, 0.30)   # SAND — warm golden tan
				5: return Color(0.82, 0.22, 0.04)   # MAGMA — vivid red-orange
				6: return Color(0.62, 0.80, 0.92)   # ICE — pale sky blue
				7: return Color(0.14, 0.38, 0.72)   # WATER — mid saturated blue
			return Color(0.24, 0.56, 0.18)          # GRASSLAND — bright grass green
		else:
			# DARK FUTURE — near-black fills, neon grid lines own the visual
			# Tiny tint differences let biome regions still read at close range
			match biome:
				1: return Color(0.016, 0.028, 0.016)   # CIRCUIT — near-black w/ green hint
				2: return Color(0.022, 0.010, 0.028)   # CORRUPTED — near-black w/ purple hint
				3: return Color(0.006, 0.002, 0.016)   # VOID_RIFT — deepest black-purple
				4: return Color(0.018, 0.018, 0.022)   # STATIC_FIELD — neutral black
				5: return Color(0.008, 0.012, 0.028)   # FROZEN_DATA — near-black blue hint
				6: return Color(0.004, 0.008, 0.022)   # DARK_POOL — darkest blue-black
				7: return Color(0.020, 0.018, 0.010)   # DEAD_SAND — near-black warm hint
			return Color(0.012, 0.020, 0.038)          # GRID_BASE — base near-black

	func _hex_pts(c: Vector2) -> PackedVector2Array:
		var pts := PackedVector2Array()
		for i in 6:
			var a: float = deg_to_rad(60.0 * float(i) - 30.0)
			pts.append(c + Vector2(cos(a), sin(a)) * S)
		return pts

	func _p(q: int, r: int) -> Vector2:
		return Vector2(
			S * (sqrt(3.0) * float(q) + sqrt(3.0) / 2.0 * float(r)) + CX,
			S * 1.5 * float(r) + CY
		)
