extends MinigameBase
## 占位小游戏：时机条。光标来回移动，按 确认（空格/J/手柄 A）时越靠近中心越好。
## 正式的第 1/2/5/6 组在 T4~T7 实装后替换。

const BAR_W := 900.0
var pos := 0.0
var dir := 1.0
var speed := 0.8
var good_w := 0.3
var perfect_w := 0.1
var cursor: ColorRect
var bar_x := 0.0

func _begin() -> void:
	speed = config.speed * (1.0 + difficulty * 0.15)
	good_w = clampf(config.good_width / (1.0 + difficulty * 0.2), 0.06, 0.6)
	perfect_w = good_w * config.perfect_ratio
	var vs := get_viewport_rect().size
	bar_x = vs.x / 2 - BAR_W / 2
	var y := vs.y / 2 - 30
	UI.rect(self, Vector2(0, y - 120), Vector2(vs.x, 260), Color(0, 0, 0, 0.6))
	var verb := "出手" if config.kind == "attack" else "格挡"
	UI.label(self, "%s —— 按 空格 / 手柄A %s！（难度 %.1f）" % [config.display_name, verb, difficulty], Vector2(bar_x, y - 100), 32)
	UI.rect(self, Vector2(bar_x, y), Vector2(BAR_W, 60), Color(0.35, 0.15, 0.15))
	UI.rect(self, Vector2(bar_x + BAR_W * (0.5 - good_w / 2), y), Vector2(BAR_W * good_w, 60), Color(0.8, 0.7, 0.2))
	UI.rect(self, Vector2(bar_x + BAR_W * (0.5 - perfect_w / 2), y), Vector2(BAR_W * perfect_w, 60), Color(0.3, 0.9, 0.4))
	cursor = UI.rect(self, Vector2(bar_x, y - 15), Vector2(12, 90), Color.WHITE)

func _tick(delta: float) -> void:
	pos += dir * speed * delta
	if pos >= 1.0:
		pos = 1.0
		dir = -1.0
	elif pos <= 0.0:
		pos = 0.0
		dir = 1.0
	cursor.position.x = bar_x + BAR_W * pos - 6

func _unhandled_input(e: InputEvent) -> void:
	if active and e.is_action_pressed("mg_action"):
		get_viewport().set_input_as_handled()
		evaluate(pos)

func evaluate(p: float) -> void:
	var dist := absf(p - 0.5)
	var r := Result.FAIL
	if dist <= perfect_w / 2:
		r = Result.PERFECT
	elif dist <= good_w / 2:
		r = Result.GOOD
	_finish(r, clampf(1.0 - dist / 0.5, 0.0, 1.0))
