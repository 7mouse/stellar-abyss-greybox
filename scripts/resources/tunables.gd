class_name Tunables
extends Resource
## 全局可调参数（调试面板 F1 运行时可改）

@export_group("迷宫")
@export var map_seed: int = -1 ## -1 = 每局随机；>=0 固定种子可复现
@export var nodes_min: int = 8
@export var nodes_max: int = 10
@export var rest_heal_ratio: float = 0.3
@export var loot_bonus_per_depth: float = 0.25
@export var chest_material: int = 2
@export var chest_shard: int = 1
@export var battle_material_drop: int = 1

@export_group("主角")
@export var player_max_hp: int = 100
@export var player_speed: int = 10
@export var slash_power: int = 10
@export var heavy_power: int = 16

@export_group("敌人")
@export var enemy_min: int = 1
@export var enemy_max: int = 3
@export var enemy_hp_per_depth: float = 0.2
@export var enemy_atk_per_depth: float = 0.15

@export_group("小游戏难度")
@export var base_difficulty: float = 1.0
@export var depth_scale: float = 0.5
@export var trait_bonus_per_level: float = 0.5

@export_group("判定倍率")
@export var atk_mult_perfect: float = 1.5
@export var atk_mult_good: float = 1.0
@export var atk_mult_fail: float = 0.5
@export var def_mult_perfect: float = 0.0
@export var def_mult_good: float = 0.5
@export var def_mult_fail: float = 1.0

@export_group("调试")
@export var god_mode: bool = false

func attack_mult(result: int) -> float:
	return [atk_mult_perfect, atk_mult_good, atk_mult_fail][result]

func defense_mult(result: int) -> float:
	return [def_mult_perfect, def_mult_good, def_mult_fail][result]
