class_name RecallCharm
extends Resource
## 紧急回村符（data/recall_charm.tres）。所有可调项都在这里，F1 面板按导出变量生成编辑器。

const ITEM_ID := "recall_charm"
const CRAFT_MATERIAL := "moss_essence"

@export var display_name := "紧急回村符"
@export var chest_drop_chance := 0.005 ## 普通宝箱。顶稀有，已经持有也照常掷
@export var elite_drop_chance := 0.003 ## 精英（elite_ids）。已经持有也照常掷
@export var lord_drop_chance := 0.02 ## 每次击杀层主
@export var zone_length := 3 ## 每个区域有几层。区域最后一层的层主，第一次击杀必给 1 张
@export var channel_sec := 3.0 ## 楼层内引导秒数，受击打断且不消耗
@export var craft_material_count := 3 ## 制作 1 张符要的层主稀有材料（萤苔精，不限哪一层）
@export var carry_per_floor := 1 ## 进入一层时，背包里最多几张没封印的符
@export var uses_per_run := 1 ## 一局最多成功使用几次
@export var blocked_hint := "此处无法使用回村符"
@export var trap_rooms_floor_1 := 0
@export var trap_rooms_floor_2 := 1
@export var trap_rooms_floor_3 := 1
@export var elite_ids := "shellbug" ## 逗号分隔的敌人 id，只影响掉符，不改数值
@export var use_hint := "R / 手柄 RB 使用回村符"
@export var sealed_hint := "回村符被封印，这一局不能用"

var last_sealed := false ## 最近一次发放是不是封印
var _lord_roll_n := 0

func trap_count(depth: int) -> int:
	match depth:
		1: return trap_rooms_floor_1
		2: return trap_rooms_floor_2
		3: return trap_rooms_floor_3
		_: return 0

func is_elite(id: String) -> bool:
	for part in elite_ids.split(",", false):
		if part.strip_edges() == id:
			return true
	return false

func is_zone_end(depth: int) -> bool:
	return zone_length > 0 and depth > 0 and depth % zone_length == 0

## 仓库 + 保险箱里的回村符。背包里的不算，死亡会丢，撤离入库之后才算进库存
func stock() -> int:
	var n := Lineage.charm_carried
	for e in Lineage.vault:
		if String(e.get("id", "")) == ITEM_ID:
			n += int(e.get("count", 0))
	return n

func owned() -> int:
	var n := Lineage.charm_carried
	if Game.run:
		n += Game.run.count_of(ITEM_ID)
	for e in Lineage.vault:
		if String(e.get("id", "")) == ITEM_ID:
			n += int(e.get("count", 0))
	return n

func carrying() -> bool:
	return Game.run != null and Game.run.unsealed_count(ITEM_ID) > 0

func can_use() -> bool:
	return carrying() and Game.run.charm_uses < uses_per_run

func stack_label(st: ItemStack) -> String:
	if st.sealed:
		return "%s（封印） ×%d" % [st.item.display_name, st.count]
	return "%s ×%d" % [st.item.display_name, st.count]

func dropped_name() -> String:
	if last_sealed:
		return display_name + "（封印）"
	return display_name

## 背包里已经有带入上限那么多符，或者这一局已经用过，新捡到的就封印
func _should_seal() -> bool:
	if Game.run == null:
		return false
	if Game.run.charm_uses >= uses_per_run:
		return true
	return Game.run.count_of(ITEM_ID) >= carry_per_floor

func grant(source: String) -> bool:
	var it := Items.get_item(ITEM_ID)
	if it == null:
		return false
	if Game.run:
		var seal := _should_seal()
		Game.run.add_item(ItemStack.new(it, 1, seal, source))
		last_sealed = seal
		if not seal:
			Game.run.charm_source = source
			Game.run.floor_stats["charm_source"] = source
	else:
		Lineage.charm_carried += 1
		Lineage.charm_source = source
		last_sealed = false
		Lineage.save()
	return true

func consume() -> bool:
	if not can_use():
		return false
	if not Game.run.take_kind(ITEM_ID, false, 1):
		return false
	Game.run.charm_uses += 1
	return true

## 村里把仓库里的 1 张放进保险箱（可以叠多张）
func deposit_carried() -> bool:
	if Lineage.charm_carried <= 0:
		return false
	if not vault_add_charm(1):
		return false
	Lineage.charm_carried -= 1
	Lineage.save()
	return true

func vault_add_charm(n: int) -> bool:
	if n <= 0:
		return false
	var i := _vault_index()
	if i >= 0:
		Lineage.vault[i]["count"] = int(Lineage.vault[i].get("count", 0)) + n
	elif Lineage.vault.size() >= Lineage.vault_capacity():
		return false
	else:
		Lineage.vault.append({"id": ITEM_ID, "count": n, "source": Lineage.charm_source})
	Lineage.save()
	Lineage.changed.emit()
	return true

## 从保险箱取出。局内放进背包（多出来的会封印），否则回到仓库
func receive_from_vault(entry: Dictionary) -> void:
	var n := maxi(1, int(entry.get("count", 1)))
	var src := String(entry.get("source", Lineage.charm_source))
	if Game.run and not Game.run.suspended:
		for _i in n:
			grant(src)
	else:
		Lineage.charm_carried += n
		Lineage.charm_source = src

func _vault_index() -> int:
	for i in Lineage.vault.size():
		if String(Lineage.vault[i].get("id", "")) == ITEM_ID:
			return i
	return -1

func roll_chest(key: String) -> bool:
	if not _roll(chest_drop_chance, "chest:" + key):
		return false
	return grant("chest")

func roll_elite(enemy_id: String, key: String) -> bool:
	if Game.run == null or not is_elite(enemy_id):
		return false
	if not _roll(elite_drop_chance, "elite:" + key):
		return false
	return grant("elite")

func _roll(chance: float, key: String) -> bool:
	if chance <= 0.0:
		return false
	var rng := RandomNumberGenerator.new()
	var seed_v := Game.run.seed if Game.run else 0
	var depth := Game.run.depth if Game.run else 0
	rng.seed = hash([seed_v, depth, "charm", key])
	return rng.randf() < chance

func craft_material_have() -> int:
	var n := int(Lineage.mats.get(CRAFT_MATERIAL, 0))
	if Game.run:
		n += Game.run.count_of(CRAFT_MATERIAL)
	return n

## 花仓库和背包里的萤苔精。没有持有上限
func craft() -> bool:
	var cost := maxi(1, craft_material_count)
	if craft_material_have() < cost:
		return false
	var left := cost
	var from_mats := mini(left, int(Lineage.mats.get(CRAFT_MATERIAL, 0)))
	Lineage.mats[CRAFT_MATERIAL] = int(Lineage.mats.get(CRAFT_MATERIAL, 0)) - from_mats
	left -= from_mats
	if left > 0 and Game.run:
		Game.run.take_item(CRAFT_MATERIAL, left)
	if not grant("craft"):
		return false
	Lineage.save()
	return true

## 每次击杀层主按 lord_drop_chance 掷。区域最后一层的第一次击杀改为必给 1 张，不重复给
func on_lord_killed(depth: int) -> void:
	var key := str(depth)
	var first := not bool(Lineage.charm_lord_seen.get(key, false))
	if is_zone_end(depth) and first:
		Lineage.charm_lord_seen[key] = true
		grant("lord")
		Lineage.save()
		return
	_lord_roll_n += 1
	if _roll(lord_drop_chance, "lord:%s:%d" % [key, _lord_roll_n]):
		grant("lord")

## 撤离时把背包里的符（含封印）存进仓库。封印解开。死亡不调用
func bank_from_run() -> void:
	if Game.run == null:
		return
	var n := Game.run.count_of(ITEM_ID)
	if n <= 0:
		return
	Game.run.remove_all(ITEM_ID)
	Lineage.charm_carried += n
	Lineage.save()

## 下潜时从仓库带入，不超过本层能带的张数。剩下的留在仓库
func bring_into_run() -> void:
	if Game.run == null or Lineage.charm_carried <= 0:
		return
	var room := carry_per_floor - Game.run.unsealed_count(ITEM_ID)
	var n := mini(maxi(0, room), Lineage.charm_carried)
	if n <= 0:
		return
	var it := Items.get_item(ITEM_ID)
	if it == null:
		return
	Game.run.add_item(ItemStack.new(it, n, false, Lineage.charm_source))
	Game.run.charm_source = Lineage.charm_source
	Game.run.floor_stats["charm_source"] = Lineage.charm_source
	Lineage.charm_carried -= n
	Lineage.save()

## 进入一层：背包里没封印的符不能超过 carry_per_floor，多的改成封印
func settle_on_floor_entry() -> void:
	if Game.run == null:
		return
	var extra := Game.run.unsealed_count(ITEM_ID) - carry_per_floor
	if extra > 0:
		Game.run.seal_excess(ITEM_ID, extra)
