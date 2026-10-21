class_name SporePod
extends Hazard
## 孢子囊：被打或被踩会爆出孢子云（2 秒内减速 30%，敌我都受影响），爆开时产生 300px 声音。一次性

func _tick(_delta: float) -> void:
	var p := player()
	# 被打：主角攻击框扇形碰到囊
	if p and p.hitbox.active:
		var hb: Hitbox = p.hitbox
		var d := global_position - hb.global_position
		if d.length() <= hb.radius + hd.radius and (hb.arc_deg >= 360.0 or absf(rad_to_deg(hb.dir.angle_to(d))) <= hb.arc_deg / 2.0 + 10.0):
			burst()
			return
	# 被踩：任何角色走上去
	if not actors_within(hd.radius).is_empty():
		burst()

## 爆开（也给测试和层主场地用）
func burst() -> void:
	if spent:
		return
	Audio.sfx("SFX-23")
	get_parent().add_child(SporeCloud.make(global_position, hd))
	if hd.noise_px > 0.0:
		NoiseBus.emit(global_position, hd.noise_px, "spore")
	_rearm()

func _draw() -> void:
	draw_circle(Vector2.ZERO, hd.radius, hd.color)
	draw_circle(Vector2.ZERO, hd.radius * 0.5, hd.color.lightened(0.3))
