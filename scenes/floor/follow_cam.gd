class_name FollowCam
extends Camera2D
## 俯视镜头：跟随目标，平滑 smooth_sec 秒。shake(px, ms) 在 ms 毫秒内线性衰减。

var target: Node2D
var smooth_sec := 0.15
var _amp := 0.0
var _left := 0.0
var _dur := 0.001
var _rng := RandomNumberGenerator.new() ## 不碰全局 randf，避免震动帧数改变敌人冷却
var limit_rect := Rect2() ## 非空时，画面停在这块矩形里

func _ready() -> void:
	_rng.seed = 1
	process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	# 主角占位高 Art.HERO_WORLD_H，放大到视口高度的 1/8。不改移动和碰撞。
	var z := (1080.0 / 8.0) / Art.HERO_WORLD_H
	zoom = Vector2(z, z)

func snap() -> void:
	if target:
		global_position = target.global_position

## px 是满幅度，ms 是衰减到 0 的时长。震动设置为 0 时不产生偏移。
func shake(px: float, ms: float = -1.0) -> void:
	var mul := Settings.shake_mul() if Settings else 1.0
	var amp := maxf(0.0, px) * mul
	var dur := ms / 1000.0 if ms >= 0.0 else 0.0
	if amp <= 0.0 or dur <= 0.0:
		return
	if amp >= _amp - 0.01:
		_amp = amp
		_dur = dur
		_left = dur

func shake_ratio() -> float:
	if _amp <= 0.0 or _left <= 0.0:
		return 0.0
	return clampf(_left / maxf(0.001, _dur), 0.0, 1.0)

func _physics_process(delta: float) -> void:
	if target and is_instance_valid(target):
		var k := 1.0 - exp(-delta / maxf(0.001, smooth_sec / 3.0))
		global_position = global_position.lerp(target.global_position, k)
	if limit_rect.size.x > 1.0 and limit_rect.size.y > 1.0:
		var half := get_viewport_rect().size / zoom * 0.5
		global_position.x = clampf(global_position.x, limit_rect.position.x + half.x, limit_rect.end.x - half.x)
		global_position.y = clampf(global_position.y, limit_rect.position.y + half.y, limit_rect.end.y - half.y)
	if Settings and Settings.shake_mul() <= 0.0:
		_amp = 0.0
		_left = 0.0
		offset = Vector2.ZERO
		return
	if _left > 0.0:
		var ratio := clampf(_left / maxf(0.001, _dur), 0.0, 1.0)
		offset = Vector2(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * _amp * ratio
		_left = maxf(0.0, _left - delta)
		if _left <= 0.0:
			_amp = 0.0
			offset = Vector2.ZERO
	else:
		offset = Vector2.ZERO
