class_name TimingConfig
extends MinigameConfig
## 普通攻击时机条：指针从左到右扫一次，中点为最佳时机

@export var qte_sec: float = 0.8 ## 扫一次的总时长
@export var qte_perfect_ms: float = 60.0 ## 距中点 ±ms 内 PERFECT
@export var qte_good_ms: float = 150.0 ## 距中点 ±ms 内 GOOD
