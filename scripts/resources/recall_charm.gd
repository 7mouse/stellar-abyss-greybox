class_name RecallCharm
extends Resource
## 紧急回村符（data/recall_charm.tres）。所有可调项都在这里，F1 面板按导出变量生成编辑器。

const ITEM_ID := "recall_charm"

@export var display_name := "紧急回村符"
@export var max_owned := 1 ## 身上 + 保险箱一共最多几个
@export var chest_drop_chance := 0.03 ## 普通宝箱。已经持有时整次判定跳过
@export var elite_drop_chance := 0.02 ## 精英（elite_ids）。已经持有时整次判定跳过
@export var channel_sec := 3.0 ## 楼层内引导秒数，受击打断且不消耗
@export var return_enabled := true ## 村里「返回第 N 层」入口。默认开，以后好关
@export var blocked_hint := "此处无法使用回村符"
@export var trap_rooms_floor_1 := 0
@export var trap_rooms_floor_2 := 1
@export var trap_rooms_floor_3 := 1
@export var elite_ids := "shellbug" ## 逗号分隔的敌人 id，只影响掉符，不改数值
@export var use_hint := "R / 手柄 RB 使用回村符"

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

func owned() -> int:
	var n := Lineage.charm_carried
	if Game.run:
		n += Game.run.count_of(ITEM_ID)
	for e in Lineage.vault:
		if String(e.get("id", "")) == ITEM_ID:
			n += int(e.get("count", 0))
	return n

func carrying() -> bool:
	return Game.run != null and Game.run.count_of(ITEM_ID) > 0

func storage_locked() -> bool:
	return Game.run != null and Game.run.suspended

## 已经持有时宝箱/精英不再掷骰
func _at_cap() -> bool:
	return owned() >= maxi(1, max_owned)

func grant(source: String) -> bool:
	if _at_cap():
		return false
	var it := Items.get_item(ITEM_ID)
	if it == null:
		return false
	if Game.run:
		Game.run.add_item(ItemStack.new(it, 1))
		Game.run.charm_source = source
		Game.run.floor_stats["charm_source"] = source
	else:
		Lineage.charm_carried = 1
		Lineage.charm_source = source
		Lineage.save()
	return true

func consume() -> bool:
	return Game.run != null and Game.run.take_item(ITEM_ID, 1)

## 村里把身上的符放进保险箱（转移，不新增）
func deposit_carried() -> bool:
	if storage_locked() or Lineage.charm_carried <= 0:
		return false
	if _vault_index() >= 0 or Lineage.vault.size() >= Lineage.vault_capacity():
		return false
	var src := Lineage.charm_source
	Lineage.charm_carried = 0
	Lineage.vault.append({"id": ITEM_ID, "count": 1, "source": src})
	Lineage.save()
	Lineage.changed.emit()
	return true

## 从保险箱取出。有进行中的局就放进背包，否则拿在身上
func receive_from_vault(entry: Dictionary) -> void:
	var src := String(entry.get("source", Lineage.charm_source))
	if Game.run and not Game.run.suspended:
		var it := Items.get_item(ITEM_ID)
		Game.run.add_item(ItemStack.new(it, 1))
		Game.run.charm_source = src
		Game.run.floor_stats["charm_source"] = src
	else:
		Lineage.charm_carried = 1
		Lineage.charm_source = src

func _vault_index() -> int:
	for i in Lineage.vault.size():
		if String(Lineage.vault[i].get("id", "")) == ITEM_ID:
			return i
	return -1

func roll_chest(key: String) -> bool:
	if _at_cap():
		return false
	if not _roll(chest_drop_chance, "chest:" + key):
		return false
	return grant("chest")

func roll_elite(enemy_id: String, key: String) -> bool:
	if Game.run == null or not is_elite(enemy_id):
		return false
	if _at_cap():
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

## 每层第一次击杀层主必给 1 个；已经持有就记成待领。本局之后的死亡不清这两份记录
func on_lord_killed(depth: int) -> void:
	var key := str(depth)
	if bool(Lineage.charm_lord_seen.get(key, false)):
		return
	Lineage.charm_lord_seen[key] = true
	if _at_cap():
		Lineage.charm_pending.append(depth)
	else:
		grant("lord")
	Lineage.save()

func claim_pending() -> bool:
	if Lineage.charm_pending.is_empty() or _at_cap():
		return false
	Lineage.charm_pending.pop_front()
	if not grant("pending"):
		return false
	Lineage.save()
	return true

## 撤离时把背包里的符存回身上；死亡不调用，符会跟着背包丢掉
func bank_from_run() -> void:
	if Game.run == null or Game.run.count_of(ITEM_ID) <= 0:
		return
	var src := Game.run.charm_source
	Game.run.take_item(ITEM_ID, Game.run.count_of(ITEM_ID))
	Lineage.charm_carried = 1
	Lineage.charm_source = src

## 下潜时把身上的符放进背包（死了会丢）
func bring_into_run() -> void:
	if Game.run == null or Lineage.charm_carried <= 0:
		return
	var it := Items.get_item(ITEM_ID)
	if it == null:
		return
	Game.run.add_item(ItemStack.new(it, Lineage.charm_carried))
	Game.run.charm_source = Lineage.charm_source
	Game.run.floor_stats["charm_source"] = Lineage.charm_source
	Lineage.charm_carried = 0
	Lineage.save()
