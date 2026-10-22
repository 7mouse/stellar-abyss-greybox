extends Node
## 声音广播（规格 2.3）：NoiseBus.emit(pos, radius, kind)。按距离筛选 enemies 组里带 EnemyAI 的敌人。
## rules 由楼层设置（radius_of 用它查各类声音半径）；noise 信号给调试层画声音圈。

signal noise(pos: Vector2, radius: float, kind: String)

var rules: AggroRules
var wall_rect := Rect2() ## 层主区围墙：声音不穿墙（一边在里面、一边在外面就听不到）
var _last := {} ## kind -> 上次广播时间（战斗声音节流）
var clock := 0.0 ## 游戏时间（随 time_scale）

func _physics_process(delta: float) -> void:
	clock += delta

func radius_of(kind: String) -> float:
	if rules == null:
		return 0.0
	match kind:
		"dash": return rules.noise_dash
		"combat": return rules.noise_combat
		"death": return rules.noise_death
		"chest": return rules.noise_chest
	return 0.0

## 按种类广播（半径取当前楼层 rules）；combat 每 noise_combat_interval 秒最多一次
func emit_kind(pos: Vector2, kind: String) -> void:
	if rules == null:
		return
	if kind == "combat":
		var now := clock
		var t: float = _last.get(kind, -999.0)
		if now - t < rules.noise_combat_interval:
			return
		_last[kind] = now
	emit(pos, radius_of(kind), kind)

func emit(pos: Vector2, radius: float, kind: String) -> void:
	noise.emit(pos, radius, kind)
	if not is_inside_tree():
		return
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.ai and e.global_position.distance_to(pos) <= radius and wall_rect.has_point(e.global_position) == wall_rect.has_point(pos):
			e.ai.hear(pos, radius, kind)

func reset() -> void:
	_last.clear()
