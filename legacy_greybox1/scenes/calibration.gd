extends Control
## 节奏输入延迟校准：跟着节拍器按 8 次，取平均偏差写入 rhythm_offset_ms。

const BPM := 100.0
const TAPS := 8
var beat := 60.0 / BPM
var start_us := 0
var last_beat := -1
var taps: Array = []
var info: Label
var flash: ColorRect
var finished_cal := false

func _ready() -> void:
	UI.rect(self, Vector2.ZERO, Vector2(1920, 1080), Color(0.1, 0.12, 0.16))
	UI.label(self, "节奏输入校准", Vector2(120, 80), 64)
	UI.label(self, "听到“哔”声 / 看到方块闪亮时按 空格/J/手柄A，共 %d 次。" % TAPS, Vector2(120, 200), 32)
	flash = UI.rect(self, Vector2(860, 420), Vector2(200, 200), Color(0.3, 0.3, 0.3))
	info = UI.label(self, "当前校准值：%+d ms" % roundi(GameState.tunables.rhythm_offset_ms), Vector2(120, 700), 32)
	var b := UI.button(self, "返回营地", func(): GameState.goto(GameState.SCN_CAMP), Vector2(360, 80))
	b.position = Vector2(120, 860)
	b.grab_focus.call_deferred()
	start_us = Time.get_ticks_usec()

func now() -> float:
	return (Time.get_ticks_usec() - start_us) / 1000000.0

func _process(_d: float) -> void:
	var b := int(floor(now() / beat))
	if b != last_beat:
		last_beat = b
		Beep.play(self, 1320.0)
		flash.color = Color(1, 1, 0.5)
	flash.color = flash.color.lerp(Color(0.3, 0.3, 0.3), 0.15)

func _unhandled_input(e: InputEvent) -> void:
	if finished_cal or e.is_echo() or not e.is_action_pressed("mg_action"):
		return
	get_viewport().set_input_as_handled()
	if now() < beat: # 第一拍之前不算
		return
	taps.append(now() * 1000.0)
	info.text = "已按 %d/%d" % [taps.size(), TAPS]
	if taps.size() >= TAPS:
		apply(taps)

## 每次按键相对最近节拍的偏差，剔除 >250ms 的离群值后取平均
static func compute_offset(tap_ms: Array, beat_ms: float) -> float:
	var offs: Array = []
	for t in tap_ms:
		var o: float = t - round(t / beat_ms) * beat_ms
		if absf(o) <= 250.0:
			offs.append(o)
	if offs.is_empty():
		return 0.0
	var s := 0.0
	for o in offs:
		s += o
	return s / offs.size()

func apply(tap_ms: Array) -> void:
	finished_cal = true
	var off := compute_offset(tap_ms, beat * 1000.0)
	GameState.tunables.rhythm_offset_ms = off
	info.text = "校准完成：输入延迟 %+d ms（已写入，可在 F1 面板微调）" % roundi(off)
