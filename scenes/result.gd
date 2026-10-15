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
		UI.label(self, "倒下惩罚：记忆碎片全部保留，材料丢失 %d" % r.get("material_lost", 0), Vector2(120, 370), 30, Color(1, 0.6, 0.5))
	var b := UI.button(self, "返回营地", back_to_camp, Vector2(400, 90))
	b.position = Vector2(120, 500)
	b.grab_focus.call_deferred()
	if OS.has_feature("web"):
		var d := UI.button(self, "下载试玩数据 CSV", func(): GameState.download_log(), Vector2(400, 80), Color(0.3, 0.35, 0.5))
		d.position = Vector2(120, 620)

func back_to_camp() -> void:
	GameState.finish_result()
