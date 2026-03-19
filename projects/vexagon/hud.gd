extends CanvasLayer

var gold := 0
var node_fragments := 0
var kill_count := 0
var skill_points := 0
var pending_skill := -1
var auto_pause_enabled: bool = false
var cooldown_label: Label
var passive_timer := 0.0

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
	node_label.position = Vector2(20, 45)
	kill_label.position = Vector2(20, 70)
	sp_label.position = Vector2(20, 95)
	skill_panel.position = Vector2(840, 10)
	var ap_btn = Button.new()
	ap_btn.text = "⏸ AUTO"
	ap_btn.toggle_mode = true
	ap_btn.button_pressed = false
	ap_btn.toggled.connect(func(pressed): auto_pause_enabled = pressed)
	skill_panel.add_child(ap_btn)
	cooldown_label = Label.new()
	cooldown_label.position = Vector2(10, 165)
	cooldown_label.visible = false
	add_child(cooldown_label)

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
		var filled := "█".repeat(skill_levels[i])
		var empty := "░".repeat(5 - min(skill_levels[i], 5))
		bars.text = filled + empty
		cost.text = "(" + str(skill_kill_costs[i]) + "sp)"
		if i == pending_skill:
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
	pending_skill = index
	call_deferred("refresh_panel")

func _on_confirm() -> void:
	if pending_skill == -1:
		return
	if skill_points < skill_kill_costs[pending_skill]:
		return
	skill_points -= skill_kill_costs[pending_skill]
	skill_levels[pending_skill] += 1
	var lvl: int = skill_levels[pending_skill]
	if lvl < 4:
		skill_kill_costs[pending_skill] = 1
	elif lvl < 7:
		skill_kill_costs[pending_skill] = 2
	elif lvl < 10:
		skill_kill_costs[pending_skill] = 4
	else:
		skill_kill_costs[pending_skill] = 8
	pending_skill = -1
	call_deferred("refresh_panel")
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
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE or event.keycode == KEY_P:
			get_tree().paused = !get_tree().paused
			
func _check_auto_pause() -> void:
	if _can_afford_any():
		get_tree().paused = true
		$SkillPanel.visible = true
			
func start_cooldown(duration: float) -> void:
	get_tree().paused = false
	cooldown_label.visible = true
	cooldown_label.text = "Next Wave: " + str(int(duration)) + "s"

func update_cooldown(time_left: float) -> void:
	cooldown_label.text = "Next Wave: " + str(int(time_left)) + "s"
	if time_left <= 0.0:
		cooldown_label.visible = false
func _can_afford_any() -> bool:
	for i in range(skill_kill_costs.size()):
		if skill_levels[i] < 10 and skill_points >= skill_kill_costs[i]:
			return true
	return false
