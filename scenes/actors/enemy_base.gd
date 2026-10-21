class_name EnemyBase
extends CharacterBody2D
## 普通敌人基类：IDLE / CHASE / WINDUP / ATTACK / RECOVER / HURT / DEAD / RETURN / PATROL / ALERT
## 地图怪（ai 不为空，见 EnemyAI）：PATROL 巡逻 → ALERT 警觉 → CHASE 追击 → RETURN 回归；前摇要先拿攻击令牌，追击名额满了就包围待机。
## ai 为空（层主、召唤物、调试刷怪、测试场）= 旧行为，IDLE 立即开追、一直追。追击/回归走 NavigationAgent2D（use_nav，楼层烘焙完导航后打开）。
## 攻击前摇有明显预兆（变色 + “!” 图标），时长 = windup；poise 打满才硬直（普通怪 poise 0 = 每下都硬直）

signal died(enemy: EnemyBase)

enum S { IDLE, CHASE, WINDUP, ATTACK, RECOVER, HURT, DEAD, RETURN, PATROL, ALERT }

var data: EnemyData
var depth := 1
var hp := 30
var max_hp := 30
var damage := 6
var poise := 0.0
var poise_acc := 0.0
var attack_interval := 1.6
var windup := 0.45
var back_mult := 1.0
var state := S.IDLE
var state_t := 0.0
var cooldown := 0.5
var attack_dir := Vector2.RIGHT
var facing := Vector2.LEFT
var slow_left := 0.0
var target: Node2D
var hurtbox: Hurtbox
var hitbox: Hitbox
var body: ColorRect
var visual: Sprite2D
var warn: Label
var aim_line: Line2D
var size := Vector2(40, 48)
var tint := Color.WHITE
var last_windup_sec := -1.0 ## 测试：上一次前摇实际时长
var telegraph_delay := 0.0
var invulnerable := false
var aggro := true
var _lunge_left := 0.0
var retreat_cd_left := 0.0
var retreat_left := 0.0
var retreats := 0 ## 被贴近后撤的次数（冷却内不再次触发）
var moss_affix: AffixData
var elite_affix: AffixData
var moss_down := 0.0 ## 厚苔破开剩余时间，此间受伤不再乘 0.7
var moss_lock := 0.0 ## 长回后不能再破的剩余时间
var speed_mult := 1.0
var xp_mult := 1.0
var _elite_ready := false
var _elite_introduced := false
var _atk_i := 0
var _bouncing := false
var _bounce_phase := "" ## air / limp
var _air_left := 0.0
var _limp_left := 0.0
var _land_pos := Vector2.ZERO
var attack_log: Array[String] = []
var bounce_ring: BounceRing
var feel_flash_t := 0.0
var feel_moss := false
var _windup_started := 0.0
var rules: AggroRules ## 仇恨参数（地图怪）；null = 一直追
var ai: EnemyAI
var home_pos := Vector2.INF ## 出生点
var no_go := Rect2() ## 主角在这个矩形里（层主区）时普通怪不追、正在追的回归
var use_nav := false
var nav: NavigationAgent2D
var _repath_t := 0.0
var _nav_goal := Vector2.INF

func setup(p_data: EnemyData, p_depth: int, fd: FloorData = null) -> void:
	data = p_data
	depth = p_depth
	var hs := fd.hp_scale() if fd else pow(1.25, p_depth - 1)
	var ds := fd.dmg_scale() if fd else pow(1.12, p_depth - 1)
	max_hp = roundi(data.max_hp * hs)
	hp = max_hp
	damage = roundi(data.damage * ds)
	poise = data.poise
	attack_interval = data.attack_interval
	windup = data.windup
	size = data.size
	tint = data.color

func _ready() -> void:
	collision_layer = 4
	collision_mask = 1
	var cs := CollisionShape2D.new()
	var sh := CircleShape2D.new()
	sh.radius = size.x * 0.4
	cs.shape = sh
	add_child(cs)
	body = ColorRect.new()
	body.size = size
	body.position = Vector2(-size.x / 2, -size.y + 10)
	body.color = tint
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.visible = false
	add_child(body)
	visual = Sprite2D.new()
	visual.centered = true
	visual.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	visual.texture = Art.enemy(data.id)
	var vh := Art.visual_h(data.id) * (size.y / maxf(1.0, data.size.y))
	if visual.texture:
		visual.scale = Vector2.ONE * (vh / visual.texture.get_height())
	visual.position = Vector2(0, 10 - vh * 0.5)
	add_child(visual)
	_sync_visual()
	warn = Label.new()
	warn.text = "!"
	warn.add_theme_font_size_override("font_size", 48)
	warn.add_theme_color_override("font_color", Color(1, 0.2, 0.2))
	warn.position = Vector2(-10, -size.y - 60)
	warn.visible = false
	add_child(warn)
	aim_line = Line2D.new()
	aim_line.width = 3
	aim_line.default_color = Color(1, 0.3, 0.3, 0.7)
	aim_line.visible = false
	add_child(aim_line)
	hurtbox = Hurtbox.new()
	hurtbox.team = "enemy"
	hurtbox.rx = size.x * 0.5
	hurtbox.ry = size.x * 0.3
	hurtbox.owner_actor = self
	add_child(hurtbox)
	hitbox = Hitbox.new()
	hitbox.team = "enemy"
	hitbox.source = self
	hitbox.source_name = data.display_name
	add_child(hitbox)
	nav = NavigationAgent2D.new()
	nav.path_desired_distance = 16.0
	nav.target_desired_distance = data.attack_range * 0.8
	nav.radius = size.x * 0.4
	add_child(nav)
	_repath_t = randf() * 0.25 ## 分帧错开寻路请求
	if home_pos == Vector2.INF:
		home_pos = global_position
	add_to_group("enemies")
	telegraph_delay = float(Game.mods().get("telegraph_delay", 0.0))
	cooldown = 0.6 + randf() * 0.6

func _physics_process(delta: float) -> void:
	var _p := Prof.t0()
	_prof_physics_process(delta)
	_sync_visual()
	Prof.add("enemy", _p)

func _sync_visual() -> void:
	if visual == null:
		return
	if feel_flash_t > 0.0:
		visual.modulate = Color(0.55, 0.9, 0.45) if feel_moss else Color(4, 4, 4)
	else:
		visual.modulate = body.color * body.modulate
	if absf(facing.x) > 0.2:
		visual.flip_h = facing.x < 0.0

func feel_flash(ms: int, moss := false, _redwhite := false) -> void:
	feel_flash_t = maxf(feel_flash_t, ms / 1000.0)
	feel_moss = moss

func _prof_physics_process(delta: float) -> void:
	feel_flash_t = maxf(0.0, feel_flash_t - delta)
	if state == S.DEAD:
		return
	state_t += delta
	slow_left = maxf(0.0, slow_left - delta)
	hz_slow_left = maxf(0.0, hz_slow_left - delta)
	cooldown = maxf(0.0, cooldown - delta)
	retreat_cd_left = maxf(0.0, retreat_cd_left - delta)
	_tick_moss(delta)
	_note_elite_seen()
	if target == null or not is_instance_valid(target):
		var ps := get_tree().get_nodes_in_group("player")
		target = ps[0] if not ps.is_empty() else null
	if ai and ai.pre_tick(delta):
		return
	_tick_extra(delta)
	match state:
		S.IDLE:
			velocity = Vector2.ZERO
			if aggro and target:
				_go(S.CHASE)
		S.PATROL:
			ai.tick_patrol(delta)
		S.ALERT:
			ai.tick_alert(delta)
		S.RETURN:
			if ai:
				ai.tick_return(delta)
			else:
				_return_home(delta)
		S.CHASE:
			_chase(delta)
		S.WINDUP:
			velocity = Vector2.ZERO
			warn.visible = state_t >= telegraph_delay
			body.color = tint.lerp(Color(1, 0.25, 0.2), 0.6)
			_sync_bounce_ring()
			if data.id == "rootshot":
				aim_line.visible = true
				aim_line.points = PackedVector2Array([Vector2.ZERO, attack_dir * 900])
			if state_t >= windup - 0.0001:
				last_windup_sec = state_t
				warn.visible = false
				aim_line.visible = false
				body.color = tint
				_begin_attack()
		S.ATTACK:
			_tick_attack(delta)
		S.RECOVER:
			velocity = Vector2.ZERO
			if state_t >= data.recover_sec:
				_go(S.CHASE)
			if ai:
				ai.end_attack()
		S.HURT:
			velocity = velocity.move_toward(Vector2.ZERO, 2000 * delta)
			move_and_slide()
			if state_t >= _hurt_len:
				_go(S.CHASE)
	if state != S.IDLE and state != S.PATROL:
		_separate()

var _hurt_len := 0.3

func _go(s: int) -> void:
	state = s
	state_t = 0.0
	if s == S.WINDUP:
		_prepare_attack()
		if target != null and is_instance_valid(target) and global_position.distance_to(target.global_position) <= Tutorial.rules.dash_threat_px:
			Tutorial.notify("threat")


## 环境机关减速（孢子云 −30%、缠根 −40%）：取持续中最强的一个
var hz_slow_left := 0.0
var hz_slow_pct := 0.0
var hz_slow_tag := "" ## 当前减速来源（root_snare = 缠根，可被冲刺挣脱）
func apply_hazard_slow(pct: float, sec: float, tag := "") -> void:
	if hz_slow_left <= 0.0 or pct >= hz_slow_pct:
		hz_slow_pct = pct
		hz_slow_tag = tag
	hz_slow_left = maxf(hz_slow_left, sec)
func hazard_speed_mult() -> float:
	return 1.0 - hz_slow_pct if hz_slow_left > 0.0 else 1.0

func speed() -> float:
	return data.move_speed * speed_mult * (0.5 if slow_left > 0.0 else 1.0) * hazard_speed_mult()

func should_return() -> bool:
	return false

## 朝 goal 走的方向：有导航时每 0.25 秒更新一次 target_position（goal 跳变 > 80px 立即更新），取下一个路径点
func nav_dir(goal: Vector2, delta: float) -> Vector2:
	var _p := Prof.t0()
	var _r := _prof_nav_dir(goal, delta)
	Prof.add("nav", _p)
	return _r

func _prof_nav_dir(goal: Vector2, delta: float) -> Vector2:
	var direct := (goal - global_position).normalized()
	if not use_nav or nav == null:
		return direct
	_repath_t -= delta
	if _repath_t <= 0.0 or _nav_goal == Vector2.INF or _nav_goal.distance_to(goal) > 80.0:
		_repath_t = 0.25
		_nav_goal = goal
		nav.target_position = goal
	var nxt := nav.get_next_path_position()
	if nxt.distance_to(global_position) < 1.0:
		return direct
	return (nxt - global_position).normalized()

func _return_home(delta: float) -> void:
	var to := home_pos - global_position
	if to.length() <= (rules.home_arrive_px if rules else 24.0):
		velocity = Vector2.ZERO
		_go(S.IDLE)
		return
	var dir := nav_dir(home_pos, delta)
	facing = dir if dir != Vector2.ZERO else facing
	velocity = dir * speed()
	move_and_slide()

func _chase(delta: float) -> void:
	if target == null:
		return
	if ai and (ai.chase_check(delta) or ai.chase_wait(delta)):
		return
	var to: Vector2 = target.global_position - global_position
	var dist := to.length()
	if elite_affix and elite_affix.leash_px > 0.0 and home_pos != Vector2.INF and global_position.distance_to(home_pos) > elite_affix.leash_px:
		_go(S.RETURN)
		return
	facing = to.normalized() if dist > 1 else facing
	var dir := nav_dir(target.global_position, delta)
	if data.id == "rootshot":
		if data.retreat_cd > 0.0 and dist <= 160.0 and retreat_cd_left <= 0.0 and retreat_left <= 0.0:
			retreat_left = 90.0
			retreat_cd_left = data.retreat_cd
			retreats += 1
		if retreat_left > 0.0:
			var away := -to.normalized() if dist > 1.0 else -facing
			var step := minf(retreat_left, speed() * delta)
			retreat_left -= step
			move_and_collide(away * step)
			velocity = Vector2.ZERO
			return
		if dist < data.keep_distance:
			dir = nav_dir(global_position - to.normalized() * 160.0, delta) ## 后退目标点同样走导航
		elif dist <= data.attack_range:
			dir = Vector2.ZERO
	elif dist <= data.attack_range * 0.8:
		dir = Vector2.ZERO
	velocity = dir * speed()
	move_and_slide()
	if dist <= data.attack_range and cooldown <= 0.0 and (ai == null or ai.request_attack()):
		attack_dir = to.normalized()
		_go(S.WINDUP)

func _begin_attack() -> void:
	_go(S.ATTACK)
	_atk_i += 1
	if _bouncing and elite_affix:
		attack_log.append("bounce")
		_land_pos = _bounce_aim()
		_bounce_phase = "air"
		_air_left = elite_affix.bounce_air_sec
		invulnerable = true
		_sync_bounce_ring()
		return
	attack_log.append("slam")
	match data.id:
		"mushling":
			_lunge_left = data.lunge_distance
			hitbox.knockback = 80
			hitbox.begin(damage, size.x * 0.5 + 14, 360.0, attack_dir)
		"rootshot":
			_shoot(attack_dir)
		_:
			hitbox.knockback = 140
			hitbox.begin(damage, data.attack_range + 20, data.slam_arc_deg, attack_dir)
			Game.hitstop(0.0)

func _shoot(dir: Vector2) -> void:
	var p := Projectile.new()
	p.team = "enemy"
	p.damage = damage
	p.velocity = dir * data.projectile_speed
	p.source_name = data.display_name
	p.position = global_position + dir * 20
	get_parent().add_child(p)

func _tick_attack(delta: float) -> void:
	if _bouncing:
		_tick_bounce(delta)
		return
	match data.id:
		"mushling":
			var step := minf(data.lunge_distance / data.lunge_time * delta, _lunge_left)
			_lunge_left -= step
			move_and_collide(attack_dir * step)
			if _lunge_left <= 0.001 or state_t >= data.lunge_time + 0.05:
				_end_attack()
		"rootshot":
			_end_attack()
		_:
			if state_t >= data.attack_active:
				_end_attack()

func _end_attack() -> void:
	hitbox.end()
	cooldown = effective_interval()
	_go(S.RECOVER)

func effective_interval() -> float:
	return attack_interval

func _tick_extra(_delta: float) -> void:
	pass

## 被打：from_back 时乘 back_mult；poise 打满才硬直
func take_hit(dmg: int, src: Node, knockback: Vector2) -> bool:
	if state == S.DEAD or invulnerable:
		return false
	var from := global_position - (knockback.normalized() * 10.0)
	if src is Node2D:
		from = src.global_position
	var to_src := (from - global_position).normalized()
	var real := dmg
	if back_mult > 1.0 and facing.dot(to_src) < -0.3:
		real = roundi(dmg * back_mult)
	if moss_affix and moss_down <= 0.0 and moss_affix.dmg_taken_mult > 0.0:
		real = roundi(float(real) * moss_affix.dmg_taken_mult)
	if moss_affix and moss_affix.break_by_heavy and _hit_is_heavy(src) and moss_down <= 0.0 and moss_lock <= 0.0:
		moss_down = moss_affix.break_sec
		Tutorial.on_thickmoss_broken()
		HitFeedback.play("armor_break", self)
	hp = maxi(0, hp - real)
	DamageNumber.spawn(get_parent(), global_position, real, Color(1, 0.95, 0.5) if real > dmg else Color.WHITE)
	Log.write("hits", [Game.run.id if Game.run else "", depth, "主角", data.display_name, real, false])
	if ai:
		ai.on_hit()
	var stagger := float(src.get("stagger_sec")) if src and src.get("stagger_sec") != null else 0.0
	var slow := float(src.get("slow_sec")) if src and src.get("slow_sec") != null else 0.0
	if slow > 0.0:
		slow_left = maxf(slow_left, slow)
	if hp <= 0:
		_die()
		return true
	var poise_mult := 1.0
	if src and src.get("poise_dmg_mult") != null:
		poise_mult = float(src.poise_dmg_mult)
	poise_acc += real * poise_mult
	if poise_acc >= poise or stagger > 0.0:
		poise_acc = 0.0
		hitbox.end()
		warn.visible = false
		aim_line.visible = false
		body.color = tint
		_hurt_len = maxf(data.hurt_sec, stagger)
		velocity = knockback / 0.2
		if ai:
			ai.end_attack()
		_go(S.HURT)
	elif knockback.length() > 1.0 and is_physics_processing():
		## 没破韧也按资源击退一截。关掉物理的测试假人停在原地。
		move_and_collide(knockback)
	return true

func _die() -> void:
	if ai:
		ai.release()
		NoiseBus.emit_kind(global_position, "death")
	HitFeedback.on_killed(self)
	_go(S.DEAD)
	hitbox.end()
	remove_from_group("enemies")
	hurtbox.remove_from_group("hurtbox_enemy")
	if Game.run:
		Game.run.kills += 1
		Game.run.floor_stats["kills"] = int(Game.run.floor_stats.get("kills", 0)) + 1
		var rm := 1.0 + float(Game.mods().get("rare_drop_pct", 0))
		for st in roll_loot(rm):
			Game.run.add_item(st)
		if not (self is Guard):
			var ckey := str(get_meta("rid", ""))
			if ckey == "":
				ckey = "%s@%d,%d" % [data.id, int(global_position.x), int(global_position.y)]
			Game.recall.roll_elite(data.id, ckey)
		Game.gain_xp(xp_value())
		var kh := int(Game.mods().get("kill_heal", 0))
		if kh > 0:
			for p in get_tree().get_nodes_in_group("player"):
				p.heal(kh)
	died.emit(self)
	queue_free()

func roll_loot(rare_mult := 1.0) -> Array[ItemStack]:
	var table := elite_affix.loot_table if elite_affix and elite_affix.loot_table else data.loot_table
	if table == null:
		return []
	return table.roll(Game.rng, rare_mult)

func xp_value() -> int:
	return roundi(data.xp * xp_mult)

func _separate() -> void:
	var _p := Prof.t0()
	_prof_separate()
	Prof.add("separate", _p)

## 性能：敌人列表每个物理帧只取一次（原来每只敌人每帧都 get_nodes_in_group 一次，分配新数组）
static var _sep_list: Array = []
static var _sep_frame := -1
func _prof_separate() -> void:
	var pf := Engine.get_physics_frames()
	if pf != _sep_frame:
		_sep_frame = pf
		_sep_list = get_tree().get_nodes_in_group("enemies")
	var gp := global_position
	for e in _sep_list:
		if e != self and is_instance_valid(e):
			var d: Vector2 = gp - e.global_position
			var min_d: float = (size.x + e.size.x) * 0.45
			var dl2 := d.length_squared()
			if dl2 >= min_d * min_d:
				continue
			if dl2 > 0.0001:
				move_and_collide(d.normalized() * (min_d - d.length()) * 0.3)

## 史莱姆 + 厚苔 + 精英。不新做敌人。菌环中心由 Floor.spawn_elite 刷出。
func make_thickmoss_elite() -> void:
	if _elite_ready:
		return
	_elite_ready = true
	moss_affix = Game.affixes.thickmoss
	elite_affix = Game.affixes.elite
	max_hp = roundi(max_hp * elite_affix.hp_mult)
	hp = max_hp
	damage = roundi(damage * elite_affix.dmg_mult)
	poise *= 1.0 + moss_affix.poise_pct
	if elite_affix.interval_override > 0.0:
		attack_interval = elite_affix.interval_override
	speed_mult = elite_affix.speed_mult
	xp_mult = elite_affix.xp_mult
	if elite_affix.palette == "deep_moss":
		tint = Color(0.13, 0.34, 0.24)
	if body:
		body.color = tint
	set_meta("elite", true)
	add_to_group("elites")
	bounce_ring = BounceRing.new()
	bounce_ring.visible = false
	add_child(bounce_ring)

func bounce_damage() -> int:
	if elite_affix == null:
		return damage
	var scale := 1.0
	if depth >= 1 and depth <= Game.floors.size():
		scale = Game.floors[depth - 1].dmg_scale()
	return roundi(data.damage * elite_affix.bounce_damage_mult * scale)

func moss_up() -> bool:
	return moss_affix != null and moss_down <= 0.0

func is_limping() -> bool:
	return _bounce_phase == "limp"

func _hit_is_heavy(src: Node) -> bool:
	return src != null and src.get("is_heavy") != null and bool(src.is_heavy)

func _tick_moss(delta: float) -> void:
	if moss_affix == null:
		return
	if moss_down > 0.0:
		moss_down = maxf(0.0, moss_down - delta)
		if moss_down <= 0.0:
			moss_lock = moss_affix.break_cd
			if body:
				body.color = tint
	elif moss_lock > 0.0:
		moss_lock = maxf(0.0, moss_lock - delta)

func _note_elite_seen() -> void:
	if _elite_introduced or elite_affix == null or target == null or not is_instance_valid(target):
		return
	if global_position.distance_to(target.global_position) <= 520.0:
		_elite_introduced = true
		Tutorial.on_elite_first_seen()

func _prepare_attack() -> void:
	if elite_affix == null or not elite_affix.bounce_enabled:
		_bouncing = false
		return
	var n := _atk_i + 1
	_bouncing = elite_affix.bounce_every > 0 and n % elite_affix.bounce_every == 0
	windup = elite_affix.bounce_windup if _bouncing else data.windup
	if not _bouncing and bounce_ring:
		bounce_ring.visible = false

func _bounce_aim() -> Vector2:
	var dest := global_position + attack_dir * 80.0
	if target and is_instance_valid(target):
		dest = target.global_position
	var delta := dest - global_position
	if delta.length() > elite_affix.bounce_range:
		dest = global_position + delta.normalized() * elite_affix.bounce_range
	return dest

func _sync_bounce_ring() -> void:
	if bounce_ring == null or elite_affix == null:
		return
	if not _bouncing or _bounce_phase == "limp":
		bounce_ring.visible = false
		return
	bounce_ring.visible = true
	var at := _land_pos if _bounce_phase == "air" else _bounce_aim()
	bounce_ring.global_position = at
	bounce_ring.radius = elite_affix.bounce_radius
	bounce_ring.fill = 1.0 if _bounce_phase == "air" else clampf(state_t / maxf(0.01, windup), 0.0, 1.0)
	bounce_ring.queue_redraw()

func _tick_bounce(delta: float) -> void:
	velocity = Vector2.ZERO
	if _bounce_phase == "air":
		_air_left -= delta
		_sync_bounce_ring()
		if _air_left <= 0.0:
			_bounce_land()
	elif _bounce_phase == "limp":
		_limp_left -= delta
		if _limp_left <= 0.0:
			_bouncing = false
			_bounce_phase = ""
			invulnerable = false
			if bounce_ring:
				bounce_ring.visible = false
			_end_attack()

func _bounce_land() -> void:
	global_position = _land_pos
	invulnerable = false
	_bounce_phase = "limp"
	_limp_left = elite_affix.bounce_recover
	if bounce_ring:
		bounce_ring.visible = false
	var dmg := bounce_damage()
	for p in get_tree().get_nodes_in_group("player"):
		if not is_instance_valid(p):
			continue
		if p.global_position.distance_to(_land_pos) <= elite_affix.bounce_radius:
			var away: Vector2 = p.global_position - _land_pos
			if away.length() < 1.0:
				away = attack_dir
			p.take_hit(dmg, self, away.normalized() * 140.0)

class BounceRing extends Node2D:
	var radius := 100.0
	var fill := 0.0

	func _draw() -> void:
		var a := 0.18 + 0.17 * clampf(fill, 0.0, 1.0)
		draw_circle(Vector2.ZERO, radius, Color(0.478, 0.165, 0.165, a))
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 40, Color(0.784, 0.345, 0.29, 0.4 + 0.45 * clampf(fill, 0.0, 1.0)), 3.0)
