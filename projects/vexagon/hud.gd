extends CanvasLayer

# ─── VARS ─────────────────────────────────────────────────────────────────────
var gold := 0
var node_fragments := 0
var kill_count := 0
var skill_points := 0
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

# ── Tower counter ─────────────────────────────────────────────────────────────
var tower_label: Label

# ── Boss HP bar ───────────────────────────────────────────────────────────────
var boss_hp_bar_bg: ColorRect
var boss_hp_bar_fill: ColorRect
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

# ── Stats tracking ────────────────────────────────────────────────────────────
var stat_shots_fired    := 0
var stat_damage_taken   := 0
var stat_waves_survived := 0
var stat_bosses_killed  := 0
var stat_nodes_placed   := 0
var _stats_labels: Dictionary = {}

# ── Power-up gallery ──────────────────────────────────────────────────────────
var collected_powerups: Array = []   # filled in future when powerup system lands

var skill_names := [
	"Fire Rate", "Firepower", "Range", "Proj Speed",
	"Knockback", "Extra Shots", "Bounce", "Explode",
	"More Health", "Slow Enemies", "Gold Multiplier"
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

	gold_label.position  = Vector2(20, 20);  gold_label.add_theme_font_size_override("font_size", 18)
	node_label.position  = Vector2(20, 45);  node_label.add_theme_font_size_override("font_size", 18)
	kill_label.position  = Vector2(20, 70);  kill_label.add_theme_font_size_override("font_size", 18)
	sp_label.position    = Vector2(20, 95);  sp_label.add_theme_font_size_override("font_size", 18)

	health_label = Label.new()
	health_label.position = Vector2(20, 118);  health_label.text = "HP: 10 / 10"
	health_label.add_theme_font_size_override("font_size", 18);  add_child(health_label)

	hp_bar_bg = ColorRect.new();  hp_bar_bg.position = Vector2(20, 138)
	hp_bar_bg.size = Vector2(200, 14);  hp_bar_bg.color = Color(0.12, 0.12, 0.12);  add_child(hp_bar_bg)
	hp_bar_fill = ColorRect.new();  hp_bar_fill.position = Vector2(20, 138)
	hp_bar_fill.size = Vector2(200, 14);  hp_bar_fill.color = Color.GREEN;  add_child(hp_bar_fill)

	wave_label = Label.new();  wave_label.position = Vector2(20, 160);  wave_label.text = "Wave: 1"
	wave_label.add_theme_font_size_override("font_size", 18);  add_child(wave_label)
	boss_label = Label.new();  boss_label.position = Vector2(20, 180);  boss_label.text = "Boss in: 5 waves"
	boss_label.add_theme_font_size_override("font_size", 18);  add_child(boss_label)
	bt_label = Label.new();  bt_label.position = Vector2(20, 200);  bt_label.text = "BT: Ready"
	bt_label.add_theme_font_size_override("font_size", 18);  add_child(bt_label)
	tower_label = Label.new();  tower_label.position = Vector2(20, 220);  tower_label.text = "🏰  Towers: 0 / 5"
	tower_label.add_theme_font_size_override("font_size", 18);  tower_label.modulate = Color(1.0, 0.55, 0.15);  add_child(tower_label)

	pause_label = Label.new();  pause_label.text = "⏸";  pause_label.visible = false
	pause_label.add_theme_font_size_override("font_size", 24);  pause_label.modulate = Color.RED
	pause_label.position = Vector2(20, 246);  add_child(pause_label)

	cooldown_label = Label.new();  cooldown_label.position = Vector2(400, 10)
	cooldown_label.add_theme_font_size_override("font_size", 24);  cooldown_label.visible = false;  add_child(cooldown_label)

	boss_hp_label = Label.new();  boss_hp_label.position = Vector2(276, 8);  boss_hp_label.size = Vector2(400, 20)
	boss_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boss_hp_label.add_theme_font_size_override("font_size", 15);  boss_hp_label.modulate = Color(1.0, 0.6, 1.0)
	boss_hp_label.visible = false;  add_child(boss_hp_label)
	boss_hp_bar_bg = ColorRect.new();  boss_hp_bar_bg.position = Vector2(276, 30);  boss_hp_bar_bg.size = Vector2(400, 20)
	boss_hp_bar_bg.color = Color(0.12, 0.0, 0.18);  boss_hp_bar_bg.visible = false;  add_child(boss_hp_bar_bg)
	boss_hp_bar_fill = ColorRect.new();  boss_hp_bar_fill.position = Vector2(276, 30);  boss_hp_bar_fill.size = Vector2(400, 20)
	boss_hp_bar_fill.color = Color(0.5, 0.0, 0.85);  boss_hp_bar_fill.visible = false;  add_child(boss_hp_bar_fill)
	boss_warning_label = Label.new();  boss_warning_label.position = Vector2(150, 240);  boss_warning_label.size = Vector2(652, 70)
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

	var tier_btn = Button.new();  tier_btn.text = "MIN: Any";  tier_btn.process_mode = Node.PROCESS_MODE_ALWAYS
	tier_btn.pressed.connect(func():
		if auto_pause_min_cost == 1:    auto_pause_min_cost = 2; tier_btn.text = "MIN: 2sp+"
		elif auto_pause_min_cost == 2:  auto_pause_min_cost = 4; tier_btn.text = "MIN: 4sp+"
		elif auto_pause_min_cost == 4:  auto_pause_min_cost = 8; tier_btn.text = "MIN: 8sp"
		else:                           auto_pause_min_cost = 1; tier_btn.text = "MIN: Any"
	)
	skill_panel.add_child(tier_btn)

	var ap_btn = Button.new();  ap_btn.text = "⏸ AUTO";  ap_btn.toggle_mode = true
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
		var name_lbl := Label.new();  name_lbl.text = skill_names[i];  name_lbl.custom_minimum_size = Vector2(120, 0)
		var bars_lbl := Label.new();  bars_lbl.text = "░░░░░";          bars_lbl.custom_minimum_size = Vector2(60, 0)
		var cost_lbl := Label.new();  cost_lbl.text = "(1sp)";          cost_lbl.custom_minimum_size = Vector2(40, 0)
		var btn := Button.new();  btn.text = "+";  btn.process_mode = Node.PROCESS_MODE_ALWAYS
		var idx := i;  btn.pressed.connect(func(): _on_skill_selected(idx))
		row.add_child(name_lbl);  row.add_child(bars_lbl);  row.add_child(cost_lbl);  row.add_child(btn)
		skill_panel.add_child(row);  skill_rows.append(row)

	confirm_btn = Button.new();  confirm_btn.text = "CONFIRM UPGRADE"
	confirm_btn.pressed.connect(_on_confirm);  confirm_btn.process_mode = Node.PROCESS_MODE_ALWAYS
	skill_panel.add_child(confirm_btn)
	refresh_panel()

	var vp := get_viewport().get_visible_rect().size
	_skills_win   = _build_skills_window(vp)
	_tower_win    = _build_tower_window(vp)
	_placer_win   = _build_placer_window(vp)
	_powerups_win = _build_powerups_window(vp)
	_stats_win    = _build_stats_window(vp)
	_build_sidebar(vp)

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

	var close_btn := Button.new();  close_btn.text = "✕"
	close_btn.size = Vector2(26, 22);  close_btn.position = Vector2(win_size.x - 30, 5)
	close_btn.process_mode = Node.PROCESS_MODE_ALWAYS
	close_btn.add_theme_color_override("font_color", Color(1.0, 0.35, 0.35))
	close_btn.add_theme_font_size_override("font_size", 13)
	close_btn.pressed.connect(func(): chrome.visible = false)
	tb.add_child(close_btn)

	# ── Drag — use event.global_position (correct in CanvasLayer) ─────────────
	var dragging := false
	var drag_offset := Vector2.ZERO
	tb.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			dragging = event.pressed
			if dragging:
				drag_offset = chrome.position - event.global_position
		elif event is InputEventMouseMotion and dragging:
			chrome.position = event.global_position + drag_offset
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
	var result := _make_window("⚡  SKILLS", Vector2(370, 680), Vector2(vp.x - 560, 40), Color(0.3, 0.9, 1.0))
	var chrome: Panel = result[0]
	var body: Panel   = result[1]

	# ScrollContainer so it never clips even with many skills
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(0, 0)
	scroll.size = Vector2(370, 680 - 32)   # body height
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
	var result := _make_window("🏰  TOWER UPGRADES", Vector2(340, 260), Vector2(vp.x - 560, 740), Color(1.0, 0.65, 0.2))
	var chrome: Panel = result[0]
	var body: Panel   = result[1]

	var upgrade_defs := [
		["⚔️  Turret Damage",   "LV: 0"],
		["🛡  Shield Strength", "LV: 0"],
		["💎  Mine Yield",      "LV: 0"],
		["⚡  Fire Rate",       "LV: 0"],
	]
	for idx in range(upgrade_defs.size()):
		var row := HBoxContainer.new()
		row.position = Vector2(10, 8 + idx * 44);  row.custom_minimum_size = Vector2(316, 36)
		var lbl := Label.new();  lbl.text = upgrade_defs[idx][0];  lbl.custom_minimum_size = Vector2(190, 0)
		lbl.add_theme_font_size_override("font_size", 14);  lbl.add_theme_color_override("font_color", Color(0.85, 0.85, 0.9))
		var lvl_lbl := Label.new();  lvl_lbl.text = upgrade_defs[idx][1];  lvl_lbl.custom_minimum_size = Vector2(55, 0)
		lvl_lbl.add_theme_font_size_override("font_size", 14);  lvl_lbl.add_theme_color_override("font_color", Color(0.4, 0.9, 1.0))
		var up_btn := Button.new();  up_btn.text = "+";  up_btn.custom_minimum_size = Vector2(34, 28)
		up_btn.process_mode = Node.PROCESS_MODE_ALWAYS;  up_btn.add_theme_color_override("font_color", Color(0.4, 1.0, 0.5))
		row.add_child(lbl);  row.add_child(lvl_lbl);  row.add_child(up_btn);  body.add_child(row)

	return chrome

# ═══════════════════════════════════════════════════════════════════════════════
# ─── NODE PLACER WINDOW ───────────────────────────────────────────────────────
# ═══════════════════════════════════════════════════════════════════════════════
func _build_placer_window(vp: Vector2) -> Panel:
	var result := _make_window("🔧  NODE PLACER", Vector2(340, 160), Vector2(vp.x - 560, 1020), Color(0.5, 1.0, 0.5))
	var chrome: Panel = result[0]
	var body: Panel   = result[1]

	var note := Label.new();  note.text = "Place nodes on adjacent hexes during cooldown."
	note.position = Vector2(10, 8);  note.size = Vector2(316, 40)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size", 13);  note.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8))
	body.add_child(note)

	var btn_defs := [["⚔️  Turret","turret",Color(1.0,0.4,0.3)],["🛡  Shield","shield",Color(0.3,0.6,1.0)],["💎  Mine","mine",Color(0.3,1.0,0.85)]]
	for i in range(btn_defs.size()):
		var pb := Button.new();  pb.text = btn_defs[i][0];  pb.size = Vector2(90, 38)
		pb.position = Vector2(10 + i * 106, 60);  pb.process_mode = Node.PROCESS_MODE_ALWAYS
		pb.add_theme_color_override("font_color", btn_defs[i][2]);  pb.add_theme_font_size_override("font_size", 14)
		var t: String = btn_defs[i][1];  pb.pressed.connect(func(): selected_node_type = t)
		body.add_child(pb)

	return chrome

# ═══════════════════════════════════════════════════════════════════════════════
# ─── POWER-UPS GALLERY WINDOW ─────────────────────────────────────────────────
# ═══════════════════════════════════════════════════════════════════════════════
func _build_powerups_window(vp: Vector2) -> Panel:
	var result := _make_window("🎁  POWER-UPS FOUND", Vector2(480, 520), Vector2(vp.x - 700, 40), Color(1.0, 0.5, 1.0))
	var chrome: Panel = result[0]
	var body: Panel   = result[1]

	var empty_lbl := Label.new()
	empty_lbl.name = "EmptyLabel"
	empty_lbl.text = "No power-ups found yet.\nExplore the map and defeat enemies\nto discover power-ups!"
	empty_lbl.position = Vector2(20, 20);  empty_lbl.size = Vector2(440, 80)
	empty_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	empty_lbl.add_theme_font_size_override("font_size", 15)
	empty_lbl.add_theme_color_override("font_color", Color(0.55, 0.55, 0.65))
	body.add_child(empty_lbl)

	# Grid container for card tiles — populated by add_powerup_to_gallery()
	var grid := GridContainer.new()
	grid.name = "PowerupGrid"
	grid.columns = 4
	grid.position = Vector2(10, 110)
	grid.custom_minimum_size = Vector2(460, 380)
	grid.process_mode = Node.PROCESS_MODE_ALWAYS
	body.add_child(grid)

	return chrome

# Call this from powerup pickup logic in future sessions
func add_powerup_to_gallery(pu_name: String, pu_icon: String, pu_desc: String, pu_color: Color) -> void:
	if _powerups_win == null:
		return
	var body := _powerups_win.get_child(1)   # body is always second child after title bar
	var grid: GridContainer = body.get_node("PowerupGrid")
	var empty_lbl: Label = body.get_node("EmptyLabel")
	if is_instance_valid(empty_lbl):
		empty_lbl.visible = false

	var card := Panel.new()
	card.custom_minimum_size = Vector2(104, 110)
	var cs := StyleBoxFlat.new()
	cs.bg_color = Color(pu_color.r * 0.15, pu_color.g * 0.15, pu_color.b * 0.15, 1.0)
	cs.border_color = pu_color;  cs.set_border_width_all(1);  cs.set_corner_radius_all(4)
	card.add_theme_stylebox_override("panel", cs)

	var icon_lbl := Label.new();  icon_lbl.text = pu_icon
	icon_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon_lbl.position = Vector2(0, 8);  icon_lbl.size = Vector2(104, 36)
	icon_lbl.add_theme_font_size_override("font_size", 28);  card.add_child(icon_lbl)

	var name_lbl := Label.new();  name_lbl.text = pu_name
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.position = Vector2(2, 46);  name_lbl.size = Vector2(100, 24)
	name_lbl.add_theme_font_size_override("font_size", 11)
	name_lbl.add_theme_color_override("font_color", pu_color);  card.add_child(name_lbl)

	var desc_lbl := Label.new();  desc_lbl.text = pu_desc
	desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_lbl.position = Vector2(2, 70);  desc_lbl.size = Vector2(100, 36)
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.add_theme_font_size_override("font_size", 10)
	desc_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8));  card.add_child(desc_lbl)

	grid.add_child(card)
	collected_powerups.append({"name": pu_name, "icon": pu_icon, "desc": pu_desc})

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
	for i in skill_names.size():
		var row: HBoxContainer = skill_rows[i]
		var bars: Label = row.get_child(1);  var cost: Label = row.get_child(2)
		var dl: int = min(skill_levels[i], 5)
		bars.text = "█".repeat(dl) + "░".repeat(5 - dl) + " LV:" + str(skill_levels[i])
		cost.text = "(" + str(skill_kill_costs[i]) + "sp)"
		if i in pending_queue:                                             row.modulate = Color.YELLOW
		elif skill_points >= skill_kill_costs[i] and skill_levels[i] < 10: row.modulate = Color(0.5, 1.0, 0.5)
		else:                                                              row.modulate = Color.WHITE

# ─── ECONOMY ──────────────────────────────────────────────────────────────────
func add_gold(amount: int) -> void:
	gold += amount;  gold_label.text = "Gold: " + str(gold)

func add_node_fragment(amount: int) -> void:
	node_fragments += amount;  node_label.text = "Upgrades: " + str(node_fragments)

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
func _on_skill_selected(index: int) -> void:
	if skill_levels[index] >= 10: return
	var qc := 0;  for q in pending_queue: qc += skill_kill_costs[q]
	if skill_points >= qc + skill_kill_costs[index]:
		pending_queue.append(index);  call_deferred("refresh_panel")

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
	pending_queue.clear();  call_deferred("refresh_panel")
	if auto_pause_enabled and not _can_afford_any(): get_tree().paused = false

# ─── PROCESS ──────────────────────────────────────────────────────────────────
func _process(delta: float) -> void:
	var gm_lvl = skill_levels[10]
	if gm_lvl >= 4:
		passive_timer += delta
		if passive_timer >= 1.0: passive_timer = 0.0; add_gold(gm_lvl - 3)

func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed: return
	var go := game_over_panel != null and is_instance_valid(game_over_panel)
	var wi := win_panel != null and is_instance_valid(win_panel)
	if go or wi:
		Engine.time_scale = 1.0;  get_tree().paused = false;  get_tree().reload_current_scene();  return
	if event.keycode == KEY_TAB:
		get_tree().paused = !get_tree().paused;  pause_label.visible = get_tree().paused
	if event.keycode == KEY_G:
		var player = get_parent().get_node("Player")
		player.current_hp = 99999.0;  player.max_hp = 99999.0;  update_health(99999, 99999)
	if event.keycode == KEY_F:
		skill_points += 50;  call_deferred("refresh_panel")

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
func update_health(current: float, max_val: float) -> void:
	health_label.text = "HP: " + str(int(current)) + " / " + str(int(max_val))
	var r := clampf(current / max_val, 0.0, 1.0) if max_val > 0 else 0.0
	hp_bar_fill.size.x = 200.0 * r
	if r > 0.6: hp_bar_fill.color = Color(0.1,0.85,0.15)
	elif r > 0.3: hp_bar_fill.color = Color(1.0,0.8,0.0)
	else: hp_bar_fill.color = Color(0.9,0.1,0.1)
	stat_damage_taken += (1.0 - r) * 0.1  # rough accumulation

func update_cooldown(time_left: float) -> void:
	cooldown_label.text = "Next Wave: " + str(int(time_left)) + "s"
	if time_left <= 0.0: cooldown_label.visible = false

func start_cooldown(duration: float) -> void:
	get_tree().paused = false;  pause_label.visible = false
	cooldown_label.visible = true;  cooldown_label.text = "Next Wave: " + str(int(duration)) + "s"
	stat_waves_survived += 1
	show_placement_panel()

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
	win_panel.modulate = Color(0,0,0,0.88);  win_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	var msg := Label.new();  msg.text = "🏆  YOU WIN!\nVEXAGON CONQUERED!"
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER;  msg.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	msg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	msg.add_theme_font_size_override("font_size", 42);  msg.add_theme_color_override("font_color", Color.GOLD)
	var sub := Label.new();  sub.text = "All 10 Boss Ranks defeated.\nPress any key to play again."
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sub.add_theme_font_size_override("font_size", 22);  sub.add_theme_color_override("font_color", Color.WHITE)
	sub.position.y = 80;  win_panel.add_child(msg);  win_panel.add_child(sub);  add_child(win_panel)

func show_game_over() -> void:
	get_tree().paused = true;  game_over_panel = Panel.new()
	game_over_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game_over_panel.modulate = Color(0,0,0,0.85);  game_over_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	var msg := Label.new();  msg.text = "Aww! Don't give up!\nRebuild your Tower and try again!"
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER;  msg.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	msg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	msg.add_theme_font_size_override("font_size", 36);  msg.add_theme_color_override("font_color", Color.RED)
	var hint := Label.new();  hint.text = "Press any key to restart"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER;  hint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hint.add_theme_font_size_override("font_size", 20);  hint.add_theme_color_override("font_color", Color.WHITE)
	hint.position.y = 60;  game_over_panel.add_child(msg);  game_over_panel.add_child(hint);  add_child(game_over_panel)

func show_placement_panel() -> void:
	if _placer_win != null: _placer_win.visible = true

func hide_placement_panel() -> void:
	selected_node_type = ""
