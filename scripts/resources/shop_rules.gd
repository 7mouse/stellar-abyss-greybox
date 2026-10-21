class_name ShopRules
extends Resource
## 补给商店。回血药放在 HUD 左下消耗品格，限购按局计。

@export var potion_heal_pct := 0.4
@export var potion_price := 30
@export var potion_limit_per_run := 2
@export var potion_name := "回血药"
@export var reason_shards := "碎片不够"
@export var reason_limit := "这局已经买满"
