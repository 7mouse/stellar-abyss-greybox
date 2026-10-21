class_name MapGen
extends RefCounted
## 开放地图生成（取代房间制 FloorGen）：grid_w × grid_h 个区块拼成一整张打通的平层地图。
## 1. 随机 DFS 生成树保证全连通，再按 loop_chance 给相邻区块额外打通（环路）；层主区只开 1~2 个口。
## 2. 区块只是生成/摆放的内部单位，区块之间没有墙。只有层主区有残垣围墙，入口宽 gap_px；外圈 map_border_px 实心墙。
## 3. 地形：64px 地形格，噪声定初始密度 → 元胞自动机平滑成团块（灌木/岩石/断崖/水/残垣），
##    沿区块图的打通边挖蜿蜒小路（宽度随噪声变化 → 隘口），区块中心挖空地；走不到的小洞填实。
##    地面群系（林地/野地/废墟）由低频噪声连续混合，普通区块的类型取区块中心的群系。
## 4. 摆放约束：起点在第 0 列、层主区在最后一列；营地距起点 ≥2、两两 ≥2、至少 1 个在最短路径 ±1 区块内；神龛不贴起点。
## 5. 40px 栅格 BFS 走通检查，不满足就换子种子重生（最多重试 5 次）。区块间距离一律按切比雪夫距离（含斜向）算。

const WALL := 40.0
const DIRS := [Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0)]
const NORMAL := ["field", "grove", "ruin"]
const MAX_RETRY := 5
const PATROL_OBS_MARGIN := 90.0 ## 巡逻路线点离障碍/墙 ≥ 60px（取 90，给组员站位留余量）
const SAFE_START_PX := 720.0 ## 巡逻点离主角出生点的最小距离（> 临时追击半径 600，开局不被立刻追）
const FIRE_SAFE_PX := 400.0 ## 巡逻点离篝火的最小距离（篝火旁不站巡逻）
const LOOT_ROUTE_DIST := 150.0 ## 宝箱/资源点离路线点 ≥ 150px

static func generate(seed: int, depth: int, fd: FloorData, first_run := true) -> Dictionary:
	var L := {}
	for attempt in MAX_RETRY + 1:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([seed, depth, "map"]) if attempt == 0 else hash([seed, depth, "map", attempt])
		L = _try(rng, fd, first_run)
		L["seed"] = seed
		L["depth"] = depth
		L["attempt"] = attempt
		if L.ok and unreachable_chunks(L).is_empty():
			break
	return L

static func cheb(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))

static func _ekey(a: Vector2i, b: Vector2i) -> String:
	return "%d,%d|%d,%d" % ([a.x, a.y, b.x, b.y] if (a.x < b.x or (a.x == b.x and a.y < b.y)) else [b.x, b.y, a.x, a.y])

static func _try(rng: RandomNumberGenerator, fd: FloorData, first_run: bool) -> Dictionary:
	var W := fd.grid_w
	var H := fd.grid_h
	var cp := fd.chunk_px
	var inside := func(c: Vector2i) -> bool: return c.x >= 0 and c.y >= 0 and c.x < W and c.y < H
	var start := Vector2i(0, rng.randi_range(0, H - 1))
	var gcell := Vector2i(W - 1, rng.randi_range(0, H - 1))
	var open := {} ## edge key -> 开口中心沿边的偏移（px，从边起点量）
	var open_edge := func(a: Vector2i, b: Vector2i) -> void:
		open[_ekey(a, b)] = cp * 0.5 + rng.randf_range(-0.25, 0.25) * cp
	# 1. 生成树（不含层主区），随机 DFS
	var seen := {start: true}
	var stack: Array = [start]
	while not stack.is_empty():
		var c: Vector2i = stack[-1]
		var opts: Array = []
		for d in DIRS:
			var n: Vector2i = c + d
			if inside.call(n) and n != gcell and not seen.has(n):
				opts.append(n)
		if opts.is_empty():
			stack.pop_back()
			continue
		var n: Vector2i = opts[rng.randi_range(0, opts.size() - 1)]
		seen[n] = true
		open_edge.call(c, n)
		stack.append(n)
	# 环路
	for y in H:
		for x in W:
			var a := Vector2i(x, y)
			for d in [Vector2i(1, 0), Vector2i(0, 1)]:
				var b: Vector2i = a + d
				if inside.call(b) and a != gcell and b != gcell and not open.has(_ekey(a, b)) and rng.randf() < fd.loop_chance:
					open_edge.call(a, b)
	# 层主区：1~2 个入口
	var gn: Array = []
	for d in DIRS:
		if inside.call(gcell + d):
			gn.append(gcell + d)
	for i in gn.size():
		var j := rng.randi_range(i, gn.size() - 1)
		var t = gn[i]; gn[i] = gn[j]; gn[j] = t
	var guard_entrances: Array = [gn[0]]
	if gn.size() > 1 and rng.randf() < fd.loop_chance:
		guard_entrances.append(gn[1])
	for n in guard_entrances:
		open_edge.call(gcell, n)
	# 区块
	var chunks: Array = []
	for y in H:
		for x in W:
			chunks.append({"id": y * W + x, "cell": Vector2i(x, y), "type": "", "template": 0, "obstacles": [], "obstacle_kinds": [], "open_edges": {}, "walls": []})
	var cid := func(c: Vector2i) -> int: return c.y * W + c.x
	var L := {"ok": true, "chunks": chunks, "grid_w": W, "grid_h": H, "chunk_px": cp,
		"start_chunk": cid.call(start), "guard_chunk": cid.call(gcell), "open": open}
	var path := _bfs_path(L, start, gcell)
	L["path"] = path
	if path.size() - 1 < fd.min_start_guard_dist:
		L.ok = false
	# 2. 类型（普通区块的类型在地形生成后按群系定）
	var path_cells: Array = path.map(func(i): return chunks[i].cell)
	var guard_adj := func(c: Vector2i) -> bool: return cheb(c, gcell) <= 1
	var cand: Array = []
	for ch in chunks:
		var c: Vector2i = ch.cell
		if c != start and c != gcell and cheb(c, start) >= 2 and not guard_adj.call(c):
			cand.append(c)
	var near_path := func(c: Vector2i) -> bool: return path_cells.any(func(p): return cheb(p, c) <= 1)
	var camps: Array = []
	var first: Array = cand.filter(near_path)
	if first.is_empty():
		L.ok = false
	else:
		camps.append(first[rng.randi_range(0, first.size() - 1)])
	while camps.size() < fd.camps and L.ok:
		var rest: Array = cand.filter(func(c): return camps.all(func(k): return cheb(k, c) >= 2))
		if rest.is_empty():
			L.ok = false
			break
		camps.append(rest[rng.randi_range(0, rest.size() - 1)])
	var shrines: Array = []
	for i in fd.shrines:
		var rest: Array = []
		for ch in chunks:
			var c: Vector2i = ch.cell
			if c != start and c != gcell and cheb(c, start) >= 2 and not camps.has(c) and not shrines.has(c):
				rest.append(c)
		if rest.is_empty():
			L.ok = false
			break
		shrines.append(rest[rng.randi_range(0, rest.size() - 1)])
	for ch in chunks:
		var c: Vector2i = ch.cell
		if c == start: ch.type = "start"
		elif c == gcell: ch.type = "guard"
		elif camps.has(c): ch.type = "camp"
		elif shrines.has(c): ch.type = "shrine"
	L["camps"] = camps.map(func(c): return cid.call(c))
	L["shrine"] = cid.call(shrines[0]) if not shrines.is_empty() else -1
	L["shrines"] = shrines.map(func(c): return cid.call(c))
	var bounds := Rect2(0, 0, W * cp, H * cp)
	L["bounds"] = bounds
	var b := fd.map_border_px
	L["border"] = [Rect2(-b, -b, bounds.size.x + 2 * b, b), Rect2(-b, bounds.size.y, bounds.size.x + 2 * b, b),
		Rect2(-b, 0, b, bounds.size.y), Rect2(bounds.size.x, 0, b, bounds.size.y)]
	# 3. 层主区围墙（全图唯一的墙：残垣围成的场地，入口 1~2 个）
	var grc := chunk_rect_cell(gcell, cp)
	var gch0: Dictionary = chunks[cid.call(gcell)]
	for d in DIRS:
		var n: Vector2i = gcell + d
		if not inside.call(n):
			continue
		var side: Rect2
		if d == Vector2i(1, 0): side = Rect2(grc.end.x - WALL / 2, grc.position.y, WALL, cp)
		elif d == Vector2i(-1, 0): side = Rect2(grc.position.x - WALL / 2, grc.position.y, WALL, cp)
		elif d == Vector2i(0, -1): side = Rect2(grc.position.x, grc.position.y - WALL / 2, cp, WALL)
		else: side = Rect2(grc.position.x, grc.end.y - WALL / 2, cp, WALL)
		var k := _ekey(gcell, n)
		if open.has(k):
			var g0: float = open[k] - fd.gap_px / 2
			var gap: Rect2
			if d.y != 0:
				gap = Rect2(side.position + Vector2(g0, 0), Vector2(fd.gap_px, WALL))
				gch0.walls.append(Rect2(side.position, Vector2(g0, WALL)))
				gch0.walls.append(Rect2(Vector2(gap.end.x, side.position.y), Vector2(side.end.x - gap.end.x, WALL)))
			else:
				gap = Rect2(side.position + Vector2(0, g0), Vector2(WALL, fd.gap_px))
				gch0.walls.append(Rect2(side.position, Vector2(WALL, g0)))
				gch0.walls.append(Rect2(Vector2(side.position.x, gap.end.y), Vector2(WALL, side.end.y - gap.end.y)))
			gch0.open_edges[d] = gap
		else:
			gch0.walls.append(side)
	# 4. 有机地形（噪声 + 元胞自动机），区块之间没有墙
	var T := _terrain(rng, L, fd)
	var grid: Dictionary = T._grid
	T.erase("_grid")
	L["terrain"] = T
	for ch in chunks:
		if ch.type == "":
			var bv: float = biome_at(T, chunk_rect(ch, cp).get_center())
			ch.type = "grove" if bv < -0.12 else ("ruin" if bv > 0.18 else "field")
	var solids := all_solids(L)
	# 层主区入口、篝火、撤离点
	var gch: Dictionary = chunks[cid.call(gcell)]
	var gc := chunk_rect(gch, cp).get_center()
	var ents: Array = []
	for n in guard_entrances:
		var d: Vector2i = n - gcell
		ents.append({"dir": d, "gap": gch.open_edges[d], "chunk": cid.call(n)})
	L["guard_entrances"] = ents
	var d0 := Vector2(ents[0].dir)
	var gap0: Rect2 = ents[0].gap
	var fire := gap0.get_center() + d0 * 200.0
	var along := Vector2(d0.y, d0.x).abs()
	var ncenter := chunk_rect(chunks[ents[0].chunk], cp).get_center()
	for i in 20:
		if is_free(fire, solids, 60.0):
			break
		fire = fire.move_toward(fire - along * (fire - ncenter).dot(along), 30.0)
	L["campfire_pos"] = fire
	L["guard_pos"] = gc
	L["exit_pos"] = gc - d0 * 300.0
	var start_pos := chunk_rect(chunks[L.start_chunk], cp).get_center()
	L["start_pos"] = start_pos
	L["landmarks"] = []
	# 地标在篝火之后、巡逻之前。没有地标的层不消耗随机数，地形和后面的摆放都不变。
	if not fd.landmarks.is_empty():
		if not _place_landmarks(rng, L, fd, grid, first_run):
			L.ok = false
		solids = all_solids(L)
		grid = reach_grid(L)
		_nudge_pods(L, grid)
		if _chunks_blocked(L, grid) and _remove_tree(L):
			solids = all_solids(L)
			grid = reach_grid(L)
			_nudge_pods(L, grid)
		if not _anchors_ok(L, grid):
			L.ok = false
	# 5. 刷怪点、宝箱、资源点
	var spawn := {"patrol": [], "camp": [], "chest": [], "node": []}
	var routes := {} ## chunk id -> [Vector2]
	for ch in chunks:
		if not NORMAL.has(ch.type) or rng.randf() >= fd.patrol_chance:
			continue
		var rc := chunk_rect(ch, cp).grow(-110)
		var pts: Array = []
		var want := rng.randi_range(2, 4)
		for t in 300:
			if pts.size() >= want:
				break
			var p := Vector2(rng.randf_range(rc.position.x, rc.end.x), rng.randf_range(rc.position.y, rc.end.y))
			if point_reachable(grid, p) and is_free(p, solids, PATROL_OBS_MARGIN) and not _landmark_blocks(L, p) and p.distance_to(start_pos) >= SAFE_START_PX and p.distance_to(fire) >= FIRE_SAFE_PX and pts.all(func(q): return q.distance_to(p) >= 160.0):
				pts.append(p)
		if pts.size() < 2:
			continue
		routes[ch.id] = pts
		spawn.patrol.append({"chunk": ch.id, "points": pts, "size": rng.randi_range(fd.patrol_size_min, fd.patrol_size_max)})
	for k in L.camps:
		spawn.camp.append({"chunk": k, "center": chunk_rect(chunks[k], cp).get_center(), "size": rng.randi_range(fd.camp_size_min, fd.camp_size_max)})
	var loot_chunks: Array = chunks.filter(func(ch): return NORMAL.has(ch.type) or ch.type == "shrine").map(func(ch): return ch.id)
	var taken: Array = []
	for kind in ["chest", "node"]:
		var n_want: int = fd.chests if kind == "chest" else fd.resource_nodes
		for i in n_want:
			var p := _loot_point(rng, chunks, loot_chunks, routes, taken, solids, cp, grid, L)
			taken.append(p)
			spawn[kind].append(p)
	# 6. 环境机关（§8.1）：普通区块空地上，离巡逻路线点 ≥ 150px
	spawn["hazard"] = []
	if fd.ecology:
		var all_route: Array = []
		for k2 in routes: all_route.append_array(routes[k2])
		var norm: Array = chunks.filter(func(ch): return NORMAL.has(ch.type))
		var htaken: Array = taken.duplicate()
		for hi in fd.ecology.hazards.size():
			var hz: HazardData = fd.ecology.hazards[hi]
			for n in fd.ecology.hazard_count(hi):
				for t in 200:
					var ch: Dictionary = norm[rng.randi_range(0, norm.size() - 1)]
					var ir := chunk_rect(ch, cp).grow(-120)
					var p := Vector2(rng.randf_range(ir.position.x, ir.end.x), rng.randf_range(ir.position.y, ir.end.y))
					if not point_reachable(grid, p) or not is_free(p, solids, hz.radius + 20.0) or _landmark_blocks(L, p):
						continue
					if all_route.any(func(q): return q.distance_to(p) < HAZARD_ROUTE_DIST) or htaken.any(func(q): return q.distance_to(p) < 180.0):
						continue
					if p.distance_to(start_pos) < SAFE_START_PX or p.distance_to(fire) < FIRE_SAFE_PX:
						continue
					htaken.append(p)
					spawn.hazard.append({"id": hz.id, "idx": hi, "pos": p, "chunk": ch.id})
					break
	L["spawn_points"] = spawn
	_mark_traps(rng, L, fd)
	return L

## 陷阱房：普通区块打上 no_recall，不改类型、不改刷怪，所以敌人总数和巡逻期望不变。数量读 recall_charm.tres
static func _mark_traps(rng: RandomNumberGenerator, L: Dictionary, fd: FloorData) -> void:
	var rules: RecallCharm = load("res://data/recall_charm.tres")
	var n := rules.trap_count(fd.depth)
	for ch in L.chunks:
		ch["no_recall"] = false
	var traps: Array = []
	if n > 0:
		var pool: Array = []
		for ch in L.chunks:
			if NORMAL.has(ch.type):
				pool.append(ch)
		for i in mini(n, pool.size()):
			var j := rng.randi_range(i, pool.size() - 1)
			var tmp = pool[i]
			pool[i] = pool[j]
			pool[j] = tmp
			pool[i]["no_recall"] = true
			traps.append(pool[i].id)
	L["traps"] = traps

static func _loot_point(rng: RandomNumberGenerator, chunks: Array, loot_chunks: Array, routes: Dictionary, taken: Array, solids: Array, cp: float, grid: Dictionary, L: Dictionary) -> Vector2:
	var last := Vector2.ZERO
	for t in 120:
		var ch: Dictionary = chunks[loot_chunks[rng.randi_range(0, loot_chunks.size() - 1)]]
		var rc := chunk_rect(ch, cp)
		var ir := rc.grow(-90)
		var p := Vector2(rng.randf_range(ir.position.x, ir.end.x), rng.randf_range(ir.position.y, ir.end.y))
		last = p
		if not point_reachable(grid, p) or not is_free(p, solids, 50.0) or _landmark_blocks(L, p):
			continue
		if routes.get(ch.id, []).any(func(q): return q.distance_to(p) < LOOT_ROUTE_DIST):
			continue
		if taken.any(func(q): return q.distance_to(p) < 200.0):
			continue
		return p
	return last

static func is_free(p: Vector2, solids: Array, margin: float) -> bool:
	for s in solids:
		if s.grow(margin).has_point(p):
			return false
	return true

static func _bfs_path(L: Dictionary, a: Vector2i, b: Vector2i) -> Array:
	var W: int = L.grid_w
	var H: int = L.grid_h
	var prev := {a: a}
	var q: Array = [a]
	while not q.is_empty():
		var c: Vector2i = q.pop_front()
		if c == b:
			break
		for d in DIRS:
			var n: Vector2i = c + d
			if n.x < 0 or n.y < 0 or n.x >= W or n.y >= H or prev.has(n) or not L.open.has(_ekey(c, n)):
				continue
			prev[n] = c
			q.append(n)
	if not prev.has(b):
		return []
	var out: Array = []
	var c := b
	while c != a:
		out.push_front(c.y * W + c.x)
		c = prev[c]
	out.push_front(a.y * W + a.x)
	return out

# ---------- 工具函数 ----------
static func chunk_rect_cell(c: Vector2i, cp: float) -> Rect2:
	return Rect2(Vector2(c) * cp, Vector2(cp, cp))

static func chunk_rect(c: Dictionary, cp := 1024.0) -> Rect2:
	return chunk_rect_cell(c.cell, cp)

## 区块持有的墙：右/下共享边（不通 = 整面，打通 = 开口两侧）；外圈墙见 layout.border
static func chunk_walls(c: Dictionary) -> Array:
	return c.walls

static func chunk_obstacles(c: Dictionary) -> Array:
	return c.obstacles

static func all_solids(layout: Dictionary) -> Array[Rect2]:
	var out: Array[Rect2] = []
	for r in layout.get("border", []):
		out.append(r)
	for c in layout.chunks:
		for r in c.walls:
			out.append(r)
		for r in c.obstacles:
			out.append(r)
	return out

## 起点 → 层主区入口外篝火的“最窄通道”宽度（px）：所有可走路线里最宽那条的瓶颈。
## 做法：cell px 栅格 → 到最近障碍的距离（chamfer 3-4）→ 按距离从大到小加入并查集，起终点连通时的距离 × 2
static func passage_width(L: Dictionary, cell := 16.0, info := {}) -> float:
	var b: Rect2 = L.bounds
	var nx := int(ceil(b.size.x / cell))
	var ny := int(ceil(b.size.y / cell))
	var INF := 1e9
	var d := PackedFloat32Array(); d.resize(nx * ny); d.fill(INF)
	for r in all_solids(L):
		var x0 := maxi(0, int((r.position.x - b.position.x) / cell)); var x1 := mini(nx - 1, int((r.end.x - b.position.x - 0.01) / cell))
		var y0 := maxi(0, int((r.position.y - b.position.y) / cell)); var y1 := mini(ny - 1, int((r.end.y - b.position.y - 0.01) / cell))
		for y in range(y0, y1 + 1):
			for x in range(x0, x1 + 1):
				d[y * nx + x] = 0.0
	var dg := cell * 1.4142
	for y in ny:
		for x in nx:
			var i := y * nx + x
			var v := d[i]
			if v == 0.0: continue
			if x > 0: v = minf(v, d[i - 1] + cell)
			else: v = minf(v, cell)
			if y > 0:
				v = minf(v, d[i - nx] + cell)
				if x > 0: v = minf(v, d[i - nx - 1] + dg)
				if x < nx - 1: v = minf(v, d[i - nx + 1] + dg)
			else: v = minf(v, cell)
			d[i] = v
	for y in range(ny - 1, -1, -1):
		for x in range(nx - 1, -1, -1):
			var i := y * nx + x
			var v := d[i]
			if v == 0.0: continue
			if x < nx - 1: v = minf(v, d[i + 1] + cell)
			else: v = minf(v, cell)
			if y < ny - 1:
				v = minf(v, d[i + nx] + cell)
				if x < nx - 1: v = minf(v, d[i + nx + 1] + dg)
				if x > 0: v = minf(v, d[i + nx - 1] + dg)
			else: v = minf(v, cell)
			d[i] = v
	var q := 4.0
	var dmax := 0.0
	for v in d: dmax = maxf(dmax, v)
	var nb := int(dmax / q) + 1
	var buckets: Array = []; buckets.resize(nb)
	for k in nb: buckets[k] = PackedInt32Array()
	for i in nx * ny:
		if d[i] > 0.0:
			buckets[int(d[i] / q)].append(i)
	var par: Array = []; par.resize(nx * ny); par.fill(-1) ## Array（lambda 里按引用）
	var find := func(f: Callable, i: int) -> int:
		var r := i
		while par[r] != r: r = par[r]
		while par[i] != r:
			var n: int = par[i]; par[i] = r; i = n
		return r
	var cidx := func(p: Vector2) -> int:
		return clampi(int((p.y - b.position.y) / cell), 0, ny - 1) * nx + clampi(int((p.x - b.position.x) / cell), 0, nx - 1)
	var s0: int = cidx.call(L.start_pos)
	var g0: int = cidx.call(L.campfire_pos)
	for k in range(nb - 1, -1, -1):
		for i in buckets[k]:
			par[i] = i
			var x: int = i % nx
			for j in [i - 1 if x > 0 else -1, i + 1 if x < nx - 1 else -1, i - nx, i + nx]:
				if j >= 0 and j < nx * ny and par[j] != -1:
					var ra: int = find.call(find, i); var rb: int = find.call(find, j)
					if ra != rb: par[ra] = rb
		if par[s0] != -1 and par[g0] != -1 and find.call(find, s0) == find.call(find, g0):
			if not buckets[k].is_empty():
				var bi: int = buckets[k][-1]
				info["at"] = b.position + Vector2((bi % nx + 0.5) * cell, (bi / nx + 0.5) * cell)
			return k * q * 2.0 - cell ## 格心距离偏大半格（两侧共一格），扣掉让结果保守
	return 0.0

## 区块级最短路（chunk id 列表，含起点和层主区）
static func shortest_path(layout: Dictionary) -> Array:
	var W: int = layout.grid_w
	var s: Dictionary = layout.chunks[layout.start_chunk]
	var g: Dictionary = layout.chunks[layout.guard_chunk]
	return _bfs_path(layout, s.cell, g.cell)

static func chunk_at(layout: Dictionary, p: Vector2) -> int:
	var cp: float = layout.chunk_px
	var c := Vector2i((p / cp).floor())
	if c.x < 0 or c.y < 0 or c.x >= layout.grid_w or c.y >= layout.grid_h:
		return -1
	return c.y * layout.grid_w + c.x

## 40px 栅格 BFS（照搬 FloorGen.unreachable_rooms 的思路，障碍按 radius 膨胀；栅格化代替逐格遍历全部矩形）
static func reach_grid(layout: Dictionary, radius := 24.0) -> Dictionary:
	var cs := 40.0
	var bounds: Rect2 = layout.bounds
	var nx := int(ceil(bounds.size.x / cs))
	var ny := int(ceil(bounds.size.y / cs))
	var blocked := PackedByteArray()
	blocked.resize(nx * ny)
	for s in all_solids(layout):
		var g: Rect2 = s.grow(radius)
		var x0 := maxi(0, int(ceil(g.position.x / cs - 0.5)))
		var x1 := mini(nx - 1, int(ceil(g.end.x / cs - 0.5)) - 1)
		var y0 := maxi(0, int(ceil(g.position.y / cs - 0.5)))
		var y1 := mini(ny - 1, int(ceil(g.end.y / cs - 0.5)) - 1)
		for y in range(y0, y1 + 1):
			for x in range(x0, x1 + 1):
				blocked[y * nx + x] = 1
	var seen := PackedByteArray()
	seen.resize(nx * ny)
	var sp := chunk_rect(layout.chunks[layout.start_chunk], layout.chunk_px).get_center()
	var si := int(sp.y / cs) * nx + int(sp.x / cs)
	if blocked[si] == 0:
		seen[si] = 1
		var q := PackedInt32Array([si])
		var head := 0
		while head < q.size():
			var i := q[head]
			head += 1
			var x := i % nx
			var y := i / nx
			for n in [i - 1 if x > 0 else -1, i + 1 if x < nx - 1 else -1, i - nx if y > 0 else -1, i + nx if y < ny - 1 else -1]:
				if n >= 0 and blocked[n] == 0 and seen[n] == 0:
					seen[n] = 1
					q.append(n)
	return {"seen": seen, "nx": nx, "ny": ny, "cs": cs}

static func point_reachable(grid: Dictionary, p: Vector2) -> bool:
	var x := int(p.x / grid.cs)
	var y := int(p.y / grid.cs)
	if x < 0 or y < 0 or x >= grid.nx or y >= grid.ny:
		return false
	return grid.seen[y * grid.nx + x] == 1

## 走不到的区块 id（区块中心按 40px 栅格到不了；空 = 全部走通）
static func unreachable_chunks(layout: Dictionary, radius := 24.0) -> Array:
	var grid := reach_grid(layout, radius)
	var bad: Array = []
	for c in layout.chunks:
		if not point_reachable(grid, chunk_rect(c, layout.chunk_px).get_center()):
			bad.append(c.id)
	return bad

## 所有刷怪点、宝箱、资源点、篝火、撤离点里走不到的
static func unreachable_points(layout: Dictionary, radius := 24.0) -> Array:
	var grid := reach_grid(layout, radius)
	var pts: Array = [layout.campfire_pos, layout.exit_pos, layout.guard_pos]
	for p in layout.spawn_points.patrol:
		pts += p.points
	for c in layout.spawn_points.camp:
		pts.append(c.center)
	pts += layout.spawn_points.chest
	pts += layout.spawn_points.node
	for lm in layout.get("landmarks", []):
		if lm.has("bar"):
			if lm.has("chest"):
				pts.append(lm.chest)
		else:
			pts.append(lm.pos)
		for pod in lm.get("pods", []):
			pts.append(pod)
		for post in lm.get("posts", []):
			pts.append(post)
	return pts.filter(func(p): return not point_reachable(grid, p))

## 地图统计（F1 面板“地图统计”、测试）
static func stats(layout: Dictionary) -> Dictionary:
	var sp: Dictionary = layout.spawn_points
	var normal := 0
	for c in layout.chunks:
		if NORMAL.has(c.type):
			normal += 1
	var patrol_enemies := 0
	for p in sp.patrol:
		patrol_enemies += p.size
	var camp_enemies := 0
	for c in sp.camp:
		camp_enemies += c.size
	return {"chunks": layout.chunks.size(), "normal_chunks": normal, "patrol_groups": sp.patrol.size(), "patrol_enemies": patrol_enemies,
		"camps": sp.camp.size(), "camp_enemies": camp_enemies, "chests": sp.chest.size(), "nodes": sp.node.size(),
		"shrines": layout.shrines.size(), "path_len": layout.path.size() - 1}

# ---------- 有机地形 ----------
static var debug_nofill := false
const TCELL := 64.0
enum { T_OPEN, T_THICKET, T_ROCK, T_CLIFF, T_WATER, T_RUIN, T_ROOT } ## T_ROOT = 层主场地的根柱（挡视线和子弹）
const KIND_NAMES := ["空地", "灌木", "岩石", "断崖", "水", "残垣", "根柱"]
const OPAQUE_LAYER := 16 ## 挡视线、挡子弹的物理层（残垣、灌木、岩石、外圈边界、层主区围墙）

static func blocks_sight(kind: int) -> bool:
	return kind != T_WATER and kind != T_CLIFF

## 点 p 离灌木格 ≤ px（树丛潜行：敌人视野 ×0.7）
static func near_thicket(L: Dictionary, p: Vector2, px := 64.0) -> bool:
	var T: Dictionary = L.terrain
	var cs: float = T.cell
	var x0 := int((p.x - px) / cs); var x1 := int((p.x + px) / cs)
	var y0 := int((p.y - px) / cs); var y1 := int((p.y + px) / cs)
	for y in range(maxi(0, y0), mini(T.ny - 1, y1) + 1):
		for x in range(maxi(0, x0), mini(T.nx - 1, x1) + 1):
			if T.cells[y * T.nx + x] == T_THICKET:
				var r := Rect2(x * cs, y * cs, cs, cs)
				var q := p.clamp(r.position, r.end)
				if q.distance_to(p) <= px:
					return true
	return false

static func _noise(rng: RandomNumberGenerator, freq: float, oct := 3) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = rng.randi()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = freq
	n.fractal_octaves = oct
	return n

static func _terrain(rng: RandomNumberGenerator, L: Dictionary, fd: FloorData) -> Dictionary:
	var cp: float = L.chunk_px
	var nx := int(L.grid_w * cp / TCELL)
	var ny := int(L.grid_h * cp / TCELL)
	var n_den := _noise(rng, 1.0 / 900.0)
	var n_bio := _noise(rng, 1.0 / 2600.0, 2)
	var n_wat := _noise(rng, 1.0 / 1500.0, 2)
	var n_cli := _noise(rng, 1.0 / 1100.0, 2)
	var n_wid := _noise(rng, 1.0 / 700.0, 1)
	# 生态（§8.1）：群系偏移和地形阈值都只从 FloorData.ecology 读
	var bias := fd.eco_f("biome_bias", 0.0)
	var den_base := fd.eco_f("density_base", 0.53)
	var water_th := fd.eco_f("water_th", 0.32)
	var cliff_th := fd.eco_f("cliff_th", 0.25)
	var g := PackedByteArray(); g.resize(nx * ny)
	var biome := PackedFloat32Array(); biome.resize(nx * ny)
	for y in ny:
		for x in nx:
			var px := (x + 0.5) * TCELL
			var py := (y + 0.5) * TCELL
			var i := y * nx + x
			biome[i] = n_bio.get_noise_2d(px, py) + bias
			var dens := den_base + 0.2 * n_den.get_noise_2d(px, py)
			g[i] = 1 if rng.randf() < dens else 0
	# 元胞自动机 4-5 规则（3 轮），地图外算实心；用带 1 格实心外框的数组 + 行累加加速
	var px_w := nx + 2
	for it in 3:
		var pad := PackedInt32Array(); pad.resize(px_w * (ny + 2)); pad.fill(1)
		for y in ny:
			for x in nx:
				pad[(y + 1) * px_w + x + 1] = g[y * nx + x]
		var hs := PackedInt32Array(); hs.resize(px_w * (ny + 2))
		for y in ny + 2:
			var row := y * px_w
			for x in range(1, nx + 1):
				hs[row + x] = pad[row + x - 1] + pad[row + x] + pad[row + x + 1]
		for y in ny:
			var r0 := y * px_w
			for x in nx:
				var cnt := hs[r0 + x + 1] + hs[r0 + px_w + x + 1] + hs[r0 + 2 * px_w + x + 1]
				g[y * nx + x] = 1 if cnt >= 5 else 0
	# 废墟群系：散落的断墙段（1 格厚）
	for t in int(nx * ny / 90):
		var x := rng.randi_range(1, nx - 2)
		var y := rng.randi_range(1, ny - 2)
		if biome[y * nx + x] <= 0.18:
			continue
		var horiz := rng.randf() < 0.5
		var seg_n := rng.randi_range(2, 3) ## 直线墙段 ≤ 3 格（规格 1.5-4）
		for k in seg_n:
			var xx := x + (k if horiz else 0)
			var yy := y + (0 if horiz else k)
			if xx < nx and yy < ny:
				g[yy * nx + xx] = 2 ## 临时标记：残垣
	var circles: Array = [] ## 先收集要挖空的圆，最后统一挖（lambda 捕获的 PackedByteArray 是副本）
	var carve := func(c: Vector2, r: float) -> void: circles.append([c, r])
	# 区块中心空地（大小不一的开阔地）
	var gcell: Vector2i = L.chunks[L.guard_chunk].cell
	var grc := chunk_rect_cell(gcell, cp)
	for ch in L.chunks:
		var c := chunk_rect(ch, cp).get_center()
		var r := rng.randf_range(170.0, 300.0)
		match ch.type:
			"start", "camp": r = 320.0
			"shrine": r = 260.0
			"guard": r = 0.0
		if r > 0:
			for k in 3: ## 三个错位圆拼成不规则空地
				carve.call(c + Vector2(rng.randf_range(-90, 90), rng.randf_range(-90, 90)), r * rng.randf_range(0.7, 1.0))
	# 沿打通边挖蜿蜒小路：中心 → 共享边上的开口点 → 中心，路线被横向噪声推歪，宽度随噪声 80~190px 半径
	for k in L.open:
		var parts: PackedStringArray = k.split("|")
		var a := Vector2i(int(parts[0].split(",")[0]), int(parts[0].split(",")[1]))
		var b := Vector2i(int(parts[1].split(",")[0]), int(parts[1].split(",")[1]))
		var off: float = L.open[k]
		var touches_guard := a == gcell or b == gcell
		var ra := chunk_rect_cell(a, cp)
		var mid := Vector2(ra.end.x, ra.position.y + off) if b.x > a.x else Vector2(ra.position.x + off, ra.end.y)
		for seg in [[chunk_rect_cell(a, cp).get_center(), mid], [mid, chunk_rect_cell(b, cp).get_center()]]:
			var p0: Vector2 = seg[0]
			var p1: Vector2 = seg[1]
			var nrm := (p1 - p0).normalized().orthogonal()
			var steps := int(p0.distance_to(p1) / 32.0)
			for s in steps + 1:
				var t := float(s) / steps
				var bend := sin(t * PI) * 260.0 * n_wid.get_noise_2d(p0.x + p1.x, p0.y + p1.y + t * 900.0)
				var q := p0.lerp(p1, t) + nrm * bend
				if not touches_guard and grc.grow(220.0).has_point(q):
					q = p0.lerp(p1, t) ## 不让别的小路拐进层主区围墙

				var w := maxf(fd.path_min_r, 125.0 + 45.0 * n_wid.get_noise_2d(q.x, q.y)) ## 半径下限：64px 地形格量化后通道仍 ≥ 目标宽度
				carve.call(q, w)
	# 层主区入口外侧：篝火所在的空地
	var gch: Dictionary = L.chunks[L.guard_chunk]
	for d in gch.open_edges:
		var gp: Rect2 = gch.open_edges[d]
		for t in 8:
			carve.call(gp.get_center() + Vector2(d) * (40.0 * t), 190.0)
	for cr in circles:
		var c: Vector2 = cr[0]
		var r: float = cr[1]
		var x0 := int((c.x - r) / TCELL); var x1 := int((c.x + r) / TCELL)
		var y0 := int((c.y - r) / TCELL); var y1 := int((c.y + r) / TCELL)
		for yy in range(maxi(0, y0), mini(ny - 1, y1) + 1):
			for xx in range(maxi(0, x0), mini(nx - 1, x1) + 1):
				if Vector2((xx + 0.5) * TCELL, (yy + 0.5) * TCELL).distance_squared_to(c) <= r * r:
					g[yy * nx + xx] = 0
	# 层主区内部清空（只留几根柱子）
	for yy in range(int(grc.position.y / TCELL), int(grc.end.y / TCELL)):
		for xx in range(int(grc.position.x / TCELL), int(grc.end.x / TCELL)):
			var cc := Vector2((xx + 0.5) * TCELL, (yy + 0.5) * TCELL)
			var lc := (cc - grc.position) / cp
			var pillar := (absf(lc.x - 0.2) < 0.04 or absf(lc.x - 0.8) < 0.04) and (absf(lc.y - 0.2) < 0.04 or absf(lc.y - 0.8) < 0.04)
			g[yy * nx + xx] = 2 if pillar else 0
	# 场地机关“根柱”（§8.3 样例 2）：4 根方柱（覆盖 c±radius 的地形格），做掩体
	var lord := fd.lord()
	var root_pts: Array = []
	if lord and lord.arena_hazard and lord.arena_hazard.id == "root_pillar":
		var offs := [Vector2(0.5, 0.3), Vector2(0.5, 0.7), Vector2(0.3, 0.5), Vector2(0.7, 0.5)]
		for oi in mini(lord.arena_hazard_count, offs.size()):
			var c: Vector2 = grc.position + offs[oi] * cp
			root_pts.append(c)
			var hr := lord.arena_hazard.radius
			for yy in range(int((c.y - hr) / TCELL), int((c.y + hr) / TCELL) + 1):
				for xx in range(int((c.x - hr) / TCELL), int((c.x + hr) / TCELL) + 1):
					g[yy * nx + xx] = 3
	L["root_pillars"] = root_pts
	# 种类：水（低洼）、断崖、灌木（林地）、岩石（野地）、残垣（废墟）
	for i in nx * ny:
		if g[i] == 0:
			continue
		var px := (i % nx + 0.5) * TCELL
		var py := (i / nx + 0.5) * TCELL
		if g[i] == 3:
			g[i] = T_ROOT
		elif g[i] == 2:
			g[i] = T_RUIN
		elif n_wat.get_noise_2d(px, py) > water_th:
			g[i] = T_WATER
		elif biome[i] < -0.12:
			g[i] = T_THICKET
		elif n_cli.get_noise_2d(px, py) > cliff_th:
			g[i] = T_CLIFF
		elif biome[i] > 0.18:
			g[i] = T_RUIN if rng.randf() < 0.3 else T_ROCK
		else:
			g[i] = T_ROCK
	var T := {"nx": nx, "ny": ny, "cell": TCELL, "cells": g, "biome": biome, "tint": fd.ecology.palette if fd.ecology else Color(0, 0, 0, 0), "tint_k": fd.ecology.palette_strength if fd.ecology else 0.0}
	# 修补：区块中心走不到时，从它到相邻的可达区块中心挖一条直路（最多 4 轮）
	var repairs := 0
	var rg := {}
	for rr in 4:
		T.cells = g
		_apply_obstacles(L, T)
		rg = reach_grid(L)
		var bad: Array = L.chunks.filter(func(c): return not point_reachable(rg, chunk_rect(c, cp).get_center()))
		if bad.is_empty():
			break
		for c in bad:
			if c.type == "guard":
				continue
			for d in DIRS:
				var n: Vector2i = c.cell + d
				if n.x < 0 or n.y < 0 or n.x >= L.grid_w or n.y >= L.grid_h or n == gcell:
					continue
				var nc := chunk_rect_cell(n, cp).get_center()
				if point_reachable(rg, nc):
					g = _carve_line(g, nx, ny, chunk_rect(c, cp).get_center(), nc, 150.0)
					repairs += 1
					break
	T["repairs"] = repairs
	# 走不到的空地填实（按真实连通检查：40px 栅格、半径 24），再重建障碍矩形
	var grid := rg
	var filled := 0
	for i in nx * ny:
		if debug_nofill or g[i] != 0:
			continue
		var c0 := Vector2((i % nx) * TCELL, (i / nx) * TCELL)
		if point_reachable(grid, c0 + Vector2(32, 32)):
			continue
		var any := false
		for sy in [4.0, 24.0, 44.0, 60.0]:
			for sx in [4.0, 24.0, 44.0, 60.0]:
				if point_reachable(grid, c0 + Vector2(sx, sy)):
					any = true
		if not any and not grc.has_point(c0 + Vector2(32, 32)):
			g[i] = T_ROCK if biome[i] >= -0.12 else T_THICKET
			filled += 1
	T.cells = g
	T["filled"] = filled
	if filled > 0:
		_apply_obstacles(L, T)
	T["_grid"] = grid ## 填实只动了走不到的格，可达栅格不变，给摆放复用
	return T

## 同种类相邻地形格合并成矩形（行内连续段，向下延伸），按矩形中心归到区块
static func _apply_obstacles(L: Dictionary, T: Dictionary) -> void:
	for ch in L.chunks:
		ch.obstacles = []
		ch.obstacle_kinds = []
	var nx: int = T.nx
	var ny: int = T.ny
	var g: PackedByteArray = T.cells
	var used := PackedByteArray(); used.resize(nx * ny)
	for y in ny:
		var x := 0
		while x < nx:
			var k := g[y * nx + x]
			if k == 0 or used[y * nx + x] == 1:
				x += 1
				continue
			var x1 := x
			while x1 + 1 < nx and g[y * nx + x1 + 1] == k and used[y * nx + x1 + 1] == 0:
				x1 += 1
			var y1 := y
			while y1 + 1 < ny:
				var okrow := true
				for xx in range(x, x1 + 1):
					if g[(y1 + 1) * nx + xx] != k or used[(y1 + 1) * nx + xx] == 1:
						okrow = false
						break
				if not okrow:
					break
				y1 += 1
			for yy in range(y, y1 + 1):
				for xx in range(x, x1 + 1):
					used[yy * nx + xx] = 1
			var r := Rect2(x * TCELL, y * TCELL, (x1 - x + 1) * TCELL, (y1 - y + 1) * TCELL)
			var cid := chunk_at(L, r.get_center())
			L.chunks[cid].obstacles.append(r)
			L.chunks[cid].obstacle_kinds.append(k)
			x = x1 + 1

static func biome_at(T: Dictionary, p: Vector2) -> float:
	var x := clampi(int(p.x / T.cell), 0, T.nx - 1)
	var y := clampi(int(p.y / T.cell), 0, T.ny - 1)
	return T.biome[y * T.nx + x]

const HAZARD_ROUTE_DIST := 150.0 ## 机关离巡逻路线点（§8.1）
const KIND_COLORS := [Color(0, 0, 0, 0), Color(0.22, 0.4, 0.18), Color(0.5, 0.48, 0.44), Color(0.36, 0.34, 0.31), Color(0.2, 0.4, 0.46), Color(0.55, 0.48, 0.4), Color(0.48, 0.34, 0.2)]
const GROUND_WOOD := Color(0.3, 0.42, 0.22)
const GROUND_WILD := Color(0.52, 0.46, 0.26)
const GROUND_RUIN := Color(0.5, 0.47, 0.42)

## 地面颜色：群系值连续混合（林地 ↔ 野地 ↔ 废墟），没有区块边界
static func ground_color(bv: float) -> Color:
	if bv < 0.03:
		return GROUND_WOOD.lerp(GROUND_WILD, smoothstep(-0.3, 0.03, bv))
	return GROUND_WILD.lerp(GROUND_RUIN, smoothstep(0.03, 0.33, bv))

## 地面 + 障碍图（每地形格 1 像素；显示时放大 TCELL 倍、线性过滤，边缘自然柔和）
static func terrain_images(L: Dictionary) -> Array:
	var T: Dictionary = L.terrain
	var ground := Image.create(T.nx, T.ny, false, Image.FORMAT_RGBA8)
	var obs := Image.create(T.nx, T.ny, false, Image.FORMAT_RGBA8)
	for y in T.ny:
		for x in T.nx:
			var i: int = y * T.nx + x
			ground.set_pixel(x, y, ground_color(T.biome[i]).lerp(T.get("tint", Color.BLACK), T.get("tint_k", 0.0)))
			var k: int = T.cells[i]
			obs.set_pixel(x, y, KIND_COLORS[k] if k != 0 else Color(ground_color(T.biome[i]), 0.0))
	return [ground, obs]

static func _carve_line(g: PackedByteArray, nx: int, ny: int, a: Vector2, b: Vector2, r: float) -> PackedByteArray:
	var steps := int(a.distance_to(b) / 32.0) + 1
	for s in steps + 1:
		var c := a.lerp(b, float(s) / steps)
		for yy in range(maxi(0, int((c.y - r) / TCELL)), mini(ny - 1, int((c.y + r) / TCELL)) + 1):
			for xx in range(maxi(0, int((c.x - r) / TCELL)), mini(nx - 1, int((c.x + r) / TCELL)) + 1):
				if Vector2((xx + 0.5) * TCELL, (yy + 0.5) * TCELL).distance_squared_to(c) <= r * r:
					g[yy * nx + xx] = 0
	return g

# ---------- 地标（第 1 层；空列表的层不会进这里） ----------
static func _want_landmark(rng: RandomNumberGenerator, lm: LandmarkData, first_run: bool) -> bool:
	if lm.guarantee_first_run and first_run:
		return true
	if lm.probability >= 0.999:
		return true
	return rng.randf() < lm.probability

static func _must_place(lm: LandmarkData, first_run: bool) -> bool:
	if lm.guarantee_first_run and first_run:
		return true
	return lm.required

static func _place_landmarks(rng: RandomNumberGenerator, L: Dictionary, fd: FloorData, grid: Dictionary, first_run: bool) -> bool:
	var placed: Array = []
	L["landmarks"] = placed
	var bars: Array = []
	var poly := _path_poly(L)
	var road: Vector2 = L.guard_pos - L.start_pos
	var vertical_bar := absf(road.x) >= absf(road.y)
	for lm in fd.landmarks:
		if not _want_landmark(rng, lm, first_run):
			continue
		var spot := {}
		match lm.id:
			"lm_crater":
				spot = _spot_crater(lm, L)
			"lm_first_fight":
				spot = _spot_first_fight(L, grid, poly, lm, placed)
			"lm_spring":
				spot = _spot_spring(L, grid, lm, placed)
			"lm_fallen_tree":
				spot = _spot_tree(L, lm, placed, bars, vertical_bar, poly)
			"lm_fairy_ring":
				spot = _spot_fairy(L, lm, placed, bars)
			"lm_epitaph":
				spot = _spot_epitaph(L, grid, poly, lm, placed, bars)
		if spot.is_empty():
			if _must_place(lm, first_run):
				return false
			continue
		placed.append(spot)
	return true

static func _lm_pack(lm: LandmarkData, pos: Vector2, relaxed: bool) -> Dictionary:
	return {"id": lm.id, "name": lm.display_name, "pos": pos, "radius": lm.radius, "min_patrol": lm.min_patrol,
		"light": lm.light_radius, "sight_cut": lm.sight_confirm_cut, "interact": lm.interact_sec, "relaxed": relaxed, "placed": true}

static func _spot_crater(lm: LandmarkData, L: Dictionary) -> Dictionary:
	return _lm_pack(lm, L.start_pos, false)

static func _spot_first_fight(L: Dictionary, grid: Dictionary, poly: Array, lm: LandmarkData, placed: Array) -> Dictionary:
	var solids := all_solids(L)
	for relax in [false, true]:
		var hi: float = lm.band_max if not relax else lm.band_max + 400.0
		var d: float = lm.band_min
		while d <= hi:
			var sample := _poly_sample(poly, d)
			var road := _road_at(grid, solids, sample, 320.0)
			if not is_inf(road.x) and road.distance_to(L.start_pos) >= lm.min_start and (relax or road.distance_to(L.start_pos) <= lm.band_max + 1.0) and _lm_ok(road, lm, L, placed):
				var pack := _lm_pack(lm, road, relax)
				var posts: Array = []
				for s in [1.0, -1.0]:
					var q: Vector2 = road + sample.perp * 36.0 * s
					posts.append(q if point_reachable(grid, q) and is_free(q, solids, 8.0) else road)
				pack["posts"] = posts
				return pack
			d += 40.0
	return {}

static func _spot_spring(L: Dictionary, grid: Dictionary, lm: LandmarkData, placed: Array) -> Dictionary:
	var solids := all_solids(L)
	for relax in [false, true]:
		var p := _scan_free(L, grid, solids, _spring_chunks(L, lm, relax), lm, placed)
		if not is_inf(p.x):
			return _lm_pack(lm, p, relax)
	return {}

static func _spring_chunks(L: Dictionary, lm: LandmarkData, relax: bool) -> Array:
	var ids: Array = []
	var near: int = lm.near_path if not relax else lm.near_path + 1
	var c0: int = lm.column_min - 1 if not relax else maxi(0, lm.column_min - 2)
	var c1: int = lm.column_max - 1 if not relax else mini(int(L.grid_w) - 1, lm.column_max)
	for ch in L.chunks:
		var cell: Vector2i = ch.cell
		if cell.x < c0 or cell.x > c1 or not _near_path(L, cell, near):
			continue
		ids.append(ch.id)
	ids.sort()
	return ids

static func _scan_free(L: Dictionary, grid: Dictionary, solids: Array, ids: Array, lm: LandmarkData, placed: Array) -> Vector2:
	for id in ids:
		var rc: Rect2 = chunk_rect(L.chunks[id], L.chunk_px).grow(-64)
		if rc.size.x < 32.0 or rc.size.y < 32.0:
			continue
		var y := rc.position.y
		while y <= rc.end.y:
			var x := rc.position.x
			while x <= rc.end.x:
				var p := Vector2(x, y)
				if point_reachable(grid, p) and is_free(p, solids, 28.0) and _lm_ok(p, lm, L, placed):
					return p
				x += 64.0
			y += 64.0
	return Vector2(INF, INF)

static func _spot_tree(L: Dictionary, lm: LandmarkData, placed: Array, bars: Array, vertical: bool, poly: Array) -> Dictionary:
	var bar := _orient(lm.bar_w, lm.bar_h, vertical)
	var foot := _orient(lm.footprint_w, lm.footprint_h, vertical)
	var tries := 0
	for relax in [false, true]:
		for id in _tree_chunks(L, relax):
			var ch: Dictionary = L.chunks[id]
			var rc: Rect2 = chunk_rect(ch, L.chunk_px).grow(-36)
			var center: Vector2 = chunk_rect(ch, L.chunk_px).get_center()
			if rc.size.x < bar.x or rc.size.y < bar.y:
				continue
			for off in [Vector2(300, 280), Vector2(-300, 280), Vector2(300, -280), Vector2(-300, -280), Vector2(360, 0), Vector2(-360, 0), Vector2(0, 360), Vector2(0, -360)]:
				var c: Vector2 = center + off
				c.x = clampf(c.x, rc.position.x + bar.x * 0.5, rc.end.x - bar.x * 0.5)
				c.y = clampf(c.y, rc.position.y + bar.y * 0.5, rc.end.y - bar.y * 0.5)
				var rect := Rect2(c - bar * 0.5, bar)
				if rect.grow(30).has_point(center) or not _lm_ok(c, lm, L, placed) or _hits_poly(rect, poly, 80.0):
					continue
				tries += 1
				if tries > 8:
					return {}
				ch.obstacles.append(rect)
				ch.obstacle_kinds.append(T_ROCK)
				var chest := _outside_rect(rect, center)
				bars.append(rect)
				var pack := _lm_pack(lm, c, relax)
				pack["bar"] = rect
				pack["block_rect"] = Rect2(c - foot * 0.5, foot)
				pack["chest"] = chest
				var side := Vector2(-off.y, off.x)
				if side.length() < 1.0:
					side = Vector2.RIGHT
				side = side.normalized()
				pack["bushes"] = [c + side * 70.0, c - side * 70.0]
				return pack
	return {}

static func _tree_chunks(L: Dictionary, relax: bool) -> Array:
	var ids: Array = []
	var x_max := int(L.grid_w) - 4 if not relax else int(L.grid_w) - 3
	for ch in L.chunks:
		if not NORMAL.has(ch.type) or L.path.has(ch.id) or ch.cell.x > x_max:
			continue
		ids.append(ch.id)
	ids.sort()
	return ids

static func _spot_fairy(L: Dictionary, lm: LandmarkData, placed: Array, bars: Array) -> Dictionary:
	var found := {}
	var relaxed := false
	for relax in [false, true]:
		found = _best_fairy_point(L, _fairy_chunks(L, lm, relax), lm, placed)
		if not found.is_empty():
			relaxed = relax
			break
	if found.is_empty():
		return {}
	var pos: Vector2 = found.pos
	var cid: int = found.chunk
	_carve_disk(L, pos, lm.radius)
	var cells: PackedByteArray = _carve_line(L.terrain.cells, L.terrain.nx, L.terrain.ny, pos, chunk_rect(L.chunks[cid], L.chunk_px).get_center(), 130.0)
	L.terrain.cells = cells
	_commit_bars(L, bars)
	var solids := all_solids(L)
	if not is_free(pos, solids, 8.0):
		return {}
	var pods: Array = []
	for i in 4:
		var pod := pos + Vector2.from_angle(PI * 0.25 + float(i) * PI * 0.5) * 200.0
		while pod.distance_to(pos) > 24.0 and not is_free(pod, solids, 6.0):
			pod = pod.move_toward(pos, 24.0)
		pods.append(pod)
	var pack := _lm_pack(lm, pos, relaxed)
	pack["pods"] = pods
	return pack

static func _fairy_chunks(L: Dictionary, lm: LandmarkData, relax: bool) -> Array:
	var col := int(L.grid_w) - 2
	var ids: Array = []
	for ch in L.chunks:
		var cell: Vector2i = ch.cell
		if cell == L.chunks[L.guard_chunk].cell:
			continue
		var col_ok: bool = cell.x == col if not relax else (cell.x == col or cell.x == col - 1)
		if not col_ok:
			continue
		var near: int = lm.near_path if not relax else lm.near_path + 1
		if near > 0 and not _near_path(L, cell, near):
			continue
		ids.append(ch.id)
	ids.sort()
	return ids

static func _best_fairy_point(L: Dictionary, ids: Array, lm: LandmarkData, placed: Array) -> Dictionary:
	var best := {}
	var best_d := 1e9
	for id in ids:
		var rc: Rect2 = chunk_rect(L.chunks[id], L.chunk_px).grow(-48)
		var center: Vector2 = chunk_rect(L.chunks[id], L.chunk_px).get_center()
		var y := rc.position.y
		while y <= rc.end.y:
			var x := rc.position.x
			while x <= rc.end.x:
				var p := Vector2(x, y)
				if _lm_ok(p, lm, L, placed):
					var d := p.distance_to(center)
					if d < best_d:
						best_d = d
						best = {"pos": p, "chunk": id}
				x += 48.0
			y += 48.0
	return best

static func _spot_epitaph(L: Dictionary, grid: Dictionary, poly: Array, lm: LandmarkData, placed: Array, bars: Array) -> Dictionary:
	var solids := all_solids(L)
	var length := _poly_len(poly)
	var free_hit := {}
	var raw_hit := {}
	var free_relax := {}
	var raw_relax := {}
	for relax in [false, true]:
		var lo: float = (lm.band_min if not relax else maxf(0.2, lm.band_min - 0.1)) * length
		var hi: float = (lm.band_max if not relax else minf(0.8, lm.band_max + 0.12)) * length
		var omin: float = lm.offset_min if not relax else maxf(40.0, lm.offset_min - 40.0)
		var omax: float = lm.offset_max if not relax else lm.offset_max + 120.0
		var d: float = lo
		while d <= hi:
			var sample := _poly_sample(poly, d)
			var road := _road_at(grid, solids, sample, 320.0)
			if not is_inf(road.x):
				var off: float = omin
				while off <= omax + 0.1:
					for sign in [1.0, -1.0]:
						var p: Vector2 = road + sample.perp * sign * off
						if not _lm_ok(p, lm, L, placed):
							continue
						var free := point_reachable(grid, p) and is_free(p, solids, 12.0)
						var info := {"pos": p, "road": road}
						if not relax:
							if free and free_hit.is_empty():
								free_hit = info
							elif raw_hit.is_empty():
								raw_hit = info
						elif free and free_relax.is_empty():
							free_relax = info
						elif raw_relax.is_empty():
							raw_relax = info
					if not free_hit.is_empty():
						break
					off += 40.0
			if not free_hit.is_empty():
				break
			d += 64.0
		if not free_hit.is_empty():
			break
	var chosen: Dictionary = free_hit if not free_hit.is_empty() else (raw_hit if not raw_hit.is_empty() else (free_relax if not free_relax.is_empty() else raw_relax))
	if chosen.is_empty():
		return {}
	var pos: Vector2 = chosen.pos
	if not (point_reachable(grid, pos) and is_free(pos, all_solids(L), 12.0)):
		_carve_disk(L, pos, 72.0)
		var cells: PackedByteArray = _carve_line(L.terrain.cells, L.terrain.nx, L.terrain.ny, pos, chosen.road, 56.0)
		L.terrain.cells = cells
		_commit_bars(L, bars)
	return _lm_pack(lm, pos, free_hit.is_empty() and raw_hit.is_empty())

static func _chunks_blocked(L: Dictionary, grid: Dictionary) -> bool:
	for c in L.chunks:
		if not point_reachable(grid, chunk_rect(c, L.chunk_px).get_center()):
			return true
	return false

## 倒伏巨树挡路时拿掉。碰撞条中心不必走到，宝箱要走到。
static func _remove_tree(L: Dictionary) -> bool:
	var idx := -1
	for i in L.landmarks.size():
		if L.landmarks[i].id == "lm_fallen_tree":
			idx = i
			break
	if idx < 0:
		return false
	var rect: Rect2 = L.landmarks[idx].bar
	L.landmarks.remove_at(idx)
	var cid := chunk_at(L, rect.get_center())
	if cid >= 0:
		var ch: Dictionary = L.chunks[cid]
		for j in range(ch.obstacles.size() - 1, -1, -1):
			if ch.obstacles[j] == rect:
				ch.obstacles.remove_at(j)
				ch.obstacle_kinds.remove_at(j)
				break
	return true

static func _nudge_pods(L: Dictionary, grid: Dictionary) -> void:
	for lm in L.landmarks:
		if not lm.has("pods"):
			continue
		var pos: Vector2 = lm.pos
		var pods: Array = lm.pods
		for i in pods.size():
			var pod: Vector2 = pods[i]
			var steps := 0
			while not point_reachable(grid, pod) and pod.distance_to(pos) > 48.0 and steps < 8:
				pod = pod.move_toward(pos, 16.0)
				steps += 1
			pods[i] = pod

static func _anchors_ok(L: Dictionary, grid: Dictionary) -> bool:
	if _chunks_blocked(L, grid):
		return false
	for lm in L.landmarks:
		var pts: Array = []
		if lm.has("bar"):
			if lm.has("chest"):
				pts.append(lm.chest)
		else:
			pts.append(lm.pos)
		for p in lm.get("pods", []):
			pts.append(p)
		for p in lm.get("posts", []):
			pts.append(p)
		for p in pts:
			if not point_reachable(grid, p):
				if lm.has("bar") and _remove_tree(L):
					return _anchors_ok(L, reach_grid(L))
				return false
	return true

static func _lm_ok(p: Vector2, lm: LandmarkData, L: Dictionary, placed: Array) -> bool:
	if not (L.bounds as Rect2).grow(-48).has_point(p):
		return false
	if lm.min_start > 0.0 and p.distance_to(L.start_pos) < lm.min_start:
		return false
	if lm.min_campfire > 0.0 and p.distance_to(L.campfire_pos) < lm.min_campfire:
		return false
	if lm.min_camp > 0.0:
		for k in L.camps:
			if p.distance_to(chunk_rect(L.chunks[k], L.chunk_px).get_center()) < lm.min_camp:
				return false
	if lm.min_entrance > 0.0:
		for en in L.guard_entrances:
			if p.distance_to((en.gap as Rect2).get_center()) < lm.min_entrance:
				return false
	if lm.min_guard_wall > 0.0:
		for w in L.chunks[L.guard_chunk].walls:
			if dist_to_rect(p, w) < lm.min_guard_wall:
				return false
	if lm.min_landmark > 0.0:
		for o in placed:
			if p.distance_to(o.pos) < lm.min_landmark:
				return false
	for o in placed:
		if _lm_overlap(p, lm, o):
			return false
	return true

static func _lm_overlap(p: Vector2, lm: LandmarkData, o: Dictionary) -> bool:
	var reach: float = lm.radius
	if lm.footprint_w > 0.0:
		reach = maxf(reach, maxf(lm.footprint_w, lm.footprint_h) * 0.5)
	if o.has("block_rect") and (o.block_rect as Rect2).grow(reach).has_point(p):
		return true
	var rad := float(o.get("radius", 0.0))
	return rad > 0.0 and p.distance_to(o.pos) < rad + reach

static func dist_to_rect(p: Vector2, r: Rect2) -> float:
	var q := Vector2(clampf(p.x, r.position.x, r.end.x), clampf(p.y, r.position.y, r.end.y))
	return p.distance_to(q)

static func _path_poly(L: Dictionary) -> Array:
	var out: Array = []
	for id in L.path:
		out.append(chunk_rect(L.chunks[id], L.chunk_px).get_center())
	return out

static func _poly_len(poly: Array) -> float:
	var n := 0.0
	for i in range(1, poly.size()):
		n += (poly[i - 1] as Vector2).distance_to(poly[i])
	return n

static func _poly_sample(poly: Array, dist: float) -> Dictionary:
	var acc := 0.0
	for i in range(1, poly.size()):
		var a: Vector2 = poly[i - 1]
		var b: Vector2 = poly[i]
		var seg := a.distance_to(b)
		if seg < 0.001:
			continue
		if acc + seg >= dist or i == poly.size() - 1:
			var dir := (b - a).normalized()
			return {"pos": a.lerp(b, clampf((dist - acc) / seg, 0.0, 1.0)), "perp": Vector2(-dir.y, dir.x)}
		acc += seg
	return {"pos": poly[-1], "perp": Vector2.UP}

static func _road_at(grid: Dictionary, solids: Array, sample: Dictionary, max_off: float) -> Vector2:
	var best := Vector2(INF, INF)
	var best_d := 1e9
	var off := -max_off
	while off <= max_off + 0.1:
		var p: Vector2 = sample.pos + sample.perp * off
		if point_reachable(grid, p) and is_free(p, solids, 24.0) and absf(off) < best_d:
			best = p
			best_d = absf(off)
		off += 32.0
	return best

static func _near_path(L: Dictionary, cell: Vector2i, n: int) -> bool:
	if n <= 0:
		return true
	for id in L.path:
		if cheb(L.chunks[id].cell, cell) <= n:
			return true
	return false

static func _orient(long_side: float, short_side: float, vertical: bool) -> Vector2:
	return Vector2(short_side, long_side) if vertical else Vector2(long_side, short_side)

static func _hits_poly(rect: Rect2, poly: Array, margin: float) -> bool:
	var g := rect.grow(margin)
	for i in range(1, poly.size()):
		var a: Vector2 = poly[i - 1]
		var b: Vector2 = poly[i]
		var steps := int(a.distance_to(b) / 40.0) + 1
		for s in steps + 1:
			if g.has_point(a.lerp(b, float(s) / float(steps))):
				return true
	return false

static func _outside_rect(rect: Rect2, toward: Vector2) -> Vector2:
	var c := rect.get_center()
	var dir := (toward - c).normalized()
	if dir.length() < 0.01:
		dir = Vector2.DOWN
	var p := c
	for i in 24:
		p += dir * 20.0
		if not rect.grow(16).has_point(p):
			return p
	return p

static func _carve_disk(L: Dictionary, center: Vector2, radius: float) -> void:
	var T: Dictionary = L.terrain
	var g: PackedByteArray = T.cells
	var nx: int = T.nx
	var ny: int = T.ny
	var r2 := radius * radius
	var guard: Rect2 = chunk_rect(L.chunks[L.guard_chunk], L.chunk_px).grow(4)
	var x0 := maxi(0, int((center.x - radius) / TCELL))
	var x1 := mini(nx - 1, int((center.x + radius) / TCELL))
	var y0 := maxi(0, int((center.y - radius) / TCELL))
	var y1 := mini(ny - 1, int((center.y + radius) / TCELL))
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var c := Vector2((x + 0.5) * TCELL, (y + 0.5) * TCELL)
			if c.distance_squared_to(center) > r2 or guard.has_point(c):
				continue
			g[y * nx + x] = T_OPEN
	T.cells = g

static func _commit_bars(L: Dictionary, bars: Array) -> void:
	_apply_obstacles(L, L.terrain)
	for rect in bars:
		var cid := chunk_at(L, rect.get_center())
		if cid < 0:
			continue
		L.chunks[cid].obstacles.append(rect)
		L.chunks[cid].obstacle_kinds.append(T_ROCK)

static func _landmark_blocks(L: Dictionary, p: Vector2) -> bool:
	for lm in L.get("landmarks", []):
		var mp := float(lm.get("min_patrol", 0.0))
		if mp > 0.0 and p.distance_to(lm.pos) < mp:
			return true
		if lm.has("block_rect") and (lm.block_rect as Rect2).has_point(p):
			return true
		var rad := float(lm.get("radius", 0.0))
		if rad > 0.0 and p.distance_to(lm.pos) < rad:
			return true
	return false
