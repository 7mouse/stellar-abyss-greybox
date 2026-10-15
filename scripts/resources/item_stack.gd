class_name ItemStack
extends RefCounted
## 一叠物品

var item: ItemData
var count := 1

func _init(p_item: ItemData = null, p_count := 1) -> void:
	item = p_item
	count = p_count

func to_dict() -> Dictionary:
	return {"id": item.id, "count": count}
