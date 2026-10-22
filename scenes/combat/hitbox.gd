class_name Hitbox
extends Node2D
## 攻击框：扇形（range, arc_deg）或圆（arc_deg ≥ 360）。active 期间每帧检测对方队伍的 Hurtbox；
## hit_once_per_target = true 时同一段攻击对同一目标只结算 1 次

signal hit_landed(target: Node, dmg: int)

var damage := 10
var knockback := 0.0
var team := "player"
var hit_once_per_target := true
var radius := 90.0
var arc_deg := 120.0
var dir := Vector2.RIGHT
var stagger_sec := 0.0
var slow_sec := 0.0
var source: Node
var source_name := ""
var active := false
var destroys_projectiles := false
var _drawn := false
var hit := {} ## 已结算目标

func begin(p_dmg: int, p_radius: float, p_arc: float, p_dir: Vector2) -> void:
	damage = p_dmg
	radius = p_radius
	arc_deg = p_arc
	dir = p_dir.normalized() if p_dir.length() > 0.01 else Vector2.RIGHT
	hit.clear()
	active = true

func end() -> void:
	active = false

func _physics_process(_d: float) -> void:
	var _p := Prof.t0()
	_prof_physics_process(_d)
	Prof.add("hitbox", _p)

func _prof_physics_process(_d: float) -> void:
	if active:
		check()
	var show := Game.show_boxes and active
	if show or _drawn: ## 性能：只在需要画或刚画过时重画
		_drawn = show
		queue_redraw()

func check() -> void:
	var other := "enemy" if team == "player" else "player"
	for hb in get_tree().get_nodes_in_group("hurtbox_" + other):
		if not is_instance_valid(hb) or not is_instance_valid(hb.owner_actor):
			continue
		if hit_once_per_target and hit.has(hb.owner_actor):
			continue
		if hb.overlaps_sector(global_position, dir, radius, arc_deg):
			hit[hb.owner_actor] = true
			var kb: Vector2 = (hb.global_position - global_position).normalized() * knockback
			if hb.owner_actor.take_hit(damage, self, kb):
				hb.hurt.emit(self)
				hit_landed.emit(hb.owner_actor, damage)
	if destroys_projectiles:
		for p in get_tree().get_nodes_in_group("projectiles"):
			if is_instance_valid(p) and p.team != team:
				var d: Vector2 = p.global_position - global_position
				if d.length() <= radius + p.radius and (arc_deg >= 360.0 or absf(rad_to_deg(dir.angle_to(d))) <= arc_deg / 2.0 + 15.0):
					p.destroy()

func _draw() -> void:
	if Game.show_boxes and active:
		var pts := PackedVector2Array([Vector2.ZERO])
		var a0 := dir.angle() - deg_to_rad(minf(arc_deg, 360.0) / 2.0)
		for i in 17:
			var a := a0 + deg_to_rad(minf(arc_deg, 360.0)) * i / 16.0
			pts.append(Vector2(cos(a), sin(a)) * radius)
		pts.append(Vector2.ZERO)
		draw_polyline(pts, Color(1, 0.3, 0.2), 2.0)
