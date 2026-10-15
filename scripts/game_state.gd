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
var run_loot := {"material": 0, "shard": 0} ## 局内背包（T8 再改为 12 格）
var player_hp: int = 100
var run_seed: int = 0
var floor_data: Dictionary = {}
var current_node: int = -1 ## -1 = 刚进入本层，尚未踏上节点
var last_result: Dictionary = {}

# ---- 测试钩子 ----
var auto_minigame: int = -1 ## >=0 时小游戏跳过操作直接给出该判定
var auto_skill: int = -1 ## >=0 时战斗自动选该技能

var debug_panel: CanvasLayer

func _ready() -> void:
	_setup_input()
	debug_panel = preload("res://scripts/debug_panel.gd").new()
	add_child(debug_panel)

func skills() -> Array:
	return [
		{"name": "节奏连斩", "power": tunables.slash_power, "minigame": mg_rhythm},
		{"name": "猜拳一击", "power": tunables.rps_power, "minigame": mg_rps},
		{"name": "命运骰击", "power": tunables.heavy_power, "minigame": mg_dice},
	]

func all_minigames() -> Array:
	return [mg_defense[1], mg_defense[2], mg_rps, mg_dice, mg_rhythm]

func luck() -> int:
	return base_luck + int(skill_levels.get(5, 0))

func trait_bonus(group: int) -> float:
	return float(skill_levels.get(group, 0)) * tunables.trait_bonus_per_level

func goto(path: String) -> void:
	get_tree().change_scene_to_file.call_deferred(path)

# ---- 局流程 ----
func new_run() -> void:
	in_run = true
	depth = 1
	loot_mult = 1.0
	run_loot = {"material": 0, "shard": 0}
	player_hp = tunables.player_max_hp
	run_seed = tunables.map_seed if tunables.map_seed >= 0 else randi()
	_gen_floor()

func descend() -> void:
	depth += 1
	loot_mult += tunables.loot_bonus_per_depth
	_gen_floor()

func _gen_floor() -> void:
	floor_data = DungeonGen.generate(run_seed, depth, tunables)
	current_node = -1

func add_loot(kind: String, base_amount: int) -> int:
	var n := int(round(base_amount * loot_mult))
	run_loot[kind] = int(run_loot.get(kind, 0)) + n
	return n

func heal_rest() -> int:
	var before := player_hp
	player_hp = mini(tunables.player_max_hp, player_hp + int(round(tunables.player_max_hp * tunables.rest_heal_ratio)))
	return player_hp - before

func start_battle() -> void:
	goto(SCN_BATTLE)

## extracted=true 撤离；false 倒下。倒下惩罚在 T8 实装，目前战利品原样带出。
func end_run(extracted: bool) -> void:
	last_result = {
		"extracted": extracted,
		"depth": depth,
		"material": run_loot.material,
		"shard": run_loot.shard,
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
	_action("mg_action", [KEY_SPACE, KEY_J, KEY_Z], [JOY_BUTTON_A])
	_action("mg_cancel", [KEY_K, KEY_X], [JOY_BUTTON_B])
	_action("debug_toggle", [KEY_F1], [JOY_BUTTON_BACK])
	_action("move_left", [KEY_A, KEY_LEFT], [JOY_BUTTON_DPAD_LEFT], JOY_AXIS_LEFT_X, -1.0)
	_action("move_right", [KEY_D, KEY_RIGHT], [JOY_BUTTON_DPAD_RIGHT], JOY_AXIS_LEFT_X, 1.0)
	_action("move_up", [KEY_W, KEY_UP], [JOY_BUTTON_DPAD_UP], JOY_AXIS_LEFT_Y, -1.0)
	_action("move_down", [KEY_S, KEY_DOWN], [JOY_BUTTON_DPAD_DOWN], JOY_AXIS_LEFT_Y, 1.0)
	_action("target_prev", [KEY_Q], [JOY_BUTTON_LEFT_SHOULDER])
	_action("target_next", [KEY_E], [JOY_BUTTON_RIGHT_SHOULDER])

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
