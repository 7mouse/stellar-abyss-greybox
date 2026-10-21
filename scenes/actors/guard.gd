class_name Guard
extends EnemyBase
## 层主 = 敌人模板 × 词缀 × 配色。
## 苔冠王野猪（charge_len > 0）：A 冲撞、B 根刺、C 号令、D 拱击。冲撞预警出现时 hook_charge_telegraph。
## 其它层：狂暴 / 召唤（每 10 秒发芽野猪）/ 硬壳 / 孢子，沿用模板攻击。
## 二阶段：HP 降到 phase2_hp_ratio 时演出（无敌），之后加 phase2_affix。

func _sfx_death() -> void:
	Audio.sfx("SFX-30")
	Audio.boss_dead()

signal phase2_started
signal summon_requested(enemy_id: String, count: int)

var gdata: GuardData
var active_affixes: Array = []
var summon_t := 0.0
var phase := 1
var phase2_t := -1.0
var source_name := ""
var hold_moves := false
var move_id := ""
var last_move := ""
var move_cd := {"A": 0.0, "B": 0.0, "C": 0.0, "D": 0.0}
var stun_left := 0.0
var stun_elapsed := 0.0
var charge_left := 0.0
var _chain_after := 0
var _chain_pending := false
var _charge_hit_player := false
var _struck := false
var _popped: Array = []
var tele = null

func setup_guard(gd: GuardData, p_depth: int) -> void:
	gdata = gd
	setup(gd.base_enemy, p_depth)
	max_hp = roundi(gd.base_enemy.max_hp * gd.hp_mult)
	hp = max_hp
	damage = roundi(gd.base_enemy.damage * gd.dmg_mult)
	windup = gd.base_enemy.windup * gd.windup_mult
	size = gd.base_enemy.size * gd.scale
	tint = gd.color
	source_name = gd.display_name
	set_affixes(gd.affixes.duplicate())

func set_affixes(list: Array) -> void:
	active_affixes = list
	back_mult = 1.0
	if gdata.poise_override > 0.0:
		poise = gdata.poise_override
	else:
		poise = gdata.base_enemy.poise
		for a in active_affixes:
			poise *= 1.0 + a.poise_pct
	for a in active_affixes:
		back_mult = maxf(back_mult, a.back_damage_mult)
	attack_interval = gdata.attack_interval

func has_affix(id: String) -> bool:
	return active_affixes.any(func(a): return a.id == id)

func effective_interval() -> float:
	var sp := 0.0
	for a in active_affixes:
		sp += a.attack_speed_pct
	return attack_interval / (1.0 + sp)

func uses_lord_moves() -> bool:
	return gdata != null and gdata.charge_len > 0.0

func _uses_body_telegraph() -> bool:
	return not uses_lord_moves() and super._uses_body_telegraph()

func _ready() -> void:
	super._ready()
	hitbox.source_name = gdata.display_name
	source_name = gdata.display_name
	warn.add_theme_font_size_override("font_size", 72)
	add_to_group("guards")
	if uses_lord_moves():
		tele = BossTelegraph.new()
		add_child(tele)
		tele.visible = false
		if visual and visual.texture:
			var vh := Art.visual_h("guard_1")
			visual.scale = Vector2.ONE * (vh / float(visual.texture.get_height()))
			visual.position = Vector2(0, 10.0 - vh * 0.5)

func _physics_process(delta: float) -> void:
	if uses_lord_moves():
		for k in move_cd:
			move_cd[k] = maxf(0.0, float(move_cd[k]) - delta)
		if stun_left > 0.0 and phase2_t < 0.0:
			var step := minf(delta, stun_left)
			stun_elapsed += step
			stun_left -= delta
			velocity = Vector2.ZERO
			if stun_left <= 0.0:
				_hide_telegraph()
				_go(S.CHASE)
			_sync_visual()
			return
	if phase2_t >= 0.0:
		state_t += delta
		_tick_extra(delta)
		_sync_visual()
		return
	super._physics_process(delta)
	if uses_lord_moves() and state == S.WINDUP:
		_sync_telegraph()

func _tick_extra(delta: float) -> void:
	if phase2_t >= 0.0:
		phase2_t += delta
		body.modulate = Color(2, 2, 2) if int(phase2_t * 10) % 2 == 0 else Color.WHITE
		if phase2_t >= gdata.phase2_sec:
			phase2_t = -1.0
			invulnerable = false
			body.modulate = Color.WHITE
			if gdata.phase2_affix and not active_affixes.has(gdata.phase2_affix):
				var l := active_affixes.duplicate()
				l.append(gdata.phase2_affix)
				set_affixes(l)
				if phase >= 2 and gdata.p2_attack_interval > 0.0:
					attack_interval = gdata.p2_attack_interval
	if uses_lord_moves():
		return
	for a in active_affixes:
		if a.summon_every > 0.0 and phase2_t < 0.0:
			summon_t += delta
			if summon_t >= a.summon_every * gdata.summon_every_mult:
				summon_t = 0.0
				summon_requested.emit(a.summon_enemy, gdata.summon_count_override if gdata.summon_count_override > 0 else a.summon_count)

func take_hit(dmg: int, src: Node, knockback: Vector2) -> bool:
	var ok := super.take_hit(dmg, src, knockback)
	if ok and state != S.DEAD and phase == 1 and gdata.phase2_hp_ratio > 0.0 and hp <= max_hp * gdata.phase2_hp_ratio:
		phase = 2
		phase2_t = 0.0
		invulnerable = true
		hitbox.end()
		warn.visible = false
		aim_line.visible = false
		_hide_telegraph()
		body.color = tint
		if gdata.p2_attack_interval > 0.0:
			attack_interval = gdata.p2_attack_interval
		_burst_arena_pods()
		_go(S.RECOVER)
		phase2_started.emit()
		HitFeedback.on_boss_phase(self)
		Audio.sfx("SFX-29")
		if max_hp > 0:
			Audio.notify_boss_hp(float(hp) / float(max_hp))
	return ok

## 冲撞预警线亮起的那一帧把线传进来。教学只闪第一次。
func hook_charge_telegraph(visual: CanvasItem) -> void:
	Tutorial.notify("boss_first_telegraph", visual)

func _chase(delta: float) -> void:
	if not uses_lord_moves():
		super._chase(delta)
		return
	if hold_moves or target == null:
		velocity = Vector2.ZERO
		return
	var to: Vector2 = target.global_position - global_position
	var dist := to.length()
	facing = to.normalized() if dist > 1.0 else facing
	if _chain_pending:
		attack_dir = facing
		start_move("A")
		return
	if cooldown > 0.0:
		velocity = nav_dir(target.global_position, delta) * speed()
		move_and_slide()
		return
	var mv := pick_move(dist)
	if mv == "":
		velocity = nav_dir(target.global_position, delta) * speed()
		move_and_slide()
		return
	attack_dir = facing
	start_move(mv)

## 距离 ≤140 且 D 就绪用 D；140-320 用 B；更远用 A。C 就绪且没到上限时优先。同一招不连用。
func pick_move(dist: float) -> String:
	var pigs := alive_piglets()
	var cap := _summon_cap()
	if _cd_ready("C") and pigs < cap and last_move != "C":
		return "C"
	var prefer := "A"
	if dist <= 140.0:
		prefer = "D"
	elif dist <= 320.0:
		prefer = "B"
	if _cd_ready(prefer) and last_move != prefer:
		return prefer
	for id in ["D", "B", "A", "C"]:
		if id == last_move or not _cd_ready(id):
			continue
		if id == "C" and pigs >= cap:
			continue
		return id
	return ""

func start_move(mv: String) -> void:
	var chained := mv == "A" and _chain_pending
	_chain_pending = false
	move_id = mv
	last_move = mv
	_struck = false
	_charge_hit_player = false
	_popped = []
	var wind := 0.8
	match mv:
		"A":
			wind = gdata.p2_rechain_windup if chained else gdata.charge_windup
			if not chained:
				move_cd["A"] = gdata.charge_cd
			if chained:
				_chain_after = maxi(0, _chain_after - 1)
			elif phase >= 2 and gdata.p2_charge_chain > 1:
				_chain_after = gdata.p2_charge_chain - 1
			else:
				_chain_after = 0
		"B":
			var sp := _affix("rootspike")
			wind = gdata.p2_spike_windup if phase >= 2 else (sp.spike_windup if sp else 0.8)
			move_cd["B"] = sp.spike_cd if sp else 9.0
		"C":
			wind = 1.0
			move_cd["C"] = gdata.p2_summon_every if phase >= 2 and gdata.p2_summon_every > 0.0 else _summon_every()
		"D":
			wind = gdata.gore_windup
			move_cd["D"] = gdata.gore_cd
	if target != null and is_instance_valid(target):
		var to := target.global_position - global_position
		if to.length() > 1.0:
			attack_dir = to.normalized()
			facing = attack_dir
	windup = wind
	_show_telegraph(mv)
	if mv == "A" and tele:
		hook_charge_telegraph(tele as CanvasItem)
		Audio.sfx("SFX-25")
	_go(S.WINDUP)

func abort_move() -> void:
	hitbox.end()
	charge_left = 0.0
	move_id = ""
	_chain_after = 0
	_chain_pending = false
	stun_left = 0.0
	_hide_telegraph()
	velocity = Vector2.ZERO
	state = S.IDLE

func spike_line_count() -> int:
	var sp := _affix("rootspike")
	if sp == null:
		return 0
	if phase >= 2 and gdata.p2_spike_lines > 0:
		return gdata.p2_spike_lines
	return sp.spike_lines

func alive_piglets() -> int:
	if not is_inside_tree():
		return 0
	var n := 0
	var me := get_instance_id()
	for e in get_tree().get_nodes_in_group("enemies"):
		if e == self:
			continue
		if int(e.get_meta("lord", -1)) != me:
			continue
		if e.state != S.DEAD:
			n += 1
	return n

func _begin_attack() -> void:
	if not uses_lord_moves():
		super._begin_attack()
		_spore_on_slam()
		return
	if move_id == "":
		return
	_go(S.ATTACK)
	_hide_telegraph(true)
	match move_id:
		"A":
			Audio.sfx("SFX-26")
			charge_left = gdata.charge_len
		"B":
			Audio.sfx("SFX-27")
			_resolve_spikes()
		"C":
			Audio.sfx("SFX-28")
			_resolve_summon()
		"D":
			Audio.sfx("SFX-51")
			_resolve_gore()

func _tick_attack(delta: float) -> void:
	if not uses_lord_moves() or move_id == "":
		super._tick_attack(delta)
		return
	if move_id == "A":
		_tick_charge(delta)
		return
	if state_t >= 0.12:
		_finish_move()

func _tick_charge(delta: float) -> void:
	var step := minf(gdata.charge_speed * delta, charge_left)
	charge_left -= step
	var origin := global_position
	var col := move_and_collide(attack_dir * step)
	var traveled := origin.distance_to(global_position)
	_try_hit_player(origin, attack_dir, maxf(traveled, 1.0), gdata.charge_width, damage, gdata.charge_kb)
	_pop_pods(origin, traveled)
	if col and _collider_is_wall(col.get_collider()):
		_begin_stun()
		return
	if charge_left <= 0.5:
		_finish_move()

func _finish_move() -> void:
	var follow := move_id == "A" and _chain_after > 0 and stun_left <= 0.0
	var missed := move_id == "A" and not _charge_hit_player
	hitbox.end()
	_hide_telegraph()
	if missed:
		Tutorial.notify("boss_charge_dodged")
	if follow:
		_chain_pending = true
		if target != null and is_instance_valid(target):
			var to := target.global_position - global_position
			if to.length() > 1.0:
				attack_dir = to.normalized()
		start_move("A")
		return
	cooldown = effective_interval()
	move_id = ""
	_go(S.RECOVER)

func _begin_stun() -> void:
	if stun_left > 0.0:
		return
	Audio.sfx("SFX-26")
	stun_left = gdata.charge_wall_stun
	stun_elapsed = 0.0
	charge_left = 0.0
	_chain_after = 0
	_chain_pending = false
	hitbox.end()
	_hide_telegraph()
	if move_id == "A" and not _charge_hit_player:
		Tutorial.notify("boss_charge_dodged")
	move_id = ""
	velocity = Vector2.ZERO
	state = S.RECOVER

func _spore_on_slam() -> void:
	if data.id == "rootshot":
		return
	for a in active_affixes:
		if a.spore_on_slam:
			var at := global_position + attack_dir * (data.attack_range * 0.6)
			get_parent().add_child(SporeCloud.make(at, a.spore_on_slam, a.spore_sec))
			spore_clouds += 1

var spore_clouds := 0

func roll_loot(rare_mult := 1.0) -> Array[ItemStack]:
	return gdata.loot_table.roll(Game.rng, rare_mult) if gdata.loot_table else []

func xp_value() -> int:
	return gdata.xp

func _affix(id: String) -> AffixData:
	for a in active_affixes:
		if a.id == id:
			return a
	return null

func _cd_ready(id: String) -> bool:
	return float(move_cd.get(id, 0.0)) <= 0.0

func _summon_affix() -> AffixData:
	return _affix("summon")

func _summon_every() -> float:
	var a := _summon_affix()
	return a.summon_every if a else 15.0

func _summon_cap() -> int:
	if phase >= 2 and gdata.p2_summon_cap > 0:
		return gdata.p2_summon_cap
	var a := _summon_affix()
	if a == null or a.summon_cap <= 0:
		return 99
	return a.summon_cap

func _summon_count() -> int:
	if phase >= 2 and gdata.p2_summon_count > 0:
		return gdata.p2_summon_count
	var a := _summon_affix()
	return a.summon_count if a else 0

func _resolve_summon() -> void:
	var room := _summon_count()
	var cap := _summon_cap()
	room = mini(room, cap - alive_piglets())
	if room <= 0:
		return
	var a := _summon_affix()
	var id := a.minion_id if a and a.minion_id != "" else (a.summon_enemy if a else "piglet")
	summon_requested.emit(id, room)

func _resolve_spikes() -> void:
	var sp := _affix("rootspike")
	if sp == null:
		return
	var n := spike_line_count()
	var half := n / 2
	for i in n:
		var ang := deg_to_rad(float(i - half) * sp.spike_spread_deg)
		_try_hit_player(global_position, attack_dir.rotated(ang), sp.spike_len, sp.spike_width, sp.spike_damage, 0.0)

func _resolve_gore() -> void:
	var p := _player()
	if p == null or p.hurtbox == null:
		return
	if p.hurtbox.overlaps_sector(global_position, attack_dir, gdata.gore_radius, gdata.gore_arc_deg):
		if p.take_hit(gdata.gore_damage, self, attack_dir * gdata.gore_kb):
			_struck = true

func _try_hit_player(origin: Vector2, dir: Vector2, length: float, width: float, dmg: int, kb: float) -> void:
	if _struck:
		return
	var p := _player()
	if p == null or p.hurtbox == null:
		return
	if not p.hurtbox.overlaps_rect(origin, dir, length, width):
		return
	if p.take_hit(dmg, self, dir * kb):
		_struck = true
		if move_id == "A":
			_charge_hit_player = true

func _player() -> Player:
	var ps := get_tree().get_nodes_in_group("player") if is_inside_tree() else []
	return ps[0] if not ps.is_empty() else null

func _pop_pods(origin: Vector2, traveled: float) -> void:
	if not is_inside_tree():
		return
	for n in get_tree().get_nodes_in_group("hazards"):
		if not (n is SporePod) or _popped.has(n):
			continue
		var pod := n as SporePod
		var extra := pod.hd.radius if pod.hd else 36.0
		if not _near_segment(pod.global_position, origin, attack_dir, traveled, extra):
			continue
		_popped.append(pod)
		if not pod.spent:
			pod.burst()
		apply_hazard_slow(0.3, 2.0)

func _burst_arena_pods() -> void:
	if not is_inside_tree():
		return
	for n in get_tree().get_nodes_in_group("hazards"):
		if n is SporePod and n.in_arena and not n.spent:
			n.burst()

func _near_segment(p: Vector2, origin: Vector2, dir: Vector2, length: float, extra: float) -> bool:
	var axis := dir.normalized() if dir.length() > 0.01 else Vector2.RIGHT
	var d := p - origin
	var along := d.dot(axis)
	var side := absf(d.dot(Vector2(-axis.y, axis.x)))
	return along >= -extra and along <= length + extra and side <= extra

func _collider_is_wall(n: Object) -> bool:
	return n is StaticBody2D

func _show_telegraph(mv: String) -> void:
	if tele == null:
		return
	var sp := _affix("rootspike")
	tele.kind = "line"
	tele.length = gdata.charge_len
	tele.width = gdata.charge_width
	tele.radius = 120.0
	tele.arc_deg = gdata.gore_arc_deg
	tele.dirs = [attack_dir]
	tele.fill = 0.0
	match mv:
		"A":
			tele.kind = "line"
		"B":
			tele.kind = "lines"
			tele.length = sp.spike_len if sp else 360.0
			tele.width = sp.spike_width if sp else 60.0
			var dirs: Array = []
			var n := spike_line_count()
			var half := n / 2
			var spread := sp.spike_spread_deg if sp else 30.0
			for i in n:
				dirs.append(attack_dir.rotated(deg_to_rad(float(i - half) * spread)))
			tele.dirs = dirs
		"C":
			tele.kind = "circle"
		"D":
			tele.kind = "wedge"
			tele.radius = gdata.gore_radius
	tele.visible = true
	tele.striking = false
	tele.sync(windup)
	tele.queue_redraw()

func _sync_telegraph() -> void:
	if tele == null or not tele.visible or tele.striking:
		return
	tele.fill = clampf(state_t / maxf(0.01, windup), 0.0, 1.0)
	tele.sync(windup)
	tele.queue_redraw()

func _hide_telegraph(strike := false) -> void:
	if tele == null:
		return
	if strike and tele.visible:
		tele.flash_then_hide()
		return
	tele.cancel()

class BossTelegraph:
	extends Node2D
	var kind := "line"
	var length := 480.0
	var width := 90.0
	var radius := 130.0
	var arc_deg := 150.0
	var dirs: Array = []
	var fill := 0.0
	var striking := false
	var windup_sec := 0.8
	var _hold := 0
	var _shapes: Array[TelegraphShape] = []

	func sync(p_windup: float) -> void:
		windup_sec = p_windup
		_paint()

	func flash_then_hide() -> void:
		striking = true
		visible = true
		_hold = 2
		_paint()

	func cancel() -> void:
		_hold = 0
		striking = false
		visible = false

	func _process(_delta: float) -> void:
		if _hold <= 0:
			return
		_hold -= 1
		if _hold == 0:
			visible = false
			striking = false

	func _draw() -> void:
		_paint()

	func _paint() -> void:
		var n := 1
		if kind == "line" or kind == "lines":
			n = maxi(1, dirs.size())
		while _shapes.size() < n:
			var made := TelegraphShape.new()
			add_child(made)
			_shapes.append(made)
		var ramp := Presentation.data().rim_ramp_sec
		for i in _shapes.size():
			var s: TelegraphShape = _shapes[i]
			s.visible = i < n and visible
			if i >= n:
				continue
			s.fill = fill
			s.rim_alpha = 1.0 if striking else TelegraphShape.rim_from_fill(fill, windup_sec, ramp, false)
			if kind == "circle":
				s.kind = "circle"
				s.radius = radius
				s.rotation = 0.0
			elif kind == "wedge":
				s.kind = "wedge"
				s.radius = radius
				s.arc_deg = arc_deg
				var aim: Vector2 = dirs[0] if not dirs.is_empty() else Vector2.RIGHT
				s.rotation = aim.angle()
			else:
				s.kind = "line"
				s.length = length
				s.width = width
				var d: Vector2 = dirs[i] if i < dirs.size() else Vector2.RIGHT
				s.rotation = d.angle()
			s.refresh()
