extends Node
## 命中反馈。数值全部读 HitFeel（F1 改资源立刻作用）。
## 顿帧不叠加，取最大；同一次攻击打中多个目标只记一次。
## 外部入口：play(事件, 目标)。T3 破甲、T4 招式可以调用。

var global_pulses := 0 ## 测试：实际发出的顿帧/震屏次数
var _swing := false
var _swing_pulsed := false
var _swing_hs := 0
var _swing_shake := 0.0
var _beep: AudioStreamPlayer
var _vig: ColorRect
var _vig_mat: ShaderMaterial
var _vig_left := 0.0
var _vig_dur := 1.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_beep = AudioStreamPlayer.new()
	_beep.volume_db = -14.0
	add_child(_beep)
	var layer := CanvasLayer.new()
	layer.layer = 40
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(layer)
	_vig = ColorRect.new()
	_vig.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vig.visible = false
	_vig_mat = ShaderMaterial.new()
	_vig_mat.shader = load("res://shaders/vignette.gdshader")
	_vig.material = _vig_mat
	layer.add_child(_vig)

func _process(delta: float) -> void:
	if _vig_left <= 0.0:
		return
	_vig_left = maxf(0.0, _vig_left - delta)
	_vig_mat.set_shader_parameter("strength", _vig_left / _vig_dur)
	if _vig_left <= 0.0:
		_vig.visible = false

func feel() -> HitFeel:
	return Game.hit_feel

func begin_swing() -> void:
	_swing = true
	_swing_pulsed = false
	_swing_hs = 0
	_swing_shake = 0.0

func end_swing() -> void:
	_swing = false
	_swing_pulsed = false

## 攻击打中一个目标（闪白、击退由调用方处理；这里只记顿帧和震屏）
func note_hit(event: String, target: Node) -> void:
	_note_global(event)
	_flash(target, event)

func play(event: String, target: Node = null) -> void:
	_note_global(event)
	if target != null:
		_flash(target, event)
	if event == "boss_death":
		_player_iframe(event)
		Game.slowmo(feel().boss_death_slowmo_ms / 1000.0, feel().boss_death_slowmo_scale)
	elif event == "kill_elite":
		_player_iframe(event)
	elif event == "boss_phase":
		if target is Node2D:
			_push_player_from(target as Node2D, feel().boss_phase_knockback_px)
		if Settings.shake_mul() <= 0.0:
			pulse_vignette(maxf(0.2, feel().boss_phase_shake_ms / 1000.0))
		if target != null:
			## T4 用这个时长做咆哮无敌。当前层主的 phase2_sec 不在这里改。
			target.set_meta("phase_feel_iframe_ms", feel().boss_phase_iframe_ms)

func on_killed(enemy: Node) -> void:
	var ev := "kill_normal"
	if enemy is Guard:
		ev = "boss_death"
	elif _is_elite(enemy):
		ev = "kill_elite"
	play(ev, enemy)
	if enemy is Node2D:
		_corpse(enemy as Node2D, ev)

func on_boss_phase(guard: Node) -> void:
	play("boss_phase", guard)

func play_player_hurt(player: Node) -> void:
	_note_global("player_hurt")
	_flash(player, "player_hurt", true)

func play_dash() -> void:
	_note_global("dash")

func boss_phase_iframe_sec() -> float:
	return maxf(0.0, feel().boss_phase_iframe_ms / 1000.0)

func iframe_sec(event: String) -> float:
	var ms := feel().iframe_ms(event)
	if ms < 0:
		return -1.0
	return ms / 1000.0

func knockback_px(event: String) -> float:
	return feel().knockback_px(event)

## 普攻 3、技能、以及会削断层主韧性的一下，对层主用 boss_heavy。
func event_for(src: Hitbox, target: Node) -> String:
	var atk: AttackData = null
	var seg := -1
	var skill := false
	if src.source is Player:
		var p := src.source as Player
		atk = p.atk
		skill = p.state == Player.S.SKILL
		if p.state == Player.S.ATTACK:
			seg = p.combo_i
	var heavy := skill or (atk != null and (atk.id in ["skill_sweep", "skill_thrust", "skill_2"] or seg == 2))
	if target is Guard:
		var g := target as Guard
		var breaks: bool = g.poise > 0.0 and (g.poise_acc + float(src.damage) >= g.poise or src.stagger_sec > 0.0)
		if heavy or breaks:
			return "boss_heavy"
	if atk != null and atk.id in ["skill_thrust", "skill_2"]:
		return "skill_2"
	if skill or (atk != null and atk.id == "skill_sweep"):
		return "skill_1"
	if seg < 0:
		return "light_1"
	return ["light_1", "light_2", "light_3"][clampi(seg, 0, 2)]

func vignette_on() -> bool:
	return _vig != null and _vig.visible

func pulse_vignette(sec: float) -> void:
	_vig_dur = maxf(0.05, sec)
	_vig_left = _vig_dur
	_vig.visible = true
	_vig_mat.set_shader_parameter("strength", 1.0)

func _note_global(event: String) -> void:
	var hs := feel().hitstop_ms(event)
	var spx := feel().shake_px(event)
	var sms := feel().shake_ms(event)
	if not Settings.hitstop_enabled:
		hs = 0
	if hs <= 0 and spx <= 0.0:
		_blip(event)
		return
	if _swing:
		var upgrade := not _swing_pulsed or hs > _swing_hs or spx > _swing_shake + 0.01
		_swing_hs = maxi(_swing_hs, hs)
		_swing_shake = maxf(_swing_shake, spx)
		if upgrade:
			_emit_pulse(hs, spx, sms, event)
			if not _swing_pulsed:
				global_pulses += 1
				_swing_pulsed = true
		return
	_emit_pulse(hs, spx, sms, event)
	global_pulses += 1

func _emit_pulse(hs: int, spx: float, sms: int, event: String) -> void:
	if hs > 0:
		Game.hitstop(hs / 1000.0)
	if spx > 0.0 and sms > 0:
		var cam := _camera()
		if cam and cam.has_method("shake"):
			cam.shake(spx, float(sms))
	_blip(event)

func _flash(target: Node, event: String, redwhite := false) -> void:
	if target == null:
		return
	var ms := feel().flash_ms(event)
	if ms <= 0:
		return
	if target.has_method("feel_flash"):
		target.feel_flash(ms, event == "armor_break", redwhite)

func _player_iframe(event: String) -> void:
	var ms := feel().iframe_ms(event)
	if ms <= 0:
		return
	var ps := get_tree().get_nodes_in_group("player")
	if ps.is_empty():
		return
	var p: Player = ps[0]
	p.iframe_left = maxf(p.iframe_left, ms / 1000.0)

func _push_player_from(src: Node2D, px: float) -> void:
	if px <= 0.0:
		return
	var ps := get_tree().get_nodes_in_group("player")
	if ps.is_empty():
		return
	var p: Player = ps[0]
	var dir := p.global_position - src.global_position
	if dir.length() < 1.0:
		dir = Vector2.DOWN
	p.move_and_collide(dir.normalized() * px)

func _corpse(enemy: Node2D, event: String) -> void:
	var px := feel().knockback_px(event)
	if px <= 0.0 or enemy.get_parent() == null:
		return
	var r := ColorRect.new()
	r.size = Vector2(28, 16)
	r.color = Color(0.62, 0.72, 0.48, 0.85)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.z_index = 6
	var parent := enemy.get_parent()
	parent.add_child(r)
	r.global_position = enemy.global_position - r.size * 0.5
	var dir := Vector2.RIGHT
	var ps := get_tree().get_nodes_in_group("player")
	if not ps.is_empty():
		var away: Vector2 = enemy.global_position - (ps[0] as Node2D).global_position
		if away.length() > 1.0:
			dir = away.normalized()
	var tw := parent.create_tween()
	tw.tween_property(r, "position", r.position + dir * px, 0.18)
	tw.parallel().tween_property(r, "modulate:a", 0.0, 0.18)
	tw.tween_callback(r.queue_free)

func _camera() -> Camera2D:
	var vp := get_viewport()
	if vp == null:
		return null
	return vp.get_camera_2d()

func _is_elite(enemy: Node) -> bool:
	return enemy.is_in_group("elites") or bool(enemy.get_meta("elite", false))

func _blip(event: String) -> void:
	if OS.has_feature("headless") or _beep == null:
		return
	var freq := 180.0
	match event:
		"light_3", "boss_heavy": freq = 130.0
		"skill_1", "skill_2": freq = 160.0
		"player_hurt": freq = 90.0
		"kill_normal": freq = 80.0
		"kill_elite", "boss_death": freq = 60.0
		"boss_phase": freq = 55.0
		"armor_break": freq = 280.0
		"dash": freq = 420.0
		_: freq = 210.0
	_beep.stream = Beep.tone(freq, 0.04, 0.35)
	_beep.play()
