extends Node
## 场景流转与当前局：village → floor(1..3) → extract_result / death_screen → legacy_pick → village

signal floor_entered(n: int)
signal run_ended(extracted: bool)

const SCN_VILLAGE := "res://scenes/village/village.tscn"
const SCN_FLOOR := "res://scenes/floor/floor.tscn"
const SCN_EXTRACT := "res://scenes/ui/extract_result.tscn"
const SCN_DEATH := "res://scenes/ui/death_screen.tscn"
const SCN_LEGACY := "res://scenes/ui/legacy_pick.tscn"
const FINAL_FLOOR := 3

var player_stats: PlayerStats = preload("res://data/player_stats.tres")
var attacks: Array[AttackData] = [preload("res://data/attacks/light_1.tres"), preload("res://data/attacks/light_2.tres"), preload("res://data/attacks/light_3.tres")]
var skill: AttackData = preload("res://data/attacks/skill_sweep.tres")
var enemies := {"mushling": preload("res://data/enemies/mushling.tres"), "rootshot": preload("res://data/enemies/rootshot.tres"), "shellbug": preload("res://data/enemies/shellbug.tres")}
var floors: Array[FloorData] = [preload("res://data/floors/floor_1.tres"), preload("res://data/floors/floor_2.tres"), preload("res://data/floors/floor_3.tres")]
var affixes := {"frenzy": preload("res://data/guards/affix_frenzy.tres"), "summon": preload("res://data/guards/affix_summon.tres"), "hardshell": preload("res://data/guards/affix_hardshell.tres"), "spore": preload("res://data/guards/affix_spore.tres")}
var clues: LoreClues = preload("res://data/lore/clues.tres")
var recall: RecallCharm ## load() in _ready; a parse-time preload cycles with this script and breaks the web build

var run: Run
var last_extract := {} ## 结算界面用
var last_death := {}
var rng := RandomNumberGenerator.new()
var run_seed_override := -1 ## 面板可改；-1 = 随机
# 调试开关
var god_mode := false
var inf_dash := false
var show_boxes := false
var auto_pick := -1 ## 测试：≥0 时 3 选 1 自动选第 n 个
var base_time_scale := 1.0
var _hitstop_until := 0
var _slowmo_until := 0
var debug_panel: CanvasLayer

func _ready() -> void:
	recall = load("res://data/recall_charm.tres")
	process_mode = Node.PROCESS_MODE_ALWAYS
	rng.randomize()
	_setup_input()
	debug_panel = load("res://scripts/debug_panel.gd").new()
	add_child(debug_panel)
	_setup_web()

func _process(_d: float) -> void:
	var now := Time.get_ticks_msec()
	var s := base_time_scale
	if now < _hitstop_until:
		s *= 0.02
	elif now < _slowmo_until:
		s *= 0.3
	Engine.time_scale = s
	_update_web()

func floor_data(n: int) -> FloorData:
	return floors[clampi(n - 1, 0, floors.size() - 1)]

func goto(path: String) -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file.call_deferred(path)

# ---------- 局流程 ----------
func start_run() -> void:
	run = Run.new()
	run.seed = run_seed_override if run_seed_override >= 0 else rng.randi() % 1000000
	run.id = "%d_%d" % [Time.get_unix_time_from_system(), run.seed]
	run.time_started = Time.get_ticks_msec() / 1000.0
	var ind := Lineage.current()
	run.xp = int(ind.xp)
	run.level_start = level()
	for id in Lineage.loadout:
		var st := ItemStack.new(Items.get_item(id), 1)
		run.equipped.append(st)
	Lineage.loadout.clear() ## 取出后的装备算局内装备
	Lineage.save()
	run.hp = max_hp()
	_floor_log_open = false
	recall.bring_into_run()
	enter_floor(1)

func enter_floor(n: int) -> void:
	run.depth = n
	goto(SCN_FLOOR)
	floor_entered.emit(n)

func level() -> int:
	return player_stats.level_for_xp(run.xp) if run else int(Lineage.current().level)

func mods() -> Dictionary:
	return Stats.collect(run)

func max_hp() -> int:
	var m := mods()
	return maxi(1, roundi(player_stats.max_hp * (1.0 + (level() - 1) * player_stats.hp_per_level)) + int(m.max_hp_add))

func gain_xp(x: int) -> void:
	var before := level()
	var old_max := max_hp()
	run.xp += x
	if level() > before:
		run.hp += max_hp() - old_max

## 撤离：全部带回 → 结算（放入保险箱）
func extract() -> void:
	var got := {"moss": run.count_of("moss"), "moss_essence": run.count_of("moss_essence"), "shards": run.shards_carried, "equipment": []}
	Lineage.mats.moss += got.moss
	Lineage.mats.moss_essence += got.moss_essence
	Lineage.shards_bank += got.shards
	if int(got.moss) > 0:
		note_run_store(true, "material", int(got.moss))
	if int(got.moss_essence) > 0:
		note_run_store(true, "rare_material", int(got.moss_essence))
	for st in run.equipped:
		got.equipment.append(st.item.id)
	recall.bank_from_run()
	stamp_charm_stock()
	var ind := Lineage.current()
	ind.level = level()
	ind.xp = run.xp
	last_extract = got
	Lineage.save()
	run_ended.emit(true)
	goto(SCN_EXTRACT)

## 回村符成功：这局中断，人在村里，楼层状态留在 run.floor_memory
func recall_to_village() -> void:
	if run == null:
		return
	run.suspended = true
	run.just_recalled = true
	run.charm_recalled = true
	goto(SCN_VILLAGE)

## 从村里回到被中断的那一层的起点。掉落和离开时一样
func recall_return() -> void:
	if run == null or not run.suspended:
		return
	run.suspended = false
	enter_floor(run.depth)

func descend() -> void:
	run.hp = mini(max_hp(), run.hp + roundi(max_hp() * player_stats.heal_between_floors))
	enter_floor(run.depth + 1)

## 死亡：顿帧 + 慢镜头 → 墓志铭 → 培养槽 → 遗志
func on_player_died(cause: String) -> void:
	if run == null or not last_death.is_empty() and last_death.get("run_id") == run.id:
		return
	var res := Lineage.record_death(run, level(), run.xp, cause)
	last_death = {"run_id": run.id, "cause": cause, "depth": run.depth, "level": level(), "name": Lineage.current().name,
		"gen_no": Lineage.current().gen_no, "candidates": run.last_boons(Lineage.legacy_rules.legacy_pick_from), "lost_shards": res.lost_shards, "clue_seen": run.clue_seen.duplicate()}
	_slowmo_until = Time.get_ticks_msec() + int(Lineage.legacy_rules.death_slowmo_sec * 1000)
	run_ended.emit(false)
	await get_tree().create_timer(Lineage.legacy_rules.death_slowmo_sec, true, false, true).timeout
	goto(SCN_DEATH)

## 遗志选择后：生成新个体，记 deaths.csv
func finish_legacy(legacy_id: String, replace_i := -1) -> void:
	Lineage.new_individual(legacy_id, replace_i)
	Log.write("deaths", [last_death.get("gen_no", 0), last_death.get("level", 1), last_death.get("depth", 0), last_death.get("cause", ""), legacy_id, Lineage.vault.size(), "|".join(last_death.get("clue_seen", []))])
	run = null
	goto(SCN_VILLAGE)

func log_floor(result: String) -> void:
	if run == null:
		return
	if _floor_log_open:
		run.unbossed_open = 0
	var fs := run.floor_stats
	var now := Time.get_ticks_msec() / 1000.0
	Log.write("floors", [run.id, Lineage.current().gen_no, run.depth, result, "%.1f" % (now - float(fs.get("t0", now))), "%.1f" % float(fs.get("combat_sec", 0.0)),
		"%.1f" % float(fs.get("guard_sec", 0.0)), fs.get("hp_start", run.hp), run.hp, fs.get("dmg_taken", 0), fs.get("kills", 0),
		"|".join(run.boon_order), fs.get("level_start", 1), level(), run.count_of("moss"), run.shards_carried, "|".join(run.clue_seen),
		fs.get("chunks_visited", 0), fs.get("encounters", 0), fs.get("chasers_peak", 0), fs.get("camps_cleared", 0), fs.get("nodes_taken", 0),
		fs.get("charm_used", 0), fs.get("charm_floor", 0), fs.get("charm_interrupted", 0), fs.get("charm_source", ""),
		1 if run.charm_recalled and run.charm_stashed else 0, run.unbossed_open, recall.stock() if recall else 0])
	_floor_log_open = true

var _floor_log_open := false

func _lord_dead_now() -> bool:
	if run == null:
		return true
	var sc := get_tree().current_scene
	if sc and sc.scene_file_path == SCN_FLOOR and "guard_dead" in sc:
		return bool(sc.guard_dead)
	var mem: Dictionary = run.floor_memory.get(run.depth, {})
	return bool(mem.get("guard_dead", false))

## 撤离入库之后，把这一行的库存改成仓库 + 保险箱的张数
func stamp_charm_stock() -> void:
	if recall == null or not _floor_log_open:
		return
	Log.patch_last("floors", {"charm_stock": recall.stock()})

## 把局里的东西放进仓库或保险箱之后记一笔。层主没死时材料计入 unbossed_mat_out
func note_run_store(from_run: bool, category: String, count: int) -> void:
	if run == null or count <= 0:
		return
	if run.charm_recalled:
		run.charm_stashed = true
	if from_run and category in ["material", "rare_material"] and not _lord_dead_now():
		run.unbossed_open += count
	if _floor_log_open:
		Log.patch_last("floors", {"charm_stash_run": 1 if run.charm_recalled and run.charm_stashed else 0, "unbossed_mat_out": run.unbossed_open})

## 背包里的材料进仓库，能进保险箱的进保险箱。一次存一组（材料整组，其余 1 个）
func store_bag(id: String) -> bool:
	if run == null or recall == null:
		return false
	var n := run.count_of(id)
	if n <= 0:
		return false
	var it := Items.get_item(id)
	if it == null:
		return false
	if it.category in ["material", "rare_material"]:
		run.take_item(id, n)
		Lineage.mats[id] = int(Lineage.mats.get(id, 0)) + n
		Lineage.save()
		note_run_store(true, it.category, n)
		return true
	if id == RecallCharm.ITEM_ID:
		return store_charm(run.sealed_count(id) > 0, false)
	if not Lineage.can_vault(it):
		return false
	if not Lineage.vault_put(it, 1):
		return false
	run.take_item(id, 1)
	note_run_store(true, it.category, 1)
	return true

## 背包里的 1 张回村符存进仓库或保险箱。存进去就解开封印
func store_charm(sealed: bool, to_vault: bool) -> bool:
	if run == null or recall == null:
		return false
	if not run.take_kind(RecallCharm.ITEM_ID, sealed, 1):
		return false
	var ok := recall.vault_add_charm(1) if to_vault else true
	if not to_vault:
		Lineage.charm_carried += 1
		Lineage.save()
	if not ok:
		run.add_item(ItemStack.new(Items.get_item(RecallCharm.ITEM_ID), 1, sealed, ""))
		return false
	note_run_store(true, "key_item", 1)
	return true

func hitstop(sec: float) -> void:
	_hitstop_until = maxi(_hitstop_until, Time.get_ticks_msec() + int(sec * 1000))

# ---------- 输入 ----------
func _setup_input() -> void:
	_action("ui_accept", [], [JOY_BUTTON_A])
	_action("ui_cancel", [], [JOY_BUTTON_B])
	_action("move_left", [KEY_A, KEY_LEFT], [JOY_BUTTON_DPAD_LEFT], JOY_AXIS_LEFT_X, -1.0)
	_action("move_right", [KEY_D, KEY_RIGHT], [JOY_BUTTON_DPAD_RIGHT], JOY_AXIS_LEFT_X, 1.0)
	_action("move_up", [KEY_W, KEY_UP], [JOY_BUTTON_DPAD_UP], JOY_AXIS_LEFT_Y, -1.0)
	_action("move_down", [KEY_S, KEY_DOWN], [JOY_BUTTON_DPAD_DOWN], JOY_AXIS_LEFT_Y, 1.0)
	_action("aim_left", [], [], JOY_AXIS_RIGHT_X, -1.0)
	_action("aim_right", [], [], JOY_AXIS_RIGHT_X, 1.0)
	_action("aim_up", [], [], JOY_AXIS_RIGHT_Y, -1.0)
	_action("aim_down", [], [], JOY_AXIS_RIGHT_Y, 1.0)
	_action("attack", [KEY_J], [JOY_BUTTON_X], -1, 0.0, MOUSE_BUTTON_LEFT)
	_action("dash", [KEY_SPACE, KEY_SHIFT], [JOY_BUTTON_A])
	_action("skill", [KEY_K, KEY_Q], [JOY_BUTTON_Y], -1, 0.0, MOUSE_BUTTON_RIGHT)
	_action("interact", [KEY_E, KEY_F], [JOY_BUTTON_B])
	_action("recall", [KEY_R], [JOY_BUTTON_RIGHT_SHOULDER])
	_action("debug_toggle", [KEY_F1, KEY_QUOTELEFT], [JOY_BUTTON_BACK])

func _action(name: String, keys: Array, buttons: Array, axis := -1, axis_val := 0.0, mouse := -1) -> void:
	if not InputMap.has_action(name):
		InputMap.add_action(name, 0.3)
	for k in keys:
		var e := InputEventKey.new()
		e.physical_keycode = k
		InputMap.action_add_event(name, e)
	for b in buttons:
		var j := InputEventJoypadButton.new()
		j.button_index = b
		InputMap.action_add_event(name, j)
	if axis >= 0:
		var m := InputEventJoypadMotion.new()
		m.axis = axis
		m.axis_value = axis_val
		InputMap.action_add_event(name, m)
	if mouse >= 0:
		var mb := InputEventMouseButton.new()
		mb.button_index = mouse
		InputMap.action_add_event(name, mb)

# ---------- 网页调试钩子：greybox.downloadCsv() / greybox.selftestRow() / greybox.startRun() / greybox.currentScene ----------
var _js_refs := []
var _js_obj
func _setup_web() -> void:
	if not OS.has_feature("web"):
		return
	var win = JavaScriptBridge.get_interface("window")
	_js_obj = JavaScriptBridge.create_object("Object")
	var cb_dl = JavaScriptBridge.create_callback(func(_a): Log.download_all())
	var cb_row = JavaScriptBridge.create_callback(func(_a): Log.write("floors", ["selftest", 0, 0, "selftest", 0, 0, 0, 0, 0, 0, 0, "", 1, 1, 0, 0, "", 0, 0, 0, 0, 0, 0, 0, 0, "", 0, 0, 0]))
	var cb_run = JavaScriptBridge.create_callback(func(_a): start_run())
	var cb_perf = JavaScriptBridge.create_callback(func(_a):
		var sc := get_tree().current_scene
		if sc and sc.has_method("debug_perf_ring"):
			god_mode = true
			sc.debug_perf_ring(12))
	var cb_prof_on = JavaScriptBridge.create_callback(func(a):
		Prof.on = bool(a[0]) if a.size() > 0 else true
		Prof.frames.clear())
	var cb_prof_dump = JavaScriptBridge.create_callback(func(_a):
		_js_obj.prof = JSON.stringify(Prof.frames))
	var cb_clear = JavaScriptBridge.create_callback(func(_a):
		for e in get_tree().get_nodes_in_group("enemies"):
			e.queue_free())
	var cb_vis = JavaScriptBridge.create_callback(func(a):
		var sc := get_tree().current_scene
		if sc and sc.has_method("debug_set_visible"):
			sc.debug_set_visible(String(a[0]), bool(a[1])))
	_js_refs = [cb_dl, cb_row, cb_run, cb_perf, cb_prof_on, cb_prof_dump, cb_clear, cb_vis]
	_js_obj.vis = cb_vis
	_js_obj.profOn = cb_prof_on
	_js_obj.profDump = cb_prof_dump
	_js_obj.clearEnemies = cb_clear
	_js_obj.perfRing = cb_perf
	_js_obj.downloadCsv = cb_dl
	_js_obj.selftestRow = cb_row
	_js_obj.startRun = cb_run
	win.greybox = _js_obj

var _logic_ms := 0.0 ## 逻辑帧时间（process + physics）指数平均，网页检查读 greybox.logicMs
var _phys_last := 0
func _update_web() -> void:
	if Prof.on:
		var pf := Engine.get_physics_frames()
		Prof.end_frame({"proc": Performance.get_monitor(Performance.TIME_PROCESS) * 1e6, "phys": Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1e6,
			"steps": pf - _phys_last, "t": Time.get_ticks_usec(), "objs": Performance.get_monitor(Performance.OBJECT_COUNT), "draw": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)})
		_phys_last = pf
	if _js_obj:
		var ms := (Performance.get_monitor(Performance.TIME_PROCESS) + Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)) * 1000.0
		_logic_ms = lerpf(_logic_ms, ms, 0.05)
		_js_obj.logicMs = _logic_ms
		_js_obj.enemies = get_tree().get_nodes_in_group("enemies").size()
	if _js_obj and get_tree().current_scene:
		_js_obj.currentScene = get_tree().current_scene.scene_file_path
