class_name Panel2
extends CanvasLayer
## 村里设施的通用面板：标题 + 内容，暂停游戏；ui_cancel 或“关闭”退出

signal closed

var title := ""
var box: VBoxContainer
var body: VBoxContainer

func _ready() -> void:
	Audio.sfx("SFX-43")
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = true
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var pp := UI.popup(root, title)
	box = pp.box
	body = VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	box.add_child(body)
	UI.button(box, "关闭", close, Vector2(300, 64))
	rebuild()

func rebuild() -> void:
	for c in body.get_children():
		body.remove_child(c)
		c.queue_free()
	_fill()
	_focus_first.call_deferred()

func _focus_first() -> void:
	for c in box.find_children("*", "Button", true, false):
		if not c.disabled and c.is_inside_tree() and not c.is_queued_for_deletion():
			c.grab_focus()
			return

func _fill() -> void:
	pass

func text(t: String, size := 26, color := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	body.add_child(l)
	return l

func btn(t: String, cb: Callable, enabled := true) -> Button:
	var b := UI.button(body, t, cb, Vector2(900, 56))
	b.add_theme_font_size_override("font_size", 24)
	b.disabled = not enabled
	return b

func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()

func close() -> void:
	if is_queued_for_deletion():
		return
	Audio.sfx("SFX-43")
	get_tree().paused = false
	closed.emit()
	queue_free()
