class_name RootSnare
extends Hazard
## 缠根地块：主角踩上后 0.8 秒预兆，预兆结束时还在地块上就被缠住 1.5 秒（移速 −40%）。之后 rearm_sec 秒重新就绪

var caught := false ## 最近一次是否缠住了主角

func _tick(delta: float) -> void:
	var p := player()
	if t < 0.0:
		if cd <= 0.0 and p and p.global_position.distance_to(global_position) <= hd.radius:
			t = 0.0
		return
	t += delta
	if t >= hd.warn_sec:
		caught = false
		if p and p.global_position.distance_to(global_position) <= hd.radius:
			p.apply_hazard_slow(hd.slow_pct, hd.effect_sec)
			caught = true
		_rearm()

func _draw() -> void:
	var c := hd.color
	if t >= 0.0:
		c = c.lerp(Color(0.9, 0.4, 0.2), 0.5 + 0.5 * sin(t * 30.0))
	elif cd > 0.0:
		c.a = 0.4
	draw_circle(Vector2.ZERO, hd.radius, Color(c, 0.55))
	for k in 6:
		var a := k * TAU / 6.0
		draw_line(Vector2.from_angle(a) * 12.0, Vector2.from_angle(a + 0.4) * hd.radius * 0.85, c.darkened(0.3), 4.0)
