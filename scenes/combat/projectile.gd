class_name Projectile
extends Node2D
## 直线单发弹：撞墙、命中或被普攻打中时消失

var team := "enemy"
var velocity := Vector2.ZERO
var damage := 5
var radius := 10.0
var life := 4.0
var source_name := ""
var source: Node
var walls: Array = [] ## Rect2

func _ready() -> void:
	add_to_group("projectiles")

func _physics_process(delta: float) -> void:
	position += velocity * delta
	life -= delta
	if life <= 0.0:
		destroy()
		return
	for w in walls:
		if w.has_point(global_position):
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
