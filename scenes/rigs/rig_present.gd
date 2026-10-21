extends Node2D
## 视口合成图贴到 Outline 上描边。网格在 CPU 上按权重变形，避开渲染器把网格画没。

var _polys: Array[Polygon2D] = []
var _view: SubViewport
var _drawing := true
var _open_eyes: Array[CanvasItem] = []
var _shut_eyes: Array[CanvasItem] = []
var _eyes_closed := false
var _blink_wait := 3.0
var _blink_hold := 0.0
var _anim_on := true
var _ap: AnimationPlayer
var _phase := 0
# Feet can sit this far outside the camera before the body leaves the picture.
const _MARGIN := 220.0
const _BLINK_HOLD := 0.12


func _ready() -> void:
	# 排在 AnimationPlayer 后面，读到的是这一帧已经写上的 bone。
	process_priority = 100
	var outline := get_node_or_null("Outline") as Sprite2D
	_view = get_node_or_null("View") as SubViewport
	if outline and _view:
		outline.texture = _view.get_texture()
	var sk := get_node_or_null("View/Motion/Bob/Skeleton")
	if sk == null:
		return
	for child in sk.get_children():
		if child is Polygon2D and child.has_meta("skin"):
			_polys.append(child)
	_collect_eyes(sk)
	_ap = get_node_or_null("AnimationPlayer") as AnimationPlayer
	_blink_wait = randf_range(2.4, 4.0)
	_phase = int(get_instance_id() & 3)
	set_eyes_closed(false)
	_skin()


func set_eyes_closed(on: bool) -> void:
	_eyes_closed = on
	for eye in _open_eyes:
		eye.visible = not on
	for eye in _shut_eyes:
		eye.visible = on


func _process(dt: float) -> void:
	var t := Prof.t0()
	var draw := _in_view() and RigVisual.allow_view
	var render := draw and _due()
	if _view:
		if render:
			var mode := SubViewport.UPDATE_ALWAYS if _full_rate() else SubViewport.UPDATE_ONCE
			if _view.render_target_update_mode != mode:
				_view.render_target_update_mode = mode
		elif _view.render_target_update_mode != SubViewport.UPDATE_DISABLED:
			_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	if draw != _drawing:
		_drawing = draw
		if not draw and _eyes_closed:
			set_eyes_closed(false)
			_blink_wait = randf_range(2.4, 4.0)
	var anim_on := RigVisual.allow_anim
	if anim_on != _anim_on and _ap:
		_anim_on = anim_on
		_ap.process_mode = Node.PROCESS_MODE_INHERIT if anim_on else Node.PROCESS_MODE_DISABLED
	RigVisual.n_rig += 1
	if draw:
		RigVisual.n_draw += 1
		if render and RigVisual.allow_skin:
			var ts := Prof.t0()
			_skin()
			Prof.add("skin", ts)
		if RigVisual.allow_blink:
			_tick_blink(dt)
	Prof.add("rig", t)


func _full_rate() -> bool:
	var host := get_parent()
	if not (host is RigVisual):
		return true
	if (host as RigVisual).kind != "boar":
		return true
	return RigVisual.enemy_step <= 1


func _due() -> bool:
	if _full_rate():
		return true
	var step := maxi(1, RigVisual.enemy_step)
	return int(Engine.get_process_frames() + _phase) % step == 0


func _in_view() -> bool:
	var vp := get_viewport()
	if vp == null or vp.get_camera_2d() == null:
		return true
	return vp.get_visible_rect().grow(_MARGIN).has_point(vp.get_canvas_transform() * global_position)


func _collect_eyes(node: Node) -> void:
	for child in node.get_children():
		var n := String(child.name)
		if child is CanvasItem:
			if n.begins_with("eye_closed"):
				_shut_eyes.append(child)
			elif n.begins_with("eye_"):
				_open_eyes.append(child)
		_collect_eyes(child)


func _tick_blink(dt: float) -> void:
	if _shut_eyes.is_empty():
		return
	if _eyes_closed:
		_blink_hold -= dt
		if _blink_hold <= 0.0:
			set_eyes_closed(false)
			_blink_wait = randf_range(2.4, 4.0)
		return
	_blink_wait -= dt
	if _blink_wait <= 0.0:
		_blink_hold = _BLINK_HOLD
		set_eyes_closed(true)


func _skin() -> void:
	for poly in _polys:
		var skin: Dictionary = poly.get_meta("skin")
		var paths: Array = skin["paths"]
		var weights: Array = skin["weights"]
		var rest: PackedVector2Array = skin["rest"]
		var sk := poly.get_parent() as Node2D
		var xforms: Array[Transform2D] = []
		for path in paths:
			var bone := poly.get_node(NodePath(String(path))) as Bone2D
			xforms.append(bone.get_relative_transform_to_parent(sk) * bone.get_skeleton_rest().affine_inverse())
		var out := PackedVector2Array()
		out.resize(rest.size())
		for i in rest.size():
			var acc := Vector2.ZERO
			for b in xforms.size():
				var row: PackedFloat32Array = weights[b]
				var w := row[i]
				if w > 0.0001:
					acc += xforms[b] * rest[i] * w
			out[i] = acc
		poly.polygon = out
