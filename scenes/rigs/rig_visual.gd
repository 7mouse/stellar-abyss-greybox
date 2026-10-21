class_name RigVisual
extends Node2D
## Hosts a Skeleton2D rig. Feet sit on this node's origin.
## Facing: side whenever the aim has a horizontal component; front/back only
## near straight up/down, with a 15 degree buffer so the set does not flicker.
## Left is the side scene mirrored. Boar art is side only, so it keeps the last side.

const HERO_SCENES := {
	"s": preload("res://scenes/rigs/hero_s.tscn"),
	"l": preload("res://scenes/rigs/hero_l.tscn"),
	"f": preload("res://scenes/rigs/hero_f.tscn"),
	"b": preload("res://scenes/rigs/hero_b.tscn"),
}
const BOAR_SCENE := preload("res://scenes/rigs/mushling_s.tscn")
const HERO_PX := 233.0
const BOAR_PX := 187.0
const ENTER := deg_to_rad(15.0)
const EXIT := deg_to_rad(30.0)
# Skeleton-space bounds of every clip, plus 8px so the 1.5px outline is not clipped.
# x = width, y = height, z = Motion.x, w = Motion.y. Feet stay on the host origin.
const VIEW := {
	"s": Vector4(217, 261, 106, 249),
	"f": Vector4(130, 257, 63, 245),
	"b": Vector4(138, 255, 75, 245),
	"boar": Vector4(264, 211, 114, 196),
}

var kind := "hero"
var _code := ""
var _anim := ""
var _world_h := 96.0
var _px := HERO_PX
var _rig: Node2D
var _ap: AnimationPlayer
var _asleep := false
var _glow: ShaderMaterial


func setup(k: String, world_h: float) -> void:
	kind = k
	_world_h = world_h
	_px = HERO_PX if k == "hero" else BOAR_PX
	_mount("s")


func facing_code() -> String:
	return _code


func anim_playing() -> String:
	if _ap == null:
		return ""
	return String(_ap.current_animation)


func set_facing(dir: Vector2) -> void:
	if dir.length() < 0.05:
		return
	var code := _pick(dir)
	if code == _code and _rig != null:
		return
	var anim := _anim
	_mount(code)
	if anim != "":
		_anim = ""
		set_anim(anim)


func set_anim(name: String) -> void:
	if name == _anim:
		return
	_anim = name
	_play(name)


func set_asleep(on: bool) -> void:
	if on == _asleep:
		return
	_asleep = on
	_apply_sleep()


func apply_glow(src: Material) -> void:
	var outline := _outline()
	if outline == null or not (outline.material is ShaderMaterial):
		return
	var sm := outline.material as ShaderMaterial
	if not (src is ShaderMaterial):
		if sm.next_pass != null:
			sm.next_pass = null
		return
	var from := src as ShaderMaterial
	if _glow == null:
		_glow = ShaderMaterial.new()
		_glow.shader = from.shader
	_glow.set_shader_parameter("fill", from.get_shader_parameter("fill"))
	_glow.set_shader_parameter("glow_a", from.get_shader_parameter("glow_a"))
	_glow.set_shader_parameter("glow_b", from.get_shader_parameter("glow_b"))
	if sm.next_pass != _glow:
		sm.next_pass = _glow


func _pick(dir: Vector2) -> String:
	var d := dir.normalized()
	if kind == "boar":
		if absf(d.x) >= sin(ENTER):
			return "l" if d.x < 0.0 else "s"
		if _code == "l" or _code == "s":
			return _code
		return "s"
	var from_down := absf(angle_difference(d.angle(), PI * 0.5))
	var from_up := absf(angle_difference(d.angle(), -PI * 0.5))
	var near := from_down if from_down <= from_up else from_up
	var vert := "f" if from_down <= from_up else "b"
	if (_code == "f" or _code == "b") and _code == vert and near < EXIT:
		return _code
	if not (_code == "f" or _code == "b") and near < ENTER:
		return vert
	return "l" if d.x < 0.0 else "s"


func _mount(code: String) -> void:
	_code = code
	_apply_scale()
	for c in get_children():
		remove_child(c)
		c.free()
	var packed: PackedScene = BOAR_SCENE if kind == "boar" else HERO_SCENES[code]
	_rig = packed.instantiate() as Node2D
	add_child(_rig)
	_ap = _rig.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var outline := _outline()
	if outline and outline.material:
		outline.material = outline.material.duplicate()
	_fit_view()
	_apply_sleep()


func _fit_view() -> void:
	var view := _rig.find_child("View", true, false) as SubViewport
	var motion := _rig.find_child("Motion", true, false) as Node2D
	var outline := _outline()
	if view == null or motion == null or outline == null:
		return
	var key := "boar" if kind == "boar" else ("s" if _code == "l" else _code)
	var spec: Vector4 = VIEW[key]
	view.size = Vector2i(int(spec.x), int(spec.y))
	motion.position = Vector2(spec.z, spec.w)
	outline.position = Vector2(spec.x * 0.5 - spec.z, spec.y * 0.5 - spec.w)
	outline.texture = view.get_texture()


func _apply_scale() -> void:
	var s := _world_h / _px
	var flip := -1.0 if kind == "boar" and _code == "l" else 1.0
	scale = Vector2(s * flip, s)


func _apply_sleep() -> void:
	if _rig == null:
		return
	_rig.process_mode = Node.PROCESS_MODE_DISABLED if _asleep else Node.PROCESS_MODE_INHERIT
	var view := _rig.find_child("View", true, false) as SubViewport
	if view:
		view.render_target_update_mode = SubViewport.UPDATE_DISABLED if _asleep else SubViewport.UPDATE_ALWAYS


func _play(name: String) -> void:
	if _ap == null or _asleep:
		return
	var use := name if _ap.has_animation(name) else "idle"
	if _ap.current_animation == use and _ap.is_playing():
		return
	_ap.play(use)


func _outline() -> Sprite2D:
	if _rig == null:
		return null
	return _rig.find_child("Outline", true, false) as Sprite2D
