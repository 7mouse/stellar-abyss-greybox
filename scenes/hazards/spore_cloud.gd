class_name SporeCloud
extends Node2D
## 孢子云：存在 sec 秒，里面的主角和敌人移速 −slow_pct（敌我都受影响）

var radius := 130.0
var sec := 2.0
var slow_pct := 0.3
var age := 0.0

static func make(pos: Vector2, hd: HazardData, p_sec := 0.0) -> SporeCloud:
	var c := SporeCloud.new()
	c.position = pos
	c.radius = hd.effect_radius
	c.sec = p_sec if p_sec > 0.0 else hd.effect_sec
	c.slow_pct = hd.slow_pct
	c.add_to_group("spore_clouds")
	c.z_index = 1
	return c

func _physics_process(delta: float) -> void:
	age += delta
	if age >= sec:
		queue_free()
		return
	var p := get_tree().get_first_node_in_group("player")
	var list: Array = get_tree().get_nodes_in_group("enemies")
	if p: list.append(p)
	for a in list:
		if is_instance_valid(a) and a.global_position.distance_to(global_position) <= radius and a.has_method("apply_hazard_slow"):
			a.apply_hazard_slow(slow_pct, 0.15)
	queue_redraw()

func _draw() -> void:
	draw_circle(Vector2.ZERO, radius, Color(0.75, 0.85, 0.35, 0.28 * (1.0 - age / sec) + 0.08))
