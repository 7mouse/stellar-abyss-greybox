class_name Tunables
extends Resource
## 全局可调参数（调试面板 F1 运行时可改）

@export_group("迷宫")
@export var map_seed: int = -1 ## -1 = 每局随机；>=0 固定种子可复现
@export var nodes_min: int = 8
@export var nodes_max: int = 10
@export var rest_heal_ratio: float = 0.3
@export var loot_bonus_per_depth: float = 0.25
@export var final_floor: int = 0 ## 最终层：该层出口 = 通关（假结局，迷宫重置）；0 = 无最终层
@export var chest_material: int = 3
@export var chest_shard: int = 1
@export var chest_shard_rate: float = 0.6 ## 宝箱掉碎片概率
@export var battle_material_drop: int = 2 ## 每个敌人掉落材料数
@export var battle_drop_rate: float = 0.8 ## 每个敌人掉材料概率
@export var battle_shard_rate: float = 0.25 ## 每个敌人掉碎片概率

@export_group("背包")
@export var backpack_slots: int = 12
@export var material_stack: int = 3 ## 每格材料上限
@export var shard_stack: int = 2 ## 每格碎片上限
@export var knockdown_material_loss: float = 0.5 ## 倒下丢失材料比例（碎片全保留）

@export_group("营地成长")
@export var upgrade_cost_base: int = 6
@export var upgrade_cost_step: int = 4
@export var upgrade_window_bonus: float = 0.1 ## 每级判定窗口 +10%

@export_group("主角")
@export var player_max_hp: int = 100
@export var player_speed: int = 10
@export var slash_power: int = 10 ## 节奏连斩
@export var heavy_power: int = 16 ## 命运骰击
@export var rps_power: int = 13 ## 猜拳一击

@export_group("敌人")
@export var enemy_min: int = 1
@export var enemy_max: int = 3
@export var enemy_hp_per_depth: float = 0.2
@export var enemy_atk_per_depth: float = 0.15

@export_group("小游戏难度")
@export var base_difficulty: float = 1.0
@export var depth_scale: float = 0.5

@export_group("判定倍率")
@export var atk_mult_perfect: float = 1.5
@export var atk_mult_good: float = 1.0
@export var atk_mult_fail: float = 0.5
@export var def_mult_perfect: float = 0.0
@export var def_mult_good: float = 0.5
@export var def_mult_fail: float = 1.0

@export_group("节奏")
@export var rhythm_offset_ms: float = 0.0 ## 输入延迟校准（正值=玩家按得偏晚）

@export_group("调试")
@export var god_mode: bool = false ## 上帝模式：主角不受伤
@export var log_enabled: bool = true ## 记录 user://playtest_log.csv

func attack_mult(result: int) -> float:
	return [atk_mult_perfect, atk_mult_good, atk_mult_fail][result]

func defense_mult(result: int) -> float:
	return [def_mult_perfect, def_mult_good, def_mult_fail][result]
