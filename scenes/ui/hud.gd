class_name Hud
extends CanvasLayer
## 局内 HUD：HP、等级/XP、冲刺充能、技能冷却、层数、背包计数、强化、互动提示、层主血条

var player: Player
var hp_bar: ColorRect
var hp_back: ColorRect
var hp_text: Label
var info: Label
var dash_pips: Array = []
var skill_box: ColorRect
var skill_label: Label
var prompt: Label
var toast: Label
var boss_back: ColorRect
var boss_bar: ColorRect
var boss_name: Label
var boons_label: Label
var channel_label: Label
var _toast_t := 0.0

func _ready() -> void:
	layer = 10
	hp_back = UI.rect(self, Vector2(40, 990), Vector2(420, 30), Color(0.2, 0.1, 0.1))
	hp_bar = UI.rect(self, Vector2(40, 990), Vector2(420, 30), Color(0.85, 0.2, 0.25))
	hp_text = UI.label(self, "", Vector2(50, 950), 26)
	info = UI.label(self, "", Vector2(40, 40), 26)
	for i in 4:
		dash_pips.append(UI.rect(self, Vector2(480 + i * 34, 994), Vector2(26, 22), Color(0.4, 0.8, 1)))
	skill_box = UI.rect(self, Vector2(640, 976), Vector2(60, 60), Color(0.4, 0.75, 0.35))
	skill_label = UI.label(self, "", Vector2(710, 988), 26)
	prompt = UI.label(self, "", Vector2(760, 860), 30, Color(1, 0.95, 0.6))
	toast = UI.label(self, "", Vector2(640, 160), 34, Color(0.8, 1, 0.8))
	boss_back = UI.rect(self, Vector2(560, 60), Vector2(800, 24), Color(0.2, 0.1, 0.1))
	boss_bar = UI.rect(self, Vector2(560, 60), Vector2(800, 24), Color(0.9, 0.3, 0.2))
	boss_name = UI.label(self, "", Vector2(560, 90), 26)
	boons_label = UI.label(self, "", Vector2(1500, 300), 22, Color(0.85, 0.85, 1))
	channel_label = UI.label(self, "", Vector2(700, 800), 28, Color(0.65, 0.9, 1))
	show_boss(null)

func show_boss(g: Node) -> void:
	var on := g != null and is_instance_valid(g)
	boss_back.visible = on
	boss_bar.visible = on
	boss_name.visible = on
	if on:
		boss_name.text = g.gdata.display_name + ("（二阶段）" if g.phase == 2 else "")
		boss_bar.size.x = 800.0 * g.hp / maxf(1, g.max_hp)

func show_toast(t: String) -> void:
	toast.text = t
	_toast_t = 2.5

func _process(delta: float) -> void:
	var _p := Prof.t0()
	_prof_process(delta)
	Prof.add("hud", _p)

func _prof_process(delta: float) -> void:
	_toast_t -= delta
	toast.visible = _toast_t > 0.0
	if player == null or not is_instance_valid(player):
		return
	hp_bar.size.x = 420.0 * player.hp / maxf(1, player.max_hp)
	hp_text.text = "HP %d / %d" % [player.hp, player.max_hp]
	var r := Game.run
	if r:
		var ps := Game.player_stats
		var lv := Game.level()
		var nxt := ps.xp_for_level(lv + 1) if lv < ps.level_cap else r.xp
		info.text = "第 %d 层   %s  Lv%d（XP %d/%d）   萤苔 %d  萤苔精 %d  记忆碎片 %d   击杀 %d" % [r.depth, Lineage.current().name, lv, r.xp, nxt, r.count_of("moss"), r.count_of("moss_essence"), r.shards_carried, r.kills]
		var names := r.boons.map(func(b): return "· " + b.display_name)
		for st in r.equipped:
			names.append("◆ " + st.item.display_name)
		boons_label.text = "强化 / 装备\n" + "\n".join(names)
	var n := player.dash_cd.size()
	for i in dash_pips.size():
		dash_pips[i].visible = i < n
		if i < n:
			dash_pips[i].color = Color(0.4, 0.8, 1) if player.dash_cd[i] <= 0.0 else Color(0.25, 0.3, 0.4)
	var cd := player.skill_cd_left
	skill_box.color = Color(0.4, 0.75, 0.35) if cd <= 0.0 else Color(0.25, 0.3, 0.25)
	skill_label.text = "根须横扫 " + ("就绪" if cd <= 0.0 else "%.1f 秒" % cd)

func skill_text() -> String:
	return skill_label.text
