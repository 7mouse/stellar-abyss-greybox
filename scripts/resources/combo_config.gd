class_name ComboConfig
extends MinigameConfig
## 第 1 组 连击闪避/格挡

@export var hits: int = 3 ## 基础出招次数
@export var hits_per_depth: int = 1 ## 每深一层 +N
@export var hits_max: int = 6
@export var window_ms: float = 600.0 ## 每次出招的反应窗口
@export var window_step_ms: float = 70.0 ## 每深一层缩短
@export var window_min_ms: float = 250.0
@export var interval_ms: float = 300.0 ## 两次出招间隔

func hits_at(d: float) -> int:
	return mini(hits_max, hits + int(floor(maxf(0.0, d - 1.0))) * hits_per_depth)

func window_at(d: float) -> float:
	return maxf(window_min_ms, window_ms - maxf(0.0, d - 1.0) * window_step_ms)
