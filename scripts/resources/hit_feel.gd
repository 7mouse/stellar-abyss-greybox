class_name HitFeel
extends Resource
## 打击感。每个事件一组：<事件>_hitstop_ms / _shake_px / _shake_ms / _knockback_px / _flash_ms / _iframe_ms。
## 不用的项写 -1（击退不改、不闪白、不加无敌）。0 表示明确做一次“力度为零”的反馈。
## 层主死亡另有 slowmo：boss_death_slowmo_scale、boss_death_slowmo_ms。

const EVENTS: PackedStringArray = [
	"light_1", "light_2", "light_3", "skill_1", "skill_2", "armor_break", "dash",
	"player_hurt", "kill_normal", "kill_elite", "boss_heavy", "boss_phase", "boss_death",
]

@export_group("普攻 1")
@export var light_1_hitstop_ms := 40
@export var light_1_shake_px := 0.0
@export var light_1_shake_ms := 0
@export var light_1_knockback_px := 20.0
@export var light_1_flash_ms := 60
@export var light_1_iframe_ms := -1

@export_group("普攻 2")
@export var light_2_hitstop_ms := 40
@export var light_2_shake_px := 0.0
@export var light_2_shake_ms := 0
@export var light_2_knockback_px := 20.0
@export var light_2_flash_ms := 60
@export var light_2_iframe_ms := -1

@export_group("普攻 3")
@export var light_3_hitstop_ms := 80
@export var light_3_shake_px := 4.0
@export var light_3_shake_ms := 120
@export var light_3_knockback_px := 140.0
@export var light_3_flash_ms := 80
@export var light_3_iframe_ms := -1

@export_group("技能 1 回身横斩")
@export var skill_1_hitstop_ms := 100
@export var skill_1_shake_px := 6.0
@export var skill_1_shake_ms := 160
@export var skill_1_knockback_px := 60.0
@export var skill_1_flash_ms := 80
@export var skill_1_iframe_ms := -1

@export_group("技能 2 破甲突刺")
@export var skill_2_hitstop_ms := 90
@export var skill_2_shake_px := 5.0
@export var skill_2_shake_ms := 140
@export var skill_2_knockback_px := 100.0
@export var skill_2_flash_ms := 80
@export var skill_2_iframe_ms := -1

@export_group("破甲")
@export var armor_break_hitstop_ms := 80
@export var armor_break_shake_px := 4.0
@export var armor_break_shake_ms := 120
@export var armor_break_knockback_px := -1.0
@export var armor_break_flash_ms := 120
@export var armor_break_iframe_ms := -1

@export_group("冲刺")
@export var dash_hitstop_ms := 0
@export var dash_shake_px := 0.0
@export var dash_shake_ms := 0
@export var dash_knockback_px := 0.0
@export var dash_flash_ms := -1
@export var dash_iframe_ms := 220

@export_group("主角受伤")
@export var player_hurt_hitstop_ms := 60
@export var player_hurt_shake_px := 5.0
@export var player_hurt_shake_ms := 150
@export var player_hurt_knockback_px := 120.0
@export var player_hurt_flash_ms := 100
@export var player_hurt_iframe_ms := 600

@export_group("击杀普通怪")
@export var kill_normal_hitstop_ms := 60
@export var kill_normal_shake_px := 3.0
@export var kill_normal_shake_ms := 100
@export var kill_normal_knockback_px := 60.0
@export var kill_normal_flash_ms := 100
@export var kill_normal_iframe_ms := -1

@export_group("击杀精英")
@export var kill_elite_hitstop_ms := 120
@export var kill_elite_shake_px := 8.0
@export var kill_elite_shake_ms := 220
@export var kill_elite_knockback_px := 100.0
@export var kill_elite_flash_ms := 120
@export var kill_elite_iframe_ms := 300

@export_group("层主受大招")
@export var boss_heavy_hitstop_ms := 120
@export var boss_heavy_shake_px := 8.0
@export var boss_heavy_shake_ms := 200
@export var boss_heavy_knockback_px := 0.0
@export var boss_heavy_flash_ms := 100
@export var boss_heavy_iframe_ms := -1

@export_group("层主阶段变化")
@export var boss_phase_hitstop_ms := 0
@export var boss_phase_shake_px := 10.0
@export var boss_phase_shake_ms := 1200
@export var boss_phase_knockback_px := 160.0
@export var boss_phase_flash_ms := -1
@export var boss_phase_iframe_ms := 1200

@export_group("层主死亡")
@export var boss_death_hitstop_ms := 250
@export var boss_death_shake_px := 14.0
@export var boss_death_shake_ms := 600
@export var boss_death_knockback_px := 0.0
@export var boss_death_flash_ms := 200
@export var boss_death_iframe_ms := 1500
@export var boss_death_slowmo_scale := 0.3
@export var boss_death_slowmo_ms := 800

func hitstop_ms(event: String) -> int:
	return int(get(event + "_hitstop_ms"))

func shake_px(event: String) -> float:
	return float(get(event + "_shake_px"))

func shake_ms(event: String) -> int:
	return int(get(event + "_shake_ms"))

func knockback_px(event: String) -> float:
	return float(get(event + "_knockback_px"))

func flash_ms(event: String) -> int:
	return int(get(event + "_flash_ms"))

func iframe_ms(event: String) -> int:
	return int(get(event + "_iframe_ms"))
