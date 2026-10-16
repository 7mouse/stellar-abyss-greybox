class_name FloorData
extends Resource
## 楼层参数（data/floors/floor_n.tres）

@export var depth := 1
@export var combat_rooms_min := 3
@export var combat_rooms_max := 4
@export var side_rooms_min := 1
@export var side_rooms_max := 2
@export var waves := 2
@export var wave_size_min := 3
@export var wave_size_max := 5
@export var wave_delay := 2.0
## 出现权重：mushling,rootshot,shellbug
@export var enemy_mix := "mushling:0.45,rootshot:0.35,shellbug:0.20"
@export var floor_hp_scale := 1.25
@export var floor_dmg_scale := 1.12
@export var enemy_dmg_mult := 1.0 ## 本层普通怪（含召唤物）伤害倍率，乘在楼层成长上；层守不受此倍率
@export var guard: GuardData
@export var campfire_heal := 0.3
@export var boon_rooms := true ## 第 1 个和最后 1 个战斗房给 3 选 1
@export var chest_loot: LootTable
@export var side_boon_chance := 0.5 ## 支路是强化房的概率（否则宝箱房）

func mix() -> Dictionary:
	var d := {}
	for part in enemy_mix.split(","):
		var kv := part.split(":")
		if kv.size() == 2:
			d[kv[0].strip_edges()] = float(kv[1])
	return d

func hp_scale() -> float:
	return pow(floor_hp_scale, depth - 1)

func dmg_scale() -> float:
	return enemy_dmg_mult * pow(floor_dmg_scale, depth - 1)

@export_group("开放地图")
## 以上 combat_rooms_* / side_rooms_* / waves / wave_* / boon_rooms / side_boon_chance 为房间制旧字段：保留但开放地图不再读取
@export var chunk_px := 1024.0 ## 区块边长
@export var grid_w := 6
@export var grid_h := 5
@export var map_border_px := 160.0 ## 外圈实心墙厚度
@export var loop_chance := 0.35 ## 生成树之外相邻区块额外打通的概率
@export var gap_px := 480.0 ## 区块之间开口宽度
@export var min_start_guard_dist := 5 ## 起点 → 层守区最短区块路
@export var camps := 2
@export var shrines := 1
@export var chests := 3
@export var resource_nodes := 6
@export var patrol_chance := 0.65 ## 每个普通区块出现巡逻组的概率
@export var patrol_size_min := 2
@export var patrol_size_max := 4
@export var camp_size_min := 4
@export var camp_size_max := 6
@export var node_loot: LootTable ## 资源点（萤苔丛）掉落
@export var aggro_override: AggroRules ## 本层仇恨参数覆盖（M1 只留字段）
