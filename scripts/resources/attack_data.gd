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
@export var knockback := 0.0
@export var cooldown := 0.0
@export var hitstop_sec := 0.05
@export var stagger_sec := 0.0
@export var combo_reset := 0.6 ## 只在第 1 段上读
