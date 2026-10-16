class_name HazardData
extends Resource
## 环境机关（data/hazards/*.tres）：孢子囊 / 缠根地块 / 落石 / 根柱

@export var id := "" ## spore_pod / root_snare / falling_rock / root_pillar
@export var display_name := ""
@export var radius := 40.0 ## 机关本体（触发）半径
@export var effect_radius := 120.0 ## 效果半径（孢子云 / 落石砸击）
@export var trigger_px := 0.0 ## 落石：主角进入这个距离开始预兆；0 = 踩上才触发
@export var warn_sec := 0.0 ## 预兆时长
@export var effect_sec := 2.0 ## 效果持续（孢子云存在 / 缠住时长）
@export var slow_pct := 0.0 ## 减速比例（0.3 = 移速 −30%）
@export var damage := 0 ## 伤害（落石）
@export var noise_px := 0.0 ## 触发时声音半径
@export var rearm_sec := 0.0 ## 重新就绪；0 = 一次性
@export var lord_dmg_mult := 1.0 ## 砸中层主的伤害倍率
@export var color := Color(0.6, 0.7, 0.3)
