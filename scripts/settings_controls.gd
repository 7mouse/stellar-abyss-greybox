class_name SettingsControls
extends RefCounted
## 暂停菜单里的设置条：镜头震动、顿帧。

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

static func _shake_text() -> String:
	return "镜头震动 %d%%" % Settings.camera_shake
