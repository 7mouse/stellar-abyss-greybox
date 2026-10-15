extends Control
## 回合制战斗：1 名主角 vs 1~3 个敌人（或 1 个精英/首领），按速度排序轮流行动。
## 我方：普通攻击 = 时机条（攒能量），大招 = 完整小游戏（能量满可用）。
## 敌人：每次行动 = 1 个敌人回合 = 最多 1 次防御小游戏；精英/首领每回合行动 actions_per_round 次。

signal skill_chosen(skill: Dictionary)
signal battle_ended(outcome: String)
signal energy_changed(v: int)

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
var drops := {"material": 0, "shard": 0}
var kind := "normal" ## normal / elite / boss
var energy := 0
var energy_boxes: Array = []
var skill_buttons: Array = [] ## [{skill, button}]
var player_turns := 0
var enemy_actions := 0
var last_basic_latency := -1.0 ## 选定普通攻击 → 伤害飘字 的秒数（1 倍速口径）
var _skill_t0 := 0
var last_float: Label
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
	kind = GameState.battle_kind
	GameState.battle_kind = "normal"
	if kind == "normal":
		var cnt := _weighted_count(t.enemy_count_weights)
		for i in cnt:
			var d: EnemyData = GameState.enemy_types[rng.randi_range(0, GameState.enemy_types.size() - 1)]
			var hp := roundi(d.max_hp * (1.0 + (GameState.depth - 1) * t.enemy_hp_per_depth) * (t.trio_hp_mult if cnt == 3 else 1.0))
			var atk := roundi(d.attack * (1.0 + (GameState.depth - 1) * t.enemy_atk_per_depth) * (t.floor3_atk_mult if GameState.is_final_floor() else 1.0))
			_add_enemy(d, hp, atk, i)
	else:
		# 精英/首领：不吃层数成长与第 3 层系数
		var d: EnemyData = GameState.elite_data if kind == "elite" else GameState.boss_data
		_add_enemy(d, d.max_hp, d.attack, 0, Vector2(220, 300))
	UI.label(self, "能量", Vector2(300, 760 - 50), 24)
	for i in t.energy_max:
		energy_boxes.append(UI.rect(self, Vector2(370 + i * 50, 718), Vector2(40, 24), Color(0.25, 0.25, 0.3)))
	marker = UI.rect(self, Vector2.ZERO, Vector2(40, 24), Color(1, 0.9, 0.2))
	menu = VBoxContainer.new()
	menu.position = Vector2(300, 800)
	add_child(menu)
	for s in GameState.skills():
		var tag := "普通攻击" if s.kind == "basic" else "大招·需满能量"
		var b := UI.button(menu, "%s（%s · 威力 %d · %s）" % [s.name, tag, s.power, s.minigame.display_name], _on_skill.bind(s), Vector2(760, 56))
		b.focus_neighbor_left = b.get_path()
		b.focus_neighbor_right = b.get_path()
		skill_buttons.append({"skill": s, "button": b})
	UI.label(self, "↑↓ 选技能   ←→/Q E/LB RB 选目标   空格/手柄A 确认", Vector2(1000, 1000), 24, Color(0.7, 0.7, 0.7))
	menu.visible = false
	_refresh()
	_run_loop()

func _add_enemy(d: EnemyData, hp: int, atk: int, i: int, size := Vector2(150, 200)) -> void:
	var e := _make_actor(d.display_name, hp, hp, d.speed, atk, Vector2(1020 + i * 300, 720 - size.y), size, d.color)
	e.data = d
	e.is_player = false
	e.action_i = 0
	enemies.append(e)

## 按权重返回 1、2 或 3
func _weighted_count(w: PackedFloat32Array) -> int:
	var tot := 0.0
	for x in w:
		tot += maxf(0.0, x)
	if tot <= 0.0:
		return 1
	var r := rng.randf() * tot
	for i in w.size():
		r -= maxf(0.0, w[i])
		if r < 0.0:
			return i + 1
	return w.size()

func can_use(skill: Dictionary) -> bool:
	return skill.get("kind", "basic") != "ult" or energy >= GameState.tunables.energy_max

func set_energy(v: int) -> void:
	energy = clampi(v, 0, GameState.tunables.energy_max)
	energy_changed.emit(energy)
	_refresh()

func _make_actor(n: String, hp: int, max_hp: int, spd: int, atk: int, pos: Vector2, size: Vector2, color: Color) -> Dictionary:
	var r := UI.rect(self, pos, size, color)
	var l := UI.label(self, "", pos + Vector2(-20, -80), 20)
	return {"name": n, "hp": hp, "max_hp": max_hp, "speed": spd, "atk": atk, "rect": r, "label": l}

func alive_enemies() -> Array:
	return enemies.filter(func(e): return e.hp > 0)

func turn_order() -> Array:
	var order: Array = [player] + alive_enemies()
	order.sort_custom(func(a, b): return a.speed > b.speed)
	return order

## 敌人 -> 防御小游戏组：defense_groups 非空时按顺序轮流；否则 近战连击=第1组，追踪弹=第2组，均衡=随机
func group_for(e: Dictionary) -> int:
	var gs: Array = e.data.defense_groups
	if not gs.is_empty():
		var g: int = gs[int(e.get("action_i", 0)) % gs.size()]
		e.action_i = int(e.get("action_i", 0)) + 1
		return g
	match e.data.pattern:
		EnemyData.Pattern.MELEE_COMBO: return 1
		EnemyData.Pattern.TRACKER: return 2
	return rng.randi_range(1, 2)

## is_attack=true：大招倍率（atk_mult_*）；false：防御倍率。普通攻击用 calc_basic_damage
static func calc_damage(base: int, result: int, is_attack: bool) -> int:
	var t: Tunables = GameState.tunables
	var m := t.attack_mult(result) if is_attack else t.defense_mult(result)
	return roundi(base * m)

static func calc_basic_damage(base: int, result: int) -> int:
	return roundi(base * GameState.tunables.qte_mult(result))

func _run_loop() -> void:
	await get_tree().process_frame
	set_energy(0) # 能量不跨战斗
	_log(("遭遇 %d 个敌人！" % enemies.size()) if kind == "normal" else ("强敌出现：%s！" % enemies[0].name))
	while not ended:
		for a in turn_order():
			if ended or a.hp <= 0:
				continue
			if a.get("is_player", false):
				await _player_turn()
			else:
				# 每次行动是一个独立的敌人回合
				for k in maxi(1, a.data.actions_per_round):
					if player.hp <= 0 or a.hp <= 0:
						break
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
	var sk: Array = GameState.skills()
	if GameState.auto_skill >= 0:
		await get_tree().process_frame
		if GameState.auto_skill == GameState.AUTO_SMART:
			skill = sk[1] if can_use(sk[1]) else sk[0]
		else:
			skill = sk[clampi(GameState.auto_skill, 0, sk.size() - 1)]
			if not can_use(skill):
				skill = sk[0]
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
	_skill_t0 = Time.get_ticks_usec()
	var res: Array = await _play_minigame(skill.minigame)
	var dmg := 0
	if skill.kind == "ult":
		dmg = calc_damage(skill.power, res[0], true)
		set_energy(0)
	else:
		dmg = calc_basic_damage(skill.power, res[0])
		set_energy(energy + GameState.tunables.energy_per_basic)
	player_turns += 1
	target.hp = maxi(0, target.hp - dmg)
	_record(player, target, res[0], skill.power, dmg, "attack", skill.minigame.group, skill.kind)
	if skill.kind == "basic":
		last_basic_latency = (Time.get_ticks_usec() - _skill_t0) / 1e6 * Engine.time_scale
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
	enemy_actions += 1
	if res[0] == MG.PERFECT:
		set_energy(energy + GameState.tunables.energy_per_perfect_def)
	_record(e, player, res[0], e.atk, dmg, "defense", g)
	_log("%s 的攻击：防御%s，受到 %d 伤害" % [e.name, MinigameBase.RESULT_CN[res[0]], dmg])

func _play_minigame(cfg: MinigameConfig) -> Array:
	var mg: MinigameBase = load(cfg.scene_path).instantiate()
	add_child(mg)
	var ctx := GameState.minigame_context(cfg)
	if GameState.auto_minigame >= 0:
		ctx["auto"] = GameState.auto_minigame
	mg.start(cfg, ctx)
	var res: Array = await mg.finished
	mg.queue_free()
	return res

func _record(src: Dictionary, dst: Dictionary, result: int, base: int, amount: int, kind: String, group: int, skill_kind := "") -> void:
	damage_events.append({"src": src.name, "dst": dst.name, "result": result, "base": base, "amount": amount, "kind": kind, "group": group, "skill_kind": skill_kind})
	var colors := [Color(0.3, 1, 0.4), Color(1, 0.9, 0.3), Color(1, 0.4, 0.3)]
	var l := UI.label(self, "%s  -%d" % [MinigameBase.RESULT_NAMES[result], amount], dst.rect.position + Vector2(-10, -140), 44, colors[result])
	l.name = "DamageFloat%d" % float_count
	l.custom_minimum_size = Vector2(320, 0) # 预留 3 位数宽度
	l.clip_text = false
	float_count += 1
	last_float = l
	var tw := create_tween() # 不阻塞下一个行动
	tw.tween_property(l, "position:y", l.position.y - 60, 0.6)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 0.6)
	tw.tween_callback(l.queue_free)
	_refresh()

func _end(o: String) -> void:
	ended = true
	outcome = o
	GameState.player_hp = player.hp
	if o == "win":
		var t := GameState.tunables
		var mats := 0
		var shards := 0
		var units := enemies.size()
		if kind == "elite":
			units = t.elite_drop_units
		elif kind == "boss":
			units = t.boss_drop_units
		for i in units:
			mats += GameState.roll_drop(t.battle_drop_rate, t.battle_material_drop, rng)
			shards += GameState.roll_drop(t.battle_shard_rate, 1, rng)
		var m := GameState.add_loot("material", mats) if mats > 0 else 0
		var s := GameState.add_loot("shard", shards) if shards > 0 else 0
		drops = {"material": m, "shard": s}
		_log("战斗胜利！获得材料 %d，记忆碎片 %d" % [m, s])
	else:
		_log("主角倒下了……")
	battle_ended.emit(o)
	await get_tree().create_timer(0.6).timeout
	if o == "win":
		GameState.goto(GameState.SCN_DUNGEON)
	else:
		GameState.end_run(false)

func _on_skill(s: Dictionary) -> void:
	if choosing and can_use(s):
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
		a.label.text = ("%s\nHP %d/%d  速度 %d" % [a.name, a.hp, a.max_hp, a.speed]) + ("" if a.get("is_player", false) else "  攻击 %d" % a.atk)
		a.rect.modulate = Color(1, 1, 1, 0.25) if a.hp <= 0 else Color.WHITE
	for i in energy_boxes.size():
		energy_boxes[i].color = Color(0.3, 0.85, 1.0) if i < energy else Color(0.25, 0.25, 0.3)
	for sb in skill_buttons:
		var ok := can_use(sb.skill)
		sb.button.disabled = not ok
		sb.button.focus_mode = Control.FOCUS_ALL if ok else Control.FOCUS_NONE
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
