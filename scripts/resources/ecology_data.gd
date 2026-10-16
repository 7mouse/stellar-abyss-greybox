class_name EcologyData
extends Resource
## 生态（规格 §8.1）：一套参数同时决定地表、敌人种群、环境机关和层主。
## 地形生成、刷怪、机关、层主都只读这里（通过 FloorData 的访问函数），不在别处另配。

@export var id := ""
@export var display_name := ""
@export var palette := Color(0.13, 0.2, 0.13) ## 地面染色；层主配色见 lord.color
@export var palette_strength := 0.25
@export var weight := 1.0 ## ecology_pool 抽取权重
@export var biome_bias := 0.0 ## 加到群系噪声 n_bio 上（负 = 林地，正 = 废墟）
@export var water_th := 0.32 ## 水阈值（越高水越少）
@export var cliff_th := 0.25 ## 断崖阈值（越低断崖越多）
@export var density_base := 0.53 ## 元胞初始密度
@export var enemy_mix := "mushling:0.45,rootshot:0.35,shellbug:0.20"
@export var hazards: Array[HazardData] = []
@export var hazard_counts: Array[int] = [] ## 与 hazards 一一对应：每层数量
@export var lord: GuardData ## 层主（GuardData 扩展的 LordData 字段）

func hazard_count(i: int) -> int:
	return hazard_counts[i] if i < hazard_counts.size() else 0
