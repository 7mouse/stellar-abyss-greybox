extends Panel2
## 培养槽：当前个体信息

func _init() -> void:
	title = "培养槽"

func _fill() -> void:
	var ind := Lineage.current()
	text("%s　第 %d 代　Lv%d" % [ind.name, ind.gen_no, ind.level], 32)
	var t: Dictionary = Stats.TRAITS.get(ind.trait, {})
	var f: Dictionary = Stats.FLAWS.get(ind.flaw, {})
	text("特质（模板差异）：" + (("%s（%s）" % [t.name, t.desc]) if t else "无"))
	text("缺陷（模板差异）：" + (("%s（%s）" % [f.name, f.desc]) if f else "无"))
	var legs: Array = ind.legacies.map(func(id): var b := Boons.get_boon(id); return b.display_name if b else id)
	text("遗志（%d/%d，按原效果 %d%% 生效）：%s" % [legs.size(), Lineage.legacy_rules.legacy_max, roundi(Lineage.legacy_rules.legacy_power * 100), "、".join(legs) if legs else "无"])
	var m: Dictionary = ind.get("mastery", {})
	text("熟练度数据（只记录）：根须短刃 %d" % int(m.get("root_blade", 0)), 22, Color(0.7, 0.7, 0.8))
	text("局外：萤苔 %d　萤苔精 %d　记忆碎片 %d" % [Lineage.mats.moss, Lineage.mats.moss_essence, Lineage.shards_bank], 22, Color(0.7, 0.9, 0.7))
