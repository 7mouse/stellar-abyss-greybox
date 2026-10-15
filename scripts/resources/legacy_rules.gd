class_name LegacyRules
extends Resource
## 遗志继承规则（data/legacy_rules.tres）

@export var level_ratio := 0.30
@export var floor_min := 1
@export var stat_ratio := 0.30 ## 前任靠等级获得的加成按此比例保留（灰盒等价于按等级继承）
@export var legacy_pick_from := 3
@export var legacy_max := 5
@export var legacy_power := 0.5 ## 遗志按强化原效果的 50% 生效
@export var mastery_ratio := 0.5 ## 灰盒只记录
@export var trait_count := 1
@export var flaw_chance := 0.5
@export var shard_loss_ratio := 0.5 ## 身上没带出的碎片死亡丢失比例（向上取整）
@export var corpse_fallback_mats := 3
@export var death_slowmo_sec := 1.0
@export var wake_sec := 2.0
@export var protagonist_name := "林"

func inherit_level(prev_level: int) -> int:
	return maxi(floor_min, floori(prev_level * level_ratio))
