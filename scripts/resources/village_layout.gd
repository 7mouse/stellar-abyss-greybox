class_name VillageLayout
extends Resource
## 起程村坐标（data/village_layout.tres）。位置是设施中心。

@export var map_w := 2400.0
@export var map_h := 1400.0
@export var plaza_x := 900.0
@export var plaza_y := 500.0
@export var plaza_w := 600.0
@export var plaza_h := 400.0
@export var spawn_x := 1200.0
@export var spawn_y := 700.0
@export var mid_spawn_x := 1200.0
@export var mid_spawn_y := 1360.0
@export var elder_intro_x := 1420.0
@export var elder_intro_y := 1200.0
@export var mid_title := "中途返回 · 第 %d 层"
@export var incubator_block := "这一趟还没结束，不能换人"
@export var bench_block := "这一趟还没结束，不能强化"
@export var epitaph_readonly := "只读"
@export var shop_closed := "补给还没到，先不能买"

@export_group("墓志铭墙")
@export var epitaph_x := 1250.0
@export var epitaph_y := 240.0
@export var epitaph_w := 320.0
@export var epitaph_h := 60.0
@export_group("培养槽")
@export var incubator_x := 1750.0
@export var incubator_y := 260.0
@export var incubator_w := 120.0
@export var incubator_h := 160.0
@export_group("布告栏")
@export var board_x := 380.0
@export var board_y := 560.0
@export var board_w := 120.0
@export var board_h := 80.0
@export_group("老冒险者")
@export var npc_x := 1560.0
@export var npc_y := 620.0
@export var npc_w := 40.0
@export var npc_h := 64.0
@export_group("仓库")
@export var warehouse_x := 520.0
@export var warehouse_y := 900.0
@export var warehouse_w := 160.0
@export var warehouse_h := 100.0
@export_group("保险箱")
@export var vault_x := 760.0
@export var vault_y := 900.0
@export var vault_w := 140.0
@export var vault_h := 100.0
@export_group("强化台")
@export var bench_x := 1560.0
@export var bench_y := 900.0
@export var bench_w := 140.0
@export var bench_h := 90.0
@export_group("合成台")
@export var craft_x := 1860.0
@export var craft_y := 900.0
@export var craft_w := 220.0
@export var craft_h := 90.0
@export_group("补给商店")
@export var shop_x := 1000.0
@export var shop_y := 1000.0
@export var shop_w := 180.0
@export var shop_h := 100.0
@export_group("下潜井口")
@export var well_x := 1200.0
@export var well_y := 1200.0
@export var well_w := 160.0
@export var well_h := 160.0
@export_group("中途")
@export var rest_x := 700.0
@export var rest_y := 1100.0
@export var rest_w := 180.0
@export var rest_h := 90.0
@export var bag_x := 1860.0
@export var bag_y := 1100.0
@export var bag_w := 180.0
@export var bag_h := 90.0
@export var return_x := 1480.0
@export var return_y := 1180.0
@export var return_w := 240.0
@export var return_h := 90.0

func pos_of(id: String) -> Vector2:
	return Vector2(float(get(id + "_x")), float(get(id + "_y")))

func size_of(id: String) -> Vector2:
	return Vector2(float(get(id + "_w")), float(get(id + "_h")))
