extends Node2D
## 起程村：自由走动，设施互动范围 64px（有提示）。第一次进入播放开场（之后在布告栏重播，可跳过）

const MAP := Vector2(2400, 1400)
var player: Player
var cam: FollowCam
var prompt: Label
var title_label: Label
var toast: Label
var facilities: Array = [] ## {id, name, pos, size, color, cb}
var opening: CanvasLayer
var opening_label: Label
var opening_skippable := false
var panel_open: Panel2
var _toast_t := 0.0
var _intro_visit := false
var _settings: CanvasLayer

func _ready() -> void:
	UI.rect(self, Vector2.ZERO, MAP, Color(0.16, 0.19, 0.15)).z_index = -10
	UI.rect(self, Vector2(900, 500), Vector2(600, 400), Color(0.22, 0.24, 0.2)).z_index = -9 ## 广场
	for r in [Rect2(-40, -40, MAP.x + 80, 40), Rect2(-40, MAP.y, MAP.x + 80, 40), Rect2(-40, 0, 40, MAP.y), Rect2(MAP.x, 0, 40, MAP.y)]:
		_wall(r)
	_fac("incubator", "培养槽", Vector2(500, 380), Vector2(120, 160), Color(0.35, 0.8, 0.85), func(): _open("res://scenes/village/incubator.gd"))
	_fac("vault", "保险箱", Vector2(820, 420), Vector2(140, 100), Color(0.7, 0.6, 0.3), _vault)
	_fac("epitaph", "墓志铭墙", Vector2(1250, 340), Vector2(320, 60), Color(0.55, 0.55, 0.6), func(): _open("res://scenes/village/epitaph_wall.gd"))
	_fac("bench", "简易强化台", Vector2(1700, 380), Vector2(140, 90), Color(0.6, 0.4, 0.3), _bench)
	_fac("well", "下潜井口", Vector2(1200, 1100), Vector2(160, 160), Color(0.08, 0.08, 0.1), _dive)
	_fac("board", "布告栏", Vector2(400, 900), Vector2(120, 80), Color(0.5, 0.42, 0.3), func(): play_opening(true))
	_intro_visit = not Lineage.flags.get("opening_seen", false)
	var npc_pos := Vector2(1380, 1100) if _intro_visit else Vector2(1550, 800)
	_fac("npc", "老冒险者", npc_pos, Vector2(40, 64), Color(0.75, 0.7, 0.55), _talk_elder)
	_fac("craft", "制作回村符", Vector2(1880, 980), Vector2(220, 90), Color(0.72, 0.48, 0.22), func(): _open("res://scenes/village/craft_ui.gd"))
	player = Player.new()
	player.position = Vector2(1200, 700)
	add_child(player)
	cam = FollowCam.new()
	cam.target = player
	add_child(cam)
	cam.make_current()
	cam.snap()
	var hud := CanvasLayer.new()
	hud.layer = 10
	add_child(hud)
	title_label = UI.label(hud, "", Vector2(40, 30), 28)
	prompt = UI.label(hud, "", Vector2(700, 900), 30, Color(1, 0.95, 0.6))
	toast = UI.label(hud, "", Vector2(560, 160), 32, Color(0.85, 1, 0.85))
	UI.label(hud, "F1 / ` 调试", Vector2(40, 1020), 22, Color(0.7, 0.7, 0.7))
	var settings_b := Button.new()
	settings_b.text = "设置"
	settings_b.position = Vector2(1760, 24)
	settings_b.custom_minimum_size = Vector2(120, 48)
	settings_b.focus_mode = Control.FOCUS_ALL
	settings_b.add_theme_font_size_override("font_size", 24)
	settings_b.pressed.connect(_open_settings)
	hud.add_child(settings_b)
	Tutorial.notify("village")
	if Tutorial.take_epitaph_flash():
		_flash_epitaph()
	if Game.run and Game.run.suspended:
		_recall_facilities()
	if not Lineage.flags.get("opening_seen", false):
		play_opening(false)

func _wall(r: Rect2) -> void:
	var sb := StaticBody2D.new()
	var cs := CollisionShape2D.new()
	var sh := RectangleShape2D.new()
	sh.size = r.size
	cs.shape = sh
	cs.position = r.get_center()
	sb.add_child(cs)
	add_child(sb)

func _fac(id: String, n: String, pos: Vector2, size: Vector2, color: Color, cb: Callable) -> void:
	var rect := UI.rect(self, pos - size / 2, size, color)
	rect.z_index = -5
	UI.label(self, n, pos + Vector2(-size.x / 2, -size.y / 2 - 40), 24)
	facilities.append({"id": id, "name": n, "pos": pos, "size": size, "cb": cb, "rect": rect})

func facility(id: String) -> Dictionary:
	for f in facilities:
		if f.id == id:
			return f
	return {}

func nearest() -> Dictionary:
	var best := {}
	var bd := INF
	for f in facilities:
		var r := Rect2(f.pos - f.size / 2, f.size)
		var d := _dist_to_rect(player.global_position, r)
		if d <= Game.player_stats.interact_range and d < bd:
			bd = d
			best = f
	return best

func _dist_to_rect(p: Vector2, r: Rect2) -> float:
	var q := Vector2(clampf(p.x, r.position.x, r.end.x), clampf(p.y, r.position.y, r.end.y))
	return p.distance_to(q)

func _process(delta: float) -> void:
	var ind := Lineage.current()
	title_label.text = "起程村　%s　Lv%d　萤苔 %d　萤苔精 %d　记忆碎片 %d　保险箱 %d/%d" % [ind.name, ind.level, Lineage.mats.moss, Lineage.mats.moss_essence, Lineage.shards_bank, Lineage.vault.size(), Lineage.vault_capacity()]
	var f := nearest()
	prompt.text = ("【%s】%s" % [InputGlyph.interact(), f.name]) if not f.is_empty() and panel_open == null and opening == null else ""
	_toast_t -= delta
	toast.visible = _toast_t > 0.0

func show_toast(t: String) -> void:
	toast.text = t
	_toast_t = 3.0

func _unhandled_input(e: InputEvent) -> void:
	if opening:
		if opening_skippable and (e.is_action_pressed("ui_accept") or e.is_action_pressed("interact") or e.is_action_pressed("ui_cancel")):
			_end_opening()
		return
	if e.is_action_pressed("interact") and panel_open == null:
		interact()

func interact() -> bool:
	var f := nearest()
	if f.is_empty():
		return false
	f.cb.call()
	return true

func _open(script_path: String) -> Panel2:
	var p: Panel2 = load(script_path).new()
	panel_open = p
	p.closed.connect(func(): panel_open = null)
	add_child(p)
	return p

func _vault() -> void:
	_open("res://scenes/village/vault_ui.gd")

func _bench() -> void:
	_open("res://scenes/village/bench.gd")

func _talk_elder() -> void:
	if _intro_visit:
		show_toast(Tutorial.rules.elder_text)
	else:
		show_toast("老冒险者：“往下走吧，越深越好。”")

func _open_settings() -> void:
	if _settings:
		return
	_settings = CanvasLayer.new()
	_settings.layer = 40
	add_child(_settings)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.size = Vector2(1920, 1080)
	dim.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed:
			_close_settings()
	)
	_settings.add_child(dim)
	var box := VBoxContainer.new()
	box.position = Vector2(700, 360)
	_settings.add_child(box)
	SettingsControls.fill(box)
	var close := Button.new()
	close.text = "关闭"
	close.custom_minimum_size = Vector2(420, 64)
	close.focus_mode = Control.FOCUS_ALL
	close.add_theme_font_size_override("font_size", 28)
	close.pressed.connect(_close_settings)
	box.add_child(close)
	close.grab_focus()

func _close_settings() -> void:
	if _settings:
		_settings.queue_free()
		_settings = null

func _flash_epitaph() -> void:
	var fac := facility("epitaph")
	var rect: CanvasItem = fac.get("rect")
	if rect == null:
		return
	var tw := create_tween()
	tw.tween_property(rect, "modulate", Color(3, 3, 2.4), 0.12)
	tw.tween_property(rect, "modulate", Color.WHITE, 0.45)

func _dive() -> void:
	if Game.run and Game.run.suspended:
		show_toast("探索还没结束，不能重新下潜")
		return
	Game.start_run()

func _recall_facilities() -> void:
	player.hp = mini(Game.run.hp, player.max_hp)
	_fac("rest", "回复生命", Vector2(860, 1100), Vector2(180, 90), Color(0.3, 0.65, 0.35), _rest)
	_fac("bag", "整理背包", Vector2(1560, 1100), Vector2(180, 90), Color(0.3, 0.45, 0.7), _bag)
	_fac("return", "返回第 %d 层" % Game.run.depth, Vector2(1200, 860), Vector2(240, 90), Color(0.42, 0.32, 0.62), _return_floor)
	if Game.run.just_recalled:
		Game.run.just_recalled = false
		show_toast("已回到起程村。层主没死就不算撤离，身上的东西仍会丢失。")

func _rest() -> void:
	if Game.run == null:
		return
	player.hp = player.max_hp
	Game.run.hp = player.hp
	show_toast("生命已恢复")

func _bag() -> void:
	_open("res://scenes/village/bag_ui.gd")

func _return_floor() -> void:
	Game.recall_return()

# ---------- 开场（方案 B；保留“死了就是真死”台词） ----------
const OPENING := [["black", "23:47。楼梯。"], ["black", "有人推了我一把。"], ["sky", "【系统】欢迎来到起程村。"], ["sky", "【系统】打穿第 100 层就能回去。"], ["sky", "【系统】在这里死了，就是真的死了。"]]

func play_opening(skippable: bool) -> void:
	if opening:
		return
	opening_skippable = skippable
	opening = CanvasLayer.new()
	opening.layer = 70
	opening.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(opening)
	var bg := UI.rect(opening, Vector2.ZERO, Vector2(1920, 1080), Color.BLACK)
	opening_label = UI.label(opening, "", Vector2(560, 480), 44)
	if skippable:
		UI.label(opening, "按 确认/E 跳过", Vector2(1600, 1020), 22, Color(0.6, 0.6, 0.6))
	player.input_enabled = false
	for line in OPENING:
		if opening == null:
			return
		bg.color = Color.BLACK if line[0] == "black" else Color(0.15, 0.2, 0.35, 0.85)
		opening_label.text = line[1]
		await get_tree().create_timer(2.0).timeout
	_end_opening()

func _end_opening() -> void:
	if opening == null:
		return
	opening.queue_free()
	opening = null
	player.input_enabled = true
	Lineage.flags["opening_seen"] = true
	Lineage.save()
