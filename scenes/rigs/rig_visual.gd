class_name RigVisual
extends Node2D
## Hosts a Skeleton2D rig. Feet sit on this node's origin.
## Facing: side whenever the aim has a horizontal component; front/back only
## near straight up/down, with a 15 degree buffer so the set does not flicker.
## Left is the side scene mirrored. Hero, boar, and the moss-crown boss share that rule.

const HERO_SCENES := {
	"s": preload("res://scenes/rigs/hero_s.tscn"),
	"l": preload("res://scenes/rigs/hero_l.tscn"),
	"f": preload("res://scenes/rigs/hero_f.tscn"),
	"b": preload("res://scenes/rigs/hero_b.tscn"),
}
const BOAR_SCENES := {
	"s": preload("res://scenes/rigs/mushling_s.tscn"),
	"f": preload("res://scenes/rigs/mushling_f.tscn"),
	"b": preload("res://scenes/rigs/mushling_b.tscn"),
}
const BOSS_SCENES := {
	"s": preload("res://scenes/rigs/mosscrown_s.tscn"),
	"f": preload("res://scenes/rigs/mosscrown_f.tscn"),
	"b": preload("res://scenes/rigs/mosscrown_b.tscn"),
}
const HERO_PX := 233.0
# Skeleton-space height of each facing, so every facing lands on the same world height.
const BOAR_PX := {"s": 193.7, "f": 201.9, "b": 202.5}
const BOSS_PX := {"s": 258.6, "f": 279.2, "b": 280.6}
const ENTER := deg_to_rad(15.0)
const EXIT := deg_to_rad(30.0)
# Skeleton-space bounds of every clip, plus 8px so the 1.5px outline is not clipped.
# x = width, y = height, z = Motion.x, w = Motion.y. Feet stay on the host origin.
const VIEW := {
	"s": Vector4(217, 261, 106, 249),
	"f": Vector4(130, 257, 63, 245),
	"b": Vector4(138, 255, 75, 245),
	"mushling_s": Vector4(264, 211, 114, 196),
	"mushling_f": Vector4(179, 219, 88, 206),
	"mushling_b": Vector4(209, 220, 90, 207),
	"boss_s": Vector4(350, 275, 140, 262),
	"boss_f": Vector4(245, 297, 121, 283),
	"boss_b": Vector4(224, 298, 113, 284),
}

# Debug switches for the perf breakdown. Defaults keep the full rig.
static var allow_skin := true
static var allow_anim := true
static var allow_blink := true
static var allow_view := true
static var cull_far := true
static var n_rig := 0
static var n_draw := 0
# Boars are the swarm. Draw them into a slightly smaller viewport (still above
# screen resolution) and, when enemy_step > 1, refresh that viewport every Nth frame.
# Hero and the boss stay full size and full rate. 1.0 / 1 is the unscaled path.
static var enemy_scale := 0.75
static var enemy_step := 1
const CULL_MARGIN := 96.0

var kind := "hero"
var _code := ""
var _scene := ""
var _anim := ""
var _world_h := 96.0
var _px := HERO_PX
var _rig: Node2D
var _ap: AnimationPlayer
var _asleep := false
var _shown := true
var _busy := false
var _anim_pos := 0.0
var _fit_k := -1.0
var _glow: ShaderMaterial
var _parked: Dictionary = {}


func setup(k: String, world_h: float) -> void:
	kind = k
	_world_h = world_h
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
	if code == _code and _rig != null and _scene == _scene_key(code):
		return
	_code = code
	_apply_scale()
	# Left/right share one scene for boars and the boss; only the host scale flips.
	# A real scene change waits until the rig is on screen, then reuses a parked copy.
	_sync_presence()


func set_anim(name: String) -> void:
	if name == _anim:
		return
	_anim = name
	_play(name)


func set_asleep(on: bool) -> void:
	if on == _asleep:
		return
	_asleep = on
	_sync_presence()


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
	var from_down := absf(angle_difference(d.angle(), PI * 0.5))
	var from_up := absf(angle_difference(d.angle(), -PI * 0.5))
	var near := from_down if from_down <= from_up else from_up
	var vert := "f" if from_down <= from_up else "b"
	if (_code == "f" or _code == "b") and _code == vert and near < EXIT:
		return _code
	# Inside the enter cone of the nearer vertical, including a jump from front to back.
	if near < ENTER:
		return vert
	return "l" if d.x < 0.0 else "s"


func _scene_key(code: String) -> String:
	if kind == "hero":
		return code
	return "s" if code == "l" else code


func _view_k() -> float:
	if kind != "boar":
		return 1.0
	return clampf(enemy_scale, 0.5, 1.0)


func _mount(code: String) -> void:
	if _busy:
		return
	var t := Prof.t0()
	_busy = true
	_code = code
	_apply_scale()
	var key := _scene_key(code)
	if _rig and is_instance_valid(_rig) and _scene != key:
		_stash(_rig)
		_rig = null
		_ap = null
	if _rig == null or not is_instance_valid(_rig):
		var reused := _parked.get(key) as Node2D
		if reused and is_instance_valid(reused):
			_parked.erase(key)
			_rig = reused
			_scene = key
			add_child(_rig)
			_bind_player()
			Prof.count("reuse")
		else:
			_spawn(key)
			Prof.count("spawn")
	_anim_pos = 0.0
	_shown = false
	_fit_k = -1.0
	_fit_view()
	Prof.add("mount", t)
	_sync_presence()
	_busy = false


func _spawn(key: String) -> void:
	for c in get_children():
		remove_child(c)
		c.free()
	var face := "s" if _code == "l" else _code
	var packed: PackedScene
	match kind:
		"boar":
			packed = BOAR_SCENES[face]
		"boss":
			packed = BOSS_SCENES[face]
		_:
			packed = HERO_SCENES[_code]
	_rig = packed.instantiate() as Node2D
	_scene = key
	add_child(_rig)
	_bind_player()
	var outline := _outline()
	if outline and outline.material:
		outline.material = outline.material.duplicate()


func _bind_player() -> void:
	if _rig == null:
		_ap = null
		return
	_ap = _rig.find_child("AnimationPlayer", true, false) as AnimationPlayer


func _stash(rig: Node2D) -> void:
	var view := rig.find_child("View", true, false) as SubViewport
	if view:
		view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	rig.process_mode = Node.PROCESS_MODE_DISABLED
	if rig.get_parent() == self:
		remove_child(rig)
	if _scene != "":
		_parked[_scene] = rig


func _process(_dt: float) -> void:
	if _rig and is_instance_valid(_rig) and absf(_fit_k - _view_k()) > 0.001:
		_fit_view()
	_sync_presence()


func _exit_tree() -> void:
	var doomed: Array[Node] = []
	if _rig and is_instance_valid(_rig) and _rig.get_parent() != self:
		doomed.append(_rig)
	for key in _parked.keys():
		var n: Node = _parked[key]
		if n and is_instance_valid(n) and n.get_parent() != self and not doomed.has(n):
			doomed.append(n)
	for n in doomed:
		n.free()


func _in_camera() -> bool:
	if not cull_far:
		return true
	var vp := get_viewport()
	if vp == null or vp.get_camera_2d() == null:
		return true
	return vp.get_visible_rect().grow(CULL_MARGIN).has_point(vp.get_canvas_transform() * global_position)


func _wants_show() -> bool:
	return allow_view and not _asleep and _in_camera()


func _sync_presence() -> void:
	var show := _wants_show()
	var key := _scene_key(_code if _code != "" else "s")
	if show and not _busy and (_rig == null or not is_instance_valid(_rig) or _scene != key):
		_mount(_code if _code != "" else "s")
		return
	if _rig == null or not is_instance_valid(_rig):
		return
	if show == _shown and (_rig.get_parent() == self) == show:
		return
	_shown = show
	var view := _rig.find_child("View", true, false) as SubViewport
	if show:
		if _rig.get_parent() != self:
			add_child(_rig)
		_rig.process_mode = Node.PROCESS_MODE_INHERIT
		if view:
			view.render_target_update_mode = SubViewport.UPDATE_ONCE
			var outline := _outline()
			if outline:
				outline.texture = view.get_texture()
		if _anim != "":
			var pos := _anim_pos
			_play(_anim)
			if _ap and pos > 0.0:
				_ap.seek(pos, true)
	else:
		if _ap and _ap.is_playing():
			_anim_pos = _ap.current_animation_position
		if view:
			view.render_target_update_mode = SubViewport.UPDATE_DISABLED
		_rig.process_mode = Node.PROCESS_MODE_DISABLED
		if _rig.get_parent() == self:
			remove_child(_rig)


func _fit_view() -> void:
	var view := _rig.find_child("View", true, false) as SubViewport
	var motion := _rig.find_child("Motion", true, false) as Node2D
	var outline := _outline()
	if view == null or motion == null or outline == null:
		return
	var face := "s" if _code == "l" else _code
	var key := face
	if kind == "boar":
		key = "mushling_" + face
	elif kind == "boss":
		key = "boss_" + face
	var spec: Vector4 = VIEW[key]
	var k := _view_k()
	_fit_k = k
	view.gui_disable_input = true
	view.handle_input_locally = false
	view.size = Vector2i(maxi(1, int(round(spec.x * k))), maxi(1, int(round(spec.y * k))))
	motion.scale = Vector2(k, k)
	motion.position = Vector2(spec.z, spec.w) * k
	# Scale the sprite back up around its center. Feet stay on the host origin.
	outline.scale = Vector2(1.0 / k, 1.0 / k)
	outline.position = Vector2(spec.x * 0.5 - spec.z, spec.y * 0.5 - spec.w)
	outline.texture = view.get_texture()


func _apply_scale() -> void:
	var face := "s" if _code == "l" else _code
	if kind == "boss":
		_px = float(BOSS_PX[face])
	elif kind == "boar":
		_px = float(BOAR_PX[face])
	else:
		_px = HERO_PX
	var s := _world_h / _px
	var flip := -1.0 if (kind == "boar" or kind == "boss") and _code == "l" else 1.0
	scale = Vector2(s * flip, s)


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
