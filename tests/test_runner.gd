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
	var mgs: MinigameConfig = GameState.mg_slash
	check(absf(MinigameBase.compute_difficulty(mgs, {"depth": 2, "trait_bonus": 0.5}) - (t.base_difficulty + 2 * t.depth_scale - 0.5)) < 0.001, "难度公式 = base + depth*scale − trait_bonus")
	check(ProjectSettings.get_setting("display/window/size/viewport_width") == 1920 and ProjectSettings.get_setting("display/window/size/viewport_height") == 1080, "基准分辨率 1920x1080")
	for a in ["mg_action", "debug_toggle", "move_left", "move_up"]:
		var has_key := false
		var has_joy := false
		for e in InputMap.action_get_events(a):
			has_key = has_key or e is InputEventKey
			has_joy = has_joy or e is InputEventJoypadButton or e is InputEventJoypadMotion
		check(has_key and has_joy, "输入 %s 同时有键盘和手柄映射" % a)
	# 占位小游戏真实判定（非 auto）
	var mg: MinigameBase = load(mgs.scene_path).instantiate()
	add_child(mg)
	var got := []
	mg.finished.connect(func(r, s): got.append([r, s]))
	Engine.time_scale = 1.0
	var t0 := Time.get_ticks_msec()
	mg.start(mgs, {"depth": 1, "luck": 0, "trait_bonus": 0.0})
	while not mg.active and not mg.done:
		await get_tree().process_frame
	var tele := (Time.get_ticks_msec() - t0) / 1000.0
	Engine.time_scale = 20.0
	check(tele >= 0.45 and tele <= 1.3, "预兆提示时长约 %.2f 秒（0.5~1.0）" % tele)
	mg.evaluate(0.5)
	check(got.size() == 1 and got[0][0] == R.PERFECT, "时机条正中心 → PERFECT")
	mg.queue_free()
	for p in [[0.5 + mg.good_w * 0.4, R.GOOD], [0.0, R.FAIL]]:
		var m2: MinigameBase = load(mgs.scene_path).instantiate()
		add_child(m2)
		var g2 := []
		m2.finished.connect(func(r, s): g2.append(r))
		m2.start(mgs, {"depth": 1})
		while not m2.active:
			await get_tree().process_frame
		m2.evaluate(p[0])
		check(g2 == [p[1]], "时机条位置 %.2f → %s" % [p[0], MinigameBase.RESULT_NAMES[p[1]]])
		m2.queue_free()
	var m3: MinigameBase = load(mgs.scene_path).instantiate()
	add_child(m3)
	var g3 := []
	m3.finished.connect(func(r, s): g3.append(r))
	m3.start(mgs, {"depth": 1})
	while g3.is_empty():
		await get_tree().process_frame
	check(g3 == [R.FAIL], "超时不操作 → FAIL")
	m3.queue_free()
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
