extends Control
## 回合制战斗：1 名主角 vs 1~3 个敌人，按速度排序轮流行动。

signal skill_chosen(skill: Dictionary)
signal battle_ended(outcome: String)

const MG := MinigameBase.Result

var rng := RandomNumberGenerator.new()
var player := {}
var enemies: Array = []
var selected := 0
var choosing := false
var ended := false
var outcome := ""
var damage_events: Array = [] ## {src, dst, result, base, amount, kind, group}
var float_count := 0
var menu: VBoxContainer
var log_label: Label
var marker: ColorRect

func _ready() -> void:
	var t := GameState.tunables
	rng.seed = hash([GameState.run_seed, GameState.depth, GameState.current_node, "battle"])
	UI.rect(self, Vector2.ZERO, Vector2(1920, 1080), Color(0.13, 0.11, 0.12))
	UI.rect(self, Vector2(0, 760), Vector2(1920, 6), Color(0.4, 0.4, 0.4))
	log_label = UI.label(self, "", Vector2(60, 40), 32)
	player = _make_actor("主角", GameState.player_hp, t.player_max_hp, t.player_speed, 0, Vector2(300, 480), Vector2(140, 260), Color(0.25, 0.55, 0.95))
	player.is_player = true
	var cnt := clampi(rng.randi_range(t.enemy_min, mini(t.enemy_max, t.enemy_min + GameState.depth)), 1, 3)
	for i in cnt:
		var d: EnemyData = GameState.enemy_types[rng.randi_range(0, GameState.enemy_types.size() - 1)]
		var hp := roundi(d.max_hp * (1.0 + (GameState.depth - 1) * t.enemy_hp_per_depth))
		var atk := roundi(d.attack * (1.0 + (GameState.depth - 1) * t.enemy_atk_per_depth))
		var e := _make_actor(d.display_name, hp, hp, d.speed, atk, Vector2(1050 + i * 280, 520), Vector2(150, 200), d.color)
		e.data = d
		e.is_player = false
		enemies.append(e)
	marker = UI.rect(self, Vector2.ZERO, Vector2(40, 24), Color(1, 0.9, 0.2))
	menu = VBoxContainer.new()
	menu.position = Vector2(300, 800)
	add_child(menu)
	for s in GameState.skills():
		var b := UI.button(menu, "%s（威力 %d · %s）" % [s.name, s.power, s.minigame.display_name], _on_skill.bind(s), Vector2(620, 70))
		b.focus_neighbor_left = b.get_path()
		b.focus_neighbor_right = b.get_path()
	UI.label(self, "↑↓ 选技能   ←→/Q E/LB RB 选目标   空格/手柄A 确认", Vector2(1000, 1000), 24, Color(0.7, 0.7, 0.7))
	menu.visible = false
	_refresh()
	_run_loop()

func _make_actor(n: String, hp: int, max_hp: int, spd: int, atk: int, pos: Vector2, size: Vector2, color: Color) -> Dictionary:
	var r := UI.rect(self, pos, size, color)
	var l := UI.label(self, "", pos + Vector2(-20, -90), 24)
	return {"name": n, "hp": hp, "max_hp": max_hp, "speed": spd, "atk": atk, "rect": r, "label": l}

func alive_enemies() -> Array:
	return enemies.filter(func(e): return e.hp > 0)

func turn_order() -> Array:
	var order: Array = [player] + alive_enemies()
	order.sort_custom(func(a, b): return a.speed > b.speed)
	return order

## 敌人类型 -> 防御小游戏组：近战连击=第1组，追踪弹=第2组，均衡=随机
func group_for(e: Dictionary) -> int:
	match e.data.pattern:
		EnemyData.Pattern.MELEE_COMBO: return 1
		EnemyData.Pattern.TRACKER: return 2
	return rng.randi_range(1, 2)

static func calc_damage(base: int, result: int, is_attack: bool) -> int:
	var t: Tunables = GameState.tunables
	var m := t.attack_mult(result) if is_attack else t.defense_mult(result)
	return roundi(base * m)

func _run_loop() -> void:
	await get_tree().process_frame
	_log("遭遇 %d 个敌人！" % enemies.size())
	while not ended:
		for a in turn_order():
			if ended or a.hp <= 0:
				continue
			if a.get("is_player", false):
				await _player_turn()
			else:
				await _enemy_turn(a)
			_refresh()
			if alive_enemies().is_empty():
				await _end("win")
				return
			if player.hp <= 0:
				await _end("lose")
				return

func _player_turn() -> void:
	_log("主角的回合：选择技能")
	var skill: Dictionary
	if GameState.auto_skill >= 0:
		await get_tree().process_frame
		skill = GameState.skills()[GameState.auto_skill]
	else:
		menu.visible = true
		choosing = true
		_refresh()
		menu.get_child(0).grab_focus()
		skill = await skill_chosen
		choosing = false
		menu.visible = false
	var alive := alive_enemies()
	var target: Dictionary = alive[clampi(selected, 0, alive.size() - 1)]
	var res: Array = await _play_minigame(skill.minigame)
	var dmg := calc_damage(skill.power, res[0], true)
	target.hp = maxi(0, target.hp - dmg)
	_record(player, target, res[0], skill.power, dmg, "attack", 0)
	_log("%s → %s：%s，造成 %d 伤害" % [skill.name, target.name, MinigameBase.RESULT_CN[res[0]], dmg])

func _enemy_turn(e: Dictionary) -> void:
	var g := group_for(e)
	_log("%s 准备出招！（第 %d 组防御）" % [e.name, g])
	var res: Array = await _play_minigame(GameState.mg_defense[g])
	var dmg := calc_damage(e.atk, res[0], false)
	if GameState.tunables.god_mode:
		dmg = 0
	player.hp = maxi(0, player.hp - dmg)
	GameState.player_hp = player.hp
	_record(e, player, res[0], e.atk, dmg, "defense", g)
	_log("%s 的攻击：防御%s，受到 %d 伤害" % [e.name, MinigameBase.RESULT_CN[res[0]], dmg])

func _play_minigame(cfg: MinigameConfig) -> Array:
	var mg: MinigameBase = load(cfg.scene_path).instantiate()
	add_child(mg)
	var ctx := {"depth": GameState.depth, "luck": GameState.luck(), "trait_bonus": GameState.trait_bonus(cfg.group)}
	if GameState.auto_minigame >= 0:
		ctx["auto"] = GameState.auto_minigame
	mg.start(cfg, ctx)
	var res: Array = await mg.finished
	mg.queue_free()
	return res

func _record(src: Dictionary, dst: Dictionary, result: int, base: int, amount: int, kind: String, group: int) -> void:
	damage_events.append({"src": src.name, "dst": dst.name, "result": result, "base": base, "amount": amount, "kind": kind, "group": group})
	var colors := [Color(0.3, 1, 0.4), Color(1, 0.9, 0.3), Color(1, 0.4, 0.3)]
	var l := UI.label(self, "%s  -%d" % [MinigameBase.RESULT_NAMES[result], amount], dst.rect.position + Vector2(-10, -140), 44, colors[result])
	l.name = "DamageFloat%d" % float_count
	float_count += 1
	var tw := create_tween()
	tw.tween_property(l, "position:y", l.position.y - 80, 1.2)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 1.2)
	tw.tween_callback(l.queue_free)
	_refresh()

func _end(o: String) -> void:
	ended = true
	outcome = o
	GameState.player_hp = player.hp
	if o == "win":
		var m := GameState.add_loot("material", GameState.tunables.battle_material_drop * enemies.size())
		_log("战斗胜利！获得材料 %d" % m)
	else:
		_log("主角倒下了……")
	battle_ended.emit(o)
	await get_tree().create_timer(1.0).timeout
	if o == "win":
		GameState.goto(GameState.SCN_DUNGEON)
	else:
		GameState.end_run(false)

func _on_skill(s: Dictionary) -> void:
	if choosing:
		skill_chosen.emit(s)

func _input(e: InputEvent) -> void:
	if not choosing:
		return
	var n := alive_enemies().size()
	if e.is_action_pressed("ui_left") or e.is_action_pressed("target_prev"):
		selected = (selected - 1 + n) % n
		get_viewport().set_input_as_handled()
		_refresh()
	elif e.is_action_pressed("ui_right") or e.is_action_pressed("target_next"):
		selected = (selected + 1) % n
		get_viewport().set_input_as_handled()
		_refresh()

func _refresh() -> void:
	for a in [player] + enemies:
		a.label.text = "%s\nHP %d/%d  速度 %d" % [a.name, a.hp, a.max_hp, a.speed]
		a.rect.modulate = Color(1, 1, 1, 0.25) if a.hp <= 0 else Color.WHITE
	var alive := alive_enemies()
	if alive.is_empty():
		marker.visible = false
		return
	selected = clampi(selected, 0, alive.size() - 1)
	var t: Dictionary = alive[selected]
	marker.visible = choosing
	marker.position = t.rect.position + Vector2(t.rect.size.x / 2 - 20, -130)

func _log(s: String) -> void:
	log_label.text = s
	print("[战斗] ", s)
