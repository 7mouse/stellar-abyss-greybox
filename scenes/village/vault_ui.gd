extends Panel2
## 保险箱：取出装备穿上（取出后算局内装备，死了会丢）；把身上的装备放进去；满了可以替换

var replacing := "" ## 正在替换的物品 id

func _init() -> void:
	title = "保险箱"

func _fill() -> void:
	text("容量 %d / %d（升级在强化台）　能放：装备、稀有材料、钥匙道具、升降梯燃料" % [Lineage.vault.size(), Lineage.vault_capacity()], 24)
	if replacing != "":
		text("选择要换出的格子（换出的东西回到身上）：", 24, Color(1, 0.9, 0.5))
		for i in Lineage.vault.size():
			var e: Dictionary = Lineage.vault[i]
			btn("换出：%s ×%d" % [Items.get_item(e.id).display_name, e.count], _replace.bind(i))
		btn("取消替换", func(): replacing = ""; rebuild())
		return
	for i in Lineage.vault.size():
		var e: Dictionary = Lineage.vault[i]
		btn("取出：%s ×%d" % [Items.get_item(e.id).display_name, e.count], _take.bind(i))
	text("身上：", 24)
	for id in Lineage.loadout:
		btn("放入：" + Items.get_item(id).display_name, _put.bind(id))
	if Lineage.mats.moss_essence > 0:
		btn("放入：萤苔精 ×1（稀有材料）", _put.bind("moss_essence"))
	btn("记忆碎片 ×%d（不能放入）" % Lineage.shards_bank, func(): pass, false)
	btn("局内强化（不能放入）", func(): pass, false)

func _take(i: int) -> void:
	Lineage.vault_take(i)
	rebuild()

func _put(id: String) -> void:
	if Lineage.vault.size() >= Lineage.vault_capacity():
		replacing = id
		rebuild()
		return
	if Lineage.vault_put(id):
		_remove_from_self(id)
	rebuild()

func _remove_from_self(id: String) -> void:
	if id == "moss_essence":
		Lineage.mats.moss_essence -= 1
	else:
		Lineage.loadout.erase(id)
	Lineage.save()

func _replace(i: int) -> void:
	var old := Lineage.vault_replace(i, replacing)
	if not old.is_empty():
		_remove_from_self(replacing)
		var it := Items.get_item(old.id)
		if it.category == "equipment":
			Lineage.loadout.append(old.id)
		else:
			Lineage.mats[old.id] = int(Lineage.mats.get(old.id, 0)) + int(old.count)
		Lineage.save()
	replacing = ""
	rebuild()
