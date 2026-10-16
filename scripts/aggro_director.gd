class_name AggroDirector
extends Node
## 追击数上限和攻击令牌（规格 2.6）：同时追击 ≤ max_chasers（多出来的在外圈包围待机），同时前摇 ≤ max_attackers。
## 只管带 EnemyAI 的地图怪；层主和召唤物不占名额。

var rules: AggroRules
var chasers: Array = []
var attackers: Array = []
var chasers_peak := 0
var attackers_peak := 0
var rng := RandomNumberGenerator.new() ## 跨组联动判定（楼层种子）

func _alive(e) -> bool:
	return is_instance_valid(e) and e.state != EnemyBase.S.DEAD and e.ai != null and e.ai.in_combat()

func _prune() -> void:
	chasers = chasers.filter(_alive)
	attackers = attackers.filter(_alive)

func request_chase_slot(e: EnemyBase) -> bool:
	if chasers.has(e):
		return true
	_prune()
	if chasers.size() >= rules.max_chasers:
		return false
	chasers.append(e)
	chasers_peak = maxi(chasers_peak, chasers.size())
	return true

func release_chase_slot(e: EnemyBase) -> void:
	chasers.erase(e)
	attackers.erase(e)

func request_attack_token(e: EnemyBase) -> bool:
	if attackers.has(e):
		return true
	_prune()
	if attackers.size() >= rules.max_attackers:
		return false
	attackers.append(e)
	attackers_peak = maxi(attackers_peak, attackers.size())
	return true

func release_attack_token(e: EnemyBase) -> void:
	attackers.erase(e)

func chasing_count() -> int:
	_prune()
	return chasers.size()

func windup_count() -> int:
	_prune()
	return attackers.size()
