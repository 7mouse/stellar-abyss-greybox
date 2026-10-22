extends SceneTree
## 最窄通道统计：godot --headless -s tools/map/passage.gd -- <层号> <种子数> [cliff_th]
func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var depth := int(a[0])
	var fd: FloorData = load("res://data/floors/floor_%d.tres" % depth)
	if a.size() > 2:
		fd.ecology.cliff_th = float(a[2])
	var mn := 1e9; var worst := 0; var t0 := Time.get_ticks_msec(); var ws: Array = []
	for i in int(a[1]):
		var sd := 424242 + i * 7919
		var w := MapGen.passage_width(MapGen.generate(sd, depth, fd))
		ws.append(w)
		if w < mn: mn = w; worst = sd
	ws.sort()
	print("floor %d cliff_th %.2f：最窄 %.0f px（种子 %d），中位 %.0f，%d ms" % [depth, fd.ecology.cliff_th, mn, worst, ws[ws.size() / 2], Time.get_ticks_msec() - t0])
	quit()
