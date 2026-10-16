extends Node
## 跨死亡数据（存档 user://lineage.json）：个体、遗志、墓志铭、尸体、保险箱、局外材料、局外强化、剧情标记

signal changed

var save_path := "user://lineage.json"
var legacy_rules: LegacyRules = preload("res://data/legacy_rules.tres")
var vault_rules: VaultRules = preload("res://data/vault_rules.tres")
var meta_rules: MetaRules = preload("res://data/meta_rules.tres")

var gen_counter := 0
var individuals: Array = [] ## {name, gen_no, level, xp, legacies, trait, flaw, mastery}
var epitaphs: Array = [] ## {gen_no, name, level, depth, cause, time, last_words}
var corpse: Dictionary = {} ## {depth, item, shards}
var vault: Array = [] ## [{id, count}]
var vault_level := 0
var loadout: Array = [] ## 村里身上的装备 id（下潜时变成局内装备）
var mats := {"moss": 0, "moss_essence": 0}
var shards_bank := 0
var upgrades := {"vit": 0, "swift": 0}
var flags := {}
var charm_carried := 0 ## 仓库里的回村符张数（没在保险箱、也没在背包里）
var charm_source := ""
var charm_lord_seen := {} ## "层数" -> true，区域最后一层的层主第一次击杀。死亡不清除
var rng := RandomNumberGenerator.new()

func _ready() -> void:
	rng.randomize()
	load_save()

# ---------- 个体 ----------
func current() -> Dictionary:
	if individuals.is_empty():
		_birth(1, [], {})
	return individuals[-1]

func individual_name(gen_no: int) -> String:
	return "%s·#%04d" % [legacy_rules.protagonist_name, gen_no]

func _birth(level: int, legacies: Array, mastery: Dictionary) -> Dictionary:
	gen_counter += 1
	var ind := {"name": individual_name(gen_counter), "gen_no": gen_counter, "level": level,
		"xp": (load("res://data/player_stats.tres") as PlayerStats).xp_for_level(level),
		"legacies": legacies.duplicate(), "trait": "", "flaw": "", "mastery": mastery}
	var tk := Stats.TRAITS.keys()
	if legacy_rules.trait_count > 0:
		ind.trait = tk[rng.randi_range(0, tk.size() - 1)]
	if rng.randf() < legacy_rules.flaw_chance:
		var fk := Stats.FLAWS.keys()
		ind.flaw = fk[rng.randi_range(0, fk.size() - 1)]
	individuals.append(ind)
	return ind

## 死亡：记墓志铭、留尸体、丢碎片；返回 {lost_shards, corpse}
func record_death(run: Run, level: int, xp: int, cause: String) -> Dictionary:
	var ind := current()
	ind.level = level
	ind.xp = xp
	epitaphs.append({"gen_no": ind.gen_no, "name": ind.name, "level": level, "depth": run.depth, "cause": cause,
		"time": Time.get_datetime_string_from_system(), "last_words": ""})
	var lost := ceili(run.shards_carried * legacy_rules.shard_loss_ratio)
	var c := {"depth": run.depth, "item": "", "shards": run.shards_carried - lost}
	if not run.equipped.is_empty():
		c.item = run.equipped[rng.randi_range(0, run.equipped.size() - 1)].item.id
	corpse = c ## 只保留最近一具
	loadout.clear() ## 取出的装备算局内装备，死了就丢
	save()
	return {"lost_shards": lost, "corpse": c}

## 新个体：等级 = max(1, floor(前任 × 0.3))；legacy_id 为空表示不继承；replace_i ≥ 0 时替换已有遗志
func new_individual(legacy_id: String, replace_i := -1) -> Dictionary:
	var prev := current()
	var legs: Array = prev.legacies.duplicate()
	if legacy_id != "":
		if legs.size() >= legacy_rules.legacy_max:
			if replace_i >= 0 and replace_i < legs.size():
				legs[replace_i] = legacy_id
		elif not legacy_id in legs:
			legs.append(legacy_id)
	var mastery := {}
	for k in prev.get("mastery", {}):
		mastery[k] = int(prev.mastery[k] * legacy_rules.mastery_ratio)
	var ind := _birth(legacy_rules.inherit_level(int(prev.level)), legs, mastery)
	save()
	return ind

# ---------- 保险箱 ----------
func vault_capacity() -> int:
	return vault_rules.base_slots + vault_level * vault_rules.upgrade_slots_per_level

func can_vault(item: ItemData) -> bool:
	return item != null and vault_rules.allows(item.category)

func vault_put(item, count := 1) -> bool:
	var it: ItemData = item if item is ItemData else (item.item if item is ItemStack else Items.get_item(String(item)))
	if item is ItemStack:
		count = item.count
	if it != null and it.id == RecallCharm.ITEM_ID:
		return Game.recall.deposit_carried()
	if not can_vault(it) or vault.size() >= vault_capacity():
		return false
	vault.append({"id": it.id, "count": count})
	save()
	changed.emit()
	return true

## 替换：把 i 号格子的东西换出来，放进新的
func vault_replace(i: int, item) -> Dictionary:
	var it: ItemData = item if item is ItemData else Items.get_item(String(item))
	if it != null and it.id == RecallCharm.ITEM_ID:
		return {}
	if not can_vault(it) or i < 0 or i >= vault.size():
		return {}
	var old: Dictionary = vault[i]
	vault[i] = {"id": it.id, "count": 1}
	save()
	changed.emit()
	return old

func vault_take(i: int) -> ItemData:
	if i < 0 or i >= vault.size():
		return null
	var e: Dictionary = vault.pop_at(i)
	var it := Items.get_item(e.id)
	if it != null and it.id == RecallCharm.ITEM_ID:
		Game.recall.receive_from_vault(e)
	elif it.category == "equipment":
		loadout.append(it.id)
	else:
		mats[it.id] = int(mats.get(it.id, 0)) + int(e.count)
	save()
	changed.emit()
	return it

func upgrade_vault() -> bool:
	if vault_level >= vault_rules.max_upgrade_level:
		return false
	var c := vault_rules.cost_for(vault_level + 1)
	if mats.moss_essence < c:
		return false
	mats.moss_essence -= c
	vault_level += 1
	save()
	return true

func buy_upgrade(kind: String) -> bool:
	var lv: int = upgrades.get(kind, 0)
	var maxl := meta_rules.vit_max_level if kind == "vit" else meta_rules.swift_max_level
	if lv >= maxl:
		return false
	var c := meta_rules.cost(meta_rules.vit_cost if kind == "vit" else meta_rules.swift_cost, lv + 1)
	if mats.moss < c:
		return false
	mats.moss -= c
	upgrades[kind] = lv + 1
	save()
	return true

# ---------- 存档 ----------
func to_dict() -> Dictionary:
	return {"v": 1, "gen_counter": gen_counter, "individuals": individuals, "epitaphs": epitaphs, "corpse": corpse, "vault": vault,
		"vault_level": vault_level, "loadout": loadout, "mats": mats, "shards_bank": shards_bank, "upgrades": upgrades, "flags": flags,
		"charm_carried": charm_carried, "charm_source": charm_source, "charm_lord_seen": charm_lord_seen}

func save() -> void:
	var f := FileAccess.open(save_path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(to_dict()))
		f.close()

func load_save() -> void:
	reset_memory()
	if not FileAccess.file_exists(save_path):
		return
	var d = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	if typeof(d) != TYPE_DICTIONARY:
		return
	gen_counter = int(d.get("gen_counter", 0))
	individuals = d.get("individuals", [])
	for ind in individuals:
		ind.level = int(ind.level); ind.gen_no = int(ind.gen_no); ind.xp = int(ind.xp)
		var m: Dictionary = ind.get("mastery", {})
		for k in m:
			m[k] = int(m[k])
	epitaphs = d.get("epitaphs", [])
	for e in epitaphs:
		for k in ["gen_no", "level", "depth"]:
			e[k] = int(e.get(k, 0))
	corpse = d.get("corpse", {})
	if corpse.has("depth"):
		corpse.depth = int(corpse.depth); corpse.shards = int(corpse.get("shards", 0))
	vault = d.get("vault", [])
	for e in vault:
		e.count = int(e.count)
	vault_level = int(d.get("vault_level", 0))
	loadout = d.get("loadout", [])
	for k in d.get("mats", {}):
		mats[k] = int(d.mats[k])
	shards_bank = int(d.get("shards_bank", 0))
	for k in d.get("upgrades", {}):
		upgrades[k] = int(d.upgrades[k])
	flags = d.get("flags", {})
	charm_carried = int(d.get("charm_carried", 0))
	charm_source = String(d.get("charm_source", ""))
	charm_lord_seen = {}
	for k in d.get("charm_lord_seen", {}):
		charm_lord_seen[str(k)] = bool(d.charm_lord_seen[k])

func reset_memory() -> void:
	gen_counter = 0
	individuals = []
	epitaphs = []
	corpse = {}
	vault = []
	vault_level = 0
	loadout = []
	mats = {"moss": 0, "moss_essence": 0}
	shards_bank = 0
	upgrades = {"vit": 0, "swift": 0}
	flags = {}
	charm_carried = 0
	charm_source = ""
	charm_lord_seen = {}

func wipe() -> void:
	reset_memory()
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	changed.emit()
