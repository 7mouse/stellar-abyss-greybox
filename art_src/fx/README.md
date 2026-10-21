# 战斗特效（fx_v1，2026-10-21c）
来源 `art_src/src/fx_set_gen1.jpg`（9 行 × 4 列），`cut_sprites.py art_src/fx/fx_cut.json`；alpha 按离白纸的距离算（保留水彩软边），没调色（原图已经是低饱和）。

| 文件夹 | 帧 | 用途 |
| --- | --- | --- |
| f01_slash | 4 | F01 轻攻击刀光（规格 6） |
| f15_ring | 4 | F15 号令声波环用 1 张；其余 3 张可当 F13 冲击波 |
| f03_thrust | 4 | F03 技能 2 刺光 |
| f04_hit_spark | 4 | F04 命中火花 |
| f05_dust | 4 | F05 冲刺尘土（F14 冲撞尘烟可复用） |
| f09_moss_debris | 4 | F09 死亡苔屑 |
| fx_leaf_scatter | 4 | 深苔破壳碎叶（C08 破甲） |
| f11_portal_splash | 4 | F11 撤离传送门（规格 10） |
| f07_spore_cloud | 4 | F07 孢子云（孢子囊 2 张没有） |
帧尺寸不统一（按原图裁），导入时按中心对齐；规格尺寸（256/384/128…）由程序缩放。

# FX v2（2026-10-21f，缺件补齐）
来源 `art_src/src/v21f/fx_set_gen2a.jpg`、`fx_set_gen2b.jpg`、`fx_f01_finisher_gen1.jpg`、`fx_f14_dust_gen1.jpg`（GenerateImage，用 fx_v1 的低饱和色板当参考，没有糖果色）；`cut_sprites.py art_src/fx/fx_v2_cut.json` → `fx_v2/`。

| 目录 | 帧 | 对应 |
| --- | --- | --- |
| f01_slash | 2 | F01 第 3 段（终结斩）`f01_slash_5/6`，接 fx_v1 的 1–4 |
| f02_sweep | 4 | F02 技能 1 横斩弧光 |
| f06_spore | 2 + 4 | F06 孢子弹 `f06_bullet_1–2`、爆散 `f06_burst_1–4` |
| f07_spore_sac | 2 | F07 孢子囊 完整 / 瘪 |
| f10_pickup | 4 | F10 拾取光（`alpha_gain 2.2` + 米白 tint，原图太淡） |
| f11_portal | 2 + 4 | F11 激活 `f11_activate_1–2`、传送 `f11_teleport_1–4` |
| f13_root_spike | 4 | F13 根刺（冲击波 3 张仍在 fx_v1） |
| f14_charge_dust | 3 | F14 冲撞尘烟（单独生成的纯尘烟图；第一版里画进了一只野兽，抠不干净，弃用） |
| f08_warning_brush | 1 | F08 预警笔触：`make_fx_extra.py` 从 `fx_f08_brush_gen1` 自动找周期、x/y 环绕后缩到 256，白色 RGBA（alpha = 笔触，引擎着色）；接缝比 x 1.08 / y 0.80；`_tiling_check.png` 是 3×3 平铺 |
| f12_damage_font | 1 | F12 伤害数字：**不用 AI**，Lilita One（SIL OFL 字库）64 px，`0123456789+-!x`，米白填充 + 5 px 深色描边 + 3 px 投影；`f12_damage_font.png` + BMFont 文本 `.fnt`；颜色由引擎 tint（预览：普通 / 暴击 / 治疗 / 主角受伤） |

清单 `fx_v2/manifest.json`（每帧来源图和裁切参数）、`fx_v2/extra_manifest.json`（F08/F12），总览 `fx_v2/contact.png`。gen2a 第 2 行（类似刺光的线条）没用。
