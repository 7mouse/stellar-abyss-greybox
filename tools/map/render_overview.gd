extends SceneTree
## 用真实 MapGen 生成楼层并输出俯视总览 PNG（地面混合 + 障碍 + 摆放点；不画区块网格）
## godot --headless -s tools/map/render_overview.gd -- <输出目录> <层号> <种子...>
func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0]
	var depth := int(args[1])
	var fd: FloorData = load("res://data/floors/floor_%d.tres" % depth)
	DirAccess.make_dir_recursive_absolute(out)
	for sa in args.slice(2):
		var seed := int(sa)
		var t0 := Time.get_ticks_usec()
		var L := MapGen.generate(seed, depth, fd)
		var gen_ms := (Time.get_ticks_usec() - t0) / 1000.0
		var t1 := Time.get_ticks_usec()
		var np := NavigationPolygon.new()
		np.agent_radius = 24.0
		var src := NavigationMeshSourceGeometryData2D.new()
		var b: Rect2 = L.bounds
		src.add_traversable_outline(_poly(b))
		var solids := MapGen.all_solids(L)
		for r in solids:
			src.add_obstruction_outline(_poly(r))
		NavigationServer2D.bake_from_source_geometry_data(np, src)
		var bake_ms := (Time.get_ticks_usec() - t1) / 1000.0
		var T: Dictionary = L.terrain
		var open_cells := 0
		for i in T.nx * T.ny:
			if T.cells[i] == 0: open_cells += 1
		var grid := MapGen.reach_grid(L)
		var reach := 0
		var free := 0
		for i in grid.nx * grid.ny:
			reach += grid.seen[i]
		var st := MapGen.stats(L)
		print("seed=%d ok=%s attempt=%d gen=%.1fms bake=%.1fms polys=%d solids=%d open=%.1f%% filled_pockets=%d reach40=%d unreachable_chunks=%s unreachable_points=%d stats=%s" % [seed, L.ok, L.attempt, gen_ms, bake_ms, np.get_polygon_count(), solids.size(), 100.0 * open_cells / (T.nx * T.ny), T.filled, reach, str(MapGen.unreachable_chunks(L)), MapGen.unreachable_points(L).size(), str(st)])
		# 画图：1px = 8 游戏像素
		var S := 8.0
		var W := int(b.size.x / S)
		var H := int(b.size.y / S)
		var imgs := MapGen.terrain_images(L)
		var g: Image = imgs[0]; g.resize(W, H, Image.INTERPOLATE_BILINEAR)
		var o: Image = imgs[1]; o.resize(W, H, Image.INTERPOLATE_BILINEAR)
		g.blend_rect(o, Rect2i(0, 0, W, H), Vector2i.ZERO)
		for c in L.chunks:
			for r in c.walls:
				g.fill_rect(Rect2i(Vector2i(r.position / S), Vector2i((r.size / S).ceil())), MapGen.KIND_COLORS[MapGen.T_RUIN].lightened(0.2))
		var dot := func(p: Vector2, col: Color, rad := 5) -> void:
			for dy in range(-rad, rad + 1):
				for dx in range(-rad, rad + 1):
					if dx * dx + dy * dy <= rad * rad:
						var x := int(p.x / S) + dx; var y := int(p.y / S) + dy
						if x >= 0 and y >= 0 and x < W and y < H: g.set_pixel(x, y, col)
		var sp: Dictionary = L.spawn_points
		for p in sp.patrol:
			for q in p.points: dot.call(q, Color(1, 0.3, 0.3), 4)
		for c in sp.camp: dot.call(c.center, Color(1, 0.1, 0.1), 9)
		for q in sp.chest: dot.call(q, Color(1, 0.85, 0.2), 6)
		for q in sp.node: dot.call(q, Color(0.3, 1, 0.75), 5)
		for i in L.shrines: dot.call(MapGen.chunk_rect(L.chunks[i], L.chunk_px).get_center(), Color(0.6, 0.5, 1), 7)
		for h in sp.get("hazard", []):
			var hc: Color = fd.ecology.hazards[h.idx].color
			dot.call(h.pos, Color(0, 0, 0), 9)
			dot.call(h.pos, hc.lightened(0.35), 7)
		dot.call(L.start_pos, Color(1, 1, 1), 9)
		dot.call(L.campfire_pos, Color(1, 0.55, 0.15), 7)
		dot.call(L.guard_pos, Color(0.9, 0.2, 0.9), 10)
		dot.call(L.exit_pos, Color(0.6, 0.6, 0.7), 6)
		g.save_png("%s/floor%d_seed%d.png" % [out, depth, seed])
		print("floor %d seed %d：%s，机关 %d，根柱 %d" % [depth, seed, fd.ecology.display_name if fd.ecology else "-", sp.get("hazard", []).size(), L.get("root_pillars", []).size()])
	quit()

static func _poly(r: Rect2) -> PackedVector2Array:
	return PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
