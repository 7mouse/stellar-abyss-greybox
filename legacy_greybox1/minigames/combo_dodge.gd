extends MinigameBase
## T4 第 1 组 连击闪避/格挡：敌人连续出招 N 次，每次闪出一个方向键/格挡键，需在窗口内按对。
## 全对 PERFECT，错 1 次 GOOD，否则 FAIL。参数每次 start 时从配置读取，调试面板改动下一次即生效。

const KEYS := ["move_up", "move_down", "move_left", "move_right", "mg_action"]
const KEY_TEXT := {"move_up": "↑", "move_down": "↓", "move_left": "←", "move_right": "→", "mg_action": "格挡"}
const KEY_HINT := {"move_up": "W/↑/十字上", "move_down": "S/↓/十字下", "move_left": "A/←/十字左", "move_right": "D/→/十字右", "mg_action": "空格/手柄A"}

var cfg: ComboConfig
var hits := 3
var window := 0.6
var interval := 0.3
var sequence: Array = []
var idx := 0
var misses := 0
var phase := "gap" ## gap / prompt / end
var phase_t := 0.0
var history: Array = [] ## 每次出招：{key, ok, reaction_ms}
var rng := RandomNumberGenerator.new()
var prompt_label: Label
var prompt_box: ColorRect
var timer_bar: ColorRect
var status: Label

func _begin() -> void:
	cfg = config as ComboConfig
	var d := eff_depth()
	hits = cfg.hits_at(d)
	window = cfg.window_at(d) / 1000.0 * float(context.get("window_mult", 1.0))
	interval = cfg.interval_ms / 1000.0
	if context.has("seed"):
		rng.seed = int(context.seed)
	else:
		rng.randomize()
	sequence.clear()
	for i in hits:
		sequence.append(KEYS[rng.randi_range(0, KEYS.size() - 1)])
	var vs := get_viewport_rect().size
	UI.rect(self, Vector2(0, vs.y / 2 - 220), Vector2(vs.x, 440), Color(0, 0, 0, 0.65))
	UI.label(self, "%s —— 按出屏幕上的键！（%d 连击，窗口 %d 毫秒）" % [config.display_name, hits, roundi(window * 1000)], Vector2(vs.x / 2 - 520, vs.y / 2 - 200), 32)
	prompt_box = UI.rect(self, Vector2(vs.x / 2 - 110, vs.y / 2 - 120), Vector2(220, 220), Color(0.3, 0.3, 0.35))
	prompt_label = UI.label(self, "", Vector2(vs.x / 2 - 90, vs.y / 2 - 80), 110)
	timer_bar = UI.rect(self, Vector2(vs.x / 2 - 300, vs.y / 2 + 130), Vector2(600, 16), Color(1, 0.8, 0.3))
	status = UI.label(self, "", Vector2(vs.x / 2 - 300, vs.y / 2 + 160), 28)
	phase = "gap"
	phase_t = 0.0
	_update_status()

func total_time() -> float:
	return hits * (window + interval)

func _tick(delta: float) -> void:
	phase_t += delta
	if phase == "gap" and phase_t >= interval:
		phase = "prompt"
		phase_t = 0.0
		prompt_label.text = KEY_TEXT[sequence[idx]]
		prompt_box.color = Color(0.85, 0.3, 0.25)
		status.text = "第 %d/%d 击：%s" % [idx + 1, hits, KEY_HINT[sequence[idx]]]
	elif phase == "prompt":
		timer_bar.scale.x = clampf(1.0 - phase_t / window, 0.0, 1.0)
		if phase_t >= window:
			_resolve(false, -1.0)

## 当前出招期间按下了某个动作
func press(action: String) -> void:
	if phase != "prompt":
		return
	_resolve(action == sequence[idx], phase_t * 1000.0)

func _resolve(ok: bool, reaction_ms: float) -> void:
	history.append({"key": sequence[idx], "ok": ok, "reaction_ms": reaction_ms})
	if not ok:
		misses += 1
	prompt_box.color = Color(0.3, 0.8, 0.4) if ok else Color(0.5, 0.1, 0.1)
	prompt_label.text = "✓" if ok else "×"
	idx += 1
	phase = "gap"
	phase_t = 0.0
	timer_bar.scale.x = 0.0
	_update_status()
	if idx >= hits:
		phase = "end"
		var r := Result.PERFECT if misses == 0 else (Result.GOOD if misses == 1 else Result.FAIL)
		_finish(r, 1.0 - float(misses) / hits)

func _update_status() -> void:
	if status and phase == "gap":
		status.text = "失误 %d 次" % misses

func _unhandled_input(e: InputEvent) -> void:
	if not active or phase != "prompt" or e.is_echo():
		return
	for a in KEYS:
		if e.is_action_pressed(a):
			get_viewport().set_input_as_handled()
			press(a)
			return

func _on_timeout() -> void:
	pass ## 由出招序列自己结束
