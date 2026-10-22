class_name AggroRules
extends Resource
## 仇恨参数（data/aggro_rules.tres = 全局默认 = 第 3 层；data/aggro/aggro_floorN.tres 按层覆盖，只覆盖和脚本默认值不同的字段）。
## 规格见 docs/open-map-spec.md 第 2 节。改动对之后的判定立即生效。

@export_group("视野")
@export var sight_range := 520.0
@export var ranged_sight_range := 640.0 ## 射手（patrol_style = post）的视野
@export var sight_angle_deg := 110.0 ## 营地待机怪 360°
@export var sense_radius := 140.0 ## 近身一律能察觉
@export var sight_confirm_sec := 0.4 ## 锥内持续这么久才进入追击（期间警觉）
@export var sight_interval := 0.1 ## 视野检测间隔（按敌人分帧错开）
@export var thicket_sight_mult := 0.7 ## 树丛潜行：主角在灌木边缘 thicket_edge_px 内时视野距离 × 这个比例
@export var thicket_edge_px := 64.0
@export var alert_sec := 1.5 ## 警觉持续时间（规格未给数，假设）
@export_group("声音")
@export var noise_dash := 360.0
@export var noise_combat := 520.0
@export var noise_combat_interval := 0.5
@export var noise_death := 300.0
@export var noise_chest := 260.0
@export var noise_aggro_ratio := 0.5 ## 声源在半径 × 这个比例以内直接追击
@export var investigate_px := 200.0
@export_group("联动")
@export var link_radius := 380.0
@export var link_chance := 0.5
@export_group("脱离")
@export var leash_px := 1100.0 ## 主角离开敌人出生点超过这个距离 → 回归
@export var enemy_leash_px := 1100.0 ## 敌人自己离出生点超过这个距离 → 回归（M1 规则，保留）
@export var leash_hard_px := 1600.0 ## 敌人离出生点的硬上限
@export var lose_sight_sec := 4.0
@export var return_regen := 0.2 ## 回归时每秒回复最大 HP 的比例
@export var reaggro_cd := 1.5 ## 回到出生点后多久才能再次进入追击
@export var home_arrive_px := 24.0
@export_group("追击上限")
@export var max_chasers := 6
@export var max_attackers := 3
@export var orbit_px := 300.0 ## 包围待机距离
@export_group("巡逻与性能")
@export var patrol_speed_mult := 0.45
@export var post_sec := 3.0 ## 射手在路线点驻守
@export var sleep_radius := 1800.0 ## 离主角更远的巡逻/待机怪休眠

## 合并：以 self 为底，override 里和脚本默认值不同的字段覆盖上去，结果写进 into（不为空时复用同一个对象，面板改动可以实时同步）
func effective(override: AggroRules, into: AggroRules = null) -> AggroRules:
	var out: AggroRules = into if into else AggroRules.new()
	var defaults := AggroRules.new()
	for p in get_property_list():
		if not (p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		var n: String = p.name
		var v = get(n)
		if override and override.get(n) != defaults.get(n):
			v = override.get(n)
		out.set(n, v)
	return out
@export var encounter_gap_sec := 3.0 ## CSV encounters：脱战这么久后再打算新的一次交战
