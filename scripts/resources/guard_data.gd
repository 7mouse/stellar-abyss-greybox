class_name GuardData
extends Resource
## 层主（LordData）= 模板 × 词缀 × 配色（data/guards/*.tres）。HP/伤害 = 模板第 1 层基准 × 倍率（不再乘楼层成长）

@export var id := ""
@export var display_name := ""
@export var base_enemy: EnemyData
@export var hp_mult := 3.0
@export var dmg_mult := 1.0
@export var attack_interval := 1.8 ## 词缀前的出手间隔（数值表给的是最终值，狂暴会再除以 1.3）
@export var scale := 1.8
@export var color := Color(0.9, 0.3, 0.3)
@export var affixes: Array[AffixData] = []
@export var phase2_hp_ratio := 0.0 ## 0 = 无二阶段
@export var phase2_affix: AffixData
@export var phase2_sec := 1.0
@export var windup_mult := 1.0 ## 攻击前摇倍率（×模板 windup）
@export var summon_every_mult := 1.0 ## 召唤间隔倍率（×词缀 summon_every）
@export var summon_count_override := 0 ## 每次召唤数量；0 = 用词缀的 summon_count
@export var xp := 30
@export var loot_table: LootTable

@export_group("层主（LordData）")
@export var moves: PackedStringArray = [] ## 招式（灰盒只用于描述）
@export var minions := "" ## 小弟："mushling:2"（实际召唤由召唤词缀驱动）
@export var arena_hazard: HazardData ## 场地机关
@export var arena_hazard_count := 0
@export var arena_hazard_phase2_only := false ## 只在二阶段出现
