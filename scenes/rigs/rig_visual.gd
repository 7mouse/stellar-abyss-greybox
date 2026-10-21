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
# Boars are the swarm. enemy_scale < 1 draws them into a smaller viewport and
# scales the sprite back up. enemy_step > 1 refreshes that viewport every Nth frame.
# outline_mode: 0 full ring, 1 cross, 2 off. Hero and the boss stay on the full ring.
# 1.0 / 1 / 0 is the unscaled path.
static var enemy_scale := 1.0
static var enemy_step := 1
static var outline_mode := 0
# How many boar viewports may redraw in one frame. The rest keep their last pose.
static var boar_budget := 2
static var _spawn_frame := -1
static var _spawns_left := 1
static var _draw_frame := -1
static var _draw_left := 0
static var _seq := 0
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
var _warm: Array[String] = []
var _rid := 0
var _sprite: Sprite2D
var _view: SubViewport
var _posed := false
var _pose_t := 0.0


func _init() -> void:
	_rid = _seq
	_seq += 1


func setup(k: String, world_h: float) -> void:
	kind = k
	_world_h = world_h
	if kind == "boar":
		_warm = ["f", "b"]
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
	var scene_changed := _scene_key(code) != _scene or _rig == null
	_code = code
	# Left/right share one scene for boars and the boss; only the host scale flips.
	if not scene_changed:
		_apply_scale()
	_sync_presence()


func set_anim(name: String) -> void:
	if name == _anim:
		return
	_anim = name
	_pose_t = 0.0
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


func wants_redraw() -> bool:
	if kind != "boar":
		return true
	if boar_budget <= 0:
		return false
	if boar_budget >= 8:
		return true
	# Spread the ids so the same boars are not always the ones that redraw.
	if (_rid + Engine.get_process_frames()) % 8 >= boar_budget:
		return false
	return _take_draw()


func _take_draw() -> bool:
	var frame := Engine.get_process_frames()
	if frame != _draw_frame:
		_draw_frame = frame
		_draw_left = boar_budget
	if _draw_left <= 0:
		return false
	_draw_left -= 1
	return true


func _spawn_limited() -> bool:
	var vp := get_viewport()
	return vp != null and vp.get_camera_2d() != null


func _take_spawn() -> bool:
	var frame := Engine.get_process_frames()
	if frame != _spawn_frame:
		_spawn_frame = frame
		_spawns_left = 1
	if _spawns_left <= 0:
		return false
	_spawns_left -= 1
	return true


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
	var key := _scene_key(code)
	if _rig == null or not is_instance_valid(_rig) or _scene != key:
		var reused := _parked.get(key) as Node2D
		if reused and is_instance_valid(reused):
			if _rig and is_instance_valid(_rig):
				_stash(_rig)
			_parked.erase(key)
			_rig = reused
			_scene = key
			add_child(_rig)
			_bind_player()
			Prof.count("reuse")
		elif kind == "boar" and _spawn_limited() and not _take_spawn():
			# Several boars changing facing in one tick used to instantiate together.
			_busy = false
			return
		else:
			if _rig and is_instance_valid(_rig):
				_stash(_rig)
				_rig = null
				_ap = null
			_spawn(key)
			Prof.count("spawn")
	_apply_scale()
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


func _process(dt: float) -> void:
	if _rig and is_instance_valid(_rig) and absf(_fit_k - _view_k()) > 0.001:
		_fit_view()
	_sync_presence()
	_pump_warm()
	_budget_view(dt)


func _pump_warm() -> void:
	# Build the other facings one per frame so a later turn does not instantiate on the spot.
	if kind != "boar" or _warm.is_empty() or not _spawn_limited():
		return
	var key := _warm[0]
	if key == _scene or _parked.has(key):
		_warm.pop_front()
		return
	if not _take_spawn():
		return
	_warm.pop_front()
	var face := key
	var rig := BOAR_SCENES[face].instantiate() as Node2D
	rig.process_mode = Node.PROCESS_MODE_DISABLED
	var outline := rig.find_child("Outline", true, false) as Sprite2D
	if outline and outline.material:
		outline.material = outline.material.duplicate()
	# Allocate the render target now, while this frame is still allowed to hitch.
	add_child(rig)
	_size_rig(rig, face)
	var view := rig.find_child("View", true, false) as SubViewport
	if view:
		view.render_target_update_mode = SubViewport.UPDATE_DISABLED
		view.process_mode = Node.PROCESS_MODE_DISABLED
	remove_child(rig)
	_parked[key] = rig
	Prof.count("warm")


func _exit_tree() -> void:
	var doomed: Array[Node] = []
	if _rig and is_instance_valid(_rig) and _rig.get_parent() != self:
		doomed.append(_rig)
	if _view and is_instance_valid(_view) and _view.get_parent() == null:
		doomed.append(_view)
	for key in _parked.keys():
		var n: Node = _parked[key]
		if n and is_instance_valid(n) and n.get_parent() != self and not doomed.has(n):
			doomed.append(n)
	for n in doomed:
		n.free()


func _budget_view(dt: float) -> void:
	if kind != "boar" or boar_budget >= 8 or not _spawn_limited():
		return
	if _rig == null or not is_instance_valid(_rig) or not _shown:
		return
	_lift_outline()
	if _view == null or not is_instance_valid(_view):
		_view = _rig.find_child("View", true, false) as SubViewport
	var redraw := not _posed or wants_redraw()
	_posed = true
	if redraw:
		_snap_pose()
		if _view and _view.get_parent() != _rig:
			_rig.add_child(_view)
		if _view:
			_view.process_mode = Node.PROCESS_MODE_INHERIT
			_view.render_target_update_mode = SubViewport.UPDATE_ONCE
		if _rig.has_method("external_tick"):
			_rig.call("external_tick", dt, true)
	else:
		_pose_t += dt
		if _view and _view.get_parent() == _rig:
			_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
			_view.process_mode = Node.PROCESS_MODE_DISABLED
			_rig.remove_child(_view)
		if _rig.has_method("external_tick"):
			_rig.call("external_tick", dt, false)


func _snap_pose() -> void:
	if _ap == null:
		return
	var use := _anim if _anim != "" and _ap.has_animation(_anim) else "idle"
	if not _ap.has_animation(use):
		return
	if _ap.current_animation != use:
		_ap.play(use)
	var length := maxf(0.001, _ap.current_animation_length)
	_ap.seek(fmod(_pose_t, length), true)


func _lift_outline() -> void:
	if _rig == null:
		return
	var outline := _rig.find_child("Outline", true, false) as Sprite2D
	if outline == null:
		return
	if _sprite and is_instance_valid(_sprite) and _sprite != outline:
		_sprite.queue_free()
	var pos := outline.position
	var sc := outline.scale
	outline.reparent(self, true)
	outline.position = pos
	outline.scale = sc
	_sprite = outline
	if _view and _view.get_texture():
		_sprite.texture = _view.get_texture()


func _size_rig(rig: Node2D, face: String) -> void:
	var view := rig.find_child("View", true, false) as SubViewport
	var motion := rig.find_child("Motion", true, false) as Node2D
	var outline := rig.find_child("Outline", true, false) as Sprite2D
	if view == null or motion == null or outline == null:
		return
	var spec: Vector4 = VIEW["mushling_" + face]
	var k := _view_k()
	view.gui_disable_input = true
	view.handle_input_locally = false
	view.size = Vector2i(maxi(1, int(round(spec.x * k))), maxi(1, int(round(spec.y * k))))
	motion.scale = Vector2(k, k)
	motion.position = Vector2(spec.z, spec.w) * k
	outline.scale = Vector2(1.0 / k, 1.0 / k)
	outline.position = Vector2(spec.x * 0.5 - spec.z, spec.y * 0.5 - spec.w)
	outline.texture = view.get_texture()


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
	if _sprite and is_instance_valid(_sprite):
		return _sprite
	if _rig == null:
		return null
	return _rig.find_child("Outline", true, false) as Sprite2D
