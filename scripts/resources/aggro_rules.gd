class_name AggroRules
extends Resource
## 仇恨参数（data/aggro_rules.tres）。M1 临时规则：主角进入 chase_radius 就追，敌人离出生点超过 leash_px 就走回出生点。
## 正式的视野锥 / 声音 / 联动 / 回归状态机在 M2（EnemyAI）。

@export var chase_radius := 600.0 ## 主角进入这个距离就开始追
@export var leash_px := 1100.0 ## 敌人离出生点超过这个距离就走回出生点
@export var home_arrive_px := 24.0 ## 回到出生点的判定距离

func effective(override: AggroRules) -> AggroRules:
	return override if override else self
