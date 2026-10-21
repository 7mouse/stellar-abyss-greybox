extends Panel2
## 用任意层的层主稀有材料（萤苔精）做 1 张回村符。已经持有时按钮变灰

func _init() -> void:
	title = "制作回村符"

func _fill() -> void:
	var rules := Game.recall
	var have := rules.craft_material_have()
	var cost := rules.craft_material_count
	text("层主稀有材料 %d / %d（苔冠獠牙、萤苔精）。仓库里已有 %d 张。" % [have, cost, Lineage.charm_carried], 22, Color(0.95, 0.85, 0.65))
	btn("制作回村符", _craft)
	if have < cost:
		text("材料不够。", 22, Color(1, 0.7, 0.6))

func _craft() -> void:
	if Game.recall.craft():
		var v := get_parent()
		if v and v.has_method("show_toast"):
			v.show_toast("做成了" + Game.recall.display_name)
	rebuild()
