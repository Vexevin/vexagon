extends CanvasLayer

# ─── VARS ─────────────────────────────────────────────────────────────────────
var gold := 0
var node_fragments := 0
var kill_count := 0
var skill_points := 0
var artifact_count: int = 0   # total artifacts revealed at tower this run
var pending_queue: Array = []
var auto_pause_enabled: bool = false
var auto_pause_min_cost := 1
var cooldown_label: Label
var passive_timer := 0.0
var health_label: Label
var pause_label: Label
var wave_label: Label
var boss_label: Label
var bt_label: Label
var game_over_panel: Panel
var win_panel: Panel
var selected_node_type := ""

# ── Health bar ────────────────────────────────────────────────────────────────
var hp_bar_bg: ColorRect
var hp_bar_fill: ColorRect
var _shield_bar_bg: ColorRect = null
var _shield_bar_fill: ColorRect = null

# ── Tower counter ─────────────────────────────────────────────────────────────
var tower_label: Label

# ── Boss HP bar ───────────────────────────────────────────────────────────────
var boss_hp_bar_bg: ColorRect
var boss_hp_bar_fill: ColorRect
var _artifact_carry_label: Label = null
var _artifact_reveal_label: Label = null
var _milestone_label: Label = null
var _flip_warning_label: Label = null
var _flip_warning_tween: Tween  = null
var _tracker_dots: Array = []      # 50 Polygon2D dots
var _tracker_bar:  Node2D = null   # container node
var boss_hp_label: Label
var boss_warning_label: Label
var current_boss_rank := 0

# ── SP progress bar ───────────────────────────────────────────────────────────
var sp_progress_label: Label

# ── Window references ─────────────────────────────────────────────────────────
var _skills_win: Panel    = null
var _tower_win: Panel     = null
var _placer_win: Panel    = null
var _powerups_win: Panel  = null
var _stats_win: Panel     = null
var _debug_panel:   Panel = null
var _options_panel: Panel = null
const WIN_POS_FILE := "user://vexagon_windows.cfg"
var _font_scale: float = 2.0   # default 2x — tunable via GMP   # persists window positions

# ── Stats tracking ────────────────────────────────────────────────────────────
var stat_shots_fired    := 0
var stat_damage_taken   := 0
var stat_waves_survived := 0
var stat_bosses_killed  := 0
var stat_nodes_placed   := 0
var _stats_labels: Dictionary = {}

# ── Tower upgrade levels ─────────────────────────────────────────────────────
var tower_upgrade_levels := [0, 0, 0, 0]
var _checkpoint: Dictionary = {}
var _escape_panel: Panel = null
var _rainbow_tween: Tween = null  # powerup panel rainbow — killed on scene end   # empty = no checkpoint
var _sp_spent_at_checkpoint: int = 0
var ng_plus: int = 0   # 0 = normal, 1+ = NG+ cycle
var active_powerups: Array = []   # list of powerup ID strings
var _powerup_panel: Panel = null
var _active_drag: Dictionary = {}   # {panel, offset} when dragging
var max_homing_bullets: int = 25   # default 25, GMP slider goes to 100
const TOWER_UPGRADE_MAX  := 5
const TOWER_UPGRADE_COST := 50   # gold per level

# ── Power-up gallery ──────────────────────────────────────────────────────────
var collected_powerups: Array = []   # filled in future when powerup system lands

var skill_names := [
	"Fire Rate", "Firepower", "Range", "Proj Speed",
	"Knockback", "Extra Shots", "Bounce", "Explode",
	"More Health", "Slow Enemies", "Gold Multiplier",
	"Heat Seeker"
]
var skill_levels := []
var skill_kill_costs := []
var skill_rows := []

@onready var gold_label: Label          = $GoldLabel
@onready var node_label: Label          = $UpgradeLabel
@onready var kill_label: Label          = $KillLabel
@onready var sp_label: Label            = $SPLabel
@onready var skill_panel: VBoxContainer = $SkillPanel

var confirm_btn: Button

# ─── READY ────────────────────────────────────────────────────────────────────
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	# ── Left-column HUD labels — positions driven by _reflow_hud_labels() ───
	gold_label.add_theme_font_size_override("font_size", 18)
	node_label.add_theme_font_size_override("font_size", 18)
	kill_label.add_theme_font_size_override("font_size", 18)
	sp_label.add_theme_font_size_override("font_size", 18)

	health_label = Label.new()
	health_label.text = "HP: 10 / 10"
	health_label.add_theme_font_size_override("font_size", 18);  add_child(health_label)

	hp_bar_bg   = ColorRect.new();  hp_bar_bg.size   = Vector2(200, 14);  hp_bar_bg.color   = Color(0.12, 0.12, 0.12);  add_child(hp_bar_bg)
	hp_bar_fill = ColorRect.new();  hp_bar_fill.size = Vector2(200, 14);  hp_bar_fill.color = Color.GREEN;               add_child(hp_bar_fill)

	wave_label  = Label.new();  wave_label.text  = "Wave: 1"
	wave_label.add_theme_font_size_override("font_size", 18);  add_child(wave_label)
	boss_label  = Label.new();  boss_label.text  = "Boss in: 5 waves"
	boss_label.add_theme_font_size_override("font_size", 18);  add_child(boss_label)
	bt_label    = Label.new();  bt_label.text    = "BT: Ready"
	bt_label.add_theme_font_size_override("font_size", 18);  add_child(bt_label)
	tower_label = Label.new();  tower_label.text = "🏰  Towers: 0 / 5"
	tower_label.add_theme_font_size_override("font_size", 18);  tower_label.modulate = Color(1.0, 0.55, 0.15);  add_child(tower_label)

	pause_label = Label.new();  pause_label.text = "⏸";  pause_label.visible = false
	pause_label.add_theme_font_size_override("font_size", 24);  pause_label.modulate = Color.RED;  add_child(pause_label)

	# ── Boss bar — centered top of screen ───────────────────────────────────
	var bar_w := 480.0
	var bar_vp_x := get_viewport().get_visible_rect().size.x
	var bar_x := bar_vp_x / 2.0 - bar_w / 2.0
	boss_hp_label = Label.new()
	boss_hp_label.position = Vector2(0, 6);  boss_hp_label.size = Vector2(bar_vp_x, 22)
	boss_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boss_hp_label.add_theme_font_size_override("font_size", 16)
	boss_hp_label.modulate = Color(1.0, 0.6, 1.0)
	boss_hp_label.visible = false;  add_child(boss_hp_label)
	boss_hp_bar_bg = ColorRect.new()
	boss_hp_bar_bg.position = Vector2(bar_x, 30);  boss_hp_bar_bg.size = Vector2(bar_w, 18)
	boss_hp_bar_bg.color = Color(0.12, 0.0, 0.18);  boss_hp_bar_bg.visible = false;  add_child(boss_hp_bar_bg)
	boss_hp_bar_fill = ColorRect.new()
	boss_hp_bar_fill.position = Vector2(bar_x, 30);  boss_hp_bar_fill.size = Vector2(bar_w, 18)
	boss_hp_bar_fill.color = Color(0.5, 0.0, 0.85);  boss_hp_bar_fill.visible = false;  add_child(boss_hp_bar_fill)
	# ── Cooldown — centered, below boss bar ─────────────────────────────────
	cooldown_label = Label.new()
	cooldown_label.position = Vector2(0, 120);  cooldown_label.size = Vector2(bar_vp_x, 36)
	cooldown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cooldown_label.add_theme_font_size_override("font_size", 22);  cooldown_label.visible = false;  add_child(cooldown_label)
	boss_warning_label = Label.new();  boss_warning_label.position = Vector2(150, 240);  boss_warning_label.size = Vector2(652, 70)
	# ── Artifact carry indicator (top-center, below cooldown label) ──────────
	var _vp := get_viewport().get_visible_rect().size
	_artifact_carry_label = Label.new()
	_artifact_carry_label.text = "◆  CARRYING ARTIFACT  —  RETURN TO CASTLE"
	_artifact_carry_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_artifact_carry_label.size = Vector2(_vp.x * 0.6, 36)
	_artifact_carry_label.position = Vector2(_vp.x * 0.2, _vp.y * 0.25)
	_artifact_carry_label.add_theme_font_size_override("font_size", int(18 * _font_scale))
	_artifact_carry_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.15))
	_artifact_carry_label.visible = false
	add_child(_artifact_carry_label)
	# ── Artifact reveal flash (center screen) ────────────────────────────────
	_artifact_reveal_label = Label.new()
	_artifact_reveal_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_artifact_reveal_label.size = Vector2(_vp.x * 0.5, 56)
	_artifact_reveal_label.position = Vector2(_vp.x * 0.25, _vp.y * 0.38)
	_artifact_reveal_label.add_theme_font_size_override("font_size", int(26 * _font_scale))
	_artifact_reveal_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
	_artifact_reveal_label.visible = false
	add_child(_artifact_reveal_label)
	# ── Milestone banner (center-low) ────────────────────────────────────────
	_milestone_label = Label.new()
	_milestone_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_milestone_label.size = Vector2(_vp.x * 0.5, 56)
	_milestone_label.position = Vector2(_vp.x * 0.25, _vp.y * 0.45)
	_milestone_label.add_theme_font_size_override("font_size", int(24 * _font_scale))
	_milestone_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.5))
	_milestone_label.visible = false
	add_child(_milestone_label)
	# ── Artifact Tracker — 50 dots across bottom of screen ───────────────────
	_build_artifact_tracker(_vp)
	boss_warning_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boss_warning_label.add_theme_font_size_override("font_size", 40);  boss_warning_label.modulate = Color.RED
	boss_warning_label.visible = false;  add_child(boss_warning_label)

	# ── Skill panel contents (reparented into window later) ───────────────────
	skill_panel.visible = false

	sp_progress_label = Label.new();  sp_progress_label.text = "⚡ ░░░░░  (0 / 5 kills)"
	sp_progress_label.add_theme_font_size_override("font_size", 14);  sp_progress_label.modulate = Color.CYAN
	skill_panel.add_child(sp_progress_label)

	var ap_dot = Label.new();  ap_dot.text = " ● INACTIVE";  ap_dot.modulate = Color.RED
	skill_panel.add_child(ap_dot)

	var tier_btn = Button.new();  tier_btn.text = "MIN: Any";  tier_btn.focus_mode = Control.FOCUS_NONE;  tier_btn.process_mode = Node.PROCESS_MODE_ALWAYS
	tier_btn.pressed.connect(func():
		if auto_pause_min_cost == 1:    auto_pause_min_cost = 2; tier_btn.text = "MIN: 2sp+"
		elif auto_pause_min_cost == 2:  auto_pause_min_cost = 4; tier_btn.text = "MIN: 4sp+"
		elif auto_pause_min_cost == 4:  auto_pause_min_cost = 8; tier_btn.text = "MIN: 8sp"
		else:                           auto_pause_min_cost = 1; tier_btn.text = "MIN: Any"
	)
	skill_panel.add_child(tier_btn)

	var ap_btn = Button.new();  ap_btn.text = "⏸ AUTO";  ap_btn.toggle_mode = true;  ap_btn.focus_mode = Control.FOCUS_NONE
	ap_btn.button_pressed = false;  ap_btn.modulate = Color.RED
	ap_btn.toggled.connect(func(pressed):
		auto_pause_enabled = pressed
		if pressed:  ap_btn.modulate = Color.GREEN; ap_dot.text = " ● ACTIVE";   ap_dot.modulate = Color.GREEN
		else:        ap_btn.modulate = Color.RED;   ap_dot.text = " ● INACTIVE"; ap_dot.modulate = Color.RED
	)
	skill_panel.add_child(ap_btn)

	for i in skill_names.size():
		skill_levels.append(0);  skill_kill_costs.append(1)

	for i in skill_names.size():
		var row := HBoxContainer.new()
		var name_lbl := Label.new();  name_lbl.text = skill_names[i];  name_lbl.custom_minimum_size = Vector2(130, 0)
		var bars_lbl := Label.new();  bars_lbl.text = "░░░░░";          bars_lbl.custom_minimum_size = Vector2(110, 0)
		var cost_lbl := Label.new();  cost_lbl.text = "(1sp)";          cost_lbl.custom_minimum_size = Vector2(40, 0)
		var min_btn := Button.new();  min_btn.text = "−";  min_btn.focus_mode = Control.FOCUS_NONE;  min_btn.process_mode = Node.PROCESS_MODE_ALWAYS
		min_btn.custom_minimum_size = Vector2(28, 0)
		var add_btn := Button.new();  add_btn.text = "+";  add_btn.focus_mode = Control.FOCUS_NONE;  add_btn.process_mode = Node.PROCESS_MODE_ALWAYS
		add_btn.custom_minimum_size = Vector2(28, 0)
		var idx := i
		min_btn.pressed.connect(func(): _on_skill_deselected(idx))
		add_btn.pressed.connect(func(): _on_skill_selected(idx))
		row.add_child(name_lbl);  row.add_child(bars_lbl);  row.add_child(cost_lbl)
		row.add_child(min_btn);   row.add_child(add_btn)
		skill_panel.add_child(row);  skill_rows.append(row)

	confirm_btn = Button.new();  confirm_btn.text = "CONFIRM UPGRADE";  confirm_btn.focus_mode = Control.FOCUS_NONE
	confirm_btn.pressed.connect(_on_confirm);  confirm_btn.process_mode = Node.PROCESS_MODE_ALWAYS
	skill_panel.add_child(confirm_btn)
	refresh_panel()

	var vp := get_viewport().get_visible_rect().size
	_skills_win   = _build_skills_window(vp)
	_tower_win    = _build_tower_window(vp)
	_placer_win   = _build_placer_window(vp)
	_powerups_win = _build_powerups_window(vp)
	_stats_win    = _build_stats_window(vp)
	_debug_panel   = _build_debug_panel(vp)
	_options_panel = _build_options_panel(vp)
	_build_sidebar(vp)
	call_deferred("_load_window_positions")
	call_deferred("_reflow_hud_labels")

# ═══════════════════════════════════════════════════════════════════════════════
# ─── WINDOW FACTORY ───────────────────────────────────════════════════════════
# ═══════════════════════════════════════════════════════════════════════════════
func _make_window(title_text: String, win_size: Vector2, start_pos: Vector2, title_color: Color) -> Array:
	const TITLE_H := 32

	var chrome := Panel.new()
	chrome.size = win_size;  chrome.position = start_pos;  chrome.visible = false
	chrome.process_mode = Node.PROCESS_MODE_ALWAYS
	var cs := StyleBoxFlat.new()
	cs.bg_color = Color(0.06, 0.07, 0.13, 1.0);  cs.border_color = Color(0.0, 0.7, 1.0, 0.8)
	cs.set_border_width_all(2);  cs.set_corner_radius_all(6)
	chrome.add_theme_stylebox_override("panel", cs);  add_child(chrome)

	# Title bar
	var tb := Panel.new()
	tb.position = Vector2(0, 0);  tb.size = Vector2(win_size.x, TITLE_H)
	tb.process_mode = Node.PROCESS_MODE_ALWAYS
	# MUST be STOP so it captures mouse events for dragging
	tb.mouse_filter = Control.MOUSE_FILTER_STOP
	var tbs := StyleBoxFlat.new()
	tbs.bg_color = Color(0.03, 0.06, 0.16, 1.0);  tbs.border_color = Color(0.0, 0.5, 0.9, 0.5)
	tbs.border_width_bottom = 1;  tbs.corner_radius_top_left = 5;  tbs.corner_radius_top_right = 5
	tb.add_theme_stylebox_override("panel", tbs);  chrome.add_child(tb)

	var title_lbl := Label.new();  title_lbl.text = title_text
	title_lbl.position = Vector2(10, 4);  title_lbl.size = Vector2(win_size.x - 50, TITLE_H - 8)
	title_lbl.add_theme_font_size_override("font_size", 15)
	title_lbl.add_theme_color_override("font_color", title_color)
	# Label must pass mouse through so title bar gets the events
	title_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tb.add_child(title_lbl)

	var close_btn := Button.new();  close_btn.text = "✕";  close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.size = Vector2(26, 22);  close_btn.position = Vector2(win_size.x - 30, 5)
	close_btn.process_mode = Node.PROCESS_MODE_ALWAYS
	close_btn.add_theme_color_override("font_color", Color(1.0, 0.35, 0.35))
	close_btn.add_theme_font_size_override("font_size", 13)
	close_btn.pressed.connect(func(): chrome.visible = false)
	tb.add_child(close_btn)

	# ── Drag — title bar detects start; _input at CanvasLayer handles motion ──
	# gui_input stops receiving motion when cursor leaves the panel,
	# so we only use it to detect the press and register _active_drag.
	tb.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_active_drag = {"panel": chrome, "offset": chrome.position - event.global_position}
			else:
				_active_drag = {}
	)

	# Body
	var body := Panel.new()
	body.position = Vector2(0, TITLE_H);  body.size = Vector2(win_size.x, win_size.y - TITLE_H)
	body.process_mode = Node.PROCESS_MODE_ALWAYS
	var bs := StyleBoxFlat.new()
	bs.bg_color = Color(0.05, 0.06, 0.12, 1.0);  bs.set_border_width_all(0)
	body.add_theme_stylebox_override("panel", bs);  chrome.add_child(body)

	return [chrome, body]

# ═══════════════════════════════════════════════════════════════════════════════
# ─── SKILLS WINDOW ────────────────────────────────────────────────────────────
# ═══════════════════════════════════════════════════════════════════════════════
func _build_skills_window(vp: Vector2) -> Panel:
	# Tall enough for all current skills + room for future skills
	var result := _make_window("⚡  SKILLS", Vector2(460, 680), Vector2(vp.x - 640, 40), Color(0.3, 0.9, 1.0))
	var chrome: Panel = result[0]
	var body: Panel   = result[1]

	# ScrollContainer so it never clips even with many skills
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(0, 0)
	scroll.size = Vector2(460, 680 - 32)   # body height
	scroll.process_mode = Node.PROCESS_MODE_ALWAYS
	body.add_child(scroll)

	# Reparent existing skill_panel VBox into scroll
	skill_panel.get_parent().remove_child(skill_panel)
	skill_panel.position = Vector2(8, 8)
	skill_panel.visible = true
	# Let VBox expand naturally inside scroll
	skill_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(skill_panel)

	return chrome

# ═══════════════════════════════════════════════════════════════════════════════
# ─── TOWER UPGRADES WINDOW ────────────────────────────────────────────────────
# ═══════════════════════════════════════════════════════════════════════════════
func _build_tower_window(vp: Vector2) -> Panel:
	var result := _make_window("🏰  TOWER UPGRADES", Vector2(340, 300), Vector2(vp.x - 560, 720), Color(1.0, 0.65, 0.2))
	var chrome: Panel = result[0]
	var body: Panel   = result[1]

	var upgrade_defs := [
		["⚔️  Turret Damage",   0],
		["🛡  Shield Strength", 1],
		["💎  Mine Yield",      2],
		["⚡  Fire Rate",       3],
	]

	for idx in range(upgrade_defs.size()):
		var row := HBoxContainer.new()
		row.position = Vector2(10, 8 + idx * 60)
		row.custom_minimum_size = Vector2(316, 52)
		# Name label
		var lbl := Label.new();  lbl.text = upgrade_defs[idx][0]
		lbl.custom_minimum_size = Vector2(170, 0)
		lbl.add_theme_font_size_override("font_size", 14)
		lbl.add_theme_color_override("font_color", Color(0.85, 0.85, 0.9))
		# Level label — named so we can update it
		var lvl_lbl := Label.new()
		lvl_lbl.name = "TowerUpgLvl" + str(idx)
		lvl_lbl.text = "LV: 0 / " + str(TOWER_UPGRADE_MAX)
		lvl_lbl.custom_minimum_size = Vector2(72, 0)
		lvl_lbl.add_theme_font_size_override("font_size", 13)
		lvl_lbl.add_theme_color_override("font_color", Color(0.4, 0.9, 1.0))
		# Cost label
		var cost_lbl := Label.new()
		cost_lbl.name = "TowerUpgCost" + str(idx)
		cost_lbl.text = str(TOWER_UPGRADE_COST) + "g"
		cost_lbl.custom_minimum_size = Vector2(36, 0)
		cost_lbl.add_theme_font_size_override("font_size", 12)
		cost_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
		# + button
		var up_btn := Button.new();  up_btn.text = "+";  up_btn.focus_mode = Control.FOCUS_NONE
		up_btn.custom_minimum_size = Vector2(30, 28)
		up_btn.process_mode = Node.PROCESS_MODE_ALWAYS
		up_btn.add_theme_color_override("font_color", Color(0.4, 1.0, 0.5))
		var slot: int = upgrade_defs[idx][1]
		up_btn.pressed.connect(func(): _on_tower_upgrade(slot))
		row.add_child(lbl);  row.add_child(lvl_lbl)
		row.add_child(cost_lbl);  row.add_child(up_btn)
		body.add_child(row)

	return chrome

# ── Tower upgrade logic ───────────────────────────────────────────────────────
func _on_tower_upgrade(slot: int) -> void:
	if tower_upgrade_levels[slot] >= TOWER_UPGRADE_MAX:
		return
	if gold < TOWER_UPGRADE_COST:
		return
	gold -= TOWER_UPGRADE_COST
	gold_label.text = "Gold: " + str(gold)
	tower_upgrade_levels[slot] += 1
	_apply_tower_upgrade(slot)
	_refresh_tower_upgrade_labels()

func _apply_tower_upgrade(slot: int) -> void:
	var lvl: int = tower_upgrade_levels[slot]
	var nm = get_parent().get_node_or_null("NodeManager")
	match slot:
		0:  # Turret Damage — +0.5 per level, applied via nm var
			if nm != null: nm.turret_damage = 1.0 + lvl * 0.5
		1:  # Shield Strength — increases shield node HP pool (future use) — sets meta
			if nm != null: nm.shield_strength = 1.0 + lvl * 0.4
		2:  # Mine Yield — +5 gold per level per tick
			if nm != null: nm.mine_gold_per_tick = 10 + lvl * 5
		3:  # Fire Rate — reduces turret_fire_rate by 0.15 per level
			if nm != null: nm.turret_fire_rate = maxf(0.3, 1.5 - lvl * 0.2)

func _refresh_tower_upgrade_labels() -> void:
	if _tower_win == null:
		return
	var body: Panel = _tower_win.get_child(1)
	for slot in range(4):
		var lvl_lbl = body.find_child("TowerUpgLvl" + str(slot), true, false)
		var cost_lbl = body.find_child("TowerUpgCost" + str(slot), true, false)
		if lvl_lbl != null:
			var lv: int = tower_upgrade_levels[slot]
			if is_instance_valid(lvl_lbl):
				(lvl_lbl as Label).text = "LV: " + str(lv) + " / " + str(TOWER_UPGRADE_MAX)
				(lvl_lbl as Label).modulate = Color.YELLOW if lv >= TOWER_UPGRADE_MAX else Color.WHITE
		if cost_lbl != null and is_instance_valid(cost_lbl):
			var lv: int = tower_upgrade_levels[slot]
			(cost_lbl as Label).text = "MAX" if lv >= TOWER_UPGRADE_MAX else str(TOWER_UPGRADE_COST) + "g"
			(cost_lbl as Label).modulate = Color.GRAY if lv >= TOWER_UPGRADE_MAX else Color(1.0, 0.85, 0.3)

# ═══════════════════════════════════════════════════════════════════════════════
# ─── NODE PLACER WINDOW ───────────────────────────────────────────────────────
# ═══════════════════════════════════════════════════════════════════════════════
func _build_placer_window(vp: Vector2) -> Panel:
	var result := _make_window("🔧  NODE PLACER", Vector2(340, 200), Vector2(vp.x - 560, 1020), Color(0.5, 1.0, 0.5))
	var chrome: Panel = result[0]
	var body: Panel   = result[1]

	var note := Label.new();  note.text = "Place nodes on adjacent hexes during cooldown."
	note.position = Vector2(10, 8);  note.size = Vector2(316, 36)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size", 13);  note.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8))
	body.add_child(note)

	# Crystal counter
	var crystal_lbl := Label.new()
	crystal_lbl.name = "PlacerCrystalLbl"
	crystal_lbl.text = "💎 Crystals: 0"
	crystal_lbl.position = Vector2(10, 48);  crystal_lbl.size = Vector2(316, 24)
	crystal_lbl.add_theme_font_size_override("font_size", 15)
	crystal_lbl.add_theme_color_override("font_color", Color(0.5, 0.9, 1.0))
	body.add_child(crystal_lbl)

	var btn_defs := [
		["⚔️  Turret",       "turret",       Color(1.0, 0.4,  0.3 )],
		["🛡  Shield",        "shield",       Color(0.3, 0.6,  1.0 )],
		["💎  Mine",          "mine",         Color(0.3, 1.0,  0.85)],
		["💠  Crystal Mine",  "crystal_mine", Color(0.4, 0.75, 1.0 )],
	]
	for i in range(btn_defs.size()):
		var col: int  = i % 2
		var row: int  = i / 2
		var bx: float = 10.0 + col * 160.0
		var by: float = 80.0 + row * 56.0
		var pb := Button.new()
		pb.text         = btn_defs[i][0]
		pb.focus_mode   = Control.FOCUS_NONE
		pb.size         = Vector2(148, 34)
		pb.position     = Vector2(bx, by)
		pb.process_mode = Node.PROCESS_MODE_ALWAYS
		pb.add_theme_color_override("font_color", btn_defs[i][2])
		pb.add_theme_font_size_override("font_size", 13)
		var t: String = btn_defs[i][1];  pb.pressed.connect(func(): selected_node_type = t)
		body.add_child(pb)
		var cost_lbl := Label.new()
		cost_lbl.name     = "CostLbl_" + t
		cost_lbl.position = Vector2(bx, by + 36)
		cost_lbl.size     = Vector2(148, 18)
		cost_lbl.add_theme_font_size_override("font_size", 11)
		cost_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8))
		cost_lbl.text = "75 Gold" if t == "crystal_mine" else "Cost: 💎?"
		body.add_child(cost_lbl)

	return chrome

# ═══════════════════════════════════════════════════════════════════════════════
# ─── POWER-UPS GALLERY WINDOW ─────────────────────────────────────────────────
# ═══════════════════════════════════════════════════════════════════════════════
# ── Power-up pool — all slots, same order as powerup_data.gd POOL ────────────
const PU_SLOTS: Array = [
	["GoldyLox",    "✦", "4488ff"], ["FURY",        "⚡", "4488ff"], ["Lightfoot",  "◈", "4488ff"],
	["T-Radar",     "◉", "4488ff"], ["Recycler",    "♻", "4488ff"], ["Phoenix Egg","❋", "4488ff"],
	["Armor",       "⬡", "4488ff"],
	["Cryo Rounds", "❄", "44cc88"], ["Chain Shot",  "⇒", "44cc88"], ["Fortify",   "▲", "44cc88"],
	["Rapid Reload","⟳", "44cc88"], ["Ghost Turret","☆", "44cc88"],
	["Overclock",   "⚙", "ffaa22"], ["Iron Skin",   "⬟", "ffaa22"], ["Fool's Gold","$", "ffaa22"],
	["Berserker",   "⚔", "ffaa22"], ["Exposed",     "◎", "ffaa22"], ["Glass Cannon","◇","ffaa22"],
	["Death Pact",  "☠", "ff3333"], ["Blood Price", "♥", "ff3333"], ["Enemy Pact",  "☯","ff3333"],
	["Void Carry",  "◆", "ff3333"], ["FCR Mod",     "≫", "ff3333"], ["Copycat",    "⋈", "ff3333"],
]

func _build_powerups_window(vp: Vector2) -> Panel:
	var result := _make_window("🎁  POWER-UPS", Vector2(520, 560), Vector2(vp.x - 720, 40), Color(1.0, 0.5, 1.0))
	var chrome: Panel = result[0]
	var body: Panel   = result[1]

	# Scroll container
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(0, 0);  scroll.size = Vector2(520, 528)
	scroll.process_mode = Node.PROCESS_MODE_ALWAYS
	body.add_child(scroll)

	var inner := Control.new()
	inner.name = "GalleryInner"
	inner.custom_minimum_size = Vector2(500, 0)
	scroll.add_child(inner)

	# Pre-draw all hex slots — staggered honeycomb layout
	var cols := 5
	var slot_w := 82.0;  var slot_h := 88.0
	var gap_x  := 4.0;   var gap_y  := -14.0   # negative gap pulls rows together like real hex grid
	var pad_x  := 12.0;  var pad_y  := 12.0
	for i in PU_SLOTS.size():
		var col: int = i % cols
		var row: int = i / cols
		# Odd rows offset right by half a slot width — classic hex stagger
		var stagger: float = (slot_w + gap_x) * 0.5 if row % 2 == 1 else 0.0
		var sx: float = pad_x + stagger + col * (slot_w + gap_x)
		var sy: float = pad_y + row * (slot_h + gap_y)
		var slot := _make_pu_hex_slot(PU_SLOTS[i][0], PU_SLOTS[i][1], Color("#" + PU_SLOTS[i][2]), Vector2(sx, sy), false)
		slot.name = "Slot_" + str(i)
		inner.add_child(slot)
	var row_count: int = int(ceil(float(PU_SLOTS.size()) / cols))
	inner.custom_minimum_size = Vector2(520, pad_y + row_count * (slot_h + gap_y) + slot_h + pad_y)

	return chrome

func _make_pu_hex_slot(pu_name: String, symbol: String, col: Color, pos: Vector2, unlocked: bool) -> Control:
	var slot := Control.new()
	slot.position = pos
	slot.custom_minimum_size = Vector2(78, 90)

	# Hex shape polygon
	var hex := Polygon2D.new()
	var pts := PackedVector2Array()
	var cx := 39.0;  var cy := 40.0;  var hr := 34.0
	for j in 6:
		var a: float = deg_to_rad(60.0 * j - 30.0)
		pts.append(Vector2(cx + cos(a) * hr, cy + sin(a) * hr))
	hex.polygon = pts
	if unlocked:
		hex.color = Color(col.r * 0.18, col.g * 0.18, col.b * 0.18, 1.0)
	else:
		hex.color = Color(0.08, 0.08, 0.12, 1.0)
	slot.add_child(hex)

	# Hex border
	var border := Line2D.new()
	border.points = pts
	border.closed = true
	border.width = 1.5
	border.default_color = col if unlocked else Color(0.2, 0.2, 0.28, 1.0)
	slot.add_child(border)

	# Symbol
	var sym_lbl := Label.new()
	sym_lbl.text = symbol
	sym_lbl.position = Vector2(0, 18);  sym_lbl.size = Vector2(78, 32)
	sym_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sym_lbl.add_theme_font_size_override("font_size", 22)
	sym_lbl.add_theme_color_override("font_color", col if unlocked else Color(0.25, 0.25, 0.32))
	slot.add_child(sym_lbl)

	# Name
	var name_lbl := Label.new()
	name_lbl.text = pu_name if unlocked else "???"
	name_lbl.position = Vector2(0, 52);  name_lbl.size = Vector2(78, 32)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_lbl.add_theme_font_size_override("font_size", 9)
	name_lbl.add_theme_color_override("font_color", col if unlocked else Color(0.3, 0.3, 0.38))
	slot.add_child(name_lbl)

	return slot

func add_powerup_to_gallery(pu_name: String, _pu_icon: String, _pu_desc: String, pu_color: Color) -> void:
	if _powerups_win == null:
		return
	# Find slot index by name and light it up
	var slot_idx: int = -1
	for i in PU_SLOTS.size():
		if PU_SLOTS[i][0] == pu_name:
			slot_idx = i
			break
	if slot_idx == -1:
		return   # unknown power-up — skip
	var body := _powerups_win.get_child(1)
	var scroll: ScrollContainer = body.get_child(0)
	var inner: Control = scroll.get_child(0)
	var old_slot: Control = inner.get_node_or_null("Slot_" + str(slot_idx))
	if old_slot == null:
		return
	# Replace with unlocked version in same position
	var col: Color = Color("#" + PU_SLOTS[slot_idx][2])
	var new_slot := _make_pu_hex_slot(pu_name, PU_SLOTS[slot_idx][1], col, old_slot.position, true)
	new_slot.name = "Slot_" + str(slot_idx)
	var pos: Vector2 = old_slot.position
	old_slot.queue_free()
	new_slot.position = pos
	inner.add_child(new_slot)
	collected_powerups.append({"name": pu_name})

# ═══════════════════════════════════════════════════════════════════════════════
# ─── STATISTICS WINDOW ────────────────────────────────────────────────────────
# ═══════════════════════════════════════════════════════════════════════════════
func _build_stats_window(vp: Vector2) -> Panel:
	var result := _make_window("📊  STATISTICS", Vector2(360, 420), Vector2(vp.x - 700, 580), Color(0.4, 1.0, 0.8))
	var chrome: Panel = result[0]
	var body: Panel   = result[1]

	var stat_defs := [
		["🌊  Waves Survived",   "stat_waves_survived",  "0"],
		["💀  Total Kills",      "kill_count",           "0"],
		["🔫  Shots Fired",      "stat_shots_fired",     "0"],
		["💥  Damage Taken",     "stat_damage_taken",    "0"],
		["👑  Bosses Defeated",  "stat_bosses_killed",   "0"],
		["🧱  Nodes Placed",     "stat_nodes_placed",    "0"],
		["💰  Gold Earned",      "gold",                 "0"],
		["⚡  Skill Points Used","sp_spent",             "0"],
	]
	for i in range(stat_defs.size()):
		var row := HBoxContainer.new()
		row.position = Vector2(12, 10 + i * 46);  row.custom_minimum_size = Vector2(330, 38)

		var lbl := Label.new();  lbl.text = stat_defs[i][0];  lbl.custom_minimum_size = Vector2(220, 0)
		lbl.add_theme_font_size_override("font_size", 15);  lbl.add_theme_color_override("font_color", Color(0.8, 0.8, 0.9))

		var val_lbl := Label.new();  val_lbl.text = stat_defs[i][2];  val_lbl.custom_minimum_size = Vector2(80, 0)
		val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		val_lbl.add_theme_font_size_override("font_size", 15);  val_lbl.add_theme_color_override("font_color", Color(0.4, 1.0, 0.8))

		_stats_labels[stat_defs[i][1]] = val_lbl
		row.add_child(lbl);  row.add_child(val_lbl);  body.add_child(row)

	return chrome

# Call this any time a stat changes to refresh the window
func _refresh_stats() -> void:
	if _stats_labels.is_empty():
		return
	var updates := {
		"stat_waves_survived": str(stat_waves_survived),
		"kill_count":          str(kill_count),
		"stat_shots_fired":    str(stat_shots_fired),
		"stat_damage_taken":   str(int(stat_damage_taken)),
		"stat_bosses_killed":  str(stat_bosses_killed),
		"stat_nodes_placed":   str(stat_nodes_placed),
		"gold":                str(gold),
		"sp_spent":            str(_sp_spent),
	}
	for key in updates:
		if _stats_labels.has(key):
			(_stats_labels[key] as Label).text = updates[key]

var _sp_spent := 0

# ═══════════════════════════════════════════════════════════════════════════════
# ─── SIDEBAR ──────────────────────────────────────────────────────────────────
# ═══════════════════════════════════════════════════════════════════════════════
# ── Font scale — applies to all major HUD labels ──────────────────────────────
# ── Font scale ────────────────────────────────────────────────────────────────
func _apply_font_scale() -> void:
	var labels := {
		"gold":      [gold_label,          18],
		"kills":     [kill_label,          18],
		"crystals":  [node_label,          18],
		"sp":        [sp_label,            18],
		"wave":      [wave_label,          18],
		"health":    [health_label,        16],
		"boss_in":   [boss_label,          14],
		"bt":        [bt_label,            14],
		"tower":     [tower_label,         14],
		"art_carry": [_artifact_carry_label,  18],
		"art_reveal":[_artifact_reveal_label, 26],
		"milestone": [_milestone_label,       24],
		"pause":     [pause_label,         24],
		"cooldown":  [cooldown_label,      22],
		"boss_name": [boss_hp_label,       16],
	}
	for k in labels:
		var lbl = labels[k][0]
		var base: int = labels[k][1]
		if lbl != null and is_instance_valid(lbl):
			(lbl as Label).add_theme_font_size_override("font_size", int(base * _font_scale))
	_reflow_hud_labels()
	var cfg := ConfigFile.new()
	cfg.load(WIN_POS_FILE)
	cfg.set_value("display", "font_scale", _font_scale)
	cfg.save(WIN_POS_FILE)

func _reflow_hud_labels() -> void:
	# All left-column positions computed from font scale
	var big_h:   float = 24.0 * _font_scale   # row height for big labels (18pt base)
	var small_h: float = 18.0 * _font_scale   # row height for small labels (14pt base)
	var bar_h:   float = 14.0 * _font_scale
	var bar_w:   float = 200.0 * _font_scale
	var x: float = 20.0
	var y: float = 20.0
	# Big stats
	for lbl in [gold_label, node_label, kill_label, sp_label]:
		if lbl != null and is_instance_valid(lbl):
			(lbl as Label).position = Vector2(x, y);  y += big_h
	# Health label
	if health_label != null and is_instance_valid(health_label):
		health_label.position = Vector2(x, y);  y += small_h
	# HP bar
	if hp_bar_bg != null:
		hp_bar_bg.position = Vector2(x, y);  hp_bar_bg.size = Vector2(bar_w, bar_h)
	if hp_bar_fill != null:
		hp_bar_fill.position = Vector2(x, y)
		var ratio: float = hp_bar_fill.size.x / maxf(hp_bar_bg.size.x, 1.0) if hp_bar_bg != null else 1.0
		hp_bar_fill.size = Vector2(bar_w * ratio, bar_h)
	y += bar_h + 6.0
	# Wave + lower labels
	for lbl in [wave_label, boss_label, bt_label, tower_label]:
		if lbl != null and is_instance_valid(lbl):
			(lbl as Label).position = Vector2(x, y);  y += small_h
	if pause_label != null and is_instance_valid(pause_label):
		pause_label.position = Vector2(x, y)

# ── Window position persistence ───────────────────────────────────────────────
func _save_window_positions() -> void:
	var cfg := ConfigFile.new()
	var wins := {"skills": _skills_win, "tower": _tower_win, "placer": _placer_win,
		"powerups": _powerups_win, "stats": _stats_win, "debug": _debug_panel, "options": _options_panel}
	for key in wins:
		if wins[key] != null and is_instance_valid(wins[key]):
			cfg.set_value("positions", key + "_x", wins[key].position.x)
			cfg.set_value("positions", key + "_y", wins[key].position.y)
	cfg.save(WIN_POS_FILE)

func _load_window_positions() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(WIN_POS_FILE) != OK:
		return
	_font_scale = cfg.get_value("display", "font_scale", 2.0)
	call_deferred("_apply_font_scale")
	var wins := {"skills": _skills_win, "tower": _tower_win, "placer": _placer_win,
		"powerups": _powerups_win, "stats": _stats_win, "debug": _debug_panel, "options": _options_panel}
	for key in wins:
		if wins[key] != null and is_instance_valid(wins[key]):
			var x: float = cfg.get_value("positions", key + "_x", wins[key].position.x)
			var y: float = cfg.get_value("positions", key + "_y", wins[key].position.y)
			wins[key].position = Vector2(x, y)

func _build_sidebar(vp: Vector2) -> void:
	const BAR_W := 160
	var bar := Panel.new()
	bar.size = Vector2(BAR_W, vp.y);  bar.position = Vector2(vp.x - BAR_W, 0)
	bar.process_mode = Node.PROCESS_MODE_ALWAYS
	var sty := StyleBoxFlat.new()
	sty.bg_color = Color(0.05, 0.05, 0.10, 1.0);  sty.border_color = Color(0.0, 0.7, 1.0, 0.7)
	sty.set_border_width_all(0);  sty.border_width_left = 2
	bar.add_theme_stylebox_override("panel", sty);  add_child(bar)

	var bsn := StyleBoxFlat.new();  bsn.bg_color = Color(0.10,0.14,0.24,1.0)
	bsn.border_color = Color(0.0,0.65,1.0,0.6);  bsn.set_border_width_all(1);  bsn.set_corner_radius_all(5)
	var bsh := StyleBoxFlat.new();  bsh.bg_color = Color(0.15,0.25,0.42,1.0)
	bsh.border_color = Color(0.0,0.9,1.0,0.9);   bsh.set_border_width_all(1);  bsh.set_corner_radius_all(5)
	var bsp := StyleBoxFlat.new();  bsp.bg_color = Color(0.0,0.35,0.65,1.0)
	bsp.border_color = Color(0.0,1.0,1.0,1.0);   bsp.set_border_width_all(2);  bsp.set_corner_radius_all(5)

	var bx := vp.x - BAR_W + 10;  var bw := BAR_W - 20

	var title_lbl := Label.new();  title_lbl.text = "VEXAGON"
	title_lbl.position = Vector2(bx, 14);  title_lbl.size = Vector2(bw, 28)
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_size_override("font_size", 18)
	title_lbl.add_theme_color_override("font_color", Color(0.0, 0.85, 1.0));  add_child(title_lbl)

	var div := ColorRect.new();  div.position = Vector2(bx, 48);  div.size = Vector2(bw, 1)
	div.color = Color(0.0, 0.7, 1.0, 0.4);  add_child(div)

	var _mk := func(lbl: String, y: float, col: Color, tog: bool) -> Button:
		var b := Button.new();  b.text = lbl;  b.toggle_mode = tog
		b.focus_mode = Control.FOCUS_NONE
		b.size = Vector2(bw, 42);  b.position = Vector2(bx, y);  b.process_mode = Node.PROCESS_MODE_ALWAYS
		b.add_theme_stylebox_override("normal", bsn);  b.add_theme_stylebox_override("hover", bsh);  b.add_theme_stylebox_override("pressed", bsp)
		b.add_theme_color_override("font_color", col);  b.add_theme_font_size_override("font_size", 14)
		add_child(b);  return b

	var skills_btn: Button = _mk.call("⚡  SKILLS",    60,  Color(0.4, 0.9, 1.0), true)
	skills_btn.toggled.connect(func(on: bool): _skills_win.visible = on)

	var tower_btn: Button = _mk.call("🏰  TOWER",     114, Color(1.0, 0.65, 0.2), true)
	tower_btn.toggled.connect(func(on: bool): _tower_win.visible = on)

	var placer_btn: Button = _mk.call("🔧  PLACER",   168, Color(0.5, 1.0, 0.5), true)
	placer_btn.toggled.connect(func(on: bool): _placer_win.visible = on)

	var pu_btn: Button = _mk.call("🎁  POWER-UPS", 222, Color(1.0, 0.5, 1.0), true)
	pu_btn.toggled.connect(func(on: bool): _powerups_win.visible = on)

	var st_btn: Button = _mk.call("📊  STATS",     276, Color(0.4, 1.0, 0.8), true)
	st_btn.toggled.connect(func(on: bool):
		if on: _refresh_stats()
		_stats_win.visible = on
	)

	var exit_btn: Button = _mk.call("✕  EXIT", vp.y - 54, Color(1.0, 0.3, 0.3), false)
	exit_btn.pressed.connect(func(): Engine.time_scale = 1.0; get_tree().quit())

# ─── REFRESH PANEL ────────────────────────────────────────────────────────────
func refresh_panel() -> void:
	sp_label.text = "Skill Points: " + str(skill_points)
	# Tally total queued SP cost so we can show remaining budget
	var queued_sp := 0
	for q in pending_queue: queued_sp += skill_kill_costs[q]
	for i in skill_names.size():
		var row: HBoxContainer = skill_rows[i]
		var bars: Label = row.get_child(1);  var cost: Label = row.get_child(2)
		var pc := _pending_count(i)          # how many of this skill are queued
		var effective_lv: int = (skill_levels[i] as int) + pc
		var dl: int = min(skill_levels[i], 5)
		var bar_str := "█".repeat(dl) + "░".repeat(5 - dl) + " LV:" + str(skill_levels[i])
		if pc > 0:
			bar_str += " [+" + str(pc) + "]"
		bars.text = bar_str
		cost.text = "(" + str(skill_kill_costs[i]) + "sp)"
		if pc > 0:                                                                         row.modulate = Color.YELLOW
		elif skill_points - queued_sp >= skill_kill_costs[i] and effective_lv < 10:        row.modulate = Color(0.5, 1.0, 0.5)
		else:                                                                              row.modulate = Color.WHITE

# ─── ECONOMY ──────────────────────────────────────────────────────────────────
func add_gold(amount: int) -> void:
	gold += amount;  gold_label.text = "Gold: " + str(gold)

func add_node_fragment(amount: int) -> void:
	node_fragments += amount
	node_label.text = "Crystals: " + str(node_fragments)
	# Also update placer window crystal label
	if _placer_win != null and is_instance_valid(_placer_win):
		var lbl = _placer_win.get_child(1).get_node_or_null("PlacerCrystalLbl")
		if lbl != null: (lbl as Label).text = "💎 Crystals: " + str(node_fragments)

func add_kill() -> void:
	kill_count += 1;  kill_label.text = "Kills: " + str(kill_count)
	if kill_count > 0 and kill_count % 5 == 0:
		skill_points += 1;  sp_progress_label.text = "⚡ █████  → +1 SP!"
		call_deferred("refresh_panel")
		if auto_pause_enabled: _check_auto_pause()
	else:
		var k := kill_count % 5
		sp_progress_label.text = "⚡ " + "█".repeat(k) + "░".repeat(5 - k) + "  (" + str(k) + " / 5)"

# ─── SKILL PANEL ──────────────────────────────────────────────────────────────
# ─── PENDING QUEUE HELPERS ───────────────────────────────────────────────────
func _pending_count(index: int) -> int:
	var c: int = 0
	for q in pending_queue:
		if q == index:
			c += 1
	return c

func _on_skill_selected(index: int) -> void:
	# Hard cap: combined current + queued must stay below 10
	if skill_levels[index] + _pending_count(index) >= 10: return
	var qc := 0;  for q in pending_queue: qc += skill_kill_costs[q]
	if skill_points >= qc + skill_kill_costs[index]:
		pending_queue.append(index);  call_deferred("refresh_panel")

func _on_skill_deselected(index: int) -> void:
	# Remove one instance of this skill from the pending queue
	var pos := pending_queue.rfind(index)
	if pos != -1:
		pending_queue.remove_at(pos);  call_deferred("refresh_panel")

func _on_confirm() -> void:
	if pending_queue.is_empty(): return
	for index in pending_queue:
		if skill_points < skill_kill_costs[index]: break
		skill_points -= skill_kill_costs[index];  _sp_spent += skill_kill_costs[index]
		skill_levels[index] += 1
		var lvl: int = skill_levels[index]
		if lvl < 4:    skill_kill_costs[index] = 1
		elif lvl < 7:  skill_kill_costs[index] = 2
		elif lvl < 10: skill_kill_costs[index] = 4
		else:          skill_kill_costs[index] = 8
	pending_queue.clear()
	var _sk_player = get_parent().get_node_or_null("Player")
	if _sk_player != null:
		var new_max: float = _sk_player.get_max_hp()
		if _sk_player.max_hp != new_max:
			_sk_player.max_hp = new_max
			_sk_player.current_hp = minf(_sk_player.current_hp, new_max)
			update_health(_sk_player.current_hp, _sk_player.max_hp)
	call_deferred("refresh_panel")
	if auto_pause_enabled and not _can_afford_any(): get_tree().paused = false

# ─── PROCESS ──────────────────────────────────────────────────────────────────
func _process(delta: float) -> void:
	var gm_lvl = skill_levels[10]
	if gm_lvl >= 4:
		passive_timer += delta
		if passive_timer >= 1.0: passive_timer = 0.0; add_gold(gm_lvl - 3)

func _input(event: InputEvent) -> void:
	# ── Global drag handler for all windows ──────────────────────────────────
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		if not _active_drag.is_empty(): _save_window_positions()
		_active_drag = {}
	if event is InputEventMouseMotion and not _active_drag.is_empty():
		(_active_drag["panel"] as Panel).position = event.global_position + _active_drag["offset"]
		return
	if not event is InputEventKey or not event.pressed: return
	var go := game_over_panel != null and is_instance_valid(game_over_panel)
	var wi := win_panel != null and is_instance_valid(win_panel)
	# NG+ intercept — must check before the generic reload handler
	if wi and event.keycode == KEY_N:
		_start_ng_plus();  return
	if go or wi:
		Engine.time_scale = 1.0;  get_tree().paused = false;  get_tree().reload_current_scene();  return
	if event.keycode == KEY_ESCAPE:
		if _powerup_panel != null and is_instance_valid(_powerup_panel):
			_dismiss_powerup_panel();  return
		# Toggle escape menu
		if _escape_panel != null and is_instance_valid(_escape_panel):
			_close_escape_menu()
		else:
			_open_escape_menu()
		return
	# KEY_TAB reserved for Inventory (future)
	if event.keycode == KEY_G:
		if _debug_panel != null: _debug_panel.visible = !_debug_panel.visible
	if event.keycode == KEY_O:
		if _options_panel != null: _options_panel.visible = !_options_panel.visible
	if event.keycode == KEY_F:
		skill_points += 50;  call_deferred("refresh_panel")

# ─── Escape Menu ──────────────────────────────────────────────────────────────
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE or what == NOTIFICATION_WM_CLOSE_REQUEST:
		if _rainbow_tween != null and _rainbow_tween.is_valid():
			_rainbow_tween.kill()


func _open_escape_menu() -> void:
	if _escape_panel != null and is_instance_valid(_escape_panel): return
	Engine.time_scale = 0.0   # freeze gameplay, keep rendering alive
	var vp := get_viewport().get_visible_rect().size
	const PW := 380.0;  const PAD := 24.0;  const BW := 332.0;  const BH := 52.0
	var panel := Panel.new()
	panel.size = Vector2(PW, 340)
	panel.position = Vector2(vp.x/2.0 - PW/2.0, vp.y/2.0 - 170.0)
	panel.z_index = 30;  panel.process_mode = Node.PROCESS_MODE_ALWAYS
	var sty := StyleBoxFlat.new()
	sty.bg_color = Color(0.04, 0.04, 0.08, 0.98)
	sty.border_color = Color(0.25, 0.28, 0.38);  sty.set_border_width_all(2);  sty.set_corner_radius_all(10)
	panel.add_theme_stylebox_override("panel", sty)
	add_child(panel)
	_escape_panel = panel
	# Backdrop
	var bd := ColorRect.new()
	bd.color = Color(0,0,0,0.6);  bd.size = vp;  bd.position = Vector2.ZERO
	bd.z_index = 29;  bd.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bd.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(bd);  panel.set_meta("bd", bd)
	# Title
	var title := Label.new();  title.text = "PAUSED"
	title.position = Vector2(PAD, 16);  title.size = Vector2(BW, 32)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.7, 0.75, 0.9))
	panel.add_child(title)
	# Helper — styled button
	var _mk := func(label: String, y: float, col: Color) -> Button:
		var b := Button.new();  b.text = label
		b.size = Vector2(BW, BH);  b.position = Vector2(PAD, y)
		b.focus_mode = Control.FOCUS_NONE;  b.process_mode = Node.PROCESS_MODE_ALWAYS
		var bs := StyleBoxFlat.new()
		bs.bg_color = Color(col.r*0.12, col.g*0.12, col.b*0.12, 1.0)
		bs.border_color = col;  bs.set_border_width_all(1);  bs.set_corner_radius_all(6)
		b.add_theme_stylebox_override("normal", bs)
		b.add_theme_color_override("font_color", col)
		b.add_theme_font_size_override("font_size", 15)
		panel.add_child(b);  return b
	# ── RESUME (no confirm needed) ───────────────────────────────────────────
	var resume_btn: Button = _mk.call("▶  RESUME", 60, Color(0.3, 1.0, 0.55))
	resume_btn.pressed.connect(_close_escape_menu)
	# ── RESTART FROM CHECKPOINT ──────────────────────────────────────────────
	var has_cp: bool = not _checkpoint.is_empty()
	var cp_btn: Button = _mk.call("↩  RESTART FROM CHECKPOINT", 124,
		Color(0.4, 0.75, 1.0) if has_cp else Color(0.3, 0.3, 0.4))
	if not has_cp:
		cp_btn.disabled = true
		cp_btn.modulate.a = 0.45
	else:
		cp_btn.pressed.connect(func():
			_confirm_action("Restart from last checkpoint?
All progress since then will be lost.",
				func():
					_close_escape_menu()
					restore_checkpoint()
			)
		)
	# ── RESTART GAME ─────────────────────────────────────────────────────────
	var restart_btn: Button = _mk.call("↺  RESTART GAME", 188, Color(1.0, 0.6, 0.2))
	restart_btn.pressed.connect(func():
		_confirm_action("Restart the entire run?
All progress will be lost.",
			func():
				_close_escape_menu()
				Engine.time_scale = 1.0
				get_tree().paused = false
				get_tree().reload_current_scene()
		)
	)
	# ── QUIT ─────────────────────────────────────────────────────────────────
	var quit_btn: Button = _mk.call("✕  QUIT TO DESKTOP", 252, Color(1.0, 0.3, 0.3))
	quit_btn.pressed.connect(func():
		_confirm_action("Quit to desktop?
Unsaved progress will be lost.",
			func():
				Engine.time_scale = 1.0
				get_tree().quit()
		)
	)
	# Show instantly — time_scale=0.0 makes tweens unusable here
	panel.modulate.a = 1.0

func _close_escape_menu() -> void:
	if _escape_panel == null or not is_instance_valid(_escape_panel): return
	var panel = _escape_panel;  _escape_panel = null
	if panel.has_meta("bd"):
		var bd = panel.get_meta("bd")
		if is_instance_valid(bd): (bd as Node).queue_free()
	# Free instantly and restore time
	if is_instance_valid(panel): panel.queue_free()
	Engine.time_scale = 1.0

func _confirm_action(msg: String, on_confirm: Callable) -> void:
	# Small confirm dialog on top of escape menu
	var vp := get_viewport().get_visible_rect().size
	const CW := 340.0;  const PAD := 20.0
	var dlg := Panel.new()
	dlg.size = Vector2(CW, 160);  dlg.z_index = 35
	dlg.position = Vector2(vp.x/2.0 - CW/2.0, vp.y/2.0 - 80.0)
	dlg.process_mode = Node.PROCESS_MODE_ALWAYS
	var ds := StyleBoxFlat.new()
	ds.bg_color = Color(0.06, 0.05, 0.10, 0.99)
	ds.border_color = Color(0.6, 0.3, 0.9);  ds.set_border_width_all(2);  ds.set_corner_radius_all(8)
	dlg.add_theme_stylebox_override("panel", ds)
	add_child(dlg)
	# Message
	var lbl := Label.new();  lbl.text = msg
	lbl.position = Vector2(PAD, 14);  lbl.size = Vector2(CW - PAD*2, 70)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", Color(0.88, 0.88, 0.95))
	dlg.add_child(lbl)
	# Buttons
	var half := (CW - PAD*2 - 10.0) / 2.0
	var yes_btn := Button.new();  yes_btn.text = "YES, DO IT"
	yes_btn.size = Vector2(half, 38);  yes_btn.position = Vector2(PAD, 104)
	yes_btn.focus_mode = Control.FOCUS_NONE;  yes_btn.process_mode = Node.PROCESS_MODE_ALWAYS
	var ybs := StyleBoxFlat.new()
	ybs.bg_color = Color(0.35, 0.08, 0.08);  ybs.border_color = Color(1.0, 0.3, 0.3)
	ybs.set_border_width_all(1);  ybs.set_corner_radius_all(5)
	yes_btn.add_theme_stylebox_override("normal", ybs)
	yes_btn.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
	yes_btn.add_theme_font_size_override("font_size", 13)
	yes_btn.pressed.connect(func(): dlg.queue_free(); on_confirm.call())
	dlg.add_child(yes_btn)
	var no_btn := Button.new();  no_btn.text = "CANCEL"
	no_btn.size = Vector2(half, 38);  no_btn.position = Vector2(PAD + half + 10.0, 104)
	no_btn.focus_mode = Control.FOCUS_NONE;  no_btn.process_mode = Node.PROCESS_MODE_ALWAYS
	var nbs := StyleBoxFlat.new()
	nbs.bg_color = Color(0.08, 0.12, 0.22);  nbs.border_color = Color(0.35, 0.45, 0.7)
	nbs.set_border_width_all(1);  nbs.set_corner_radius_all(5)
	no_btn.add_theme_stylebox_override("normal", nbs)
	no_btn.add_theme_color_override("font_color", Color(0.5, 0.65, 1.0))
	no_btn.add_theme_font_size_override("font_size", 13)
	no_btn.pressed.connect(dlg.queue_free)
	dlg.add_child(no_btn)
	# Show instantly
	dlg.scale = Vector2(1.0, 1.0);  dlg.modulate.a = 1.0


func _build_options_panel(vp: Vector2) -> Panel:
	const PW := 500.0;  const PAD := 18.0;  const BW := 464.0
	var y := 14.0

	var panel := Panel.new()
	panel.position = Vector2(vp.x / 2.0 - PW / 2.0, vp.y / 2.0 - 200.0)
	panel.visible  = false
	panel.process_mode = Node.PROCESS_MODE_ALWAYS
	var sty := StyleBoxFlat.new()
	sty.bg_color     = Color(0.04, 0.05, 0.08, 0.97)
	sty.border_color = Color(0.3, 0.5, 0.9, 0.85)
	sty.set_border_width_all(2);  sty.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", sty)
	add_child(panel)

	# Title
	var title := Label.new();  title.text = "⚙  OPTIONS"
	title.position = Vector2(PAD, y);  title.size = Vector2(BW, 30)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(0.5, 0.7, 1.0))
	panel.add_child(title);  y += 38
	var hint := Label.new();  hint.text = "O  to close"
	hint.position = Vector2(PAD, y);  hint.size = Vector2(BW, 18)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", Color(0.4, 0.4, 0.5))
	panel.add_child(hint);  y += 30

	# ── Divider helper ────────────────────────────────────────────────────────
	var _div := func() -> void:
		var d := ColorRect.new()
		d.position = Vector2(PAD, y);  d.size = Vector2(BW, 1)
		d.color = Color(0.25, 0.3, 0.45, 0.6)
		panel.add_child(d);  y += 14

	# ── Section: DISPLAY ─────────────────────────────────────────────────────
	_div.call()
	var sec := Label.new();  sec.text = "DISPLAY"
	sec.position = Vector2(PAD, y);  sec.size = Vector2(BW, 20)
	sec.add_theme_font_size_override("font_size", 12)
	sec.add_theme_color_override("font_color", Color(0.5, 0.5, 0.65))
	panel.add_child(sec);  y += 28

	# UI Scale
	var scale_lbl := Label.new();  scale_lbl.text = "HUD Scale"
	scale_lbl.position = Vector2(PAD, y);  scale_lbl.size = Vector2(160, 28)
	scale_lbl.add_theme_font_size_override("font_size", 15)
	scale_lbl.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0))
	panel.add_child(scale_lbl)
	var scale_val := Label.new();  scale_val.text = str(snappedf(_font_scale, 0.25)) + "×"
	scale_val.position = Vector2(PW - PAD - 60.0, y);  scale_val.size = Vector2(60, 28)
	scale_val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	scale_val.add_theme_font_size_override("font_size", 15)
	scale_val.add_theme_color_override("font_color", Color(0.5, 0.85, 1.0))
	panel.add_child(scale_val)
	var scale_desc := Label.new()
	scale_desc.text = "Scales HUD labels, HP bars, and UI text"
	scale_desc.position = Vector2(PAD, y + 22);  scale_desc.size = Vector2(BW, 18)
	scale_desc.add_theme_font_size_override("font_size", 11)
	scale_desc.add_theme_color_override("font_color", Color(0.45, 0.45, 0.55))
	panel.add_child(scale_desc);  y += 46
	var scale_sld := HSlider.new()
	scale_sld.min_value = 0.5;  scale_sld.max_value = 4.0;  scale_sld.step = 0.25
	scale_sld.value = _font_scale
	scale_sld.position = Vector2(PAD, y);  scale_sld.size = Vector2(BW, 28)
	scale_sld.process_mode = Node.PROCESS_MODE_ALWAYS
	scale_sld.value_changed.connect(func(v: float):
		_font_scale = v;  _apply_font_scale()
		scale_val.text = str(snappedf(v, 0.25)) + "×"
	)
	panel.add_child(scale_sld);  y += 40

	# Preset buttons
	var presets := [["1×  Normal", 1.0], ["1.5×  Large", 1.5], ["2×  5K Default", 2.0], ["3×  Giant", 3.0]]
	var preset_x := PAD
	var preset_w := (BW - 12.0) / 4.0
	for pr in presets:
		var pb := Button.new();  pb.text = pr[0] as String
		pb.size = Vector2(preset_w, 36);  pb.position = Vector2(preset_x, y)
		pb.focus_mode = Control.FOCUS_NONE
		pb.process_mode = Node.PROCESS_MODE_ALWAYS
		var pbs := StyleBoxFlat.new()
		pbs.bg_color = Color(0.08, 0.10, 0.18, 1.0)
		pbs.border_color = Color(0.3, 0.5, 0.85, 0.8)
		pbs.set_border_width_all(1);  pbs.set_corner_radius_all(4)
		pb.add_theme_stylebox_override("normal", pbs)
		pb.add_theme_color_override("font_color", Color(0.55, 0.75, 1.0))
		pb.add_theme_font_size_override("font_size", 12)
		var scale_v: float = pr[1] as float
		pb.pressed.connect(func():
			_font_scale = scale_v;  _apply_font_scale()
			scale_sld.value = scale_v
			scale_val.text  = str(snappedf(scale_v, 0.25)) + "×"
		)
		panel.add_child(pb)
		preset_x += preset_w + 4.0
	y += 44

	# Zoom slider
	var zoom_val_lbl := Label.new()
	zoom_val_lbl.position = Vector2(PW - PAD - 70.0, y)
	zoom_val_lbl.size = Vector2(70, 28)
	zoom_val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	zoom_val_lbl.add_theme_font_size_override("font_size", 13)
	zoom_val_lbl.add_theme_color_override("font_color", Color(0.5, 0.85, 1.0))
	zoom_val_lbl.text = "0.75×"
	panel.add_child(zoom_val_lbl)

	var zoom_lbl := Label.new();  zoom_lbl.text = "Camera Zoom"
	zoom_lbl.position = Vector2(PAD, y);  zoom_lbl.size = Vector2(160, 28)
	zoom_lbl.add_theme_font_size_override("font_size", 15)
	zoom_lbl.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0))
	panel.add_child(zoom_lbl)

	var zoom_desc := Label.new()
	zoom_desc.text = "Scroll wheel or Z to reset. 0.75× default for 5K"
	zoom_desc.position = Vector2(PAD, y + 22);  zoom_desc.size = Vector2(BW, 18)
	zoom_desc.add_theme_font_size_override("font_size", 11)
	zoom_desc.add_theme_color_override("font_color", Color(0.45, 0.45, 0.55))
	panel.add_child(zoom_desc);  y += 46

	var zoom_sld := HSlider.new()
	zoom_sld.min_value = 0.25;  zoom_sld.max_value = 2.5;  zoom_sld.step = 0.05
	zoom_sld.value = 0.75
	zoom_sld.position = Vector2(PAD, y);  zoom_sld.size = Vector2(BW, 28)
	zoom_sld.process_mode = Node.PROCESS_MODE_ALWAYS
	zoom_sld.focus_mode = Control.FOCUS_NONE
	zoom_sld.value_changed.connect(func(v: float):
		zoom_val_lbl.text = str(snappedf(v, 0.05)) + "×"
		var player = get_parent().get_node_or_null("Player")
		if player != null and player.has_method("_set_zoom"):
			player.call("_set_zoom", v)
	)
	panel.add_child(zoom_sld);  y += 40

	# Preset zoom buttons
	var zoom_presets := [["0.5×  Far", 0.5], ["0.75×  5K", 0.75], ["1×  Normal", 1.0], ["1.5×  Close", 1.5]]
	var zp_x := PAD
	var zp_w := (BW - 12.0) / 4.0
	for zp in zoom_presets:
		var zpb := Button.new();  zpb.text = zp[0] as String
		zpb.size = Vector2(zp_w, 34);  zpb.position = Vector2(zp_x, y)
		zpb.focus_mode = Control.FOCUS_NONE
		zpb.process_mode = Node.PROCESS_MODE_ALWAYS
		var zpbs := StyleBoxFlat.new()
		zpbs.bg_color = Color(0.06, 0.08, 0.14, 1.0)
		zpbs.border_color = Color(0.3, 0.5, 0.85, 0.8)
		zpbs.set_border_width_all(1);  zpbs.set_corner_radius_all(4)
		zpb.add_theme_stylebox_override("normal", zpbs)
		zpb.add_theme_color_override("font_color", Color(0.55, 0.75, 1.0))
		zpb.add_theme_font_size_override("font_size", 12)
		var zv: float = zp[1] as float
		zpb.pressed.connect(func():
			zoom_sld.value = zv
			zoom_val_lbl.text = str(snappedf(zv, 0.05)) + "×"
			var player = get_parent().get_node_or_null("Player")
			if player != null and player.has_method("_set_zoom"):
				player.call("_set_zoom", zv)
		)
		panel.add_child(zpb)
		zp_x += zp_w + 4.0
	y += 44

	_div.call()
	var sec2 := Label.new();  sec2.text = "WINDOW"
	sec2.position = Vector2(PAD, y);  sec2.size = Vector2(BW, 20)
	sec2.add_theme_font_size_override("font_size", 12)
	sec2.add_theme_color_override("font_color", Color(0.5, 0.5, 0.65))
	panel.add_child(sec2);  y += 28
	var win_btn := Button.new()
	win_btn.text = "WINDOWED MODE"
	win_btn.size = Vector2(BW, 44);  win_btn.position = Vector2(PAD, y)
	win_btn.focus_mode = Control.FOCUS_NONE
	win_btn.process_mode = Node.PROCESS_MODE_ALWAYS
	var wbs := StyleBoxFlat.new()
	wbs.bg_color = Color(0.08, 0.06, 0.12, 1.0)
	wbs.border_color = Color(0.55, 0.35, 0.85, 0.8)
	wbs.set_border_width_all(1);  wbs.set_corner_radius_all(5)
	win_btn.add_theme_stylebox_override("normal", wbs)
	win_btn.add_theme_color_override("font_color", Color(0.75, 0.55, 1.0))
	win_btn.add_theme_font_size_override("font_size", 14)
	win_btn.pressed.connect(func():
		var mode := DisplayServer.window_get_mode()
		if mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			win_btn.text = "FULLSCREEN MODE"
		else:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
			win_btn.text = "WINDOWED MODE"
	)
	panel.add_child(win_btn);  y += 52

	panel.size = Vector2(PW, y + 20.0)
	return panel


# ─── Artifact Tracker ─────────────────────────────────────────────────────────
func _build_artifact_tracker(vp: Vector2) -> void:
	const TOTAL     := 50
	const DOT_R     := 7.0
	const DOT_GAP   := 4.0
	const ROW_Y_OFF := 38.0   # distance above bottom edge
	var total_w: float = TOTAL * (DOT_R * 2.0 + DOT_GAP) - DOT_GAP
	var start_x: float = (vp.x - total_w) / 2.0
	var y_pos: float   = vp.y - ROW_Y_OFF

	_tracker_bar = Node2D.new()
	_tracker_bar.z_index = 8;  _tracker_bar.z_as_relative = false
	add_child(_tracker_bar)

	# Milestone icons at positions 10, 25, 50
	var milestones := {10: "●●", 25: "●●●", 50: "⬡"}
	_tracker_dots.clear()

	for i in TOTAL:
		var cx: float = start_x + float(i) * (DOT_R * 2.0 + DOT_GAP) + DOT_R
		var dot_node := Node2D.new()
		dot_node.position = Vector2(cx, y_pos)
		_tracker_bar.add_child(dot_node)

		# Hollow circle outline (uncollected state)
		var pts := PackedVector2Array()
		for j in 10:
			var a: float = TAU * float(j) / 10.0
			pts.append(Vector2(cos(a), sin(a)) * DOT_R)
		var outline := Polygon2D.new()
		outline.polygon = pts
		outline.color   = Color(0.35, 0.35, 0.40, 0.55)
		dot_node.add_child(outline)

		# Filled dot (collected state — hidden initially)
		var fill := Polygon2D.new()
		fill.polygon = pts
		fill.color   = Color(1.0, 0.85, 0.2, 0.0)  # transparent = uncollected
		dot_node.add_child(fill)

		_tracker_dots.append({"outline": outline, "fill": fill, "node": dot_node,
							   "collected": false, "color": Color.WHITE})

		# Milestone separators
		if (i + 1) in milestones.keys() and i < TOTAL - 1:
			var sep := ColorRect.new()
			sep.size = Vector2(2.0, DOT_R * 2.0 + 4.0)
			sep.position = Vector2(cx + DOT_R + 1.0, y_pos - DOT_R - 2.0)
			sep.color = Color(0.55, 0.55, 0.65, 0.6)
			_tracker_bar.add_child(sep)

func tick_artifact_tracker(total: int = -1) -> void:
	# Called by show_artifact_reveal — total is the player's artifact_count
	var idx: int = (total - 1) if total > 0 else (artifact_count - 1)
	if idx < 0 or idx >= _tracker_dots.size():
		return
	var slot = _tracker_dots[idx]
	# Random vivid color — no same color as previous
	var prev_hue: float = -1.0
	if idx > 0 and (_tracker_dots[idx-1]["collected"] as bool):
		prev_hue = (_tracker_dots[idx-1]["color"] as Color).h
	var hue: float = prev_hue
	while abs(hue - prev_hue) < 0.08:
		hue = randf()
	var col: Color = Color.from_hsv(hue, 0.85, 1.0, 1.0)
	slot["collected"] = true
	slot["color"]     = col
	# Pop-in animation
	var fill: Polygon2D = slot["fill"] as Polygon2D
	fill.color = col
	var dot_node: Node2D = slot["node"] as Node2D
	dot_node.scale = Vector2(0.1, 0.1)
	var tw := get_tree().create_tween()
	tw.set_parallel(true)
	tw.tween_property(dot_node, "scale", Vector2(1.3, 1.3), 0.15)
	tw.tween_property(fill,     "color", col,               0.15)
	tw.set_parallel(false)
	tw.tween_property(dot_node, "scale", Vector2(1.0, 1.0), 0.08)


# ─── Artifact HUD ─────────────────────────────────────────────────────────────
func show_artifact_carrying(is_carrying: bool) -> void:
	if _artifact_carry_label == null: return
	_artifact_carry_label.visible = is_carrying
	if is_carrying:
		# Pulse the label while carrying
		var tw := get_tree().create_tween().set_loops()
		tw.tween_property(_artifact_carry_label, "modulate:a", 0.4, 0.7)
		tw.tween_property(_artifact_carry_label, "modulate:a", 1.0, 0.7)
		_artifact_carry_label.set_meta("pulse_tween", tw)
	else:
		if _artifact_carry_label.has_meta("pulse_tween"):
			(_artifact_carry_label.get_meta("pulse_tween") as Tween).kill()
		_artifact_carry_label.modulate.a = 1.0

func show_artifact_reveal(reward_name: String, total: int) -> void:
	if _artifact_reveal_label == null: return
	_artifact_reveal_label.text = "◆  " + reward_name + "\n    Artifacts: " + str(total)
	artifact_count = total   # keep hud in sync
	tick_artifact_tracker(total)
	_artifact_reveal_label.visible = true
	_artifact_reveal_label.modulate.a = 1.0
	# Hide carry label
	show_artifact_carrying(false)
	var tw := get_tree().create_tween()
	tw.tween_interval(1.8)
	tw.tween_property(_artifact_reveal_label, "modulate:a", 0.0, 0.6)
	tw.tween_callback(func(): _artifact_reveal_label.visible = false)

func show_artifact_dropped() -> void:
	if _artifact_carry_label != null:
		_artifact_carry_label.visible = false
	if _artifact_reveal_label == null: return
	_artifact_reveal_label.text = "◆  ARTIFACT LOST  —  Find it again"
	_artifact_reveal_label.modulate.a = 1.0
	_artifact_reveal_label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.2))
	_artifact_reveal_label.visible = true
	var tw := get_tree().create_tween()
	tw.tween_interval(2.2)
	tw.tween_property(_artifact_reveal_label, "modulate:a", 0.0, 0.6)
	tw.tween_callback(func():
		_artifact_reveal_label.visible = false
		_artifact_reveal_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
	)


func show_milestone(text: String) -> void:
	if _milestone_label == null: return
	_milestone_label.text = "★  " + text + "  ★"
	_milestone_label.visible = true
	_milestone_label.modulate.a = 1.0
	var tw := get_tree().create_tween()
	tw.tween_interval(3.0)
	tw.tween_property(_milestone_label, "modulate:a", 0.0, 1.0)
	tw.tween_callback(func(): _milestone_label.visible = false)


# ─── AUTO-PAUSE ───────────────────────────────────────────────────────────────
func _check_auto_pause() -> void:
	if _can_afford_any():
		get_tree().paused = true
		if _skills_win != null: _skills_win.visible = true

func _can_afford_any() -> bool:
	for i in range(skill_kill_costs.size()):
		if skill_levels[i] < 10 and skill_points >= skill_kill_costs[i] and skill_kill_costs[i] >= auto_pause_min_cost:
			return true
	return false


# ─── HUD UPDATES ──────────────────────────────────────────────────────────────
func update_shield(current: float, max_val: float) -> void:
	# Lazy-create shield bar above HP bar
	if _shield_bar_bg == null:
		var bar_w: float = 200.0 * _font_scale
		var bar_h: float = 6.0 * _font_scale
		_shield_bar_bg = ColorRect.new()
		_shield_bar_bg.size = Vector2(bar_w, bar_h)
		_shield_bar_bg.color = Color(0.05, 0.08, 0.18)
		add_child(_shield_bar_bg)
		_shield_bar_fill = ColorRect.new()
		_shield_bar_fill.size = Vector2(bar_w, bar_h)
		_shield_bar_fill.color = Color(0.2, 0.6, 1.0)
		add_child(_shield_bar_fill)
		# Position above HP bar
		if hp_bar_bg != null:
			_shield_bar_bg.position = hp_bar_bg.position + Vector2(0, -(bar_h + 3.0))
			_shield_bar_fill.position = _shield_bar_bg.position
	if _shield_bar_bg == null: return
	var ratio: float = clampf(current / maxf(max_val, 1.0), 0.0, 1.0)
	_shield_bar_fill.size.x = _shield_bar_bg.size.x * ratio
	_shield_bar_fill.color = Color(0.2, 0.6, 1.0) if ratio > 0.3 else Color(0.4, 0.3, 0.9)
	_shield_bar_bg.visible = max_val > 0.0
	_shield_bar_fill.visible = max_val > 0.0

func update_health(current: float, max_val: float) -> void:
	health_label.text = "HP: " + str(int(current)) + " / " + str(int(max_val))
	var r := clampf(current / max_val, 0.0, 1.0) if max_val > 0 else 0.0
	hp_bar_fill.size.x = 200.0 * r
	if r > 0.6: hp_bar_fill.color = Color(0.1,0.85,0.15)
	elif r > 0.3: hp_bar_fill.color = Color(1.0,0.8,0.0)
	else: hp_bar_fill.color = Color(0.9,0.1,0.1)
	stat_damage_taken += (1.0 - r) * 0.1  # rough accumulation

func update_cooldown(time_left: float) -> void:
	if time_left <= 0.0:
		cooldown_label.visible = false
		return
	var mins: int = int(time_left) / 60
	var secs: int = int(time_left) % 60
	cooldown_label.text = "NEXT WAVE  " + str(mins) + ":" + ("%02d" % secs)
	# Color shifts red as time runs low
	var ratio: float = clampf(time_left / 60.0, 0.0, 1.0)
	cooldown_label.modulate = Color(1.0, ratio * 0.7 + 0.3, ratio * 0.3)

func start_cooldown(duration: float) -> void:
	get_tree().paused = false;  pause_label.visible = false
	var mins: int = int(duration) / 60
	var secs: int = int(duration) % 60
	cooldown_label.text = "NEXT WAVE  " + str(mins) + ":" + ("%02d" % secs)
	cooldown_label.visible = true
	stat_waves_survived += 1
	show_placement_panel()
	call_deferred("show_powerup_offer", "wave")

func update_wave_info(wave: int, bt_active: bool, bt_timer: float, bt_recharge: float) -> void:
	if wave_label == null: return
	wave_label.text = "Wave: " + str(wave)
	boss_label.text = "Boss in: " + str(5 - ((wave - 1) % 5)) + " waves"
	if bt_active:        bt_label.text = "BT: " + str(snappedf(bt_timer / 10.0, 0.1)) + "s"
	elif bt_recharge > 0: bt_label.text = "BT: " + str(snappedf(bt_recharge, 0.1)) + "s recharge"
	else:                bt_label.text = "BT: Ready"

func update_tower_count(destroyed: int, total: int) -> void:
	var rem := total - destroyed
	tower_label.text = "🏰  Towers: " + str(destroyed) + " / " + str(total)
	if rem == 0:    tower_label.text = "🏰  All towers down — BOSS INCOMING!"; tower_label.modulate = Color.RED
	elif rem <= 2:  tower_label.modulate = Color(1.0, 0.3, 0.1)
	else:           tower_label.modulate = Color(1.0, 0.55, 0.15)

func show_boss_warning(rank: int) -> void:
	current_boss_rank = rank
	boss_hp_bar_bg.visible = true;  boss_hp_bar_fill.visible = true;  boss_hp_label.visible = true
	boss_warning_label.text = "⚠  BOSS  RANK " + str(rank) + "  INCOMING!";  boss_warning_label.visible = true
	await get_tree().create_timer(3.0, true).timeout
	if is_instance_valid(boss_warning_label): boss_warning_label.visible = false

# ── Tron Flip warning overlay ─────────────────────────────────────────────────
func show_flip_warning() -> void:
	# Lazy-create the WARNING BOSS FIGHT label
	if _flip_warning_label == null:
		_flip_warning_label = Label.new()
		_flip_warning_label.text = "⚠  WARNING  BOSS FIGHT  ⚠"
		_flip_warning_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_flip_warning_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
		_flip_warning_label.position.y = 120
		_flip_warning_label.size = Vector2(get_viewport().size.x, 72)
		_flip_warning_label.add_theme_font_size_override("font_size", 48)
		_flip_warning_label.add_theme_color_override("font_color", Color(1.0, 0.0, 0.0))
		_flip_warning_label.process_mode = Node.PROCESS_MODE_ALWAYS
		_flip_warning_label.visible = false
		add_child(_flip_warning_label)

	_flip_warning_label.visible = true
	_flip_warning_label.modulate = Color(1, 1, 1, 1)

	# Pulsing dark red ↔ bright red, looping
	if _flip_warning_tween != null and is_instance_valid(_flip_warning_tween):
		_flip_warning_tween.kill()
	_flip_warning_tween = get_tree().create_tween().set_loops()
	_flip_warning_tween.tween_property(_flip_warning_label, "modulate",
		Color(0.4, 0.0, 0.0, 1.0), 0.55)
	_flip_warning_tween.tween_property(_flip_warning_label, "modulate",
		Color(1.0, 0.0, 0.0, 1.0), 0.55)

func hide_flip_warning() -> void:
	if _flip_warning_tween != null and is_instance_valid(_flip_warning_tween):
		_flip_warning_tween.kill()
		_flip_warning_tween = null
	if _flip_warning_label != null and is_instance_valid(_flip_warning_label):
		var fw := get_tree().create_tween()
		fw.tween_property(_flip_warning_label, "modulate:a", 0.0, 0.5)
		fw.tween_callback(func(): _flip_warning_label.visible = false)

func update_boss_hp(current: float, max_val: float) -> void:
	boss_hp_label.text = "⚔  RANK " + str(current_boss_rank) + "   " + str(int(current)) + " / " + str(int(max_val))
	var r := clampf(current / max_val, 0.0, 1.0) if max_val > 0 else 0.0
	boss_hp_bar_fill.size.x = 400.0 * r;  boss_hp_bar_fill.color = Color(0.2 + (1.0 - r) * 0.5, 0.0, r * 0.85)

func hide_boss_bar() -> void:
	boss_hp_bar_bg.visible = false;  boss_hp_bar_fill.visible = false;  boss_hp_label.visible = false
	tower_label.modulate = Color(1.0, 0.55, 0.15);  stat_bosses_killed += 1

func show_you_win() -> void:
	get_tree().paused = true;  win_panel = Panel.new()
	win_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	win_panel.modulate = Color(0, 0, 0, 0.90)
	win_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	var msg := Label.new()
	msg.text = "🏆  YOU WIN!\nVEXAGON CONQUERED!" if ng_plus == 0 else "🌟  NG+ CYCLE " + str(ng_plus) + " COMPLETE!"
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER;  msg.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	msg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	msg.add_theme_font_size_override("font_size", 42);  msg.add_theme_color_override("font_color", Color.GOLD)
	var sub := Label.new()
	sub.text = "All 10 Boss Ranks defeated.\nPress N for New Game+  (keep upgrades, bosses start Rank " + str(5 + ng_plus * 5) + ")\nPress any other key to start fresh."
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sub.add_theme_font_size_override("font_size", 20);  sub.add_theme_color_override("font_color", Color.WHITE)
	sub.position.y = 80
	win_panel.add_child(msg);  win_panel.add_child(sub);  add_child(win_panel)

func _start_ng_plus() -> void:
	ng_plus += 1
	var spawner = get_parent().get_node("EnemySpawner")
	# Keep all upgrades, skills, gold — reset waves and bosses
	spawner.wave_number     = 0
	spawner.boss_rank       = 4 + ng_plus    # starts at rank 5 for NG+1, 6 for NG+2, etc.
	spawner.towers_destroyed = 0
	spawner.tower_level     = spawner.boss_rank
	spawner.boss_alive      = false
	spawner.boss_node       = null
	spawner._spawn_enemy_towers()
	spawner.start_wave()
	_checkpoint.clear()
	get_tree().paused = false
	if is_instance_valid(win_panel): win_panel.queue_free()
	win_panel = null
	update_tower_count(0, 5)

func save_checkpoint() -> void:
	var player    = get_parent().get_node_or_null("Player")
	var spawner   = get_parent().get_node("EnemySpawner")
	var nm        = get_parent().get_node_or_null("NodeManager")
	var placed_serial: Array = []
	if nm != null:
		for hex_key in (nm as Node).get("placed_nodes").keys():
			var hk := hex_key as Vector2i
			placed_serial.append([hk.x, hk.y, nm.placed_nodes[hex_key]])
	_checkpoint = {
		"gold":              gold,
		"skill_levels":      skill_levels.duplicate(),
		"skill_kill_costs":  skill_kill_costs.duplicate(),
		"skill_points":      skill_points,
		"kill_count":        kill_count,
		"tower_upgrades":    tower_upgrade_levels.duplicate(),
		"sp_spent":          _sp_spent,
		"wave":              spawner.wave_number,
		"boss_rank":         spawner.boss_rank,
		"placed_nodes":      placed_serial,
	}
	if player != null:
		_checkpoint["player_hp"]       = player.current_hp
		_checkpoint["barrel_level"]    = player.barrel_level
		_checkpoint["shield_unlocked"] = player.shield_unlocked
		_checkpoint["shield_hp"]       = player.get("_shield_hp") if player.get("_shield_hp") != null else 0.0
		_checkpoint["shield_max"]      = player.get("_shield_max") if player.get("_shield_max") != null else 0.0
		_checkpoint["artifact_count"]  = player.artifact_count
	var banner := Label.new()
	banner.text = "✔  CHECKPOINT SAVED"
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	banner.position.y = 80
	banner.add_theme_font_size_override("font_size", 26)
	banner.add_theme_color_override("font_color", Color(0.3, 1.0, 0.5))
	banner.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(banner)
	await get_tree().create_timer(2.5, true).timeout
	if is_instance_valid(banner): banner.queue_free()

func restore_checkpoint() -> bool:
	if _checkpoint.is_empty(): return false
	gold = _checkpoint["gold"];  gold_label.text = "Gold: " + str(gold)
	skill_levels      = (_checkpoint["skill_levels"] as Array).duplicate()
	skill_kill_costs  = (_checkpoint["skill_kill_costs"] as Array).duplicate()
	skill_points      = _checkpoint["skill_points"]
	kill_count        = _checkpoint["kill_count"];  kill_label.text = "Kills: " + str(kill_count)
	tower_upgrade_levels = (_checkpoint["tower_upgrades"] as Array).duplicate()
	_sp_spent         = _checkpoint["sp_spent"]
	var spawner       = get_parent().get_node("EnemySpawner")
	spawner.wave_number = _checkpoint["wave"]
	spawner.boss_rank   = _checkpoint["boss_rank"]
	spawner.boss_alive  = false
	spawner.towers_destroyed = 0
	spawner._spawn_enemy_towers()
	update_tower_count(0, 5)
	var player = get_parent().get_node_or_null("Player")
	if player != null:
		player.current_hp      = _checkpoint.get("player_hp", 10.0)
		player.max_hp          = player.get_max_hp()
		player.barrel_level    = _checkpoint.get("barrel_level", 1)
		player.artifact_count  = _checkpoint.get("artifact_count", 0)
		player.shield_unlocked = _checkpoint.get("shield_unlocked", false)
		player.set("_shield_max", _checkpoint.get("shield_max", 0.0))
		player.set("_shield_hp",  _checkpoint.get("shield_hp",  0.0))
		update_health(player.current_hp, player.max_hp)
		if player.shield_unlocked:
			update_shield(player.get("_shield_hp"), player.get("_shield_max"))
	var nm = get_parent().get_node_or_null("NodeManager")
	if nm != null and _checkpoint.has("placed_nodes"):
		nm.placed_nodes.clear()
		nm.turret_timers.clear()
		nm.turret_rotations.clear()
		nm.mine_smoke_phase.clear()
		for entry in (_checkpoint["placed_nodes"] as Array):
			nm.place_node(Vector2i(entry[0] as int, entry[1] as int), entry[2] as String)
	call_deferred("refresh_panel")
	return true

func show_game_over() -> void:
	# Try checkpoint restore first
	if not _checkpoint.is_empty():
		var restored: bool = restore_checkpoint()
		if restored:
			var banner := Label.new()
			banner.text = "↩  CHECKPOINT RESTORED"
			banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			banner.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
			banner.position.y = 80
			banner.add_theme_font_size_override("font_size", 26)
			banner.add_theme_color_override("font_color", Color(1.0, 0.7, 0.2))
			banner.process_mode = Node.PROCESS_MODE_ALWAYS
			add_child(banner)
			await get_tree().create_timer(3.0, true).timeout
			if is_instance_valid(banner): banner.queue_free()
			return
	get_tree().paused = true;  game_over_panel = Panel.new()
	game_over_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game_over_panel.modulate = Color(0,0,0,0.85);  game_over_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	var msg := Label.new();  msg.text = "Aww! Don't give up!\nRebuild your Castle and try again!"
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER;  msg.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	msg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	msg.add_theme_font_size_override("font_size", 36);  msg.add_theme_color_override("font_color", Color.RED)
	var hint := Label.new();  hint.text = "Press any key to restart"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER;  hint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hint.add_theme_font_size_override("font_size", 20);  hint.add_theme_color_override("font_color", Color.WHITE)
	hint.position.y = 60;  game_over_panel.add_child(msg);  game_over_panel.add_child(hint);  add_child(game_over_panel)

func show_powerup_offer(source: String) -> void:
	if _powerup_panel != null and is_instance_valid(_powerup_panel):
		_dismiss_powerup_panel()
	var pd = load("res://powerup_data.gd")
	if pd == null: return
	var pdi = pd.new()
	var active_ids: Array = []
	for pu in active_powerups: active_ids.append(pu["id"])
	var offers: Array = pdi.get_offer(active_ids, source)
	pdi.queue_free()
	if offers.is_empty(): return

	var vp := get_viewport().get_visible_rect().size
	Engine.time_scale = 0.15
	var panel := Panel.new()
	panel.size = Vector2(720, 290)
	panel.position = Vector2(vp.x / 2.0 - 360.0, vp.y / 2.0 - 145.0)
	panel.z_index = 20
	panel.process_mode = Node.PROCESS_MODE_ALWAYS
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.03, 0.03, 0.07, 0.97)
	ps.border_color = Color(0.0, 0.9, 1.0)
	ps.set_border_width_all(3);  ps.set_corner_radius_all(10)
	panel.add_theme_stylebox_override("panel", ps)
	add_child(panel)
	_powerup_panel = panel
	# Rainbow border
	var _hue := [0.0]
	var _rainbow := get_tree().create_tween().set_loops()
	_rainbow.set_process_mode(Tween.TWEEN_PROCESS_IDLE)
	_rainbow.tween_callback(func():
		if not is_instance_valid(panel): return
		_hue[0] = fmod(_hue[0] + 0.025, 1.0)
		ps.border_color = Color.from_hsv(_hue[0], 0.95, 1.0)
		panel.add_theme_stylebox_override("panel", ps)
	)
	_rainbow.tween_interval(0.04)
	panel.set_meta("rainbow_tween", _rainbow)
	_rainbow_tween = _rainbow
	# Dark backdrop
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.0, 0.0, 0.0, 0.50)
	backdrop.size = vp;  backdrop.position = Vector2.ZERO
	backdrop.z_index = 19
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(backdrop)
	panel.set_meta("backdrop_ref", backdrop)
	# Slide in from below
	var final_y: float = panel.position.y
	panel.position.y = vp.y + 20.0
	panel.modulate.a = 0.0
	var slide_tw := get_tree().create_tween()
	slide_tw.set_process_mode(Tween.TWEEN_PROCESS_IDLE)
	slide_tw.set_parallel(true)
	slide_tw.tween_property(panel, "position:y", final_y, 0.22)
	slide_tw.tween_property(panel, "modulate:a",  1.0,    0.18)

	var title := Label.new()
	title.text = "⚡  POWER-UP OFFER — pick one (or press ESC to skip)"
	title.position = Vector2(10, 8);  title.size = Vector2(680, 24)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0))
	panel.add_child(title)

	var cat_names := ["PLAYER", "TOWER", "TRADEOFF", "CURSED"]
	var card_w := 210.0
	var card_x := 12.0
	for i in offers.size():
		var pu: Array = offers[i]
		var pu_col := Color("#" + pu[5])
		var card := Panel.new()
		card.size = Vector2(card_w, 200)
		card.position = Vector2(card_x + float(i) * (card_w + 12.0), 36)
		card.process_mode = Node.PROCESS_MODE_ALWAYS
		var cs := StyleBoxFlat.new()
		cs.bg_color = Color(pu_col.r * 0.1, pu_col.g * 0.1, pu_col.b * 0.1, 1.0)
		cs.border_color = pu_col;  cs.set_border_width_all(1);  cs.set_corner_radius_all(6)
		card.add_theme_stylebox_override("panel", cs)
		panel.add_child(card)

		var cat_lbl := Label.new()
		cat_lbl.text = cat_names[pu[2]]
		cat_lbl.position = Vector2(8, 6);  cat_lbl.size = Vector2(card_w - 16, 18)
		cat_lbl.add_theme_font_size_override("font_size", 11)
		cat_lbl.add_theme_color_override("font_color", pu_col)
		card.add_child(cat_lbl)

		var name_lbl := Label.new()
		name_lbl.text = pu[1]
		name_lbl.position = Vector2(8, 26);  name_lbl.size = Vector2(card_w - 16, 28)
		name_lbl.add_theme_font_size_override("font_size", 17)
		name_lbl.add_theme_color_override("font_color", Color.WHITE)
		card.add_child(name_lbl)

		var effect_lbl := Label.new()
		effect_lbl.text = pu[3]
		effect_lbl.position = Vector2(8, 60);  effect_lbl.size = Vector2(card_w - 16, 60)
		effect_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		effect_lbl.add_theme_font_size_override("font_size", 13)
		effect_lbl.add_theme_color_override("font_color", Color(0.85, 0.85, 0.9))
		card.add_child(effect_lbl)

		if pu[4] != "":
			var cost_lbl := Label.new()
			cost_lbl.text = "COST: " + pu[4]
			cost_lbl.position = Vector2(8, 120);  cost_lbl.size = Vector2(card_w - 16, 50)
			cost_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			cost_lbl.add_theme_font_size_override("font_size", 11)
			cost_lbl.add_theme_color_override("font_color", Color(1.0, 0.5, 0.4))
			card.add_child(cost_lbl)

		var pick_btn := Button.new();  pick_btn.focus_mode = Control.FOCUS_NONE
		pick_btn.text = "TAKE IT"
		pick_btn.size = Vector2(card_w - 16, 30)
		pick_btn.position = Vector2(8, 164)
		pick_btn.process_mode = Node.PROCESS_MODE_ALWAYS
		var btn_sty := StyleBoxFlat.new()
		btn_sty.bg_color = Color(pu_col.r * 0.3, pu_col.g * 0.3, pu_col.b * 0.3, 1.0)
		btn_sty.border_color = pu_col;  btn_sty.set_border_width_all(1);  btn_sty.set_corner_radius_all(4)
		pick_btn.add_theme_stylebox_override("normal", btn_sty)
		pick_btn.add_theme_color_override("font_color", pu_col)
		pick_btn.add_theme_font_size_override("font_size", 14)
		var captured_pu = pu
		pick_btn.pressed.connect(func():
			_on_powerup_picked(captured_pu)
		)
		card.add_child(pick_btn)

func _dismiss_powerup_panel() -> void:
	if _powerup_panel == null or not is_instance_valid(_powerup_panel): return
	var panel = _powerup_panel
	_powerup_panel = null
	if panel.has_meta("rainbow_tween"):
		(panel.get_meta("rainbow_tween") as Tween).kill()
	_rainbow_tween = null
	if panel.has_meta("backdrop_ref"):
		var bd = panel.get_meta("backdrop_ref")
		if is_instance_valid(bd): (bd as Node).queue_free()
	var tw := get_tree().create_tween()
	tw.set_process_mode(Tween.TWEEN_PROCESS_IDLE)
	tw.set_parallel(true)
	tw.tween_property(panel, "position:y", panel.position.y + 60.0, 0.16)
	tw.tween_property(panel, "modulate:a", 0.0, 0.14)
	tw.set_parallel(false)
	tw.tween_callback(func():
		if is_instance_valid(panel): panel.queue_free()
		Engine.time_scale = 1.0
	)

func _on_powerup_picked(pu: Array) -> void:
	active_powerups.append({"id": pu[0], "name": pu[1], "category": pu[2], "effect": pu[3], "cost": pu[4]})
	add_powerup_to_gallery(pu[1], "⚡", pu[3], Color("#" + pu[5]))
	_apply_powerup_effect(pu[0])
	_dismiss_powerup_panel()

func _apply_powerup_effect(id: String) -> void:
	var player = get_parent().get_node_or_null("Player")
	var spawner = get_parent().get_node_or_null("EnemySpawner")
	var nm = get_parent().get_node_or_null("NodeManager")
	match id:
		"fury":
			if player != null: player.set_meta("fury_active", true)
		"armor":
			if player != null: player.set_meta("damage_resist", 0.10)
		"iron_skin":
			if player != null:
				player.max_hp += 3.0
				player.set_meta("speed_mult", 0.80)
		"overclock":
			if player != null: player.set_meta("speed_mult", 1.40)
		"glass_cannon":
			if player != null:
				player.max_hp = 3.0
				player.current_hp = minf(player.current_hp, 3.0)
				player.set_meta("damage_mult", 2.0)
		"rapid_reload":
			if nm != null: nm.turret_fire_rate = maxf(0.2, nm.turret_fire_rate * 0.75)
		"enemy_pact":
			if spawner != null: spawner.set_meta("enemy_hp_mult", 0.70)
		"fools_gold":
			set_meta("gold_mult", 2.0)
		"berserker":
			if player != null:
				player.max_hp -= 2.0
				player.set_meta("berserker_active", true)
		_:
			pass   # remaining effects wired in Batch 5

func show_placement_panel() -> void:
	if _placer_win != null: _placer_win.visible = true

func hide_placement_panel() -> void:
	selected_node_type = ""

# ─── DEBUG PANEL (G key) ──────────────────────────────────────────────────────
func _build_debug_panel(vp: Vector2) -> Panel:
	const PW  := 520.0
	const PAD := 16.0
	const BW  := 488.0   # usable content width
	const BH  := 48.0    # button height
	const BH2 := 42.0    # half-row button height
	const SH  := 38.0    # slider row height

	var panel := Panel.new()
	panel.size = Vector2(PW, 1020)
	panel.position = Vector2(vp.x / 2.0 - PW / 2.0, vp.y / 2.0 - 510.0)
	panel.visible = false
	panel.process_mode = Node.PROCESS_MODE_ALWAYS
	var sty := StyleBoxFlat.new()
	sty.bg_color = Color(0.05, 0.05, 0.09, 0.97)
	sty.border_color = Color(1.0, 0.3, 0.3, 0.9)
	sty.set_border_width_all(2);  sty.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", sty)
	add_child(panel)

	# ── Inline helpers (no lambda-y tricks — all explicit positions) ──────────
	var _lbl := func(text: String, x: float, y: float, w: float, h: float,
					  fs: int, col: Color, center: bool = false) -> Label:
		var l := Label.new();  l.text = text
		l.position = Vector2(x, y);  l.size = Vector2(w, h)
		l.add_theme_font_size_override("font_size", fs)
		l.add_theme_color_override("font_color", col)
		if center: l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		panel.add_child(l);  return l

	var _btn := func(label: String, x: float, y: float, w: float, h: float,
					 col: Color, cb: Callable) -> Button:
		var b := Button.new();  b.text = label
		b.size = Vector2(w, h);  b.position = Vector2(x, y)
		b.focus_mode = Control.FOCUS_NONE
		b.process_mode = Node.PROCESS_MODE_ALWAYS
		var bsn := StyleBoxFlat.new()
		bsn.bg_color = Color(0.09, 0.06, 0.06, 1.0)
		bsn.border_color = col;  bsn.set_border_width_all(1);  bsn.set_corner_radius_all(5)
		b.add_theme_stylebox_override("normal", bsn)
		b.add_theme_color_override("font_color", col)
		b.add_theme_font_size_override("font_size", 14)
		b.pressed.connect(cb)
		panel.add_child(b);  return b

	var _sld := func(label: String, y: float, min_v: float, max_v: float,
					 val: float, step: float, col: Color, cb: Callable) -> void:
		var row := HBoxContainer.new()
		row.position = Vector2(PAD, y);  row.custom_minimum_size = Vector2(BW, SH)
		row.process_mode = Node.PROCESS_MODE_ALWAYS
		var lbl2 := Label.new();  lbl2.text = label
		lbl2.custom_minimum_size = Vector2(165, 0)
		lbl2.add_theme_font_size_override("font_size", 13)
		lbl2.add_theme_color_override("font_color", col)
		var sld2 := HSlider.new()
		sld2.min_value = min_v;  sld2.max_value = max_v;  sld2.value = val;  sld2.step = step
		sld2.custom_minimum_size = Vector2(210, 0);  sld2.process_mode = Node.PROCESS_MODE_ALWAYS
		var vl := Label.new();  vl.text = str(snappedf(val, step))
		vl.custom_minimum_size = Vector2(50, 0)
		vl.add_theme_font_size_override("font_size", 13)
		vl.add_theme_color_override("font_color", col)
		sld2.value_changed.connect(func(v): vl.text = str(snappedf(v, step)); cb.call(v))
		row.add_child(lbl2);  row.add_child(sld2);  row.add_child(vl)
		panel.add_child(row)

	# ─────────────────────────────────────────────────────────────────────────
	# HEADER
	# ─────────────────────────────────────────────────────────────────────────
	_lbl.call("⚠  DEBUG / GAME MASTER PANEL", PAD, 10, BW, 30, 18, Color(1.0, 0.35, 0.35), true)
	_lbl.call("G  to close    |    O  for Options", PAD, 44, BW, 20, 11, Color(0.42, 0.42, 0.52), true)

	# ─────────────────────────────────────────────────────────────────────────
	# SECTION: SKILLS  (y=82)
	# ─────────────────────────────────────────────────────────────────────────
	_lbl.call("— SKILLS —", PAD, 76, BW, 22, 13, Color(0.55, 0.55, 0.70))
	_btn.call("MAX ALL SKILLS  (LV 10)", PAD, 102, BW, BH, Color(1.0, 0.7, 0.2), func():
		for i in skill_levels.size():
			skill_levels[i] = 10;  skill_kill_costs[i] = 8
		pending_queue.clear();  call_deferred("refresh_panel")
	)
	_btn.call("+1 ALL SKILLS  (step test)", PAD, 158, BW, BH, Color(0.45, 0.85, 0.38), func():
		for i in skill_levels.size():
			skill_levels[i] = mini((skill_levels[i] as int) + 1, 10)
			if skill_levels[i] == 10: skill_kill_costs[i] = 8
		pending_queue.clear();  call_deferred("refresh_panel")
	)
	_btn.call("RESET ALL SKILLS", PAD, 214, BW, BH, Color(0.8, 0.4, 0.2), func():
		for i in skill_levels.size():
			skill_levels[i] = 0;  skill_kill_costs[i] = 1
		pending_queue.clear();  call_deferred("refresh_panel")
	)

	# ─────────────────────────────────────────────────────────────────────────
	# SECTION: PLAYER  (y=282)
	# ─────────────────────────────────────────────────────────────────────────
	_lbl.call("— PLAYER —", PAD, 278, BW, 22, 13, Color(0.55, 0.55, 0.70))
	var half := BW / 2.0 - 4.0
	_btn.call("GOD MODE  (HP ∞)", PAD,            304, half, BH2, Color(0.4, 1.0, 0.5), func():
		var player = get_parent().get_node("Player")
		player._god_mode = not player._god_mode
		if player._god_mode:
			player.current_hp = player.max_hp;  update_health(player.max_hp, player.max_hp)
		else: update_health(player.current_hp, player.max_hp)
	)
	_btn.call("TOWER INVINCIBLE",  PAD + half + 8, 304, half, BH2, Color(0.3, 0.8, 1.0), func():
		var t = get_parent().get_node_or_null("Castle")
		if t != null: t.invincible = not t.invincible
	)
	_btn.call("+50 Skill Points",  PAD,            354, half, BH2, Color(0.4, 0.7, 1.0), func():
		skill_points += 50;  call_deferred("refresh_panel")
	)
	_btn.call("+500 Skill Points", PAD + half + 8, 354, half, BH2, Color(0.3, 0.55, 0.9), func():
		skill_points += 500;  call_deferred("refresh_panel")
	)
	_sld.call("Max homing bullets", 404, 15, 100, max_homing_bullets, 1,
		Color(1.0, 0.6, 0.9), func(v: float): max_homing_bullets = int(v))

	# ─────────────────────────────────────────────────────────────────────────
	# SECTION: DISPLAY  (y=458)
	# ─────────────────────────────────────────────────────────────────────────
	_lbl.call("— DISPLAY —", PAD, 454, BW, 22, 13, Color(0.55, 0.55, 0.70))
	_sld.call("UI Font Scale", 480, 0.5, 4.0, _font_scale, 0.25,
		Color(0.9, 0.9, 0.5), func(v: float): _font_scale = v; _apply_font_scale())

	# ─────────────────────────────────────────────────────────────────────────
	# SECTION: ENEMIES  (y=534)
	# ─────────────────────────────────────────────────────────────────────────
	_lbl.call("— ENEMIES —", PAD, 530, BW, 22, 13, Color(0.55, 0.55, 0.70))
	_sld.call("Cooldown (s)",     556, 10, 300, 60,  10, Color(0.6, 0.8, 1.0), func(v: float):
		var sp = get_parent().get_node_or_null("EnemySpawner")
		if sp != null: sp.cooldown_duration = v)
	_sld.call("Spawn rate /sec",  602, 1,  10,  1,   1,  Color(1.0, 0.5, 0.4), func(v: float):
		var sp = get_parent().get_node_or_null("EnemySpawner")
		if sp != null: sp.spawn_delay_interval = 1.0 / v)
	_sld.call("Enemy speed mult", 648, 0.5, 3.0, 1.0, 0.5, Color(1.0, 0.7, 0.4), func(v: float):
		var sp = get_parent().get_node_or_null("EnemySpawner")
		if sp != null: sp.debug_speed_mult = v)

	# ─────────────────────────────────────────────────────────────────────────
	# SECTION: GOLD  (y=702)
	# ─────────────────────────────────────────────────────────────────────────
	_lbl.call("— GOLD —", PAD, 698, BW, 22, 13, Color(0.55, 0.55, 0.70))
	_btn.call("+1000 Gold",  PAD,            724, half, BH2, Color(1.0, 0.85, 0.2), func(): add_gold(1000))
	_btn.call("+10000 Gold", PAD + half + 8, 724, half, BH2, Color(0.9, 0.75, 0.1), func(): add_gold(10000))

	# ─────────────────────────────────────────────────────────────────────────
	# SECTION: CRYSTALS  (y=752)
	# ─────────────────────────────────────────────────────────────────────────
	_lbl.call("— CRYSTALS —", PAD, 750, BW, 22, 13, Color(0.3, 0.85, 1.0))
	_btn.call("+10 Crystals",  PAD,            776, half, BH2, Color(0.2, 0.75, 1.0), func(): add_node_fragment(10))
	_btn.call("+100 Crystals", PAD + half + 8, 776, half, BH2, Color(0.1, 0.55, 0.9), func(): add_node_fragment(100))

	# ─────────────────────────────────────────────────────────────────────────
	# SECTION: WORLD  (y=832)
	# ─────────────────────────────────────────────────────────────────────────
	_lbl.call("— WORLD TRANSITION —", PAD, 830, BW, 22, 13, Color(0.55, 0.55, 0.70))
	var _world_btn: Button = _btn.call("FLIP TO DARK FUTURE", PAD, 856, BW, BH, Color(0.0, 0.85, 1.0), func(): pass) as Button
	var _wb_sty := StyleBoxFlat.new()
	_wb_sty.bg_color = Color(0.04, 0.02, 0.10, 1.0)
	_wb_sty.border_color = Color(0.0, 0.85, 1.0)
	_wb_sty.set_border_width_all(1);  _wb_sty.set_corner_radius_all(5)
	_world_btn.add_theme_stylebox_override("normal", _wb_sty)
	# Disconnect the placeholder and wire the real toggle
	for c in _world_btn.pressed.get_connections(): _world_btn.pressed.disconnect(c["callable"])
	_world_btn.pressed.connect(func():
		var hex_map = get_parent().get_node_or_null("HexMap")
		if hex_map == null: return
		var going_future: bool = not hex_map.is_future_mode
		hex_map.cascade_world_flip(going_future)
		if going_future:
			_world_btn.text = "FLIP TO OVERWORLD"
			_wb_sty.border_color = Color(0.0, 1.0, 0.5)
			_world_btn.add_theme_color_override("font_color", Color(0.0, 1.0, 0.5))
		else:
			_world_btn.text = "FLIP TO DARK FUTURE"
			_wb_sty.border_color = Color(0.0, 0.85, 1.0)
			_world_btn.add_theme_color_override("font_color", Color(0.0, 0.85, 1.0))
	)

	panel.size = Vector2(PW, 866)
	return panel
