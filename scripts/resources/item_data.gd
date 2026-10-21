class_name ItemData
extends Resource
## 物品定义（data/items/*.tres）。category: material / rare_material / shard / equipment / key_item / consumable / boon

@export var id := ""
@export var display_name := ""
@export var category := "material"
@export var quality := "" ## 空则按类别：材料苔绿、稀有紫、碎片青、关键道具金
@export var color := Color(0.6, 0.9, 0.5)
@export var stat_mods: Dictionary = {} ## 装备效果
