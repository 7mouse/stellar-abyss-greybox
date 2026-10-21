extends Panel2
## 仓库：材料不限格数。有进行中的探索时可以从背包存入、取回背包。

func _init() -> void:
	title = "仓库"

func _fill() -> void:
	var any := false
	for id in Lineage.mats.keys():
		var n := int(Lineage.mats[id])
		if n <= 0:
			continue
		any = true
		var it := Items.get_item(str(id))
		var label := it.display_name if it else str(id)
		var row := HBoxContainer.new()
		body.add_child(row)
		var l := Label.new()
		l.text = "%s ×%d" % [label, n]
		l.custom_minimum_size = Vector2(360, 0)
		l.add_theme_font_size_override("font_size", 24)
		row.add_child(l)
		if Game.run:
			var take := Button.new()
			take.text = "取出"
			take.pressed.connect(_take.bind(str(id)))
			row.add_child(take)
	if not any:
		text("仓库是空的。", 22, Color(0.75, 0.75, 0.75))
	if Game.run == null:
		return
	text("背包里的材料可以存进来。", 22, Color(0.75, 0.85, 0.95))
	var seen := {}
	for st in Game.run.bag:
		if not (st.item.category in ["material", "rare_material"]):
			continue
		if seen.has(st.item.id):
			continue
		seen[st.item.id] = true
		var dep := Button.new()
		dep.text = "存入 %s" % st.item.display_name
		dep.pressed.connect(_store.bind(st.item.id))
		body.add_child(dep)

func _store(id: String) -> void:
	Game.store_bag(id)
	rebuild()

func _take(id: String) -> void:
	if Game.run == null:
		return
	var n := int(Lineage.mats.get(id, 0))
	if n <= 0:
		return
	var it := Items.get_item(id)
	if it == null:
		return
	Lineage.mats[id] = n - 1
	Lineage.save()
	Game.run.add_item(ItemStack.new(it, 1))
	rebuild()
