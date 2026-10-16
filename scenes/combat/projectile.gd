class_name Projectile
extends Node2D
## 直线单发弹：撞墙（物理层 1 射线检测）、命中或被普攻打中时消失

var team := "enemy"
var velocity := Vector2.ZERO
var damage := 5
var radius := 10.0
var life := 4.0
var source_name := ""
var source: Node
const WALL_MASK := 16 ## 挡子弹的物理层（楼层里水、断崖不在这一层，见 MapGen.OPAQUE_LAYER）
var hit_wall := false ## 测试：因撞墙消失

func _ready() -> void:
	add_to_group("projectiles")

func _physics_process(delta: float) -> void:
	var _p := Prof.t0()
	_prof_physics_process(delta)
	Prof.add("projectile", _p)

func _prof_physics_process(delta: float) -> void:
	var prev := global_position
	position += velocity * delta
	life -= delta
	if life <= 0.0:
		destroy()
		return
	var q := PhysicsRayQueryParameters2D.create(prev, global_position, WALL_MASK)
	if not get_world_2d().direct_space_state.intersect_ray(q).is_empty():
		hit_wall = true
		destroy()
		return
	var other := "player" if team == "enemy" else "enemy"
	for hb in get_tree().get_nodes_in_group("hurtbox_" + other):
		if is_instance_valid(hb) and is_instance_valid(hb.owner_actor) and hb.overlaps_circle(global_position, radius):
			hb.owner_actor.take_hit(damage, self, velocity.normalized() * 60.0)
			destroy() ## 冲刺无敌时也会被“吃掉”，避免同一发反复判定
			return
	queue_redraw()

func destroy() -> void:
	if not is_queued_for_deletion():
		queue_free()

func _draw() -> void:
	draw_circle(Vector2.ZERO, radius, Color(0.75, 1, 0.35))
