extends Panel2
## 用任意层的层主稀有材料（萤苔精）做 1 张回村符。已经持有时按钮变灰

func _init() -> void:
	title = "制作回村符"

func _fill() -> void:
	var rules := Game.recall
	var have := rules.craft_material_have()
	var cost := rules.craft_material_count
	var owned := rules.owned() >= rules.max_owned
	text("任意层的层主材料都可以。萤苔精 %d / %d。" % [have, cost], 22, Color(0.95, 0.85, 0.65))
	if owned:
		text("已经持有回村符，不能再做。", 22, Color(1, 0.75, 0.55))
	btn("制作回村符", _craft, not owned)
	if not owned and have < cost:
		text("材料不够。", 22, Color(1, 0.7, 0.6))

func _craft() -> void:
	if Game.recall.craft():
		var v := get_parent()
		if v and v.has_method("show_toast"):
			v.show_toast("做成了" + Game.recall.display_name)
	rebuild()
