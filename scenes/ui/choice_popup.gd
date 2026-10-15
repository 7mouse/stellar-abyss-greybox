class_name ChoicePopup
extends CanvasLayer
## 通用暂停弹窗：标题 + 若干按钮（手柄/键盘可选）。选择期间暂停游戏。

signal chosen(index: int)

var title := ""
var options: Array = [] ## [{text, enabled}]
var buttons: Array[Button] = []
var auto_index := -1

static func open(parent: Node, p_title: String, p_options: Array, auto := -1) -> ChoicePopup:
	var p := ChoicePopup.new()
	p.title = p_title
	p.options = p_options
	p.auto_index = auto
	parent.add_child(p)
	return p

func _ready() -> void:
	layer = 60
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = true
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var pp := UI.popup(root, title)
	for i in options.size():
		var o: Dictionary = options[i]
		var b := UI.button(pp.box, o.text, _pick.bind(i), Vector2(900, 80))
		b.disabled = not o.get("enabled", true)
		buttons.append(b)
	for b in buttons:
		if not b.disabled:
			b.grab_focus.call_deferred()
			break
	if auto_index >= 0:
		_pick.call_deferred(auto_index)

func _pick(i: int) -> void:
	if is_queued_for_deletion():
		return
	get_tree().paused = false
	chosen.emit(i)
	queue_free()
