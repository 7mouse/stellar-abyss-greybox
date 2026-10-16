class_name AttackData
extends Resource
## 一段攻击（普攻三段 / 技能）：data/attacks/*.tres

@export var id := ""
@export var display_name := ""
@export var damage := 10
@export var windup := 0.08
@export var active := 0.06
@export var recovery := 0.16
@export var attack_range := 90.0
@export var arc_deg := 120.0 ## ≥360 表示以自身为圆心的圆
@export var width := 0.0 ## >0 时判定改为朝向矩形：长 attack_range、宽 width，穿透路径上的敌人
@export var lunge_px := 0.0 ## 判定期间沿朝向前冲的距离；冲刺中没有无敌
@export var poise_dmg_mult := 1.0 ## 削韧倍率（伤害 × 此值累进 poise）
@export var is_heavy := false ## 重击：普攻第 3 段、技能 1、技能 2
@export var knockback := 0.0
@export var cooldown := 0.0
@export var hitstop_sec := 0.05
@export var stagger_sec := 0.0
@export var combo_reset := 0.6 ## 只在第 1 段上读
