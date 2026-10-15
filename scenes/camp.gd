extends Control
## 营地（T9 再补升级）。

var enter_btn: Button
var upgrade_buttons := {}
var msg: Label
var mats_label: Label
const GROUP_NAMES := {1: "连击闪避/格挡", 2: "追逐躲球", 5: "运气", 6: "节奏按键"}

func _ready() -> void:
	UI.rect(self, Vector2.ZERO, Vector2(1920, 1080), Color(0.16, 0.2, 0.16))
	UI.label(self, "营地", Vector2(120, 80), 72)
	UI.label(self, "你被卷入了这个异世界。公会说：通关迷宫，就能回去。", Vector2(120, 190), 32, Color(0.85, 0.85, 0.75))
	mats_label = UI.label(self, "", Vector2(120, 280), 36)
	var box := VBoxContainer.new()
	box.position = Vector2(120, 420)
	box.add_theme_constant_override("separation", 12)
	add_child(box)
	enter_btn = UI.button(box, "再次下潜（从第 1 层开始）", enter_dungeon, Vector2(620, 90), Color(0.2, 0.45, 0.3))
	UI.label(box, "—— 技能组升级（花费局外材料）——", Vector2.ZERO, 28, Color(1, 0.85, 0.4))
	for g in GameState.skill_levels:
		var b := UI.button(box, _upgrade_text(g), _on_upgrade.bind(g), Vector2(620, 70), Color(0.3, 0.3, 0.45))
		b.disabled = not GameState.can_upgrade(g)
		upgrade_buttons[g] = b
	msg = UI.label(self, "", Vector2(800, 520), 30, Color(0.7, 1, 0.7))
	mats_label.text = "局外材料：%d    记忆碎片：%d" % [GameState.meta_materials, GameState.meta_shards]
	UI.button(box, "节奏输入延迟校准", func(): GameState.goto(GameState.SCN_CALIBRATION), Vector2(520, 80))
	UI.label(self, "操作：方向键/左摇杆 选择，空格/回车/手柄A 确认，F1 调试面板", Vector2(120, 980), 24, Color(0.7, 0.7, 0.7))
	enter_btn.grab_focus.call_deferred()

func _upgrade_text(g: int) -> String:
	var eff := "幸运 +1" if g == 5 else "判定窗口 +10%"
	return "第%d组 %s  Lv%d → Lv%d（%s）  花费 %d" % [g, GROUP_NAMES[g], GameState.skill_levels[g], GameState.skill_levels[g] + 1, eff, GameState.upgrade_cost(g)]

func _on_upgrade(g: int) -> void:
	if GameState.upgrade(g):
		msg.text = "第%d组 升到 Lv%d！下次下潜生效。" % [g, GameState.skill_levels[g]]
	_refresh()

func _refresh() -> void:
	mats_label.text = "局外材料：%d    记忆碎片：%d" % [GameState.meta_materials, GameState.meta_shards]
	for g in upgrade_buttons:
		upgrade_buttons[g].text = _upgrade_text(g)
		upgrade_buttons[g].disabled = not GameState.can_upgrade(g)
	if get_viewport().gui_get_focus_owner() == null or get_viewport().gui_get_focus_owner().disabled:
		enter_btn.grab_focus()

func enter_dungeon() -> void:
	GameState.new_run()
	GameState.goto(GameState.SCN_DUNGEON)
