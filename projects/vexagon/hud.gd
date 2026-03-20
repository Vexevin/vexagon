extends CanvasLayer

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


var skill_names := [
	"Fire Rate", "Firepower", "Range", "Proj Speed",
	"Knockback", "Extra Shots", "Bounce", "Explode",
	"More Health", "Slow Enemies", "Gold Multiplier"
]
var skill_levels := []
var skill_kill_costs := []
var skill_rows := []

@onready var gold_label: Label = $GoldLabel
@onready var node_label: Label = $UpgradeLabel
@onready var kill_label: Label = $KillLabel
@onready var sp_label: Label = $SPLabel
@onready var skill_panel: VBoxContainer = $SkillPanel

var confirm_btn: Button

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	gold_label.position = Vector2(20, 20)
	gold_label.add_theme_font_size_override("font_size", 18)
	node_label.position = Vector2(20, 45)
	node_label.add_theme_font_size_override("font_size", 18)
	kill_label.position = Vector2(20, 70)
	kill_label.add_theme_font_size_override("font_size", 18)
	sp_label.position = Vector2(20, 95)
	sp_label.add_theme_font_size_override("font_size", 18)
	skill_panel.position = Vector2(840, 10)
	var ap_btn = Button.new()
	ap_btn.text = "⏸ AUTO"
	ap_btn.toggle_mode = true
	ap_btn.button_pressed = false
	var ap_dot = Label.new()
	ap_dot.text = " ● INACTIVE"
	ap_dot.modulate = Color.RED
	skill_panel.add_child(ap_dot)
	var tier_btn = Button.new()
	tier_btn.text = "MIN: Any"
	tier_btn.process_mode = Node.PROCESS_MODE_ALWAYS
	tier_btn.pressed.connect(func():
		if auto_pause_min_cost == 1:
			auto_pause_min_cost = 2
			tier_btn.text = "MIN: 2sp+"
		elif auto_pause_min_cost == 2:
			auto_pause_min_cost = 4
			tier_btn.text = "MIN: 4sp+"
		elif auto_pause_min_cost == 4:
			auto_pause_min_cost = 8
			tier_btn.text = "MIN: 8sp"
		else:
			auto_pause_min_cost = 1
			tier_btn.text = "MIN: Any"
	)
	skill_panel.add_child(tier_btn)
	ap_btn.modulate = Color.RED
	ap_btn.toggled.connect(func(pressed):
		auto_pause_enabled = pressed
		if pressed:
			ap_btn.modulate = Color.GREEN
			ap_dot.text = " ● ACTIVE"
			ap_dot.modulate = Color.GREEN
		else:
			ap_btn.modulate = Color.RED
			ap_dot.text = " ● INACTIVE"
			ap_dot.modulate = Color.RED
	)
	skill_panel.add_child(ap_btn)  
	cooldown_label = Label.new()  
	cooldown_label.position = Vector2(400, 10)  
	cooldown_label.add_theme_font_size_override("font_size", 24)  
	cooldown_label.visible = false 
	pause_label = Label.new()
	pause_label.text = "⏸"
	pause_label.visible = false
	pause_label.add_theme_font_size_override("font_size", 120)
	pause_label.modulate = Color.RED
	pause_label.position = Vector2(440, 200)
	add_child(pause_label)
	add_child(cooldown_label)
	health_label = Label.new()
	health_label.position = Vector2(20, 120)
	health_label.text = "HP: 10 / 10"
	wave_label = Label.new()
	wave_label.position = Vector2(20, 145)
	wave_label.text = "Wave: 1"
	add_child(wave_label)
	wave_label.add_theme_font_size_override("font_size", 18)
	boss_label = Label.new()
	boss_label.position = Vector2(20, 165)
	boss_label.text = "Boss in: 5 waves"
	add_child(boss_label)
	boss_label.add_theme_font_size_override("font_size", 18)
	bt_label = Label.new()
	bt_label.position = Vector2(20, 185)
	bt_label.text = "BT: Ready"
	add_child(bt_label)
	bt_label.add_theme_font_size_override("font_size", 18)
	add_child(health_label)
	health_label.add_theme_font_size_override("font_size", 18)
	for i in skill_names.size():
		skill_levels.append(0)
		skill_kill_costs.append(1)

	# Build skill rows in code
	for i in skill_names.size():
		var row := HBoxContainer.new()
		var name_lbl := Label.new()
		name_lbl.text = skill_names[i]
		name_lbl.custom_minimum_size = Vector2(120, 0)
		var bars_lbl := Label.new()
		bars_lbl.text = "░░░░░"
		bars_lbl.custom_minimum_size = Vector2(60, 0)
		var cost_lbl := Label.new()
		cost_lbl.text = "(1sp)"
		cost_lbl.custom_minimum_size = Vector2(40, 0)
		var btn := Button.new()
		btn.text = "+"
		btn.process_mode = Node.PROCESS_MODE_ALWAYS
		var idx := i
		btn.pressed.connect(func(): _on_skill_selected(idx))
		row.add_child(name_lbl)
		row.add_child(bars_lbl)
		row.add_child(cost_lbl)
		row.add_child(btn)
		skill_panel.add_child(row)
		skill_rows.append(row)

	confirm_btn = Button.new()
	confirm_btn.text = "CONFIRM UPGRADE"
	confirm_btn.pressed.connect(_on_confirm)
	skill_panel.add_child(confirm_btn)
	confirm_btn.process_mode = Node.PROCESS_MODE_ALWAYS
	refresh_panel()

func refresh_panel() -> void:
	sp_label.text = "Skill Points: " + str(skill_points)
	for i in skill_names.size():
		var row: HBoxContainer = skill_rows[i]
		var bars: Label = row.get_child(1)
		var cost: Label = row.get_child(2)
		var display_lvl: int = min(skill_levels[i], 5)
		var filled := "█".repeat(display_lvl)
		var empty := "░".repeat(5 - display_lvl)
		bars.text = filled + empty + " LV:" + str(skill_levels[i])
		cost.text = "(" + str(skill_kill_costs[i]) + "sp)"
		if i in pending_queue:
			row.modulate = Color.YELLOW
			row.modulate = Color.YELLOW
		elif skill_points >= skill_kill_costs[i] and skill_levels[i] < 10:
			row.modulate = Color(0.5, 1.0, 0.5)
		else:
			row.modulate = Color.WHITE

func add_gold(amount: int) -> void:
	gold += amount
	gold_label.text = "Gold: " + str(gold)
	
func add_node_fragment(amount: int) -> void:
	node_fragments += amount
	node_label.text = "Upgrades: " + str(node_fragments)

func add_kill() -> void:
	kill_count += 1
	kill_label.text = "Kills: " + str(kill_count)
	if kill_count > 0 and kill_count % 5 == 0:
		skill_points += 1
		call_deferred("refresh_panel")
		if auto_pause_enabled:
			_check_auto_pause()
		
func _on_skill_selected(index: int) -> void:
	if skill_levels[index] >= 10:
		return
	var queue_cost = 0
	for q in pending_queue:
		queue_cost += skill_kill_costs[q]
	var next_cost = skill_kill_costs[index]
	if skill_points >= queue_cost + next_cost:
		pending_queue.append(index)
		call_deferred("refresh_panel")
		
func _on_confirm() -> void:
	if pending_queue.is_empty():
		return
	for index in pending_queue:
		if skill_points < skill_kill_costs[index]:
			break
		skill_points -= skill_kill_costs[index]
		skill_levels[index] += 1
		var lvl: int = skill_levels[index]
		if lvl < 4:
			skill_kill_costs[index] = 1
		elif lvl < 7:
			skill_kill_costs[index] = 2
		elif lvl < 10:
			skill_kill_costs[index] = 4
		else:
			skill_kill_costs[index] = 8
	pending_queue.clear()
	call_deferred("refresh_panel")
	var queue_cost = 0
	for q in pending_queue:
		queue_cost += skill_kill_costs[q]
	confirm_btn.text = "CONFIRM (" + str(queue_cost) + "sp)" if queue_cost > 0 else "CONFIRM UPGRADE"
	if auto_pause_enabled and not _can_afford_any():
		get_tree().paused = false

func _process(delta: float) -> void:
	var gm_lvl = skill_levels[10]
	if gm_lvl >= 4:
		passive_timer += delta
		var interval = 1.0
		var passive_gold = gm_lvl - 3
		if passive_timer >= interval:
			passive_timer = 0.0
			add_gold(passive_gold)

func _input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	if not event.pressed:
		return
	if game_over_panel != null and is_instance_valid(game_over_panel):
		Engine.time_scale = 1.0
		get_tree().paused = false
		get_tree().reload_current_scene()
		return
	if event.keycode == KEY_TAB:
		get_tree().paused = !get_tree().paused
		pause_label.visible = get_tree().paused
	if event.keycode == KEY_I:
		$SkillPanel.visible = !$SkillPanel.visible
		get_tree().paused = $SkillPanel.visible
		pause_label.visible = get_tree().paused
	if event.keycode == KEY_G:
		var player = get_parent().get_node("Player")
		player.current_hp = 99999.0
		player.max_hp = 99999.0
		update_health(99999, 99999)
	if event.keycode == KEY_F:
		skill_points += 50
		call_deferred("refresh_panel")
			
func _check_auto_pause() -> void:
	if _can_afford_any():
		get_tree().paused = true
		$SkillPanel.visible = true
			
func start_cooldown(duration: float) -> void:
	get_tree().paused = false
	pause_label.visible = false
	cooldown_label.visible = true
	cooldown_label.text = "Next Wave: " + str(int(duration)) + "s"

func update_cooldown(time_left: float) -> void:
	cooldown_label.text = "Next Wave: " + str(int(time_left)) + "s"
	if time_left <= 0.0:
		cooldown_label.visible = false
func _can_afford_any() -> bool:
	for i in range(skill_kill_costs.size()):
		if skill_levels[i] < 10 and skill_points >= skill_kill_costs[i] and skill_kill_costs[i] >= auto_pause_min_cost:
			return true
	return false
	
func update_health(current: float, max_val: float) -> void:
	health_label.text = "HP: " + str(int(current)) + " / " + str(int(max_val))
	
func update_wave_info(wave: int, bt_active: bool, bt_timer: float, bt_recharge: float) -> void:
	wave_label.text = "Wave: " + str(wave)
	var waves_to_boss = 5 - ((wave - 1) % 5)
	boss_label.text = "Boss in: " + str(waves_to_boss) + " waves"
	if bt_active:
		bt_label.text = "BT: " + str(snappedf(bt_timer / 10.0, 0.1)) + "s"
	elif bt_recharge > 0:
		bt_label.text = "BT: " + str(snappedf(bt_recharge, 0.1)) + "s recharge"
	else:
		bt_label.text = "BT: Ready"
		
func show_game_over() -> void:
	get_tree().paused = true
	game_over_panel = Panel.new()
	game_over_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game_over_panel.modulate = Color(0, 0, 0, 0.85)
	game_over_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	var msg = Label.new()
	msg.text = "Aww! Don't give up!\nRebuild your Tower and try again!"
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	msg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	msg.add_theme_font_size_override("font_size", 36)
	msg.modulate = Color.RED
	var hint = Label.new()
	hint.text = "Press any key to restart"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hint.add_theme_font_size_override("font_size", 20)
	hint.modulate = Color.WHITE
	hint.position.y = 60
	game_over_panel.add_child(msg)
	game_over_panel.add_child(hint)
	add_child(game_over_panel)
