class_name FollowCam
extends Camera2D
## 俯视镜头：跟随目标，平滑 smooth_sec 秒；shake(px) 震屏

var target: Node2D
var smooth_sec := 0.15
var _shake := 0.0

func _ready() -> void:
	process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS

func snap() -> void:
	if target:
		global_position = target.global_position

func shake(px: float) -> void:
	_shake = maxf(_shake, px)

func _physics_process(delta: float) -> void:
	if target and is_instance_valid(target):
		var k := 1.0 - exp(-delta / maxf(0.001, smooth_sec / 3.0))
		global_position = global_position.lerp(target.global_position, k)
	offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * _shake
	_shake = move_toward(_shake, 0.0, 40.0 * delta)
