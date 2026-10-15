class_name FloorGen
extends RefCounted
## 楼层生成：手工房间模板拼成主路（入口 → 战斗 ×3~4 → 篝火 → 层守），再挂 0~2 个支路（宝箱/强化）。
## 房间放在网格上，主路只向右/上/下走（不会自交），门开在共享墙的正中。
## 模板障碍物只放在四个象限里，房间中间的十字通道永远畅通 → 不会有死路/卡墙。

const ROOM := Vector2(1280, 800)
const WALL := 40.0
const DOOR := 200.0
const DIRS := [Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0)]

## 模板：障碍物用房间内 0..1 的归一化矩形；十字带 x∈[0.38,0.62] 或 y∈[0.36,0.64] 不许放
const TEMPLATES := {
	"entrance": [[]],
	"combat": [
		[[0.15, 0.15, 0.12, 0.12], [0.73, 0.15, 0.12, 0.12], [0.15, 0.73, 0.12, 0.12], [0.73, 0.73, 0.12, 0.12]],
		[[0.1, 0.12, 0.22, 0.08], [0.68, 0.8, 0.22, 0.08]],
		[[0.2, 0.2, 0.08, 0.14], [0.72, 0.66, 0.08, 0.14], [0.08, 0.7, 0.14, 0.1]],
	],
	"campfire": [[], [[0.12, 0.12, 0.1, 0.1], [0.78, 0.78, 0.1, 0.1]]],
	"guard": [[], [[0.1, 0.1, 0.08, 0.08], [0.82, 0.1, 0.08, 0.08], [0.1, 0.82, 0.08, 0.08], [0.82, 0.82, 0.08, 0.08]]],
	"chest": [[[0.2, 0.15, 0.1, 0.15]], [[0.7, 0.7, 0.15, 0.1]]],
	"boon": [[]],
}

static func generate(seed: int, depth: int, fd: FloorData) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed, depth])
	var types: Array = ["entrance"]
	for i in rng.randi_range(fd.combat_rooms_min, fd.combat_rooms_max):
		types.append("combat")
	types += ["campfire", "guard"]
	var rooms: Array = []
	var used := {}
	var cell := Vector2i.ZERO
	for i in types.size():
		if i > 0:
			var opts: Array = []
			for d in [Vector2i(1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
				if not used.has(cell + d):
					opts.append(d)
			cell += opts[rng.randi_range(0, opts.size() - 1)]
		used[cell] = rooms.size()
		rooms.append(_room(rooms.size(), types[i], cell, rng, true))
	for i in range(1, rooms.size()):
		_link(rooms[i - 1], rooms[i])
	var n_side := rng.randi_range(fd.side_rooms_min, fd.side_rooms_max)
	var combat_ids: Array = rooms.filter(func(r): return r.type == "combat").map(func(r): return r.id)
	var tries := 0
	while n_side > 0 and tries < 40:
		tries += 1
		var host: Dictionary = rooms[combat_ids[rng.randi_range(0, combat_ids.size() - 1)]]
		var d: Vector2i = DIRS[rng.randi_range(0, 3)]
		var c: Vector2i = host.cell + d
		if used.has(c):
			continue
		var t := "boon" if rng.randf() < fd.side_boon_chance else "chest"
		var r := _room(rooms.size(), t, c, rng, false)
		used[c] = r.id
		rooms.append(r)
		_link(host, r)
		n_side -= 1
	return {"seed": seed, "depth": depth, "rooms": rooms, "entrance": 0, "guard": types.size() - 1,
		"main": range(types.size()), "first_combat": combat_ids[0], "last_combat": combat_ids[-1]}

static func _room(id: int, type: String, cell: Vector2i, rng: RandomNumberGenerator, main: bool) -> Dictionary:
	var ts: Array = TEMPLATES[type]
	var ti := rng.randi_range(0, ts.size() - 1)
	return {"id": id, "type": type, "cell": cell, "template": ti, "obstacles": ts[ti], "doors": {}, "main": main}

static func _link(a: Dictionary, b: Dictionary) -> void:
	var d: Vector2i = b.cell - a.cell
	a.doors[d] = b.id
	b.doors[-d] = a.id

static func room_rect(r: Dictionary) -> Rect2:
	return Rect2(Vector2(r.cell) * ROOM, ROOM)

static func room_center(r: Dictionary) -> Vector2:
	return room_rect(r).get_center()

## 房间的墙体（世界坐标矩形），门口留空；返回 {walls:[Rect2], doors:{dir: Rect2}}
static func room_walls(r: Dictionary) -> Dictionary:
	var rc := room_rect(r)
	var walls: Array = []
	var doors := {}
	for d in DIRS:
		var horizontal: bool = d.y != 0
		var side: Rect2
		if d == Vector2i(1, 0): side = Rect2(rc.end.x - WALL / 2, rc.position.y - WALL / 2, WALL, rc.size.y + WALL)
		elif d == Vector2i(-1, 0): side = Rect2(rc.position.x - WALL / 2, rc.position.y - WALL / 2, WALL, rc.size.y + WALL)
		elif d == Vector2i(0, -1): side = Rect2(rc.position.x - WALL / 2, rc.position.y - WALL / 2, rc.size.x + WALL, WALL)
		else: side = Rect2(rc.position.x - WALL / 2, rc.end.y - WALL / 2, rc.size.x + WALL, WALL)
		if r.doors.has(d):
			var gap: Rect2
			if horizontal:
				var cx := rc.get_center().x
				walls.append(Rect2(side.position, Vector2(cx - DOOR / 2 - side.position.x, WALL)))
				walls.append(Rect2(Vector2(cx + DOOR / 2, side.position.y), Vector2(side.end.x - cx - DOOR / 2, WALL)))
				gap = Rect2(Vector2(cx - DOOR / 2, side.position.y), Vector2(DOOR, WALL))
			else:
				var cy := rc.get_center().y
				walls.append(Rect2(side.position, Vector2(WALL, cy - DOOR / 2 - side.position.y)))
				walls.append(Rect2(Vector2(side.position.x, cy + DOOR / 2), Vector2(WALL, side.end.y - cy - DOOR / 2)))
				gap = Rect2(Vector2(side.position.x, cy - DOOR / 2), Vector2(WALL, DOOR))
			doors[d] = gap
		else:
			walls.append(side)
	return {"walls": walls, "doors": doors}

static func room_obstacles(r: Dictionary) -> Array:
	var rc := room_rect(r)
	var out: Array = []
	for o in r.obstacles:
		out.append(Rect2(rc.position + Vector2(o[0], o[1]) * ROOM, Vector2(o[2], o[3]) * ROOM))
	return out

## 几何走通检查：40px 栅格，按主角脚底半径膨胀障碍；门全开。返回到不了的房间 id 列表（空 = 全部走通）
static func unreachable_rooms(layout: Dictionary, radius := 22.0) -> Array:
	var cs := 40.0
	var blocked := {}
	var bounds := Rect2()
	var first := true
	var solid: Array = []
	for r in layout.rooms:
		var rc := room_rect(r)
		bounds = rc if first else bounds.merge(rc)
		first = false
		solid += room_walls(r).walls
		solid += room_obstacles(r)
	var open_cell := func(c: Vector2i) -> bool:
		var p := (Vector2(c) + Vector2(0.5, 0.5)) * cs
		for s in solid:
			if s.grow(radius).has_point(p):
				return false
		return bounds.has_point(p)
	var start := Vector2i((room_center(layout.rooms[layout.entrance]) / cs).floor())
	var seen := {start: true}
	var q := [start]
	while not q.is_empty():
		var c: Vector2i = q.pop_back()
		for d in DIRS:
			var n: Vector2i = c + d
			if seen.has(n):
				continue
			if not blocked.has(n):
				blocked[n] = not open_cell.call(n)
			if not blocked[n]:
				seen[n] = true
				q.append(n)
	var bad: Array = []
	for r in layout.rooms:
		if not seen.has(Vector2i((room_center(r) / cs).floor())):
			bad.append(r.id)
	return bad
