extends MinigameBase
## T7 第 6 组 节奏按键：音符沿轨道落到判定线，跟着节拍器按 空格/J/手柄A。
## 每个音符：|偏差| ≤ perfect_ms 记 1，≤ good_ms 记 good_weight，否则/漏按记 0。
## 命中比例 ≥ perfect_ratio → PERFECT，≥ good_ratio → GOOD，否则 FAIL。
## 偏差 = 按键时间 − rhythm_offset_ms（输入延迟校准） − 音符时间。

const SCROLL := 600.0 ## 像素/秒
var cfg: RhythmConfig
var bpm := 100.0
var beat := 0.6
var notes: Array = [] ## {t, judged, grade, offset_ms, rect}
var song_t := 0.0
var start_us := 0
var last_beat := -1
var line_y := 0.0
var lane_x := 0.0
var perfect_w := 0.05
var good_w := 0.12
var status: Label
var flash: ColorRect
var manual_clock := false ## 测试用：由测试推进 song_t

func _begin() -> void:
	cfg = config as RhythmConfig
	var d := eff_depth()
	bpm = cfg.bpm_at(d)
	beat = 60.0 / bpm
	var wm := float(context.get("window_mult", 1.0))
	perfect_w = cfg.perfect_ms / 1000.0 * wm
	good_w = cfg.good_ms / 1000.0 * wm
	var vs := get_viewport_rect().size
	lane_x = vs.x / 2 - 60
	line_y = vs.y / 2 + 300
	UI.rect(self, Vector2.ZERO, vs, Color(0, 0, 0, 0.6))
	UI.label(self, "%s —— 音符落到白线时按 空格/J/手柄A（BPM %d）" % [config.display_name, roundi(bpm)], Vector2(vs.x / 2 - 520, 60), 32)
	UI.rect(self, Vector2(lane_x, 0), Vector2(120, vs.y), Color(0.15, 0.15, 0.2))
	UI.rect(self, Vector2(lane_x - 40, line_y - 4), Vector2(200, 8), Color.WHITE)
	flash = UI.rect(self, Vector2(lane_x + 160, line_y - 30), Vector2(60, 60), Color(1, 1, 1, 0.1))
	status = UI.label(self, "", Vector2(lane_x + 260, line_y - 20), 32)
	for i in cfg.notes_at(d):
		var r := UI.rect(self, Vector2(lane_x + 10, -100), Vector2(100, 30), Color(0.4, 0.9, 1.0))
		notes.append({"t": (cfg.lead_beats + i) * beat, "judged": false, "grade": 0.0, "offset_ms": 0.0, "rect": r})
	start_us = Time.get_ticks_usec()
	_layout()

func end_time() -> float:
	return notes[-1].t + good_w + 0.2 if not notes.is_empty() else 0.0

func note_y(n: Dictionary) -> float:
	return line_y - (n.t - song_t) * SCROLL

func _tick(_delta: float) -> void:
	if not manual_clock:
		song_t = (Time.get_ticks_usec() - start_us) / 1000000.0 * Engine.time_scale
	advance()

## 推进到 song_t：节拍器、漏按判定、画面
func advance() -> void:
	var b := int(floor(song_t / beat))
	if b != last_beat and b >= 0:
		last_beat = b
		var on_note := b >= cfg.lead_beats
		Beep.play(self, 1320.0 if on_note else 880.0)
		flash.color = Color(1, 1, 0.5, 0.9)
	flash.color.a = maxf(0.1, flash.color.a - 0.05)
	var cal := GameState.tunables.rhythm_offset_ms / 1000.0
	for n in notes:
		if not n.judged and song_t - cal > n.t + good_w:
			_grade(n, 0.0, (song_t - cal - n.t) * 1000.0, "漏")
	_layout()
	if not done and song_t >= end_time() and notes.all(func(n): return n.judged):
		var tot := 0.0
		for n in notes:
			tot += n.grade
		var ratio := tot / notes.size()
		var r := Result.PERFECT if ratio >= cfg.perfect_ratio else (Result.GOOD if ratio >= cfg.good_ratio else Result.FAIL)
		_finish(r, ratio)

## 在歌曲时间 at（秒）按键
func press_at(at: float) -> void:
	var t := at - GameState.tunables.rhythm_offset_ms / 1000.0
	var best: Dictionary = {}
	var best_d := 1e9
	for n in notes:
		if n.judged:
			continue
		var dd: float = absf(t - n.t)
		if dd < best_d:
			best_d = dd
			best = n
	if best.is_empty() or best_d > good_w:
		status.text = "空按"
		return
	if best_d <= perfect_w:
		_grade(best, 1.0, (t - best.t) * 1000.0, "完美")
	else:
		_grade(best, cfg.good_weight, (t - best.t) * 1000.0, "良好")

func _grade(n: Dictionary, g: float, off_ms: float, txt: String) -> void:
	n.judged = true
	n.grade = g
	n.offset_ms = off_ms
	n.rect.color = Color(0.3, 1, 0.4) if g >= 1.0 else (Color(1, 0.9, 0.3) if g > 0 else Color(0.6, 0.2, 0.2))
	status.text = "%s  %+d ms" % [txt, roundi(off_ms)] if txt != "漏" else "漏按"

func _layout() -> void:
	for n in notes:
		if not n.judged:
			n.rect.position.y = note_y(n) - 15

func _unhandled_input(e: InputEvent) -> void:
	if active and not e.is_echo() and e.is_action_pressed("mg_action"):
		get_viewport().set_input_as_handled()
		if not manual_clock:
			song_t = (Time.get_ticks_usec() - start_us) / 1000000.0 * Engine.time_scale
		press_at(song_t)

func _on_timeout() -> void:
	pass
