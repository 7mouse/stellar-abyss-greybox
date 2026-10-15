extends Node
## T1~T3 自动验收。运行：godot --headless res://tests/test_main.tscn
## 退出码 0 = 全部通过。

const R := MinigameBase.Result
var passes := 0
var fails := 0

func check(cond: bool, msg: String) -> void:
	if cond:
		passes += 1
		print("  [PASS] ", msg)
	else:
		fails += 1
		printerr("  [FAIL] ", msg)

func _ready() -> void:
	Engine.time_scale = 20.0
	get_tree().create_timer(900.0, true, false, true).timeout.connect(func():
		printerr("[FAIL] 超时"); get_tree().quit(2))
	_run()

func battle_outcome(b) -> String:
	if b.ended:
		return b.outcome
	return await b.battle_ended

func scene() -> Node:
	return get_tree().current_scene

func wait_scene(path: String, timeout := 30.0) -> bool:
	var t := 0.0
	while t < timeout:
		var s := scene()
		if s and s.scene_file_path == path and s.is_node_ready():
			await get_tree().process_frame
			return true
		await get_tree().process_frame
		t += get_process_delta_time()
	return false

## 在当前迷宫层走到某类型节点（BFS 最短路径），沿途处理弹窗与战斗。返回是否到达。
func walk_to(type: String) -> bool:
	for _step in 30:
		var d = scene()
		if d.scene_file_path != GameState.SCN_DUNGEON:
			return false
		var path := _bfs(GameState.floor_data, GameState.current_node, type)
		if path.is_empty():
			return false
		var nid: int = path[0]
		d.visit(nid)
		var nd: Dictionary = GameState.floor_data.nodes[nid]
		if nd.type == "combat":
			if not await wait_scene(GameState.SCN_BATTLE):
				return false
			var b = scene()
			var o = await battle_outcome(b)
			if o != "win":
				return false
			if not await wait_scene(GameState.SCN_DUNGEON):
				return false
		elif nd.type != "exit":
			if d.popup_kind == "message":
				d.dismiss_message()
		if nd.type == type:
			return true
	return false

func _bfs(fd: Dictionary, cur: int, type: String) -> Array:
	var q: Array = []
	var prev := {}
	for s in DungeonGen.reachable_from(fd, cur):
		q.append(s)
		prev[s] = -1
	while not q.is_empty():
		var n: int = q.pop_front()
		if fd.nodes[n].type == type:
			var p: Array = [n]
			while prev[p[0]] != -1:
				p.push_front(prev[p[0]])
			return p
		for m in fd.nodes[n].next:
			if not prev.has(m):
				prev[m] = n
				q.append(m)
	return []

func _run() -> void:
	await get_tree().process_frame
	var t := GameState.tunables
	t.map_seed = 12345
	GameState.auto_minigame = R.PERFECT
	GameState.auto_skill = 0

	print("== 通用约定 ==")
	var mgs: MinigameConfig = GameState.mg_rhythm
	check(absf(MinigameBase.compute_difficulty(mgs, {"depth": 2, "trait_bonus": 0.5}) - (t.base_difficulty + 2 * t.depth_scale - 0.5)) < 0.001, "难度公式 = base + depth*scale − trait_bonus")
	check(ProjectSettings.get_setting("display/window/size/viewport_width") == 1920 and ProjectSettings.get_setting("display/window/size/viewport_height") == 1080, "基准分辨率 1920x1080")
	for a in ["mg_action", "debug_toggle", "move_left", "move_up"]:
		var has_key := false
		var has_joy := false
		for e in InputMap.action_get_events(a):
			has_key = has_key or e is InputEventKey
			has_joy = has_joy or e is InputEventJoypadButton or e is InputEventJoypadMotion
		check(has_key and has_joy, "输入 %s 同时有键盘和手柄映射" % a)
	await test_minigames()
	# 调试面板
	GameState.debug_panel.toggle()
	check(GameState.debug_panel.is_open(), "F1 调试面板可打开")
	GameState.debug_panel.toggle()

	print("== T2 迷宫生成 ==")
	var gen_ok := true
	var types_ok := true
	var reach_ok := true
	var seen_types := {}
	for sd in 60:
		for dp in [1, 2, 3]:
			var fd := DungeonGen.generate(sd, dp, t)
			var n: int = fd.nodes.size()
			gen_ok = gen_ok and n >= 8 and n <= 10
			var exits := 0
			for nd in fd.nodes:
				seen_types[nd.type] = true
				types_ok = types_ok and nd.type in ["combat", "chest", "event", "rest", "exit"]
				if nd.type == "exit":
					exits += 1
				# 每个节点都能走到出口
				reach_ok = reach_ok and (nd.type == "exit" or not _bfs(fd, nd.id, "exit").is_empty())
			gen_ok = gen_ok and exits == 1
			reach_ok = reach_ok and not _bfs(fd, -1, "exit").is_empty()
	check(gen_ok, "360 次生成：每层 8~10 个节点、恰好 1 个出口")
	check(types_ok and seen_types.size() == 5, "节点类型覆盖 战斗/宝箱/事件/休息/出口")
	check(reach_ok, "所有节点均可到达出口（无死路）")
	check(var_to_str(DungeonGen.generate(777, 1, t)) == var_to_str(DungeonGen.generate(777, 1, t)), "固定种子可复现")
	check(var_to_str(DungeonGen.generate(777, 1, t)) != var_to_str(DungeonGen.generate(778, 1, t)), "不同种子结果不同")
	GameState.new_run()
	GameState.player_hp = 50
	var healed := GameState.heal_rest()
	check(healed == 30 and GameState.player_hp == 80, "休息回复 30%% 最大生命（50→%d）" % GameState.player_hp)

	print("== T1 场景流转 Camp→Dungeon→Battle→Dungeon→Result→Camp ==")
	GameState.goto(GameState.SCN_CAMP)
	check(await wait_scene(GameState.SCN_CAMP), "进入营地")
	scene().enter_dungeon()
	check(await wait_scene(GameState.SCN_DUNGEON), "营地 → 迷宫")
	check(GameState.depth == 1 and GameState.in_run, "新一局从第 1 层开始")
	var fd1 := GameState.floor_data
	var cpath := _bfs(fd1, -1, "combat")
	for i in cpath.size() - 1:
		scene().visit(cpath[i])
		if scene().popup_kind == "message":
			scene().dismiss_message()
	scene().visit(cpath[-1])
	check(await wait_scene(GameState.SCN_BATTLE), "迷宫 → 战斗")
	var battle = scene()
	var o = await battle_outcome(battle)
	check(o == "win", "战斗胜利（自动 PERFECT）")
	check(await wait_scene(GameState.SCN_DUNGEON), "战斗 → 迷宫")
	check(GameState.floor_data.nodes[cpath[-1]].visited and GameState.current_node == cpath[-1], "回到迷宫后保留进度")
	check(await walk_to("exit"), "走到出口")
	check(scene().popup_kind == "exit", "出口弹出二选一")
	var mats_before := GameState.meta_materials
	var run_mats: int = GameState.run_loot.material
	scene().choose_withdraw()
	check(await wait_scene(GameState.SCN_RESULT), "撤离 → 结算")
	check(GameState.last_result.extracted == true, "结算记录为撤离")
	scene().back_to_camp()
	check(await wait_scene(GameState.SCN_CAMP), "结算 → 营地")
	check(GameState.meta_materials == mats_before + run_mats and run_mats > 0, "撤离带出全部材料（%d）" % run_mats)

	print("== T2 两层走通 + 撤离/继续深入 ==")
	scene().enter_dungeon()
	await wait_scene(GameState.SCN_DUNGEON)
	check(await walk_to("exit"), "第 1 层走到出口")
	scene().choose_descend()
	await get_tree().process_frame
	check(await wait_scene(GameState.SCN_DUNGEON), "继续深入 → 新的迷宫层")
	check(GameState.depth == 2 and absf(GameState.loot_mult - 1.25) < 0.001, "层数 +1（%d），掉落倍率 125%%" % GameState.depth)
	check(GameState.floor_data.depth == 2 and GameState.current_node == -1, "第 2 层重新生成，从入口开始")
	var m_before: int = GameState.run_loot.material
	check(await walk_to("exit"), "第 2 层走到出口")
	check(GameState.run_loot.material >= m_before, "第 2 层掉落按倍率累计")
	scene().choose_withdraw()
	check(await wait_scene(GameState.SCN_RESULT), "第 2 层撤离 → 结算")
	check(GameState.last_result.depth == 2, "结算显示到达第 2 层")
	scene().back_to_camp()
	await wait_scene(GameState.SCN_CAMP)
	scene().enter_dungeon()
	await wait_scene(GameState.SCN_DUNGEON)
	check(GameState.depth == 1, "撤离后下一局从第 1 层开始")

	print("== T3 回合制战斗 ==")
	check(Battle_calc(10, R.PERFECT, true) == 15 and Battle_calc(10, R.GOOD, true) == 10 and Battle_calc(10, R.FAIL, true) == 5, "攻击伤害 150%/100%/50%")
	check(Battle_calc(10, R.PERFECT, false) == 0 and Battle_calc(10, R.GOOD, false) == 5 and Battle_calc(10, R.FAIL, false) == 10, "防御受伤 0/50%/100%")
	var counts := {}
	var dmg_by_result := {}
	for res in [R.PERFECT, R.GOOD, R.FAIL]:
		GameState.auto_minigame = res
		GameState.player_hp = 100000 # 保证打完
		GameState.start_battle()
		await wait_scene(GameState.SCN_BATTLE)
		var b = scene()
		counts[b.enemies.size()] = true
		var ord: Array = b.turn_order()
		var sorted := true
		for i in ord.size() - 1:
			sorted = sorted and ord[i].speed >= ord[i + 1].speed
		check(sorted, "[%s] 行动顺序按速度降序" % MinigameBase.RESULT_NAMES[res])
		var oc = await battle_outcome(b)
		check(oc == "win", "[%s] 战斗完整打完" % MinigameBase.RESULT_NAMES[res])
		var atk_ok := true
		var def_ok := true
		var grp_ok := true
		for ev in b.damage_events:
			if ev.kind == "attack":
				atk_ok = atk_ok and ev.amount == roundi(ev.base * t.attack_mult(res))
				dmg_by_result[res] = ev.amount if ev.base == t.slash_power else dmg_by_result.get(res, 0)
			else:
				def_ok = def_ok and ev.amount == roundi(ev.base * t.defense_mult(res))
				var e_ok: bool = ev.group in [1, 2]
				grp_ok = grp_ok and e_ok
		check(atk_ok and def_ok, "[%s] 伤害数值按判定倍率结算（%d 条记录）" % [MinigameBase.RESULT_NAMES[res], b.damage_events.size()])
		check(grp_ok, "[%s] 敌人出招前触发第 1/2 组防御小游戏" % MinigameBase.RESULT_NAMES[res])
		check(b.float_count == b.damage_events.size() and b.float_count > 0, "[%s] 每次结算都在屏幕上飘出伤害数字" % MinigameBase.RESULT_NAMES[res])
		await wait_scene(GameState.SCN_DUNGEON)
	check(dmg_by_result.get(R.PERFECT) == 15 and dmg_by_result.get(R.GOOD) == 10 and dmg_by_result.get(R.FAIL) == 5, "斩击伤害随判定变化：15 / 10 / 5")
	# 敌人类型 → 小游戏组
	GameState.auto_minigame = R.PERFECT
	GameState.start_battle()
	await wait_scene(GameState.SCN_BATTLE)
	var bb = scene()
	var groups_bal := {}
	for i in 50:
		groups_bal[bb.group_for({"data": GameState.enemy_types[2]})] = true
	check(bb.group_for({"data": GameState.enemy_types[0]}) == 1, "近战连击型 → 第 1 组")
	check(bb.group_for({"data": GameState.enemy_types[1]}) == 2, "追踪弹型 → 第 2 组")
	check(groups_bal.has(1) and groups_bal.has(2), "均衡型 → 随机第 1/2 组")
	await battle_outcome(bb)
	await wait_scene(GameState.SCN_DUNGEON)
	# 敌人数量 1~3
	var cnt_ok := true
	for i in 6:
		GameState.current_node = i
		GameState.depth = 3
		GameState.start_battle()
		await wait_scene(GameState.SCN_BATTLE)
		var n: int = scene().enemies.size()
		cnt_ok = cnt_ok and n >= 1 and n <= 3
		counts[n] = true
		GameState.depth = 1
		await battle_outcome(scene())
		await wait_scene(GameState.SCN_DUNGEON)
	check(cnt_ok, "敌人数量在 1~3 之间（出现过：%s）" % str(counts.keys()))
	# 倒下
	GameState.auto_minigame = R.FAIL
	GameState.player_hp = 1
	t.slash_power = 0
	t.heavy_power = 0
	GameState.start_battle()
	await wait_scene(GameState.SCN_BATTLE)
	var ob = await battle_outcome(scene())
	check(ob == "lose", "主角 HP 归零 → 倒下")
	check(await wait_scene(GameState.SCN_RESULT), "倒下 → 结算")
	check(GameState.last_result.extracted == false, "结算记录为倒下")
	scene().back_to_camp()
	check(await wait_scene(GameState.SCN_CAMP), "倒下结算 → 营地")

	print("\n结果：%d 通过，%d 失败" % [passes, fails])
	get_tree().quit(0 if fails == 0 else 1)

func Battle_calc(b: int, r: int, atk: bool) -> int:
	return preload("res://scenes/battle.gd").calc_damage(b, r, atk)

# ======================= 小游戏 T4~T7 =======================
func spawn(cfg: MinigameConfig, ctx: Dictionary) -> MinigameBase:
	var mg: MinigameBase = load(cfg.scene_path).instantiate()
	add_child(mg)
	mg.set_meta("results", [])
	mg.finished.connect(func(r, s): mg.get_meta("results").append(r))
	mg.start(cfg, ctx)
	while not mg.active and not mg.done:
		await get_tree().process_frame
	return mg

func wait_done(mg: MinigameBase, limit := 20.0) -> int:
	var w := 0.0
	while not mg.done and w < limit:
		await get_tree().process_frame
		w += get_process_delta_time()
	var r: Array = mg.get_meta("results")
	return r[0] if r.size() > 0 else -1

func key_ev(code: int, pressed := true) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = pressed
	return e

func joy_ev(btn: int, pressed := true) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = btn
	e.pressed = pressed
	return e

func tap(ev: InputEvent) -> void:
	Input.parse_input_event(ev)
	await get_tree().process_frame
	var up = ev.duplicate()
	up.pressed = false
	Input.parse_input_event(up)
	await get_tree().process_frame

const KB := {"move_up": KEY_UP, "move_down": KEY_DOWN, "move_left": KEY_LEFT, "move_right": KEY_RIGHT, "mg_action": KEY_SPACE}
const JOY := {"move_up": JOY_BUTTON_DPAD_UP, "move_down": JOY_BUTTON_DPAD_DOWN, "move_left": JOY_BUTTON_DPAD_LEFT, "move_right": JOY_BUTTON_DPAD_RIGHT, "mg_action": JOY_BUTTON_A}

## 连击：在每次出招期间按下 answer(i, key) 返回的动作（"" = 不按）
func play_combo(ctx: Dictionary, answer: Callable, device := "") -> MinigameBase:
	var mg: MinigameBase = await spawn(GameState.mg_defense[1], ctx)
	var handled := -1
	while not mg.done:
		if mg.phase == "prompt" and mg.idx != handled:
			handled = mg.idx
			var want: String = mg.sequence[mg.idx]
			var a: String = answer.call(mg.idx, want)
			if a != "":
				if device == "kb":
					await tap(key_ev(KB[a]))
				elif device == "joy":
					await tap(joy_ev(JOY[a]))
				else:
					mg.press(a)
		await get_tree().process_frame
	return mg

func wrong(k: String) -> String:
	return "move_up" if k != "move_up" else "move_down"

func test_minigames() -> void:
	var t := GameState.tunables
	# ---------- 预兆 ----------
	Engine.time_scale = 1.0
	var t0 := Time.get_ticks_msec()
	var mg0: MinigameBase = await spawn(GameState.mg_defense[1], {"depth": 1})
	var tele := (Time.get_ticks_msec() - t0) / 1000.0
	mg0.queue_free()
	Engine.time_scale = 20.0
	check(tele >= 0.45 and tele <= 1.3, "预兆提示时长约 %.2f 秒（0.5~1.0），含图标/文字/音效占位" % tele)
	var sk: Array = GameState.skills()
	check(sk[0].minigame == GameState.mg_rhythm and sk[1].minigame == GameState.mg_rps and sk[2].minigame == GameState.mg_dice, "技能绑定：节奏连斩→第6组，猜拳一击/命运骰击→第5组")
	check(GameState.mg_defense[1] is ComboConfig and GameState.mg_defense[2] is ChaseConfig, "防御第1组→连击闪避，第2组→追逐躲球（时机条占位已移除）")

	print("== T4 连击闪避/格挡 ==")
	var cc: ComboConfig = GameState.mg_defense[1]
	check(cc.hits_at(1) == 3 and cc.hits_at(2) == 4 and cc.hits_at(4) == 6 and cc.hits_at(9) == 6, "出招次数 3，随深度 +1，上限 6")
	check(is_equal_approx(cc.window_at(1), 600) and cc.window_at(2) < 600 and is_equal_approx(cc.window_at(20), 250), "窗口 600ms，随深度缩短，下限 250ms")
	var m := await play_combo({"depth": 1, "seed": 1}, func(i, k): return k)
	check(m.get_meta("results") == [R.PERFECT] and m.hits == 3, "全部按对 → PERFECT")
	m.queue_free()
	m = await play_combo({"depth": 2, "seed": 2}, func(i, k): return wrong(k) if i == 1 else k)
	check(m.get_meta("results") == [R.GOOD] and m.hits == 4, "错 1 次 → GOOD（第 2 层 4 连击）")
	m.queue_free()
	m = await play_combo({"depth": 1, "seed": 3}, func(i, k): return wrong(k) if i < 2 else k)
	check(m.get_meta("results") == [R.FAIL], "错 2 次 → FAIL")
	m.queue_free()
	m = await play_combo({"depth": 1, "seed": 4}, func(i, k): return "")
	check(m.get_meta("results") == [R.FAIL] and m.history.all(func(h): return h.reaction_ms < 0), "不按（全部超时）→ FAIL")
	m.queue_free()
	Engine.time_scale = 1.0
	m = await play_combo({"depth": 1, "seed": 5}, func(i, k): return k, "kb")
	check(m.get_meta("results") == [R.PERFECT], "键盘输入（方向键/空格）可完成")
	m.queue_free()
	m = await play_combo({"depth": 1, "seed": 6}, func(i, k): return k, "joy")
	check(m.get_meta("results") == [R.PERFECT], "手柄输入（十字键/A）可完成")
	m.queue_free()
	Engine.time_scale = 20.0
	var ed: SpinBox = GameState.debug_panel.find_editor(cc, "hits")
	var ed2: SpinBox = GameState.debug_panel.find_editor(cc, "window_ms")
	check(ed != null and ed2 != null, "调试面板中有 hits / window_ms 等参数")
	ed.value = 5
	ed2.value = 400
	m = await spawn(cc, {"depth": 1, "seed": 7})
	check(m.hits == 5 and is_equal_approx(m.window, 0.4), "面板改 hits=5、window_ms=400 后下一次立即生效")
	m.queue_free()
	ed.value = 3
	ed2.value = 600
	var c1t: float = 3 * (0.6 + 0.3)
	var c6t: float = 6 * (cc.window_at(4) / 1000.0 + 0.3)
	check(c1t >= 2.5 and c6t <= 6.0, "判定耗时：第1层 %.1f 秒、6 连击 %.1f 秒（+预兆约 0.7 秒）" % [c1t, c6t])

	print("== T5 追逐躲球 ==")
	var ch: ChaseConfig = GameState.mg_defense[2]
	check(ch.balls_at(1) == 1 and ch.balls_at(3) == 2 and ch.balls_at(5) == 3, "球数随深度增加（1/2/3 @ 第1/3/5层）")
	Engine.time_scale = 1.0
	var mc: MinigameBase = await spawn(ch, {"depth": 1, "seed": 1})
	mc.drive = func(_x): return Vector2.ZERO
	var res := await wait_done(mc)
	Engine.time_scale = 20.0
	check(res >= 0 and mc.t >= 4.0 and mc.t < 4.05, "持续 4 秒后结束（实际 %.2f 秒）" % mc.t)
	mc.queue_free()
	# 追踪可感知：手动推进，球的航向会转向玩家
	mc = await spawn(ch, {"depth": 1, "seed": 2})
	mc.active = false
	mc.player_pos = Vector2(100, 320)
	mc.balls[0].pos = Vector2(320, 100)
	mc.balls[0].vel = Vector2(1, 0) * ch.ball_speed
	var a0: float = absf(wrapf((mc.player_pos - mc.balls[0].pos).angle() - mc.balls[0].vel.angle(), -PI, PI))
	for i in 30:
		mc.step(1.0 / 60.0, Vector2.ZERO)
	var a1: float = absf(wrapf((mc.player_pos - mc.balls[0].pos).angle() - mc.balls[0].vel.angle(), -PI, PI))
	check(a1 < a0 - 0.4, "球朝角色转向（0.5 秒内航向偏差 %.0f° → %.0f°）" % [rad_to_deg(a0), rad_to_deg(a1)])
	mc.queue_free()
	var stand_hit_runs := 0
	var stand_hits := 0
	var dodge_ok := 0
	var dodge_hits := 0
	var N := 40
	for sd in N:
		for mode in ["stand", "dodge"]:
			var b: MinigameBase = await spawn(ch, {"depth": 1, "seed": 100 + sd})
			b.active = false
			while not b.done:
				var mv := Vector2.ZERO
				if mode == "dodge":
					mv = dodge_bot(b)
				b.step(1.0 / 60.0, mv)
			if mode == "stand":
				stand_hits += b.hits
				if b.hits > 0:
					stand_hit_runs += 1
			else:
				dodge_hits += b.hits
				if b.get_meta("results")[0] != R.FAIL:
					dodge_ok += 1
			b.queue_free()
	check(stand_hit_runs >= N * 0.9, "站着不动 %d/%d 局被击中，平均 %.1f 次（追踪有威胁）" % [stand_hit_runs, N, stand_hits / float(N)])
	check(dodge_ok / float(N) >= 0.8, "简单躲避 AI 有 %d%% 局非 FAIL，平均被击中 %.2f 次（可躲）" % [roundi(dodge_ok * 100.0 / N), dodge_hits / float(N)])
	# 第 3 层（2 个球）也可躲
	var d3_ok := 0
	for sd in 20:
		var b: MinigameBase = await spawn(ch, {"depth": 3, "seed": 300 + sd})
		b.active = false
		while not b.done:
			b.step(1.0 / 60.0, dodge_bot(b))
		if b.get_meta("results")[0] != R.FAIL:
			d3_ok += 1
		b.queue_free()
	check(d3_ok >= 6 and d3_ok / 20.0 < dodge_ok / float(N), "第 3 层（2 球）同一躲避 AI 非 FAIL %d/20，低于第 1 层（难度随层数提升）" % d3_ok)
	# 键盘/手柄移动
	for dev in ["kb", "joy"]:
		var b: MinigameBase = await spawn(ch, {"depth": 1, "seed": 9})
		var x0: float = b.player_pos.x
		var ev: InputEvent
		if dev == "kb":
			ev = key_ev(KEY_RIGHT)
		else:
			ev = InputEventJoypadMotion.new()
			ev.axis = JOY_AXIS_LEFT_X
			ev.axis_value = 1.0
		Input.parse_input_event(ev)
		for i in 5:
			await get_tree().process_frame
		var x1: float = b.player_pos.x
		if dev == "kb":
			Input.parse_input_event(key_ev(KEY_RIGHT, false))
		else:
			var r0 := InputEventJoypadMotion.new()
			r0.axis = JOY_AXIS_LEFT_X
			r0.axis_value = 0.0
			Input.parse_input_event(r0)
		await get_tree().process_frame
		check(x1 > x0 + 5, "%s 可移动角色（x %.0f → %.0f）" % ["键盘方向键" if dev == "kb" else "手柄左摇杆", x0, x1])
		b.queue_free()

	print("== T6 运气：猜拳 / 骰子 ==")
	var rp: LuckConfig = GameState.mg_rps
	var dc: LuckConfig = GameState.mg_dice
	for lk in [0, 3]:
		var want := rp.rps_win_rate(lk)
		var sim: Dictionary = preload("res://minigames/luck_game.gd").simulate(rp, lk, 1000, 42 + lk)
		var pr: Array = rp.outcome_probs(lk)
		check(absf(sim.first - want) <= 0.03, "猜拳 幸运%d：1000 次模拟单局胜率 %.1f%%，设定 %.1f%%（误差 %.1f%%）" % [lk, sim.first * 100, want * 100, absf(sim.first - want) * 100])
		check(absf(sim.perfect - pr[0]) <= 0.03 and absf(sim.good - pr[1]) <= 0.03 and absf(sim.fail - pr[2]) <= 0.03, "猜拳 幸运%d：判定分布 P/G/F 模拟 %.1f/%.1f/%.1f%% vs 理论 %.1f/%.1f/%.1f%%" % [lk, sim.perfect * 100, sim.good * 100, sim.fail * 100, pr[0] * 100, pr[1] * 100, pr[2] * 100])
	for lk in [0, 2]:
		var sim: Dictionary = preload("res://minigames/luck_game.gd").simulate(dc, lk, 1000, 77 + lk)
		var pr: Array = dc.outcome_probs(lk)
		check(absf(sim.first - dc.dice_base_rate()) <= 0.03 and absf(sim.perfect - pr[0]) <= 0.03 and absf(sim.good - pr[1]) <= 0.03, "骰子 幸运%d：1000 次模拟 首掷成功 %.1f%%（设定 %.1f%%），P/G/F %.1f/%.1f/%.1f%% vs 理论 %.1f/%.1f/%.1f%%" % [lk, sim.first * 100, dc.dice_base_rate() * 100, sim.perfect * 100, sim.good * 100, sim.fail * 100, pr[0] * 100, pr[1] * 100, pr[2] * 100])
	# 多种子稳健性
	var within := 0
	var max_err := 0.0
	for sd in 50:
		var s1: Dictionary = preload("res://minigames/luck_game.gd").simulate(rp, 0, 1000, 1000 + sd)
		var err := absf(s1.first - rp.rps_win_rate(0))
		max_err = maxf(max_err, err)
		if err <= 0.03:
			within += 1
	check(within >= 45, "50 组不同种子的 1000 次模拟：%d 组误差 ≤3%%（最大 %.1f%%，统计上约 95%% 预期）" % [within, max_err * 100])
	var ptxt: String = GameState.debug_panel.probability_text()
	check(ptxt.contains("33.0%") and ptxt.contains("50.0%"), "调试面板显示实际概率：" + ptxt.replace("\n", " / "))
	# 实际操作：猜拳（键盘←=石头）与骰子（手柄A）
	var lg: MinigameBase = await spawn(rp, {"depth": 1, "luck": 0, "seed": 5})
	var gt0 := 0.0
	await tap(key_ev(KEY_LEFT))
	var r6 := await wait_done(lg)
	check(r6 in [R.PERFECT, R.GOOD, R.FAIL] and lg.stage == "done", "猜拳：键盘出拳后播放动画并给出判定（%s）" % MinigameBase.RESULT_NAMES[r6])
	lg.queue_free()
	lg = await spawn(dc, {"depth": 1, "luck": 0, "seed": 6})
	await tap(joy_ev(JOY_BUTTON_A))
	r6 = await wait_done(lg)
	check(r6 in [R.PERFECT, R.GOOD, R.FAIL], "骰子：手柄 A 掷骰后给出判定（%s）" % MinigameBase.RESULT_NAMES[r6])
	lg.queue_free()
	lg = await spawn(dc, {"depth": 1, "luck": 0, "seed": 8})
	var tt := 0.0
	while not lg.done:
		await get_tree().process_frame
		tt += get_process_delta_time()
	check(tt >= 2.5 and tt <= 6.0, "不操作 2.5 秒后自动出手，总耗时 %.1f 秒" % tt)
	lg.queue_free()

	print("== T7 节奏按键 ==")
	var rc: RhythmConfig = GameState.mg_rhythm
	check(is_equal_approx(rc.bpm_at(1), 100) and rc.bpm_at(3) > rc.bpm_at(1), "BPM 随深度提高（%d → %d @ 第3层）" % [rc.bpm_at(1), rc.bpm_at(3)])
	check(rc.notes_at(1) == 4 and rc.notes_at(5) == 8 and rc.notes_at(9) == 8, "音符数 4~8")
	var rm: MinigameBase = await spawn(rc, {"depth": 1})
	rm.manual_clock = true
	var align := true
	var beat_ok := true
	for n in rm.notes:
		rm.song_t = n.t
		rm.advance()
		align = align and absf(n.rect.position.y + 15 - rm.line_y) < 0.5
		beat_ok = beat_ok and rm.last_beat == roundi(n.t / rm.beat)
		rm.press_at(n.t)
	rm.song_t = rm.end_time() + 0.01
	rm.advance()
	check(align, "每个音符恰好在其拍点时刻落到判定线")
	check(beat_ok, "节拍器在音符拍点上发声（音符时间 = (空拍 + i) × 60/BPM）")
	check(rm.get_meta("results") == [R.PERFECT], "全部踩点 → PERFECT")
	rm.queue_free()
	var cases := [[0.04, R.PERFECT, "全部 +40ms（PERFECT 窗口内）"], [0.08, R.GOOD, "全部 +80ms（GOOD 窗口，比例 0.75）"], [-0.1, R.GOOD, "全部 −100ms"], [0.2, R.FAIL, "全部 +200ms（超出窗口）"], [999.0, R.FAIL, "完全不按"]]
	for c in cases:
		var r7: MinigameBase = await spawn(rc, {"depth": 1})
		r7.manual_clock = true
		for n in r7.notes:
			if c[0] < 900:
				r7.song_t = n.t + c[0]
				r7.advance()
				r7.press_at(n.t + c[0])
		r7.song_t = r7.end_time() + 0.5
		r7.advance()
		check(r7.get_meta("results") == [c[1]], "%s → %s" % [c[2], MinigameBase.RESULT_NAMES[c[1]]])
		r7.queue_free()
	var r8: MinigameBase = await spawn(rc, {"depth": 1})
	r8.manual_clock = true
	for i in r8.notes.size():
		if i % 2 == 0:
			r8.press_at(r8.notes[i].t)
	r8.song_t = r8.end_time() + 0.5
	r8.advance()
	check(r8.get_meta("results") == [R.FAIL], "只按中一半（比例 0.5）→ FAIL")
	r8.queue_free()
	t.rhythm_offset_ms = 100.0
	var r9: MinigameBase = await spawn(rc, {"depth": 1})
	r9.manual_clock = true
	for n in r9.notes:
		r9.press_at(n.t + 0.1)
	r9.song_t = r9.end_time() + 0.5
	r9.advance()
	check(r9.get_meta("results") == [R.PERFECT], "校准值 +100ms 时，晚 100ms 按 → PERFECT（校准生效）")
	r9.queue_free()
	t.rhythm_offset_ms = 0.0
	var taps: Array = []
	for i in range(1, 9):
		taps.append(i * 600.0 + 70.0 + (i % 3 - 1) * 10.0)
	var off: float = preload("res://scenes/calibration.gd").compute_offset(taps, 600.0)
	check(absf(off - 70.0) < 5.0, "校准算法：8 次按键偏晚约 70ms → 算得 %+.1f ms" % off)
	# 真实时钟 + 真实输入事件：测输入链路自身延迟
	Engine.time_scale = 1.0
	var rr: MinigameBase = await spawn(rc, {"depth": 1})
	var offs: Array = []
	for n in rr.notes:
		while rr.song_t < n.t and not rr.done:
			await get_tree().process_frame
		await tap(joy_ev(JOY_BUTTON_A) if offs.size() % 2 else key_ev(KEY_SPACE))
		offs.append(n.offset_ms)
	var rres := await wait_done(rr)
	var mx := 0.0
	for o in offs:
		mx = maxf(mx, absf(o))
	check(rres == R.PERFECT and mx <= 50.0, "真实时钟下用键盘/手柄交替按键：最大偏差 %.1f ms（无额外延迟），判定 %s" % [mx, MinigameBase.RESULT_NAMES[rres]])
	var dur: float = rr.end_time()
	rr.queue_free()
	Engine.time_scale = 20.0
	var dmax := 0.0
	for dp in [1, 3, 5, 8]:
		var bt := 60.0 / rc.bpm_at(dp)
		dmax = maxf(dmax, (rc.lead_beats + rc.notes_at(dp) - 1) * bt + rc.good_ms / 1000.0 + 0.2)
	check(dur >= 2.5 and dmax <= 6.0, "判定耗时：第1层 %.1f 秒，各层最长 %.1f 秒" % [dur, dmax])

## 简单躲避 AI：远离各球（越近权重越大），并向场地中心回拉，侧向闪避
func dodge_bot(b) -> Vector2:
	var v := Vector2.ZERO
	for ball in b.balls:
		var d: Vector2 = b.player_pos - ball.pos
		var dist := maxf(d.length(), 1.0)
		var w := 1.0 / (dist * dist) * 40000.0
		v += d.normalized() * w + d.normalized().orthogonal() * w * 0.8
	var a: float = b.cfg.arena_size
	v += (Vector2(a / 2, a / 2) - b.player_pos) / a * 1.2
	return v.normalized()
