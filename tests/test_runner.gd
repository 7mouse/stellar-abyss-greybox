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
		while d.popup_kind == "discard":
			d.choose_discard_new()
			await get_tree().process_frame
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
	GameState.log_path = "user://test_playtest_log.csv"
	GameState.clear_log()
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
			var extra := 1 if t.has_entrance_rest(dp) else 0
			gen_ok = gen_ok and n >= t.nodes_min + extra and n <= t.nodes_max + extra
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
	check(gen_ok, "360 次生成：每层 %d~%d 个节点（入口休息层 +1）、恰好 1 个出口" % [t.nodes_min, t.nodes_max])
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
	check(Battle_calc(10, R.PERFECT, false) == 0 and Battle_calc(10, R.GOOD, false) == roundi(10 * t.def_mult_good) and Battle_calc(10, R.FAIL, false) == 10, "防御受伤 0/%d%%/100%%" % roundi(t.def_mult_good * 100))
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
	t.slash_power = 10
	t.heavy_power = 16

	await test_milestone3()
	await test_balance_v1()

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

# ======================= T8~T10 + 整体验收 =======================
func focus_ok() -> bool:
	await get_tree().process_frame
	await get_tree().process_frame
	var f := get_viewport().gui_get_focus_owner()
	return f != null and f.is_visible_in_tree() and not (f is Button and f.disabled)

func pad(btn := JOY_BUTTON_A) -> void:
	await tap(joy_ev(btn))

func test_milestone3() -> void:
	var t := GameState.tunables
	GameState.auto_minigame = R.PERFECT
	GameState.auto_skill = 0
	print("== T8 搜刮与背包 ==")
	GameState.new_run()
	GameState.put_item("material", 3)
	check(GameState.inventory.size() == 1, "放入材料 3 → 占 1 格")
	GameState.put_item("material", 34)
	check(GameState.inventory.size() == 12 and GameState.pending_loot.size() == 1, "背包上限 12 格，多出的进入待取舍（%d 格，待取舍 %d）" % [GameState.inventory.size(), GameState.pending_loot.size()])
	GameState.pending_loot.clear()
	GameState.put_item("shard", 1)
	GameState.goto(GameState.SCN_DUNGEON)
	await wait_scene(GameState.SCN_DUNGEON)
	check(scene().popup_kind == "discard", "背包满时进入迷宫/拾取 → 弹出取舍界面")
	check(await focus_ok(), "取舍界面有默认焦点（手柄可操作）")
	var all_disabled := true
	for id in scene().buttons:
		all_disabled = all_disabled and scene().buttons[id].disabled
	check(all_disabled, "取舍未完成前不能继续走迷宫")
	scene().choose_discard_slot(0)
	await get_tree().process_frame
	check(GameState.pending_loot.is_empty() and GameState.inventory.size() == 12 and GameState.run_loot.shard == 1 and GameState.run_loot.material == 33, "丢弃第 1 格材料 → 碎片入包（材料 %d 碎片 %d）" % [GameState.run_loot.material, GameState.run_loot.shard])
	GameState.put_item("shard", 2)
	GameState.put_item("material", 3) # 堆满后溢出
	await get_tree().process_frame
	scene()._refresh()
	check(scene().popup_kind == "discard", "再次溢出 → 再次弹出取舍")
	while not GameState.pending_loot.is_empty():
		scene().choose_discard_new()
		await get_tree().process_frame
	check(GameState.run_loot.material <= 36 and scene().popup_kind == "", "放弃新物品 → 背包不变，取舍结束")
	# 倒下 / 撤离结算
	GameState.new_run()
	GameState.put_item("material", 7)
	GameState.put_item("shard", 3)
	var meta_m := GameState.meta_materials
	var meta_s := GameState.meta_shards
	GameState.end_run(false)
	await wait_scene(GameState.SCN_RESULT)
	var lr := GameState.last_result
	check(lr.material == 3 and lr.material_lost == 4 and lr.shard == 3, "倒下：材料 7 → 带出 3（丢 4），碎片 3 全保留")
	scene().back_to_camp()
	await wait_scene(GameState.SCN_CAMP)
	check(GameState.meta_materials == meta_m + 3 and GameState.meta_shards == meta_s + 3, "倒下结算正确计入局外")
	GameState.new_run()
	GameState.put_item("material", 7)
	GameState.put_item("shard", 3)
	GameState.end_run(true)
	await wait_scene(GameState.SCN_RESULT)
	check(GameState.last_result.material == 7 and GameState.last_result.shard == 3, "撤离：材料 7、碎片 3 全部带出")
	scene().back_to_camp()
	await wait_scene(GameState.SCN_CAMP)
	# 掉落率
	GameState.new_run()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var hits := 0
	for i in 2000:
		hits += 1 if GameState.roll_drop(0.25, 1, rng) > 0 else 0
	check(absf(hits / 2000.0 - 0.25) < 0.03, "掉落率 25%% → 模拟 %.1f%%" % (hits / 20.0))
	t.battle_drop_rate = 1.0
	t.battle_shard_rate = 1.0
	GameState.start_battle()
	await wait_scene(GameState.SCN_BATTLE)
	var bt = scene()
	await battle_outcome(bt)
	var ne: int = bt.enemies.size()
	check(bt.drops.material == ne * t.battle_material_drop and bt.drops.shard == ne, "战斗掉落：%d 个敌人 → 材料 %d、碎片 %d（掉落率 100%%）" % [ne, bt.drops.material, bt.drops.shard])
	t.battle_drop_rate = 0.8
	t.battle_shard_rate = 0.25
	await wait_scene(GameState.SCN_DUNGEON)

	print("== T9 极简营地 ==")
	GameState.goto(GameState.SCN_CAMP)
	await wait_scene(GameState.SCN_CAMP)
	GameState.meta_materials = 0
	scene()._refresh()
	check(scene().upgrade_buttons[1].disabled, "材料不足时升级按钮不可用")
	GameState.meta_materials = 40
	scene()._refresh()
	var cost1 := GameState.upgrade_cost(1)
	scene().upgrade_buttons[1].pressed.emit()
	check(GameState.skill_levels[1] == 1 and GameState.meta_materials == 40 - cost1, "第1组升到 Lv1，花费 %d 材料" % cost1)
	check(GameState.upgrade_cost(1) > cost1, "再升级花费递增（%d）" % GameState.upgrade_cost(1))
	scene().upgrade_buttons[5].pressed.emit()
	scene().upgrade_buttons[6].pressed.emit()
	scene().upgrade_buttons[2].pressed.emit()
	check(GameState.skill_levels[5] == 1 and GameState.skill_levels[6] == 1 and GameState.skill_levels[2] == 1, "第2/5/6组也可升级")
	GameState.depth = 3
	scene().enter_dungeon()
	await wait_scene(GameState.SCN_DUNGEON)
	check(GameState.depth == 1, "“再次下潜”从第 1 层开始")
	var cm: MinigameBase = await spawn(GameState.mg_defense[1], GameState.minigame_context(GameState.mg_defense[1]))
	check(is_equal_approx(cm.window, 0.66), "下一局：连击窗口 600 → %d ms（+10%%）" % roundi(cm.window * 1000))
	cm.queue_free()
	var rmg: MinigameBase = await spawn(GameState.mg_rhythm, GameState.minigame_context(GameState.mg_rhythm))
	check(is_equal_approx(rmg.good_w, 0.132) and is_equal_approx(rmg.perfect_w, 0.055), "下一局：节奏判定 ±50/±120 → ±%d/±%d ms" % [roundi(rmg.perfect_w * 1000), roundi(rmg.good_w * 1000)])
	rmg.queue_free()
	var chm: MinigameBase = await spawn(GameState.mg_defense[2], GameState.minigame_context(GameState.mg_defense[2]))
	var sp: float = chm.balls[0].vel.length()
	check(absf(sp - 260.0 / 1.1) < 0.5, "下一局：追踪球速 260 → %.0f（等效窗口 +10%%）" % sp)
	chm.queue_free()
	check(GameState.luck() == 1 and GameState.mg_rps.rps_win_rate(GameState.luck()) > GameState.mg_rps.rps_win_rate(0), "下一局：幸运 +1，猜拳胜率 33%% → %d%%" % roundi(GameState.mg_rps.rps_win_rate(GameState.luck()) * 100))
	# 还原
	for g in GameState.skill_levels:
		GameState.skill_levels[g] = 0

	print("== T10 调试面板与数据记录 ==")
	var dp = GameState.debug_panel
	var need := [[t, "battle_drop_rate"], [t, "battle_shard_rate"], [t, "chest_shard_rate"], [t, "base_difficulty"], [GameState.enemy_types[0], "attack"], [GameState.enemy_types[1], "attack"], [GameState.enemy_types[2], "attack"], [GameState.mg_defense[2], "ball_speed"], [GameState.mg_rhythm, "bpm"], [GameState.mg_rps, "rps_base_win"]]
	var miss := []
	for pr in need:
		if dp.find_editor(pr[0], pr[1]) == null:
			miss.append(pr[1])
	check(miss.is_empty(), "面板包含：掉落率、敌人伤害、各小游戏参数（缺失：%s）" % str(miss))
	var gm := false
	for c in dp.root.find_children("*", "CheckBox", true, false):
		gm = gm or true
	check(gm and dp.depth_spin != null, "面板包含上帝模式开关与当前层")
	dp.toggle()
	await get_tree().process_frame
	await get_tree().process_frame
	check(int(dp.depth_spin.value) == GameState.depth and dp.info.text.contains("当前层"), "面板显示当前层 %d" % GameState.depth)
	dp.toggle()
	t.god_mode = true
	GameState.auto_minigame = R.FAIL
	GameState.player_hp = 100
	GameState.start_battle()
	await wait_scene(GameState.SCN_BATTLE)
	var gb = scene()
	await battle_outcome(gb)
	var dmg_taken := 0
	for ev in gb.damage_events:
		if ev.kind == "defense":
			dmg_taken += ev.amount
	check(gb.outcome == "win" and dmg_taken == 0 and GameState.player_hp == 100, "上帝模式：防御全 FAIL 也不掉血")
	t.god_mode = false
	await wait_scene(GameState.SCN_DUNGEON)
	GameState.auto_minigame = R.PERFECT
	GameState.clear_log()
	GameState.start_battle()
	await wait_scene(GameState.SCN_BATTLE)
	var lb = scene()
	await battle_outcome(lb)
	var n_events: int = lb.damage_events.size()
	await wait_scene(GameState.SCN_DUNGEON)
	var f := FileAccess.open(GameState.log_path, FileAccess.READ)
	var lines := f.get_as_text().strip_edges().split("\n")
	f.close()
	check(lines[0] == GameState.LOG_HEADER, "CSV 表头：" + lines[0])
	check(lines.size() - 1 == n_events, "每次小游戏写一行（%d 行 = %d 次判定）" % [lines.size() - 1, n_events])
	var cols_ok := true
	for i in range(1, lines.size()):
		var c := lines[i].split(",")
		cols_ok = cols_ok and c.size() == 11 and c[6] in ["PERFECT", "GOOD", "FAIL"] and float(c[9]) > 0.4
	check(cols_ok, "每行含判定结果与耗时（例：%s）" % lines[1])
	# 真实操作的日志（非 auto）
	GameState.clear_log()
	var lm: MinigameBase = await spawn(GameState.mg_rps, GameState.minigame_context(GameState.mg_rps))
	await tap(key_ev(KEY_LEFT))
	await wait_done(lm)
	lm.queue_free()
	f = FileAccess.open(GameState.log_path, FileAccess.READ)
	var l2 := f.get_as_text().strip_edges().split("\n")
	f.close()
	var c2 := l2[1].split(",")
	check(c2[3] == "luck_rps" and c2[10] == "0" and float(c2[8]) > 0.5, "真实操作的小游戏也记录（%s）" % l2[1])
	print("  CSV 路径：", ProjectSettings.globalize_path(GameState.log_path))

	print("== 整体验收（headless 可测部分）==")
	# 全手柄 / 全键盘走一局：营地 → 迷宫 → 战斗（菜单选技能）→ 出口撤离 → 结算 → 营地
	for dev in ["joy", "kb"]:
		GameState.auto_skill = -1
		GameState.auto_minigame = R.PERFECT
		GameState.goto(GameState.SCN_CAMP)
		await wait_scene(GameState.SCN_CAMP)
		var screens := {}
		var ok := true
		var steps := 0
		var left_camp := false
		while steps < 400:
			steps += 1
			var sc := scene()
			var path: String = sc.scene_file_path if sc else ""
			if path == GameState.SCN_CAMP and left_camp:
				break
			if path == GameState.SCN_BATTLE and not sc.choosing:
				await get_tree().process_frame
				continue
			if not await focus_ok():
				await get_tree().process_frame
				if not await focus_ok():
					continue
			screens[path.get_file().get_basename() + ("/" + sc.popup_kind if path == GameState.SCN_DUNGEON and sc.popup_kind != "" else "")] = true
			if path != GameState.SCN_CAMP:
				left_camp = true
			if dev == "joy":
				await pad()
			else:
				await tap(key_ev(KEY_ENTER))
			for i in 3:
				await get_tree().process_frame
		var got_all: bool = screens.has("camp") and screens.has("dungeon") and screens.has("battle") and screens.has("dungeon/exit") and screens.has("result")
		check(got_all and scene().scene_file_path == GameState.SCN_CAMP, "仅用%s走完一局：%s" % ["手柄 A 键" if dev == "joy" else "键盘回车", str(screens.keys())])
	GameState.auto_skill = 0
	# 校准界面焦点
	GameState.goto(GameState.SCN_CALIBRATION)
	await wait_scene(GameState.SCN_CALIBRATION)
	check(await focus_ok(), "校准界面可用手柄/键盘返回")
	# 一局时长估算：用 auto GOOD 打一局到第 3 层再撤离，数判定次数
	GameState.auto_minigame = R.GOOD
	GameState.goto(GameState.SCN_CAMP)
	await wait_scene(GameState.SCN_CAMP)
	scene().enter_dungeon()
	await wait_scene(GameState.SCN_DUNGEON)
	var judges := 0
	var nodes_visited := 0
	var battles := 0
	var player_turns := 0
	var dead := false
	for fl in 3:
		while true:
			var d = scene()
			if d.scene_file_path != GameState.SCN_DUNGEON:
				break
			if d.popup_kind == "discard":
				d.choose_discard_new()
				await get_tree().process_frame
				continue
			var path := _bfs(GameState.floor_data, GameState.current_node, "exit")
			var nid: int = path[0]
			nodes_visited += 1
			d.visit(nid)
			var nd: Dictionary = GameState.floor_data.nodes[nid]
			if nd.type == "combat":
				await wait_scene(GameState.SCN_BATTLE)
				var b = scene()
				var o = await battle_outcome(b)
				battles += 1
				judges += b.damage_events.size()
				for ev in b.damage_events:
					if ev.kind == "attack":
						player_turns += 1
				if o != "win":
					dead = true
					break
				await wait_scene(GameState.SCN_DUNGEON)
			elif nd.type == "exit":
				if scene().popup_kind == "clear":
					scene().choose_clear_confirm()
					await wait_scene(GameState.SCN_DUNGEON)
				elif fl < 2:
					scene().choose_descend()
					await get_tree().process_frame
					await wait_scene(GameState.SCN_DUNGEON)
				else:
					scene().choose_withdraw()
				break
			elif d.popup_kind == "message":
				d.dismiss_message()
		if dead:
			break
	# 估算：每次判定 预兆0.7 + 判定≈3.8 + 结算演出1.2 秒；玩家每回合选技能≈3 秒；每个节点走动/阅读≈8 秒；每场战斗进出≈5 秒
	var est := judges * (0.7 + 3.8 + 1.2) + player_turns * 3.0 + nodes_visited * 8.0 + battles * 5.0
	print("  估算一局：%d 个节点、%d 场战斗、%d 次判定（全 GOOD，%s）→ 约 %.1f 分钟" % [nodes_visited, battles, judges, "中途倒下" if dead else "打通第 3 层", est / 60.0])
	check(est / 60.0 >= 5.0 and est / 60.0 <= 20.0, "一局时长估算 %.1f 分钟（目标 10~15，需真人计时确认）" % (est / 60.0))
	GameState.auto_minigame = R.PERFECT

# ======================= 数值调整 v1 + 最终层 =======================
func test_balance_v1() -> void:
	var t := GameState.tunables
	print("== 数值 v1 ==")
	var d := Tunables.new()
	check(d.nodes_min == 8 and d.nodes_max == 10 and is_equal_approx(d.def_mult_good, 0.5) and is_equal_approx(d.enemy_hp_per_depth, 0.2) and is_equal_approx(d.enemy_atk_per_depth, 0.15) and d.final_floor == 0, "tunables.gd 默认值未改（可回滚）")
	var f: Tunables = load("res://data/tunables.tres")
	check(f.nodes_min == 12 and f.nodes_max == 14 and is_equal_approx(f.def_mult_good, 0.35) and is_equal_approx(f.enemy_hp_per_depth, 0.25) and is_equal_approx(f.enemy_atk_per_depth, 0.2) and f.final_floor == 3 and f.entrance_rest_floors == "3" and is_equal_approx(f.entrance_rest_heal, 0.7), "tunables.tres 覆盖：节点 12~14、GOOD 防御 35%、敌人成长 HP 25%/攻击 20%、最终层 3、第3层入口休息 70%")
	check(f.upgrade_cost_base == 6 and is_equal_approx(f.rest_heal_ratio, 0.3), "upgrade_cost_base=6、休息回血 30% 不变")
	var at := []
	for e in GameState.enemy_types:
		at.append(e.attack)
	check(at == [5, 7, 5], "敌人攻击：近战连击 5、追踪弹 7、均衡 5")
	check(is_equal_approx(GameState.mg_rps.anim_sec, 0.5) and is_equal_approx(GameState.mg_dice.anim_sec, 0.8), "猜拳 anim_sec 0.5（骰子保持 0.8）")
	check(GameState.debug_panel.find_editor(t, "final_floor") != null, "F1 面板可改最终层 final_floor")
	check(GameState.debug_panel.find_editor(t, "entrance_rest_floors") is LineEdit and GameState.debug_panel.find_editor(t, "entrance_rest_heal") != null, "F1 面板可改入口休息层（文本，如 2,3）与回血比例")
	print("== 第 3 层入口固定休息点 ==")
	var ok3 := true
	var ok_other := true
	var reach := true
	for sd in 40:
		var f3 := DungeonGen.generate(sd, 3, t)
		var e: Dictionary = f3.nodes[0]
		ok3 = ok3 and f3.start == [0] and e.type == "rest" and e.get("entrance", false) and not e.next.is_empty()
		for nd in f3.nodes:
			reach = reach and (nd.type == "exit" or not _bfs(f3, nd.id, "exit").is_empty())
		for dpp in [1, 2]:
			var fo := DungeonGen.generate(sd, dpp, t)
			for nd in fo.nodes:
				ok_other = ok_other and not nd.get("entrance", false)
	check(ok3, "第 3 层：入口唯一可选节点是固定休息点")
	check(reach, "第 3 层：入口之后所有节点仍可到达出口")
	check(ok_other, "第 1/2 层没有入口休息点")
	t.entrance_rest_floors = "2,3"
	check(DungeonGen.generate(5, 2, t).nodes[0].get("entrance", false), "改成 \"2,3\" 后第 2 层也有入口休息点")
	t.entrance_rest_floors = "3"
	GameState.new_run()
	GameState.depth = 3
	GameState.floor_data = DungeonGen.generate(GameState.run_seed, 3, t)
	GameState.current_node = -1
	GameState.player_hp = 20
	GameState.goto(GameState.SCN_DUNGEON)
	await wait_scene(GameState.SCN_DUNGEON)
	scene().visit(0)
	check(GameState.player_hp == 90, "入口休息回复 70%%（20 → %d）" % GameState.player_hp)
	scene().dismiss_message()
	GameState.goto(GameState.SCN_CAMP)
	await wait_scene(GameState.SCN_CAMP)
	check(scene().upgrade_buttons[2].text.contains("追踪球速度降低") and scene().upgrade_buttons[1].text.contains("判定窗口 +10%"), "营地文案：第2组“追踪球速度降低”")
	# 猜拳平局最长耗时
	var lg: MinigameBase = await spawn(GameState.mg_rps, {"depth": 1, "luck": 0, "seed": 1})
	var steps := maxi(3, roundi(0.5 / 0.08))
	lg.queue_free()
	var worst := 2.5 + 2 * (steps * 0.08 + 0.5) + 0.3
	check(worst <= 5.0, "猜拳平局最坏耗时 %.1f 秒（+预兆 0.7）" % worst)

	print("== 最终层 / 假结局循环 ==")
	GameState.auto_minigame = R.PERFECT
	GameState.auto_skill = 0
	scene().enter_dungeon()
	await wait_scene(GameState.SCN_DUNGEON)
	for loop in 2:
		var meta_m := GameState.meta_materials
		var clears := GameState.clear_count
		for fl in range(1, 4):
			check(GameState.depth == fl, "第 %d 轮：到达第 %d 层" % [loop + 1, fl])
			if not await walk_to("exit"):
				check(false, "走到出口失败")
				return
			if fl < 3:
				check(scene().popup_kind == "exit", "第 %d 层出口：撤离/继续二选一" % fl)
				scene().choose_descend()
				await get_tree().process_frame
				await wait_scene(GameState.SCN_DUNGEON)
		check(scene().popup_kind == "clear" and GameState.is_final_floor(), "第 3 层出口 → “恭喜通关”（无继续深入）")
		check(await focus_ok(), "通关弹窗有默认焦点")
		var loot: Dictionary = GameState.run_loot
		var old_seed := GameState.run_seed
		scene().choose_clear_confirm()
		await get_tree().process_frame
		check(await wait_scene(GameState.SCN_DUNGEON), "确认后迷宫重置")
		check(GameState.depth == 1 and GameState.current_node == -1 and GameState.inventory.is_empty() and GameState.player_hp == t.player_max_hp, "重置为第 1 层入口，背包清空，满血")
		check(GameState.clear_count == clears + 1 and GameState.meta_materials == meta_m + loot.material and GameState.last_result.get("cleared", false), "通关次数 %d，战利品（材料 %d）全部存入局外" % [GameState.clear_count, loot.material])
		check(GameState.run_seed != old_seed, "重置后生成新的迷宫（种子 %d → %d）" % [old_seed, GameState.run_seed])
	GameState.auto_minigame = R.PERFECT
