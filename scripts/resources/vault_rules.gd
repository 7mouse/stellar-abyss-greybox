class_name VaultRules
extends Resource
## 保险箱规则（data/vault_rules.tres）

@export var base_slots := 4
@export var upgrade_slots_per_level := 2
@export var max_upgrade_level := 3
@export var village_bonus_per_village := 1 ## 灰盒只有一个村，不生效
@export var allowed_categories: PackedStringArray = ["equipment", "rare_material", "key_item"]
## 升到第 1..3 级各花多少萤苔精
@export var upgrade_cost := "2,4,6"

func cost_for(level: int) -> int:
	var c := upgrade_cost.split(",")
	return int(c[clampi(level - 1, 0, c.size() - 1)])

func allows(category: String) -> bool:
	return category in allowed_categories
