class_name EnemyBase
extends CharacterBody2D
## 普通敌人基类：IDLE / CHASE / WINDUP / ATTACK / RECOVER / HURT / DEAD
## 攻击前摇有明显预兆（变色 + “!” 图标），时长 = windup；poise 打满才硬直（普通怪 poise 0 = 每下都硬直）

signal died(enemy: EnemyBase)

enum S { IDLE, CHASE, WINDUP, ATTACK, RECOVER, HURT, DEAD }

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
var warn: Label
var aim_line: Line2D
var size := Vector2(40, 48)
var tint := Color.WHITE
var walls: Array = [] ## 给弹道用
var last_windup_sec := -1.0 ## 测试：上一次前摇实际时长
var telegraph_delay := 0.0
var invulnerable := false
var aggro := true
var _lunge_left := 0.0
var _windup_started := 0.0

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
	add_child(body)
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
	add_to_group("enemies")
	telegraph_delay = float(Game.mods().get("telegraph_delay", 0.0))
	cooldown = 0.6 + randf() * 0.6

func _physics_process(delta: float) -> void:
	if state == S.DEAD:
		return
	state_t += delta
	slow_left = maxf(0.0, slow_left - delta)
	cooldown = maxf(0.0, cooldown - delta)
	if target == null or not is_instance_valid(target):
		var ps := get_tree().get_nodes_in_group("player")
		target = ps[0] if not ps.is_empty() else null
	_tick_extra(delta)
	match state:
		S.IDLE:
			velocity = Vector2.ZERO
			if aggro and target:
				_go(S.CHASE)
		S.CHASE:
			_chase(delta)
		S.WINDUP:
			velocity = Vector2.ZERO
			warn.visible = state_t >= telegraph_delay
			body.color = tint.lerp(Color(1, 0.25, 0.2), 0.6)
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
		S.HURT:
			velocity = velocity.move_toward(Vector2.ZERO, 2000 * delta)
			move_and_slide()
			if state_t >= _hurt_len:
				_go(S.CHASE)
	_separate()

var _hurt_len := 0.3

func _go(s: int) -> void:
	state = s
	state_t = 0.0

func speed() -> float:
	return data.move_speed * (0.5 if slow_left > 0.0 else 1.0)

func _chase(_delta: float) -> void:
	if target == null:
		return
	var to: Vector2 = target.global_position - global_position
	var dist := to.length()
	facing = to.normalized() if dist > 1 else facing
	var dir := to.normalized()
	if data.id == "rootshot":
		if dist < data.keep_distance:
			dir = -dir
		elif dist <= data.attack_range:
			dir = Vector2.ZERO
	elif dist <= data.attack_range * 0.8:
		dir = Vector2.ZERO
	velocity = dir * speed()
	move_and_slide()
	if dist <= data.attack_range and cooldown <= 0.0:
		attack_dir = to.normalized()
		_go(S.WINDUP)

func _begin_attack() -> void:
	_go(S.ATTACK)
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
	p.walls = walls
	p.position = global_position + dir * 20
	get_parent().add_child(p)

func _tick_attack(delta: float) -> void:
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
	hp = maxi(0, hp - real)
	DamageNumber.spawn(get_parent(), global_position, real, Color(1, 0.95, 0.5) if real > dmg else Color.WHITE)
	Log.write("hits", [Game.run.id if Game.run else "", depth, "主角", data.display_name, real, false])
	var stagger := float(src.get("stagger_sec")) if src and src.get("stagger_sec") != null else 0.0
	var slow := float(src.get("slow_sec")) if src and src.get("slow_sec") != null else 0.0
	if slow > 0.0:
		slow_left = maxf(slow_left, slow)
	if hp <= 0:
		_die()
		return true
	poise_acc += real
	if poise_acc >= poise or stagger > 0.0:
		poise_acc = 0.0
		hitbox.end()
		warn.visible = false
		aim_line.visible = false
		body.color = tint
		_hurt_len = maxf(data.hurt_sec, stagger)
		velocity = knockback / 0.2
		_go(S.HURT)
	return true

func _die() -> void:
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
		Game.gain_xp(xp_value())
		var kh := int(Game.mods().get("kill_heal", 0))
		if kh > 0:
			for p in get_tree().get_nodes_in_group("player"):
				p.heal(kh)
	died.emit(self)
	queue_free()

func roll_loot(rare_mult := 1.0) -> Array[ItemStack]:
	if data.loot_table == null:
		return []
	return data.loot_table.roll(Game.rng, rare_mult)

func xp_value() -> int:
	return data.xp

func _separate() -> void:
	for e in get_tree().get_nodes_in_group("enemies"):
		if e != self:
			var d: Vector2 = global_position - e.global_position
			var min_d: float = (size.x + e.size.x) * 0.45
			if d.length() < min_d and d.length() > 0.01:
				move_and_collide(d.normalized() * (min_d - d.length()) * 0.3)
