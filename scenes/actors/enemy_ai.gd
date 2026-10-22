class_name EnemyAI
extends Node
## 地图怪的仇恨 AI（规格第 2 节），挂在 EnemyBase 下。EnemyBase 的 PATROL / ALERT / RETURN 由这里驱动，
## CHASE 里的脱离判定、追击名额（包围待机）、攻击令牌也在这里。战斗状态（WINDUP 等）仍由 EnemyBase 处理。
## 时间一律用累计的 delta（随 time_scale）。

var e: EnemyBase
var R: AggroRules
var director: AggroDirector
var floor_node: Node ## 楼层（查同组成员）
var style := "walk" ## walk 巡逻 / post 射手驻守 / camp 营地待机
var route: Array = [] ## 巡逻路线点（含本人的队形偏移）
var route_i := 0
var post_t := 0.0
var clock := 0.0
var _sight_t := 0.0
var seen_t := 0.0 ## 锥内连续看到主角的时间
var lost_t := 0.0 ## 追击中失去视野的时间
var alert_t := 0.0
var alert_src := Vector2.INF
var investigate_goal := Vector2.INF
var reaggro_at := -999.0
var link_rolled := false ## 跨组联动：每个敌人只判定一次
var has_slot := false
var orbit_dir := 1.0
var sleeping := false
var _sleep_t := 0.0
var _regen_acc := 0.0
var last_reason := ""
var q_label: Label
var rng := RandomNumberGenerator.new()

func setup(p_e: EnemyBase, p_rules: AggroRules, p_director: AggroDirector, p_floor: Node, p_style: String, p_route: Array) -> void:
	e = p_e
	R = p_rules
	director = p_director
	floor_node = p_floor
	style = p_style
	route = p_route
	rng.seed = hash([e.home_pos, e.get_meta("group", "")])
	orbit_dir = 1.0 if rng.randf() < 0.5 else -1.0
	_sight_t = rng.randf() * R.sight_interval ## 分帧错开
	_sleep_t = rng.randf() * 0.5

func _ready() -> void:
	q_label = Label.new()
	q_label.text = "?"
	q_label.add_theme_font_size_override("font_size", 44)
	q_label.add_theme_color_override("font_color", Color(1, 0.9, 0.3))
	q_label.position = Vector2(-10, -e.size.y - 60)
	q_label.visible = false
	e.add_child(q_label)

func in_combat() -> bool:
	return e.state in [EnemyBase.S.CHASE, EnemyBase.S.WINDUP, EnemyBase.S.ATTACK, EnemyBase.S.RECOVER, EnemyBase.S.HURT]

func sight_range() -> float:
	var r := R.ranged_sight_range if style == "post" else R.sight_range
	if floor_node and floor_node.get("player_in_thicket") == true:
		r *= R.thicket_sight_mult
	return r

func sight_angle() -> float:
	return 360.0 if style == "camp" else R.sight_angle_deg

func target_pos() -> Vector2:
	return e.target.global_position if e.target and is_instance_valid(e.target) else Vector2.INF

func _player_in_no_go() -> bool:
	var p := target_pos()
	return p != Vector2.INF and e.no_go.has_point(p)

## 视野：近身 sense_radius 一律察觉；否则要在 sight_range、视野角内，并且墙体层射线不被挡
func can_see_player(use_cone := true) -> bool:
	var _p := Prof.t0()
	var _r = _prof_can_see_player(use_cone)
	Prof.add("sight", _p)
	return _r

func _prof_can_see_player(use_cone := true) -> bool:
	var p := target_pos()
	if p == Vector2.INF or _player_in_no_go():
		return false
	var to := p - e.global_position
	var d := to.length()
	if d <= R.sense_radius:
		return true
	if d > sight_range():
		return false
	if use_cone and sight_angle() < 359.0 and d > 0.01:
		if rad_to_deg(e.facing.angle_to(to)) > sight_angle() / 2.0 or rad_to_deg(e.facing.angle_to(to)) < -sight_angle() / 2.0:
			return false
	return has_los(p)

func has_los(p: Vector2) -> bool:
	var space := e.get_world_2d().direct_space_state
	var q := PhysicsRayQueryParameters2D.create(e.global_position, p, MapGen.OPAQUE_LAYER) ## 只有挡视线的地形（水、断崖不挡）
	return space.intersect_ray(q).is_empty()

## 每帧由 EnemyBase 调用；返回 true = 本帧休眠（不再处理）
func pre_tick(delta: float) -> bool:
	clock += delta
	if e.state == EnemyBase.S.PATROL or e.state == EnemyBase.S.ALERT:
		_sleep_t -= delta
		if _sleep_t <= 0.0:
			_sleep_t = 0.5
			var p := target_pos()
			sleeping = (Game.debug_panel != null and Game.debug_panel.get("sleep_all") == true) or (p != Vector2.INF and e.global_position.distance_to(p) > R.sleep_radius)
		if sleeping:
			e.velocity = Vector2.ZERO
			return true
	else:
		sleeping = false
	q_label.visible = e.state == EnemyBase.S.ALERT
	return false

func _sight_tick(delta: float) -> bool:
	_sight_t -= delta
	if _sight_t > 0.0:
		return false
	_sight_t += R.sight_interval
	return true

func tick_patrol(delta: float) -> void:
	if _sight_tick(delta) and clock >= reaggro_at and can_see_player():
		seen_t = 0.0
		_to_alert(target_pos(), false)
		return
	if style == "camp" or route.size() < 2:
		_move_to(e.home_pos, delta, R.patrol_speed_mult, 12.0)
		return
	var goal: Vector2 = route[route_i]
	if e.global_position.distance_to(goal) <= 20.0:
		if style == "post":
			post_t += delta
			e.velocity = Vector2.ZERO
			if post_t < R.post_sec:
				return
		post_t = 0.0
		route_i = (route_i + 1) % route.size()
		goal = route[route_i]
	_move_to(goal, delta, R.patrol_speed_mult)

func _move_to(goal: Vector2, delta: float, mult: float, arrive := 4.0) -> void:
	if e.global_position.distance_to(goal) <= arrive:
		e.velocity = Vector2.ZERO
		return
	var dir := e.nav_dir(goal, delta)
	if dir != Vector2.ZERO:
		e.facing = dir
	e.velocity = dir * e.speed() * mult
	e.move_and_slide()

func _to_alert(src: Vector2, from_noise: bool) -> void:
	alert_src = src
	alert_t = 0.0
	investigate_goal = e.global_position + (src - e.global_position).limit_length(R.investigate_px) if from_noise else Vector2.INF
	if src != Vector2.INF and src.distance_to(e.global_position) > 1.0:
		e.facing = (src - e.global_position).normalized()
	e._go(EnemyBase.S.ALERT)

func tick_alert(delta: float) -> void:
	alert_t += delta
	if _sight_tick(delta):
		if clock >= reaggro_at and can_see_player():
			seen_t += R.sight_interval
			alert_src = target_pos()
			alert_t = 0.0
			if seen_t >= R.sight_confirm_sec - 0.001:
				enter_chase("sight")
				return
		else:
			seen_t = 0.0
	if investigate_goal != Vector2.INF and e.global_position.distance_to(investigate_goal) > 16.0:
		_move_to(investigate_goal, delta, R.patrol_speed_mult)
	else:
		e.velocity = Vector2.ZERO
		if alert_src != Vector2.INF and alert_src.distance_to(e.global_position) > 1.0:
			e.facing = (alert_src - e.global_position).normalized()
	if alert_t >= R.alert_sec:
		seen_t = 0.0
		e._go(EnemyBase.S.PATROL)

## 听到声音（RETURN、追击中不响应）
var last_heard_kind := "" ## 最近一次听到的声音种类（调试 / 测试）

func hear(pos: Vector2, radius: float, _kind: String) -> void:
	last_heard_kind = _kind
	if not (e.state == EnemyBase.S.PATROL or e.state == EnemyBase.S.ALERT):
		return
	if clock < reaggro_at:
		return
	sleeping = false
	if e.global_position.distance_to(pos) <= radius * R.noise_aggro_ratio:
		enter_chase("noise")
	else:
		_to_alert(pos, true)

func on_hit() -> void:
	if e.state == EnemyBase.S.PATROL or e.state == EnemyBase.S.ALERT or e.state == EnemyBase.S.RETURN:
		enter_chase("hit")

## 进入追击；group = 同组全部追击；allow_link = 是否对 link_radius 内别组的巡逻怪做一次联动判定
func enter_chase(reason: String, allow_link := true) -> void:
	if in_combat() or e.state == EnemyBase.S.DEAD:
		return
	last_reason = reason
	sleeping = false
	lost_t = 0.0
	seen_t = 0.0
	e._go(EnemyBase.S.CHASE)
	var gid: String = e.get_meta("group", "")
	var mates: Array = []
	if gid != "" and floor_node and floor_node.has_method("enemies_in_group"):
		mates = floor_node.enemies_in_group(gid)
		for m in mates:
			if m != e and m.ai and not m.ai.in_combat():
				m.ai.enter_chase("group", allow_link)
	if not allow_link:
		return
	for o in e.get_tree().get_nodes_in_group("enemies"):
		if o == e or o.ai == null or mates.has(o) or o.ai.link_rolled:
			continue
		if not (o.state == EnemyBase.S.PATROL or o.state == EnemyBase.S.ALERT):
			continue
		if o.global_position.distance_to(e.global_position) > R.link_radius:
			continue
		o.ai.link_rolled = true
		var roll: float = director.rng.randf() if director else o.ai.rng.randf()
		if roll < R.link_chance:
			o.ai.enter_chase("link", false)

## 追击中每帧调用：脱离判定。返回 true = 已转回归
func chase_check(delta: float) -> bool:
	var p := target_pos()
	if p == Vector2.INF:
		return false
	var reason := ""
	var self_d := e.global_position.distance_to(e.home_pos)
	if p.distance_to(e.home_pos) > R.leash_px:
		reason = "leash"
	elif self_d > R.leash_hard_px:
		reason = "leash_hard"
	elif self_d > R.enemy_leash_px:
		reason = "leash_self"
	elif _player_in_no_go():
		reason = "guard_zone"
	else:
		if _sight_tick(delta):
			if p.distance_to(e.global_position) <= sight_range() and has_los(p):
				lost_t = 0.0
			else:
				lost_t += R.sight_interval
		if lost_t >= R.lose_sight_sec - 0.001:
			reason = "lost_sight"
	if reason == "":
		return false
	start_return(reason)
	return true

func start_return(reason: String) -> void:
	last_reason = reason
	release()
	e.hitbox.end()
	e.warn.visible = false
	e.aim_line.visible = false
	e.body.color = e.tint
	_regen_acc = 0.0
	e._go(EnemyBase.S.RETURN)

func tick_return(delta: float) -> void:
	_regen_acc += e.max_hp * R.return_regen * delta
	if _regen_acc >= 1.0:
		var n := int(_regen_acc)
		_regen_acc -= n
		e.hp = mini(e.max_hp, e.hp + n)
	if e.global_position.distance_to(e.home_pos) <= R.home_arrive_px:
		e.velocity = Vector2.ZERO
		reaggro_at = clock + R.reaggro_cd
		link_rolled = false
		route_i = _nearest_route_i()
		e._go(EnemyBase.S.PATROL)
		return
	_move_to(e.home_pos, delta, 1.0, 0.0)

func _nearest_route_i() -> int:
	var best := 0
	for i in route.size():
		if route[i].distance_to(e.global_position) < route[best].distance_to(e.global_position):
			best = i
	return best

## 追击名额：拿不到就在外圈包围待机（返回 true = 本帧已处理移动）
func chase_wait(delta: float) -> bool:
	if director == null:
		return false
	has_slot = director.request_chase_slot(e)
	if has_slot:
		return false
	var p := target_pos()
	if p == Vector2.INF:
		return true
	var away := e.global_position - p
	if away.length() < 1.0:
		away = Vector2.RIGHT
	var goal := p + away.normalized().rotated(orbit_dir * 0.5) * R.orbit_px
	e.facing = (p - e.global_position).normalized()
	_move_to(goal, delta, 0.8, 10.0)
	return true

func request_attack() -> bool:
	return director == null or director.request_attack_token(e)

func end_attack() -> void:
	if director:
		director.release_attack_token(e)

func release() -> void:
	has_slot = false
	if director:
		director.release_chase_slot(e)
