class_name EnemyData
extends Resource

enum Pattern { MELEE_COMBO, TRACKER, BALANCED }

@export var display_name: String = ""
@export var max_hp: int = 30
@export var attack: int = 8
@export var speed: int = 8
@export var pattern: Pattern = Pattern.BALANCED
@export var color: Color = Color.RED
@export var defense_groups: Array[int] = [] ## 非空时按顺序轮流使用这些防御组；空 = 按 pattern 映射
@export var actions_per_round: int = 1 ## 每回合行动次数（每次行动 = 1 个独立敌人回合 = 1 次防御小游戏）
@export_enum("normal", "elite", "boss") var rank: String = "normal" ## 精英/首领不吃 enemy_*_per_depth 成长
