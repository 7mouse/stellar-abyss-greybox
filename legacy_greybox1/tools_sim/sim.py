"""Stellar Abyss 灰盒数值模拟（按 greybox 代码公式复刻）。
用法: python3 sim.py [old|new|v2] [runs]（v2 = 当前游戏参数，最终层 3）
判定模式: perfect / good / fail / mixed(25%P 50%G 25%F)
注: 判定被强制（同游戏内 auto_minigame 测试钩子），运气小游戏也按强制判定计。
"""
import random, sys, statistics as st

OLD = dict(nodes_min=8, nodes_max=10, rest_heal_ratio=0.3, player_max_hp=100, player_speed=10,
    slash=10, heavy=16, rps=13, enemy_min=1, enemy_max=3, hp_per_depth=0.2, atk_per_depth=0.15,
    atk_mult=[1.5,1.0,0.5], def_mult=[0.0,0.5,1.0],
    enemies=[("melee",28,9,12),("tracker",22,11,7),("balanced",34,8,9)],
    weights=[0.45,0.2,0.2,0.15], rps_anim=0.8)
NEW = dict(OLD, nodes_min=11, nodes_max=13, rest_heal_ratio=0.3, hp_per_depth=0.25, atk_per_depth=0.25,
    def_mult=[0.0,0.35,1.0],
    enemies=[("melee",28,5,12),("tracker",22,7,7),("balanced",34,5,9)],
    weights=[0.45,0.2,0.2,0.15], rps_anim=0.5)

# v2（与 data/tunables.tres 同步）：第 3 层入口固定休息点、最终层 3
V2 = dict(NEW, nodes_min=12, nodes_max=14, atk_per_depth=0.2,
    entrance_rest_floors=(3,), entrance_rest_heal=0.7)

TYPES=["combat","chest","event","rest"]
# 时长估算（秒）
T_MG=(3.0,6.0)      # 每次小游戏（含预兆），按要求 3-6 秒
T_MENU=2.0          # 主角选技能/目标
T_BATTLE_IO=3.5     # 进场 + 胜利 1.0s + 场景切换
T_NODE=3.0          # 地图上选节点+移动
T_POPUP=2.5         # 宝箱/事件/休息弹窗确认
T_EXIT=4.0          # 出口抉择+生成下一层
T_RESULT=8.0        # 结算界面

def rr(x):  # Godot roundi：四舍五入远离零
    return int(x+0.5) if x>=0 else -int(-x+0.5)

def gen_floor(p, rng):
    n=rng.randint(p["nodes_min"],p["nodes_max"]); middle=n-1; cols=[]
    while middle>0:
        c=min(rng.randint(1,3),middle); cols.append(c); middle-=c
    # 路径：每列走一个节点（DAG 列式，每列必经一个）；类型按权重
    path=[]
    for c in cols:
        opts=[rng.choices(TYPES,p["weights"])[0] for _ in range(c)]
        path.append(opts)
    if not any("combat" in o for o in path):
        path[rng.randrange(len(path))][0]="combat"
    return path

def judge(mode, rng):
    if mode=="perfect": return 0
    if mode=="good": return 1
    if mode=="fail": return 2
    return rng.choices([0,1,2],[0.25,0.5,0.25])[0]

def mg_time(rng, p, is_rps=False, res=1):
    t=rng.uniform(*T_MG)
    if is_rps and res==1:  # 平局重来：多一轮洗牌动画 + 0.5s 展示
        t+=p["rps_anim"]+0.5
    return t

def battle(p, depth, hp, mode, rng):
    t=T_BATTLE_IO
    cnt=max(1,min(3,rng.randint(p["enemy_min"],min(p["enemy_max"],p["enemy_min"]+depth))))
    es=[]
    for _ in range(cnt):
        n,mh,atk,spd=rng.choice(p["enemies"])
        h=rr(mh*(1+(depth-1)*p["hp_per_depth"])); a=rr(atk*(1+(depth-1)*p["atk_per_depth"]))
        es.append([h,a,spd])
    skills=[(p["slash"],False),(p["rps"],True),(p["heavy"],False)]
    while True:
        order=[("P",p["player_speed"])]+[(i,e[2]) for i,e in enumerate(es) if e[0]>0]
        order.sort(key=lambda x:-x[1])  # Godot sort_custom 非稳定，此处近似
        for who,_ in order:
            if who=="P":
                alive=[e for e in es if e[0]>0]
                if not alive: break
                pw,isr=rng.choice(skills)   # 玩家随机轮换 3 个技能
                r=judge(mode,rng); t+=T_MENU+mg_time(rng,p,isr,r)
                tgt=min(alive,key=lambda e:e[0])  # 集火残血
                tgt[0]=max(0,tgt[0]-rr(pw*p["atk_mult"][r]))
            else:
                e=es[who]
                if e[0]<=0: continue
                r=judge(mode,rng); t+=mg_time(rng,p)
                hp=max(0,hp-rr(e[1]*p["def_mult"][r]))
            if all(e[0]<=0 for e in es): return hp,t,True
            if hp<=0: return 0,t,False

def run(p, mode, rng, policy="always", max_depth=3):
    hp=p["player_max_hp"]; depth=1; t=0.0; hp_after={}; low={}
    while True:
        if depth in p.get("entrance_rest_floors",()):  # 固定入口休息点（必经）
            t+=T_NODE+T_POPUP
            hp=min(p["player_max_hp"],hp+rr(p["player_max_hp"]*p["entrance_rest_heal"]))
        for opts in gen_floor(p,rng):
            t+=T_NODE
            # 选点：低血优先休息，否则随机
            node = "rest" if (hp<p["player_max_hp"]*0.6 and "rest" in opts) else rng.choice(opts)
            if node=="combat":
                hp,bt,ok=battle(p,depth,hp,mode,rng); t+=bt
                low[depth]=min(low.get(depth,1.0),hp/p["player_max_hp"])
                if not ok: return dict(died=True,depth=depth,time=t+T_RESULT,hp_after=hp_after,low=low)
            else:
                t+=T_POPUP
                if node=="rest": hp=min(p["player_max_hp"],hp+rr(p["player_max_hp"]*p["rest_heal_ratio"]))
        hp_after[depth]=hp/p["player_max_hp"]
        t+=T_EXIT
        if depth>=max_depth or (policy=="cautious" and hp<p["player_max_hp"]*0.4):
            return dict(died=False,depth=depth,time=t+T_RESULT,hp_after=hp_after,low=low)
        depth+=1

def report(p, runs, policy, seed=1):
    out={}
    for mode in ["perfect","good","mixed","fail"]:
        rng=random.Random(seed); rs=[run(p,mode,rng,policy) for _ in range(runs)]
        times=sorted(r["time"]/60 for r in rs)
        clear2=sum(1 for r in rs if 2 in r["hp_after"])/runs
        hp2=[r["hp_after"][2] for r in rs if 2 in r["hp_after"]]
        low2=[min(r["low"].get(1,1),r["low"].get(2,1)) for r in rs if 2 in r["hp_after"]]
        died12=sum(1 for r in rs if r["died"] and r["depth"]<=2)/runs
        avgd=st.mean(r["depth"] for r in rs)
        out[mode]=(st.mean(times),times[runs//10],times[runs*9//10],avgd,clear2,st.mean(hp2) if hp2 else 0,died12)
        print(f"{policy:8s} {mode:8s} 时长均值 {out[mode][0]:5.1f}min (P10 {out[mode][1]:4.1f} / P90 {out[mode][2]:4.1f})  "
              f"平均结束层 {avgd:4.2f}  打完第2层 {clear2*100:5.1f}%  第2层出口剩血 {out[mode][5]*100:4.0f}%  前2层最低血线 {(st.median(low2) if low2 else 0)*100:4.0f}%  第1-2层倒下 {died12*100:5.1f}%")
    return out

if __name__=="__main__" and not (len(sys.argv)>1 and sys.argv[1]=="v2"):
    which=sys.argv[1] if len(sys.argv)>1 else "both"; n=int(sys.argv[2]) if len(sys.argv)>2 else 1000
    for name,p in (("OLD",OLD),("NEW",NEW)):
        if which in (name.lower(),"both"):
            print(f"===== {name} 参数, 每种 {n} 局 =====")
            for pol in ("always","cautious"): report(p,n,pol)

def table(p, runs=1000, seed=1):
    rows=[]
    for mode in ["good","mixed","perfect","fail"]:
        for pol in ["always","cautious"]:
            rng=random.Random(seed); rs=[run(p,mode,rng,pol) for _ in range(runs)]
            ts=sorted(r["time"]/60 for r in rs)
            clear=sum(1 for r in rs if not r["died"] and r["depth"]>=3)/runs
            died=sum(1 for r in rs if r["died"])/runs
            rows.append((mode,pol,st.mean(ts),ts[runs//10],ts[runs*9//10],clear,died))
    return rows

if __name__=="__main__" and len(sys.argv)>1 and sys.argv[1]=="v2":
    n=int(sys.argv[2]) if len(sys.argv)>2 else 1000
    print(f"===== V2 参数（最终层 3），每种 {n} 局 =====")
    for mode,pol,avg,p10,p90,clr,died in table(V2,n):
        print(f"{mode:8s} {pol:8s} 均值 {avg:5.1f} 分钟 (P10 {p10:4.1f} / P90 {p90:4.1f})  通关 {clr*100:5.1f}%  倒下 {died*100:5.1f}%")
    sys.exit(0)

