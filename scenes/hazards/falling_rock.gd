class_name FallingRock
extends Hazard
## 落石：主角走进 trigger_px 内后地面出现裂纹，预兆 1.2 秒后砸下，半径内所有角色受 14 伤害；砸中层主时 ×lord_dmg_mult

var last_hits: Array = []

func _tick(delta: float) -> void:
	if t < 0.0:
		var p := player()
		if cd <= 0.0 and p and p.global_position.distance_to(global_position) <= hd.trigger_px:
			t = 0.0
		return
	t += delta
	if t >= hd.warn_sec:
		smash()

func smash() -> void:
	last_hits.clear()
	for a in actors_within(hd.effect_radius):
		var dmg := hd.damage
		if a is Guard:
			dmg = roundi(dmg * hd.lord_dmg_mult)
		var kb: Vector2 = (a.global_position - global_position).normalized() * 120.0
		if a.take_hit(dmg, self, kb):
			last_hits.append([a, dmg])
	NoiseBus.emit(global_position, 300.0, "rock")
	_rearm()

func _draw() -> void:
	if t >= 0.0:
		var k := t / hd.warn_sec
		draw_circle(Vector2.ZERO, hd.effect_radius, Color(0.9, 0.3, 0.2, 0.15 + 0.35 * k))
		for i in 5:
			var a := i * TAU / 5.0 + 0.3
			draw_line(Vector2.ZERO, Vector2.from_angle(a) * hd.effect_radius * k, Color(0.1, 0.08, 0.06), 3.0)
	else:
		draw_arc(Vector2.ZERO, hd.effect_radius, 0, TAU, 24, Color(hd.color, 0.35 if cd <= 0.0 else 0.12), 2.0)
