extends MinigameBase
## 普通攻击时机条（C1）：指针从左到右扫一次（qte_sec），中点为最佳时机。
## 距中点 ±qte_perfect_ms 内 PERFECT，±qte_good_ms 内 GOOD，其余或超时 FAIL。
## 第 6 组营地升级的 window_mult 同样放大两个区间。不播预兆。

const BAR_W := 800.0
var cfg: TimingConfig
var t := 0.0
var center := 0.4
var perfect_w := 0.06
var good_w := 0.15
var cursor: ColorRect
var bar_x := 0.0
var result_label: Label

func _begin() -> void:
	cfg = config as TimingConfig
	var wm := float(context.get("window_mult", 1.0))
	center = cfg.qte_sec / 2.0
	perfect_w = cfg.qte_perfect_ms / 1000.0 * wm
	good_w = cfg.qte_good_ms / 1000.0 * wm
	var vs := get_viewport_rect().size
	bar_x = vs.x / 2 - BAR_W / 2
	var y := vs.y / 2 + 120
	var px := BAR_W / cfg.qte_sec ## 每秒多少像素
	UI.rect(self, Vector2(bar_x - 20, y - 70), Vector2(BAR_W + 40, 150), Color(0, 0, 0, 0.6))
	UI.label(self, "斩击！指针到中间时按 空格/手柄A", Vector2(bar_x, y - 62), 26)
	UI.rect(self, Vector2(bar_x, y), Vector2(BAR_W, 40), Color(0.35, 0.15, 0.15))
	UI.rect(self, Vector2(bar_x + (center - good_w) * px, y), Vector2(good_w * 2 * px, 40), Color(0.85, 0.7, 0.2))
	UI.rect(self, Vector2(bar_x + (center - perfect_w) * px, y), Vector2(perfect_w * 2 * px, 40), Color(0.3, 0.9, 0.4))
	cursor = UI.rect(self, Vector2(bar_x, y - 10), Vector2(8, 60), Color.WHITE)
	result_label = UI.label(self, "", Vector2(bar_x + BAR_W + 30, y), 32)

func _tick(delta: float) -> void:
	t += delta
	cursor.position.x = bar_x + clampf(t / cfg.qte_sec, 0.0, 1.0) * BAR_W - 4
	if t >= cfg.qte_sec:
		_finish(Result.FAIL, 0.0)

## 在扫描开始后第 at 秒按下
func press_at(at: float) -> void:
	var off := absf(at - center)
	var r := Result.FAIL
	if off <= perfect_w:
		r = Result.PERFECT
	elif off <= good_w:
		r = Result.GOOD
	result_label.text = RESULT_CN[r]
	_finish(r, clampf(1.0 - off / center, 0.0, 1.0))

func _unhandled_input(e: InputEvent) -> void:
	if active and not e.is_echo() and e.is_action_pressed("mg_action"):
		get_viewport().set_input_as_handled()
		press_at(t)

func _on_timeout() -> void:
	pass
