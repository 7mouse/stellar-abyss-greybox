extends Node
## 灰盒 2 无头验收。运行：tests/run_tests.sh（退出码 0 = 全部通过）

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
	await test_rooms()
	await test_village()
	await test_death_flow()
	await test_full_flow_input()
	await test_csv()
	print("\n结果：%d 通过，%d 失败" % [passes, fails])
	Lineage.wipe()
	Log.clear()
	get_tree().quit(0 if fails == 0 else 1)

# ---------------- T13.1 / T6 楼层生成 ----------------
func test_generation() -> void:
	print("== T6/T13 楼层生成 ==")
	var ok := true
	var struct_ok := true
	var bad_msg := ""
	for depth in [1, 2, 3]:
		var fd := Game.floor_data(depth)
		for s in 50:
			var L := FloorGen.generate(s * 7 + 1, depth, fd)
			var bad := FloorGen.unreachable_rooms(L)
			if not bad.is_empty():
				ok = false
				bad_msg = "层 %d 种子 %d 房间 %s" % [depth, s, str(bad)]
			var main: Array = L.rooms.filter(func(r): return r.main).map(func(r): return r.type)
			var nc := main.count("combat")
			var sides: Array = L.rooms.filter(func(r): return not r.main)
			struct_ok = struct_ok and main[0] == "entrance" and main[-1] == "guard" and main[-2] == "campfire" and nc >= fd.combat_rooms_min and nc <= fd.combat_rooms_max
			struct_ok = struct_ok and sides.size() <= fd.side_rooms_max and sides.all(func(r): return r.type in ["chest", "boon"])
	check(ok, "第 1~3 层各生成 50 次，所有房间按 40px 栅格都能走到（无死路、无卡墙）%s" % bad_msg)
	check(struct_ok, "主路：入口 → 战斗 ×3~4 → 篝火 → 层守；支路 ≤2 个且为宝箱/强化")
	check(var_to_str(FloorGen.generate(42, 1, Game.floors[0]).rooms) == var_to_str(FloorGen.generate(42, 1, Game.floors[0]).rooms), "固定种子可复现")
	check(var_to_str(FloorGen.generate(42, 1, Game.floors[0]).rooms) != var_to_str(FloorGen.generate(42, 2, Game.floors[1]).rooms), "种子 + 层号决定布局")

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
			var e: EnemyBase = f.spawn_enemy(id, gp + Vector2(dist, 0), -1)
			e.cooldown = 0.0
			await until(func(): return not (e.state != EnemyBase.S.WINDUP))
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
	var sb: EnemyBase = f.spawn_enemy("shellbug", f.player.global_position + Vector2(300, 0), -1)
	await frames(2)
	var src := Src.new()
	f.add_child(src)
	sb.take_hit(10, src, Vector2.ZERO)
	var no_stagger := sb.state != EnemyBase.S.HURT
	sb.take_hit(10, src, Vector2.ZERO)
	sb.take_hit(10, src, Vector2.ZERO)
	check(no_stagger and sb.state == EnemyBase.S.HURT, "硬壳甲虫 poise 30：累计 30 伤害才硬直")
	var mu: EnemyBase = f.spawn_enemy("mushling", f.player.global_position + Vector2(-300, 0), -1)
	await frames(2)
	mu.take_hit(1, src, Vector2.ZERO)
	check(mu.state == EnemyBase.S.HURT, "普通怪 poise 0：一下就硬直")
	check(Game.enemies.mushling.max_hp == 30 and roundi(30 * Game.floors[2].hp_scale()) == 47 and roundi(12 * Game.floors[2].dmg_scale()) == 15, "楼层成长：小鬼 HP 30→第 3 层 47，甲虫伤害 12→15")
	for e in get_tree().get_nodes_in_group("enemies"):
		e.queue_free()

# ---------------- T5 层守 + T6 撤离 + T14 线索 2 ----------------
func kill_guard(f: Node) -> void:
	var src := Src.new()
	f.add_child(src)
	while is_instance_valid(f.guard) and f.guard.state != EnemyBase.S.DEAD:
		if not f.guard.invulnerable:
			f.guard.take_hit(f.guard.hp, src, Vector2.ZERO)
		await frames(1)

func test_guards_and_exit() -> void:
	print("== T5 层守 / T6 撤离点 / T14 系统日志 ==")
	var f := scene()
	check(DP.find_editor(Game.floors[0].guard, "affix_frenzy") != null, "词缀可以在面板上勾选组合")
	DP.set_guard_affix(Game.floors[0].guard, Game.affixes.frenzy, true)
	check(Game.floors[0].guard.affixes.size() == 2, "勾选“狂暴”后第 1 层层守 = 硬壳 + 狂暴")
	DP.set_guard_affix(Game.floors[0].guard, Game.affixes.frenzy, false)
	f.debug_guard()
	await secs(0.5)
	check(f.guard != null and f.doors_locked(f.layout.guard), "进层守房：门锁上，层守出现")
	check(f.guard.max_hp == 260 and f.guard.damage == 10 and f.guard.poise == 60.0 and is_equal_approx(f.guard.back_mult, 1.5), "第 1 层层守：HP 260、伤害 10、poise 60（硬壳 +100%）、背后 ×1.5")
	check(not f.exit_active and f.nearest_interactable().get("id", "") != "exit", "层守没死时撤离点不能互动")
	f.player.global_position = f.exit_pos
	await frames(2)
	check(not f.interact() or f.nearest_interactable().get("id", "") != "exit", "站在撤离点上也互动不了")
	var t_kill := Time.get_ticks_msec()
	await kill_guard(f)
	await frames(1)
	check(SysLog.is_showing() and "backup #0001" in SysLog.last_text and "sync OK" in SysLog.last_text, "第 1 层层守首杀闪出系统日志：%s" % SysLog.last_text)
	check(not get_tree().paused and f.player.input_enabled, "日志闪现不打断操作")
	await until(func(): return not (SysLog.is_showing()))
	check(absf(SysLog.last_duration - 0.35) <= 1.0 / 60.0 + 0.005, "日志显示 %.3f 秒（0.35 ± 1 帧）" % SysLog.last_duration)
	await until(func(): return not (not f.exit_active))
	check(f.exit_activated_at - f.guard_killed_at <= 1.0, "击杀后 %.2f 秒撤离点激活（≤ 1 秒）" % (f.exit_activated_at - f.guard_killed_at))
	check(f.nearest_interactable().get("id", "") == "exit", "层守死后撤离点可以互动")
	# 下潜
	f.choose_exit(true)
	check(await wait_scene(Game.SCN_FLOOR) and Game.run.depth == 2, "下潜：进入第 2 层")
	f = scene()
	check(f.layout.rooms.all(func(r): return r.type != "exit") and f.depth == 2, "第 2 层没有回第 1 层的路（下潜后无法返回）")
	f.debug_guard()
	await secs(0.5)
	check(f.guard.has_affix("summon") and f.guard.gdata.base_enemy.id == "rootshot", "第 2 层层守：射手 + 召唤")
	f.guard.summon_t = 9.99
	await secs(0.2)
	check(f.enemies_in_room(f.layout.guard).filter(func(e): return e != f.guard).size() == 2, "召唤：一次召 2 只菌菇小鬼")
	Game.clues.log_repeat_chance = 0.0
	await kill_guard(f)
	await frames(1)
	check(SysLog.last_text == Game.clues.guard_log_2, "第 2 层首杀日志：%s" % SysLog.last_text)
	await until(func(): return not (not f.exit_active))
	f.choose_exit(true)
	await wait_scene(Game.SCN_FLOOR)
	f = scene()
	f.debug_guard()
	await secs(0.5)
	var g: Guard = f.guard
	check(g.max_hp == 620 and g.has_affix("hardshell") and g.has_affix("frenzy") and absf(g.effective_interval() - 1.5) < 0.01, "第 3 层层守：HP 620、硬壳 + 狂暴、出手间隔 %.2f 秒" % g.effective_interval())
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
	check(not corpse_it.is_empty(), "到达同一层时入口房有前任尸体")
	f.player.global_position = corpse_it.pos
	await frames(2)
	f.interact()
	check(Game.run.equipped.any(func(s): return s.item.id == "trinket_atk") and Game.run.shards_carried == 1 and Lineage.corpse.is_empty(), "回收到前任的装备和碎片，尸体消失")

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
		f.debug_guard()
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
	f.debug_guard()
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

# ---------------- T6 战斗房 / 篝火 / 宝箱 ----------------
func test_rooms() -> void:
	print("== T6 战斗房波次 / 篝火 / 宝箱 ==")
	Lineage.wipe()
	plain()
	Game.auto_pick = 0
	Game.start_run()
	await wait_scene(Game.SCN_FLOOR)
	var f := scene()
	var src := Src.new()
	f.add_child(src)
	var cid: int = f.layout.first_combat
	f.player.global_position = FloorGen.room_center(f.layout.rooms[cid])
	await frames(3)
	var n1: int = f.enemies_in_room(cid).size()
	check(f.doors_locked(cid) and n1 >= 3 and n1 <= 5, "进战斗房：门锁上，第 1 波 %d 只（3~5）" % n1)
	for e in f.enemies_in_room(cid):
		e.take_hit(9999, src, Vector2.ZERO)
	await secs(1.0)
	check(f.doors_locked(cid) and f.enemies_in_room(cid).is_empty(), "第 1 波清完：门仍锁着，等第 2 波")
	await secs(1.3)
	var n2: int = f.enemies_in_room(cid).size()
	check(n2 >= 3 and n2 <= 5 and f.rooms_state[cid].wave == 2, "清完 2 秒后刷出第 2 波 %d 只" % n2)
	for e in f.enemies_in_room(cid):
		e.take_hit(9999, src, Vector2.ZERO)
	await secs(0.5)
	check(not f.doors_locked(cid) and f.rooms_state[cid].cleared, "2 波都清完：门打开")
	check(Game.run.boons.size() == 1, "第 1 个战斗房奖励 3 选 1：%s" % (Game.run.boons[0].display_name if Game.run.boons.size() else "无"))
	f.player.global_position = FloorGen.room_center(f.layout.rooms[0])
	await frames(3)
	check(f.room_at(f.player.global_position) == 0, "本层房间可以回头走（回到入口）")
	for r in f.layout.rooms:
		if r.type == "campfire":
			f.player.hp = 40
			f.player.global_position = FloorGen.room_center(r) + Vector2(0, 40)
			await frames(2)
			f.interact()
			check(f.player.hp == 40 + roundi(f.player.max_hp * 0.3) and f.nearest_interactable().is_empty(), "篝火回复 30%%（40 → %d），只能用一次" % f.player.hp)
		if r.type == "chest":
			var before: int = Game.run.count_of("moss")
			f.player.global_position = FloorGen.room_center(r) + Vector2(0, 40)
			await frames(2)
			f.interact()
			check(Game.run.count_of("moss") - before >= 3, "宝箱掉材料 3~5")
	Game.auto_pick = -1
