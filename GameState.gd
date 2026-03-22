## GameState.gd
## Global state singleton. Add to Project → Autoloads as "GameState".
## Path: res://GameState.gd
extends Node

# ── Tron Flip ─────────────────────────────────────────────────────────────────
## True during the 10s boss flip cascade. Freezes player, enemies, bullets.
var boss_flip_active: bool = false

## Emitted when the cascade completes — enemy_spawner listens to reveal boss.
signal flip_started()
signal flip_complete()
