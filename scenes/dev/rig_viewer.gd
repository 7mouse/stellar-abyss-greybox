extends Node2D
## 试看。F1 或按钮在动作和朝向之间切换。
## 主角脚底是场景原点；左侧面是侧面场景的水平镜像。

const FEET_Y := 900.0
const PREVIEW_SCALE := 1.65
const SCENES := {
	"s": "res://scenes/rigs/hero_s.tscn",
	"f": "res://scenes/rigs/hero_f.tscn",
	"b": "res://scenes/rigs/hero_b.tscn",
	"l": "res://scenes/rigs/hero_l.tscn",
}
const BOAR_SCENE := "res://scenes/rigs/mushling_s.tscn"

var _states: Array[Dictionary] = [
	{"hero": "s", "anim": "idle", "boar": "idle", "text": "侧面 · 待机"},
	{"hero": "s", "anim": "move", "boar": "move", "text": "侧面 · 移动"},
	{"hero": "s", "anim": "attack_1", "boar": "move", "text": "侧面 · 主角轻攻击 / mushling 移动"},
	{"hero": "s", "anim": "hit", "boar": "idle", "text": "侧面 · 主角受击"},
	{"hero": "l", "anim": "move", "boar": "move", "text": "左侧面（镜像）· 移动"},
	{"hero": "f", "anim": "idle", "boar": "idle", "text": "正面 · 待机"},
	{"hero": "b", "anim": "idle", "boar": "idle", "text": "背面 · 待机"},
]

var _i := 0
var _hero_slot: Node2D
var _boar_slot: Node2D
var _state_label: Label
var _hero_facing := ""


func _ready() -> void:
	_build()
	show_state(0)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F1:
		cycle()


func cycle() -> void:
	show_state((_i + 1) % _states.size())


func show_state(i: int) -> void:
	_i = i
	var st: Dictionary = _states[i]
	_ensure_hero(String(st["hero"]))
	_play(_hero_slot, String(st["anim"]))
	_play(_boar_slot, String(st["boar"]))
	_state_label.text = "F1 切换    %s" % st["text"]


func seek(t: float) -> void:
	for ap in _players():
		ap.seek(t, true)


func _process(_dt: float) -> void:
	if OS.get_environment("RIG_CAPTURE") == "1":
		return
	for ap in _players():
		var anim_name := String(ap.assigned_animation)
		if anim_name == "" or ap.is_playing():
			continue
		var anim := ap.get_animation(anim_name)
		if anim and anim.loop_mode == Animation.LOOP_NONE:
			ap.play(anim_name)


func _build() -> void:
	var bg := Polygon2D.new()
	bg.color = Color(0.11, 0.12, 0.13)
	bg.polygon = PackedVector2Array([Vector2(0, 0), Vector2(1920, 0), Vector2(1920, 1080), Vector2(0, 1080)])
	bg.z_index = -20
	add_child(bg)
	var ground := Polygon2D.new()
	ground.color = Color(0.24, 0.26, 0.24)
	ground.polygon = PackedVector2Array([
		Vector2(0, FEET_Y), Vector2(1920, FEET_Y), Vector2(1920, 1080), Vector2(0, 1080),
	])
	ground.z_index = -10
	add_child(ground)
	var lip := Polygon2D.new()
	lip.color = Color(0.34, 0.36, 0.33)
	lip.polygon = PackedVector2Array([
		Vector2(0, FEET_Y), Vector2(1920, FEET_Y), Vector2(1920, FEET_Y + 8), Vector2(0, FEET_Y + 8),
	])
	lip.z_index = -9
	add_child(lip)

	_hero_slot = Node2D.new()
	_hero_slot.name = "HeroSlot"
	_hero_slot.position = Vector2(520, FEET_Y)
	_hero_slot.scale = Vector2.ONE * PREVIEW_SCALE
	add_child(_hero_slot)
	_boar_slot = Node2D.new()
	_boar_slot.name = "BoarSlot"
	_boar_slot.position = Vector2(1240, FEET_Y)
	_boar_slot.scale = Vector2.ONE * PREVIEW_SCALE
	add_child(_boar_slot)
	_boar_slot.add_child(load(BOAR_SCENE).instantiate())

	var ui := CanvasLayer.new()
	add_child(ui)
	var panel := ColorRect.new()
	panel.color = Color(0, 0, 0, 0.45)
	panel.position = Vector2(36, 28)
	panel.size = Vector2(980, 108)
	ui.add_child(panel)
	var title := Label.new()
	title.text = "角色试看    主角 / mushling"
	title.position = Vector2(52, 36)
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", Color(0.95, 0.93, 0.86))
	ui.add_child(title)
	_state_label = Label.new()
	_state_label.position = Vector2(52, 82)
	_state_label.add_theme_font_size_override("font_size", 26)
	_state_label.add_theme_color_override("font_color", Color(0.85, 0.88, 0.75))
	ui.add_child(_state_label)
	var button := Button.new()
	button.text = "F1 切换"
	button.position = Vector2(1680, 36)
	button.custom_minimum_size = Vector2(180, 64)
	button.add_theme_font_size_override("font_size", 28)
	button.pressed.connect(cycle)
	ui.add_child(button)
	_tag(ui, "主角", Vector2(430, FEET_Y + 18))
	_tag(ui, "mushling", Vector2(1140, FEET_Y + 18))


func _tag(ui: CanvasLayer, text: String, pos: Vector2) -> void:
	var label := Label.new()
	label.text = text
	label.position = pos
	label.add_theme_font_size_override("font_size", 28)
	label.add_theme_color_override("font_color", Color(0.8, 0.82, 0.74))
	ui.add_child(label)


func _ensure_hero(facing: String) -> void:
	if facing == _hero_facing and _hero_slot.get_child_count() > 0:
		return
	for c in _hero_slot.get_children():
		c.free()
	_hero_slot.add_child(load(SCENES[facing]).instantiate())
	_hero_facing = facing


func _play(slot: Node2D, anim_name: String) -> void:
	var ap := slot.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if ap == null:
		return
	if ap.has_animation(anim_name):
		ap.play(anim_name)
	else:
		ap.play("idle")


func _players() -> Array[AnimationPlayer]:
	var out: Array[AnimationPlayer] = []
	for slot in [_hero_slot, _boar_slot]:
		var ap := slot.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if ap:
			out.append(ap)
	return out
