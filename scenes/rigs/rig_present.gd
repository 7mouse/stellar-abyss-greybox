extends Node2D
## 视口合成图贴到 Outline 上描边。网格在 CPU 上按权重变形，避开渲染器把网格画没。

var _polys: Array[Polygon2D] = []


func _ready() -> void:
	# 排在 AnimationPlayer 后面，读到的是这一帧已经写上的 bone。
	process_priority = 100
	var outline := get_node_or_null("Outline") as Sprite2D
	var view := get_node_or_null("View") as SubViewport
	if outline and view:
		outline.texture = view.get_texture()
	var sk := get_node_or_null("View/Motion/Bob/Skeleton")
	if sk == null:
		return
	for child in sk.get_children():
		if child is Polygon2D and child.has_meta("skin"):
			_polys.append(child)
	_skin()


func _process(_dt: float) -> void:
	_skin()


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
