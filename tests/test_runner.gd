extends Node
## 灰盒 2 / 开放地图 M1 无头验收。运行：tests/run_tests.sh（退出码 0 = 全部通过）

var passes := 0
var fails := 0
var DP: Node

func check(cond: bool, msg: String) -> void:
	if cond:
		passes += 1
		print("  [PASS] ", msg)
	else:
		fails += 1
		printerr("  [FAIL] ", msg)

func _ready() -> void:
	get_tree().create_timer(800.0, true, false, true).timeout.connect(func(): printerr("[FAIL] 超时"); get_tree().quit(2))
	process_mode = Node.PROCESS_MODE_ALWAYS
	DP = Game.debug_panel
	# 固定随机：楼层布局（局种子）、全局 randf（敌人初始冷却）、Game/Lineage 的 rng。TEST_SEED 环境变量可换种子
	var sd := int(OS.get_environment("TEST_SEED")) if OS.has_environment("TEST_SEED") else 424242
	print("测试种子 ", sd)
	Game.run_seed_override = sd
	seed(sd)
	Game.rng.seed = sd
	Lineage.rng.seed = sd + 1
	Lineage.save_path = "user://test_lineage.json"
	Log.dir = "user://test_logs"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(Log.dir))
	Log.clear()
	Lineage.wipe()
	_run()

func frames(n := 1) -> void:
	for i in n:
		await get_tree().physics_frame

func secs(s: float) -> void:
	await get_tree().create_timer(s, true, true).timeout

## 等到条件成立（最多 t 秒真实时间），超时打印警告
func until(c: Callable, t := 8.0) -> bool:
	var t0 := Time.get_ticks_msec()
	while not c.call():
		if Time.get_ticks_msec() - t0 > t * 1000:
			printerr("  [超时] 等待条件 ", c)
			return false
		await get_tree().physics_frame
	return true

## 去掉随机特质/缺陷，避免影响数值断言
func plain() -> void:
	var ind := Lineage.current()
	ind.trait = ""
	ind.flaw = ""

func scene() -> Node:
	return get_tree().current_scene

func wait_scene(path: String, timeout := 20.0) -> bool:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < timeout * 1000 / maxf(1.0, Game.base_time_scale) + 3000:
		var s := scene()
		if s and s.scene_file_path == path and s.is_node_ready():
			await frames(2)
			return true
		await get_tree().process_frame
	return false

func _run() -> void:
	await frames(2)
	await test_generation()
	test_drops()
	test_inheritance()
	test_vault()
	test_save()
	await test_player()
	await test_attacks()
	await test_enemies()
	await test_guards_and_exit()
	await test_boons()
	await test_open_map()
	await test_aggro()
	await test_ecology()
	await test_m3_panel()
	await test_m4_designer()
	await test_nav_chase()
	await test_walk_floor1()
	await test_village()
	await test_death_flow()
	await test_full_flow_input()
	await test_csv()
	await test_recall_charm()
	print("\n结果：%d 通过，%d 失败" % [passes, fails])
	Lineage.wipe()
	Log.clear()
	get_tree().quit(0 if fails == 0 else 1)

# ---------------- OM1 开放地图生成 / OM4 分布 ----------------
func test_generation() -> void:
	print("== OM1 地图生成 MapGen / OM4 分布 ==")
	var reach_ok := true
	var pts_ok := true
	var cons_ok := true
	var count_ok := true
	var empty_ok := true
	var bad_msg := ""
	var cons_msg := ""
	var tmax := 0.0
	var retries := 0
	var patrol_report := []
	var patrol_ok := true
	for depth in [1, 2, 3]:
		var fd := Game.floor_data(depth)
		var groups := 0.0
		var expect := 0.0
		for s in 50:
			var t0 := Time.get_ticks_usec()
			var L := MapGen.generate(s * 7 + 1, depth, fd)
			tmax = maxf(tmax, (Time.get_ticks_usec() - t0) / 1000.0)
			retries += int(L.attempt)
			var bad := MapGen.unreachable_chunks(L)
			if not bad.is_empty() or not L.ok:
				reach_ok = false
				bad_msg = "层 %d 种子 %d 区块 %s ok=%s" % [depth, s, str(bad), L.ok]
			var up := MapGen.unreachable_points(L)
			if not up.is_empty():
				pts_ok = false
				bad_msg += " 点 %s" % str(up)
			var ch: Array = L.chunks
			var sc: Vector2i = ch[L.start_chunk].cell
			var gc: Vector2i = ch[L.guard_chunk].cell
			var path := MapGen.shortest_path(L)
			var pcells: Array = path.map(func(i): return ch[i].cell)
			var camps: Array = L.camps.map(func(i): return ch[i].cell)
			var c_ok: bool = sc.x == 0 and gc.x == fd.grid_w - 1 and path.size() - 1 >= fd.min_start_guard_dist
			c_ok = c_ok and camps.all(func(c): return MapGen.cheb(c, sc) >= 2)
			for i in camps.size():
				for j in range(i + 1, camps.size()):
					c_ok = c_ok and MapGen.cheb(camps[i], camps[j]) >= 2
			c_ok = c_ok and camps.any(func(c): return pcells.any(func(p): return MapGen.cheb(p, c) <= 1))
			c_ok = c_ok and L.shrines.all(func(i): return MapGen.cheb(ch[i].cell, sc) >= 2)
			c_ok = c_ok and L.guard_entrances.size() >= 1 and L.guard_entrances.size() <= 2 and ch[L.guard_chunk].open_edges.size() == L.guard_entrances.size()
			if not c_ok:
				cons_ok = false
				cons_msg = "层 %d 种子 %d" % [depth, s]
			var st := MapGen.stats(L)
			count_ok = count_ok and st.camps == fd.camps and st.chests == fd.chests and st.nodes == fd.resource_nodes and st.shrines == fd.shrines
			var sp: Dictionary = L.spawn_points
			count_ok = count_ok and sp.patrol.all(func(p): return p.size >= fd.patrol_size_min and p.size <= fd.patrol_size_max and p.points.size() >= 2 and p.points.size() <= 4)
			count_ok = count_ok and sp.camp.all(func(c): return c.size >= fd.camp_size_min and c.size <= fd.camp_size_max)
			var solids := MapGen.all_solids(L)
			for p in sp.patrol:
				for q in p.points:
					var k := MapGen.chunk_at(L, q)
					empty_ok = empty_ok and k != L.start_chunk and k != L.guard_chunk and MapGen.is_free(q, solids, 60.0)
			for c in sp.camp:
				var k := MapGen.chunk_at(L, c.center)
				empty_ok = empty_ok and k != L.start_chunk and k != L.guard_chunk
			for q in sp.chest + sp.node:
				for p in sp.patrol:
					if MapGen.chunk_at(L, q) == p.chunk:
						empty_ok = empty_ok and p.points.all(func(r): return r.distance_to(q) >= 150.0)
			groups += st.patrol_groups
			expect += st.normal_chunks * fd.patrol_chance
		var err := absf(groups - expect) / expect
		patrol_ok = patrol_ok and err <= 0.15
		patrol_report.append("第 %d 层 %.1f / 期望 %.1f（%+.1f%%）" % [depth, groups / 50.0, expect / 50.0, (groups - expect) / expect * 100])
	check(reach_ok, "OM1-1 第 1~3 层 × 50 个种子：unreachable_chunks 全部为空（40px 栅格，半径 24）%s" % bad_msg)
	check(pts_ok, "OM1-1 巡逻点、营地、宝箱、资源点、篝火、撤离点、层主位置都能走到（不卡墙）")
	check(cons_ok, "OM1-1 摆放约束：起点第 0 列、层主区最后一列、最短路 ≥ 5（第 3 层 ≥ 6）、营地距起点 ≥2 且两两 ≥2、至少 1 个营地在最短路 ±1、神龛不贴起点、层主区 1~2 个入口 %s" % cons_msg)
	print("  （150 张图共换子种子重试 %d 次）" % retries)
	var fd1 := Game.floors[0]
	var a := MapGen.generate(42, 1, fd1)
	var b := MapGen.generate(42, 1, fd1)
	check(var_to_str(a.chunks) == var_to_str(b.chunks) and var_to_str(a.spawn_points) == var_to_str(b.spawn_points), "OM1-2 同种子同层生成两次，chunks 和 spawn_points 完全一致")
	check(var_to_str(a.chunks) != var_to_str(MapGen.generate(42, 2, Game.floors[1]).chunks) and var_to_str(a.chunks) != var_to_str(MapGen.generate(43, 1, fd1).chunks), "种子 / 层号不同 → 布局不同")
	check(tmax <= 200.0, "1.5-3 单次生成最长 %.1f ms（生成 + 烘焙 ≤ 300 ms，烘焙见 OM3-2；这里生成单独 ≤ 200 ms）" % tmax)
	# ---- §10 / §3.3 摆放规则 ----
	var two := 0
	var cand2 := 0
	var gap_ok := true
	var camp_guard_ok := true
	var path4_ok := true
	var fire_ok := true
	var enemies_avg := []
	for depth in [1, 2, 3]:
		var fdd := Game.floor_data(depth)
		var tot := 0.0
		for sd in 50:
			var L := MapGen.generate(sd * 11 + 5, depth, fdd)
			var ch: Array = L.chunks
			var gc: Vector2i = ch[L.guard_chunk].cell
			var nb := 0
			for d in MapGen.DIRS:
				var n: Vector2i = gc + d
				if n.x >= 0 and n.y >= 0 and n.x < fdd.grid_w and n.y < fdd.grid_h:
					nb += 1
			if nb >= 2:
				cand2 += 1
				two += int(L.guard_entrances.size() == 2)
			for en in L.guard_entrances:
				var g: Rect2 = en.gap
				gap_ok = gap_ok and is_equal_approx(maxf(g.size.x, g.size.y), fdd.gap_px) and is_equal_approx(fdd.gap_px, 480.0)
			camp_guard_ok = camp_guard_ok and L.camps.all(func(k): return MapGen.cheb(ch[k].cell, gc) >= 2)
			# 最短路按打通边 4 邻接：路径上相邻两格曼哈顿距离 = 1，且边是打通的
			var path: Array = L.path
			for i in range(1, path.size()):
				var ca: Vector2i = ch[path[i - 1]].cell
				var cb: Vector2i = ch[path[i]].cell
				path4_ok = path4_ok and absi(ca.x - cb.x) + absi(ca.y - cb.y) == 1 and L.open.has(MapGen._ekey(ca, cb))
			path4_ok = path4_ok and path.size() - 1 >= fdd.min_start_guard_dist
			# 篝火空地：篝火在入口外侧、可达、离障碍 ≥ 60px
			var fire: Vector2 = L.campfire_pos
			fire_ok = fire_ok and not MapGen.chunk_rect(ch[L.guard_chunk], L.chunk_px).has_point(fire) and MapGen.is_free(fire, MapGen.all_solids(L), 60.0) and MapGen.point_reachable(MapGen.reach_grid(L), fire)
			var st := MapGen.stats(L)
			tot += st.patrol_enemies + st.camp_enemies
		enemies_avg.append(tot / 50.0)
	var p2 := float(two) / cand2
	check(absf(p2 - 0.35) <= 0.1, "3.3 层主区固定 1 个入口，第 2 个按 0.35 开：150 张图里有 2 个以上相邻区块的 %d 张，开了 2 个入口的占 %.0f%%" % [cand2, p2 * 100])
	check(gap_ok, "3.3 层主区入口宽 480px（gap_px）")
	check(camp_guard_ok, "3.3 / §10-5 营地不在层主区周围 8 格（切比雪夫 ≤ 1 一个都没有），150 张图")
	check(path4_ok, "§10-2 起点到层主区最短路按打通边 4 邻接 BFS 计步，且 ≥ min_start_guard_dist")
	check(fire_ok, "3.3 篝火在入口外侧的空地上：离障碍 ≥ 60px、可达，150 张图")
	var exp_n := [56.0, 54.0, 72.0]
	var en_ok := true
	for i in 3:
		en_ok = en_ok and absf(enemies_avg[i] - exp_n[i]) / exp_n[i] <= 0.1
	check(en_ok, "3.1 全层敌人总数 50 种子均值：第 1 层 %.1f（约 56）、第 2 层 %.1f（约 54）、第 3 层 %.1f（约 72），误差 ≤ 10%%" % enemies_avg)
	check(count_ok, "OM4-1 营地、宝箱、资源点、神龛数量和设定精确相符（2 / 3 / 6 / 1），巡逻组 2~4 人、营地人数在区间内")
	check(patrol_ok, "OM4-1 巡逻组数 50 种子均值和期望（普通区块 × patrol_chance）误差 ≤ 15%%：%s" % "，".join(patrol_report))
	check(empty_ok, "OM4-2 起点区块和层主区内没有巡逻点 / 营地；巡逻路线点离障碍 ≥ 60px；宝箱/资源点离路线点 ≥ 150px")

# ---------------- T8 / T13.2 掉落 ----------------
func test_drops() -> void:
	print("== T8/T13 掉落 ==")
	var d: Dictionary = DP.drop_stats(1000)
	var ok := true
	var worst := 0.0
	for id in d:
		for k in d[id]:
			var diff: float = absf(d[id][k].got - d[id][k].want)
			worst = maxf(worst, diff)
			ok = ok and diff <= 0.03
	check(ok, "F1“刷 1000 只怪”：所有掉落项和设定误差 ≤ 3%%（最大 %.1f%%）" % (worst * 100))
	print("  ", DP.drop_stats_text(1000).replace("\n", "\n  "))

# ---------------- T10 / T13.3 继承 ----------------
func test_inheritance() -> void:
	print("== T10/T13 继承公式 ==")
	var lr := Lineage.legacy_rules
	var ok := true
	for lv in range(1, 11):
		ok = ok and lr.inherit_level(lv) == maxi(1, floori(lv * 0.3))
	check(ok and lr.inherit_level(6) == 1 and lr.inherit_level(7) == 2 and lr.inherit_level(10) == 3, "新个体等级 = max(1, floor(前任 × 0.3))：6→1、7→2、10→3")
	check(is_equal_approx(lr.mastery_ratio, 0.5) and is_equal_approx(lr.legacy_power, 0.5) and lr.legacy_pick_from == 3 and lr.legacy_max == 5, "熟练度 50%（只记录）、遗志 3 选 1、上限 5、遗志效果 50%")
	Lineage.wipe()
	var ind := Lineage.current()
	check(ind.name == "林·#0001" and ind.gen_no == 1, "第一个个体名字：%s" % ind.name)
	ind.level = 8
	ind.mastery = {"root_blade": 40}
	var n := Lineage.new_individual("blade")
	check(n.name == "林·#0002" and n.level == 2 and n.legacies == ["blade"] and int(n.mastery.root_blade) == 20, "新个体 %s：Lv8 → Lv%d，遗志 %s，熟练度 40 → %d" % [n.name, n.level, n.legacies, int(n.mastery.root_blade)])
	# 遗志 50%
	var m := Stats.collect(null)
	check(is_equal_approx(m.light_pct, 0.1), "遗志“利刃”按 50%% 生效：普攻 +%d%%" % roundi(m.light_pct * 100))
	lr.legacy_power = 1.0
	check(is_equal_approx(Stats.collect(null).light_pct, 0.2), "面板把 legacy_power 改成 1.0 后立即按 100% 生效")
	lr.legacy_power = 0.5
	check(DP.find_editor(lr, "legacy_power") != null, "legacy_power 在 F1 面板“遗志”分组里可调")
	# 上限 5 替换
	Lineage.current().legacies = ["blade", "gale", "afterimage", "rootbind", "thickhide"]
	var r := Lineage.new_individual("swift", 1)
	check(r.legacies.size() == 5 and r.legacies[1] == "swift", "遗志满 5 个时替换指定的一个：%s" % str(r.legacies))
	Lineage.wipe()

# ---------------- T9 / T13.4 保险箱 ----------------
func test_vault() -> void:
	print("== T9/T13 保险箱 ==")
	Lineage.wipe()
	check(Lineage.vault_capacity() == 4, "初始 4 格")
	check(not Lineage.vault_put("shard") and not Lineage.vault_put("moss"), "碎片、普通材料放不进去")
	var cons := ItemData.new()
	cons.id = "potion"
	cons.category = "consumable"
	var boon := ItemData.new()
	boon.category = "boon"
	check(not Lineage.vault_put(cons) and not Lineage.vault_put(boon), "消耗品、局内强化放不进去")
	var ok := true
	for id in ["trinket_hp", "trinket_atk", "moss_essence", "trinket_dash"]:
		ok = ok and Lineage.vault_put(id)
	check(ok and Lineage.vault.size() == 4, "装备、稀有材料可以放入")
	check(not Lineage.vault_put("trinket_hp"), "满了以后不能再放")
	var old := Lineage.vault_replace(0, "trinket_dash")
	check(old.id == "trinket_hp" and Lineage.vault[0].id == "trinket_dash", "满了可以替换已有物品")
	Lineage.mats.moss_essence = 2
	check(Lineage.upgrade_vault() and Lineage.vault_capacity() == 6 and Lineage.mats.moss_essence == 0, "花 2 个萤苔精升 1 级：容量 6")
	check(not Lineage.upgrade_vault(), "萤苔精不够（第 2 级要 4）不能升级")
	var it := Lineage.vault_take(0)
	check(it.id == "trinket_dash" and "trinket_dash" in Lineage.loadout, "取出装备 → 穿在身上（下潜时算局内装备）")

# ---------------- T13.5 存档 ----------------
func test_save() -> void:
	print("== T13 存档往返 ==")
	Lineage.flags["x"] = true
	Lineage.epitaphs.append({"gen_no": 1, "name": "林·#0001", "level": 3, "depth": 2, "cause": "测试", "time": "t", "last_words": ""})
	Lineage.save()
	var before := JSON.stringify(Lineage.to_dict())
	Lineage.reset_memory()
	Lineage.load_save()
	check(JSON.stringify(Lineage.to_dict()) == before, "写入再读取后数据一致（个体、墓志铭、保险箱、材料、标记）")
	check(Lineage.epitaphs[0].has("last_words"), "墓志铭预留 last_words 字段")
	Lineage.wipe()

# ---------------- 测试场景工具 ----------------
var arena: Node2D

func make_arena() -> Node2D:
	if arena and is_instance_valid(arena):
		arena.queue_free()
		await frames(2)
	arena = Node2D.new()
	get_tree().root.add_child(arena)
	return arena

func make_player(pos := Vector2(0, 0)) -> Player:
	var p := Player.new()
	p.position = pos
	arena.add_child(p)
	await frames(1)
	return p

func make_enemy(id: String, pos: Vector2, hp := -1) -> EnemyBase:
	var e := EnemyBase.new()
	e.setup(Game.enemies[id], 1)
	e.position = pos
	arena.add_child(e)
	if hp > 0:
		e.max_hp = hp
		e.hp = hp
	await frames(1)
	return e

class Src extends Node2D:
	var source_name := "测试"
	var stagger_sec := 0.0
	var slow_sec := 0.0

# ---------------- T2 主角 ----------------
func test_player() -> void:
	print("== T2 主角控制器 ==")
	Lineage.wipe()
	plain()
	Game.run = null
	await make_arena()
	var p := await make_player()
	var src := Src.new()
	arena.add_child(src)
	var hp0 := p.hp
	p.try_dash()
	await frames(2)
	check(p.state == Player.S.DASH and p.hurtbox.invulnerable, "冲刺中无敌（受击框变灰）")
	check(p.take_hit(10, src, Vector2.ZERO) == false and p.hp == hp0, "冲刺无敌帧内被命中不掉血")
	await secs(0.5)
	check(p.take_hit(10, src, Vector2(1, 0)) and p.hp == hp0 - 10, "无敌结束后正常受伤")
	await frames(3)
	var flick := false
	for i in 12:
		await frames(1)
		flick = flick or p.body_rect.modulate.a < 1.0
	check(p.take_hit(10, src, Vector2.ZERO) == false and p.hp == hp0 - 10 and flick, "受击后无敌时间内闪烁且不再掉血")
	await secs(0.7)
	# 冲刺充能
	var c0 := p.charges_ready()
	p.try_dash()
	await secs(0.25)
	p.try_dash()
	await secs(0.25)
	check(c0 == 2 and not p.try_dash(), "2 次充能用完后不能冲刺")
	await secs(1.0)
	check(p.charges_ready() == 2, "充能各自冷却（0.9 秒）后恢复")
	# 60 / 120 FPS 冲刺距离
	var dists := {}
	for fps in [60, 120]:
		Engine.physics_ticks_per_second = fps
		await frames(3)
		p.global_position = Vector2.ZERO
		p.sim_move = Vector2.RIGHT
		await frames(1)
		p.try_dash()
		await until(func(): return not (p.state == Player.S.DASH))
		p.sim_move = Vector2.ZERO
		dists[fps] = p.last_dash_distance
		await secs(1.0)
	Engine.physics_ticks_per_second = 60
	var err: float = absf(dists[60] - dists[120]) / dists[60]
	check(err < 0.03 and absf(dists[60] - 160.0) < 160 * 0.03, "60 FPS 冲刺 %.1f px、120 FPS %.1f px，误差 %.2f%%（< 3%%）" % [dists[60], dists[120], err * 100])

# ---------------- T3 普攻与技能 ----------------
func test_attacks() -> void:
	print("== T3 普攻与技能 ==")
	Lineage.wipe()
	plain()
	Game.run = null
	await make_arena()
	var p := await make_player()
	p.facing = Vector2.RIGHT
	p.sim_aim = Vector2.RIGHT
	var e := await make_enemy("shellbug", Vector2(60, 0), 9999)
	e.aggro = false
	e.set_physics_process(false)
	p.try_attack()
	await frames(2)
	check(p.state == Player.S.ATTACK and p.phase == "windup", "普攻第 1 段前摇")
	p.try_dash()
	await frames(1)
	check(p.state == Player.S.DASH and not p.hitbox.active, "普攻前摇可以被冲刺取消")
	await secs(1.2)
	p.global_position = Vector2.ZERO
	await frames(2)
	# 三连击，同一段只结算 1 次
	var dmgs := []
	for seg in 3:
		var before := e.hp
		p.try_attack()
		await until(func(): return not (p.state == Player.S.ATTACK and p.phase != "recovery"))
		await frames(3)
		dmgs.append(before - e.hp)
		await until(func(): return not (p.state == Player.S.ATTACK))
	check(dmgs == [10, 10, 16], "三连伤害 %s（10/10/16），每段对同一目标只结算 1 次" % str(dmgs))
	# 后摇可被冲刺取消
	p.try_attack()
	await until(func(): return not (p.phase != "recovery"))
	check(p.try_dash() and p.state == Player.S.DASH, "普攻后摇可以被冲刺取消")
	await secs(1.2)
	# combo_reset
	p.global_position = Vector2.ZERO
	p.try_attack()
	await until(func(): return not (p.state == Player.S.ATTACK))
	await secs(0.8)
	p.try_attack()
	await frames(1)
	check(p.atk == Game.attacks[0], "超过 combo_reset（0.6 秒）没接续回到第一段")
	await until(func(): return not (p.state == Player.S.ATTACK))
	# 参数立即生效
	Game.attacks[0].damage = 33
	await secs(0.8)
	var b2 := e.hp
	p.try_attack()
	await until(func(): return not (p.state == Player.S.ATTACK))
	check(b2 - e.hp == 33, "改 light_1.damage = 33 后下一下立即生效")
	Game.attacks[0].damage = 10
	# 技能 + HUD 冷却
	var hud := Hud.new()
	hud.player = p
	arena.add_child(hud)
	var b3 := e.hp
	p.try_skill()
	await until(func(): return not (p.state == Player.S.SKILL))
	await frames(2)
	check(b3 - e.hp == 40 and p.skill_cd_left > 5.0, "根须横扫造成 40 伤害，进入 6 秒冷却")
	check("秒" in hud.skill_text(), "技能冷却显示在 HUD：%s" % hud.skill_text())
	check(not p.try_skill(), "冷却中不能再放")

# ---------------- T4 敌人 ----------------
func test_enemies() -> void:
	print("== T4 敌人 ==")
	if arena and is_instance_valid(arena):
		arena.queue_free()
		await frames(2)
	Lineage.wipe()
	plain()
	Game.start_run()
	check(await wait_scene(Game.SCN_FLOOR), "进入第 1 层")
	var f := scene()
	for id in Game.enemies:
		var es: Array = DP.spawn_enemies(id, 1)
		await frames(2)
		check(es.size() == 1 and is_instance_valid(es[0]) and es[0].data.id == id, "F1 面板可单独刷出 %s" % Game.enemies[id].display_name)
		for x in es:
			x.queue_free()
	await frames(2)
	for e in get_tree().get_nodes_in_group("enemies"):
		e.queue_free()
	await frames(2)
	Game.god_mode = false
	for id in Game.enemies:
		for dodge in [false, true]:
			for e in get_tree().get_nodes_in_group("enemies"):
				e.queue_free()
			await frames(2)
			f.player.heal(999)
			f.player.iframe_left = 0.0
			var gp: Vector2 = f.player.global_position
			var dist: float = {"mushling": 60.0, "rootshot": 380.0, "shellbug": 90.0}[id]
			var e: EnemyBase = f.spawn_enemy(id, gp + Vector2(dist, 0))
			e.cooldown = 0.0
			if not await until(func(): return not (e.state != EnemyBase.S.WINDUP)):
				printerr("    调试：%s 状态 %d aggro %s cd %.2f 距离 %.0f 敌 %s 玩家 %s 玩家hp %d paused %s 场景 %s" % [id, e.state, e.aggro, e.cooldown, e.global_position.distance_to(f.player.global_position), e.global_position, f.player.global_position, f.player.hp, get_tree().paused, scene().name])
			var hp0: int = f.player.hp
			await until(func(): return not (e.state == EnemyBase.S.WINDUP and e.state_t < e.windup - 0.04))
			if dodge:
				f.player.sim_move = Vector2(0, 1)
				f.player.try_dash()
			await secs(1.5 if id == "rootshot" else 0.45)
			f.player.sim_move = Vector2.ZERO
			if dodge:
				check(f.player.hp == hp0, "%s 的攻击能靠冲刺躲开" % e.data.display_name)
				check(absf(e.last_windup_sec - e.windup) <= 1.0 / 60.0 + 0.001, "%s 预兆时长 %.3f 秒 = 参数 %.2f（±1 帧）" % [e.data.display_name, e.last_windup_sec, e.windup])
			else:
				check(f.player.hp < hp0, "%s 不躲会被打中（%d → %d）" % [e.data.display_name, hp0, f.player.hp])
			if is_instance_valid(e):
				e.queue_free()
			await secs(0.7)
			f.player.global_position = gp
	# 射手弹可以被普攻打消
	var pr := Projectile.new()
	pr.velocity = Vector2(-10, 0)
	pr.position = f.player.global_position + Vector2(50, 0)
	f.world.add_child(pr)
	f.player.sim_aim = Vector2.RIGHT
	f.player.try_attack()
	await secs(0.3)
	f.player.sim_aim = Vector2.ZERO
	check(not is_instance_valid(pr), "根须射手的子弹可以被普攻打消")
	# poise：甲虫 30 poise，一下 10 不硬直
	var sb: EnemyBase = f.spawn_enemy("shellbug", f.player.global_position + Vector2(300, 0))
	await frames(2)
	var src := Src.new()
	f.add_child(src)
	sb.take_hit(10, src, Vector2.ZERO)
	var no_stagger := sb.state != EnemyBase.S.HURT
	sb.take_hit(10, src, Vector2.ZERO)
	sb.take_hit(10, src, Vector2.ZERO)
	check(no_stagger and sb.state == EnemyBase.S.HURT, "硬壳甲虫 poise 30：累计 30 伤害才硬直")
	var mu: EnemyBase = f.spawn_enemy("mushling", f.player.global_position + Vector2(-300, 0))
	await frames(2)
	mu.take_hit(1, src, Vector2.ZERO)
	check(mu.state == EnemyBase.S.HURT, "普通怪 poise 0：一下就硬直")
	check(Game.enemies.mushling.max_hp == 30 and roundi(30 * Game.floors[2].hp_scale()) == 47 and roundi(12 * Game.floors[2].dmg_scale()) == 15, "楼层成长：小鬼 HP 30→第 3 层 47，甲虫伤害 12→15")
	for e in get_tree().get_nodes_in_group("enemies"):
		e.queue_free()
	check(not get_tree().paused, "T4 结束时游戏没有被弹窗暂停")

# ---------------- T5 层主 + T6 撤离 + T14 线索 2 ----------------
func kill_guard(f: Node) -> void:
	var src := Src.new()
	f.add_child(src)
	while is_instance_valid(f.guard) and f.guard.state != EnemyBase.S.DEAD:
		if not f.guard.invulnerable:
			f.guard.take_hit(f.guard.hp, src, Vector2.ZERO)
		await frames(1)

func test_guards_and_exit() -> void:
	print("== T5 层主 / T6 撤离点 / T14 系统日志 ==")
	var f := scene()
	check(DP.find_editor(Game.floors[0].guard, "affix_frenzy") != null, "词缀可以在面板上勾选组合")
	DP.set_guard_affix(Game.floors[0].guard, Game.affixes.frenzy, true)
	check(Game.floors[0].guard.affixes.size() == 3, "勾选“狂暴”后第 1 层层主 = 硬壳 + 孢子 + 狂暴")
	DP.set_guard_affix(Game.floors[0].guard, Game.affixes.frenzy, false)
	f.debug_guard()
	await frames(3)
	check(f.guard == null and not f.fence_up() and f.player.global_position.distance_to(f.layout.campfire_pos) < 1.0, "“传送到层主区”把主角放在入口外侧篝火旁，层主还没出现")
	f.debug_enter_guard_zone()
	await secs(0.5)
	check(f.guard != null and f.fence_up(), "OM2 走进层主区入口线：开口升起能量栅栏，层主出现")
	var ent: Dictionary = f.layout.guard_entrances[0]
	var fence_r: Rect2 = ent.gap
	f.player.global_position = fence_r.get_center() - Vector2(ent.dir) * 80.0
	f.player.sim_move = Vector2(ent.dir)
	await secs(1.5)
	f.player.sim_move = Vector2.ZERO
	var dpos: float = (f.player.global_position - fence_r.get_center()).dot(Vector2(ent.dir))
	check(dpos < 0.0 and f.guard_rect.has_point(f.player.global_position), "OM2-3 层主战期间栅栏不能穿过（朝外走 1.5 秒，主角停在栅栏内侧 %.0f px）" % -dpos)
	f.player.global_position = f.guard_entry_pos(true)
	await frames(2)
	check(f.guard.max_hp == 400 and f.guard.damage == 10 and f.guard.poise == 60.0 and is_equal_approx(f.guard.back_mult, 1.5), "第 1 层层主：HP 400、伤害 10、poise 60（硬壳 +100%）、背后 ×1.5")
	check(not f.exit_active and f.nearest_interactable().get("id", "") != "exit", "层主没死时撤离点不能互动")
	f.player.global_position = f.exit_pos
	await frames(2)
	check(not f.interact() or f.nearest_interactable().get("id", "") != "exit", "站在撤离点上也互动不了")
	var t_kill := Time.get_ticks_msec()
	await kill_guard(f)
	await frames(1)
	check(SysLog.is_showing() and "backup #0001" in SysLog.last_text and "sync OK" in SysLog.last_text, "第 1 层层主首杀闪出系统日志：%s" % SysLog.last_text)
	check(not get_tree().paused and f.player.input_enabled, "日志闪现不打断操作")
	await until(func(): return not (SysLog.is_showing()))
	check(absf(SysLog.last_duration - 0.35) <= 1.0 / 60.0 + 0.005, "日志显示 %.3f 秒（0.35 ± 1 帧）" % SysLog.last_duration)
	await until(func(): return not (not f.exit_active))
	check(f.exit_activated_at - f.guard_killed_at <= 1.0, "击杀后 %.2f 秒撤离点激活（≤ 1 秒）" % (f.exit_activated_at - f.guard_killed_at))
	check(f.nearest_interactable().get("id", "") == "exit", "层主死后撤离点可以互动")
	# 下潜
	f.choose_exit(true)
	check(await wait_scene(Game.SCN_FLOOR) and Game.run.depth == 2, "下潜：进入第 2 层")
	f = scene()
	check(f.depth == 2 and f.interactables.all(func(it): return it.id != "exit" or not it.enabled.call()), "第 2 层没有回第 1 层的路（下潜后无法返回）")
	f.debug_enter_guard_zone()
	await secs(0.5)
	check(f.guard.has_affix("summon") and f.guard.gdata.base_enemy.id == "rootshot", "第 2 层层主：射手 + 召唤")
	f.guard.summon_t = 9.99
	await secs(0.2)
	var sums: Array = f.guard_zone_enemies()
	check(sums.size() == 2 and sums.all(func(e): return f.guard_rect.has_point(e.home_pos) and e.home_pos.distance_to(f.player.global_position) >= 159.0), "召唤：一次召 2 只菌菇小鬼，刷在层主区内、离主角 ≥ 160px")
	Game.clues.log_repeat_chance = 0.0
	await kill_guard(f)
	await frames(1)
	check(SysLog.last_text == Game.clues.guard_log_2, "第 2 层首杀日志：%s" % SysLog.last_text)
	await until(func(): return not (not f.exit_active))
	f.choose_exit(true)
	await wait_scene(Game.SCN_FLOOR)
	f = scene()
	f.debug_enter_guard_zone()
	await secs(0.5)
	var g: Guard = f.guard
	check(g.max_hp == 1200 and g.damage == 9 and absf(g.windup - 1.35) < 0.001 and is_equal_approx(g.gdata.summon_every_mult, 1.5) and g.has_affix("hardshell") and g.has_affix("frenzy") and absf(g.effective_interval() - 1.5) < 0.01, "第 3 层层主：HP 1200、伤害 9、前摇 1.35 秒、召唤间隔 ×1.5、硬壳 + 狂暴、出手间隔 %.2f 秒" % g.effective_interval())
	var src := Src.new()
	f.add_child(src)
	g.take_hit(g.hp - 300, src, Vector2.ZERO)
	check(g.phase == 2 and g.invulnerable, "HP 降到 50% 进入二阶段演出，期间无敌")
	check(g.take_hit(50, src, Vector2.ZERO) == false, "演出中受击无效")
	var t0 := Time.get_ticks_msec()
	await until(func(): return not (g.invulnerable))
	var dur := (Time.get_ticks_msec() - t0) / 1000.0 * Game.base_time_scale
	check(absf(dur - 1.0) < 0.1 and g.has_affix("summon"), "二阶段演出约 %.2f 秒，之后加上召唤" % dur)
	await kill_guard(f)
	await frames(1)
	check(SysLog.last_text == Game.clues.guard_log_3, "第 3 层首杀日志：%s" % SysLog.last_text)
	await until(func(): return not (not f.exit_active))
	# 概率 0：第二次击杀不再闪
	SysLog.last_text = ""
	f.spawn_guard()
	await frames(2)
	await kill_guard(f)
	await frames(2)
	check(SysLog.last_text == "", "log_repeat_chance = 0 时第二次击杀不再出现")
	Game.clues.log_repeat_chance = 0.3
	check(Game.run.clue_seen.has("guard_log_1") and Game.run.clue_seen.has("guard_log_3"), "本局看到的线索记入 clue_seen：%s" % str(Game.run.clue_seen))
	var opts_before := Game.run.depth
	f.choose_exit(true)
	check(await wait_scene(Game.SCN_EXTRACT) and opts_before == 3, "第 3 层只能撤离（选下潜也进结算）")
	var got: Dictionary = Game.last_extract
	check(got.shards >= 4 and Lineage.shards_bank == got.shards and Lineage.mats.moss >= 28, "撤离带回全部：碎片 %d、萤苔 %d" % [got.shards, Lineage.mats.moss])

# ---------------- T7 强化 ----------------
func test_boons() -> void:
	print("== T7 局内强化 ==")
	scene().finish()
	await wait_scene(Game.SCN_VILLAGE)
	Lineage.wipe()
	plain()
	Game.start_run()
	await wait_scene(Game.SCN_FLOOR)
	var f := scene()
	f.offer_boons()
	await frames(2)
	var pop: ChoicePopup = null
	for c in f.get_children():
		if c is ChoicePopup:
			pop = c
	check(pop != null and get_tree().paused and pop.buttons.size() == 3, "3 选 1 弹出时暂停战斗")
	check(pop.buttons[0].has_focus(), "手柄/键盘焦点在第一个选项上")
	var ev := InputEventJoypadButton.new()
	ev.button_index = JOY_BUTTON_A
	ev.pressed = true
	Input.parse_input_event(ev)
	await get_tree().process_frame
	ev = ev.duplicate()
	ev.pressed = false
	Input.parse_input_event(ev)
	await frames(3)
	check(Game.run.boons.size() == 1 and not get_tree().paused, "手柄 A 选中强化（%s），战斗继续" % (Game.run.boons[0].display_name if Game.run.boons.size() else "无"))
	for b in Boons.all().slice(0, 6):
		Game.run.add_boon(b)
	var offer := Boons.offer(Game.run.boons, RandomNumberGenerator.new())
	check(offer.all(func(b): return not Game.run.boons.has(b)) and offer.size() == 8 - Game.run.boons.size(), "已有的强化不再出现（剩 %d 个候选）" % offer.size())
	Game.run.boons.clear()
	Game.run.boon_order.clear()
	DP.give_boon("thickhide")
	await frames(1)
	var hp_with: int = f.player.max_hp
	DP.give_boon("gale")
	DP.give_boon("swift")
	await frames(1)
	check(hp_with == 120 and f.player.dash_cd.size() == 3 and absf(f.player.skill_cooldown() - 4.5) < 0.01, "面板给予：厚皮 HP 120、疾风 3 次冲刺、迅捷技能冷却 4.5 秒")
	DP.remove_boon("thickhide")
	await frames(1)
	check(f.player.max_hp == 100, "面板移除强化后立即失效")
	DP.give_boon("blade")
	DP.give_boon("finisher")
	check(f.player.attack_damage(Game.attacks[2], 2) == roundi(16 * 1.2 * 1.5) and f.player.attack_damage(Game.attacks[0], 0) == 12, "利刃 +20%、终结 第三段 +50%")
	DP.give_boon("bloodthirst")
	f.player.hp = 50
	var mu: EnemyBase = f.spawn_enemy("mushling", f.player.global_position + Vector2(400, 0))
	await frames(2)
	var src := Src.new()
	f.add_child(src)
	mu.take_hit(999, src, Vector2.ZERO)
	await frames(2)
	check(f.player.hp == 52, "嗜血：击杀回 2 HP（50 → %d）" % f.player.hp)

# ---------------- T11 起程村 + T14 线索 1 ----------------
func test_village() -> void:
	print("== T11 起程村 ==")
	Lineage.wipe()
	Game.run = null
	Game.goto(Game.SCN_VILLAGE)
	await wait_scene(Game.SCN_VILLAGE)
	var v := scene()
	check(v.opening != null and "23:47" in v.opening_label.text, "第一次进入播放开场：%s" % v.opening_label.text)
	var lines := []
	while v.opening != null:
		if not v.opening_label.text in lines:
			lines.append(v.opening_label.text)
		await get_tree().process_frame
	check("【系统】打穿第 100 层就能回去。" in lines and "【系统】在这里死了，就是真的死了。" in lines and "有人推了我一把。" in lines, "开场：黑屏 2 行 + 系统旁白（含“死了就是真死”）")
	Game.goto(Game.SCN_VILLAGE)
	await wait_scene(Game.SCN_VILLAGE)
	v = scene()
	check(v.opening == null, "之后再进村不再播放开场")
	v.play_opening(true)
	await frames(2)
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_E
	ev.pressed = true
	Input.parse_input_event(ev)
	await frames(2)
	var ev2 := ev.duplicate()
	ev2.pressed = false
	Input.parse_input_event(ev2)
	await frames(2)
	check(v.opening == null, "布告栏重播开场可以跳过")
	var ok := true
	var names := []
	for fac in v.facilities:
		if fac.id == "well":
			continue
		v.player.global_position = fac.pos + Vector2(0, fac.size.y / 2 + 40)
		await frames(2)
		var near: Dictionary = v.nearest()
		var good: bool = near.get("id", "") == fac.id and v.interact()
		await frames(3)
		if v.panel_open:
			good = good and get_tree().paused and v.panel_open.box.find_children("*", "Button", true, false).any(func(b): return b.has_focus())
			v.panel_open.close()
			await frames(2)
		ok = ok and good
		if good:
			names.append(fac.name)
	check(ok, "所有设施都能走到并互动（64px 内有提示，面板有焦点）：%s" % "、".join(names))
	v.player.global_position = v.facility("npc").pos + Vector2(0, 80)
	await frames(2)
	v.interact()
	check("越深越好" in v.toast.text, "老冒险者对话：%s" % v.toast.text)

func test_death_flow() -> void:
	print("== T10 死亡 / 遗志 / T14 墓志铭 #0000 ==")
	Lineage.wipe()
	Game.base_time_scale = 4.0
	for k in 2:
		Game.start_run()
		await wait_scene(Game.SCN_FLOOR)
		var f := scene()
		for b in ["blade", "gale", "afterimage", "thickhide"]:
			DP.give_boon(b)
		Game.run.xp = 160 # Lv5
		Game.run.shards_carried = 3
		Game.run.add_item(ItemStack.new(Items.get_item("trinket_atk"), 1))
		DP.kill_self()
		check(await wait_scene(Game.SCN_DEATH, 10), "第 %d 次死亡：慢镜头后进入墓志铭" % (k + 1))
		var ds := scene()
		check("倒在第 1 层" in ds.label.text and Lineage.current().name in ds.label.text, "墓志铭显示名字、层数、死因")
		var saw_garble := false
		while scene() == ds:
			saw_garble = saw_garble or ds.garbled
			await get_tree().process_frame
		check(saw_garble, "死亡画面最后闪过乱码（RELOAD TEMPLATE）")
		check(await wait_scene(Game.SCN_LEGACY), "培养槽苏醒后进入遗志选择")
		var lp := scene()
		check(lp.candidates == ["gale", "afterimage", "thickhide"], "候选只有死亡时持有的最后 3 个强化：%s" % str(lp.candidates))
		check(Lineage.corpse.depth == 1 and Lineage.corpse.item == "trinket_atk" and Lineage.corpse.shards == 1, "尸体在第 1 层，带 1 件局内装备和剩下的碎片（3 个丢 2 个）")
		lp._pick("afterimage" if k == 0 else "thickhide")
		check(await wait_scene(Game.SCN_VILLAGE), "选择遗志后回村")
	var ind := Lineage.current()
	check(ind.gen_no == 3 and ind.name == "林·#0003" and ind.level == 1 and ind.legacies == ["afterimage", "thickhide"], "第 3 代 %s：Lv5 → Lv%d，遗志 %s" % [ind.name, ind.level, str(ind.legacies)])
	check(Log.rows("deaths").size() == 3, "deaths.csv 记了 2 次死亡")
	Game.base_time_scale = 1.0
	# 墓志铭墙
	var v := scene()
	var wall: Panel2 = v._open("res://scenes/village/epitaph_wall.gd")
	await frames(3)
	var texts: Array = wall.body.get_children().filter(func(c): return c is Button).map(func(b): return b.text)
	check(texts.size() == 3 and "林·#0001" in texts[0] and "林·#0002" in texts[1], "墓志铭墙显示所有前任")
	check(wall.ghost != null and wall.ghost_text() == Game.clues.epitaph0_raw, "死过 2 次后最底部出现灰色 #0000")
	wall.ghost.grab_focus()
	await secs(1.0)
	check(wall.fix_progress < 0.0, "悬停不到 2 秒不修复")
	await secs(1.3)
	check(wall.fix_progress >= 0.0 and wall.ghost_text() != Game.clues.epitaph0_raw, "悬停 2 秒后开始逐字修复")
	await secs(1.2)
	check(wall.ghost_text() == Game.clues.epitaph0_fixed and Lineage.flags.get("clue_epitaph0", false), "修复完成：%s" % wall.ghost_text())
	wall.close()
	Lineage.reset_memory()
	Lineage.load_save()
	var w2: Panel2 = v._open("res://scenes/village/epitaph_wall.gd")
	await frames(3)
	check(w2.ghost_text() == Game.clues.epitaph0_fixed, "重启（重新读档）后保持修复状态")
	w2.close()
	await frames(2)
	# 尸体回收
	Game.start_run()
	await wait_scene(Game.SCN_FLOOR)
	var f := scene()
	var corpse_it: Dictionary = {}
	for it in f.interactables:
		if it.id == "corpse":
			corpse_it = it
	check(not corpse_it.is_empty() and f.layout.chunks[MapGen.chunk_at(f.layout, corpse_it.pos)].type == "start", "到达同一层时起点区块有前任尸体")
	f.player.global_position = corpse_it.pos
	await frames(2)
	f.interact()
	check(Game.run.equipped.any(func(s): return s.item.id == "trinket_atk") and Game.run.shards_carried == 1 and Lineage.corpse.is_empty(), "回收到前任的装备和碎片，尸体消失")
	check(not f.interact() and f.nearest_interactable().get("id", "") != "corpse", "OM2-2 尸体只能回收一次")

# ---------------- T1 全流程（键盘 / 手柄） ----------------
func press(ev: InputEvent) -> void:
	ev.pressed = true
	Input.parse_input_event(ev)
	await frames(2)
	var up := ev.duplicate()
	up.pressed = false
	Input.parse_input_event(up)
	await frames(2)

func key(k: int) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = k
	e.keycode = k
	return e

func joy(b: int) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = b
	return e

func test_full_flow_input() -> void:
	print("== T1 全流程（键盘 / 手柄） ==")
	Lineage.wipe()
	Lineage.flags["opening_seen"] = true
	for dev in ["kb", "joy"]:
		Game.goto(Game.SCN_VILLAGE)
		await wait_scene(Game.SCN_VILLAGE)
		var v := scene()
		v.player.global_position = v.facility("well").pos + Vector2(0, -120)
		await frames(2)
		await press(key(KEY_E) if dev == "kb" else joy(JOY_BUTTON_B))
		check(await wait_scene(Game.SCN_FLOOR), "%s：村里井口互动 → 下潜第 1 层" % ("键盘 E" if dev == "kb" else "手柄 B"))
		var f := scene()
		# 用输入移动和攻击
		var x0: float = f.player.global_position.x
		var right: InputEvent = key(KEY_D) if dev == "kb" else InputEventJoypadMotion.new()
		if dev == "joy":
			right.axis = JOY_AXIS_LEFT_X
			right.axis_value = 1.0
			Input.parse_input_event(right)
		else:
			right.pressed = true
			Input.parse_input_event(right)
		await secs(0.3)
		if dev == "joy":
			right.axis_value = 0.0
			Input.parse_input_event(right)
		else:
			right.pressed = false
			Input.parse_input_event(right)
		await frames(2)
		check(f.player.global_position.x > x0 + 40, "%s移动" % ("键盘 D " if dev == "kb" else "左摇杆 "))
		await press(key(KEY_J) if dev == "kb" else joy(JOY_BUTTON_X))
		check(f.player.state == Player.S.ATTACK, "%s普攻" % ("键盘 J " if dev == "kb" else "手柄 X "))
		await secs(0.5)
		await press(key(KEY_SPACE) if dev == "kb" else joy(JOY_BUTTON_A))
		check(f.player.state == Player.S.DASH, "%s冲刺" % ("空格 " if dev == "kb" else "手柄 A "))
		await secs(0.4)
		f.debug_enter_guard_zone()
		await secs(0.4)
		await kill_guard(f)
		await until(func(): return not (not f.exit_active))
		f.player.global_position = f.exit_pos
		await frames(2)
		await press(key(KEY_E) if dev == "kb" else joy(JOY_BUTTON_B))
		await frames(3)
		await press(key(KEY_ENTER) if dev == "kb" else joy(JOY_BUTTON_A))
		check(await wait_scene(Game.SCN_EXTRACT), "撤离点选“撤离” → 结算")
		var ex := scene()
		var focus_ok: bool = ex.box.get_children().any(func(b): return b is Button and b.has_focus())
		check(focus_ok, "结算界面有焦点")
		ex.finish()
		check(await wait_scene(Game.SCN_VILLAGE), "回村")
	# 层中死亡 → 遗志 → 回村（全键盘）
	Game.start_run()
	await wait_scene(Game.SCN_FLOOR)
	DP.give_boon("blade")
	scene().player.kill_self()
	await wait_scene(Game.SCN_LEGACY, 15)
	await frames(3)
	await press(key(KEY_ENTER))
	check(await wait_scene(Game.SCN_VILLAGE), "层中死亡 → 墓志铭 → 遗志（回车选择）→ 回村")
	check(Lineage.current().legacies == ["blade"], "回车选中了第一个候选（利刃）")

# ---------------- T12 CSV ----------------
func test_csv() -> void:
	print("== T12 CSV ==")
	Log.clear()
	Game.start_run()
	await wait_scene(Game.SCN_FLOOR)
	var f := scene()
	var t0 := Time.get_ticks_msec()
	var e: EnemyBase = f.spawn_enemy("mushling", f.player.global_position + Vector2(60, 0))
	e.cooldown = 0.0
	await secs(1.5)
	# OM11：第 2 次交战（脱战 > encounter_gap_sec 后再打）、清 1 个营地、采 1 个资源点、走过多个区块
	Game.god_mode = true
	var sc := Src.new()
	f.add_child(sc)
	if is_instance_valid(e): e.take_hit(999, sc, Vector2.ZERO)
	await secs(f.aggro.encounter_gap_sec / Engine.time_scale + 0.5)
	var e2: EnemyBase = f._map_enemy("mushling", f.player.global_position + Vector2(60, 0), "csv")
	await until(func(): return f.director.chasers_peak >= 1, 4.0)
	if is_instance_valid(e2): e2.take_hit(999, sc, Vector2.ZERO)
	await frames(2)
	var cid: int = f.layout.spawn_points.camp[0].chunk
	for m in get_tree().get_nodes_in_group("enemies"):
		if m.get_meta("camp", -1) == cid:
			m.take_hit(9999, sc, Vector2.ZERO)
	f._take_node("node_0")
	await clear_enemies()
	f.player.global_position = f.layout.campfire_pos
	await secs(0.3)
	Game.god_mode = false
	f.debug_enter_guard_zone()
	await secs(0.5)
	await kill_guard(f)
	await until(func(): return not (not f.exit_active))
	await secs(1.0)
	var real := (Time.get_ticks_msec() - t0) / 1000.0
	f.choose_exit(false)
	await wait_scene(Game.SCN_EXTRACT)
	var fl := Log.rows("floors")
	var hits := Log.rows("hits")
	check(fl.size() == 2 and fl[0] == Log.HEADERS.floors, "floors.csv 表头 + 1 行：%s" % (fl[1] if fl.size() > 1 else ""))
	var cols: PackedStringArray = fl[1].split(",")
	var hdr: PackedStringArray = Log.HEADERS.floors.split(",")
	var newc := {}
	for c in ["chunks_visited", "encounters", "chasers_peak", "camps_cleared", "nodes_taken"]:
		var ix := hdr.find(c)
		newc[c] = cols[ix] if ix >= 0 and ix < cols.size() else ""
	check(newc.values().all(func(v): return v != "" and v.is_valid_int()) and int(newc.chunks_visited) >= 2 and int(newc.encounters) == 2 and int(newc.chasers_peak) >= 1 and int(newc.camps_cleared) == 1 and int(newc.nodes_taken) == 1,
		"OM11 floors.csv 新列都有值：%s（走过 2+ 区块、交战 2 次、追击峰值 ≥1、清 1 营地、采 1 资源点）" % str(newc))
	check(cols[4] == "extract" and absf(float(cols[5]) - real) < 1.0, "floor_sec %s 秒，和计时器 %.1f 秒误差 < 1 秒" % [cols[5], real])
	check(float(cols[7]) > 0.0 and cols.size() == Log.HEADERS.floors.split(",").size(), "guard_sec 有值，列数和表头一致")
	check(hits.size() > 2, "hits.csv 有 %d 行" % (hits.size() - 1))
	scene().finish()
	await wait_scene(Game.SCN_VILLAGE)
	DP.kill_self()
	await wait_scene(Game.SCN_LEGACY, 15)
	scene()._pick("-")
	await wait_scene(Game.SCN_VILLAGE)
	var ds := Log.rows("deaths")
	check(ds.size() == 2 and ds[0] == Log.HEADERS.deaths, "deaths.csv 有数据：%s" % (ds[1] if ds.size() > 1 else ""))
	check(Log.download_all() == 3, "三张表都可下载（网页版逐个下载）")

# ---------------- OM2 开放地图互动：篝火 / 宝箱 / 资源点 / 神龛 / 营地神龛 ----------------
func hold_interact(sec: float) -> void:
	Input.action_press("interact")
	await secs(sec)
	Input.action_release("interact")
	await frames(2)

func find_it(f: Node, key: String) -> Dictionary:
	for it in f.interactables:
		if it.key == key:
			return it
	return {}

func test_open_map() -> void:
	print("== OM2 开放地图：篝火 / 宝箱 / 资源点 / 神龛 / 营地 ==")
	Lineage.wipe()
	plain()
	Game.auto_pick = 0
	Game.god_mode = true
	Game.start_run()
	await wait_scene(Game.SCN_FLOOR)
	var f := scene()
	var L: Dictionary = f.layout
	check(f.layout.chunks.size() == 30 and f.player.global_position.distance_to(L.start_pos) < 1.0 and L.chunks[MapGen.chunk_at(L, f.player.global_position)].type == "start", "第 1 层是 6×5 区块的开放地图，主角在起点区块中心")
	check(f.get_node_or_null("Nav") is NavigationRegion2D and f.nav_ready and f.wall_rects.size() == MapGen.all_solids(L).size(), "floor.tscn 有 NavigationRegion2D，烘焙成功；墙和障碍全部生成（%d 个实心矩形）" % f.wall_rects.size())
	var st: Dictionary = f.map_stats()
	var on_map := get_tree().get_nodes_in_group("enemies")
	check(on_map.size() == st.patrol_enemies + st.camp_enemies and on_map.all(func(e): var k := MapGen.chunk_at(L, e.global_position); return k != L.start_chunk and k != L.guard_chunk), "OM4-2 开局刷出巡逻 %d + 营地 %d 只，起点区块和层主区里没有普通怪" % [st.patrol_enemies, st.camp_enemies])
	check(on_map.all(func(e): return e.ai != null and (e.state == EnemyBase.S.PATROL or e.state == EnemyBase.S.ALERT)), "开局所有普通怪在巡逻 / 待机，没有人在追（离起点都超过 720px）")
	# 篝火
	f.player.hp = 40
	f.player.global_position = L.campfire_pos + Vector2(0, 30)
	await frames(2)
	var fire_ok: bool = f.interact()
	check(fire_ok and f.player.hp == 40 + roundi(f.player.max_hp * 0.3) and not f.interact(), "篝火（层主区入口外侧）回复 30%%（40 → %d），只能用一次" % f.player.hp)
	check(not f.guard_rect.has_point(L.campfire_pos) and L.campfire_pos.distance_to(f.guard_entry_pos(false)) < 80.0, "篝火在层主区入口外侧约 200px")
	# 宝箱：长按 0.6 秒
	var ch: Dictionary = find_it(f, "chest_0")
	f.player.global_position = ch.pos + Vector2(0, 30)
	await frames(2)
	var moss0: int = Game.run.count_of("moss")
	check(not f.interact() and "长按" in f.hud.prompt.text, "宝箱要长按，按一下打不开（提示：%s）" % f.hud.prompt.text)
	Input.action_press("interact")
	await secs(0.35)
	var mid: bool = f.used.has("chest_0")
	await secs(0.4)
	Input.action_release("interact")
	await frames(2)
	check(not mid and f.used.has("chest_0") and Game.run.count_of("moss") - moss0 >= 3, "长按 0.6 秒打开宝箱（0.35 秒时还没开），萤苔 +%d" % (Game.run.count_of("moss") - moss0))
	var moss1: int = Game.run.count_of("moss")
	await hold_interact(0.8)
	check(Game.run.count_of("moss") == moss1 and f.nearest_interactable().get("key", "") != "chest_0", "同一个宝箱只能开一次")
	# 资源点：长按 1.0 秒，萤苔 ×1
	var nd: Dictionary = find_it(f, "node_0")
	f.player.global_position = nd.pos + Vector2(0, 30)
	await frames(2)
	Input.action_press("interact")
	await secs(0.7)
	var nmid: bool = f.used.has("node_0")
	await secs(0.45)
	Input.action_release("interact")
	await frames(2)
	check(not nmid and f.used.has("node_0") and Game.run.count_of("moss") - moss1 == 1, "资源点长按 1.0 秒采集（0.7 秒时还没好），萤苔 ×%d" % (Game.run.count_of("moss") - moss1))
	await hold_interact(1.2)
	check(Game.run.count_of("moss") - moss1 == 1, "同一个资源点只能采一次")
	# 强化神龛
	var sh: Dictionary = find_it(f, "shrine_0")
	f.player.global_position = sh.pos + Vector2(0, 30)
	await frames(2)
	var b0: int = Game.run.boons.size()
	f.interact()
	await frames(4)
	check(Game.run.boons.size() == b0 + 1 and not f.interact(), "强化神龛 3 选 1，只能用一次")
	# 营地神龛：清空营地才点亮
	var cid: int = L.camps[0]
	var cs: Dictionary = find_it(f, "camp_shrine_%d" % cid)
	f.player.global_position = cs.pos + Vector2(0, 30)
	await frames(2)
	check(f.nearest_interactable().get("key", "") != cs.key and not f.camps_state[cid].cleared, "营地没清空时营地神龛不能用")
	var src := Src.new()
	f.add_child(src)
	var members: Array = f.enemies_in_group("c%d" % cid)
	check(members.size() == f.camps_state[cid].total and members.size() >= f.fd.camp_size_min, "营地 %s 有 %d 只怪（同组 meta group / camp）" % [f.chunk_label(cid), members.size()])
	for e in members:
		e.take_hit(99999, src, Vector2.ZERO)
	await frames(3)
	check(f.camps_state[cid].cleared and f.nearest_interactable().get("key", "") == cs.key, "营地清空后营地神龛点亮")
	b0 = Game.run.boons.size()
	f.interact()
	await frames(4)
	check(Game.run.boons.size() == b0 + 1 and not f.interact(), "营地神龛 3 选 1，只能用一次")
	check(not get_tree().paused, "互动结束后游戏没有被暂停")
	# 地图统计 / 区块网格（F1）
	DP.show_chunks = true
	await frames(2)
	var labels: Array = f.chunk_overlay.find_children("*", "Label", true, false)
	check(f.chunk_overlay.visible and labels.size() == 30 and labels.any(func(l): return "层主区" in l.text) and labels.any(func(l): return "营地" in l.text), "F1“显示区块网格”：显示区块编号和类型（%s …）" % labels[0].text)
	DP.show_chunks = false
	var txt: String = DP.map_stats_text()
	check("巡逻组" in txt and "宝箱 3，资源点 6，强化神龛 1，营地神龛 2" in txt, "F1“地图统计”：%s" % txt.replace("\n", " / "))
	var fd1: FloorData = Game.floors[0]
	check(DP.find_editor(fd1, "patrol_chance") != null and DP.find_editor(fd1, "chunk_px") != null and DP.find_editor(fd1, "gap_px") != null and is_equal_approx(Game.floors[1].patrol_chance, 0.6), "新 FloorData 字段在 F1“楼层”分组可调；第 2 层 patrol_chance = 0.60")
	Game.auto_pick = -1
	Game.god_mode = false

# ---------------- M1 临时仇恨规则 ----------------
func clear_enemies() -> void:
	for e in get_tree().get_nodes_in_group("enemies"):
		e.queue_free()
	await frames(2)

## 在 E 附近找一个方向 dir：E + dir*front 和 E - dir*back 都是空地，且与 E 之间没有墙
func open_line(f: Node, E: Vector2, front: float, back: float) -> Vector2:
	var solids := MapGen.all_solids(f.layout)
	var space: PhysicsDirectSpaceState2D = f.get_world_2d().direct_space_state
	for i in 16:
		var d := Vector2.from_angle(TAU * i / 16.0)
		var a := E + d * front
		var b := E - d * back
		if not MapGen.is_free(a, solids, 40.0) or not MapGen.is_free(b, solids, 40.0):
			continue
		if space.intersect_ray(PhysicsRayQueryParameters2D.create(E, a, 1)).is_empty() and space.intersect_ray(PhysicsRayQueryParameters2D.create(E, b, 1)).is_empty():
			return d
	return Vector2.ZERO

## 一块开阔的空地（巡逻点是离障碍 ≥ 90px 的空地）
func open_spots(f: Node) -> Array:
	var out: Array = [f.layout.start_pos]
	for p in f.layout.spawn_points.patrol:
		out += p.points
	return out

## 切换本层是否用按层覆盖（false = 全局参数），并立刻同步到本层生效的 rules
func _sync_rules(f: Node, use_override: bool) -> void:
	if not f.fd.has_meta("_ov"):
		f.fd.set_meta("_ov", f.fd.aggro_override)
	f.fd.aggro_override = f.fd.get_meta("_ov") if use_override else null
	(load("res://data/aggro_rules.tres") as AggroRules).effective(f.fd.aggro_override, f.aggro)

func test_aggro() -> void:
	print("== M2 仇恨：视野锥 / 声音 / 联动 / 回归 / 追击上限 / 小地图 / 休眠 ==")
	var f := scene()
	Game.god_mode = true
	await clear_enemies()
	var R: AggroRules = f.aggro
	var base: AggroRules = load("res://data/aggro_rules.tres")
	check(f.depth == 1 and is_equal_approx(R.link_chance, 0.2) and is_equal_approx(R.sight_confirm_sec, 0.7) and is_equal_approx(base.link_chance, 0.5) and is_equal_approx(base.sight_confirm_sec, 0.4)
		and is_equal_approx(Game.floors[1].aggro_override.link_chance, 0.35) and Game.floors[2].aggro_override == null,
		"2.7 按层覆盖：第 1 层联动 %.2f / 确认 %.1f s，第 2 层联动 %.2f，第 3 层用全局 %.2f / %.1f s" % [R.link_chance, R.sight_confirm_sec, Game.floors[1].aggro_override.link_chance, base.link_chance, base.sight_confirm_sec])
	check(DP.find_editor(base, "sight_range") != null and DP.find_editor(base, "max_chasers") != null and DP.find_editor(Game.floors[0].aggro_override, "link_chance") != null, "仇恨参数（全局 + 第 1/2 层覆盖）都在 F1“仇恨”分组可调")
	# ---- 2.8-1 视野锥 ----
	var E: Vector2 = f.layout.start_pos
	var dir := open_line(f, E, 330.0, 220.0)
	for conf in [[true, R.sight_confirm_sec], [false, 0.4]]:
		_sync_rules(f, conf[0])
		var want: float = conf[1]
		var e: EnemyBase = f._map_enemy("mushling", E, "t")
		await frames(2)
		e.facing = dir
		f.player.global_position = E - dir * 200.0
		var noticed := false
		var t := 0.0
		while t < 3.0:
			await frames(1)
			t += Engine.time_scale / Engine.physics_ticks_per_second
			e.facing = dir
			noticed = noticed or e.state != EnemyBase.S.PATROL
		check(not noticed, "2.8-1 主角在背后 200px（视野锥外）：3 秒内没察觉（%s）" % ("第 1 层参数" if conf[0] else "全局参数"))
		f.player.global_position = E + dir * 300.0
		t = 0.0
		var t_alert := -1.0
		while t < 2.0 and e.state != EnemyBase.S.CHASE:
			await frames(1)
			t += Engine.time_scale / Engine.physics_ticks_per_second
			if t_alert < 0.0 and e.state == EnemyBase.S.ALERT:
				t_alert = t
		check(e.state == EnemyBase.S.CHASE and t >= want - 0.02 and t <= want + 0.15 and t_alert >= 0.0 and t_alert < 0.15, "2.8-1 正面 300px 进入视野锥：%.2f s 警觉，%.2f s 进入追击（确认时间 %.1f s，检测间隔 0.1 s）" % [t_alert, t, want])
		e.queue_free()
		await frames(2)
	# 墙后看不到：找一个障碍矩形，敌人和主角分在两侧
	_sync_rules(f, true)
	var solids := MapGen.all_solids(f.layout)
	var space: PhysicsDirectSpaceState2D = f.get_world_2d().direct_space_state
	var wall_pair := []
	for c in f.layout.chunks:
		if wall_pair.size() > 0 or c.type == "guard":
			continue
		for o in c.obstacles:
			var ep: Vector2 = o.get_center() - Vector2(o.size.x / 2 + 90, 0)
			var pp: Vector2 = o.get_center() + Vector2(o.size.x / 2 + 90, 0)
			if o.size.x >= 128 and MapGen.is_free(ep, solids, 40) and MapGen.is_free(pp, solids, 40) and not space.intersect_ray(PhysicsRayQueryParameters2D.create(ep, pp, 1)).is_empty() and not f.guard_rect.grow(300).has_point(ep):
				wall_pair = [ep, pp]
				break
	var e3: EnemyBase = f._map_enemy("mushling", wall_pair[0], "t")
	await frames(2)
	e3.facing = Vector2.RIGHT
	f.player.global_position = wall_pair[1]
	var seen := false
	for i in 90:
		await frames(1)
		e3.facing = Vector2.RIGHT
		seen = seen or e3.state != EnemyBase.S.PATROL
	check(not seen and e3.global_position.distance_to(wall_pair[1]) > e3.rules.sense_radius, "2.2 墙后看不到：正对主角、%.0f px，但射线被障碍挡住 → 1.5 秒没察觉" % e3.global_position.distance_to(wall_pair[1]))
	e3.queue_free()
	await frames(2)
	# ---- 2.9 有机地形下的视线：水、断崖不挡；灌木、岩石挡；树丛边缘视野 ×0.7 ----
	var pairs := {}
	for c in f.layout.chunks:
		if c.type == "guard":
			continue
		for i in c.obstacles.size():
			var kind: int = c.obstacle_kinds[i]
			if pairs.has(kind):
				continue
			var o: Rect2 = c.obstacles[i]
			for axo in [[Vector2(1, 0), 100.0], [Vector2(0, 1), 100.0], [Vector2(1, 0), 70.0], [Vector2(0, 1), 70.0], [Vector2(1, 0), 140.0], [Vector2(0, 1), 140.0]]:
				var ax: Vector2 = axo[0]
				var half: float = (o.size.x if ax.x > 0 else o.size.y) / 2.0
				if half * 2.0 > 300.0 or pairs.has(kind):
					continue
				var ep: Vector2 = o.get_center() - ax * (half + axo[1])
				var pp: Vector2 = o.get_center() + ax * (half + axo[1])
				if not MapGen.is_free(ep, solids, 40) or not MapGen.is_free(pp, solids, 40) or f.guard_rect.grow(300).has_point(ep) or ep.distance_to(pp) > 480.0:
					continue
				if space.intersect_ray(PhysicsRayQueryParameters2D.create(ep, pp, 1)).is_empty():
					continue ## 要求两点之间确实有障碍挡着移动
				var opaque_hit := not space.intersect_ray(PhysicsRayQueryParameters2D.create(ep, pp, MapGen.OPAQUE_LAYER)).is_empty()
				if opaque_hit != MapGen.blocks_sight(kind):
					continue ## 射线上还有别的种类的障碍，换一个
				if MapGen.near_thicket(f.layout, pp) or MapGen.near_thicket(f.layout, ep):
					continue
				pairs[kind] = [ep, pp]
				break
	for kind in [MapGen.T_WATER, MapGen.T_CLIFF, MapGen.T_THICKET, MapGen.T_ROCK]:
		if not pairs.has(kind):
			check(false, "2.9 第 1 层找不到合适的%s样本" % MapGen.KIND_NAMES[kind])
			continue
		var ep2: Vector2 = pairs[kind][0]
		var pp2: Vector2 = pairs[kind][1]
		f.player.global_position = pp2
		var ek: EnemyBase = f._map_enemy("mushling", ep2, "t")
		ek.facing = (pp2 - ep2).normalized()
		var got := false
		for i in 90:
			await frames(1)
			ek.facing = (pp2 - ep2).normalized()
			got = got or ek.state != EnemyBase.S.PATROL
		var want_see := not MapGen.blocks_sight(kind)
		check(got == want_see, "2.9 隔着%s（%.0f px）：%s" % [MapGen.KIND_NAMES[kind], ep2.distance_to(pp2), "能被看见" if want_see else "看不见"])
		ek.queue_free()
		await frames(2)
	# 树丛边缘：找一个灌木旁 64px 内的点
	var bush := Vector2.INF
	for c in f.layout.chunks:
		if bush != Vector2.INF or c.type == "guard":
			continue
		for i in c.obstacles.size():
			if c.obstacle_kinds[i] != MapGen.T_THICKET:
				continue
			var o: Rect2 = c.obstacles[i]
			for q in [Vector2(o.end.x + 40, o.get_center().y), Vector2(o.position.x - 40, o.get_center().y), Vector2(o.get_center().x, o.end.y + 40), Vector2(o.get_center().x, o.position.y - 40)]:
				if MapGen.is_free(q, solids, 30) and MapGen.near_thicket(f.layout, q):
					bush = q
					break
			if bush != Vector2.INF:
				break
	f.player.global_position = bush
	await secs(0.15)
	var ex: EnemyBase = f._map_enemy("mushling", bush + Vector2(2000, 0), "t")
	await frames(2)
	var r_in: float = ex.ai.sight_range()
	f.player.global_position = E
	await secs(0.15)
	var r_out: float = ex.ai.sight_range()
	check(f.player_in_thicket == false and absf(r_in - R.sight_range * 0.7) < 0.5 and absf(r_out - R.sight_range) < 0.5, "2.9 树丛潜行：主角在灌木边缘 64px 内时敌人视野 %.0f px（×0.7），离开后 %.0f px" % [r_in, r_out])
	ex.queue_free()
	await frames(2)
	# 声音不穿层主区围墙
	var gin0: Vector2 = f.guard_entry_pos(true)
	var eg: EnemyBase = f._map_enemy("mushling", f.guard_rect.get_center() + Vector2(0, 0), "t")
	await frames(2)
	var heard_in := false
	NoiseBus.emit(f.guard_rect.get_center() + (f.guard_rect.get_center() - gin0).normalized() * -700.0, 900.0, "test")
	heard_in = eg.state != EnemyBase.S.PATROL
	check(not heard_in, "2.9 声音不穿层主区围墙：墙外 700px 的 900px 声音，墙里的怪听不到")
	eg.queue_free()
	await frames(2)
	# ---- 2.8-2 冲刺声音 ----
	var e: EnemyBase = f._map_enemy("mushling", E, "t")
	await frames(2)
	e.facing = dir
	f.player.global_position = E - dir * 300.0
	await frames(3)
	f.player.try_dash()
	await frames(2)
	var turned := e.facing.dot(-dir) > 0.9
	check(e.state == EnemyBase.S.ALERT and turned and e.ai.investigate_goal.distance_to(E) <= R.investigate_px + 1.0, "2.8-2 背后 300px 冲刺（声音 %.0f px）：巡逻怪转身警觉，朝声源走 %.0f px" % [R.noise_dash, e.ai.investigate_goal.distance_to(E)])
	e.queue_free()
	await frames(2)
	f.player.global_position = E - dir * 160.0
	e = f._map_enemy("mushling", E, "t")
	e.facing = dir
	await frames(2)
	e.facing = dir
	await frames(3)
	f.player.try_dash()
	await frames(2)
	check(e.state == EnemyBase.S.CHASE, "声源在 0.5 倍半径（180 px）以内：直接追击")
	e.queue_free()
	await frames(2)
	f.player.global_position = E - dir * 420.0
	e = f._map_enemy("mushling", E, "t")
	await frames(2)
	e.facing = dir
	await frames(3)
	f.player.try_dash()
	await frames(2)
	check(e.state == EnemyBase.S.PATROL, "360px 外冲刺（%.0f px）：听不到（状态 %d，声源 %s，主角 %s，敌人 %s 朝向 %s）" % [e.global_position.distance_to(E - dir * 420.0), e.state, e.ai.alert_src, f.player.global_position, e.global_position, e.facing])
	e.queue_free()
	await clear_enemies()
	# ---- 2.8-3 同组联动 + 跨组联动（50 次）----
	_sync_rules(f, false) ## 全局 link_chance 0.5
	var spots := open_spots(f)
	var group_ok := 0
	var linked := 0
	var trials := 0
	var far_none := true
	for i in 50:
		var c: Vector2 = spots[i % spots.size()] + Vector2(i * 3, 0)
		var a: Array = []
		for k in 3:
			a.append(f._map_enemy("mushling", c + Vector2(0, 50 * k), "ga%d" % i))
		var b: EnemyBase = f._map_enemy("mushling", c + Vector2(300, 0), "gb%d" % i)
		var far: EnemyBase = f._map_enemy("mushling", c + Vector2(-500, 0), "gc%d" % i)
		f.player.global_position = c + Vector2(0, 900) if c.y < 2500 else c - Vector2(0, 900) ## 视野外、拴绳内
		await frames(2)
		a[0].take_hit(1, f.player, Vector2.ZERO)
		await frames(1)
		trials += 1
		if a.all(func(x): return x.ai.in_combat()):
			group_ok += 1
		if b.ai.in_combat():
			linked += 1
		far_none = far_none and not far.ai.in_combat()
		for x in a + [b, far]:
			x.queue_free()
		await frames(2)
	check(group_ok == 50, "2.8-3 打一只，同组 3 只全部进入追击（%d / 50）" % group_ok)
	var rate := float(linked) / trials
	check(rate >= 0.3 and rate <= 0.7 and far_none, "2.8-3 380px 内别组巡逻怪被拉进来 %d / %d = %.0f%%（link_chance %.2f，“约一半”按 30%%~70%% 判）；500px 外的从不被拉" % [linked, trials, rate * 100, base.link_chance])
	_sync_rules(f, true)
	var lk := 0
	for i in 50:
		var c: Vector2 = spots[i % spots.size()] + Vector2(i * 3, 0)
		var a0: EnemyBase = f._map_enemy("mushling", c, "ha%d" % i)
		var b0: EnemyBase = f._map_enemy("mushling", c + Vector2(300, 0), "hb%d" % i)
		f.player.global_position = c + Vector2(0, 900) if c.y < 2500 else c - Vector2(0, 900)
		await frames(2)
		a0.take_hit(1, f.player, Vector2.ZERO)
		await frames(1)
		lk += int(b0.ai.in_combat())
		a0.queue_free()
		b0.queue_free()
		await frames(2)
	check(lk >= 3 and lk <= 18, "第 1 层覆盖 link_chance 0.20：跨组联动 %d / 50 = %.0f%%" % [lk, lk * 2.0])
	await clear_enemies()
	# ---- 2.8-4 回归：跑出 1100px ----
	Game.base_time_scale = 4.0
	var H: Vector2 = spots[1]
	e = f._map_enemy("mushling", H, "t")
	await frames(2)
	var away: Vector2 = f.layout.start_pos if H.distance_to(f.layout.start_pos) > 1300 else spots[spots.size() - 1]
	f.player.global_position = H + (away - H).normalized() * 500.0
	e.ai.enter_chase("test")
	await secs(0.6) ## 先追出去一段（time_scale 4）
	e.hp = e.max_hp / 2
	var left_home := e.global_position.distance_to(H)
	f.player.global_position = H + (away - H).normalized() * 1200.0
	await frames(3)
	var went: bool = e.state == EnemyBase.S.RETURN and e.ai.last_reason == "leash"
	var hp_mid := 0
	var t0 := 0.0
	while e.state == EnemyBase.S.RETURN and t0 < 15.0:
		await frames(1)
		t0 += Engine.time_scale / Engine.physics_ticks_per_second
		if hp_mid == 0 and t0 >= 0.5:
			hp_mid = e.hp
	var home_d := e.global_position.distance_to(H)
	check(went and left_home > 100.0 and e.state == EnemyBase.S.PATROL and home_d <= R.home_arrive_px + 2.0 and t0 < 10.0, "2.8-4 敌人追出 %.0f px 后，主角离出生点 %.0f px（> 1100）：转回归，%.1f s 回到出生点（差 %.0f px），恢复巡逻" % [left_home, f.player.global_position.distance_to(H), t0, home_d])
	check(e.hp > e.max_hp / 2 and (hp_mid == 0 or hp_mid > e.max_hp / 2), "回归路上回血：%d → %d / %d（每秒 %.0f%%）" % [e.max_hp / 2, e.hp, e.max_hp, R.return_regen * 100])
	f.player.global_position = H + Vector2(60, 0)
	await frames(10)
	var cd_ok: bool = e.state == EnemyBase.S.PATROL
	var t_re := 0.0
	while e.state == EnemyBase.S.PATROL and t_re < 4.0:
		await frames(1)
		t_re += Engine.time_scale / Engine.physics_ticks_per_second
	var t_total := t_re + 10.0 * Engine.time_scale / Engine.physics_ticks_per_second
	check(cd_ok and e.state != EnemyBase.S.PATROL and t_total >= R.reaggro_cd - 0.1 and t_total <= R.reaggro_cd + 0.4, "主角贴脸（60px）：回到出生点后 %.2f s 才重新察觉（reaggro_cd %.1f s）" % [t_total, R.reaggro_cd])
	e.queue_free()
	await frames(2)
	# 躲到墙后 4 秒：敌人定在原地（临时把移速设 0），主角在障碍另一侧
	var md: EnemyData = Game.enemies["mushling"]
	var sp0 := md.move_speed
	e = f._map_enemy("mushling", wall_pair[0], "t")
	await frames(2)
	e.ai.enter_chase("test")
	md.move_speed = 0.0
	f.player.global_position = wall_pair[1]
	var tl := 0.0
	while e.state == EnemyBase.S.CHASE and tl < 8.0:
		await frames(1)
		tl += Engine.time_scale / Engine.physics_ticks_per_second
	md.move_speed = sp0
	check(e.state == EnemyBase.S.RETURN and e.ai.last_reason == "lost_sight" and absf(tl - R.lose_sight_sec) <= 0.25, "2.8-4 躲到墙后：%.2f s 后失去视野转回归（lose_sight_sec %.1f）" % [tl, R.lose_sight_sec])
	e.queue_free()
	await frames(2)
	# 敌人自己离出生点 > 1100（M1 规则保留）、> 1600 硬上限
	var Hs: Vector2 = spots[1]
	var dir2: Vector2 = ((spots[0] - Hs).normalized() if spots[0].distance_to(Hs) > 10 else Vector2.RIGHT)
	for case in [["leash_self", 1150.0, 1100.0], ["leash_hard", 1650.0, 5000.0]]:
		base.enemy_leash_px = case[2]
		(base as AggroRules).effective(f.fd.aggro_override, f.aggro)
		var el: EnemyBase = f._map_enemy("mushling", Hs, "t")
		await frames(2)
		el.ai.enter_chase("test")
		el.global_position = Hs + dir2 * case[1]
		f.player.global_position = Hs + dir2 * 1050.0 ## 主角离出生点 1050 < 1100
		await frames(3)
		check(el.ai.last_reason == case[0], "2.5 主角离出生点 1050px（未超 1100），敌人被拉到 %.0f px：回归，原因 %s（enemy_leash %.0f / 硬上限 %.0f）" % [case[1], el.ai.last_reason, case[2], R.leash_hard_px])
		el.queue_free()
		await frames(2)
	base.enemy_leash_px = 1100.0
	(base as AggroRules).effective(f.fd.aggro_override, f.aggro)
	# 层主区：主角在里面时普通怪不追；追击中主角进入层主区 → 回归
	var gin: Vector2 = f.guard_entry_pos(true)
	var gout: Vector2 = f.guard_entry_pos(false)
	f.player.global_position = gin
	var e2: EnemyBase = f._map_enemy("mushling", gout, "t")
	await secs(0.5)
	check(e2.state == EnemyBase.S.PATROL, "3.4-3 主角在层主区里：入口外 %.0f px 的普通怪不追" % gin.distance_to(e2.global_position))
	f.player.global_position = gout + Vector2(f.layout.guard_entrances[0].dir) * 250.0
	e2.ai.enter_chase("test")
	await frames(3)
	var chasing: bool = e2.state == EnemyBase.S.CHASE
	f.player.global_position = gin
	await frames(3)
	check(chasing and (e2.state == EnemyBase.S.RETURN or e2.state == EnemyBase.S.PATROL) and e2.ai.last_reason == "guard_zone", "3.4-3 追击中主角进入层主区 → 普通怪回归")
	f.guard_trigger.monitoring = false ## 上面进出层主区不算开战
	await clear_enemies()
	# ---- 2.8-5 追击上限 6、前摇令牌 3 ----
	var C: Vector2 = spots[2]
	f.player.global_position = C
	var crowd: Array = []
	for i in 12:
		crowd.append(f._map_enemy("mushling", C + Vector2(230, 0).rotated(TAU * i / 12.0), "crowd"))
	await frames(2)
	crowd[0].take_hit(1, f.player, Vector2.ZERO)
	var max_ch := 0
	var max_wu := 0
	var max_combat := 0
	var waiting_d: Array = []
	for i in 600:
		await frames(1)
		f.player.global_position = C
		var ch: int = f.director.chasing_count()
		var wu := crowd.filter(func(x): return is_instance_valid(x) and x.state == EnemyBase.S.WINDUP).size()
		var near := crowd.filter(func(x): return is_instance_valid(x) and x.ai.has_slot).size()
		max_ch = maxi(max_ch, maxi(ch, near))
		max_wu = maxi(max_wu, wu)
		max_combat = maxi(max_combat, crowd.filter(func(x): return is_instance_valid(x) and x.ai.in_combat()).size())
		if i == 599:
			for x in crowd:
				if is_instance_valid(x) and not x.ai.has_slot:
					waiting_d.append(x.global_position.distance_to(C))
	var avg_wait := 0.0
	for d in waiting_d:
		avg_wait += d / maxf(1, waiting_d.size())
	check(max_combat == 12 and max_ch <= 6 and max_ch >= 5 and max_wu <= 3 and max_wu >= 1, "2.8-5 12 只同时进入战斗：持有追击名额最多 %d（≤ 6），同时前摇最多 %d（≤ 3）" % [max_ch, max_wu])
	check(waiting_d.size() >= 5 and avg_wait > 200.0 and avg_wait < 420.0, "没拿到名额的 %d 只在外圈包围待机，平均距离 %.0f px（orbit 300）" % [waiting_d.size(), avg_wait])
	DP.root.visible = true
	await frames(2)
	check(DP.aggro_label.text.begins_with("追击 ") and DP.aggro_label.text.contains("/ 6") and DP.aggro_label.text.contains("/ 3"), "2.8-5 F1 面板显示计数：%s" % DP.aggro_label.text)
	# ---- 2.8-6 视野锥和声音圈 ----
	DP.show_aggro = true
	f.player.try_dash()
	await frames(3)
	check(f.aggro_overlay.visible and f.noises.size() >= 1, "2.8-6 F1“显示视野锥和声音圈”：调试层可见，冲刺后有 %d 个声音圈" % f.noises.size())
	DP.show_aggro = false
	DP.root.visible = false
	await clear_enemies()
	Game.base_time_scale = 1.0
	# ---- OM8 小地图 ----
	var mm: Minimap = f.minimap
	var before: int = mm.revealed
	var other := Vector2.INF
	for c in f.layout.chunks:
		var cc := MapGen.chunk_rect(c, f.layout.chunk_px).get_center()
		if other == Vector2.INF and not mm.is_revealed(cc) and c.type != "guard":
			other = cc
	var was_dark := other != Vector2.INF and not mm.is_revealed(other)
	f.player.global_position = other
	await secs(0.4)
	check(mm != null and mm.is_visible_in_tree() and mm.get_rect().position.x > 1500 and was_dark and mm.is_revealed(other) and mm.revealed > before and f.visited.has(MapGen.chunk_at(f.layout, other)),
		"3.4-4 小地图在右上角，按 4×4 地形格一个像素块画（%d×%d 块，不画区块网格）；走到新地方后点亮（%d → %d 块）；层主区和方向箭头从开局就画" % [mm.fog_img.get_width(), mm.fog_img.get_height(), before, mm.revealed])
	# ---- OM9 休眠 + 帧时间 ----
	var sl: EnemyBase = f._map_enemy("mushling", spots[0], "t")
	f.player.global_position = spots[0] + Vector2(1900, 0) if spots[0].x < 3000 else spots[0] - Vector2(1900, 0)
	await secs(0.7)
	var slept: bool = sl.ai.sleeping
	f.player.global_position = spots[0] + Vector2(600, 0) if spots[0].x < 3000 else spots[0] - Vector2(600, 0)
	await secs(0.7)
	check(slept and not sl.ai.sleeping, "OM9 离主角 > 1800px 的巡逻怪休眠，靠近后醒来")
	await clear_enemies()
	f.player.global_position = C
	var ring: Array = []
	for i in 12:
		ring.append(f._map_enemy(["mushling", "rootshot", "shellbug"][i % 3], C + Vector2(260, 0).rotated(TAU * i / 12.0), "perf"))
	await frames(2)
	ring[0].take_hit(1, f.player, Vector2.ZERO)
	await frames(30)
	var tot := 0.0
	var mx := 0.0
	for i in 120:
		await get_tree().process_frame
		var ms := (Performance.get_monitor(Performance.TIME_PROCESS) + Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)) * 1000.0
		tot += ms
		mx = maxf(mx, ms)
	check(tot / 120.0 <= 16.0, "OM9 同屏 12 只敌人战斗中：逻辑帧时间平均 %.2f ms，最大 %.2f ms（≤ 16 ms，桌面无头；网页版见 web check）" % [tot / 120.0, mx])
	await clear_enemies()
	f.player.global_position = f.layout.start_pos
	await frames(2)
	Game.god_mode = false

func nav_path(f: Node, from: Vector2, to: Vector2) -> PackedVector2Array:
	var nm: RID = f.get_world_2d().navigation_map
	var path := PackedVector2Array()
	for i in 30:
		path = NavigationServer2D.map_get_path(nm, from, to, true)
		if path.size() >= 2:
			break
		await frames(1)
	return path

# ---------------- OM3 导航追击 / 烘焙 / 弹道撞墙 ----------------
func test_nav_chase() -> void:
	print("== OM3 导航与追击 ==")
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	for depth in [1, 2, 3]:
		DP.jump_floor(depth)
		await frames(1)
		check(await wait_scene(Game.SCN_FLOOR), "跳到第 %d 层" % depth)
		var f := scene()
		check(f.nav_ready and f.bake_ms <= 200.0 and f.gen_ms <= 100.0, "OM3-2 第 %d 层：生成 %.1f ms（≤100）、导航烘焙 %.1f ms（≤200，桌面）" % [depth, f.gen_ms, f.bake_ms])
		var goal: Vector2 = f.guard_entry_pos(true)
		var path := await nav_path(f, f.layout.start_pos, goal)
		check(path.size() >= 2 and path[-1].distance_to(goal) < 30.0, "OM2-1 第 %d 层导航路径：起点 → 层主区入口内侧，%d 个路点" % [depth, path.size()])
		Game.god_mode = true
		await clear_enemies()
		var L: Dictionary = f.layout
		var solids := MapGen.all_solids(L)
		var obs: Array = []
		for c in L.chunks:
			if MapGen.NORMAL.has(c.type) or c.type == "camp":
				obs += c.obstacles
		for i in obs.size():
			var j := rng.randi_range(i, obs.size() - 1)
			var t = obs[i]; obs[i] = obs[j]; obs[j] = t
		var trials := 0
		var reached := 0
		var stuck := 0
		var tmax := 0.0
		Game.base_time_scale = 4.0
		var space: PhysicsDirectSpaceState2D = f.get_world_2d().direct_space_state
		# 有机地形：障碍矩形是团块的一部分，在矩形两侧不同距离找空地，要求两点之间被障碍挡住
		var cands: Array = []
		for o in obs:
			for axis in [Vector2(1, 0), Vector2(0, 1)]:
				for off in [90.0, 150.0]:
					var half: float = (o.size.x if axis.x > 0 else o.size.y) / 2.0
					cands.append([o.get_center() + axis * (half + off), o.get_center() - axis * (half + off)])
		for cand in cands:
			if trials >= 20:
				break
			var pp: Vector2 = cand[0]
			var ep: Vector2 = cand[1]
			if not MapGen.is_free(pp, solids, 40.0) or not MapGen.is_free(ep, solids, 40.0):
				continue
			if f.guard_rect.grow(200.0).has_point(pp) or f.guard_rect.grow(200.0).has_point(ep):
				continue ## 主角进层主区会升起栅栏，不算地形绕路
			if space.intersect_ray(PhysicsRayQueryParameters2D.create(ep, pp, 1)).is_empty():
				continue
			var np := await nav_path(f, ep, pp)
			if np.size() < 2 or np[-1].distance_to(pp) > 30.0:
				continue
			var plen := 0.0
			for pi in range(1, np.size()):
				plen += np[pi - 1].distance_to(np[pi])
			if plen > 900.0: ## 只测绕开一个障碍团块的局部绕路（大团块整圈绕行不算这条）
				continue
			trials += 1
			f.player.global_position = pp
			var e: EnemyBase = f.spawn_enemy("mushling", ep)
			await frames(2)
			var gt := 0.0
			var win_t := 0.0
			var win_p := ep
			var ok := false
			var was_stuck := false
			while gt < 12.0:
				await frames(1)
				var dt := Engine.time_scale / Engine.physics_ticks_per_second
				gt += dt
				win_t += dt
				if not is_instance_valid(e):
					break
				if e.global_position.distance_to(pp) <= e.data.attack_range + 8.0:
					ok = true
					break
				if win_t >= 1.0:
					if e.global_position.distance_to(win_p) < 10.0 and e.state == EnemyBase.S.CHASE:
						was_stuck = true
					win_t = 0.0
					win_p = e.global_position
			if ok:
				reached += 1
				tmax = maxf(tmax, gt)
			if was_stuck or not ok:
				print("    [诊断] ep=%s pp=%s ok=%s stuck=%s 敌人停在 %s" % [ep, pp, ok, was_stuck, e.global_position if is_instance_valid(e) else "-"])
			if was_stuck:
				stuck += 1
			if is_instance_valid(e):
				e.queue_free()
			await frames(2)
		Game.base_time_scale = 1.0
		check(trials == 20 and reached == 20 and stuck == 0, "OM3-1 第 %d 层：隔着障碍物 %d 次，绕路追到 %d 次，卡住 >1 秒 %d 次（最慢 %.1f 秒）" % [depth, trials, reached, stuck, tmax])
		if depth == 1:
			# 射手子弹撞墙消失：朝外圈墙（x = 0）射
			var y: float = f.layout.start_pos.y + 300.0
			var pr := Projectile.new()
			pr.position = Vector2(120, y)
			pr.velocity = Vector2(-320, 0)
			f.world.add_child(pr)
			var min_x := 999.0
			var gone := false
			for i in 60:
				await frames(1)
				if not is_instance_valid(pr):
					gone = true
					break
				min_x = minf(min_x, pr.global_position.x)
			check(gone and min_x > -20.0, "OM3-3 子弹撞墙消失（物理层 1 射线检测，最远到 x = %.0f）" % min_x)
			# 真射手：隔墙射击的子弹被墙挡住
			var rs: EnemyBase = f.spawn_enemy("rootshot", Vector2(200, y))
			rs.cooldown = 99.0
			await frames(2)
			rs._shoot(Vector2.LEFT)
			await secs(0.6)
			check(get_tree().get_nodes_in_group("projectiles").is_empty(), "根须射手朝墙开火，子弹在墙上消失")
			rs.queue_free()
		Game.god_mode = false
	await frames(2)

# ---------------- M1 冒烟：自动打完第 1 层（上帝模式 + 沿导航走 / 传送） ----------------
func test_walk_floor1() -> void:
	print("== M1 冒烟：沿导航从起点走到层主区，打败层主，撤离 ==")
	Lineage.wipe()
	plain()
	Lineage.flags["opening_seen"] = true
	Game.god_mode = true
	Game.start_run()
	await wait_scene(Game.SCN_FLOOR)
	var f := scene()
	var src := Src.new()
	f.add_child(src)
	var goal: Vector2 = f.guard_entry_pos(true)
	var path := await nav_path(f, f.player.global_position, goal)
	Game.base_time_scale = 3.0
	var t_real := Time.get_ticks_msec()
	var gt := 0.0
	var kills0: int = Game.run.kills
	var chunks_seen := {}
	var i := 1
	var stuck_t := 0.0
	var last: Vector2 = f.player.global_position
	var fail := ""
	while i < path.size() and f.guard == null:
		var to: Vector2 = path[i] - f.player.global_position
		if to.length() < 24.0:
			i += 1
			continue
		f.player.sim_move = to.normalized()
		await frames(1)
		var dt := Engine.time_scale / Engine.physics_ticks_per_second
		gt += dt
		chunks_seen[MapGen.chunk_at(f.layout, f.player.global_position)] = true
		for e in get_tree().get_nodes_in_group("enemies"):
			if e.global_position.distance_to(f.player.global_position) < 220.0:
				e.take_hit(99999, src, Vector2.ZERO)
		if f.player.global_position.distance_to(last) < 1.0:
			stuck_t += dt
			if stuck_t > 2.0:
				fail = "卡在 %s" % str(f.player.global_position)
				break
		else:
			stuck_t = 0.0
		last = f.player.global_position
		if gt > 120.0:
			fail = "超时"
			break
	f.player.sim_move = Vector2.ZERO
	await secs(0.3)
	check(fail == "" and f.guard != null and f.fence_up(), "第 1 层：沿导航走 %.0f 秒（游戏时间）经过 %d 个区块，路上清掉 %d 只怪，走进层主区触发栅栏和层主 %s" % [gt, chunks_seen.size(), Game.run.kills - kills0, fail])
	Game.base_time_scale = 1.0
	await kill_guard(f)
	await until(func(): return not (not f.exit_active))
	check(f.exit_active and not f.fence_up() and f.exit_activated_at - f.guard_killed_at <= 1.0, "层主死后 %.2f 秒撤离点亮起，栅栏撤掉" % (f.exit_activated_at - f.guard_killed_at))
	f.player.global_position = f.exit_pos
	await frames(2)
	check(f.nearest_interactable().get("id", "") == "exit", "走到撤离点可以互动")
	f.choose_exit(false)
	check(await wait_scene(Game.SCN_EXTRACT), "撤离 → 结算")
	var fl := Log.rows("floors")
	check(fl.size() >= 2 and "extract" in fl[-1], "floors.csv 记了这一层：%s" % fl[-1])
	scene().finish()
	await wait_scene(Game.SCN_VILLAGE)
	Game.god_mode = false

# ---------------- M4 生态 × 层主（§8、§9） ----------------
func _kind_share(L: Dictionary) -> Dictionary:
	var T: Dictionary = L.terrain
	var n := {}
	var bsum := 0.0
	for i in T.cells.size():
		n[T.cells[i]] = int(n.get(T.cells[i], 0)) + 1
		bsum += T.biome[i]
	var out := {"bio": bsum / T.cells.size()}
	for k in MapGen.KIND_NAMES.size():
		out[k] = float(n.get(k, 0)) / T.cells.size()
	return out

func _avg_share(fd: FloorData, seeds: Array) -> Dictionary:
	var acc := {}
	for sd in seeds:
		var s := _kind_share(MapGen.generate(sd, fd.depth, fd))
		for k in s:
			acc[k] = float(acc.get(k, 0.0)) + s[k] / seeds.size()
	return acc

func test_ecology() -> void:
	print("== M4 生态 × 层主 ==")
	var want := [
		["fungal_grove", "菌褶林", "菌母·苔根巨菇", "shellbug", ["hardshell", "spore"], 400, 10, 1.8, {"mushling": 0.60, "rootshot": 0.25, "shellbug": 0.15}, "spore_pod", 6, "spore_pod", 4],
		["root_gorge", "根须深谷", "根须射手王", "rootshot", ["summon"], 400, 12, 1.7, {"rootshot": 0.50, "mushling": 0.35, "shellbug": 0.15}, "root_snare", 5, "root_pillar", 4],
		["flooded_ruin", "积水甲虫废墟", "狂暴硬壳甲虫", "shellbug", ["hardshell", "frenzy"], 1200, 9, 1.95, {"shellbug": 0.35, "mushling": 0.40, "rootshot": 0.25}, "falling_rock", 4, "falling_rock", 3],
	]
	var biases := [-0.25, 0.0, 0.25]
	var seeds := [424242, 1001, 2002, 3003, 4004]
	for i in 3:
		var fd: FloorData = Game.floors[i]
		var w: Array = want[i]
		var eco: EcologyData = fd.ecology
		var lord: GuardData = fd.lord()
		var hp := roundi(lord.base_enemy.max_hp * lord.hp_mult)
		var dmg := roundi(lord.base_enemy.damage * lord.dmg_mult)
		var affs: Array = lord.affixes.map(func(a): return a.id)
		check(eco != null and eco.id == w[0] and eco.display_name == w[1] and lord == eco.lord and lord.display_name == w[2] and lord.base_enemy.id == w[3] and affs == w[4]
			and hp == w[5] and dmg == w[6] and is_equal_approx(lord.attack_interval, w[7]) and is_equal_approx(eco.biome_bias, biases[i]),
			"8.3 第 %d 层：%s + %s（%s 模板，词缀 %s，HP %d / 伤害 %d / 间隔 %.2f 秒，biome_bias %+.2f）" % [i + 1, eco.display_name, lord.display_name, lord.base_enemy.display_name, "+".join(lord.affixes.map(func(a): return a.display_name)), hp, dmg, lord.attack_interval, eco.biome_bias])
		var mix := fd.mix()
		var mix_ok := mix.size() == 3
		for k in w[8]:
			mix_ok = mix_ok and is_equal_approx(mix.get(k, -1.0), w[8][k])
		check(mix_ok and fd.enemy_mix != eco.enemy_mix, "第 %d 层敌人种群只读生态：%s" % [i + 1, eco.enemy_mix])
		check(eco.hazards.size() == 1 and eco.hazards[0].id == w[9] and eco.hazard_count(0) == w[10] and lord.arena_hazard.id == w[11] and lord.arena_hazard_count == w[12],
			"第 %d 层机关：%s ×%d，场地机关 %s ×%d" % [i + 1, eco.hazards[0].display_name, w[10], lord.arena_hazard.display_name, w[12]])
		# 摆放：数量、普通区块、离路线点 ≥ 150px、可达
		var placed_ok := true
		var min_route := 1e9
		for sd in seeds:
			var L := MapGen.generate(sd, fd.depth, fd)
			var hz: Array = L.spawn_points.hazard
			var route: Array = []
			for p in L.spawn_points.patrol: route.append_array(p.points)
			placed_ok = placed_ok and hz.size() == w[10]
			for h in hz:
				placed_ok = placed_ok and MapGen.NORMAL.has(L.chunks[h.chunk].type) and not L.chunks[h.chunk].type == "guard"
				for q in route:
					min_route = minf(min_route, q.distance_to(h.pos))
		check(placed_ok and min_route >= 150.0, "第 %d 层 5 个种子：每层 %d 个机关都放在普通区块，离巡逻路线点最近 %.0f px（≥ 150）" % [i + 1, w[10], min_route])
	# 地表：和不带生态的同参数对比
	var sh := []
	var base_sh := []
	for i in 3:
		var fd: FloorData = Game.floors[i]
		sh.append(_avg_share(fd, seeds))
		var eco := fd.ecology
		fd.ecology = null
		base_sh.append(_avg_share(fd, seeds))
		fd.ecology = eco
	check(sh[0].bio < base_sh[0].bio - 0.2 and sh[0][MapGen.T_THICKET] > base_sh[0][MapGen.T_THICKET] and sh[0][MapGen.T_WATER] < base_sh[0][MapGen.T_WATER],
		"菌褶林：林地为主（群系均值 %.2f vs 无生态 %.2f），灌木 %.1f%%（无生态 %.1f%%），水 %.1f%%（无生态 %.1f%%）" % [sh[0].bio, base_sh[0].bio, sh[0][MapGen.T_THICKET] * 100, base_sh[0][MapGen.T_THICKET] * 100, sh[0][MapGen.T_WATER] * 100, base_sh[0][MapGen.T_WATER] * 100])
	check(sh[1][MapGen.T_CLIFF] > base_sh[1][MapGen.T_CLIFF] * 1.3, "根须深谷：断崖 %.1f%%（无生态 %.1f%%）" % [sh[1][MapGen.T_CLIFF] * 100, base_sh[1][MapGen.T_CLIFF] * 100])
	check(sh[2].bio > base_sh[2].bio + 0.2 and sh[2][MapGen.T_RUIN] > base_sh[2][MapGen.T_RUIN] and sh[2][MapGen.T_WATER] > base_sh[2][MapGen.T_WATER],
		"积水甲虫废墟：废墟为主（群系均值 %.2f vs %.2f），残垣 %.1f%%（%.1f%%），积水 %.1f%%（%.1f%%）" % [sh[2].bio, base_sh[2].bio, sh[2][MapGen.T_RUIN] * 100, base_sh[2][MapGen.T_RUIN] * 100, sh[2][MapGen.T_WATER] * 100, base_sh[2][MapGen.T_WATER] * 100])
	# 验收 2：同一个生态改 biome_bias，地表和刷怪同时变化
	var fd1: FloorData = Game.floors[0]
	var b0 := fd1.ecology.biome_bias
	var LA := MapGen.generate(424242, 1, fd1)
	fd1.ecology.biome_bias = 0.35
	var LB := MapGen.generate(424242, 1, fd1)
	fd1.ecology.biome_bias = b0
	var types := func(L: Dictionary) -> Dictionary:
		var d := {}
		for c in L.chunks: d[c.type] = int(d.get(c.type, 0)) + 1
		return d
	var ta: Dictionary = types.call(LA)
	var tb: Dictionary = types.call(LB)
	var pa: Array = LA.spawn_points.patrol.map(func(p): return p.points[0])
	var pb: Array = LB.spawn_points.patrol.map(func(p): return p.points[0])
	check(_kind_share(LB).bio > _kind_share(LA).bio + 0.4 and int(tb.get("ruin", 0)) > int(ta.get("ruin", 0)) and int(tb.get("grove", 0)) < int(ta.get("grove", 0)) and pa != pb,
		"验收 2：biome_bias −0.25 → +0.35，同种子林地区块 %d → %d、废墟区块 %d → %d，巡逻组 %d → %d 组且位置改变" % [int(ta.get("grove", 0)), int(tb.get("grove", 0)), int(ta.get("ruin", 0)), int(tb.get("ruin", 0)), pa.size(), pb.size()])
	# ecology_pool：按权重抽，不和上一层重复，可复现
	var pool_fd := FloorData.new()
	pool_fd.ecology_pool = [Game.floors[0].ecology, Game.floors[1].ecology, Game.floors[2].ecology]
	var rep := true
	var norep := true
	for sd in 200:
		var e1 := pool_fd.pick_ecology(sd, "root_gorge")
		rep = rep and e1 == pool_fd.pick_ecology(sd, "root_gorge")
		norep = norep and e1.id != "root_gorge"
	check(rep and norep, "8.2-1 ecology_pool：200 个种子都不和上一层（根须深谷）重复，同种子结果相同")
	check(DP.find_editor(Game.floors[0].ecology, "biome_bias") != null and DP.find_editor(load("res://data/hazards/spore_pod.tres"), "slow_pct") != null and DP.find_editor(Game.floors[2].lord(), "arena_hazard_count") != null, "生态 / 机关 / 层主场地参数都在 F1 面板可调")
	await test_ecology_floor()

func test_ecology_floor() -> void:
	var src := Src.new()
	add_child(src)
	for depth in [1, 2, 3]:
		DP.jump_floor(depth)
		await frames(1)
		await wait_scene(Game.SCN_FLOOR)
		var f := scene()
		var fd: FloorData = f.fd
		var hz: Array = get_tree().get_nodes_in_group("hazards")
		var txt: String = f.map_stats_text()
		var cnt := {}
		var tot := 0
		for e in get_tree().get_nodes_in_group("enemies"):
			cnt[e.data.id] = int(cnt.get(e.data.id, 0)) + 1
			tot += 1
		var picks := {}
		for k in 6000:
			var id: String = f._pick_enemy()
			picks[id] = int(picks.get(id, 0)) + 1
		var dev := 0.0
		for k in fd.mix():
			dev = maxf(dev, absf(float(picks.get(k, 0)) / 6000.0 - fd.mix()[k]))
		check(hz.size() == fd.ecology.hazard_count(0) and fd.ecology.display_name in txt and fd.ecology.hazards[0].display_name in txt and "敌种比例" in txt and dev < 0.02,
			"验收 1 第 %d 层：场上 %d 个%s；抽怪 6000 次最大偏差 %.3f；实际 %d 只（%s）；F1 地图统计：%s" % [depth, hz.size(), fd.ecology.hazards[0].display_name, dev, tot, str(cnt), " | ".join(txt.split("\n").slice(-3))])
		Game.god_mode = true
		await clear_enemies()
		for h in get_tree().get_nodes_in_group("hazards"):
			h.queue_free()
		await frames(2)
		# 验收 3：不击杀层主就不能前往下一层（也不能撤离）
		check(not f.exit_active and f.choose_exit(true) == false and f.choose_exit(false) == false and scene() == f, "验收 3 / 方案 A 第 %d 层：层主没死时选下潜和撤离都无效，仍在本层" % depth)
		if depth == 1:
			await _test_spore(f, src)
		elif depth == 2:
			await _test_snare(f, src)
		else:
			await _test_rock(f, src)
		# 方案 A：击杀后二选一 / 第 3 层只能撤离
		if depth < 3:
			Game.god_mode = false
			f.player.hp = 50
			Game.run.hp = 50
			var mh: int = Game.max_hp()
			f.choose_exit(true)
			await wait_scene(Game.SCN_FLOOR)
			check(Game.run.depth == depth + 1 and scene().player.hp == mini(mh, 50 + roundi(mh * 0.4)), "方案 A：第 %d 层击杀后下潜，HP 50 → %d（回复 40%% = %d）" % [depth, scene().player.hp, roundi(mh * 0.4)])
			Game.god_mode = true
	Game.god_mode = false

func _lord_fight(f: Node) -> Guard:
	f.debug_enter_guard_zone()
	await secs(0.4)
	return f.guard

func _test_spore(f: Node, src: Node) -> void:
	var p: Player = f.player
	var hd: HazardData = load("res://data/hazards/spore_pod.tres")
	var E := p.global_position
	var pod: SporePod = f._spawn_hazard(hd, E + Vector2(300, 0), false)
	var e: EnemyBase = f._map_enemy("mushling", E + Vector2(300, 0) + Vector2(0, 100), "t")
	var far: EnemyBase = f._map_enemy("mushling", E + Vector2(300, 0) + Vector2(0, 290), "t2")
	await frames(3)
	p.global_position = E + Vector2(300 - 30, 0) ## 踩上
	await frames(3)
	var clouds := get_tree().get_nodes_in_group("spore_clouds")
	await frames(2)
	check(pod.spent and clouds.size() == 1 and is_equal_approx(p.hazard_speed_mult(), 0.7) and is_equal_approx(e.hazard_speed_mult(), 0.7) and far.ai.last_heard_kind == "spore",
		"孢子囊被踩：爆出孢子云，主角移速 ×%.2f、云里的敌人 ×%.2f（敌我都减速），290px 外的敌人听到爆开声（300px），状态 %s" % [p.hazard_speed_mult(), e.hazard_speed_mult(), EnemyBase.S.keys()[far.state]])
	var t0 := Time.get_ticks_msec()
	await until(func(): return get_tree().get_nodes_in_group("spore_clouds").is_empty(), 6.0)
	var dur := (Time.get_ticks_msec() - t0) / 1000.0 * Engine.time_scale
	check(absf(dur - 2.0) < 0.25, "孢子云持续约 %.2f 秒（2 秒）" % dur)
	await clear_enemies()
	# 被打
	var pod2: SporePod = f._spawn_hazard(hd, p.global_position + Vector2(90, 0), false)
	await frames(2)
	p.hitbox.begin(5, 80.0, 120.0, Vector2.RIGHT)
	await frames(2)
	p.hitbox.end()
	check(pod2.spent, "孢子囊被打：主角攻击碰到就爆")
	await until(func(): return get_tree().get_nodes_in_group("spore_clouds").is_empty(), 6.0)
	# 层主：孢子词缀 + 场地 4 个孢子囊
	var g: Guard = await _lord_fight(f)
	var arena: Array = f.arena_hazards
	check(arena.size() == 4 and arena.all(func(h): return h is SporePod and f.guard_rect.has_point(h.global_position)), "菌母·苔根巨菇：场地内 %d 个孢子囊" % arena.size())
	g.attack_dir = Vector2.RIGHT
	g._begin_attack()
	await frames(2)
	var gc: Array = get_tree().get_nodes_in_group("spore_clouds")
	check(g.has_affix("spore") and g.spore_clouds == 1 and gc.size() == 1 and is_equal_approx(gc[0].sec, 2.0), "新词缀“孢子”：重砸后落点留下 %.0f 秒孢子云" % (gc[0].sec if gc.size() else 0.0))
	g.hitbox.end()
	arena[0].burst()
	g.global_position = arena[0].global_position
	await frames(3)
	check(g.hazard_speed_mult() < 1.0, "打爆场地孢子囊可以减速层主（×%.2f）" % g.hazard_speed_mult())
	await kill_guard(f)
	await until(func(): return f.exit_active)
	check(f.arena_hazards.is_empty(), "层主死后场地机关清掉，撤离点亮起")

func _test_snare(f: Node, src: Node) -> void:
	var p: Player = f.player
	var hd: HazardData = load("res://data/hazards/root_snare.tres")
	var s: RootSnare = f._spawn_hazard(hd, p.global_position, false)
	await frames(2)
	var t0 := Time.get_ticks_msec()
	await until(func(): return s.fire_count > 0, 4.0)
	var warn := (Time.get_ticks_msec() - t0) / 1000.0 * Engine.time_scale
	check(s.caught and is_equal_approx(p.hazard_speed_mult(), 0.6) and absf(warn - 0.8) < 0.1, "缠根地块：预兆 %.2f 秒（0.8）后缠住，移速 ×%.2f（−40%%）" % [warn, p.hazard_speed_mult()])
	t0 = Time.get_ticks_msec()
	await until(func(): return p.hazard_speed_mult() >= 1.0, 4.0)
	var hold := (Time.get_ticks_msec() - t0) / 1000.0 * Engine.time_scale
	check(absf(hold - 1.5) < 0.12, "缠住持续 %.2f 秒（1.5）" % hold)
	# 预兆期间走开：不被缠
	await until(func(): return s.cd <= 0.0, 6.0)
	await frames(2)
	await until(func(): return s.t >= 0.0, 2.0)
	p.global_position += Vector2(200, 0)
	await until(func(): return s.fire_count > 1, 3.0)
	check(not s.caught and p.hazard_speed_mult() >= 1.0, "预兆 0.8 秒内离开地块就不会被缠住")
	s.queue_free()
	# 层主：根柱 4 根，挡视线和子弹
	var L: Dictionary = f.layout
	var g: Guard = await _lord_fight(f)
	var space: PhysicsDirectSpaceState2D = f.get_world_2d().direct_space_state
	var blocked := 0
	for c in L.root_pillars:
		var q := PhysicsRayQueryParameters2D.create(c + Vector2(-140, 0), c + Vector2(140, 0), MapGen.OPAQUE_LAYER)
		if not space.intersect_ray(q).is_empty() and f.guard_rect.has_point(c):
			blocked += 1
	check(L.root_pillars.size() == 4 and blocked == 4 and MapGen.blocks_sight(MapGen.T_ROOT), "根须射手王：场地 4 根根柱，%d 根挡住视线 / 子弹射线（OPAQUE 层）" % blocked)
	check(g.gdata.minions == "mushling:2" and is_equal_approx(g.active_affixes[0].summon_every, 10.0), "小弟：菌菇小鬼 ×2，每 10 秒召唤")
	await kill_guard(f)
	await until(func(): return f.exit_active)

func _test_rock(f: Node, src: Node) -> void:
	var p: Player = f.player
	var hd: HazardData = load("res://data/hazards/falling_rock.tres")
	Game.god_mode = false
	p.hp = p.max_hp
	p.iframe_left = 0.0
	var r: FallingRock = f._spawn_hazard(hd, p.global_position + Vector2(200, 0), false)
	await frames(2)
	var hp0 := p.hp
	var t0 := Time.get_ticks_msec()
	await until(func(): return r.fire_count > 0, 4.0)
	var warn := (Time.get_ticks_msec() - t0) / 1000.0 * Engine.time_scale
	check(p.hp == hp0 and absf(warn - 1.2) < 0.1, "落石：主角走进 220px，裂纹预兆 %.2f 秒（1.2）；在砸击半径外没受伤" % warn)
	await until(func(): return r.cd <= 0.0, 8.0)
	p.global_position = r.global_position
	p.iframe_left = 0.0
	hp0 = p.hp
	await until(func(): return r.fire_count > 1, 4.0)
	check(hp0 - p.hp == 14, "落石砸中主角：伤害 %d（14）" % (hp0 - p.hp))
	r.queue_free()
	Game.god_mode = true
	var g: Guard = await _lord_fight(f)
	check(f.arena_hazards.is_empty(), "狂暴硬壳甲虫一阶段：场地没有落石")
	g.take_hit(g.hp - 590, src, Vector2.ZERO)
	await until(func(): return not g.invulnerable)
	await frames(2)
	var rocks: Array = f.arena_hazards
	check(g.phase == 2 and rocks.size() == 3 and rocks.all(func(h): return h is FallingRock and f.guard_rect.has_point(h.global_position)), "二阶段：场地出现 %d 处落石" % rocks.size())
	var rk: FallingRock = rocks[0]
	g.global_position = rk.global_position
	g.velocity = Vector2.ZERO
	var ghp := g.hp
	rk.smash()
	var lord_dmg := ghp - g.hp
	check(lord_dmg == 28 or (lord_dmg == 42 and g.back_mult > 1.0), "落石砸中层主：伤害 %d（14 × 2）" % lord_dmg)
	await kill_guard(f)
	await until(func(): return f.exit_active)
	var opts_ok: bool = Game.FINAL_FLOOR == 3
	f.choose_exit(true)
	check(opts_ok and await wait_scene(Game.SCN_EXTRACT), "方案 A：第 3 层击杀后只能撤离（选下潜也进结算）")

# ---------------- M3 OM10 F1 面板 / OM12 ----------------
func test_m3_panel() -> void:
	print("== M3 F1 面板 / 测试 ==")
	DP.jump_floor(1)
	await frames(1)
	await wait_scene(Game.SCN_FLOOR)
	var f := scene()
	var base: AggroRules = load("res://data/aggro_rules.tres")
	var fd: FloorData = Game.floors[0]
	var eds := ["chunk_px", "grid_w", "loop_chance", "gap_px", "patrol_chance", "camps", "path_min_r"].filter(func(k): return DP.find_editor(fd, k) == null)
	var aeds := ["sight_range", "sight_angle_deg", "noise_dash", "link_chance", "leash_px", "max_chasers", "max_attackers", "sleep_radius", "encounter_gap_sec"].filter(func(k): return DP.find_editor(base, k) == null)
	check(eds.is_empty() and aeds.is_empty(), "OM10 F1：FloorData 开放地图字段和 AggroRules 都有编辑器（缺：%s %s）" % [str(eds), str(aeds)])
	# 参数即时生效：改全局 sight_range（第 1 层没覆盖这个字段）→ 0.5 秒内本层生效对象同步
	var old := base.sight_range
	var ed: Control = DP.find_editor(base, "sight_range")
	ed.value = 333.0
	await secs(0.7 / Engine.time_scale + 0.1)
	var live: float = f.aggro.sight_range
	ed.value = old
	await secs(0.7 / Engine.time_scale + 0.1)
	check(is_equal_approx(live, 333.0) and is_equal_approx(f.aggro.sight_range, old), "OM10 面板改 sight_range %.0f → 333：本层生效参数 %.0f，改回后 %.0f（新进入追击的敌人读同一个对象）" % [old, live, f.aggro.sight_range])
	DP.show_chunks = true
	await frames(2)
	var grid_on: bool = f.chunk_overlay.visible
	DP.show_chunks = false
	await frames(2)
	DP.show_aggro = true
	await frames(2)
	var aggro_on: bool = f.show_aggro_debug()
	DP.show_aggro = false
	DP.sleep_all = true
	await secs(1.2)
	var awake_ids: Array = get_tree().get_nodes_in_group("enemies").filter(func(e): return e.ai and e.state == EnemyBase.S.PATROL and not e.ai.sleeping).map(func(e): return [e.ai._sleep_t, Game.debug_panel == DP])
	if not awake_ids.is_empty(): print("    awake: ", awake_ids)
	var awake := get_tree().get_nodes_in_group("enemies").filter(func(e): return e.ai and e.state == EnemyBase.S.PATROL and not e.ai.sleeping).size()
	DP.sleep_all = false
	await secs(0.4)
	check(grid_on and not f.chunk_overlay.visible and aggro_on and awake == 0, "OM10 区块网格开关 / 视野锥声音圈开关 / 全图休眠（打开后巡逻中醒着的 %d 只）都生效" % awake)
	var tx: String = f.map_stats_text()
	DP.debug_guard()
	await frames(2)
	check("区块" in tx and "巡逻组" in tx and f.player.global_position.distance_to(f.layout.campfire_pos) < 1.0, "OM10 地图统计有数字、“传送到层主区”可用")

# ---------------- M4 设计补充（a~e） ----------------
func test_m4_designer() -> void:
	print("== M4 设计补充：孢子囊 / 缠根 / 落石 / 染色 / 第 2 层通道 ==")
	DP.jump_floor(1)
	await frames(1)
	await wait_scene(Game.SCN_FLOOR)
	var f := scene()
	Game.god_mode = true
	await clear_enemies()
	for h in get_tree().get_nodes_in_group("hazards"): h.queue_free()
	await frames(2)
	var p: Player = f.player
	var E := p.global_position
	# (a) 敌人踩上孢子囊：触发，并且敌人自己被减速
	var pod: SporePod = f._spawn_hazard(load("res://data/hazards/spore_pod.tres"), E + Vector2(400, 0), false)
	var e: EnemyBase = f._map_enemy("mushling", E + Vector2(400, 0), "t")
	await frames(4)
	check(pod.spent and get_tree().get_nodes_in_group("spore_clouds").size() == 1 and is_equal_approx(e.hazard_speed_mult(), 0.7) and p.global_position.distance_to(pod.global_position) > 300.0,
		"(a) 敌人踩孢子囊（主角在 %.0f px 外）：触发爆开，敌人移速 ×%.2f" % [p.global_position.distance_to(pod.global_position), e.hazard_speed_mult()])
	await clear_enemies()
	# (b) 冲刺挣脱缠根
	var sn: RootSnare = f._spawn_hazard(load("res://data/hazards/root_snare.tres"), p.global_position, false)
	await until(func(): return sn.fire_count > 0, 4.0)
	var held := p.hazard_speed_mult()
	p.dash_cd.fill(0.0)
	var dashed := p.try_dash()
	await frames(1)
	check(sn.caught and is_equal_approx(held, 0.6) and dashed and p.hazard_speed_mult() >= 1.0 and p.snare_breaks == 1, "(b) 缠住时移速 ×%.2f，冲刺后立即挣脱（×%.2f）" % [held, p.hazard_speed_mult()])
	sn.queue_free()
	# (c) 落石预兆 ≥ 0.8 秒且画落点圈
	await secs(0.5)
	var rk: FallingRock = f._spawn_hazard(load("res://data/hazards/falling_rock.tres"), p.global_position + Vector2(150, 0), false)
	await until(func(): return rk.t >= 0.3, 3.0)
	await frames(2)
	check(rk.hd.warn_sec >= 0.8 and rk.visible and rk.landing_drawn and rk.is_visible_in_tree(), "(c) 落石预兆 %.1f 秒（≥ 0.8），预兆中落点圈已绘制、可见" % rk.hd.warn_sec)
	rk.queue_free()
	Game.god_mode = false
	# (d) 生态染色强度可调
	var eco: EcologyData = Game.floors[0].ecology
	var L := MapGen.generate(424242, 1, Game.floors[0])
	var c0: Color = MapGen.terrain_images(L)[0].get_pixel(10, 10)
	var k0 := eco.palette_strength
	eco.palette_strength = 0.0
	var L2 := MapGen.generate(424242, 1, Game.floors[0])
	var c1: Color = MapGen.terrain_images(L2)[0].get_pixel(10, 10)
	eco.palette_strength = k0
	check(is_equal_approx(k0, 0.25) and DP.find_editor(eco, "palette_strength") != null and not c0.is_equal_approx(c1) and _col_close(c1, MapGen.ground_color(L2.terrain.biome[10 * L2.terrain.nx + 10])),
		"(d) EcologyData.palette_strength = %.2f 在 F1 可调；改成 0 后地面回到纯群系色" % k0)
	# (e) 第 2 层最窄通道 ≥ 160px（50 个种子）
	var fd2: FloorData = Game.floors[1]
	var mn := 1e9
	var worst := 0
	for i in 50:
		var sd := 424242 + i * 7919
		var w := MapGen.passage_width(MapGen.generate(sd, 2, fd2))
		if w < mn:
			mn = w
			worst = sd
	var fd1: FloorData = Game.floors[0]
	var mn1 := 1e9
	var ws1: Array = []
	for i in 50:
		var w1 := MapGen.passage_width(MapGen.generate(424242 + i * 7919, 1, fd1))
		ws1.append(w1)
		mn1 = minf(mn1, w1)
	ws1.sort()
	check(mn1 >= 160.0 and is_equal_approx(fd1.path_min_r, 112.0) and is_zero_approx(Game.floors[2].path_min_r), "第 1 层 50 个种子：最窄通道 %.0f px（≥ 160），中位 %.0f px（path_min_r 112；第 3 层仍为 0）" % [mn1, ws1[25]])
	check(mn >= 160.0, "(e) 第 2 层 50 个种子：起点 → 层主区篝火最窄通道 %.0f px（种子 %d，≥ 160；cliff_th %.2f，path_min_r %.0f）" % [mn, worst, fd2.ecology.cliff_th, fd2.path_min_r])

func _col_close(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 0.01 and absf(a.g - b.g) < 0.01 and absf(a.b - b.b) < 0.01

# ---------------- 紧急回村符 ----------------
func test_recall_charm() -> void:
	print("== 紧急回村符 ==")
	var rules := Game.recall
	var saved := {
		"chest": rules.chest_drop_chance, "elite": rules.elite_drop_chance, "lord": rules.lord_drop_chance,
		"zone": rules.zone_length, "channel": rules.channel_sec, "craft": rules.craft_material_count,
		"carry": rules.carry_per_floor, "uses": rules.uses_per_run,
		"t1": rules.trap_rooms_floor_1, "t2": rules.trap_rooms_floor_2, "t3": rules.trap_rooms_floor_3,
	}
	var editors_ok := true
	for prop in ["display_name", "chest_drop_chance", "elite_drop_chance", "lord_drop_chance", "zone_length", "channel_sec", "craft_material_count", "carry_per_floor", "uses_per_run", "blocked_hint", "trap_rooms_floor_1", "trap_rooms_floor_2", "trap_rooms_floor_3", "elite_ids", "use_hint", "sealed_hint"]:
		editors_ok = editors_ok and DP.find_editor(rules, prop) != null
	check(editors_ok, "F1 回村符分组能改 recall_charm.tres 的全部可调项")
	var ev_ok := false
	var joy_ok := false
	for ev in InputMap.action_get_events("recall"):
		if ev is InputEventKey and ev.physical_keycode == KEY_R:
			ev_ok = true
		if ev is InputEventJoypadButton and ev.button_index == JOY_BUTTON_RIGHT_SHOULDER:
			joy_ok = true
	check(ev_ok and joy_ok, "使用回村符：键盘 R，手柄 RB")
	check(is_equal_approx(rules.chest_drop_chance, 0.005) and is_equal_approx(rules.elite_drop_chance, 0.003) and is_equal_approx(rules.lord_drop_chance, 0.02) and rules.zone_length == 3 and rules.craft_material_count == 3 and rules.carry_per_floor == 1 and rules.uses_per_run == 1, "顶稀有：宝箱 0.005、精英 0.003、层主每次 0.02，区域 3 层，制作 3 个材料，进层带 1 张，一局用 1 次")
	# 旧表头改名
	Log.clear()
	var p := Log.path("floors")
	var oldp_pre := p.get_basename() + ".old.csv"
	if FileAccess.file_exists(oldp_pre):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(oldp_pre))
	var oldf := FileAccess.open(p, FileAccess.WRITE)
	oldf.store_line("time,run_id,gen_no,depth,result")
	oldf.store_line("old")
	oldf.close()
	Log.write("floors", ["t", 0, 1, "recall", 0, 0, 0, 1, 1, 0, 0, "", 1, 1, 0, 0, "", 0, 0, 0, 0, 0, 0, 0, 0, ""])
	var oldp := p.get_basename() + ".old.csv"
	check(FileAccess.file_exists(oldp) and "time,run_id,gen_no,depth,result\n" in FileAccess.get_file_as_string(oldp), "旧 floors.csv 表头被改名为 .old.csv")
	var hdr_rows := Log.rows("floors")
	check(hdr_rows.size() >= 2 and hdr_rows[0] == Log.HEADERS.floors and "charm_stash_run" in hdr_rows[0] and "unbossed_mat_out" in hdr_rows[0] and hdr_rows[0].ends_with("unbossed_mat_out"), "新 floors.csv 用带 charm_* 和风险监控列的表头")
	Log.clear()
	# 没有全局持有上限：已经有符也照常掉，仓库和保险箱都能放多张
	Lineage.wipe()
	Game.run = null
	rules.chest_drop_chance = 1.0
	rules.elite_drop_chance = 1.0
	rules.lord_drop_chance = 0.0
	check(rules.grant("chest") and rules.owned() == 1 and Lineage.charm_carried == 1, "没有符时可以获得 1 个，先放在仓库")
	check(rules.grant("elite") and Lineage.charm_carried == 2 and rules.owned() == 2, "已经持有时仍然可以再获得")
	check(Lineage.vault_put(RecallCharm.ITEM_ID) and Lineage.vault_put(RecallCharm.ITEM_ID) and Lineage.charm_carried == 0 and Lineage.vault.size() == 1 and int(Lineage.vault[0].count) == 2, "保险箱可以叠放多张回村符")
	Game.run = Run.new()
	Game.run.seed = 7
	Game.run.depth = 1
	check(rules.roll_chest("still-rolls") and Game.run.unsealed_count(RecallCharm.ITEM_ID) == 1, "保险箱里已经有符时，宝箱仍然会掉")
	check(rules.roll_elite("shellbug", "still-elite") and Game.run.sealed_count(RecallCharm.ITEM_ID) == 1 and Game.run.count_of(RecallCharm.ITEM_ID) == 2, "已经有 1 张时再掉到的是封印，两张都在背包里")
	check(not rules.roll_elite("mushling", "not-elite"), "不在 elite_ids 里的敌人不会掉符")
	Game.run = null
	var taken := Lineage.vault_take(0)
	check(taken != null and taken.id == RecallCharm.ITEM_ID and Lineage.charm_carried == 2, "从保险箱取出后整叠回到仓库")
	Lineage.charm_carried = 0
	check(rules.roll_elite("shellbug", "elite-ok") == false, "没有进行中的局时精英不往存档里塞符")
	Game.run = Run.new()
	Game.run.seed = 7
	Game.run.depth = 2
	check(rules.roll_elite("shellbug", "elite-ok") and Game.run.charm_source == "elite" and Game.run.unsealed_count(RecallCharm.ITEM_ID) == 1, "精英（硬壳甲虫）按精英概率掉符，来源记为 elite")
	check(rules.roll_chest("after-elite") and Game.run.sealed_count(RecallCharm.ITEM_ID) == 1, "已经有符时宝箱继续掷，多出来的那张封印")
	# 封印的第二张不能用；存进去就解开。进层最多带 1 张
	check(rules.can_use() and rules.consume() and Game.run.charm_uses == 1 and Game.run.unsealed_count(RecallCharm.ITEM_ID) == 0 and Game.run.sealed_count(RecallCharm.ITEM_ID) == 1, "用掉没封印的那张，封印的还在")
	Game.run.charm_uses = 0
	check(not rules.can_use() and not rules.consume() and Game.run.sealed_count(RecallCharm.ITEM_ID) == 1, "封印的第二张这一局不能用")
	var stock_before := Lineage.charm_carried
	check(Game.store_charm(true, false) and Game.run.sealed_count(RecallCharm.ITEM_ID) == 0 and Lineage.charm_carried == stock_before + 1, "封印的符存进仓库")
	Game.run = Run.new()
	Game.run.seed = 11
	Game.run.depth = 1
	rules.bring_into_run()
	check(Game.run.unsealed_count(RecallCharm.ITEM_ID) == 1 and Game.run.sealed_count(RecallCharm.ITEM_ID) == 0 and rules.can_use(), "存进仓库之后封印解开，下一次可以带去用")
	Lineage.charm_carried = 3
	Lineage.vault.clear()
	Lineage.vault.append({"id": RecallCharm.ITEM_ID, "count": 2})
	Game.run = Run.new()
	Game.run.seed = 12
	Game.run.depth = 1
	rules.bring_into_run()
	rules.settle_on_floor_entry()
	check(Game.run.unsealed_count(RecallCharm.ITEM_ID) == 1 and Game.run.count_of(RecallCharm.ITEM_ID) == 1 and Lineage.charm_carried == 2 and int(Lineage.vault[0].count) == 2, "进层只从仓库带 1 张，保险箱里的不动")
	Game.run.add_item(ItemStack.new(Items.get_item(RecallCharm.ITEM_ID), 1, false, "extra"))
	rules.settle_on_floor_entry()
	check(Game.run.unsealed_count(RecallCharm.ITEM_ID) == 1 and Game.run.sealed_count(RecallCharm.ITEM_ID) == 1, "进层时背包里多出来的没封印符会改成封印")
	# 层主：平时按概率，只有区域最后一层的第一次击杀必给。死亡后这份记录还在
	Lineage.wipe()
	Game.run = Run.new()
	Game.run.seed = 3
	Game.run.depth = 1
	rules.lord_drop_chance = 0.0
	rules.on_lord_killed(1)
	rules.on_lord_killed(2)
	check(rules.owned() == 0 and not bool(Lineage.charm_lord_seen.get("1", false)), "第 1、2 层层主概率是 0 时不给符，也没有必给")
	rules.on_lord_killed(3)
	check(rules.owned() == 1 and Game.run.charm_source == "lord" and bool(Lineage.charm_lord_seen.get("3", false)) and Game.run.unsealed_count(RecallCharm.ITEM_ID) == 1, "第 3 层是区域最后一层，第一次击杀必给 1 张")
	rules.on_lord_killed(3)
	check(rules.owned() == 1, "同一层主再杀一次，概率是 0 时不再给")
	rules.lord_drop_chance = 1.0
	rules.on_lord_killed(1)
	check(Game.run.count_of(RecallCharm.ITEM_ID) == 2 and Game.run.sealed_count(RecallCharm.ITEM_ID) == 1, "每次层主击杀都会掷，掷中的第二张是封印")
	Lineage.save()
	var seen := Lineage.charm_lord_seen.duplicate()
	Lineage.reset_memory()
	Lineage.load_save()
	check(Lineage.charm_lord_seen == seen and bool(Lineage.charm_lord_seen.get("3", false)), "区域末层的首杀记录写入存档后再读回来一致")
	Lineage.record_death(Game.run, 1, 0, "回村符测试")
	Lineage.new_individual("")
	Game.run = null
	check(bool(Lineage.charm_lord_seen.get("3", false)) and rules.owned() == 0, "换人（死亡）之后首杀记录还在，背包里的符丢掉")
	# 陷阱房数量
	var trap_ok := true
	var trap_msg := ""
	for depth in [1, 2, 3]:
		var want: int = rules.trap_count(depth)
		for s in 8:
			var L := MapGen.generate(s * 13 + 4, depth, Game.floor_data(depth))
			if L.traps.size() != want:
				trap_ok = false
				trap_msg = "层 %d 种子 %d 陷阱 %d" % [depth, s, L.traps.size()]
			for id in L.traps:
				var ch: Dictionary = L.chunks[id]
				trap_ok = trap_ok and ch.no_recall and ch.type in ["field", "grove", "ruin"] and id != L.start_chunk and id != L.guard_chunk
	check(trap_ok and rules.trap_count(1) == 0 and rules.trap_count(2) == 1 and rules.trap_count(3) == 1, "灰盒第 2、3 层各 1 间陷阱房（no_recall），第 1 层没有 %s" % trap_msg)
	# 制作：3 个萤苔精，不限哪一层；已经持有还能再做
	Lineage.wipe()
	Game.run = null
	rules.craft_material_count = 3
	check(not rules.craft() and rules.owned() == 0, "没有材料时做不出回村符")
	Lineage.mats.moss_essence = 2
	check(not rules.craft() and int(Lineage.mats.moss_essence) == 2, "2 个层主稀有材料不够做")
	Lineage.mats.moss_essence = 3
	check(rules.craft() and rules.owned() == 1 and Lineage.charm_carried == 1 and int(Lineage.mats.moss_essence) == 0 and Lineage.charm_source == "craft", "3 个层主稀有材料做成 1 张符")
	Lineage.mats.moss_essence = 3
	check(rules.craft() and Lineage.charm_carried == 2 and int(Lineage.mats.moss_essence) == 0, "已经持有时还能再做一张")
	var craft_panel: Panel2 = load("res://scenes/village/craft_ui.gd").new()
	get_tree().root.add_child(craft_panel)
	await frames(2)
	var craft_enabled := false
	for b in craft_panel.box.find_children("*", "Button", true, false):
		if b.text == "制作回村符":
			craft_enabled = not b.disabled
	check(craft_enabled, "已经持有回村符时，制作按钮仍然可点")
	craft_panel.close()
	await frames(2)
	rules.craft_material_count = 4
	Lineage.mats.moss_essence = 3
	check(not rules.craft() and int(Lineage.mats.moss_essence) == 3, "把材料数量改成 4 之后，3 个不够")
	rules.craft_material_count = 3
	Lineage.mats.moss_essence = 2
	Game.run = Run.new()
	Game.run.add_item(ItemStack.new(Items.get_item("moss_essence"), 1))
	check(rules.craft_material_have() == 3 and rules.craft() and Game.run.count_of("moss_essence") == 0 and int(Lineage.mats.moss_essence) == 0 and Game.run.unsealed_count(RecallCharm.ITEM_ID) == 1, "仓库和背包里的萤苔精可以合在一起用，不限哪一层打来的")
	Game.run = null
	# 楼层里：禁区、受击打断、使用、回村可存、楼层状态
	Lineage.wipe()
	plain()
	Lineage.flags["opening_seen"] = true
	Lineage.save()
	rules.chest_drop_chance = 0.0
	rules.elite_drop_chance = 0.0
	rules.lord_drop_chance = 1.0
	rules.channel_sec = 5.0
	Game.base_time_scale = 1.0
	Game.god_mode = true
	Game.run = null
	var banked: int = int(Lineage.mats.moss)
	Game.start_run()
	check(await wait_scene(Game.SCN_FLOOR), "进入第 1 层")
	var f := scene()
	var src := Src.new()
	f.add_child(src)
	f.debug_enter_guard_zone()
	await secs(0.4)
	await kill_guard(f)
	check(rules.owned() == 1 and Game.run.charm_source == "lord" and Game.run.unsealed_count(RecallCharm.ITEM_ID) == 1 and not bool(Lineage.charm_lord_seen.get("1", false)), "第 1 层层主按掉落概率给符，不是每层必给")
	check(f.recall_blocked() and not f.try_recall() and f.last_recall_hint == rules.blocked_hint and not f.channeling and rules.carrying(), "层主区内不能使用回村符，提示「此处无法使用回村符」，符还在")
	var tracked: Array = []
	for e in get_tree().get_nodes_in_group("enemies"):
		if str(e.get_meta("rid", "")) != "":
			tracked.append(e)
	check(tracked.size() >= 2, "第 1 层至少有 2 只带编号的地图怪（%d）" % tracked.size())
	var victim: EnemyBase = tracked[0]
	var survivor: EnemyBase = tracked[1]
	var victim_id := str(victim.get_meta("rid", ""))
	var survivor_id := str(survivor.get_meta("rid", ""))
	var home: Vector2 = survivor.home_pos
	survivor.hp = maxi(1, survivor.max_hp / 5)
	survivor.ai.enter_chase("test", false)
	check(survivor.state == EnemyBase.S.CHASE, "活着的那只在回村前处于追击")
	victim.take_hit(999999, src, Vector2.ZERO)
	await frames(2)
	f._open_chest("chest_0")
	Game.run.add_item(ItemStack.new(Items.get_item("trinket_hp"), 1))
	var moss_carry: int = Game.run.count_of("moss")
	check(moss_carry >= 3 and f.used.has("chest_0"), "宝箱已拾取（萤苔 %d）" % moss_carry)
	f.player.global_position = f.layout.start_pos
	await frames(3)
	check(rules.grant("chest") and Game.run.sealed_count(RecallCharm.ITEM_ID) == 1 and rules.can_use(), "地上再捡到的第二张是封印，原来那张还能用")
	check(Game.run.take_kind(RecallCharm.ITEM_ID, false, 1), "先把没封印的那张拿开")
	check(not f.try_recall() and f.last_recall_hint == rules.sealed_hint and Game.run.sealed_count(RecallCharm.ITEM_ID) == 1, "只剩封印的符时不能引导")
	Game.run.add_item(ItemStack.new(Items.get_item(RecallCharm.ITEM_ID), 1, false, "lord"))
	Game.run.charm_source = "lord"
	Game.god_mode = false
	check(not f.recall_blocked() and f.try_recall() and f.channeling and not f.player.input_enabled, "起点可以开始引导，引导中不能操作")
	await secs(0.2)
	var hp_before: int = f.player.hp
	f.player.take_hit(1, src, Vector2.ZERO)
	await frames(2)
	check(not f.channeling and f.player.input_enabled and rules.carrying() and f.player.hp == hp_before - 1 and int(Game.run.floor_stats.get("charm_interrupted", 0)) >= 1, "受击打断引导，回村符不消耗（HP %d → %d）" % [hp_before, f.player.hp])
	rules.channel_sec = 0.25
	f.player.hp = 15
	Game.run.hp = 15
	check(f.try_recall(), "打断后可以重新引导")
	check(await until(func(): return scene().scene_file_path == Game.SCN_VILLAGE, 3.0), "引导结束回到起程村")
	var v := scene()
	check(Game.run != null and Game.run.suspended and Game.run.count_of("moss") == moss_carry and Lineage.mats.moss == banked and not rules.carrying(), "回村不是撤离：背包里的萤苔还在，仓库材料没增加，符已消耗")
	var fl := Log.rows("floors")
	var hdr := Log.HEADERS.floors.split(",")
	var cols := fl[-1].split(",")
	check(cols[hdr.find("result")] == "recall" and int(cols[hdr.find("charm_used")]) == 1 and int(cols[hdr.find("charm_floor")]) == 1 and int(cols[hdr.find("charm_interrupted")]) >= 1 and cols[hdr.find("charm_source")] == "lord" and int(cols[hdr.find("charm_stash_run")]) == 0 and int(cols[hdr.find("unbossed_mat_out")]) == 0, "floors.csv 记下 charm 列；刚回村还没存东西：%s" % fl[-1])
	v.player.global_position = v.facility("vault").pos + Vector2(0, 90)
	await frames(2)
	check(v.interact() and v.panel_open != null, "回村后可以打开保险箱")
	if v.panel_open:
		v.panel_open.close()
		await frames(2)
	v.player.global_position = v.facility("bench").pos + Vector2(0, 80)
	await frames(2)
	check(v.interact() and v.panel_open != null, "回村后可以打开强化台")
	if v.panel_open:
		v.panel_open.close()
		await frames(2)
	check(v.player.hp == 15, "回到村里时生命还是楼层里的 %d" % v.player.hp)
	v.player.global_position = v.facility("rest").pos + Vector2(0, 80)
	await frames(2)
	check(v.interact() and v.player.hp == v.player.max_hp and Game.run.hp == v.player.max_hp, "可以回复生命到 %d" % v.player.hp)
	var bag_before: Array = Game.run.bag.map(func(st): return st.item.id)
	v.player.global_position = v.facility("bag").pos + Vector2(0, 80)
	await frames(2)
	check(v.interact() and v.panel_open != null, "可以打开整理背包")
	var store_btn := false
	for b in v.panel_open.box.find_children("*", "Button", true, false):
		if b.text == "存入仓库":
			store_btn = true
	var moved := false
	for b in v.panel_open.box.find_children("*", "Button", true, false):
		if b.text == "下移" and not b.disabled:
			b.pressed.emit()
			moved = true
			break
	await frames(2)
	var bag_after: Array = Game.run.bag.map(func(st): return st.item.id)
	check(store_btn and moved and bag_after != bag_before and bag_after.size() == bag_before.size(), "背包可以调整顺序（%s → %s），也可以存进仓库" % [str(bag_before), str(bag_after)])
	if v.panel_open:
		v.panel_open.close()
		await frames(2)
	check(Game.store_bag("moss") and Lineage.mats.moss == banked + moss_carry and Game.run.count_of("moss") == 0, "萤苔存进仓库（%d → %d）" % [banked, Lineage.mats.moss])
	fl = Log.rows("floors")
	cols = fl[-1].split(",")
	check(int(cols[hdr.find("charm_stash_run")]) == 1 and int(cols[hdr.find("unbossed_mat_out")]) == 0, "层主已经死了：记成回村后存过东西，未击杀带出的材料是 0：%s" % fl[-1])
	if v.panel_open:
		v.panel_open.close()
		await frames(2)
	Game.run.add_item(ItemStack.new(Items.get_item(RecallCharm.ITEM_ID), 1, false, "chest"))
	Game.run.charm_source = "chest"
	check(rules.carrying(), "回村之后可以再带 1 张没封印的符进层")
	var ret: Dictionary = v.facility("return")
	check(ret.get("name", "") == "返回第 1 层", "返回入口文案：%s" % ret.get("name", ""))
	v.player.global_position = ret.pos + Vector2(0, 80)
	await frames(2)
	var back: bool = v.interact()
	check(back and await wait_scene(Game.SCN_FLOOR), "从返回入口回到第 1 层")
	f = scene()
	var mem: Dictionary = Game.run.floor_memory.get(1, {})
	var back_victim := false
	var survivor_now: EnemyBase = null
	for e in get_tree().get_nodes_in_group("enemies"):
		var rid := str(e.get_meta("rid", ""))
		if rid == victim_id:
			back_victim = true
		if rid == survivor_id:
			survivor_now = e
	var zrng := RandomNumberGenerator.new()
	zrng.seed = 3
	var back_moss := false
	for st in Game.floors[0].chest_loot.roll(zrng):
		if st.item.id == "moss":
			back_moss = true
	check(back_moss and rules.carrying(), "返回之后掉落和原来一样，宝箱萤苔仍然必掉")
	check(f.layout.seed == Game.run.seed and int(mem.get("seed", -1)) == Game.run.seed and "chest_0" in mem.get("picked", []) and victim_id in mem.get("killed", []), "楼层种子、已拾取、已击杀都留着")
	check(f.used.has("chest_0") and not back_victim and f.guard_dead and f.exit_active and f.guard == null, "宝箱不会再出现，被击杀的怪和层主不会复活，撤离点保持亮起")
	check(survivor_now != null and survivor_now.hp == survivor_now.max_hp and not survivor_now.ai.in_combat() and survivor_now.global_position.distance_to(home) < 80.0, "活着的怪满血、仇恨清空、回到巡逻点（HP %s，距离 %.0f）" % [str(survivor_now.hp if survivor_now else -1), survivor_now.global_position.distance_to(home) if survivor_now else -1])
	Game.god_mode = true
	Game.enter_floor(2)
	check(await wait_scene(Game.SCN_FLOOR) and scene().depth == 2, "进入第 2 层看陷阱房")
	f = scene()
	check(f.layout.traps.size() == 1, "第 2 层这一局有 1 间陷阱房")
	var trap_id: int = f.layout.traps[0]
	f.player.global_position = MapGen.chunk_rect(f.layout.chunks[trap_id], f.layout.chunk_px).get_center()
	await frames(3)
	check(f.recall_blocked() and f.last_recall_hint == "此处无法使用回村符" and not f.try_recall() and rules.carrying(), "走进陷阱房会提示，并且不能使用回村符")
	f.player.global_position = f.guard_rect.get_center()
	await frames(3)
	check(f.recall_blocked() and not f.try_recall(), "第 2 层层主区同样不能使用")
	# 风险监控列
	Game.goto(Game.SCN_VILLAGE)
	check(await wait_scene(Game.SCN_VILLAGE), "离开楼层再记风险监控")
	Log.clear()
	Game._floor_log_open = false
	Game.run = Run.new()
	Game.run.id = "risk-a"
	Game.run.depth = 1
	Game.run.charm_recalled = true
	Game.run.floor_memory[1] = {"guard_dead": false}
	Game.run.floor_stats = {"t0": 0.0}
	Game.run.add_item(ItemStack.new(Items.get_item("moss"), 4))
	Game.run.add_item(ItemStack.new(Items.get_item("trinket_hp"), 1))
	Game.log_floor("recall")
	var risk_hdr := Log.HEADERS.floors.split(",")
	var risk_row := Log.rows("floors")[-1].split(",")
	check(int(risk_row[risk_hdr.find("charm_stash_run")]) == 0 and int(risk_row[risk_hdr.find("unbossed_mat_out")]) == 0, "回村当刻还没存东西")
	check(Game.store_bag("moss"), "把 4 个萤苔存进仓库")
	risk_row = Log.rows("floors")[-1].split(",")
	check(int(risk_row[risk_hdr.find("charm_stash_run")]) == 1 and int(risk_row[risk_hdr.find("unbossed_mat_out")]) == 4, "层主没死就存进仓库：charm_stash_run=1，unbossed_mat_out=4")
	check(Game.store_bag("trinket_hp"), "装备放进保险箱")
	risk_row = Log.rows("floors")[-1].split(",")
	check(int(risk_row[risk_hdr.find("unbossed_mat_out")]) == 4, "装备不算材料，未击杀带出的数量不变")
	Game.run.floor_memory[1]["guard_dead"] = true
	Game.run.add_item(ItemStack.new(Items.get_item("moss"), 3))
	check(Game.store_bag("moss"), "层主死后继续存萤苔")
	risk_row = Log.rows("floors")[-1].split(",")
	check(int(risk_row[risk_hdr.find("unbossed_mat_out")]) == 4 and int(risk_row[risk_hdr.find("charm_stash_run")]) == 1, "层主死后存的材料不再计入 unbossed_mat_out")
	Game.log_floor("extract")
	risk_row = Log.rows("floors")[-1].split(",")
	check(risk_row[risk_hdr.find("result")] == "extract" and int(risk_row[risk_hdr.find("charm_stash_run")]) == 1 and int(risk_row[risk_hdr.find("unbossed_mat_out")]) == 0, "下一行只带这局已经存过的标记，材料数重新计")
	Game._floor_log_open = false
	Game.run = Run.new()
	Game.run.id = "risk-b"
	Game.run.depth = 2
	Game.run.floor_memory[2] = {"guard_dead": false}
	Game.run.floor_stats = {"t0": 0.0}
	Game.run.add_item(ItemStack.new(Items.get_item("moss"), 2))
	Game.log_floor("death")
	check(Game.store_bag("moss"), "没用回村符也把材料存进仓库")
	risk_row = Log.rows("floors")[-1].split(",")
	check(int(risk_row[risk_hdr.find("charm_stash_run")]) == 0 and int(risk_row[risk_hdr.find("unbossed_mat_out")]) == 2, "没用回村符：charm_stash_run 仍是 0，材料数照记")
	var summary: Dictionary = Log.risk_summary()
	check(int(summary.runs) == 2 and int(summary.stash_runs) == 1 and is_equal_approx(float(summary.share), 0.5) and int(summary.unbossed_sum) == 6 and is_equal_approx(float(summary.unbossed_avg), 2.0), "F1 用的合计：存物局 1/2，材料合计 6，平均 2（%s）" % str(summary))
	DP.root.visible = true
	await frames(2)
	check("1/2" in DP.risk_label.text and "合计 6" in DP.risk_label.text, "F1 回村符分组显示运行中的占比、合计和平均：%s" % DP.risk_label.text)
	DP.root.visible = false
	# 还原可调项，避免污染资源
	rules.chest_drop_chance = saved.chest
	rules.elite_drop_chance = saved.elite
	rules.lord_drop_chance = saved.lord
	rules.zone_length = saved.zone
	rules.channel_sec = saved.channel
	rules.craft_material_count = saved.craft
	rules.carry_per_floor = saved.carry
	rules.uses_per_run = saved.uses
	rules.trap_rooms_floor_1 = saved.t1
	rules.trap_rooms_floor_2 = saved.t2
	rules.trap_rooms_floor_3 = saved.t3
	Game.goto(Game.SCN_VILLAGE)
	check(await wait_scene(Game.SCN_VILLAGE), "测试结束先离开楼层再清局")
	Game.god_mode = false
	Game.run = null
	Lineage.wipe()
