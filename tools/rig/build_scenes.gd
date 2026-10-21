extends SceneTree
## 读 assets/rigs/manifests/*.json，生成 Skeleton2D 场景。
## 运行：godot --headless --path . --script res://tools/rig/build_scenes.gd

const MANIFEST_DIR := "res://assets/rigs/manifests"
const SHADER_PATH := "res://assets/rigs/outline.gdshader"
const PAD_PATH := "res://assets/rigs/joint_pad.png"


func _initialize() -> void:
	var dir := DirAccess.open(ProjectSettings.globalize_path(MANIFEST_DIR))
	if dir == null:
		push_error("没有清单目录 " + MANIFEST_DIR)
		quit(1)
		return
	var names: Array[String] = []
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry.ends_with(".json"):
			names.append(entry)
		entry = dir.get_next()
	dir.list_dir_end()
	names.sort()
	if names.is_empty():
		push_error("没有清单")
		quit(1)
		return
	for file_name in names:
		var path := MANIFEST_DIR + "/" + file_name
		var data = _read_json(path)
		if data == null:
			quit(1)
			return
		var scene_path := String(data["scene"])
		var rig := _build(data)
		get_root().add_child(rig)
		_bind_meshes(rig, data)
		var err := _save(rig, scene_path)
		rig.queue_free()
		if err != OK:
			push_error("保存出错 %s (%s)" % [scene_path, error_string(err)])
			quit(1)
			return
		print("场景 ", scene_path, " bone ", data["bones"].size())
	_save_mirror()
	print("build_scenes 完成")
	quit(0)


func _read_json(path: String):
	var f := FileAccess.open(ProjectSettings.globalize_path(path), FileAccess.READ)
	if f == null:
		push_error("打不开 " + path)
		return null
	var data = JSON.parse_string(f.get_as_text())
	f.close()
	if data == null:
		push_error("JSON 格式不对 " + path)
	return data


func _build(data: Dictionary) -> Node2D:
	var rig := Node2D.new()
	rig.name = String(data["id"])
	rig.set_script(load("res://scenes/rigs/rig_present.gd"))
	# 权重网格放进 CanvasGroup 会变成白块，所以整只画进 SubViewport，再对合成图描边。
	var view := SubViewport.new()
	view.name = "View"
	view.size = Vector2i(512, 512)
	view.transparent_bg = true
	view.disable_3d = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	view.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR
	rig.add_child(view)
	var motion := Node2D.new()
	motion.name = "Motion"
	# 脚底放在视口偏下，上面留出手的空间。这个节点不被动画改位置。
	motion.position = Vector2(256, 450)
	view.add_child(motion)
	var bob := Node2D.new()
	bob.name = "Bob"
	motion.add_child(bob)
	var sk := Skeleton2D.new()
	sk.name = "Skeleton"
	bob.add_child(sk)
	var bones := {}
	for b in data["bones"]:
		var bone := Bone2D.new()
		bone.name = String(b["name"])
		# 关掉自动朝向子节点，否则停住时会被转去指向子节点，部件会散开。
		bone.auto_calculate_length_and_angle = false
		var p: Array = b["pos"]
		bone.position = Vector2(float(p[0]), float(p[1]))
		bone.rotation = 0.0
		var parent_name := String(b["parent"])
		var parent: Node = sk
		if parent_name != "":
			parent = bones[parent_name]
		parent.add_child(bone)
		bone.rest = bone.transform
		bones[bone.name] = bone
	var pad_tex: Texture2D = load(PAD_PATH)
	for sp in data["sprites"]:
		var sprite := Sprite2D.new()
		sprite.name = String(sp["name"])
		sprite.centered = true
		sprite.texture = load(String(sp["tex"]))
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		var lp: Array = sp["pos"]
		sprite.position = Vector2(float(lp[0]), float(lp[1]))
		sprite.z_index = int(sp["z"])
		bones[String(sp["bone"])].add_child(sprite)
	for pad in data["pads"]:
		var spr := Sprite2D.new()
		spr.name = "pad_" + String(pad["joint"])
		spr.centered = true
		spr.texture = pad_tex
		spr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		var rad := float(pad["radius"])
		spr.scale = Vector2.ONE * (rad * 2.0 / 32.0)
		var col: Array = pad["color"]
		spr.modulate = Color(float(col[0]), float(col[1]), float(col[2]), 1.0)
		spr.z_index = int(pad["z"])
		bones[String(pad["bone"])].add_child(spr)
	for mesh in data["meshes"]:
		var poly := Polygon2D.new()
		poly.name = String(mesh["name"])
		poly.texture = load(String(mesh["tex"]))
		poly.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		poly.z_index = int(mesh["z"])
		poly.antialiased = false
		poly.polygon = _vec2s(mesh["points"])
		poly.uv = _vec2s(mesh["uvs"])
		var tris: Array = []
		for t in mesh["tris"]:
			tris.append(PackedInt32Array([int(t[0]), int(t[1]), int(t[2])]))
		poly.polygons = tris
		# 不挂 Skeleton2D。gl_compatibility 里 GPU 权重会把网格画没。
		# 权重交给 rig_present.gd，每帧在 CPU 上算。
		sk.add_child(poly)
	var outline := Sprite2D.new()
	outline.name = "Outline"
	outline.centered = true
	outline.texture = view.get_texture()
	outline.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	# 视口中心在 (256,256)，脚底在 (256,450)，把脚底对到角色原点。
	outline.position = Vector2(0, -(450 - 256))
	var mat := ShaderMaterial.new()
	mat.shader = load(SHADER_PATH)
	var oc: Array = data["outline_color"]
	mat.set_shader_parameter("outline_color", Color(float(oc[0]), float(oc[1]), float(oc[2]), float(oc[3])))
	mat.set_shader_parameter("outline_width", float(data.get("outline_width", 1.5)))
	outline.material = mat
	rig.add_child(outline)
	var player := AnimationPlayer.new()
	player.name = "AnimationPlayer"
	player.root_node = NodePath("..")
	var lib := AnimationLibrary.new()
	for anim_desc in data["anims"]:
		lib.add_animation(String(anim_desc["name"]), _anim(anim_desc, data))
	player.add_animation_library("", lib)
	if data["anims"].size() > 0:
		player.autoplay = "idle"
	rig.add_child(player)
	_own(rig, rig)
	return rig


func _bind_meshes(rig: Node2D, data: Dictionary) -> void:
	# 每个网格记下 bone 路径和每个顶点的权重，场景运行时再变形。
	if data["bones"].size() > 20:
		push_error("%s bone %d 超过 20" % [data["id"], data["bones"].size()])
		quit(1)
		return
	var parents := {}
	for b in data["bones"]:
		parents[String(b["name"])] = String(b["parent"])
	var sk := rig.get_node("View/Motion/Bob/Skeleton") as Skeleton2D
	for mesh in data["meshes"]:
		var poly := sk.get_node(String(mesh["name"])) as Polygon2D
		var names: Array = mesh["bone_names"]
		var weights: Array = mesh["weights"]
		var nverts := poly.polygon.size()
		var per_bone := {}
		for v in nverts:
			for k in 4:
				var slot := v * 4 + k
				var w := float(weights[slot])
				if w <= 0.0001:
					continue
				var bone_name := String(names[slot])
				if not per_bone.has(bone_name):
					var arr := PackedFloat32Array()
					arr.resize(nverts)
					per_bone[bone_name] = arr
				per_bone[bone_name][v] = float(per_bone[bone_name][v]) + w
		var paths: Array = []
		var weight_rows: Array = []
		for bone_name in per_bone.keys():
			paths.append(_bone_node_path(parents, String(bone_name)))
			weight_rows.append(per_bone[bone_name])
		poly.set_meta("skin", {
			"paths": paths,
			"weights": weight_rows,
			"rest": poly.polygon,
		})


func _bone_node_path(parents: Dictionary, name: String) -> String:
	var chain: Array[String] = []
	var cur := name
	while cur != "":
		chain.append(cur)
		cur = String(parents.get(cur, ""))
	chain.reverse()
	return "../" + "/".join(chain)


func _anim(desc: Dictionary, data: Dictionary) -> Animation:
	var anim := Animation.new()
	var fps := float(desc["fps"])
	var nframes := int(desc["frames"])
	anim.length = nframes / fps
	anim.step = 1.0 / fps
	anim.loop_mode = Animation.LOOP_LINEAR if bool(desc["loop"]) else Animation.LOOP_NONE
	var parents := {}
	for b in data["bones"]:
		parents[String(b["name"])] = String(b["parent"])
	var rots: Dictionary = desc["rot"]
	for bone_name in rots.keys():
		var values: Array = rots[bone_name]
		var ti := anim.add_track(Animation.TYPE_VALUE)
		anim.track_set_path(ti, NodePath(_bone_path(parents, String(bone_name)) + ":rotation"))
		anim.track_set_interpolation_type(ti, Animation.INTERPOLATION_LINEAR)
		anim.value_track_set_update_mode(ti, Animation.UPDATE_CONTINUOUS)
		for i in values.size():
			anim.track_insert_key(ti, i / fps, deg_to_rad(float(values[i])))
	if desc.has("pos"):
		var pos: Dictionary = desc["pos"]
		for node_name in pos.keys():
			var values: Array = pos[node_name]
			var ti := anim.add_track(Animation.TYPE_VALUE)
			var pos_path := "View/Motion/Bob" if String(node_name) == "Motion" else String(node_name)
			anim.track_set_path(ti, NodePath(pos_path + ":position"))
			anim.track_set_interpolation_type(ti, Animation.INTERPOLATION_LINEAR)
			anim.value_track_set_update_mode(ti, Animation.UPDATE_CONTINUOUS)
			for i in values.size():
				var xy: Array = values[i]
				anim.track_insert_key(ti, i / fps, Vector2(float(xy[0]), float(xy[1])))
	return anim


func _bone_path(parents: Dictionary, name: String) -> String:
	var chain: Array[String] = []
	var cur := name
	while cur != "":
		chain.append(cur)
		cur = String(parents.get(cur, ""))
	chain.reverse()
	return "View/Motion/Bob/Skeleton/" + "/".join(chain)


func _vec2s(raw: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in raw:
		out.append(Vector2(float(p[0]), float(p[1])))
	return out


func _own(node: Node, root: Node) -> void:
	for c in node.get_children():
		c.owner = root
		_own(c, root)


func _save(node: Node, path: String) -> int:
	var packed := PackedScene.new()
	var err := packed.pack(node)
	if err != OK:
		return err
	var abs := ProjectSettings.globalize_path(path)
	DirAccess.make_dir_recursive_absolute(abs.get_base_dir())
	return ResourceSaver.save(packed, path)


func _save_mirror() -> void:
	# 左侧不另做一套，直接把侧面场景水平镜像。手写 tscn，避免 pack 把实例展开成两份。
	var text := "[gd_scene load_steps=2 format=3]\n\n[ext_resource type=\"PackedScene\" path=\"res://scenes/rigs/hero_s.tscn\" id=\"1_side\"]\n\n[node name=\"hero_l\" type=\"Node2D\"]\nscale = Vector2(-1, 1)\n\n[node name=\"Side\" parent=\".\" instance=ExtResource(\"1_side\")]\n"
	var abs := ProjectSettings.globalize_path("res://scenes/rigs/hero_l.tscn")
	DirAccess.make_dir_recursive_absolute(abs.get_base_dir())
	var f := FileAccess.open(abs, FileAccess.WRITE)
	if f == null:
		push_error("镜像场景写不了")
		quit(1)
		return
	f.store_string(text)
	f.close()
	print("场景 res://scenes/rigs/hero_l.tscn 镜像侧面")
