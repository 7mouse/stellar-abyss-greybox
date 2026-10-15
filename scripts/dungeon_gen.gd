class_name DungeonGen
extends RefCounted
## 迷宫层生成：8~10 个节点的分支图（列式 DAG），同种子+层数可复现。

const TYPES := ["combat", "chest", "event", "rest"]
const WEIGHTS := [0.45, 0.2, 0.2, 0.15]
const TYPE_CN := {"combat": "战斗", "chest": "宝箱", "event": "事件", "rest": "休息", "exit": "出口"}

static func generate(seed: int, depth: int, t: Tunables) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed, depth])
	var n := rng.randi_range(t.nodes_min, t.nodes_max)
	var middle := n - 1
	var cols: Array = []
	var id := 0
	while middle > 0:
		var c := mini(rng.randi_range(1, 3), middle)
		var col: Array = []
		for i in c:
			col.append(id)
			id += 1
		cols.append(col)
		middle -= c
	var exit_id := id
	cols.append([exit_id])
	var nodes: Array = []
	for ci in cols.size():
		for ri in cols[ci].size():
			nodes.append({"id": cols[ci][ri], "col": ci, "row": ri, "rows": cols[ci].size(),
				"type": "exit" if cols[ci][ri] == exit_id else _pick(rng), "next": [], "visited": false})
	nodes.sort_custom(func(a, b): return a.id < b.id)
	# 连边：每个节点连向下一列 1~2 个；保证下一列每个节点都有入边
	for ci in cols.size() - 1:
		var nxt: Array = cols[ci + 1]
		for nid in cols[ci]:
			var picks := nxt.duplicate()
			_shuffle(picks, rng)
			for k in mini(rng.randi_range(1, 2), picks.size()):
				nodes[nid].next.append(picks[k])
		for tid in nxt:
			var has := false
			for nid in cols[ci]:
				if tid in nodes[nid].next:
					has = true
			if not has:
				nodes[cols[ci][rng.randi_range(0, cols[ci].size() - 1)]].next.append(tid)
		for nid in cols[ci]:
			nodes[nid].next.sort()
	# 入口固定休息点：在第 0 列之前插入一个必经的休息节点（不计入 nodes_min/max）
	if t.has_entrance_rest(depth):
		for nd in nodes:
			nd.id += 1
			nd.col += 1
			for k in nd.next.size():
				nd.next[k] += 1
		for ci in cols.size():
			for k in cols[ci].size():
				cols[ci][k] += 1
		exit_id += 1
		nodes.push_front({"id": 0, "col": 0, "row": 0, "rows": 1, "type": "rest", "entrance": true, "next": cols[0].duplicate(), "visited": false})
		cols.push_front([0])
	# 保证至少一个战斗
	var has_combat := false
	for nd in nodes:
		if nd.type == "combat":
			has_combat = true
	if not has_combat:
		var lo := 1 if t.has_entrance_rest(depth) else 0
		nodes[rng.randi_range(lo, exit_id - 1)].type = "combat"
	return {"seed": seed, "depth": depth, "nodes": nodes, "cols": cols.size(), "start": cols[0], "exit": exit_id}

static func _pick(rng: RandomNumberGenerator) -> String:
	var r := rng.randf()
	var acc := 0.0
	for i in TYPES.size():
		acc += WEIGHTS[i]
		if r < acc:
			return TYPES[i]
	return TYPES[0]

static func _shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp

static func reachable_from(fd: Dictionary, cur: int) -> Array:
	return fd.start.duplicate() if cur < 0 else fd.nodes[cur].next.duplicate()
