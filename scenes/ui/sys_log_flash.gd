extends CanvasLayer
## 系统日志闪现（autoload SysLog）：左上角绿字，显示 log_flash_sec 秒，期间 2 帧横向错位 ±6px。不拦截输入。

var label: Label
var shown_at := -1.0
var last_text := ""
var last_duration := 0.0 ## 测试：上次实际显示时长（秒）
var _frames := 0

func _ready() -> void:
	layer = 95
	process_mode = Node.PROCESS_MODE_ALWAYS
	label = Label.new()
	label.position = Vector2(24, 18)
	label.add_theme_font_size_override("font_size", 26)
	label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.45))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.visible = false
	add_child(label)

func flash(text: String) -> void:
	last_text = text
	label.text = text
	label.visible = true
	label.position.x = 24
	shown_at = Time.get_ticks_usec() / 1e6
	_frames = 0

func is_showing() -> bool:
	return label.visible

func _process(_d: float) -> void:
	if not label.visible:
		return
	_frames += 1
	label.position.x = 24 + (Game.clues.log_jitter_px * (1 if _frames == 2 else -1) if _frames in [2, 3] else 0.0)
	var el := Time.get_ticks_usec() / 1e6 - shown_at
	if el >= Game.clues.log_flash_sec:
		label.visible = false
		last_duration = el
