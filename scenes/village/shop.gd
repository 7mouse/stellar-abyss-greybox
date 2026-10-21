extends Panel2
## 补给商店：回血药。碎片不够或达到本局限购时按钮灰掉，并写原因。

func _init() -> void:
	title = "补给商店"

func _fill() -> void:
	var rules := Game.shop_rules()
	var shards := Game.run.shards_carried if Game.run else 0
	var own := Game.run.potions if Game.run else 0
	var bought := Game.run.potions_bought if Game.run else 0
	text("身上碎片 %d。%s %d 碎片一瓶，这局 %d/%d，身上 %d 瓶。" % [shards, rules.potion_name, rules.potion_price, bought, rules.potion_limit_per_run, own], 22, Color(0.9, 0.88, 0.8))
	text("喝下去回复最大生命的 %.0f%%。" % (rules.potion_heal_pct * 100.0), 22, Color(0.75, 0.9, 0.7))
	var why := Game.potion_block_reason()
	var b := btn("购买" + rules.potion_name, _buy, why == "")
	b.name = "buy_potion"
	if why != "":
		var reason := text(why, 22, Color(1, 0.65, 0.55))
		reason.name = "shop_reason"

func _buy() -> void:
	if Game.buy_potion():
		var v := get_parent()
		if v and v.has_method("show_toast"):
			v.show_toast("买到了" + Game.shop_rules().potion_name)
	rebuild()
