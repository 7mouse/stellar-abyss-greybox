class_name Hud
extends CanvasLayer
## 局内 HUD：左上头像 / HP / MP / SP / 等级，右上层数、背包、碎片、暂停和圆形小地图，
## 右下是攻击键和围着它的一圈按钮，左下一格消耗品。MP、SP、重攻击、第二技能、消耗品还没有对应系统，显示占位。

const BAG_SLOTS := 12 ## 画面上的容量。灰盒背包还没有这个上限
const CREAM := Color(0.9, 0.86, 0.76)
const PAPER := "res://art_src/ui/hud_v2/panels/ui_paper_grain_tile_256.png"
const BAR_FRAME := "res://art_src/ui/hud_v2/bars/u02_bar_frame.png"
const BOSS_FRAME := "res://art_src/ui/hud_v2/bars/u10_boss_bar_frame.png"
const SLOT := "res://art_src/ui/hud_v2/frames/u07_slot.png"
const BADGE := "res://art_src/ui/hud_v2/frames/u03_level_badge.png"
const PORTRAIT_RING := "res://art_src/ui/hud_v2/hud/u01_portrait_ring.png"
const PAUSE_PANEL := "res://art_src/ui/hud_v2/panels/ui_panel_window.png"
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
var paper_pause: NinePatchRect
var quality_frame: ColorRect
var potion_btn: Button
var potion_count: Label
var _toast_t := 0.0
var _we_paused := false

func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_status()
	_build_actions()
	prompt = UI.label(self, "", Vector2(560, 800), 30, Color(1, 0.95, 0.7))
	toast = UI.label(self, "", Vector2(640, 180), 34, Color(0.9, 1, 0.86))
	_nine(BOSS_FRAME, Vector2(548, 16), Vector2(664, 40), 8, 7, 8, 6, "paper_boss")
	boss_back = UI.rect(self, Vector2(560, 28), Vector2(640, 18), Color(0.15, 0.08, 0.08, 0.55))
	boss_bar = UI.rect(self, Vector2(560, 28), Vector2(640, 18), HP_COLOR)
	boss_name = UI.label(self, "", Vector2(560, 50), 24, CREAM)
	boons_label = UI.label(self, "", Vector2(36, 150), 20, Color(0.86, 0.84, 0.78))
	channel_label = UI.label(self, "", Vector2(620, 740), 26, Color(0.55, 0.95, 0.9))
	info = UI.label(self, "", Vector2(0, 0), 8)
	info.visible = false
	quality_frame = ColorRect.new()
	quality_frame.name = "quality_frame"
	quality_frame.position = Vector2(1508, 68)
	quality_frame.size = Vector2(48, 48)
	quality_frame.color = Color(0.93, 0.74, 0.28, 1)
	quality_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	quality_frame.visible = false
	add_child(quality_frame)
	show_boss(null)

func _build_status() -> void:
	var plate := TextureRect.new()
	plate.name = "paper_status"
	plate.texture = load(PAPER)
	plate.position = Vector2(8, 4)
	plate.size = Vector2(430, 156)
	plate.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	plate.stretch_mode = TextureRect.STRETCH_TILE
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	add_child(plate)
	_nine(BAR_FRAME, Vector2(124, 12), Vector2(304, 42), 10, 8, 10, 6, "paper_hp")
	_nine(BAR_FRAME, Vector2(124, 44), Vector2(304, 34), 10, 8, 10, 6, "paper_mp")
	_nine(BAR_FRAME, Vector2(124, 68), Vector2(304, 34), 10, 8, 10, 6, "paper_sp")
	var portrait := TextureRect.new()
	portrait.texture = Art.portrait()
	portrait.position = Vector2(24, 18)
	portrait.size = Vector2(96, 96)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_SCALE
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(portrait)
	var ring := TextureRect.new()
	ring.name = "paper_portrait"
	ring.texture = load(PORTRAIT_RING)
	ring.position = Vector2(12, 6)
	ring.size = Vector2(120, 120)
	ring.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ring.stretch_mode = TextureRect.STRETCH_SCALE
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ring.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	add_child(ring)
	var badge := _Badge.new()
	badge.position = Vector2(84, 72)
	badge.size = Vector2(52, 52)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(badge)
	var badge_tex := TextureRect.new()
	badge_tex.texture = load(BADGE)
	badge_tex.position = Vector2.ZERO
	badge_tex.size = badge.size
	badge_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	badge_tex.stretch_mode = TextureRect.STRETCH_SCALE
	badge_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_child(badge_tex)
	level_label = UI.label(badge, "1", Vector2.ZERO, 18, CREAM)
	level_label.size = badge.size
	level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	level_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hp_back = UI.rect(self, Vector2(136, 22), Vector2(280, 24), Color(0, 0, 0, 0))
	hp_bar = UI.rect(self, Vector2(136, 22), Vector2(280, 24), HP_COLOR)
	hp_text = UI.label(self, "HP", Vector2(144, 22), 18, CREAM)
	UI.rect(self, Vector2(136, 52), Vector2(280, 18), Color(0, 0, 0, 0))
	mp_bar = UI.rect(self, Vector2(136, 52), Vector2(280, 18), MP_COLOR)
	UI.label(self, "MP  100 / 100", Vector2(144, 50), 14, CREAM)
	UI.rect(self, Vector2(136, 76), Vector2(280, 18), Color(0, 0, 0, 0))
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
	paper_pause = _nine(PAUSE_PANEL, Vector2(640, 300), Vector2(640, 460), 13, 14, 15, 14, "paper_pause")
	paper_pause.visible = false
	paper_pause.z_index = 1
	pause_b.z_index = 2
	pause_label.z_index = 2

func _build_actions() -> void:
	potion_btn = _btn(Vector2(28, 948), Vector2(104, 104), "potion", _press_potion)
	potion_btn.name = "potion"
	potion_btn.text = ""
	potion_count = UI.label(potion_btn, "0", Vector2(64, 64), 22, CREAM)
	potion_count.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		var sb := StyleBoxTexture.new()
		sb.texture = load(SLOT)
		sb.texture_margin_left = 13
		sb.texture_margin_right = 13
		sb.texture_margin_top = 13
		sb.texture_margin_bottom = 12
		sb.set_content_margin_all(8)
		match st:
			"hover": sb.modulate_color = Color(1.12, 1.08, 1.0, 1)
			"pressed": sb.modulate_color = Color(0.82, 0.78, 0.7, 1)
			"disabled": sb.modulate_color = Color(0.45, 0.45, 0.45, 0.8)
			_: sb.modulate_color = Color.WHITE
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
	if paper_pause:
		paper_pause.visible = _we_paused
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

func _press_potion() -> void:
	if Game.run == null or Game.run.potions <= 0:
		show_toast("还没有回血药")
		return
	if player and Game.drink_potion(player):
		show_toast("喝了回血药")

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
	if potion_count:
		potion_count.text = str(r.potions) if r else "0"
	if potion_btn:
		potion_btn.modulate = Color.WHITE if r != null and r.potions > 0 else Color(0.45, 0.45, 0.45)
	if quality_frame:
		var carry := Game.recall != null and Game.recall.carrying()
		quality_frame.visible = carry
		if carry:
			var qmat := QualityFrame.apply(quality_frame, "gold")
			qmat.set_shader_parameter("time_sec", Time.get_ticks_msec() / 1000.0)

func skill_text() -> String:
	return skill_label.text

func _nine(path: String, pos: Vector2, sz: Vector2, left: int, top: int, right: int, bottom: int, node_name: String) -> NinePatchRect:
	var n := NinePatchRect.new()
	n.name = node_name
	n.texture = load(path)
	n.position = pos
	n.size = sz
	n.patch_margin_left = left
	n.patch_margin_top = top
	n.patch_margin_right = right
	n.patch_margin_bottom = bottom
	n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(n)
	return n

class _Badge extends Control:
	func _draw() -> void:
		pass
