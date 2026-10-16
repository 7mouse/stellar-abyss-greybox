class_name LootTable
extends Resource
## 掉落表：entries 每项 {item(id), chance, min, max}；稀有类（rare_material/equipment）吃 rare_mult

@export var id := ""
@export var entries: Array[Dictionary] = []

func roll(rng: RandomNumberGenerator, rare_mult := 1.0, drop_mult := 1.0) -> Array[ItemStack]:
	var out: Array[ItemStack] = []
	for e in entries:
		var iid := String(e.get("item", ""))
		var any_equip := iid == "trinket_any" ## 随机一件饰品
		var it: ItemData = null if any_equip else Items.get_item(iid)
		if it == null and not any_equip:
			continue
		var ch := float(e.get("chance", 1.0)) * drop_mult
		if any_equip or it.category in ["rare_material", "equipment"]:
			ch *= rare_mult
		if rng.randf() < ch:
			var n := rng.randi_range(int(e.get("min", 1)), int(e.get("max", 1)))
			if any_equip:
				var eq := Items.equipment()
				it = eq[rng.randi_range(0, eq.size() - 1)]
			if n > 0:
				out.append(ItemStack.new(it, n))
	return out
