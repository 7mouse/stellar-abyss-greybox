extends Control
## 遗志选择：从死亡时持有的最后 3 个强化里选 1 个写回（按原效果 legacy_power 生效）；已满 5 个时要替换一个

var box: VBoxContainer
var picked := ""
var candidates: Array = []

func _ready() -> void:
	UI.rect(self, Vector2.ZERO, Vector2(1920, 1080), Color(0.08, 0.1, 0.14))
	UI.label(self, "选择要写回的那条记忆", Vector2(120, 80), 46)
	UI.label(self, "遗志按强化原效果的 %d%% 生效；残缺的意识最多只能承载 %d 条" % [roundi(Lineage.legacy_rules.legacy_power * 100), Lineage.legacy_rules.legacy_max], Vector2(120, 150), 26, Color(0.75, 0.75, 0.85))
	var nl := Lineage.legacy_rules.inherit_level(int(Game.last_death.get("level", 1)))
	UI.label(self, "下一个个体：%s，从 Lv%d 起步" % [Lineage.individual_name(Lineage.gen_counter + 1), nl], Vector2(120, 200), 26, Color(0.7, 0.9, 0.8))
	candidates = Game.last_death.get("candidates", [])
	box = VBoxContainer.new()
	box.position = Vector2(120, 280)
	box.add_theme_constant_override("separation", 12)
	add_child(box)
	rebuild()

func rebuild() -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()
	var legs: Array = Lineage.current().legacies
	if picked == "":
		if candidates.is_empty():
			var l := Label.new()
			l.text = "这一次没有可以写回的记忆。"
			l.add_theme_font_size_override("font_size", 28)
			box.add_child(l)
		for id in candidates:
			var b := Boons.get_boon(id)
			UI.button(box, "%s：%s" % [b.display_name, b.desc], _pick.bind(id), Vector2(1000, 64))
		UI.button(box, "不写回，直接苏醒", _pick.bind("-"), Vector2(1000, 64), Color(0.3, 0.3, 0.35))
	else:
		var l2 := Label.new()
		l2.text = "遗志已满 %d 条，选择要替换掉的一条：" % legs.size()
		l2.add_theme_font_size_override("font_size", 28)
		box.add_child(l2)
		for i in legs.size():
			UI.button(box, "替换：" + Boons.get_boon(legs[i]).display_name, func(): Game.finish_legacy(picked, i), Vector2(1000, 64))
		UI.button(box, "算了，不写回", func(): Game.finish_legacy(""), Vector2(1000, 64), Color(0.3, 0.3, 0.35))
	for c in box.get_children():
		if c is Button:
			c.grab_focus.call_deferred()
			break

func _pick(id: String) -> void:
	if id == "-":
		Game.finish_legacy("")
		return
	var legs: Array = Lineage.current().legacies
	if id in legs:
		Game.finish_legacy("")
		return
	if legs.size() >= Lineage.legacy_rules.legacy_max:
		picked = id
		rebuild()
		return
	Game.finish_legacy(id)
