extends Control
## 营地（T9 再补升级）。

var enter_btn: Button

func _ready() -> void:
	UI.rect(self, Vector2.ZERO, Vector2(1920, 1080), Color(0.16, 0.2, 0.16))
	UI.label(self, "营地", Vector2(120, 80), 72)
	UI.label(self, "你被卷入了这个异世界。公会说：通关迷宫，就能回去。", Vector2(120, 190), 32, Color(0.85, 0.85, 0.75))
	UI.label(self, "局外材料：%d    记忆碎片：%d" % [GameState.meta_materials, GameState.meta_shards], Vector2(120, 280), 36)
	var lv := []
	for g in GameState.skill_levels:
		lv.append("第%d组 Lv%d" % [g, GameState.skill_levels[g]])
	UI.label(self, "技能组：" + "  ".join(lv), Vector2(120, 340), 28, Color(0.8, 0.8, 0.8))
	var box := VBoxContainer.new()
	box.position = Vector2(120, 460)
	add_child(box)
	enter_btn = UI.button(box, "下潜迷宫（从第 1 层开始）", enter_dungeon, Vector2(520, 90), Color(0.2, 0.45, 0.3))
	UI.button(box, "节奏输入延迟校准", func(): GameState.goto(GameState.SCN_CALIBRATION), Vector2(520, 80))
	UI.label(self, "操作：方向键/左摇杆 选择，空格/回车/手柄A 确认，F1 调试面板", Vector2(120, 980), 24, Color(0.7, 0.7, 0.7))
	enter_btn.grab_focus.call_deferred()

func enter_dungeon() -> void:
	GameState.new_run()
	GameState.goto(GameState.SCN_DUNGEON)
