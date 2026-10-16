class_name EnemyData
extends Resource
## 普通敌人参数（data/enemies/*.tres），第 1 层基准

@export var id := ""
@export var display_name := ""
@export var max_hp := 30
@export var damage := 6
@export var move_speed := 170.0
@export var attack_range := 60.0
@export var windup := 0.45
@export var attack_interval := 1.6
@export var poise := 0.0
@export var xp := 4
@export var loot_table: LootTable
@export var color := Color(0.8, 0.5, 0.3)
@export var size := Vector2(40, 48)
@export_group("行为")
@export var lunge_distance := 110.0 ## 发芽野猪扑撞
@export var lunge_time := 0.15
@export var keep_distance := 320.0 ## 孢子菇保持距离
@export var projectile_speed := 320.0
@export var slam_arc_deg := 100.0 ## 史莱姆重拍扇形
@export var attack_active := 0.12 ## 判定时长；野猪扑撞仍走 lunge_time
@export var recover_sec := 0.35
@export var hurt_sec := 0.3
@export var retreat_cd := 0.0 ## 孢子菇被贴近后撤一次的冷却；0 = 不后撤
