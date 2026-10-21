class_name SettingsControls
extends RefCounted
## 暂停菜单和村落里的设置条：镜头震动、顿帧。教学重置由新手引导补上。

static func fill(box: VBoxContainer) -> void:
	for c in box.get_children():
		c.queue_free()
	var shake := Button.new()
	shake.focus_mode = Control.FOCUS_ALL
	shake.custom_minimum_size = Vector2(420, 64)
	shake.add_theme_font_size_override("font_size", 28)
	shake.text = _shake_text()
	shake.pressed.connect(func() -> void:
		var order: Array[int] = [100, 50, 0]
		var i := order.find(Settings.camera_shake)
		var n: int = order[(i + 1) % order.size()] if i >= 0 else 100
		Settings.set_camera_shake(n)
		shake.text = _shake_text()
	)
	box.add_child(shake)
	var hs := CheckBox.new()
	hs.focus_mode = Control.FOCUS_ALL
	hs.add_theme_font_size_override("font_size", 28)
	hs.text = "顿帧"
	hs.button_pressed = Settings.hitstop_enabled
	hs.toggled.connect(func(v: bool) -> void: Settings.set_hitstop_enabled(v))
	box.add_child(hs)
	_slider(box, "主音量", "master", Settings.vol_master)
	_slider(box, "音乐", "music", Settings.vol_music)
	_slider(box, "音效", "sfx", Settings.vol_sfx)
	_slider(box, "环境", "ambience", Settings.vol_ambience)
	var reset := Button.new()
	reset.focus_mode = Control.FOCUS_ALL
	reset.custom_minimum_size = Vector2(420, 64)
	reset.add_theme_font_size_override("font_size", 28)
	reset.text = "重置教学"
	reset.pressed.connect(func() -> void:
		Tutorial.reset_progress()
		reset.text = "教学已重置"
	)
	box.add_child(reset)

static func _slider(box: VBoxContainer, label: String, bus: String, value: float) -> void:
	var l := Label.new()
	l.text = label
	l.add_theme_font_size_override("font_size", 24)
	box.add_child(l)
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 100.0
	s.step = 1.0
	s.value = value * 100.0
	s.custom_minimum_size = Vector2(420, 36)
	s.focus_mode = Control.FOCUS_ALL
	s.value_changed.connect(func(v: float) -> void: Settings.set_bus_volume(bus, v / 100.0))
	box.add_child(s)

static func _shake_text() -> String:
	return "镜头震动 %d%%" % Settings.camera_shake
