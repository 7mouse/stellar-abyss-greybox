class_name LoreClues
extends Resource
## 虚拟世界线索文本与参数（data/lore/clues.tres）

@export_multiline var epitaph0_raw := "#0000  ▒▒▒▒▒  —  第 ▒ 层  —  死因：▒▒▒"
@export_multiline var epitaph0_fixed := "#0000  [姓名未登记]  —  23:47  —  死因：坠落（楼梯）    备注：非本迷宫记录"
@export var epitaph0_min_deaths := 2
@export var epitaph0_hover_sec := 2.0
@export var guard_log_1 := "[CRADLE] subject_07 / backup #{gen} · neural yield +{yield}% · sync OK"
@export var guard_log_2 := "[CRADLE] heart rate 41 bpm · keep subject asleep"
@export var guard_log_3 := "[深潜计划] 产出达标。继续下潜。—— S."
@export var log_flash_sec := 0.35
@export var log_repeat_chance := 0.3
@export var log_jitter_px := 6.0
@export var death_garble := "▒▒ RELOAD TEMPLATE … 30% ▒▒"
@export var death_garble_sec := 0.2
@export var heartbeat_hz := 55.0

func guard_log(depth: int) -> String:
	return [guard_log_1, guard_log_2, guard_log_3][clampi(depth - 1, 0, 2)]
