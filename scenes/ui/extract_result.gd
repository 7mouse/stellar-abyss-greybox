extends Control
## 撤离结算：带回全部收获，然后选择放入保险箱。没放入的装备留在身上（下次下潜算局内装备）

var box: VBoxContainer
var info: Label
var pending: Array = [] ## 待处理的装备 id
var replacing := ""

func _ready() -> void:
	UI.rect(self, Vector2.ZERO, Vector2(1920, 1080), Color(0.1, 0.13, 0.12))
	UI.label(self, "撤离成功", Vector2(120, 80), 48, Color(0.6, 1, 0.7))
	var got: Dictionary = Game.last_extract
	pending = got.get("equipment", []).duplicate()
	info = UI.label(self, "带回：萤苔 %d　萤苔精 %d　记忆碎片 %d　装备 %d 件" % [got.get("moss", 0), got.get("moss_essence", 0), got.get("shards", 0), pending.size()], Vector2(120, 170), 30)
	box = VBoxContainer.new()
	box.position = Vector2(120, 260)
	box.add_theme_constant_override("separation", 10)
	add_child(box)
	rebuild()

func rebuild() -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()
	var l := Label.new()
	l.text = "放入保险箱（%d / %d）：" % [Lineage.vault.size(), Lineage.vault_capacity()]
	l.add_theme_font_size_override("font_size", 28)
	box.add_child(l)
	if replacing != "":
		for i in Lineage.vault.size():
			UI.button(box, "换出：" + Items.get_item(Lineage.vault[i].id).display_name, _replace.bind(i), Vector2(900, 56))
		UI.button(box, "取消替换", func(): replacing = ""; rebuild(), Vector2(900, 56))
	else:
		for id in pending:
			UI.button(box, "放入：" + Items.get_item(id).display_name, _put.bind(id), Vector2(900, 56))
		if Lineage.mats.moss_essence > 0:
			UI.button(box, "放入：萤苔精 ×1（稀有材料）", _put.bind("moss_essence"), Vector2(900, 56))
		var b1 := UI.button(box, "记忆碎片（不能放入，已存入剧情库）", func(): pass, Vector2(900, 56))
		b1.disabled = true
		var b2 := UI.button(box, "局内强化 ×%d（不能放入，随本局消失）" % (Game.run.boons.size() if Game.run else 0), func(): pass, Vector2(900, 56))
		b2.disabled = true
		UI.button(box, "完成，回村", finish, Vector2(900, 64), Color(0.25, 0.45, 0.3))
	for c in box.get_children():
		if c is Button and not c.disabled:
			c.grab_focus.call_deferred()
			break

func _put(id: String) -> void:
	if Lineage.vault.size() >= Lineage.vault_capacity():
		replacing = id
		rebuild()
		return
	if Lineage.vault_put(id):
		if id == "moss_essence":
			Lineage.mats.moss_essence -= 1
		else:
			pending.erase(id)
		Lineage.save()
	rebuild()

func _replace(i: int) -> void:
	var old := Lineage.vault_replace(i, replacing)
	if not old.is_empty():
		if replacing == "moss_essence":
			Lineage.mats.moss_essence -= 1
		else:
			pending.erase(replacing)
		if Items.get_item(old.id).category == "equipment":
			pending.append(old.id)
		else:
			Lineage.mats[old.id] = int(Lineage.mats.get(old.id, 0)) + int(old.count)
	replacing = ""
	Lineage.save()
	rebuild()

func finish() -> void:
	for id in pending:
		Lineage.loadout.append(id)
	pending.clear()
	Lineage.save()
	Game.run = null
	Game.goto(Game.SCN_VILLAGE)
