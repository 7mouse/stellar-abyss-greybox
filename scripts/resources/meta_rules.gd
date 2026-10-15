class_name MetaRules
extends Resource
## 强化台局外强化（data/meta_rules.tres）

@export var vit_hp_per_level := 10
@export var vit_max_level := 3
@export var vit_cost := "15,25,40"
@export var swift_dash_per_level := 1
@export var swift_max_level := 1
@export var swift_cost := "40"

func cost(list: String, level: int) -> int:
	var c := list.split(",")
	return int(c[clampi(level - 1, 0, c.size() - 1)])
