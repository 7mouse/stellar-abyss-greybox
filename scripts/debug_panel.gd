extends CanvasLayer
## F1 调试面板（骨架）：运行时编辑 Tunables 与各小游戏配置。T10 再补全掉落率、CSV 等。

var root: PanelContainer
var info: Label
var prob: Label
var depth_spin: SpinBox
var log_label: Label

func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	root = PanelContainer.new()
	root.position = Vector2(20, 20)
	root.size = Vector2(640, 1040)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.05, 0.08, 0.92)
	sb.set_content_margin_all(16)
	root.add_theme_stylebox_override("panel", sb)
	add_child(root)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(600, 1000)
	root.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	var title := Label.new()
	title.text = "调试面板（F1 / 手柄 Back 开关）"
	title.add_theme_font_size_override("font_size", 26)
	box.add_child(title)
	info = Label.new()
	box.add_child(info)
	prob = Label.new()
	prob.add_theme_color_override("font_color", Color(0.6, 1, 0.7))
	box.add_child(prob)
	var row := HBoxContainer.new()
	box.add_child(row)
	var dl := Label.new()
	dl.text = "当前层（下次生成生效）"
	row.add_child(dl)
	depth_spin = SpinBox.new()
	depth_spin.min_value = 1
	depth_spin.max_value = 99
	depth_spin.value_changed.connect(func(v): GameState.depth = int(v))
	row.add_child(depth_spin)
	var row2 := HBoxContainer.new()
	box.add_child(row2)
	for pair in [["回满血", func(): GameState.player_hp = GameState.tunables.player_max_hp], ["跳到下一层", _skip_floor], ["清空 CSV 日志", func(): GameState.clear_log()], ["局外材料 +20", func(): GameState.meta_materials += 20]]:
		var b := Button.new()
		b.text = pair[0]
		b.pressed.connect(pair[1])
		row2.add_child(b)
	log_label = Label.new()
	box.add_child(log_label)
	_section(box, "全局参数（含掉落率、背包、营地、上帝模式 god_mode）", GameState.tunables)
	for cfg in GameState.all_minigames():
		_section(box, "小游戏：" + cfg.display_name, cfg)
	for e in GameState.enemy_types:
		_section(box, "敌人：" + e.display_name + "（attack = 伤害）", e)
	root.visible = false

func _process(_d: float) -> void:
	if root.visible:
		info.text = "当前层：%d  掉落倍率：%d%%  HP：%d  材料：%d  碎片：%d" % [GameState.depth, roundi(GameState.loot_mult * 100), GameState.player_hp, GameState.run_loot.material, GameState.run_loot.shard]
		prob.text = probability_text()
		if not depth_spin.get_line_edit().has_focus():
			depth_spin.set_value_no_signal(GameState.depth)
		log_label.text = "试玩日志：%s" % ProjectSettings.globalize_path(GameState.log_path)

func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("debug_toggle"):
		toggle()
		get_viewport().set_input_as_handled()

func _skip_floor() -> void:
	if GameState.in_run:
		GameState.descend()
		GameState.goto(GameState.SCN_DUNGEON)

func toggle() -> void:
	root.visible = not root.visible

func is_open() -> bool:
	return root.visible

## 列出 Resource 的所有 int/float/bool 导出变量，生成可编辑控件（改动即时写回 Resource）
func _section(box: VBoxContainer, title: String, res: Resource) -> void:
	var h := Label.new()
	h.text = "— " + title + " —"
	h.add_theme_color_override("font_color", Color(1, 0.85, 0.3))
	box.add_child(h)
	for p in res.get_property_list():
		if not (p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		var t: int = p.type
		if t != TYPE_INT and t != TYPE_FLOAT and t != TYPE_BOOL:
			continue
		var row := HBoxContainer.new()
		var l := Label.new()
		l.text = p.name
		l.custom_minimum_size = Vector2(330, 0)
		row.add_child(l)
		var pname: String = p.name
		if t == TYPE_BOOL:
			var c := CheckBox.new()
			c.button_pressed = res.get(pname)
			c.toggled.connect(func(v): res.set(pname, v))
			row.add_child(c)
		else:
			var s := SpinBox.new()
			s.set_meta("res", res)
			s.set_meta("prop", pname)
			s.min_value = -100000
			s.max_value = 100000
			s.step = 1.0 if t == TYPE_INT else 0.01
			s.value = res.get(pname)
			s.custom_minimum_size = Vector2(200, 0)
			s.value_changed.connect(func(v): res.set(pname, int(v) if t == TYPE_INT else v))
			row.add_child(s)
		box.add_child(row)

## 运气小游戏的实际概率（随幸运与参数实时变化）
func probability_text() -> String:
	var lk := GameState.luck()
	var lines := ["运气实际概率（幸运 %d）：" % lk]
	var r: LuckConfig = GameState.mg_rps
	var pr: Array = r.outcome_probs(lk)
	lines.append("猜拳 单局胜率 %.1f%%｜PERFECT %.1f%% GOOD %.1f%% FAIL %.1f%%" % [r.rps_win_rate(lk) * 100, pr[0] * 100, pr[1] * 100, pr[2] * 100])
	var d: LuckConfig = GameState.mg_dice
	var pd: Array = d.outcome_probs(lk)
	lines.append("骰子 首掷成功 %.1f%% 重掷 %.1f%%｜PERFECT %.1f%% GOOD %.1f%% FAIL %.1f%%" % [d.dice_base_rate() * 100, d.dice_reroll_rate(lk) * 100, pd[0] * 100, pd[1] * 100, pd[2] * 100])
	return "\n".join(lines)

## 找到某个资源某个参数对应的输入框（测试用）
func find_editor(res: Resource, prop: String) -> SpinBox:
	for n in root.find_children("*", "SpinBox", true, false):
		if n.has_meta("res") and n.get_meta("res") == res and n.get_meta("prop", "") == prop:
			return n
	return null
