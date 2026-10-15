class_name PlayerStats
extends Resource
## 主角基础参数（data/player_stats.tres）

@export_group("基础")
@export var max_hp := 100
@export var move_speed := 260.0
@export_group("冲刺")
@export var dash_distance := 160.0
@export var dash_time := 0.18
@export var dash_iframes := 0.22
@export var dash_charges := 2
@export var dash_recharge := 0.9
@export_group("受击")
@export var hurt_iframes := 0.6
@export var hurt_knockback := 120.0
@export_group("成长")
@export var hp_per_level := 0.08
@export var atk_per_level := 0.05
@export var level_cap := 10
## 累计到 Lv2..10 需要的 XP，逗号分隔
@export var xp_table := "20,50,95,155,230,320,430,560,710"
@export_group("打击感")
@export var hitstop_sec := 0.05
@export var shake_px := 4.0
@export var cam_smooth_sec := 0.15
@export_group("局内")
@export var heal_between_floors := 0.3
@export var interact_range := 64.0

func xp_thresholds() -> PackedInt32Array:
	var out := PackedInt32Array()
	for s in xp_table.split(","):
		out.append(int(s.strip_edges()))
	return out

## 由累计 XP 算等级（1..level_cap）
func level_for_xp(xp: int) -> int:
	var lv := 1
	for th in xp_thresholds():
		if xp >= th and lv < level_cap:
			lv += 1
	return lv

func xp_for_level(lv: int) -> int:
	if lv <= 1:
		return 0
	var th := xp_thresholds()
	return th[mini(lv - 2, th.size() - 1)]
