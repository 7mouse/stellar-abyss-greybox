class_name Guard
extends EnemyBase
## 层守 = 敌人模板 × 词缀 × 配色。词缀：狂暴（攻速 +30%）、召唤（每 10 秒 2 只菌菇小鬼）、硬壳（poise +100%，背后受伤 ×1.5）
## 二阶段：HP 降到 phase2_hp_ratio 时 1 秒演出（无敌），之后加 phase2_affix

signal phase2_started
signal summon_requested(enemy_id: String, count: int)

var gdata: GuardData
var active_affixes: Array = []
var summon_t := 0.0
var phase := 1
var phase2_t := -1.0

func setup_guard(gd: GuardData, p_depth: int) -> void:
	gdata = gd
	setup(gd.base_enemy, p_depth)
	max_hp = roundi(gd.base_enemy.max_hp * gd.hp_mult)
	hp = max_hp
	damage = roundi(gd.base_enemy.damage * gd.dmg_mult)
	windup = gd.base_enemy.windup * gd.windup_mult
	size = gd.base_enemy.size * gd.scale
	tint = gd.color
	set_affixes(gd.affixes.duplicate())

func set_affixes(list: Array) -> void:
	active_affixes = list
	poise = gdata.base_enemy.poise
	back_mult = 1.0
	for a in active_affixes:
		poise *= 1.0 + a.poise_pct
		back_mult = maxf(back_mult, a.back_damage_mult)
	attack_interval = gdata.attack_interval

func has_affix(id: String) -> bool:
	return active_affixes.any(func(a): return a.id == id)

func effective_interval() -> float:
	var sp := 0.0
	for a in active_affixes:
		sp += a.attack_speed_pct
	return attack_interval / (1.0 + sp)

func _ready() -> void:
	super._ready()
	hitbox.source_name = gdata.display_name
	warn.add_theme_font_size_override("font_size", 72)  # 层守预兆“!”加大
	add_to_group("guards")

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
	for a in active_affixes:
		if a.summon_every > 0.0 and phase2_t < 0.0:
			summon_t += delta
			if summon_t >= a.summon_every * gdata.summon_every_mult:
				summon_t = 0.0
				summon_requested.emit(a.summon_enemy, gdata.summon_count_override if gdata.summon_count_override > 0 else a.summon_count)

func _physics_process(delta: float) -> void:
	if phase2_t >= 0.0:
		state_t += delta
		_tick_extra(delta)
		return
	super._physics_process(delta)

func take_hit(dmg: int, src: Node, knockback: Vector2) -> bool:
	var ok := super.take_hit(dmg, src, knockback)
	if ok and state != S.DEAD and phase == 1 and gdata.phase2_hp_ratio > 0.0 and hp <= max_hp * gdata.phase2_hp_ratio:
		phase = 2
		phase2_t = 0.0
		invulnerable = true
		hitbox.end()
		warn.visible = false
		aim_line.visible = false
		body.color = tint
		_go(S.RECOVER)
		phase2_started.emit()
	return ok

func roll_loot(rare_mult := 1.0) -> Array[ItemStack]:
	return gdata.loot_table.roll(Game.rng, rare_mult) if gdata.loot_table else []

func xp_value() -> int:
	return gdata.xp
