class_name ItemStack
extends RefCounted
## 一叠物品。回村符可以带封印：封印的那张本局不能用，存进仓库或保险箱后解开

var item: ItemData
var count := 1
var sealed := false
var source := ""

func _init(p_item: ItemData = null, p_count := 1, p_sealed := false, p_source := "") -> void:
	item = p_item
	count = p_count
	sealed = p_sealed
	source = p_source

func to_dict() -> Dictionary:
	return {"id": item.id, "count": count}
