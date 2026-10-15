extends Panel2
## 强化台：升级保险箱（萤苔精）+ 局外强化（萤苔）

func _init() -> void:
	title = "简易强化台"

func _fill() -> void:
	var vr := Lineage.vault_rules
	var mr := Lineage.meta_rules
	text("萤苔 %d　萤苔精 %d" % [Lineage.mats.moss, Lineage.mats.moss_essence])
	if Lineage.vault_level < vr.max_upgrade_level:
		var c := vr.cost_for(Lineage.vault_level + 1)
		btn("保险箱扩容 Lv%d → Lv%d（+%d 格，花萤苔精 %d）" % [Lineage.vault_level, Lineage.vault_level + 1, vr.upgrade_slots_per_level, c], func(): Lineage.upgrade_vault(); rebuild(), Lineage.mats.moss_essence >= c)
	else:
		btn("保险箱已满级", func(): pass, false)
	var v: int = Lineage.upgrades.vit
	if v < mr.vit_max_level:
		var c2 := mr.cost(mr.vit_cost, v + 1)
		btn("体魄 Lv%d → Lv%d（最大 HP +%d，花萤苔 %d）" % [v, v + 1, mr.vit_hp_per_level, c2], func(): Lineage.buy_upgrade("vit"); rebuild(), Lineage.mats.moss >= c2)
	else:
		btn("体魄已满级", func(): pass, false)
	var s: int = Lineage.upgrades.swift
	if s < mr.swift_max_level:
		var c3 := mr.cost(mr.swift_cost, s + 1)
		btn("迅身 Lv%d → Lv%d（起始冲刺充能 +1，花萤苔 %d）" % [s, s + 1, c3], func(): Lineage.buy_upgrade("swift"); rebuild(), Lineage.mats.moss >= c3)
	else:
		btn("迅身已满级", func(): pass, false)
