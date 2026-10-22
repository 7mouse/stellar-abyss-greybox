extends Node
## 出图：RIG_OUT 指定目录。由 xvfb 打开，不用 --headless（那样不画）。

func _ready() -> void:
	var out := OS.get_environment("RIG_OUT")
	if out == "":
		out = "/tmp/rigshots"
	DirAccess.make_dir_recursive_absolute(out)
	var viewer = load("res://scenes/dev/rig_viewer.tscn").instantiate()
	add_child(viewer)
	await get_tree().process_frame
	await get_tree().process_frame
	await _still(viewer, 0, 0.35, out + "/viewer_idle.png")
	await _still(viewer, 1, 0.22, out + "/viewer_move.png")
	await _still(viewer, 2, 0.33, out + "/viewer_attack.png")
	await _still(viewer, 3, 0.16, out + "/viewer_hit.png")
	await _still(viewer, 4, 0.22, out + "/viewer_left_move.png")
	await _still(viewer, 5, 0.4, out + "/viewer_front_idle.png")
	await _still(viewer, 6, 0.4, out + "/viewer_back_idle.png")
	await _clip(viewer, out)
	print("capture done ", out)
	get_tree().quit(0)


func _still(viewer: Node, state: int, t: float, path: String) -> void:
	viewer.call("show_state", state)
	viewer.call("seek", t)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_save(path)


func _clip(viewer: Node, out: String) -> void:
	# 12fps：待机 1 秒、移动 1 秒、轻攻击一轮，mushling 跟着待机或移动。
	var seq := [
		{"state": 0, "dur": 1.0},
		{"state": 1, "dur": 1.0},
		{"state": 2, "dur": 0.7},
	]
	var fps := 12.0
	var n := 0
	for part in seq:
		viewer.call("show_state", int(part["state"]))
		var frames := int(round(float(part["dur"]) * fps))
		for i in frames:
			viewer.call("seek", i / fps)
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			_save("%s/frame_%03d.png" % [out, n])
			n += 1
	print("frames ", n)


func _save(path: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
