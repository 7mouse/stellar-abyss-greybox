class_name Hud
extends CanvasLayer
## 局内 HUD：左上头像 / HP / MP / SP / 等级，右上层数、背包、碎片、暂停和圆形小地图，
## 右下是攻击键和围着它的一圈按钮，左下一格消耗品。MP、SP、重攻击、第二技能、消耗品还没有对应系统，显示占位。

const BAG_SLOTS := 12 ## 画面上的容量。灰盒背包还没有这个上限
const CREAM := Color(0.9, 0.86, 0.76)
const INK := Color(0.08, 0.07, 0.06, 0.82)
const HP_COLOR := Color(0.78, 0.16, 0.18)
const MP_COLOR := Color(0.22, 0.45, 0.86)
const SP_COLOR := Color(0.86, 0.62, 0.16)

var player: Player
var hp_bar: ColorRect
var hp_back: ColorRect
var hp_text: Label
var mp_bar: ColorRect
var sp_bar: ColorRect
var level_label: Label
var floor_label: Label
var bag_label: Label
var shard_label: Label
var info: Label
var skill_box: Control
var skill_label: Label
var skill2_label: Label
var prompt: Label
var toast: Label
var boss_back: ColorRect
var boss_bar: ColorRect
var boss_name: Label
var boons_label: Label
var channel_label: Label
var attack_btn: Button
var heavy_btn: Button
var dash_btn: Button
var skill2_btn: Button
var pause_dim: ColorRect
var pause_label: Label
var pause_box: VBoxContainer
var _toast_t := 0.0
var _we_paused := false

func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_status()
	_build_actions()
	prompt = UI.label(self, "", Vector2(560, 800), 30, Color(1, 0.95, 0.7))
	toast = UI.label(self, "", Vector2(640, 180), 34, Color(0.9, 1, 0.86))
	boss_back = UI.rect(self, Vector2(560, 28), Vector2(640, 18), Color(0.15, 0.08, 0.08, 0.85))
	boss_bar = UI.rect(self, Vector2(560, 28), Vector2(640, 18), HP_COLOR)
	boss_name = UI.label(self, "", Vector2(560, 50), 24, CREAM)
	boons_label = UI.label(self, "", Vector2(36, 150), 20, Color(0.86, 0.84, 0.78))
	channel_label = UI.label(self, "", Vector2(620, 740), 26, Color(0.55, 0.95, 0.9))
	info = UI.label(self, "", Vector2(0, 0), 8)
	info.visible = false
	show_boss(null)

func _build_status() -> void:
	var portrait := TextureRect.new()
	portrait.texture = Art.portrait()
	portrait.position = Vector2(24, 18)
	portrait.size = Vector2(96, 96)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_SCALE
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(portrait)
	var badge := _Badge.new()
	badge.position = Vector2(12, 8)
	badge.size = Vector2(36, 36)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(badge)
	level_label = UI.label(badge, "1", Vector2.ZERO, 18, CREAM)
	level_label.size = badge.size
	level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	level_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hp_back = UI.rect(self, Vector2(136, 22), Vector2(280, 24), Color(0.18, 0.08, 0.08, 0.9))
	hp_bar = UI.rect(self, Vector2(136, 22), Vector2(280, 24), HP_COLOR)
	hp_text = UI.label(self, "HP", Vector2(144, 22), 18, CREAM)
	UI.rect(self, Vector2(136, 52), Vector2(280, 18), Color(0.08, 0.1, 0.16, 0.9))
	mp_bar = UI.rect(self, Vector2(136, 52), Vector2(280, 18), MP_COLOR)
	UI.label(self, "MP  100 / 100", Vector2(144, 50), 14, CREAM)
	UI.rect(self, Vector2(136, 76), Vector2(280, 18), Color(0.16, 0.12, 0.06, 0.9))
	sp_bar = UI.rect(self, Vector2(136, 76), Vector2(224, 18), SP_COLOR)
	UI.label(self, "SP  80 / 100", Vector2(144, 74), 14, CREAM)
	floor_label = UI.label(self, "", Vector2(1360, 24), 28, CREAM)
	_icon(self, "bag", Vector2(1508, 22), 36)
	bag_label = UI.label(self, "0/12", Vector2(1548, 26), 24, CREAM)
	_icon(self, "shard", Vector2(1660, 22), 36)
	shard_label = UI.label(self, "0", Vector2(1700, 26), 24, CREAM)
	var pause_b := _btn(Vector2(1828, 16), Vector2(64, 64), "pause", _toggle_pause)
	pause_dim = ColorRect.new()
	pause_dim.color = Color(0, 0, 0, 0.45)
	pause_dim.position = Vector2.ZERO
	pause_dim.size = Vector2(1920, 1080)
	pause_dim.visible = false
	pause_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(pause_dim)
	pause_label = UI.label(self, "暂停\nP / Start 继续", Vector2(820, 360), 40, CREAM)
	pause_label.visible = false
	pause_box = VBoxContainer.new()
	pause_box.position = Vector2(720, 520)
	pause_box.visible = false
	pause_box.z_index = 2
	add_child(pause_box)
	pause_b.z_index = 2
	pause_label.z_index = 2

func _build_actions() -> void:
	var pot := _btn(Vector2(28, 948), Vector2(104, 104), "potion", func(): show_toast("还没有消耗品"))
	pot.text = ""
	var count := UI.label(pot, "0", Vector2(64, 64), 22, CREAM)
	count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	heavy_btn = _btn(Vector2(1564, 948), Vector2(86, 86), "heavy", func(): show_toast("还没有重攻击"))
	dash_btn = _btn(Vector2(1584, 828), Vector2(86, 86), "dash", _press_dash)
	skill_box = _btn(Vector2(1704, 728), Vector2(96, 96), "skill", _press_skill)
	skill2_btn = _btn(Vector2(1836, 768), Vector2(96, 96), "skill2", _press_skill2)
	attack_btn = _btn(Vector2(1736, 868), Vector2(156, 156), "attack", _press_attack)
	skill_label = UI.label(self, "", Vector2(1488, 688), 20, CREAM)
	skill2_label = UI.label(self, "", Vector2(1760, 700), 18, CREAM)

func _icon(parent: Node, name: String, pos: Vector2, px: float) -> TextureRect:
	var t := TextureRect.new()
	t.texture = Art.icon(name)
	t.position = pos
	t.size = Vector2(px, px)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(t)
	return t

func _btn(pos: Vector2, sz: Vector2, icon_name: String, cb: Callable) -> Button:
	var b := Button.new()
	b.position = pos
	b.custom_minimum_size = sz
	b.size = sz
	b.focus_mode = Control.FOCUS_NONE
	b.icon = Art.icon(icon_name)
	b.expand_icon = true
	b.add_theme_constant_override("icon_max_width", int(sz.x * 0.62))
	var radius := int(sz.x / 2)
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = INK
		sb.corner_radius_top_left = radius
		sb.corner_radius_top_right = radius
		sb.corner_radius_bottom_left = radius
		sb.corner_radius_bottom_right = radius
		sb.set_border_width_all(2)
		sb.border_color = CREAM
		match st:
			"hover": sb.bg_color = INK.lightened(0.15)
			"pressed": sb.bg_color = INK.lightened(0.28)
			"disabled": sb.bg_color = Color(0.05, 0.05, 0.05, 0.7)
		b.add_theme_stylebox_override(st, sb)
	b.pressed.connect(cb)
	add_child(b)
	return b

func _popup_blocking() -> bool:
	var f := get_parent()
	return f != null and bool(f.get("popup_open"))

func _toggle_pause() -> void:
	if _popup_blocking():
		return
	if _we_paused:
		get_tree().paused = false
		_we_paused = false
	elif get_tree().paused:
		return
	else:
		get_tree().paused = true
		_we_paused = true
	pause_dim.visible = _we_paused
	pause_label.visible = _we_paused
	pause_box.visible = _we_paused
	if _we_paused:
		SettingsControls.fill(pause_box)
		if pause_box.get_child_count() > 0 and pause_box.get_child(0) is Control:
			(pause_box.get_child(0) as Control).grab_focus()

func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("pause"):
		_toggle_pause()

func _press_attack() -> void:
	if _we_paused or player == null:
		return
	player.try_attack()

func _press_dash() -> void:
	if _we_paused or player == null:
		return
	player.try_dash()

func _press_skill() -> void:
	if _we_paused or player == null:
		return
	player.try_skill()

func _press_skill2() -> void:
	if _we_paused or player == null:
		return
	player.try_skill2()

func show_boss(g: Node) -> void:
	var on := g != null and is_instance_valid(g)
	boss_back.visible = on
	boss_bar.visible = on
	boss_name.visible = on
	if on:
		boss_name.text = g.gdata.display_name + ("（二阶段）" if g.phase == 2 else "")
		boss_bar.size.x = 640.0 * g.hp / maxf(1, g.max_hp)

func show_toast(t: String) -> void:
	toast.text = t
	_toast_t = 2.5

func _process(delta: float) -> void:
	var _p := Prof.t0()
	_prof_process(delta)
	Prof.add("hud", _p)

func _prof_process(delta: float) -> void:
	_toast_t -= delta
	toast.visible = _toast_t > 0.0
	if player == null or not is_instance_valid(player):
		return
	hp_bar.size.x = 280.0 * player.hp / maxf(1, player.max_hp)
	hp_text.text = "HP %d / %d" % [player.hp, player.max_hp]
	level_label.text = str(Game.level())
	var cd := player.skill_cd_left
	var name1 := Game.skill.display_name if Game.skill else "技能"
	skill_label.text = name1 + " " + ("就绪" if cd <= 0.0 else "%.1f 秒" % cd)
	if skill_box is CanvasItem:
		skill_box.modulate = Color.WHITE if cd <= 0.0 else Color(0.55, 0.55, 0.55)
	var cd2 := player.skill2_cd_left
	var name2 := Game.skill2.display_name if Game.skill2 else "技能 2"
	if skill2_label:
		skill2_label.text = name2 + " " + ("就绪" if cd2 <= 0.0 else "%.1f 秒" % cd2)
	if skill2_btn:
		skill2_btn.modulate = Color.WHITE if cd2 <= 0.0 else Color(0.55, 0.55, 0.55)
	if dash_btn:
		dash_btn.modulate = Color.WHITE if player.charges_ready() > 0 else Color(0.45, 0.45, 0.45)
	var r := Game.run
	if r:
		floor_label.text = "第 %d 层" % r.depth
		bag_label.text = "%d/%d" % [r.bag.size(), BAG_SLOTS]
		shard_label.text = str(r.shards_carried)
		var names := r.boons.map(func(b): return "· " + b.display_name)
		for st in r.equipped:
			names.append("◆ " + st.item.display_name)
		boons_label.text = "\n".join(names)

func skill_text() -> String:
	return skill_label.text

class _Badge extends Control:
	func _draw() -> void:
		draw_circle(size * 0.5, size.x * 0.5 - 1.0, Color(0.1, 0.09, 0.08, 0.94))
		draw_arc(size * 0.5, size.x * 0.5 - 1.5, 0, TAU, 24, Color(0.9, 0.86, 0.76), 2.0, true)
