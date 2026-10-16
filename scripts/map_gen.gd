class_name MapGen
extends RefCounted
## 开放地图生成（取代房间制 FloorGen）：grid_w × grid_h 个区块拼成一整张打通的平层地图。
## 1. 随机 DFS 生成树保证全连通，再按 loop_chance 给相邻区块额外打通（环路）；层守区只开 1~2 个口。
## 2. 打通的区块边留 gap_px 宽开口（边中段 ±25% 随机），不通的边是矮墙；外圈 map_border_px 实心墙。
## 3. 区块模板：障碍物是区块内 0..1 归一化矩形，只放在四个象限里，十字通道 x∈[0.38,0.62]、y∈[0.36,0.64] 永远畅通。
## 4. 摆放约束：起点在第 0 列、层守区在最后一列；营地距起点 ≥2、两两 ≥2、至少 1 个在最短路径 ±1 区块内；神龛不贴起点。
## 5. 40px 栅格 BFS 走通检查，不满足就换子种子重生（最多重试 5 次）。区块间距离一律按切比雪夫距离（含斜向）算。

const WALL := 40.0
const DIRS := [Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0)]
const NORMAL := ["field", "grove", "ruin"]
const MAX_RETRY := 5
const PATROL_OBS_MARGIN := 90.0 ## 巡逻路线点离障碍/墙 ≥ 60px（取 90，给组员站位留余量）
const SAFE_START_PX := 720.0 ## 巡逻点离主角出生点的最小距离（> 临时追击半径 600，开局不被立刻追）
const LOOT_ROUTE_DIST := 150.0 ## 宝箱/资源点离路线点 ≥ 150px

## 模板：每项 [x, y, w, h]（区块内归一化），共 14 个
const TEMPLATES := {
	"start": [[], [[0.1, 0.1, 0.1, 0.1], [0.8, 0.8, 0.1, 0.1]]],
	"guard": [[], [[0.1, 0.1, 0.08, 0.08], [0.82, 0.1, 0.08, 0.08], [0.1, 0.82, 0.08, 0.08], [0.82, 0.82, 0.08, 0.08]]],
	"camp": [
		[[0.08, 0.08, 0.14, 0.1], [0.78, 0.82, 0.14, 0.1]],
		[[0.1, 0.1, 0.08, 0.18], [0.82, 0.72, 0.08, 0.18], [0.72, 0.1, 0.18, 0.08]],
	],
	"shrine": [[], [[0.15, 0.15, 0.1, 0.1], [0.75, 0.75, 0.1, 0.1]]],
	"field": [
		[[0.15, 0.15, 0.12, 0.12], [0.73, 0.15, 0.12, 0.12], [0.15, 0.73, 0.12, 0.12], [0.73, 0.73, 0.12, 0.12]],
		[[0.1, 0.12, 0.22, 0.08], [0.68, 0.8, 0.22, 0.08]],
	],
	"grove": [
		[[0.2, 0.2, 0.08, 0.14], [0.72, 0.66, 0.08, 0.14], [0.08, 0.7, 0.14, 0.1]],
		[[0.12, 0.12, 0.06, 0.06], [0.24, 0.2, 0.06, 0.06], [0.7, 0.14, 0.06, 0.06], [0.8, 0.24, 0.06, 0.06], [0.14, 0.78, 0.06, 0.06], [0.76, 0.76, 0.08, 0.08]],
	],
	"ruin": [
		[[0.1, 0.1, 0.24, 0.06], [0.1, 0.1, 0.06, 0.22], [0.66, 0.84, 0.24, 0.06], [0.84, 0.68, 0.06, 0.22]],
		[[0.66, 0.1, 0.24, 0.06], [0.84, 0.1, 0.06, 0.22], [0.1, 0.84, 0.24, 0.06], [0.1, 0.68, 0.06, 0.22]],
	],
}

static func generate(seed: int, depth: int, fd: FloorData) -> Dictionary:
	var L := {}
	for attempt in MAX_RETRY + 1:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([seed, depth, "map"]) if attempt == 0 else hash([seed, depth, "map", attempt])
		L = _try(rng, fd)
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

static func _try(rng: RandomNumberGenerator, fd: FloorData) -> Dictionary:
	var W := fd.grid_w
	var H := fd.grid_h
	var cp := fd.chunk_px
	var inside := func(c: Vector2i) -> bool: return c.x >= 0 and c.y >= 0 and c.x < W and c.y < H
	var start := Vector2i(0, rng.randi_range(0, H - 1))
	var gcell := Vector2i(W - 1, rng.randi_range(0, H - 1))
	var open := {} ## edge key -> 开口中心沿边的偏移（px，从边起点量）
	var open_edge := func(a: Vector2i, b: Vector2i) -> void:
		open[_ekey(a, b)] = cp * 0.5 + rng.randf_range(-0.25, 0.25) * cp
	# 1. 生成树（不含层守区），随机 DFS
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
	# 层守区：1~2 个入口
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
			chunks.append({"id": y * W + x, "cell": Vector2i(x, y), "type": "", "template": 0, "obstacles": [], "open_edges": {}, "walls": []})
	var cid := func(c: Vector2i) -> int: return c.y * W + c.x
	var L := {"ok": true, "chunks": chunks, "grid_w": W, "grid_h": H, "chunk_px": cp,
		"start_chunk": cid.call(start), "guard_chunk": cid.call(gcell), "open": open}
	var path := _bfs_path(L, start, gcell)
	L["path"] = path
	if path.size() - 1 < fd.min_start_guard_dist:
		L.ok = false
	# 2. 类型
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
		else: ch.type = NORMAL[rng.randi_range(0, NORMAL.size() - 1)]
		var ts: Array = TEMPLATES[ch.type]
		ch.template = rng.randi_range(0, ts.size() - 1)
		var rc := chunk_rect_cell(c, cp)
		var obs: Array = []
		for o in ts[ch.template]:
			obs.append(Rect2(rc.position + Vector2(o[0], o[1]) * cp, Vector2(o[2], o[3]) * cp))
		ch.obstacles = obs
	L["camps"] = camps.map(func(c): return cid.call(c))
	L["shrine"] = cid.call(shrines[0]) if not shrines.is_empty() else -1
	L["shrines"] = shrines.map(func(c): return cid.call(c))
	# 3. 墙与开口
	for ch in chunks:
		var c: Vector2i = ch.cell
		var rc := chunk_rect_cell(c, cp)
		for d in DIRS:
			var n: Vector2i = c + d
			if not inside.call(n):
				continue
			var k := _ekey(c, n)
			var horizontal: bool = d.y != 0 ## 上下边（墙是横的）
			var side: Rect2
			if d == Vector2i(1, 0): side = Rect2(rc.end.x - WALL / 2, rc.position.y, WALL, cp)
			elif d == Vector2i(-1, 0): side = Rect2(rc.position.x - WALL / 2, rc.position.y, WALL, cp)
			elif d == Vector2i(0, -1): side = Rect2(rc.position.x, rc.position.y - WALL / 2, cp, WALL)
			else: side = Rect2(rc.position.x, rc.end.y - WALL / 2, cp, WALL)
			var own: bool = d == Vector2i(1, 0) or d == Vector2i(0, 1) ## 共享边只由左/上区块持有墙体
			if open.has(k):
				var off: float = open[k]
				var g0 := off - fd.gap_px / 2
				var gap: Rect2
				if horizontal:
					gap = Rect2(side.position + Vector2(g0, 0), Vector2(fd.gap_px, WALL))
					if own:
						ch.walls.append(Rect2(side.position, Vector2(g0, WALL)))
						ch.walls.append(Rect2(Vector2(gap.end.x, side.position.y), Vector2(side.end.x - gap.end.x, WALL)))
				else:
					gap = Rect2(side.position + Vector2(0, g0), Vector2(WALL, fd.gap_px))
					if own:
						ch.walls.append(Rect2(side.position, Vector2(WALL, g0)))
						ch.walls.append(Rect2(Vector2(side.position.x, gap.end.y), Vector2(WALL, side.end.y - gap.end.y)))
				ch.open_edges[d] = gap
			elif own:
				ch.walls.append(side)
	var bounds := Rect2(0, 0, W * cp, H * cp)
	L["bounds"] = bounds
	var b := fd.map_border_px
	L["border"] = [Rect2(-b, -b, bounds.size.x + 2 * b, b), Rect2(-b, bounds.size.y, bounds.size.x + 2 * b, b),
		Rect2(-b, 0, b, bounds.size.y), Rect2(bounds.size.x, 0, b, bounds.size.y)]
	# 4. 层守区、篝火、撤离点
	var gch: Dictionary = chunks[cid.call(gcell)]
	var gc := chunk_rect(gch, cp).get_center()
	var ents: Array = []
	for n in guard_entrances:
		var d: Vector2i = n - gcell
		ents.append({"dir": d, "gap": gch.open_edges[d], "chunk": cid.call(n)})
	L["guard_entrances"] = ents
	var d0 := Vector2(ents[0].dir)
	var solids := all_solids(L)
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
	# 5. 刷怪点、宝箱、资源点
	var spawn := {"patrol": [], "camp": [], "chest": [], "node": []}
	var start_pos := chunk_rect(chunks[L.start_chunk], cp).get_center()
	L["start_pos"] = start_pos
	var routes := {} ## chunk id -> [Vector2]
	for ch in chunks:
		if not NORMAL.has(ch.type) or rng.randf() >= fd.patrol_chance:
			continue
		var rc := chunk_rect(ch, cp).grow(-110)
		var pts: Array = []
		var want := rng.randi_range(2, 4)
		for t in 80:
			if pts.size() >= want:
				break
			var p := Vector2(rng.randf_range(rc.position.x, rc.end.x), rng.randf_range(rc.position.y, rc.end.y))
			if is_free(p, solids, PATROL_OBS_MARGIN) and p.distance_to(start_pos) >= SAFE_START_PX and pts.all(func(q): return q.distance_to(p) >= 160.0):
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
			var p := _loot_point(rng, chunks, loot_chunks, routes, taken, solids, cp)
			taken.append(p)
			spawn[kind].append(p)
	L["spawn_points"] = spawn
	return L

static func _loot_point(rng: RandomNumberGenerator, chunks: Array, loot_chunks: Array, routes: Dictionary, taken: Array, solids: Array, cp: float) -> Vector2:
	var last := Vector2.ZERO
	for t in 120:
		var ch: Dictionary = chunks[loot_chunks[rng.randi_range(0, loot_chunks.size() - 1)]]
		var rc := chunk_rect(ch, cp)
		var corner := Vector2(rng.randi_range(0, 1), rng.randi_range(0, 1))
		var inset := Vector2(rng.randf_range(90, 220), rng.randf_range(90, 220))
		var p := rc.position + corner * rc.size + (Vector2.ONE - corner * 2) * inset
		last = p
		if not is_free(p, solids, 50.0):
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

## 区块级最短路（chunk id 列表，含起点和层守区）
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
