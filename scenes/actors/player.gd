class_name Player
extends CharacterBody2D
## 主角：8 方向移动；攻击朝向 = 右摇杆 / 鼠标，没有瞄准输入时跟移动方向。
## 状态机 IDLE / MOVE / ATTACK / DASH / SKILL / HURT / DEAD；冲刺有无敌帧、2 次独立充能，可取消普攻任意阶段。

signal hp_changed(cur: int, max: int)
signal died(cause: String)
signal dashed(from: Vector2, to: Vector2)
signal damaged(amount: int)

enum S { IDLE, MOVE, ATTACK, DASH, SKILL, HURT, DEAD }
const SIZE := Vector2(40, 64)

var state := S.IDLE
var stats: PlayerStats
var mods := {}
var hp := 100
var max_hp := 100
var facing := Vector2.RIGHT
var hurtbox: Hurtbox
var hitbox: Hitbox
var iframe_left := 0.0
var flash_t := 0.0
# 冲刺
var dash_cd: Array[float] = [] ## 每格充能剩余冷却（0 = 可用）
var dash_dir := Vector2.ZERO
var dash_travelled := 0.0
var dash_total := 0.0
var dash_t := 0.0
var dash_start := Vector2.ZERO
var last_dash_distance := 0.0
# 普攻 / 技能
var combo_i := 0 ## 下一段（0..2）
var combo_timer := 0.0
var atk: AttackData
var phase := "" ## windup / active / recovery
var phase_t := 0.0
var attack_buffered := false
var skill_cd_left := 0.0
var hurt_t := 0.0
var kb_vel := Vector2.ZERO
var _mouse_aim_t := -10.0
var input_enabled := true
var sim_move := Vector2.ZERO ## 测试注入
var sim_aim := Vector2.ZERO
var body_rect: ColorRect
var depth := 1

func _ready() -> void:
	stats = Game.player_stats
	collision_layer = 2
	collision_mask = 1
	var cs := CollisionShape2D.new()
	var sh := CircleShape2D.new()
	sh.radius = 16
	cs.shape = sh
	add_child(cs)
	body_rect = ColorRect.new()
	body_rect.size = SIZE
	body_rect.position = Vector2(-SIZE.x / 2, -SIZE.y + 8)
	body_rect.color = Color(0.3, 0.6, 1.0)
	body_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(body_rect)
	hurtbox = Hurtbox.new()
	hurtbox.team = "player"
	hurtbox.owner_actor = self
	add_child(hurtbox)
	hitbox = Hitbox.new()
	hitbox.team = "player"
	hitbox.source = self
	hitbox.source_name = "主角"
	hitbox.destroys_projectiles = true
	hitbox.hit_landed.connect(_on_hit_landed)
	add_child(hitbox)
	add_to_group("player")
	refresh_stats()

## 吃等级、强化、遗志、特质、装备的属性修正
func apply_stat_mods(m: Dictionary) -> void:
	mods = m
	var old_max := max_hp
	max_hp = Game.max_hp() if Game.run else stats.max_hp + int(m.get("max_hp_add", 0))
	if old_max != max_hp and old_max > 0:
		hp = clampi(hp + maxi(0, max_hp - old_max), 0, max_hp)
	var n := dash_charges()
	while dash_cd.size() < n:
		dash_cd.append(0.0)
	while dash_cd.size() > n:
		dash_cd.pop_back()
	hp_changed.emit(hp, max_hp)

func refresh_stats() -> void:
	apply_stat_mods(Game.mods())

func dash_charges() -> int:
	return maxi(1, stats.dash_charges + int(mods.get("dash_charges_add", 0)))

func dash_recharge() -> float:
	return stats.dash_recharge * maxf(0.1, 1.0 + float(mods.get("dash_recharge_pct", 0)))

func dash_distance() -> float:
	return stats.dash_distance * (1.0 + float(mods.get("dash_dist_pct", 0)))


## 环境机关减速（孢子云 −30%、缠根 −40%）：取持续中最强的一个
var hz_slow_left := 0.0
var hz_slow_pct := 0.0
var snare_breaks := 0
var hz_slow_tag := "" ## 当前减速来源（root_snare = 缠根，可被冲刺挣脱）
func apply_hazard_slow(pct: float, sec: float, tag := "") -> void:
	if hz_slow_left <= 0.0 or pct >= hz_slow_pct:
		hz_slow_pct = pct
		hz_slow_tag = tag
	hz_slow_left = maxf(hz_slow_left, sec)
func hazard_speed_mult() -> float:
	return 1.0 - hz_slow_pct if hz_slow_left > 0.0 else 1.0

func move_speed() -> float:
	return stats.move_speed * (1.0 + float(mods.get("move_pct", 0))) * hazard_speed_mult()

func skill_cooldown() -> float:
	return Game.skill.cooldown * maxf(0.1, 1.0 + float(mods.get("skill_cd_pct", 0)))

func atk_mult() -> float:
	return (1.0 + (Game.level() - 1) * stats.atk_per_level) * (1.0 + float(mods.get("atk_pct", 0)))

func attack_damage(a: AttackData, seg: int) -> int:
	var m := atk_mult()
	if seg >= 0:
		m *= 1.0 + float(mods.get("light_pct", 0))
		if seg == 2:
			m *= 1.0 + float(mods.get("finisher_pct", 0))
	return roundi(a.damage * m)

func charges_ready() -> int:
	return dash_cd.filter(func(c): return c <= 0.0).size()

func is_invulnerable() -> bool:
	return iframe_left > 0.0 or state == S.DEAD

# ---------- 输入 ----------
func move_input() -> Vector2:
	if sim_move != Vector2.ZERO:
		return sim_move.limit_length(1.0)
	if not input_enabled:
		return Vector2.ZERO
	return Input.get_vector("move_left", "move_right", "move_up", "move_down")

func aim_input() -> Vector2:
	if sim_aim != Vector2.ZERO:
		return sim_aim.normalized()
	var st := Input.get_vector("aim_left", "aim_right", "aim_up", "aim_down")
	if st.length() > 0.3:
		return st.normalized()
	if Time.get_ticks_msec() / 1000.0 - _mouse_aim_t < 1.5:
		var d := get_global_mouse_position() - global_position
		if d.length() > 8:
			return d.normalized()
	return Vector2.ZERO

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion:
		_mouse_aim_t = Time.get_ticks_msec() / 1000.0
	if not input_enabled or get_tree().paused:
		return
	if e.is_action_pressed("dash"):
		try_dash()
	elif e.is_action_pressed("attack"):
		try_attack()
	elif e.is_action_pressed("skill"):
		try_skill()

# ---------- 动作 ----------
func try_attack() -> bool:
	if state in [S.DEAD, S.HURT, S.DASH, S.SKILL]:
		return false
	if state == S.ATTACK:
		if phase == "recovery":
			attack_buffered = true
		return false
	_start_attack()
	return true

func _start_attack() -> void:
	if combo_timer <= 0.0:
		combo_i = 0
	_update_facing()
	atk = Game.attacks[combo_i]
	state = S.ATTACK
	phase = "windup"
	phase_t = 0.0
	attack_buffered = false

func try_skill() -> bool:
	if state in [S.DEAD, S.HURT, S.DASH, S.SKILL] or skill_cd_left > 0.0:
		return false
	if state == S.ATTACK:
		hitbox.end()
	_update_facing()
	atk = Game.skill
	NoiseBus.emit_kind(global_position, "combat")
	state = S.SKILL
	phase = "windup"
	phase_t = 0.0
	skill_cd_left = skill_cooldown()
	return true

func try_dash() -> bool:
	if state == S.DEAD or state == S.HURT:
		return false
	var i := dash_cd.find(0.0)
	if i < 0:
		for k in dash_cd.size():
			if dash_cd[k] <= 0.0:
				i = k
				break
	if i < 0 and not Game.inf_dash:
		return false
	if i >= 0 and not Game.inf_dash:
		dash_cd[i] = dash_recharge()
	if hz_slow_left > 0.0 and hz_slow_tag == "root_snare": ## 冲刺挣脱缠根
		hz_slow_left = 0.0
		hz_slow_tag = ""
		snare_breaks += 1
	if state == S.ATTACK or state == S.SKILL:
		hitbox.end() ## 取消普攻（含后摇）
	var mv := move_input()
	dash_dir = (mv if mv.length() > 0.2 else facing).normalized()
	dash_total = dash_distance()
	dash_travelled = 0.0
	dash_t = 0.0
	dash_start = global_position
	iframe_left = maxf(iframe_left, stats.dash_iframes)
	state = S.DASH
	NoiseBus.emit_kind(global_position, "dash")
	return true

func _update_facing() -> void:
	var a := aim_input()
	if a == Vector2.ZERO:
		var m := move_input()
		if m.length() > 0.2:
			a = m.normalized()
	if a != Vector2.ZERO:
		facing = a

func _physics_process(delta: float) -> void:
	var _p := Prof.t0()
	_prof_physics_process(delta)
	Prof.add("player", _p)

func _prof_physics_process(delta: float) -> void:
	hz_slow_left = maxf(0.0, hz_slow_left - delta)
	iframe_left = maxf(0.0, iframe_left - delta)
	skill_cd_left = maxf(0.0, skill_cd_left - delta)
	combo_timer = maxf(0.0, combo_timer - delta)
	for k in dash_cd.size():
		dash_cd[k] = maxf(0.0, dash_cd[k] - delta)
	match state:
		S.DEAD:
			velocity = Vector2.ZERO
		S.DASH:
			dash_t += delta
			var step := minf(dash_total / stats.dash_time * delta, dash_total - dash_travelled)
			var col := move_and_collide(dash_dir * step)
			dash_travelled += step
			if col:
				dash_travelled = dash_total
			if dash_travelled >= dash_total - 0.001:
				last_dash_distance = global_position.distance_to(dash_start)
				state = S.IDLE
				dashed.emit(dash_start, global_position)
		S.HURT:
			hurt_t -= delta
			velocity = kb_vel
			kb_vel = kb_vel.move_toward(Vector2.ZERO, 1500 * delta)
			move_and_slide()
			if hurt_t <= 0.0:
				state = S.IDLE
		S.ATTACK, S.SKILL:
			_tick_attack(delta)
			velocity = move_input() * move_speed() * 0.25
			move_and_slide()
		_:
			var mv := move_input()
			velocity = mv * move_speed()
			state = S.MOVE if mv.length() > 0.05 else S.IDLE
			_update_facing()
			move_and_slide()
	hitbox.position = Vector2.ZERO
	hurtbox.invulnerable = is_invulnerable()
	flash_t += delta
	body_rect.modulate.a = 0.35 if (iframe_left > 0.0 and state != S.DASH and int(flash_t * 20) % 2 == 0) else 1.0
	body_rect.color = Color(0.55, 0.8, 1.0) if state == S.DASH else Color(0.3, 0.6, 1.0)

func _tick_attack(delta: float) -> void:
	phase_t += delta
	var seg := combo_i if state == S.ATTACK else -1
	if phase == "windup" and phase_t >= atk.windup:
		phase = "active"
		phase_t -= atk.windup
		hitbox.knockback = atk.knockback
		hitbox.stagger_sec = atk.stagger_sec
		hitbox.slow_sec = float(mods.get("skill_slow_sec", 0)) if state == S.SKILL else 0.0
		hitbox.begin(attack_damage(atk, seg), atk.attack_range, atk.arc_deg, facing)
		hitbox.check()
	if phase == "active" and phase_t >= atk.active:
		phase = "recovery"
		phase_t -= atk.active
		hitbox.end()
	if phase == "recovery" and phase_t >= atk.recovery:
		if state == S.ATTACK:
			combo_i = (combo_i + 1) % 3
			combo_timer = Game.attacks[0].combo_reset
			Mastery.use("root_blade")
		state = S.IDLE
		phase = ""
		if attack_buffered:
			_start_attack()

func _on_hit_landed(_t: Node, _dmg: int) -> void:
	NoiseBus.emit_kind(global_position, "combat")
	Game.hitstop(atk.hitstop_sec if atk else stats.hitstop_sec)
	var cam := get_viewport().get_camera_2d()
	if cam and cam.has_method("shake"):
		cam.shake(stats.shake_px)

## 返回 false = 无敌中没受伤
func take_hit(dmg: int, src: Node, knockback: Vector2) -> bool:
	var sname := String(src.get("source_name")) if src and src.get("source_name") != null else "未知"
	var depth_now := Game.run.depth if Game.run else 0
	if is_invulnerable():
		Log.write("hits", [Game.run.id if Game.run else "", depth_now, sname, "主角", 0, state == S.DASH or iframe_left > 0.0])
		return false
	var real := 0 if Game.god_mode else dmg
	hp = maxi(0, hp - real)
	if Game.run:
		Game.run.hp = hp
		Game.run.dmg_taken += real
		Game.run.floor_stats["dmg_taken"] = int(Game.run.floor_stats.get("dmg_taken", 0)) + real
	Log.write("hits", [Game.run.id if Game.run else "", depth_now, sname, "主角", real, false])
	if real > 0:
		damaged.emit(real)
	DamageNumber.spawn(get_parent(), global_position, real, Color(1, 0.4, 0.4))
	hp_changed.emit(hp, max_hp)
	iframe_left = stats.hurt_iframes
	hitbox.end()
	if hp <= 0:
		state = S.DEAD
		body_rect.color = Color(0.3, 0.3, 0.35)
		died.emit(sname)
		return true
	state = S.HURT
	hurt_t = 0.15
	var dir := knockback.normalized() if knockback.length() > 0.01 else Vector2.ZERO
	kb_vel = dir * stats.hurt_knockback / 0.15 * 1.4
	return true

func heal(n: int) -> void:
	hp = mini(max_hp, hp + n)
	if Game.run:
		Game.run.hp = hp
	hp_changed.emit(hp, max_hp)

func kill_self() -> void:
	iframe_left = 0.0
	var g := Game.god_mode
	Game.god_mode = false
	take_hit(hp, null, Vector2.ZERO)
	Game.god_mode = g
