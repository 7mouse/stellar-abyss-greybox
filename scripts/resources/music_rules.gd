class_name MusicRules
extends Resource
## 音乐切换。探索层常驻，战斗层叠在上面；层主从小节头进。F1 改完立刻生效。

@export_group("探索")
@export var explore_fade_sec := 2.0 ## 进入楼层时 BGM-02 淡入

@export_group("战斗层")
@export var combat_in_sec := 0.8 ## 有人追击且距离内，BGM-03 淡入
@export var combat_out_sec := 4.0 ## 追击全部结束后再等这么久
@export var combat_fade_sec := 2.0 ## 然后 BGM-03 淡出
@export var combat_range := 800.0

@export_group("层主")
@export var boss_fade_sec := 1.5 ## 02 和 03 淡出
@export var boss_hp_ratio := 0.5 ## 低于此切到 04b，等下一个小节
@export var bar_sec := 2.0 ## 小节长度。04 / 04b 从小节头进
@export var boss_silence_sec := 1.0 ## 层主死后静默
@export var lowpass_sec := 2.0 ## 静默后再回 02，低通这么久后打开

@export_group("其他")
@export var death_cut_sec := 0.3 ## 主角死亡时切掉全部音乐
@export var reduced_gain := 0.65 ## 回村中途的村落降配（少一层）
