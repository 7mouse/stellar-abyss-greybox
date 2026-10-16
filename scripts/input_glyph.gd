class_name InputGlyph
extends RefCounted
## 当前输入设备。提示文字按最近一次键盘/鼠标或手柄事件切换。

static var device := "kb"

static func note(e: InputEvent) -> void:
	if e is InputEventKey or e is InputEventMouseButton or e is InputEventMouseMotion:
		device = "kb"
	elif e is InputEventJoypadButton:
		device = "pad"
	elif e is InputEventJoypadMotion and absf((e as InputEventJoypadMotion).axis_value) > 0.35:
		device = "pad"

static func using_pad() -> bool:
	return device == "pad"

static func move() -> String:
	return "左摇杆" if device == "pad" else "WASD"

static func attack() -> String:
	return "X" if device == "pad" else "J"

static func dash() -> String:
	return "A" if device == "pad" else "空格"

static func interact() -> String:
	return "B" if device == "pad" else "E"

static func skill() -> String:
	return "Y" if device == "pad" else "K"
