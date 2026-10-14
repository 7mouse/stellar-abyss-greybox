extends Control
## 结算界面

func _ready() -> void:
	var r := GameState.last_result
	var ok: bool = r.get("extracted", false)
	UI.rect(self, Vector2.ZERO, Vector2(1920, 1080), Color(0.12, 0.18, 0.25) if ok else Color(0.25, 0.1, 0.1))
	UI.label(self, "成功撤离！" if ok else "主角倒下了……", Vector2(120, 100), 72)
	UI.label(self, "到达层数：第 %d 层" % r.get("depth", 1), Vector2(120, 240), 36)
	UI.label(self, "带出材料：%d    记忆碎片：%d" % [r.get("material", 0), r.get("shard", 0)], Vector2(120, 300), 36)
	if not ok:
		UI.label(self, "（倒下惩罚“碎片保留、材料减半”将在 T8 实装，目前战利品全部带出）", Vector2(120, 370), 26, Color(0.85, 0.75, 0.6))
	var b := UI.button(self, "返回营地", back_to_camp, Vector2(400, 90))
	b.position = Vector2(120, 500)
	b.grab_focus.call_deferred()

func back_to_camp() -> void:
	GameState.finish_result()
