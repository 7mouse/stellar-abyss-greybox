"""灰盒 2 模拟（设计师 docs/sim2/sim_g2.py 的副本，参数按游戏 79dce9c 对齐，并补充统计）。
不改设计文档；与原脚本的差异见 MISMATCH 注释。用法: python3 tools/sim/sim_g2_game.py [runs] [--doc]
覆盖键：guardN_hp/dmg/iv/xp、wavesN（第 N 层每房波数）、heal_between、legacy_power、summon_every、guard_hit_mult
--doc：原脚本参数（对照）；默认：游戏参数。可用 --set KEY=VAL 覆盖（例：--set guard3_hp=520）。"""
import random, sys, statistics as st, math, json

DOC = "--doc" in sys.argv
OVR = {}
for a in sys.argv:
    if a.startswith("--set="):
        for kv in a[6:].split(","):
            k, v = kv.split("="); OVR[k] = float(v)
args = [a for a in sys.argv[1:] if not a.startswith("--")]
N = int(args[0]) if args else 1000

PLAYER = dict(hp=100, light=[10,10,16], light_t=[0.30,0.30,0.45], skill_dmg=40, skill_cd=6.0, skill_targets=2.5,
              hp_per_lv=0.08, atk_per_lv=0.05, xp_curve=[0,20,50,95,155,230,320,430,560,710], heal_between_floors=0.30)
ENEMIES = {"mushling": (30, 6, 1.6, 4), "rootshot": (22, 5, 2.0, 4), "shellbug": (70, 12, 2.6, 8)}
SCALE = dict(hp=1.25, dmg=1.12)
FLOOR = dict(combat_rooms=(3,4), waves=(2,2), mix=[0.45,0.35,0.20], explore_s_per_room=25, rooms_extra=(1,2),
             wave_gap_s=3.0 if DOC else 2.0,           # MISMATCH：游戏 wave_delay = 2.0
             boon_pick_s=6.0)
WAVE_SIZE = {1:(3,5), 2:(3,5), 3:(3,5) if DOC else (4,5)}   # MISMATCH：游戏第 3 层 4~5
GUARD = {1:[260,10,1.8,30], 2:[380,12,1.7,40], 3:[620,14,1.5,60]}
WAVES = {1:2, 2:2, 3:2}                                   # 每个战斗房波数（游戏 FloorData.waves）
if not DOC:   # 主策决定（灰盒 2 调参）：层守 1/2 HP、层守 3 1200/11、第 3 层 3 波、层间回血 40%
    GUARD[1][0] = 400; GUARD[2][0] = 400; GUARD[3][0] = 1200; GUARD[3][1] = 11
    WAVES[3] = 3; PLAYER["heal_between_floors"] = 0.40
GUARD_MATS = {1:8, 2:8, 3:8 if DOC else 12}               # MISMATCH：游戏第 3 层层守掉材料 12
TRINKET_CH = {1:0.25, 2:0.30, 3:0.50}
GUARD_HEAL_ROOM = 0.30
BOON_ATK = 0.10
LEGACY_POWER = OVR.get("legacy_power", 0.5)
PHASE2_SEC = 1.0          # 二阶段演出（无敌）
GUARD_SKILL_TARGETS = 2.5 if DOC else 1.0   # MISMATCH：层守战只有 1 个目标（召唤物另算），原脚本按 2.5 个
PROFILE = {"novice": dict(hit=0.38, uptime=0.45, guard_hit=0.45), "average": dict(hit=0.24, uptime=0.55, guard_hit=0.30),
           "skilled": dict(hit=0.12, uptime=0.65, guard_hit=0.16)}
for k, v in OVR.items():
    if k.startswith("guard") and k[5:6].isdigit():
        n, f = k[5], k.split("_")[1]; GUARD[int(n)][["hp","dmg","iv","xp"].index(f)] = v
    elif k == "summon_every": pass
    elif k.startswith("waves"): WAVES[int(k[5])] = int(v)
    elif k == "heal_between": PLAYER["heal_between_floors"] = v
    elif k == "guard_hit_mult":
        for p in PROFILE.values(): p["guard_hit"] *= v
SUMMON_EVERY = OVR.get("summon_every", 10.0)

def lv_of(xp): return sum(1 for x in PLAYER["xp_curve"] if xp >= x)

def dps(lv, s, prof, targets=None):
    combo = sum(PLAYER["light"]) / sum(PLAYER["light_t"])
    skill = PLAYER["skill_dmg"] * (PLAYER["skill_targets"] if targets is None else targets) / PLAYER["skill_cd"]
    return (combo*prof["uptime"] + skill) * (1+(lv-1)*PLAYER["atk_per_lv"]) * (1 + s["boons"]*BOON_ATK + s["legacies"]*BOON_ATK*LEGACY_POWER) * (1 + s["atk_eq"])

def maxhp(s): return PLAYER["hp"]*(1+(lv_of(s["xp"])-1)*PLAYER["hp_per_lv"]) + s["hp_eq"]

def fight(enemies, hp, s, prof, rng, guard=None, depth=1):
    """guard=(n) 时模拟召唤与二阶段；返回 (hp, 时长)"""
    t = 0.0; pool = [list(e) for e in enemies]; d = dps(lv_of(s["xp"]), s, prof, GUARD_SKILL_TARGETS if guard else None)
    g = pool[0] if guard else None; g_max = g[0] if g else 0; phase2 = False; next_summon = SUMMON_EVERY
    while pool and (g is None or g[0] > 0):
        t += 0.5
        active = pool[:3]
        if g is not None:   # 层守战：先清召唤物再打层守（召唤物一刀一只的量级）
            adds = [e for e in pool if e is not g]
            tgt = min(adds, key=lambda e: e[0]) if adds else g
        else:
            tgt = min(active, key=lambda e: e[0])
        tgt[0] -= d*0.5*rng.uniform(0.7, 1.3)
        for e in active:
            if rng.random() < 0.5/e[2] and rng.random() < (prof["guard_hit"] if (g is not None and e is g) else prof["hit"]):
                hp -= e[1]
        if g is not None and not DOC:
            if depth == 3 and not phase2 and g[0] <= g_max*0.5:
                phase2 = True; t += PHASE2_SEC
            summ = depth == 2 or (depth == 3 and phase2)
            if summ and t >= next_summon:
                h, dm, iv, _ = ENEMIES["mushling"]
                for _ in range(2): pool.append([h*SCALE["hp"]**(depth-1), dm*SCALE["dmg"]**(depth-1), iv])
                next_summon = t + SUMMON_EVERY
        pool = [e for e in pool if e[0] > 0 or e is g]
        if hp <= 0: return 0, t
    return hp, t

def floor_run(n, s, prof, rng, stats):
    t = 0.0; sc_h = SCALE["hp"]**(n-1); sc_d = SCALE["dmg"]**(n-1)
    rooms = rng.randint(*FLOOR["combat_rooms"]); extra = rng.randint(*FLOOR["rooms_extra"])
    if DOC: boons_here = rng.randint(2, 3)
    else: boons_here = 2 + sum(1 for _ in range(extra) if rng.random() < 0.5)   # MISMATCH：游戏 2 个奖励房 + 强化支路（50%）= 2~4
    t += boons_here*FLOOR["boon_pick_s"] + (rooms+extra+1)*FLOOR["explore_s_per_room"]
    for r in range(rooms):
        for w in range(WAVES[n]):
            es = []
            for _ in range(rng.randint(*WAVE_SIZE[n])):
                k = rng.choices(list(ENEMIES), FLOOR["mix"])[0]; h, dm, iv, xp = ENEMIES[k]
                es.append((h*sc_h, dm*sc_d, iv)); s["xp"] += xp
            s["hp"], ft = fight(es, s["hp"], s, prof, rng, depth=n); t += ft+FLOOR["wave_gap_s"]
            if s["hp"] <= 0: return False, t
        if r == 0 or r == rooms-1: s["boons"] += 1
    s["boons"] += max(0, boons_here-2)
    s["hp"] = min(maxhp(s), s["hp"] + maxhp(s)*GUARD_HEAL_ROOM)
    gh, gd, gi, gx = GUARD[n]
    hp0 = s["hp"]
    s["hp"], ft = fight([(gh, gd, gi)], s["hp"], s, prof, rng, guard=n, depth=n); t += ft+5
    stats.setdefault(n, []).append(dict(t=ft, died=s["hp"] <= 0, lost=(hp0 - max(0, s["hp"]))/maxhp(s)))
    if s["hp"] <= 0: return False, t
    s["xp"] += gx
    if not DOC and rng.random() < TRINKET_CH[n]:   # MISMATCH：饰品（假设值）原脚本未计
        k = rng.choice(["hp", "atk", "dash"])
        if k == "hp": s["hp_eq"] += 15; s["hp"] += 15
        elif k == "atk": s["atk_eq"] += 0.10
    return True, t

def run(prof, rng, start_lv=1, legacies=0, stats=None):
    s = dict(xp=PLAYER["xp_curve"][start_lv-1], boons=0, legacies=legacies, hp_eq=0, atk_eq=0.0)
    s["hp"] = maxhp(s); res = []
    for n in (1, 2, 3):
        ok, t = floor_run(n, s, PROFILE[prof], rng, stats if stats is not None else {})
        res.append((ok, t, lv_of(s["xp"])))
        if not ok: break
        s["hp"] = min(maxhp(s), s["hp"] + maxhp(s)*PLAYER["heal_between_floors"])
    return res

def pct(xs, p):
    xs = sorted(xs); return xs[min(len(xs)-1, int(p*len(xs)))] if xs else 0

if __name__ == "__main__":
    print("参数：", "设计师原脚本" if DOC else "游戏（灰盒 2 调参后）", OVR or "")
    for prof in PROFILE:
        rng = random.Random(11); stats = {}; rs = [run(prof, rng, 1, 0, stats) for _ in range(N)]
        print(f"== {prof} ==")
        for n in (1, 2, 3):
            reached = [r for r in rs if len(r) >= n]; ok = [r[n-1] for r in reached if r[n-1][0]]
            ts = [x[1]/60 for x in ok]
            g = stats.get(n, [])
            gd = sum(1 for x in g if x["died"]) / max(1, len(g))
            print(f"  第{n}层 累计通过 {len(ok)/N*100:5.1f}%  用时 中位 {pct(ts,.5):4.1f} 分（P10 {pct(ts,.1):4.1f} – P90 {pct(ts,.9):4.1f}）  结束 Lv{st.mean(x[2] for x in ok) if ok else 0:3.1f}"
                  f"  | 层守：战斗 中位 {pct([x['t'] for x in g],.5):4.0f} 秒（P10 {pct([x['t'] for x in g],.1):3.0f}–P90 {pct([x['t'] for x in g],.9):3.0f}）"
                  f"  到达层守后死亡 {gd*100:4.1f}%  掉血中位 {pct([x['lost'] for x in g],.5)*100:3.0f}% 最大 HP")
    for prof in PROFILE:
        out = []
        for lv, leg in ((1, 0), (2, 0), (2, 1)):
            rng = random.Random(12); rs = [run(prof, rng, lv, leg) for _ in range(N)]
            out.append(sum(1 for r in rs if len(r) == 3 and r[2][0]) / N * 100)
        print(f"{prof:8s} 打穿 3 层：Lv1 {out[0]:5.1f}%  继承 Lv2 {out[1]:5.1f}%  Lv2 + 1 遗志（50%） {out[2]:5.1f}%")
