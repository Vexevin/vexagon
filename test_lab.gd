extends Node2D

func _ready() -> void:
	GameState.flip_started.connect(_on_flip_started)
	_build_menu()

func _build_menu() -> void:
	var panel = PanelContainer.new()
	panel.position = Vector2(20, 20)
	panel.size = Vector2(220, 400)
	get_node("HUD").add_child(panel)
	var vbox = VBoxContainer.new()
	panel.add_child(vbox)
	_add_button(vbox, "⚠ Show WARNING", _test_warning)
	_add_button(vbox, "🌀 Trigger Flip", _test_flip)
	_add_button(vbox, "💥 Fireworks", _test_fireworks)
	_add_button(vbox, "⏱ Bullet Time", _test_bullet_time)

func _add_button(parent: Node, label: String, callback: Callable) -> void:
	var btn = Button.new()
	btn.text = label
	btn.pressed.connect(callback)
	parent.add_child(btn)

func _test_warning() -> void:
	_show_warning()

func _test_flip() -> void:
	GameState.flip_started.emit()

func _test_fireworks() -> void:
	print("Fireworks triggered")

func _test_bullet_time() -> void:
	Engine.time_scale = 0.15
	get_tree().create_timer(2.0, true, false, true).timeout.connect(func():
		Engine.time_scale = 1.0)

func _on_flip_started() -> void:
	_show_warning()

func _show_warning() -> void:
	var hud = get_node("HUD")
	var warning = ColorRect.new()
	warning.color = Color(0.8, 0.0, 0.0, 0.3)
	warning.set_anchors_preset(Control.PRESET_FULL_RECT)
	warning.mouse_filter = Control.MOUSE_FILTER_IGNORE
	warning.z_index = 100
	hud.add_child(warning)
	var warn_label = Label.new()
	warn_label.text = "⚠  WARNING  ⚠"
	warn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	warn_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	warn_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	warn_label.add_theme_font_size_override("font_size", 72)
	warn_label.modulate = Color(1.0, 0.1, 0.1, 1.0)
	warn_label.z_index = 101
	hud.add_child(warn_label)
	for _i in range(6):
		var tw = get_tree().create_tween()
		tw.tween_property(warning, "color", Color(0.8, 0.0, 0.0, 0.5), 0.3)
		tw.tween_property(warning, "color", Color(0.8, 0.0, 0.0, 0.05), 0.3)
		await tw.finished
	warning.queue_free()
	warn_label.queue_free()
