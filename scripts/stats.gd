class_name Stats
extends RefCounted
## 属性修正汇总：等级、强化、遗志（×legacy_power）、特质/缺陷、局外强化、装备

const KEYS := ["max_hp_add", "atk_pct", "light_pct", "finisher_pct", "dash_charges_add", "dash_recharge_pct", "dash_dist_pct",
	"skill_cd_pct", "kill_heal", "skill_slow_sec", "afterimage_dmg", "move_pct", "rare_drop_pct", "telegraph_delay", "move_pct_floor3"]
## 整数型的键：遗志削弱后仍至少 +1（否则“疾风”这类遗志会失效）
const INT_KEYS := ["dash_charges_add"]

const TRAITS := {
	"agile": {"name": "灵巧", "desc": "冲刺冷却 −15%", "mods": {"dash_recharge_pct": -0.15}},
	"sturdy": {"name": "壮硕", "desc": "HP +15", "mods": {"max_hp_add": 15}},
	"zeal": {"name": "狂热", "desc": "攻击 +8%", "mods": {"atk_pct": 0.08}},
	"lucky": {"name": "幸运", "desc": "稀有掉落 +25%", "mods": {"rare_drop_pct": 0.25}},
}
const FLAWS := {
	"myopic": {"name": "近视", "desc": "敌人预兆图标延迟 0.1 秒出现", "mods": {"telegraph_delay": 0.1}},
	"clumsy": {"name": "笨拙", "desc": "冲刺距离 −10%", "mods": {"dash_dist_pct": -0.1}},
	"frail": {"name": "虚弱", "desc": "HP −10", "mods": {"max_hp_add": -10}},
	"acrophobe": {"name": "恐高", "desc": "第 3 层移速 −10%", "mods": {"move_pct_floor3": -0.1}},
}

static func empty() -> Dictionary:
	var d := {}
	for k in KEYS:
		d[k] = 0.0
	return d

static func add(into: Dictionary, mods: Dictionary, power := 1.0) -> void:
	for k in mods:
		var v := float(mods[k]) * power
		if k in INT_KEYS and power < 1.0 and float(mods[k]) >= 1.0:
			v = maxf(1.0, roundf(v))
		into[k] = float(into.get(k, 0.0)) + v

## 当前个体 + 本局的全部修正
static func collect(run: Run) -> Dictionary:
	var d := empty()
	var lin = Engine.get_main_loop().root.get_node("Lineage")
	var ind: Dictionary = lin.current()
	if TRAITS.has(ind.get("trait", "")):
		add(d, TRAITS[ind.trait].mods)
	if FLAWS.has(ind.get("flaw", "")):
		add(d, FLAWS[ind.flaw].mods)
	var lp: float = lin.legacy_rules.legacy_power
	for bid in ind.get("legacies", []):
		var b: BoonData = Boons.get_boon(bid)
		if b:
			add(d, b.stat_mods, lp)
	add(d, {"max_hp_add": lin.upgrades.get("vit", 0) * lin.meta_rules.vit_hp_per_level, "dash_charges_add": lin.upgrades.get("swift", 0) * lin.meta_rules.swift_dash_per_level})
	if run:
		for b in run.boons:
			add(d, b.stat_mods)
		for st in run.equipped:
			add(d, st.item.stat_mods)
		if run.depth == 3:
			d.move_pct += d.move_pct_floor3
	return d
