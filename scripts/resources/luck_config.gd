class_name LuckConfig
extends MinigameConfig
## 第 5 组 运气：猜拳 / 骰子

@export_enum("rps", "dice") var mode: String = "rps"
@export var rps_base_win: float = 0.33 ## 猜拳基础胜率
@export var rps_win_per_luck: float = 0.05 ## 每点幸运 +胜率
@export var rps_win_max: float = 0.9
@export var dice_target: int = 4 ## 1d6 ≥ 目标值成功
@export var dice_reroll_per_luck: float = 0.15 ## 每点幸运 +重掷几率
@export var anim_sec: float = 0.8 ## 结果动画时长

func rps_win_rate(luck: int) -> float:
	return clampf(rps_base_win + luck * rps_win_per_luck, 0.0, rps_win_max)

func dice_base_rate() -> float:
	return clampf((7.0 - dice_target) / 6.0, 0.0, 1.0)

func dice_reroll_rate(luck: int) -> float:
	return clampf(luck * dice_reroll_per_luck, 0.0, 1.0)

## 理论判定概率 [PERFECT, GOOD, FAIL]
func outcome_probs(luck: int) -> Array:
	if mode == "rps":
		var w := rps_win_rate(luck)
		var d := (1.0 - w) / 2.0
		# 首局胜=PERFECT；平局重来一次：再胜=PERFECT，再平/负=GOOD；首局负=FAIL
		return [w + d * w, d * (1.0 - w), d]
	var p := dice_base_rate()
	var r := dice_reroll_rate(luck)
	# 首掷成功=PERFECT；失败后获得重掷且成功=GOOD；否则 FAIL
	return [p, (1.0 - p) * r * p, (1.0 - p) * (1.0 - r * p)]
