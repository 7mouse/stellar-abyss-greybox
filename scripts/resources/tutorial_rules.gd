class_name TutorialRules
extends Resource
## 新手引导可调参数。提示时长、重试、距离都在这里，F1 改完立刻生效。

@export var hint_sec := 8.0
@export var retry_sec := 20.0
@export var max_shows := 2
@export var move_delay_sec := 1.5
@export var move_px := 120.0
@export var attack_range_px := 400.0
@export var dash_threat_px := 150.0
@export var dash_uses_skip := 3
@export var loot_px := 200.0
@export var fire_px := 300.0
@export var cone_sec := 3.0
@export var banner_sec := 2.0
@export var telegraph_flashes := 2
@export var boss_name := "苔冠王野猪"
@export var move_text := "[%s] 先站起来。"
@export var attack_text := "[%s] 拔刀。连砍三下，第三下最重。"
@export var dash_text := "[%s] 冲过去。动起来的那一瞬间，刀砍不到你。"
@export var loot_text := "[%s] 捡起来。死了，背上的东西就不是你的了。"
@export var stealth_text := "它还没看清你。躲到树后面，或者离开它面前。"
@export var fire_text := "篝火。坐一会儿，前面就是这层的主人。"
@export var fire_full_text := "……前面就是这层的主人。"
@export var extract_text := "出口开了。走出去才算活下来。"
@export var death_text := "林 #07 的记录到此为止。"
@export var charm_text := "紧急回村符。引导 3 秒，挨打会断。层主身边用不了。"
@export var elder_text := "老冒险者：“井口在这儿。往下走吧，越深越好。”"
