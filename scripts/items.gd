class_name Items
extends RefCounted
## 物品注册表：读取 data/items/*.tres

static var _all := {}

static func _ensure() -> void:
	if not _all.is_empty():
		return
	for id in ["moss", "moss_essence", "shard", "trinket_hp", "trinket_atk", "trinket_dash", "recall_charm", "moss_fang"]:
		var r: ItemData = load("res://data/items/%s.tres" % id)
		_all[id] = r

static func get_item(id: String) -> ItemData:
	_ensure()
	return _all.get(id)

static func equipment() -> Array:
	_ensure()
	return _all.values().filter(func(i): return i.category == "equipment")

static func all() -> Array:
	_ensure()
	return _all.values()
