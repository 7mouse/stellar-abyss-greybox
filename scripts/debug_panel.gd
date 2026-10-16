extends CanvasLayer
## F1 / ` / 手柄 Back 调试面板：按分组折叠；反射 Resource 的 int/float/bool/String 字段生成编辑器，改动立即生效；可导出为 .tres

var root: PanelContainer
var box: VBoxContainer
var info: Label
var drop_label: Label
var spawn_kind: OptionButton
var spawn_count: SpinBox
var floor_spin: SpinBox
var boon_pick: OptionButton
var seed_spin: SpinBox
var groups := {} ## 名称 -> VBoxContainer
var show_chunks := false ## 显示区块网格（楼层每帧读取）
var show_aggro := false ## 显示视野锥和声音圈
var sleep_all := false ## 全图怪物休眠
var aggro_label: Label
var map_label: Label
var risk_label: Label

func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	root = PanelContainer.new()
	root.position = Vector2(20, 20)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.05, 0.08, 0.93)
	sb.set_content_margin_all(14)
	root.add_theme_stylebox_override("panel", sb)
	add_child(root)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(760, 1020)
	root.add_child(scroll)
	box = VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	_lbl(box, "调试面板（F1 / ` / 手柄 Back 开关）", 26)
	info = _lbl(box, "", 20)
	_build_tools()
	var g := Game
	_section("玩家", "主角参数", g.player_stats)
	for a in g.attacks:
		_section("攻击", a.display_name, a)
	_section("攻击", g.skill.display_name, g.skill)
	for id in g.enemies:
		_section("敌人：" + g.enemies[id].display_name, g.enemies[id].display_name, g.enemies[id])
	for fd in g.floors:
		_section("层主", fd.lord().display_name, fd.lord())
		_affix_toggles("层主", fd.lord())
		if fd.ecology:
			_section("生态", "第 %d 层：%s（改 biome_bias 等后重新生成本层生效）" % [fd.depth, fd.ecology.display_name], fd.ecology)
	for hid in ["spore_pod", "root_snare", "falling_rock", "root_pillar"]:
		var hr: HazardData = load("res://data/hazards/%s.tres" % hid)
		_section("生态", "机关：" + hr.display_name, hr)
	for id in g.affixes:
		_section("层主", "词缀：" + g.affixes[id].display_name, g.affixes[id])
	for fd in g.floors:
		_section("楼层", "第 %d 层" % fd.depth, fd)
	_section("仇恨", "全局仇恨参数 aggro_rules.tres（= 第 3 层）", load("res://data/aggro_rules.tres"))
	for fd in g.floors:
		if fd.aggro_override:
			_section("仇恨", "第 %d 层覆盖（只有和默认值不同的字段生效）" % fd.depth, fd.aggro_override)
	for id in ["enemy_common", "guard_1", "guard_2", "guard_3", "chest", "node"]:
		_loot_section(load("res://data/loot_tables/%s.tres" % id))
	_section("遗志", "继承规则（legacy_power = 遗志生效比例）", Lineage.legacy_rules)
	_section("保险箱", "保险箱规则", Lineage.vault_rules)
	_section("保险箱", "强化台（局外）", Lineage.meta_rules)
	_section("线索", "虚拟世界线索 clues.tres", g.clues)
	_section("回村符", "紧急回村符 recall_charm.tres", g.recall)
	_section("打击感", "hit_feel.tres", g.hit_feel)
	_section("教学", "tutorial_rules.tres", load("res://data/tutorial/tutorial_rules.tres"))
	_btn(_group("教学"), "重置教学", func(): Tutorial.reset_progress())
	_btn(_group("回村符"), "发 1 张回村符到身上", give_recall_charm)
	risk_label = _lbl(_group("回村符"), "", 18)
	root.visible = false

func set_aggro_counts(chasing: int, windup: int, chase_peak: int, windup_peak: int) -> void:
	if aggro_label and root.visible:
		var R: AggroRules = load("res://data/aggro_rules.tres")
		aggro_label.text = "追击 %d / %d，前摇 %d / %d（本层峰值 %d / %d）" % [chasing, R.max_chasers, windup, R.max_attackers, chase_peak, windup_peak]

func _lbl(parent: Node, t: String, size := 20) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", size)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 720
	parent.add_child(l)
	return l

func _btn(parent: Node, t: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = t
	b.pressed.connect(cb)
	parent.add_child(b)
	return b

func _row(parent: Node) -> HBoxContainer:
	var r := HBoxContainer.new()
	parent.add_child(r)
	return r

func _check(parent: Node, t: String, val: bool, cb: Callable) -> CheckBox:
	var c := CheckBox.new()
	c.text = t
	c.button_pressed = val
	c.toggled.connect(cb)
	parent.add_child(c)
	return c

func _build_tools() -> void:
	var tools := _group("调试按钮", true)
	var r1 := _row(tools)
	_check(r1, "上帝模式", Game.god_mode, func(v): Game.god_mode = v)
	_check(r1, "无限冲刺", Game.inf_dash, func(v): Game.inf_dash = v)
	_check(r1, "显示受击框/攻击框", Game.show_boxes, func(v): Game.show_boxes = v)
	_check(r1, "记录 hits.csv", Log.hits_enabled, func(v): Log.hits_enabled = v)
	var r2 := _row(tools)
	_lbl(r2, "刷怪").custom_minimum_size.x = 60
	spawn_kind = OptionButton.new()
	for id in Game.enemies:
		spawn_kind.add_item(Game.enemies[id].display_name)
	r2.add_child(spawn_kind)
	spawn_count = SpinBox.new()
	spawn_count.min_value = 1
	spawn_count.max_value = 20
	spawn_count.value = 1
	r2.add_child(spawn_count)
	_btn(r2, "刷出", func(): spawn_enemies(Game.enemies.keys()[spawn_kind.selected], int(spawn_count.value)))
	_btn(r2, "传送到层主区（入口外侧）", debug_guard)
	var rm := _row(tools)
	_check(rm, "显示区块网格", show_chunks, func(v): show_chunks = v)
	_check(rm, "显示视野锥和声音圈", show_aggro, func(v): show_aggro = v)
	_check(rm, "全图怪物休眠", sleep_all, func(v): sleep_all = v)
	_btn(rm, "地图统计", func(): map_label.text = map_stats_text())
	map_label = _lbl(tools, "")
	aggro_label = _lbl(tools, "追击 0 / 6，前摇 0 / 3")
	var r3 := _row(tools)
	floor_spin = SpinBox.new()
	floor_spin.min_value = 1
	floor_spin.max_value = 3
	r3.add_child(floor_spin)
	_btn(r3, "跳到第 n 层", func(): jump_floor(int(floor_spin.value)))
	_lbl(r3, "种子（-1 随机，下一局生效）").custom_minimum_size.x = 240
	seed_spin = SpinBox.new()
	seed_spin.min_value = -1
	seed_spin.max_value = 999999
	seed_spin.value = Game.run_seed_override
	seed_spin.value_changed.connect(func(v): Game.run_seed_override = int(v))
	r3.add_child(seed_spin)
	var r4 := _row(tools)
	boon_pick = OptionButton.new()
	for b in Boons.all():
		boon_pick.add_item(b.display_name)
	r4.add_child(boon_pick)
	_btn(r4, "给予强化", func(): give_boon(Boons.all()[boon_pick.selected].id))
	_btn(r4, "移除强化", func(): remove_boon(Boons.all()[boon_pick.selected].id))
	var r5 := _row(tools)
	_btn(r5, "杀死自己", kill_self)
	_btn(r5, "材料 +50", func(): add_mats(50))
	_btn(r5, "清空存档", func(): Lineage.wipe())
	_btn(r5, "下载 CSV", func(): Log.download_all())
	_btn(r5, "刷 1000 只怪（掉落统计）", func(): drop_label.text = drop_stats_text(1000))
	drop_label = _lbl(tools, "")
	_btn(tools, "导出全部参数为 .tres（user://export/）", export_all)

func _group(name: String, open := false) -> VBoxContainer:
	if groups.has(name):
		return groups[name]
	var head := Button.new()
	head.text = ("▼ " if open else "▶ ") + name
	head.alignment = HORIZONTAL_ALIGNMENT_LEFT
	head.add_theme_color_override("font_color", Color(1, 0.85, 0.3))
	box.add_child(head)
	var g := VBoxContainer.new()
	g.visible = open
	box.add_child(g)
	head.pressed.connect(func(): g.visible = not g.visible; head.text = ("▼ " if g.visible else "▶ ") + name)
	groups[name] = g
	return g

## 列出 Resource 的 int/float/bool/String 导出变量，生成可编辑控件（改动即时写回 Resource）
func _section(group: String, title: String, res: Resource) -> void:
	var g := _group(group)
	var h := _row(g)
	_lbl(h, "— " + title + " —").custom_minimum_size.x = 520
	_btn(h, "导出 .tres", func(): export_res(res))
	for p in res.get_property_list():
		if not (p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		var t: int = p.type
		if not t in [TYPE_INT, TYPE_FLOAT, TYPE_BOOL, TYPE_STRING]:
			continue
		var row := _row(g)
		var l := _lbl(row, p.name, 18)
		l.custom_minimum_size.x = 300
		var pname: String = p.name
		var c: Control
		if t == TYPE_STRING:
			var le := LineEdit.new()
			le.text = res.get(pname)
			le.custom_minimum_size = Vector2(420, 0)
			le.text_changed.connect(func(v): res.set(pname, v))
			c = le
		elif t == TYPE_BOOL:
			var cb := CheckBox.new()
			cb.button_pressed = res.get(pname)
			cb.toggled.connect(func(v): res.set(pname, v))
			c = cb
		else:
			var s := SpinBox.new()
			s.min_value = -100000
			s.max_value = 100000
			s.step = 1.0 if t == TYPE_INT else 0.01
			s.value = res.get(pname)
			s.custom_minimum_size = Vector2(200, 0)
			s.value_changed.connect(func(v): res.set(pname, int(v) if t == TYPE_INT else v))
			c = s
		c.set_meta("res", res)
		c.set_meta("prop", pname)
		row.add_child(c)

func _affix_toggles(group: String, gd: GuardData) -> void:
	var r := _row(_group(group))
	_lbl(r, "  词缀组合：", 18).custom_minimum_size.x = 140
	for id in Game.affixes:
		var a: AffixData = Game.affixes[id]
		var c := _check(r, a.display_name, gd.affixes.has(a), func(v): set_guard_affix(gd, a, v))
		c.set_meta("res", gd)
		c.set_meta("prop", "affix_" + id)

func set_guard_affix(gd: GuardData, a: AffixData, on: bool) -> void:
	if on and not gd.affixes.has(a):
		gd.affixes.append(a)
	elif not on:
		gd.affixes.erase(a)
	for g in get_tree().get_nodes_in_group("guards"):
		if g.gdata == gd:
			g.set_affixes(gd.affixes.duplicate())

func _loot_section(lt: LootTable) -> void:
	var g := _group("掉落")
	var h := _row(g)
	_lbl(h, "— 掉落表 " + lt.id + " —").custom_minimum_size.x = 520
	_btn(h, "导出 .tres", func(): export_res(lt))
	for e in lt.entries:
		var row := _row(g)
		_lbl(row, "%s（%d~%d）概率" % [e.item, e.min, e.max], 18).custom_minimum_size.x = 300
		var s := SpinBox.new()
		s.min_value = 0
		s.max_value = 1
		s.step = 0.01
		s.value = e.chance
		s.value_changed.connect(func(v): e.chance = v)
		row.add_child(s)

func _process(_d: float) -> void:
	if root.visible:
		var r := Game.run
		info.text = "个体 %s　局：%s　层 %d　种子 %s\n存档：%s　CSV：%s" % [Lineage.current().name, r.id if r else "—", r.depth if r else 0, str(r.seed) if r else "—",
			ProjectSettings.globalize_path(Lineage.save_path), ProjectSettings.globalize_path(Log.dir)]
		if risk_label:
			var s: Dictionary = Log.risk_summary()
			var stock: int = Game.recall.stock() if Game.recall else 0
			risk_label.text = "回村并存物 %d/%d 局（%.0f%%）　未击杀层主带出材料 合计 %d　平均 %.2f　回村符库存 %d" % [int(s.stash_runs), int(s.runs), float(s.share) * 100.0, int(s.unbossed_sum), float(s.unbossed_avg), stock]

func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("debug_toggle"):
		toggle()
		get_viewport().set_input_as_handled()

func toggle() -> void:
	root.visible = not root.visible

func is_open() -> bool:
	return root.visible

func find_editor(res: Resource, prop: String) -> Control:
	for n in root.find_children("*", "Control", true, false):
		if n.has_meta("res") and n.get_meta("res") == res and n.get_meta("prop", "") == prop:
			return n
	return null

# ---------- 调试操作 ----------
func _floor() -> Node:
	var s := get_tree().current_scene
	return s if s and s.scene_file_path == Game.SCN_FLOOR else null

func spawn_enemies(id: String, n: int) -> Array:
	var f := _floor()
	if f == null:
		return []
	var out := []
	for i in n:
		out.append(f.spawn_enemy(id, f.player.global_position + Vector2(260, 0).rotated(TAU * i / maxf(1, n))))
	return out

func debug_guard() -> void:
	var f := _floor()
	if f:
		f.debug_guard()

func map_stats_text() -> String:
	var f := _floor()
	return f.map_stats_text() if f else "不在楼层里"

func jump_floor(n: int) -> void:
	if Game.run == null:
		Game.start_run()
	Game.enter_floor(clampi(n, 1, Game.FINAL_FLOOR))

## 还没下潜时放进仓库，进层再按能带的张数带上。已经在局内就发放，多出来的封印
func give_recall_charm() -> void:
	if Game.recall == null:
		return
	if Game.run == null:
		Lineage.charm_carried += 1
		Lineage.charm_source = "debug"
		Lineage.save()
		return
	Game.recall.grant("debug")

func give_boon(id: String) -> void:
	if Game.run:
		Game.run.add_boon(Boons.get_boon(id))
		_refresh_player()

func remove_boon(id: String) -> void:
	if Game.run:
		Game.run.remove_boon(Boons.get_boon(id))
		_refresh_player()

func _refresh_player() -> void:
	for p in get_tree().get_nodes_in_group("player"):
		p.refresh_stats()

func kill_self() -> void:
	var f := _floor()
	if f:
		f.player.kill_self()
	else:
		## 不在迷宫里：直接走一次死亡记录（测试死亡流程）
		if Game.run == null:
			Game.run = Run.new()
			Game.run.id = "debug_%d" % Time.get_ticks_msec()
			Game.run.xp = int(Lineage.current().xp)
		Game.on_player_died("调试：杀死自己")

func add_mats(n: int) -> void:
	Lineage.mats.moss += n
	Lineage.mats.moss_essence += n
	Lineage.save()

## 用真实掉落表刷 n 只普通怪 + n 只各层主 + n 个宝箱，统计每项出现率
func drop_stats(n: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var out := {}
	for id in ["enemy_common", "guard_1", "guard_2", "guard_3", "chest", "node"]:
		var lt: LootTable = load("res://data/loot_tables/%s.tres" % id)
		var hits := {}
		for i in n:
			var seen := {}
			for st in lt.roll(rng):
				var k: String = "trinket_any" if st.item.category == "equipment" else st.item.id
				seen[k] = true
			for k in seen:
				hits[k] = int(hits.get(k, 0)) + 1
		var rates := {}
		for e in lt.entries:
			rates[e.item] = {"want": float(e.chance), "got": float(hits.get(e.item, 0)) / n}
		out[id] = rates
	return out

func drop_stats_text(n: int) -> String:
	var lines := []
	var d := drop_stats(n)
	for id in d:
		var parts := []
		for k in d[id]:
			parts.append("%s %.1f%%（设定 %.0f%%）" % [k, d[id][k].got * 100, d[id][k].want * 100])
		lines.append("%s：%s" % [id, "，".join(parts)])
	return "\n".join(lines)

func export_res(res: Resource) -> String:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://export"))
	var name := res.resource_path.get_file() if res.resource_path != "" else "resource.tres"
	var p := "user://export/" + name
	var copy := res.duplicate(true)
	ResourceSaver.save(copy, p)
	if OS.has_feature("web"):
		JavaScriptBridge.download_buffer(FileAccess.get_file_as_bytes(p), name, "text/plain")
	return p

func export_all() -> Array:
	var out := []
	var list: Array = [load("res://data/aggro_rules.tres"), Game.player_stats, Game.skill, Game.clues, Lineage.legacy_rules, Lineage.vault_rules, Lineage.meta_rules, Game.recall]
	list += Game.attacks
	list += Game.enemies.values()
	list += Game.floors
	for f in Game.floors:
		list.append(f.lord())
		if f.ecology:
			list.append(f.ecology)
	for r in list:
		out.append(export_res(r))
	return out
