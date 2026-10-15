class_name Boons
extends RefCounted
## 8 个局内强化的注册表

const IDS := ["blade", "gale", "afterimage", "rootbind", "thickhide", "bloodthirst", "finisher", "swift"]
static var _all := {}

static func all() -> Array:
	if _all.is_empty():
		for id in IDS:
			_all[id] = load("res://data/boons/%s.tres" % id)
	return IDS.map(func(i): return _all[i])

static func get_boon(id: String) -> BoonData:
	all()
	return _all.get(id)

## 3 选 1 候选：排除已有的
static func offer(owned: Array, rng: RandomNumberGenerator, n := 3) -> Array:
	var pool := all().filter(func(b): return not owned.has(b))
	for i in range(pool.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = pool[i]
		pool[i] = pool[j]
		pool[j] = t
	return pool.slice(0, n)
