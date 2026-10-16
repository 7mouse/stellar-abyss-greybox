extends Panel2
## 回村后整理背包。材料可以存进仓库，装备和钥匙道具可以放进保险箱

func _init() -> void:
	title = "整理背包"

func _fill() -> void:
	var run := Game.run
	if run == null:
		text("没有进行中的探索")
		return
	text("可以调整顺序，也可以把材料存进仓库，或把装备放进保险箱。", 22, Color(0.75, 0.85, 0.95))
	if run.bag.is_empty():
		text("背包是空的")
		return
	for i in run.bag.size():
		var st: ItemStack = run.bag[i]
		var row := HBoxContainer.new()
		body.add_child(row)
		var l := Label.new()
		l.text = "%s ×%d" % [st.item.display_name, st.count]
		l.custom_minimum_size = Vector2(360, 0)
		l.add_theme_font_size_override("font_size", 24)
		row.add_child(l)
		var up := Button.new()
		up.text = "上移"
		up.disabled = i == 0
		up.pressed.connect(_move.bind(i, -1))
		row.add_child(up)
		var down := Button.new()
		down.text = "下移"
		down.disabled = i == run.bag.size() - 1
		down.pressed.connect(_move.bind(i, 1))
		row.add_child(down)
		if st.item.category in ["material", "rare_material"]:
			var dep := Button.new()
			dep.text = "存入仓库"
			dep.pressed.connect(_store.bind(st.item.id))
			row.add_child(dep)
		elif Lineage.can_vault(st.item):
			var dep2 := Button.new()
			dep2.text = "放入保险箱"
			dep2.pressed.connect(_store.bind(st.item.id))
			row.add_child(dep2)

func _move(i: int, dir: int) -> void:
	if Game.run == null:
		return
	Game.run.swap_bag(i, i + dir)
	rebuild()

func _store(id: String) -> void:
	Game.store_bag(id)
	rebuild()
