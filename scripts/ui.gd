class_name UI
extends RefCounted
## 灰盒 UI 小工具：色块、标签、按钮、弹窗

static func rect(parent: Node, pos: Vector2, size: Vector2, color: Color) -> ColorRect:
	var r := ColorRect.new()
	r.position = pos
	r.size = size
	r.color = color
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(r)
	return r

static func label(parent: Node, text: String, pos: Vector2, font_size: int = 32, color: Color = Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l

static func button(parent: Node, text: String, cb: Callable, min_size := Vector2(320, 72), bg := Color(0.25, 0.3, 0.4)) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.add_theme_font_size_override("font_size", 30)
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = bg
		match st:
			"hover": sb.bg_color = bg.lightened(0.2)
			"pressed": sb.bg_color = bg.darkened(0.2)
			"disabled": sb.bg_color = bg.darkened(0.55)
			"focus":
				sb.draw_center = false
				sb.border_color = Color(1, 0.9, 0.3)
				sb.set_border_width_all(5)
		b.add_theme_stylebox_override(st, sb)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b

## 居中弹窗：返回 {panel, box}
static func popup(parent: Node, title: String) -> Dictionary:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	parent.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.add_child(center)
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.13, 0.17)
	sb.set_content_margin_all(40)
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 24)
	panel.add_child(box)
	var l := Label.new()
	l.text = title
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 36)
	box.add_child(l)
	return {"panel": dim, "box": box}
