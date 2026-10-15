class_name ChaseConfig
extends MinigameConfig
## 第 2 组 2D 追逐躲球

@export var chase_duration: float = 4.0
@export var ball_count: int = 1
@export var balls_per_depth: float = 0.5 ## 每层增加的球（向下取整累计）
@export var ball_count_max: int = 4
@export var ball_speed: float = 260.0 ## 像素/秒
@export var ball_speed_per_depth: float = 20.0
@export var turn_rate: float = 2.2 ## 转向速度（弧度/秒）
@export var player_speed: float = 420.0
@export var arena_size: float = 640.0
@export var player_radius: float = 22.0
@export var ball_radius: float = 18.0
@export var hit_invuln: float = 0.6 ## 被击中后的无敌时间

func balls_at(d: float) -> int:
	return mini(ball_count_max, ball_count + int(floor(maxf(0.0, d - 1.0) * balls_per_depth)))

func speed_at(d: float) -> float:
	return ball_speed + maxf(0.0, d - 1.0) * ball_speed_per_depth
