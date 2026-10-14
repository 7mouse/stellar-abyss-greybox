extends CanvasLayer
## F1 调试面板（骨架）：运行时编辑 Tunables 与各小游戏配置。T10 再补全掉落率、CSV 等。

var root: PanelContainer
var info: Label

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
	_section(box, "全局参数", GameState.tunables)
	for cfg in [GameState.mg_slash, GameState.mg_heavy, GameState.mg_defense[1], GameState.mg_defense[2]]:
		_section(box, "小游戏：" + cfg.display_name, cfg)
	for e in GameState.enemy_types:
		_section(box, "敌人：" + e.display_name, e)
	root.visible = false

func _process(_d: float) -> void:
	if root.visible:
		info.text = "当前层：%d  掉落倍率：%d%%  HP：%d  材料：%d  碎片：%d" % [GameState.depth, roundi(GameState.loot_mult * 100), GameState.player_hp, GameState.run_loot.material, GameState.run_loot.shard]

func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("debug_toggle"):
		toggle()
		get_viewport().set_input_as_handled()

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
			s.min_value = -100000
			s.max_value = 100000
			s.step = 1.0 if t == TYPE_INT else 0.01
			s.value = res.get(pname)
			s.custom_minimum_size = Vector2(200, 0)
			s.value_changed.connect(func(v): res.set(pname, int(v) if t == TYPE_INT else v))
			row.add_child(s)
		box.add_child(row)
