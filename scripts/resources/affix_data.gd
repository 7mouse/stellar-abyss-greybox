class_name AffixData
extends Resource
## 层主词缀：狂暴 / 召唤 / 硬壳 / 孢子

@export var id := ""
@export var display_name := ""
@export var attack_speed_pct := 0.0 ## 狂暴：+0.3 = 攻速 +30%
@export var summon_every := 0.0 ## 召唤：每 N 秒
@export var summon_count := 0
@export var summon_enemy := "mushling"
@export var poise_pct := 0.0 ## 硬壳：+1.0 = poise +100%
@export var back_damage_mult := 1.0 ## 硬壳：背后受伤 ×1.5
@export var spore_on_slam: HazardData ## 孢子：重砸后在落点留下孢子云（用这个机关的效果参数）
@export var spore_sec := 0.0 ## 孢子云持续秒数（0 = 用机关的 effect_sec）
@export_group("厚苔")
@export var dmg_taken_mult := 1.0 ## 1 = 不减伤
@export var break_by_heavy := false
@export var break_sec := 0.0 ## 破开后按原伤结算的秒数
@export var break_cd := 0.0 ## 长回来之后，这段时间不能再破
@export_group("精英")
@export var hp_mult := 1.0
@export var dmg_mult := 1.0
@export var speed_mult := 1.0
@export var interval_override := 0.0 ## >0 时覆盖出手间隔
@export var palette := ""
@export var bounce_enabled := false
@export var bounce_windup := 0.8
@export var bounce_range := 260.0
@export var bounce_air_sec := 0.6
@export var bounce_radius := 100.0
@export var bounce_damage_mult := 1.35
@export var bounce_recover := 1.0
@export var bounce_every := 3
@export var leash_px := 0.0 ## >0 时离开出生点这么远就回归
@export var loot_table: LootTable
@export var xp_mult := 1.0
