extends MinigameBase
## T5 第 2 组 2D 追逐躲球：方向键/摇杆移动，追踪球朝角色转向追击，持续 chase_duration 秒。
## 0 次命中 PERFECT，1 次 GOOD，2 次以上 FAIL。

var cfg: ChaseConfig
var arena_origin := Vector2.ZERO
var player_pos := Vector2.ZERO
var balls: Array = [] ## {pos, vel}
var hits := 0
var invuln := 0.0
var t := 0.0
var rng := RandomNumberGenerator.new()
var player_rect: ColorRect
var ball_rects: Array = []
var status: Label
var drive: Callable = Callable() ## 测试用：替代玩家输入，func(minigame) -> Vector2

func _begin() -> void:
	cfg = config as ChaseConfig
	var d := eff_depth()
	if context.has("seed"):
		rng.seed = int(context.seed)
	else:
		rng.randomize()
	var vs := get_viewport_rect().size
	var a := cfg.arena_size
	arena_origin = Vector2(vs.x / 2 - a / 2, vs.y / 2 - a / 2 + 30)
	UI.rect(self, Vector2.ZERO, vs, Color(0, 0, 0, 0.6))
	UI.label(self, "%s —— 方向键/摇杆移动，躲开追踪球！" % config.display_name, Vector2(arena_origin.x - 60, arena_origin.y - 80), 32)
	UI.rect(self, arena_origin, Vector2(a, a), Color(0.18, 0.2, 0.24))
	player_pos = Vector2(a / 2, a / 2)
	var speed := cfg.speed_at(d) / float(context.get("window_mult", 1.0)) ## 升级：球速降低，等效判定窗口 +10%/级
	for i in cfg.balls_at(d):
		var corner := Vector2(rng.randf_range(0.0, 1.0) * a, 0.0 if i % 2 == 0 else a)
		var dir := (player_pos - corner).normalized().rotated(rng.randf_range(-0.6, 0.6))
		balls.append({"pos": corner, "vel": dir * speed})
		ball_rects.append(UI.rect(self, Vector2.ZERO, Vector2.ONE * cfg.ball_radius * 2, Color(0.9, 0.3, 0.3)))
	player_rect = UI.rect(self, Vector2.ZERO, Vector2.ONE * cfg.player_radius * 2, Color(0.3, 0.6, 1.0))
	status = UI.label(self, "", Vector2(arena_origin.x, arena_origin.y + a + 10), 28)
	_sync()

func _tick(delta: float) -> void:
	var move := Vector2.ZERO
	if drive.is_valid():
		move = drive.call(self)
	else:
		move = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	step(delta, move)
	_sync()

## 物理推进一步（可被测试直接调用）
func step(delta: float, move: Vector2) -> void:
	t += delta
	var a := cfg.arena_size
	var pr := cfg.player_radius
	player_pos += move.limit_length(1.0) * cfg.player_speed * delta
	player_pos = player_pos.clamp(Vector2(pr, pr), Vector2(a - pr, a - pr))
	invuln = maxf(0.0, invuln - delta)
	for b in balls:
		var want: float = (player_pos - b.pos).angle()
		var cur: float = b.vel.angle()
		var diff := wrapf(want - cur, -PI, PI)
		var turn := clampf(diff, -cfg.turn_rate * delta, cfg.turn_rate * delta)
		b.vel = b.vel.rotated(turn)
		b.pos += b.vel * delta
		# 撞墙反弹，避免卡在场外
		if b.pos.x < 0 or b.pos.x > a:
			b.vel.x = -b.vel.x
			b.pos.x = clampf(b.pos.x, 0, a)
		if b.pos.y < 0 or b.pos.y > a:
			b.vel.y = -b.vel.y
			b.pos.y = clampf(b.pos.y, 0, a)
		if invuln <= 0.0 and b.pos.distance_to(player_pos) < pr + cfg.ball_radius:
			hits += 1
			invuln = cfg.hit_invuln
			# 命中后把球弹开
			b.vel = (b.pos - player_pos).normalized() * b.vel.length()
	if t >= cfg.chase_duration:
		var r := Result.PERFECT if hits == 0 else (Result.GOOD if hits == 1 else Result.FAIL)
		_finish(r, clampf(1.0 - hits * 0.4, 0.0, 1.0))

func _sync() -> void:
	if not player_rect:
		return
	player_rect.position = arena_origin + player_pos - Vector2.ONE * cfg.player_radius
	player_rect.modulate.a = 0.4 if invuln > 0 else 1.0
	for i in balls.size():
		ball_rects[i].position = arena_origin + balls[i].pos - Vector2.ONE * cfg.ball_radius
	status.text = "剩余 %.1f 秒    被击中 %d 次" % [maxf(0.0, cfg.chase_duration - t), hits]

func _on_timeout() -> void:
	pass ## 由 chase_duration 结束
