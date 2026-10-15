class_name AffixData
extends Resource
## 层守词缀：狂暴 / 召唤 / 硬壳

@export var id := ""
@export var display_name := ""
@export var attack_speed_pct := 0.0 ## 狂暴：+0.3 = 攻速 +30%
@export var summon_every := 0.0 ## 召唤：每 N 秒
@export var summon_count := 0
@export var summon_enemy := "mushling"
@export var poise_pct := 0.0 ## 硬壳：+1.0 = poise +100%
@export var back_damage_mult := 1.0 ## 硬壳：背后受伤 ×1.5
