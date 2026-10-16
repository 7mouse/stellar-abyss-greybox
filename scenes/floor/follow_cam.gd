class_name FollowCam
extends Camera2D
## 俯视镜头：跟随目标，平滑 smooth_sec 秒；shake(px) 震屏

var target: Node2D
var smooth_sec := 0.15
var _shake := 0.0
var limit_rect := Rect2() ## 非空时，画面停在这块矩形里

func _ready() -> void:
	process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	# 主角占位高 Art.HERO_WORLD_H，放大到视口高度的 1/8。不改移动和碰撞。
	var z := (1080.0 / 8.0) / Art.HERO_WORLD_H
	zoom = Vector2(z, z)

func snap() -> void:
	if target:
		global_position = target.global_position

func shake(px: float) -> void:
	_shake = maxf(_shake, px)

func _physics_process(delta: float) -> void:
	if target and is_instance_valid(target):
		var k := 1.0 - exp(-delta / maxf(0.001, smooth_sec / 3.0))
		global_position = global_position.lerp(target.global_position, k)
	if limit_rect.size.x > 1.0 and limit_rect.size.y > 1.0:
		var half := get_viewport_rect().size / zoom * 0.5
		global_position.x = clampf(global_position.x, limit_rect.position.x + half.x, limit_rect.end.x - half.x)
		global_position.y = clampf(global_position.y, limit_rect.position.y + half.y, limit_rect.end.y - half.y)
	offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * _shake
	_shake = move_toward(_shake, 0.0, 40.0 * delta)
