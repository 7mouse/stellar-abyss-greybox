class_name Mastery
extends RefCounted
## 武器熟练度：灰盒只记录使用次数（继承时按 mastery_ratio 保留，不生效）

static func use(weapon: String) -> void:
	var lin = Engine.get_main_loop().root.get_node_or_null("Lineage")
	if lin == null or lin.individuals.is_empty():
		return
	var m: Dictionary = lin.current().get("mastery", {})
	m[weapon] = int(m.get(weapon, 0)) + 1
	lin.current()["mastery"] = m
