class_name BoonData
extends Resource
## 局内强化（data/boons/*.tres）。效果写在 stat_mods，特殊效果用 tags 里的 hook 名

@export var id := ""
@export var display_name := ""
@export var desc := ""
@export var rarity := 1
## 例：{"light_pct": 0.2}；键见 Stats.KEYS
@export var stat_mods: Dictionary = {}
@export var tags: PackedStringArray = []
