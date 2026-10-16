class_name Run
extends RefCounted
## 一局（从井口下潜到撤离/死亡）

var id := ""
var seed := 0
var depth := 1
var boons: Array[BoonData] = []
var boon_order: Array[String] = [] ## 获得顺序（遗志取最后 3 个）
var bag: Array[ItemStack] = [] ## 局内背包：材料/稀有材料/碎片/捡到的装备
var equipped: Array[ItemStack] = [] ## 生效中的装备（从保险箱取出 + 局内捡到）
var shards_carried := 0
var time_started := 0.0
var kills := 0
var dmg_taken := 0
var hp := 100
var xp := 0
var level_start := 1
var clue_seen: Array[String] = []
var floor_stats := {} ## 本层统计：floor_t0, combat_sec, guard_sec, hp_start, dmg_taken, kills, level_start
var charm_source := "" ## 当前这张回村符从哪来：chest / elite / lord / pending
var suspended := false ## 用回村符回到村里，这局还没结束
var just_recalled := false
var floor_memory := {} ## depth -> {seed, killed, picked, guard_dead, corpse_taken}

func add_item(st: ItemStack) -> void:
	if st.item.category == "shard":
		shards_carried += st.count
		return
	if st.item.category == "equipment":
		bag.append(st)
		equipped.append(st)
		return
	for b in bag:
		if b.item == st.item:
			b.count += st.count
			return
	bag.append(ItemStack.new(st.item, st.count))

func take_item(id: String, n := 1) -> bool:
	for i in bag.size():
		if bag[i].item.id != id:
			continue
		if bag[i].count < n:
			return false
		bag[i].count -= n
		if bag[i].count <= 0:
			bag.remove_at(i)
			for j in range(equipped.size() - 1, -1, -1):
				if equipped[j].item.id == id:
					equipped.remove_at(j)
					break
		return true
	return false

func swap_bag(i: int, j: int) -> void:
	if i < 0 or j < 0 or i >= bag.size() or j >= bag.size() or i == j:
		return
	var tmp: ItemStack = bag[i]
	bag[i] = bag[j]
	bag[j] = tmp

func count_of(id: String) -> int:
	if id == "shard":
		return shards_carried
	var n := 0
	for b in bag:
		if b.item.id == id:
			n += b.count
	return n

func add_boon(b: BoonData) -> void:
	if b in boons:
		return
	boons.append(b)
	boon_order.append(b.id)

func remove_boon(b: BoonData) -> void:
	boons.erase(b)
	boon_order.erase(b.id)

func last_boons(n: int) -> Array:
	return boon_order.slice(maxi(0, boon_order.size() - n))

func see_clue(c: String) -> void:
	if not c in clue_seen:
		clue_seen.append(c)
