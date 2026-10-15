extends Node
## 全局状态（autoload）：局内背包、局外材料、技能等级、当前层数，以及场景流转。

const SCN_CAMP := "res://scenes/camp.tscn"
const SCN_DUNGEON := "res://scenes/dungeon.tscn"
const SCN_BATTLE := "res://scenes/battle.tscn"
const SCN_RESULT := "res://scenes/result.tscn"
const SCN_CALIBRATION := "res://scenes/calibration.tscn"

var tunables: Tunables = preload("res://data/tunables.tres")
var enemy_types: Array[EnemyData] = [
	preload("res://data/enemies/melee.tres"),
	preload("res://data/enemies/tracker.tres"),
	preload("res://data/enemies/balanced.tres"),
]
var elite_data: EnemyData = preload("res://data/enemies/elite_placeholder.tres")
var boss_data: EnemyData = preload("res://data/enemies/boss_placeholder.tres")
var mg_timing: TimingConfig = preload("res://data/minigames/attack_timing.tres")
var mg_rhythm: RhythmConfig = preload("res://data/minigames/attack_rhythm.tres")
var mg_rps: LuckConfig = preload("res://data/minigames/attack_rps.tres")
var mg_dice: LuckConfig = preload("res://data/minigames/attack_dice.tres")
var mg_defense := {
	1: preload("res://data/minigames/defense_g1.tres"),
	2: preload("res://data/minigames/defense_g2.tres"),
}

# ---- 局外 ----
var meta_materials: int = 0
var meta_shards: int = 0
var skill_levels := {1: 0, 2: 0, 5: 0, 6: 0} ## 技能组 -> 等级
var base_luck: int = 0

# ---- 局内 ----
var in_run := false
var depth: int = 1
var loot_mult: float = 1.0
## 局内背包：最多 backpack_slots 格，每格 {kind, count}；材料/碎片各自按堆叠上限叠放
var inventory: Array = []
var pending_loot: Array = [] ## 背包满时待取舍的新物品 [{kind, count}]
var run_loot: Dictionary:
	get:
		var d := {"material": 0, "shard": 0}
		for it in inventory:
			d[it.kind] += it.count
		return d
var run_id := ""
var log_path := "user://playtest_log.csv"
var player_hp: int = 100
var run_seed: int = 0
var floor_data: Dictionary = {}
var current_node: int = -1 ## -1 = 刚进入本层，尚未踏上节点
var last_result: Dictionary = {}
var clear_count: int = 0 ## 通关（假结局）次数

# ---- 测试钩子 ----
var auto_minigame: int = -1 ## >=0 时小游戏跳过操作直接给出该判定
var auto_skill: int = -1 ## >=0 时战斗自动选该技能（大招能量不足时退回普通攻击）；AUTO_SMART = 能量满放大招，否则普通攻击
const AUTO_SMART := 99
var battle_kind := "normal" ## 下一场战斗：normal / elite / boss

# ---- 时间倍率（C4 / v1.1 §4）----
var base_time_scale := 1.0 ## 测试用基准倍率；正常游玩为 1
var _judging := 0
var ff_label: Label

var debug_panel: CanvasLayer

func _ready() -> void:
	_setup_input()
	debug_panel = preload("res://scripts/debug_panel.gd").new()
	add_child(debug_panel)
	if OS.has_feature("web"):
		_setup_web_hooks()
	process_mode = Node.PROCESS_MODE_ALWAYS
	var hud := CanvasLayer.new()
	hud.layer = 90
	add_child(hud)
	ff_label = Label.new()
	ff_label.text = "▶▶ 2×"
	ff_label.position = Vector2(1720, 20)
	ff_label.add_theme_font_size_override("font_size", 36)
	ff_label.add_theme_color_override("font_color", Color(1, 0.85, 0.3))
	hud.add_child(ff_label)
	Settings.fast_forward_changed.connect(func(_on): apply_time_scale())
	apply_time_scale()

## 加速开关（Tab / Shift / 手柄 RT，按一下切换，状态持久化）
func _input(e: InputEvent) -> void:
	if e.is_action_pressed("fast_forward") and not e.is_echo():
		Settings.toggle_fast_forward()

func judge_begin() -> void:
	_judging += 1
	apply_time_scale()

func judge_end() -> void:
	_judging = maxi(0, _judging - 1)
	apply_time_scale()

func is_judging() -> bool:
	return _judging > 0

func apply_time_scale() -> void:
	var ff := Settings.fast_forward
	Engine.time_scale = 1.0 if _judging > 0 else base_time_scale * (tunables.fast_forward_scale if ff else 1.0)
	if ff_label:
		var s := get_tree().current_scene if is_inside_tree() else null
		var p := s.scene_file_path if s else ""
		ff_label.text = "▶▶ %s×" % str(snappedf(tunables.fast_forward_scale, 0.1)).trim_suffix(".0")
		ff_label.visible = ff and (p == SCN_BATTLE or p == SCN_DUNGEON)

func skills() -> Array:
	return [
		{"name": "斩击", "kind": "basic", "power": tunables.basic_power, "minigame": mg_timing},
		{"name": "节奏连斩", "kind": "ult", "power": tunables.ult_power, "minigame": mg_rhythm},
		{"name": "猜拳一击", "kind": "ult", "power": tunables.ult_power, "minigame": mg_rps},
		{"name": "命运骰击", "kind": "ult", "power": tunables.ult_power, "minigame": mg_dice},
	]

func all_minigames() -> Array:
	return [mg_timing, mg_defense[1], mg_defense[2], mg_rps, mg_dice, mg_rhythm]

func luck() -> int:
	return base_luck + int(skill_levels.get(5, 0))

## 角色特长加成（灰盒没有角色，固定 0；接口保留给难度公式）
func trait_bonus(_group: int) -> float:
	return 0.0

## 营地升级：判定窗口倍率（每级 +10%）。第 5 组升级改为幸运 +1，见 luck()
func window_mult(group: int) -> float:
	return 1.0 + float(skill_levels.get(group, 0)) * tunables.upgrade_window_bonus

func upgrade_cost(group: int) -> int:
	return tunables.upgrade_cost_base + int(skill_levels.get(group, 0)) * tunables.upgrade_cost_step

func can_upgrade(group: int) -> bool:
	return meta_materials >= upgrade_cost(group)

func upgrade(group: int) -> bool:
	if not can_upgrade(group):
		return false
	meta_materials -= upgrade_cost(group)
	skill_levels[group] = int(skill_levels.get(group, 0)) + 1
	return true

func minigame_context(cfg: MinigameConfig) -> Dictionary:
	return {"depth": depth, "luck": luck(), "trait_bonus": trait_bonus(cfg.group), "window_mult": window_mult(cfg.group)}

func goto(path: String) -> void:
	get_tree().change_scene_to_file.call_deferred(path)

# ---- 局流程 ----
func new_run() -> void:
	in_run = true
	depth = 1
	loot_mult = 1.0
	inventory = []
	pending_loot = []
	run_id = "%d_%d" % [Time.get_unix_time_from_system(), randi() % 10000]
	player_hp = tunables.player_max_hp
	run_seed = tunables.map_seed if tunables.map_seed >= 0 else randi()
	_gen_floor()

func is_final_floor() -> bool:
	return tunables.final_floor > 0 and depth >= tunables.final_floor

## 通关最终层（假结局占位）：战利品全部存入局外，迷宫重置，从第 1 层重新开始
func clear_dungeon() -> void:
	var loot := run_loot
	meta_materials += loot.material
	meta_shards += loot.shard
	clear_count += 1
	last_result = {"extracted": true, "cleared": true, "depth": depth, "material": loot.material, "material_lost": 0, "shard": loot.shard}
	var keep_hp := player_hp
	new_run()
	if tunables.map_seed >= 0:
		run_seed = tunables.map_seed + clear_count * 7919
		_gen_floor()
	player_hp = tunables.player_max_hp
	goto(SCN_DUNGEON)

func descend() -> void:
	depth += 1
	loot_mult += tunables.loot_bonus_per_depth
	_gen_floor()

func _gen_floor() -> void:
	floor_data = DungeonGen.generate(run_seed, depth, tunables)
	current_node = -1

## 按掉落倍率放入背包，返回实际数量。放不下的部分进入 pending_loot 等待取舍。
func add_loot(kind: String, base_amount: int) -> int:
	var n := int(round(base_amount * loot_mult))
	put_item(kind, n)
	return n

func stack_max(kind: String) -> int:
	return tunables.material_stack if kind == "material" else tunables.shard_stack

func put_item(kind: String, n: int) -> void:
	var left := n
	for it in inventory:
		if left <= 0:
			break
		if it.kind == kind and it.count < stack_max(kind):
			var add := mini(left, stack_max(kind) - it.count)
			it.count += add
			left -= add
	while left > 0:
		var c := mini(left, stack_max(kind))
		if inventory.size() < tunables.backpack_slots:
			inventory.append({"kind": kind, "count": c})
		else:
			pending_loot.append({"kind": kind, "count": c})
		left -= c

## 取舍：丢掉背包第 i 格，把第一个待取舍物品放进去
func discard_slot(i: int) -> void:
	if pending_loot.is_empty() or i < 0 or i >= inventory.size():
		return
	inventory.remove_at(i)
	var it: Dictionary = pending_loot.pop_front()
	put_item(it.kind, it.count)

## 取舍：放弃第一个待取舍物品
func discard_pending() -> void:
	if not pending_loot.is_empty():
		pending_loot.pop_front()

static func item_name(it: Dictionary) -> String:
	return ("材料" if it.kind == "material" else "记忆碎片") + " ×%d" % it.count

## 掉落：按概率决定是否掉、掉多少
func roll_drop(rate: float, amount: int, rng: RandomNumberGenerator) -> int:
	return amount if rng.randf() < rate else 0

func heal_rest(ratio: float = -1.0) -> int:
	var before := player_hp
	var r := tunables.rest_heal_ratio if ratio < 0 else ratio
	player_hp = mini(tunables.player_max_hp, player_hp + int(round(tunables.player_max_hp * r)))
	return player_hp - before

func start_battle() -> void:
	goto(SCN_BATTLE)

## extracted=true 撤离：全部带出；false 倒下：碎片全保留，材料丢一半（向下取整保留）
func end_run(extracted: bool) -> void:
	var loot := run_loot
	var mats: int = loot.material if extracted else int(floor(loot.material * (1.0 - tunables.knockdown_material_loss)))
	pending_loot = []
	last_result = {
		"extracted": extracted,
		"depth": depth,
		"material": mats,
		"material_lost": loot.material - mats,
		"shard": loot.shard,
	}
	in_run = false
	goto(SCN_RESULT)

func finish_result() -> void:
	meta_materials += int(last_result.get("material", 0))
	meta_shards += int(last_result.get("shard", 0))
	depth = 1
	goto(SCN_CAMP)

# ---- 输入映射（键盘 + 手柄）----
func _setup_input() -> void:
	# 菜单确认/返回也绑定手柄（引擎默认 ui_accept 不含手柄 A）
	_action("ui_accept", [], [JOY_BUTTON_A])
	_action("ui_cancel", [], [JOY_BUTTON_B])
	_action("mg_action", [KEY_SPACE, KEY_J, KEY_Z], [JOY_BUTTON_A])
	_action("mg_cancel", [KEY_K, KEY_X], [JOY_BUTTON_B])
	_action("debug_toggle", [KEY_F1, KEY_QUOTELEFT], [JOY_BUTTON_BACK])
	_action("move_left", [KEY_A, KEY_LEFT], [JOY_BUTTON_DPAD_LEFT], JOY_AXIS_LEFT_X, -1.0)
	_action("move_right", [KEY_D, KEY_RIGHT], [JOY_BUTTON_DPAD_RIGHT], JOY_AXIS_LEFT_X, 1.0)
	_action("move_up", [KEY_W, KEY_UP], [JOY_BUTTON_DPAD_UP], JOY_AXIS_LEFT_Y, -1.0)
	_action("move_down", [KEY_S, KEY_DOWN], [JOY_BUTTON_DPAD_DOWN], JOY_AXIS_LEFT_Y, 1.0)
	_action("target_prev", [KEY_Q], [JOY_BUTTON_LEFT_SHOULDER])
	_action("target_next", [KEY_E], [JOY_BUTTON_RIGHT_SHOULDER])
	_action("fast_forward", [KEY_TAB, KEY_SHIFT], [], JOY_AXIS_TRIGGER_RIGHT, 1.0)
	# Tab 用作加速，不再用于界面焦点切换
	for a in ["ui_focus_next", "ui_focus_prev"]:
		for ev in InputMap.action_get_events(a):
			if ev is InputEventKey and (ev.keycode == KEY_TAB or ev.physical_keycode == KEY_TAB):
				InputMap.action_erase_event(a, ev)

func _action(name: String, keys: Array, buttons: Array, axis: int = -1, axis_val: float = 0.0) -> void:
	if not InputMap.has_action(name):
		InputMap.add_action(name, 0.4)
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

# ---- 试玩数据记录（T10）----
const LOG_HEADER := "time,run_id,depth,minigame,group,kind,result,score,judge_sec,total_sec,auto"

func log_minigame(cfg: MinigameConfig, ctx: Dictionary, result: int, score: float, judge_sec: float, total_sec: float) -> void:
	if not tunables.log_enabled:
		return
	var exists := FileAccess.file_exists(log_path)
	var f := FileAccess.open(log_path, FileAccess.READ_WRITE if exists else FileAccess.WRITE)
	if f == null:
		push_warning("无法写入 %s" % log_path)
		return
	if exists:
		f.seek_end()
	else:
		f.store_line(LOG_HEADER)
	f.store_line("%s,%s,%d,%s,%d,%s,%s,%.3f,%.3f,%.3f,%d" % [Time.get_datetime_string_from_system(), run_id, int(ctx.get("depth", depth)), cfg.id, cfg.group, cfg.kind, MinigameBase.RESULT_NAMES[result], score, judge_sec, total_sec, 1 if int(ctx.get("auto", -1)) >= 0 else 0])
	f.close()

## 网页版：把 CSV 作为文件下载到浏览器（user:// 在网页里存于 IndexedDB，玩家拿不到）
func download_log() -> bool:
	if not FileAccess.file_exists(log_path):
		return false
	var bytes := FileAccess.get_file_as_bytes(log_path)
	if OS.has_feature("web"):
		JavaScriptBridge.download_buffer(bytes, "playtest_log.csv", "text/csv")
		return true
	return false

# 网页调试钩子：浏览器控制台里可用 greybox.downloadCsv() / greybox.selftestRow() / greybox.currentScene
var _js_cbs: Array = []
var _js_obj = null
var _js_scene := ""
func _setup_web_hooks() -> void:
	var win = JavaScriptBridge.get_interface("window")
	if win == null:
		return
	var obj = JavaScriptBridge.create_object("Object")
	var cb_dl = JavaScriptBridge.create_callback(func(_a): download_log())
	var cb_row = JavaScriptBridge.create_callback(func(_a): log_minigame(mg_rps, {"depth": depth, "auto": 9}, MinigameBase.Result.GOOD, 0.5, 1.0, 1.7))
	_js_cbs = [cb_dl, cb_row]
	obj.downloadCsv = cb_dl
	obj.selftestRow = cb_row
	win.greybox = obj
	_js_obj = obj

## 网页版：把当前场景写到 window.greybox.currentScene（JS 回调拿不到返回值）
func _process(_d: float) -> void:
	apply_time_scale()
	if _js_obj != null:
		var s := get_tree().current_scene
		var path := s.scene_file_path if s else ""
		if path != _js_scene:
			_js_scene = path
			_js_obj.currentScene = path

func clear_log() -> void:
	if FileAccess.file_exists(log_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(log_path))
