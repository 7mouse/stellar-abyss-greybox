"""生成 data/*.tres 默认参数（数值来自 docs/greybox2-numbers.md）。python3 tools/data/gen_data.py"""
import os
R = "res://scripts/resources/"
def val(v):
    if isinstance(v, bool): return "true" if v else "false"
    if isinstance(v, (int, float)): return repr(v)
    if isinstance(v, str):
        if v.startswith("@"): return v[1:]
        return '"' + v.replace('\\', '\\\\').replace('"', '\\"') + '"'
    if isinstance(v, tuple): return "Color(%s)" % ", ".join(str(x) for x in v)
    if isinstance(v, dict): return "{" + ", ".join(f'"{k}": {val(x)}' for k, x in v.items()) + "}"
    if isinstance(v, list): return "[" + ", ".join(val(x) for x in v) + "]"
    raise TypeError(v)
def write(path, cls, script, props, ext=()):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    lines = [f'[gd_resource type="Resource" script_class="{cls}" format=3]', "",
             f'[ext_resource type="Script" path="{R}{script}.gd" id="s"]']
    for i, p in enumerate(ext):
        lines.append(f'[ext_resource type="Resource" path="{p}" id="r{i}"]')
    lines += ["", "[resource]", 'script = ExtResource("s")']
    for k, v in props.items():
        lines.append(f"{k} = {val(v)}")
    open(path, "w", encoding="utf-8").write("\n".join(lines) + "\n")
def ref(i): return f'@ExtResource("r{i}")'

write("data/player_stats.tres", "PlayerStats", "player_stats", {"max_hp": 100})
A = [("light_1", "普攻 1", 10, .08, .06, .16, 90., 120., 0., 0., 0.),
     ("light_2", "普攻 2", 10, .08, .06, .16, 90., 120., 0., 0., 0.),
     ("light_3", "普攻 3", 16, .15, .08, .22, 110., 160., 140., 0., 0.),
     ("skill_sweep", "根须横扫", 40, .2, .1, .25, 150., 360., 60., 6.0, .5)]
for a in A:
    write(f"data/attacks/{a[0]}.tres", "AttackData", "attack_data", {"id": a[0], "display_name": a[1], "damage": a[2], "windup": a[3], "active": a[4], "recovery": a[5], "attack_range": a[6], "arc_deg": a[7], "knockback": a[8], "cooldown": a[9], "stagger_sec": a[10], "hitstop_sec": 0.05, "combo_reset": 0.6})
I = [("moss", "萤苔", "material", (0.5, 0.9, 0.5, 1), {}), ("moss_essence", "萤苔精", "rare_material", (0.3, 1, 0.9, 1), {}),
     ("shard", "记忆碎片", "shard", (0.8, 0.6, 1, 1), {}),
     ("trinket_hp", "萤石护符（HP +15）", "equipment", (1, 0.5, 0.5, 1), {"max_hp_add": 15}),
     ("trinket_atk", "根刺指环（攻击 +10%）", "equipment", (1, 0.7, 0.3, 1), {"atk_pct": 0.1}),
     ("trinket_dash", "风羽坠（冲刺冷却 −20%）", "equipment", (0.5, 0.8, 1, 1), {"dash_recharge_pct": -0.2})]
for i in I:
    write(f"data/items/{i[0]}.tres", "ItemData", "item_data", {"id": i[0], "display_name": i[1], "category": i[2], "color": i[3], "stat_mods": i[4]})
L = {"enemy_common": [{"item": "moss", "chance": 0.3, "min": 1, "max": 1}],
     "guard_1": [{"item": "moss", "chance": 1.0, "min": 8, "max": 8}, {"item": "shard", "chance": 1.0, "min": 1, "max": 1}, {"item": "moss_essence", "chance": 0.4, "min": 1, "max": 1}, {"item": "trinket_any", "chance": 0.25, "min": 1, "max": 1}],
     "guard_2": [{"item": "moss", "chance": 1.0, "min": 8, "max": 8}, {"item": "shard", "chance": 1.0, "min": 1, "max": 1}, {"item": "moss_essence", "chance": 0.5, "min": 1, "max": 1}, {"item": "trinket_any", "chance": 0.3, "min": 1, "max": 1}],
     "guard_3": [{"item": "moss", "chance": 1.0, "min": 12, "max": 12}, {"item": "shard", "chance": 1.0, "min": 2, "max": 2}, {"item": "moss_essence", "chance": 1.0, "min": 1, "max": 1}, {"item": "trinket_any", "chance": 0.5, "min": 1, "max": 1}],
     "chest": [{"item": "moss", "chance": 1.0, "min": 3, "max": 5}, {"item": "shard", "chance": 0.2, "min": 1, "max": 1}, {"item": "moss_essence", "chance": 0.1, "min": 1, "max": 1}]}
for k, e in L.items():
    write(f"data/loot_tables/{k}.tres", "LootTable", "loot_table", {"id": k, "entries": "@Array[Dictionary](" + val(e) + ")"})
E = [("mushling", "菌菇小鬼", 30, 6, 170., 70., .45, 1.6, 0., 4, (0.85, 0.55, 0.35, 1), "Vector2(40, 44)"),
     ("rootshot", "根须射手", 22, 5, 120., 460., .6, 2.0, 0., 4, (0.45, 0.75, 0.3, 1), "Vector2(36, 56)"),
     ("shellbug", "硬壳甲虫", 70, 12, 80., 110., .9, 2.6, 30., 8, (0.4, 0.45, 0.65, 1), "Vector2(64, 52)")]
for e in E:
    p = {"id": e[0], "display_name": e[1], "max_hp": e[2], "damage": e[3], "move_speed": e[4], "attack_range": e[5], "windup": e[6], "attack_interval": e[7], "poise": e[8], "xp": e[9], "loot_table": ref(0), "color": e[10], "size": "@" + e[11]}
    if e[0] == "shellbug": p.update({"attack_active": 0.15, "recover_sec": 0.5})
    write(f"data/enemies/{e[0]}.tres", "EnemyData", "enemy_data", p, ["res://data/loot_tables/enemy_common.tres"])
F = {"frenzy": ("狂暴", {"attack_speed_pct": 0.3}), "summon": ("召唤", {"summon_every": 10.0, "summon_count": 2}), "hardshell": ("硬壳", {"poise_pct": 1.0, "back_damage_mult": 1.5})}
for k, (n, p) in F.items():
    write(f"data/guards/affix_{k}.tres", "AffixData", "affix_data", dict(id=k, display_name=n, **p))
G = [(1, "shellbug", "层守·硬壳甲虫", 260 / 70, 10 / 12, 1.8, ["hardshell"], 0.0, None, 30, (0.75, 0.3, 0.3, 1)),
     (2, "rootshot", "层守·召唤射手", 380 / 22, 12 / 5, 1.7, ["summon"], 0.0, None, 40, (0.35, 0.7, 0.75, 1)),
     (3, "shellbug", "层守·狂暴硬壳甲虫", 620 / 70, 14 / 12, 1.5 * 1.3, ["hardshell", "frenzy"], 0.5, "summon", 60, (0.85, 0.2, 0.55, 1))]
for g in G:
    ext = [f"res://data/enemies/{g[1]}.tres", f"res://data/loot_tables/guard_{g[0]}.tres"] + [f"res://data/guards/affix_{a}.tres" for a in g[6]]
    p = {"id": f"guard_{g[0]}", "display_name": g[2], "base_enemy": ref(0), "hp_mult": round(g[3], 4), "dmg_mult": round(g[4], 4), "attack_interval": round(g[5], 3), "scale": 1.8, "color": g[10],
         "affixes": "@Array[ExtResource(\"sa\")]([" + ", ".join(f'ExtResource("r{2+i}")' for i in range(len(g[6]))) + "])", "phase2_hp_ratio": g[7], "xp": g[9], "loot_table": ref(1)}
    if g[8]:
        ext.append(f"res://data/guards/affix_{g[8]}.tres"); p["phase2_affix"] = ref(len(ext) - 1)
    write(f"data/guards/guard_{g[0]}.tres", "GuardData", "guard_data", p, ext)
    s = open(f"data/guards/guard_{g[0]}.tres").read().replace('id="s"]', 'id="s"]\n[ext_resource type="Script" path="res://scripts/resources/affix_data.gd" id="sa"]', 1)
    open(f"data/guards/guard_{g[0]}.tres", "w").write(s)
for n in (1, 2, 3):
    write(f"data/floors/floor_{n}.tres", "FloorData", "floor_data", {"depth": n, "wave_size_min": 4 if n == 3 else 3, "guard": ref(0), "chest_loot": ref(1)},
          [f"res://data/guards/guard_{n}.tres", "res://data/loot_tables/chest.tres"])
B = [("blade", "利刃", "普攻伤害 +20%", {"light_pct": 0.2}, []), ("gale", "疾风", "冲刺充能 +1", {"dash_charges_add": 1}, []),
     ("afterimage", "残影", "冲刺终点留下 0.5 秒的伤害圈（8 伤害）", {"afterimage_dmg": 8}, ["on_dash"]),
     ("rootbind", "根缠", "技能附带 1.5 秒减速", {"skill_slow_sec": 1.5}, []), ("thickhide", "厚皮", "最大 HP +20", {"max_hp_add": 20}, []),
     ("bloodthirst", "嗜血", "击杀回 2 HP", {"kill_heal": 2}, ["on_kill"]), ("finisher", "终结", "第三段伤害 +50%", {"finisher_pct": 0.5}, []),
     ("swift", "迅捷", "技能冷却 −25%", {"skill_cd_pct": -0.25}, [])]
for b in B:
    write(f"data/boons/{b[0]}.tres", "BoonData", "boon_data", {"id": b[0], "display_name": b[1], "desc": b[2], "stat_mods": b[3], "tags": "@PackedStringArray(" + ", ".join(val(x) for x in b[4]) + ")"})
write("data/legacy_rules.tres", "LegacyRules", "legacy_rules", {"level_ratio": 0.3, "legacy_power": 0.5, "mastery_ratio": 0.5})
write("data/vault_rules.tres", "VaultRules", "vault_rules", {"base_slots": 4})
write("data/meta_rules.tres", "MetaRules", "meta_rules", {"vit_hp_per_level": 10})
write("data/lore/clues.tres", "LoreClues", "lore_clues", {"log_flash_sec": 0.35, "log_repeat_chance": 0.3})
print("ok")
