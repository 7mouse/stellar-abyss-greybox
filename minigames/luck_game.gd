extends MinigameBase
## T6 第 5 组 运气：猜拳 / 骰子（由 LuckConfig.mode 决定）。
## 猜拳：玩家出拳，胜率 = 基础 + 幸运加成；平局重来一次。首局胜/重来胜=PERFECT，平局后未胜=GOOD，负=FAIL。
## 骰子：按确认掷 1d6，≥目标值成功=PERFECT；失败时按幸运获得重掷机会，重掷成功=GOOD；否则 FAIL。

const HANDS := ["石头", "剪刀", "布"]
const HAND_COLOR := [Color(0.6, 0.6, 0.6), Color(0.9, 0.5, 0.2), Color(0.4, 0.7, 0.9)]

var cfg: LuckConfig
var rng := RandomNumberGenerator.new()
var luck := 0
var stage := "choose" ## choose / anim / done
var draws := 0
var rerolled := false
var title: Label
var big: Label
var info: Label
var me_box: ColorRect
var foe_box: ColorRect
var auto_choice := -1 ## 测试/超时用

func _begin() -> void:
	cfg = config as LuckConfig
	luck = int(context.get("luck", 0))
	if context.has("seed"):
		rng.seed = int(context.seed)
	else:
		rng.randomize()
	var vs := get_viewport_rect().size
	UI.rect(self, Vector2(0, vs.y / 2 - 260), Vector2(vs.x, 520), Color(0, 0, 0, 0.7))
	title = UI.label(self, "", Vector2(vs.x / 2 - 560, vs.y / 2 - 240), 32)
	me_box = UI.rect(self, Vector2(vs.x / 2 - 400, vs.y / 2 - 140), Vector2(240, 240), Color(0.3, 0.3, 0.35))
	foe_box = UI.rect(self, Vector2(vs.x / 2 + 160, vs.y / 2 - 140), Vector2(240, 240), Color(0.3, 0.3, 0.35))
	big = UI.label(self, "", Vector2(vs.x / 2 - 120, vs.y / 2 - 60), 72)
	info = UI.label(self, "", Vector2(vs.x / 2 - 560, vs.y / 2 + 140), 28)
	if cfg.mode == "rps":
		title.text = "猜拳 —— ← 石头   ↑ 剪刀   → 布（手柄十字键）    胜率 %d%%（幸运 %d）" % [roundi(cfg.rps_win_rate(luck) * 100), luck]
	else:
		title.text = "掷骰 —— 按 空格/手柄A 掷出 1d6，≥ %d 成功    成功率 %d%%，重掷几率 %d%%（幸运 %d）" % [cfg.dice_target, roundi(cfg.dice_base_rate() * 100), roundi(cfg.dice_reroll_rate(luck) * 100), luck]
	info.text = "（2.5 秒内不操作将自动出手）"

func _tick(_delta: float) -> void:
	if stage == "choose" and elapsed >= 2.5:
		if cfg.mode == "rps":
			choose(rng.randi_range(0, 2))
		else:
			roll()

func _unhandled_input(e: InputEvent) -> void:
	if not active or stage != "choose" or e.is_echo():
		return
	if cfg.mode == "rps":
		for i in 3:
			if e.is_action_pressed(["move_left", "move_up", "move_right"][i]):
				get_viewport().set_input_as_handled()
				choose(i)
				return
	elif e.is_action_pressed("mg_action"):
		get_viewport().set_input_as_handled()
		roll()

# ---- 纯逻辑（模拟也用这些）----
## 一局猜拳的结果：1 胜 0 平 -1 负
static func rps_round(c: LuckConfig, lk: int, r: RandomNumberGenerator) -> int:
	var w := c.rps_win_rate(lk)
	var x := r.randf()
	if x < w:
		return 1
	return 0 if x < w + (1.0 - w) / 2.0 else -1

static func rps_resolve(c: LuckConfig, lk: int, r: RandomNumberGenerator) -> Array:
	var rounds: Array = [rps_round(c, lk, r)]
	if rounds[0] == 0:
		rounds.append(rps_round(c, lk, r))
	var res := Result.FAIL
	if rounds[-1] == 1:
		res = Result.PERFECT
	elif rounds.size() == 2:
		res = Result.GOOD
	return [res, rounds]

static func dice_resolve(c: LuckConfig, lk: int, r: RandomNumberGenerator) -> Array:
	var rolls: Array = [r.randi_range(1, 6)]
	if rolls[0] >= c.dice_target:
		return [Result.PERFECT, rolls]
	if r.randf() < c.dice_reroll_rate(lk):
		rolls.append(r.randi_range(1, 6))
		if rolls[1] >= c.dice_target:
			return [Result.GOOD, rolls]
	return [Result.FAIL, rolls]

## 自动模拟 n 次，返回 {PERFECT, GOOD, FAIL 比例, first_win（单局胜率/首掷成功率）}
static func simulate(c: LuckConfig, lk: int, n: int, seed: int) -> Dictionary:
	var r := RandomNumberGenerator.new()
	r.seed = seed
	var cnt := [0, 0, 0]
	var first := 0
	for i in n:
		var out: Array = rps_resolve(c, lk, r) if c.mode == "rps" else dice_resolve(c, lk, r)
		cnt[out[0]] += 1
		if (c.mode == "rps" and out[1][0] == 1) or (c.mode == "dice" and out[1][0] >= c.dice_target):
			first += 1
	return {"perfect": cnt[0] / float(n), "good": cnt[1] / float(n), "fail": cnt[2] / float(n), "first": first / float(n)}

# ---- 演出 ----
func choose(hand: int) -> void:
	if stage != "choose":
		return
	stage = "anim"
	var out: Array = rps_resolve(cfg, luck, rng)
	for i in out[1].size():
		var o: int = out[1][i]
		# 根据胜负倒推敌人出拳：胜→敌人出被克的，平→相同，负→克制玩家的
		var foe: int = (hand + 1) % 3 if o == 1 else (hand if o == 0 else (hand + 2) % 3)
		await _shuffle_anim()
		me_box.color = HAND_COLOR[hand]
		foe_box.color = HAND_COLOR[foe]
		big.text = ["负", "平", "胜"][o + 1]
		info.text = "你：%s    敌人：%s%s" % [HANDS[hand], HANDS[foe], "    平局，再来一次！" if o == 0 and i == 0 else ""]
		await get_tree().create_timer(0.5).timeout
	_done(out[0])

func roll() -> void:
	if stage != "choose":
		return
	stage = "anim"
	var out: Array = dice_resolve(cfg, luck, rng)
	for i in out[1].size():
		await _shuffle_anim(true)
		var v: int = out[1][i]
		big.text = str(v)
		me_box.color = Color(0.3, 0.8, 0.4) if v >= cfg.dice_target else Color(0.7, 0.25, 0.25)
		info.text = ("大成功！" if v == 6 else ("成功！" if v >= cfg.dice_target else "失败……")) + ("    幸运触发重掷！" if i == 0 and out[1].size() == 2 else "")
		await get_tree().create_timer(0.5).timeout
	_done(out[0])

func _shuffle_anim(dice := false) -> void:
	var steps := maxi(3, roundi(cfg.anim_sec / 0.08))
	for s in steps:
		if dice:
			big.text = str(rng.randi_range(1, 6))
			me_box.color = Color(0.9, 0.9, 0.9) if s % 2 == 0 else Color(0.6, 0.6, 0.6)
		else:
			me_box.color = HAND_COLOR[s % 3]
			foe_box.color = HAND_COLOR[(s + 1) % 3]
			big.text = "…"
		await get_tree().create_timer(0.08).timeout

func _done(r: int) -> void:
	stage = "done"
	title.text = "判定：" + RESULT_CN[r]
	await get_tree().create_timer(0.3).timeout
	_finish(r, [1.0, 0.6, 0.0][r])

func _on_timeout() -> void:
	pass
