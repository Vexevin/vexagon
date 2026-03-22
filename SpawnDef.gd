## SpawnDef.gd
## Data definition for any world-spawnable object.
## One SpawnDef = one spawnable type. No new spawn code ever.
## Create instances in WorldSpawner._ready() or save as .tres in res://spawns/
class_name SpawnDef
extends Resource

# ── Identity ──────────────────────────────────────────────────────────────────
@export var id: String = ""
@export var display_name: String = ""
@export var group: String = ""

# ── Placement ─────────────────────────────────────────────────────────────────
@export var count_min: int = 1
@export var count_max: int = 1

## Minimum hex-ring distance from map center (castle).
@export var min_hex_from_center: int = 0

## Minimum hex-ring distance between any two placed instances of this def.
@export var min_hex_between: int = 0

## If > 0: placement candidates are limited to a hex-ring of this radius.
## If 0: WorldSpawner uses its own full-map candidate list.
@export var search_radius: int = 0

## Hex types allowed for placement. 0 = NORMAL (see HexType enum in hex_map.gd).
@export var valid_hex_types: Array[int] = [0]

# ── Behavior ──────────────────────────────────────────────────────────────────
## Node disappears on first interaction (pickup, bullet hit, etc.)
@export var one_shot: bool = true

## If dropped (pit penalty), respawn at a new random hex.
@export var respawn_on_drop: bool = false

# ── Visuals ───────────────────────────────────────────────────────────────────
## WorldSpawner uses these to draw the node unless draw_mode == "custom".
@export var draw_mode: String = "builtin"      # "builtin" or "custom"
@export var draw_func: String = ""             # func name on WorldSpawner if custom

@export var base_color: Color  = Color(0.2, 0.75, 1.0)
@export var glow_color: Color  = Color(0.2, 0.75, 1.0, 0.30)
@export var accent_color: Color = Color(1.0, 1.0, 1.0, 0.55)   # inner facet / jewel
@export var size: float = 14.0
@export var z_index: int = 2

# ── Signals (string names — WorldSpawner emits these after placement events) ──
@export var on_collect_signal: String = ""   # emitted when item is collected/destroyed
