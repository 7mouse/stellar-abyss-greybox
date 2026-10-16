class_name Hazard
extends Node2D
## 环境机关基类（§8.3）：参数全在 HazardData（data/hazards/*.tres）。子类见 spore_pod / root_snare / falling_rock

signal fired(h: Hazard)

var hd: HazardData
var in_arena := false ## 层主场地里的机关
var t := -1.0 ## 预兆 / 效果计时；-1 = 待机
var cd := 0.0 ## 重新就绪倒计时
var spent := false ## 一次性机关已用掉
var fire_count := 0
var source_name := "" ## 给 take_hit 记录伤害来源
var slow_sec := 0.0 ## take_hit 会读这个字段；机关的减速走 apply_hazard_slow

func setup(d: HazardData, pos: Vector2, arena := false) -> Hazard:
	hd = d
	position = pos
	in_arena = arena
	source_name = d.display_name
	add_to_group("hazards")
	z_index = -1
	return self

func player() -> Node2D:
	return get_tree().get_first_node_in_group("player") if is_inside_tree() else null

## 主角和所有活着的敌人（含层主）
func actors() -> Array:
	var out: Array = []
	var p := player()
	if p and int(p.get("hp")) > 0:
		out.append(p)
	for e in get_tree().get_nodes_in_group("enemies"):
		if is_instance_valid(e) and e.state != EnemyBase.S.DEAD:
			out.append(e)
	return out

func actors_within(r: float) -> Array:
	return actors().filter(func(a): return a.global_position.distance_to(global_position) <= r)

func _physics_process(delta: float) -> void:
	if spent:
		return
	if cd > 0.0:
		cd = maxf(0.0, cd - delta)
	_tick(delta)
	queue_redraw()

func _tick(_delta: float) -> void:
	pass

func _rearm() -> void:
	fire_count += 1
	fired.emit(self)
	t = -1.0
	if hd.rearm_sec > 0.0:
		cd = hd.rearm_sec
	else:
		spent = true
		visible = false
