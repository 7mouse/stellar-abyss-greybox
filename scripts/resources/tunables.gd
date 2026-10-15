class_name Tunables
extends Resource
## 全局可调参数（调试面板 F1 运行时可改）

@export_group("迷宫")
@export var map_seed: int = -1 ## -1 = 每局随机；>=0 固定种子可复现
@export var nodes_min: int = 8
@export var nodes_max: int = 10
@export var rest_heal_ratio: float = 0.3
@export var entrance_rest_floors: String = "" ## 入口固定休息点的层，逗号分隔，如 "3" 或 "2,3"；空 = 无
@export var entrance_rest_heal: float = 0.3 ## 入口休息点回血比例
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
@export var basic_power: int = 10 ## 普通攻击“斩击”（时机条）
@export var ult_power: int = 28 ## 大招（节奏连斩 / 猜拳一击 / 命运骰击）基础威力
@export var qte_mult_perfect: float = 1.3 ## 时机条倍率
@export var qte_mult_good: float = 1.0
@export var qte_mult_fail: float = 0.7

@export_group("能量（大招）")
@export var energy_max: int = 3
@export var energy_per_basic: int = 1 ## 每次普通攻击 +能量
@export var energy_per_perfect_def: int = 1 ## 每次防御 PERFECT 额外 +能量

@export_group("精英与首领（占位）")
@export var elite_floors: String = "2" ## 中段必经精英的层（逗号分隔）
@export var boss_on_final_floor: bool = true ## 最终层出口前必经首领
@export var elite_drop_units: int = 3 ## 精英掉落按 N 个普通敌人计算
@export var boss_drop_units: int = 5

@export_group("加速")
@export var fast_forward_scale: float = 2.0 ## 加速开启时的倍速（小游戏判定期间强制 1 倍）；开关状态存于 Settings

@export_group("敌人")
## 每场普通战敌人数量权重：1 只 / 2 只 / 3 只（调试面板暂不支持数组，拆成 3 个 float）
@export var enemy_count_w1: float = 0.5
@export var enemy_count_w2: float = 0.25
@export var enemy_count_w3: float = 0.25
@export var trio_hp_mult: float = 0.8 ## 一场 3 只普通敌人时，每只 HP 乘此系数
@export var floor3_atk_mult: float = 1.4 ## 最终层普通敌人攻击系数（不影响精英/首领）
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

func has_entrance_rest(depth: int) -> bool:
	for s in entrance_rest_floors.split(",", false):
		if s.strip_edges().is_valid_int() and int(s) == depth:
			return true
	return false

var enemy_count_weights: PackedFloat32Array:
	get:
		return PackedFloat32Array([enemy_count_w1, enemy_count_w2, enemy_count_w3])

func qte_mult(result: int) -> float:
	return [qte_mult_perfect, qte_mult_good, qte_mult_fail][result]

func has_elite(depth: int) -> bool:
	for s in elite_floors.split(",", false):
		if s.strip_edges().is_valid_int() and int(s) == depth:
			return true
	return false

func attack_mult(result: int) -> float:
	return [atk_mult_perfect, atk_mult_good, atk_mult_fail][result]

func defense_mult(result: int) -> float:
	return [def_mult_perfect, def_mult_good, def_mult_fail][result]
