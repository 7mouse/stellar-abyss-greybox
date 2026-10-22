# 美术交接文档（ART_HANDOFF）· 第一关 · 2026-10-21

仓库：[7mouse/stellar-abyss-greybox](https://github.com/7mouse/stellar-abyss-greybox) 分支 [`rig-trial`](https://github.com/7mouse/stellar-abyss-greybox/tree/rig-trial)（公开）；设计仓库 [7mouse/stellar-abyss-design](https://github.com/7mouse/stellar-abyss-design)（私有，规范和第三方参考图在这里）。
交接时（2026-10-21 约 17:40，UTC+8）进度：**P0 283/318**；最后一批（第 5 项）只生成了原图、没切，见 [art_src/wip/2026-10-21g/](https://github.com/7mouse/stellar-abyss-greybox/tree/rig-trial/art_src/wip/2026-10-21g)。

做法总原则（制作人定）：美术预算 ¥0；**全部用 GenerateImage 生成 + 脚本切图/拼装，不手绘**；先求第一关能玩，画质后修。脚本只依赖 python3 + numpy、scipy、pillow、psd-tools。所有命令都在仓库根目录跑。

---

## 1. 风格基准与规范（先看这些）
| 内容 | 链接 |
|---|---|
| 美术方向总纲（**定稿 v2**） | [06-art-direction/README.md](https://github.com/7mouse/stellar-abyss-design/blob/main/06-art-direction/README.md) |
| 战斗基准图（制作人确认 2026-10-16） | [06-art-direction/img/combat_baseline_v2.jpg](https://github.com/7mouse/stellar-abyss-design/blob/main/06-art-direction/img/combat_baseline_v2.jpg)；副本 [art_src/ref/combat_baseline_v2.jpg](https://github.com/7mouse/stellar-abyss-greybox/blob/rig-trial/art_src/ref/combat_baseline_v2.jpg) |
| UI 样式规范（末尾「定稿 v2」「道具品质规范」有效） | [06-art-direction/specs/ui_style_v1.md](https://github.com/7mouse/stellar-abyss-design/blob/main/06-art-direction/specs/ui_style_v1.md) |
| 第一关美术方案 v1 / v2 | [level1_art_plan_v1.md](https://github.com/7mouse/stellar-abyss-design/blob/main/06-art-direction/specs/level1_art_plan_v1.md)、[level1_art_plan_v2.md](https://github.com/7mouse/stellar-abyss-design/blob/main/06-art-direction/specs/level1_art_plan_v2.md) |
| 角色 / 怪物设计标准 | [character_monster_design_standard.md](https://github.com/7mouse/stellar-abyss-design/blob/main/06-art-direction/specs/character_monster_design_standard.md) |
| 资产总表（编号 C/F/S/V/U） | [10-assets/ASSETS.md](https://github.com/7mouse/stellar-abyss-design/blob/main/10-assets/ASSETS.md) |
| 第一关打磨规格（尺寸、数量、村落布局 §7.2、P0 §8.7） | [docs/level1-polish-spec.md](https://github.com/7mouse/stellar-abyss-greybox/blob/rig-trial/docs/level1-polish-spec.md)（设计仓库 07-prototype/ 同名） |
| 骨骼拆件规范 | [docs/rig-parts-spec.md](https://github.com/7mouse/stellar-abyss-greybox/blob/rig-trial/docs/rig-parts-spec.md) |
| 最新完成清单（21f） | [docs/level1-art-checklist-2026-10-21f.md](https://github.com/7mouse/stellar-abyss-greybox/blob/rig-trial/docs/level1-art-checklist-2026-10-21f.md) |
| 最新总览图（21f） | [docs/level1-art-overview-2026-10-21f.png](https://github.com/7mouse/stellar-abyss-greybox/blob/rig-trial/docs/level1-art-overview-2026-10-21f.png) |
| 最新战斗对照图（21f） | [docs/level1-combat-mock-2026-10-21f.png](https://github.com/7mouse/stellar-abyss-greybox/blob/rig-trial/docs/level1-combat-mock-2026-10-21f.png) |

**制作人的口味约束（硬性）**
- 不要廉价页游感（通用扁平 UI 套件、金属镶边、菱形钉、亮面塑料感）。
- 不要糖果色、不要过饱和；整体低饱和、偏暗、有雾气。
- 不要 AI 味（规整重复的叶片/鬃毛、假文字、贴纸边、白底残留、到处一样的纹理）。
- 不模仿、也不在提示词里写任何在世画师的名字。
- 画风：非像素日式手绘 2D，约 2.5 头身 Q 版角色，对话头像 D 比例，Zenonia 式 HUD，高俯视 3/4 视角。
- 第三方截图（Zenonia 等）**只放私有设计仓库** 06-art-direction/reference/，本仓库公开，不放。

---

## 2. 目录结构
```
art_src/
  ref/            参考图（基准图、设定图、方案样板 level1_plan_samples/、作废的画风探索 explore/）+ README
  src/            AI 原图（GenerateImage 输出，按批次：根目录=21c 前，terrain_v2/ ui_v2/ = 21d/21e，v21f/ = 21f；derived/ = 工具从原图拆出的五官）
  prompts/        每轮的提示词、宽高比、参考图、输出 id（见 §4）
  wip/2026-10-21g/  最后一批的原图，WIP，未切（见 §6）
  rigs/<角色>/    拆件：*_cut.json / *_extras_vX.json / *_patch.json / *_fix.json（配置），
                  *_parts_<f|s|b>_vX.psd（1:1）、*_src2x.psd（2x）、*_preview.png、*_pivots.json、*_jointcheck.png/json、
                  parts_vX/*.png（1:1 整画布单件）、*_palette_src.png/json、*_preview_swaps.png
  rigs/_poses/    参考姿势配置 *_poses_v1/v2.json（ref_poses.py 用）
  rigs/LEVEL1_BATCH_NOTES.md  21c–21f 每批角色做法；rigs/RIG_V2_NOTES.md  v2 / v2.1 关节规则的来源和数据
  terrain/        地表配置 *.json + floor1_v1/（21c，作废）+ floor1_v2/（现行：tiles edges trees props_* decals_v3 light_v3 cliffs forest）+ README
  ui/             hud_v1/（作废）hud_v2/（现行：bars frames panels icons icons_u16 states screens portrait hud）+ 配置 + README
  fx/             fx_v1/（F03–F05、F09 等 21c）fx_v2/（21f 补齐）+ 配置 + README
  tools/          全部脚本 + README_rig_tools.md（v3–v6 每版新增功能）
docs/
  ART_HANDOFF.md                 本文
  level1-art-checklist-2026-10-21{c,d,e,f}.md   每批完成清单（最新 21f）
  level1-art-overview-2026-10-21{c,d,e,f}.png   每批总览
  level1-combat-mock-2026-10-21{d,e,f}.png      每批战斗对照（左新右 baseline）
  level1-polish-spec.md / level1-tech-plan.md / rig-parts-spec.md
```

---

## 3. 管线（从生成到交付）
### 3.1 生成
- 工具：GenerateImage。参数只有提示词、`aspect_ratio`、参考图；16:9 输出 1280×720，1:1 输出 1024²。**没有 seed**，不能复现，原图一律入库。
- 部件表 / 道具表：**纯白底**、每件之间留白不相接、不要文字/标签/地面阴影；参考图给同角色的已有预览或 combat_baseline_v2，保证画风一致。
- 读图时显示为 1024×576，脚本里的 `pick` / `rect` 坐标是 **显示坐标**，`disp_scale` 1.25 换算到实际像素（1024² 图用 1.0）。

### 3.2 角色拆件（rigs）
顺序：
1. `python3 art_src/tools/cut_partsheet.py art_src/rigs/<x>/<x>_<dir>_cut.json` → 分层 PSD（白底抠图、按部件放到 2x 画布、`_pivots` 层），配置里写 `joints` 会自动做关节圆头（先出 `_raw`）。键：`canvas2x(_h)`、`k`（固定缩放）、`source`/`png`/`clip`/`flip_h`/`swap`/`recolor_ref`/`keep_holes` 等，见 tools README v3。
2. `python3 art_src/tools/rig_extras.py art_src/rigs/<x>/<x>_<dir>_extras_vX.json` → 在已有版本上加件出新版本（`_vX_raw`）：`blink`、`add_part`（新原图取件 + IoU/box/at 对位 + 换色 + 遮罩）、`split`（肢体膝点切 2 段）、`underfill`（隐藏延伸）、`grade`、`reorder`、`swap`（隐藏替换件）、`empty`（结构空层）、`pivots`、`rename`。
3. `python3 art_src/tools/rig_patch.py art_src/rigs/<x>/<x>_parts_<dir>_vX_patch.json` → 关节圆头（`"cap_version": 2`）、去白边、补洞、导出 1:1 / 2x / 预览 / pivots。
4. `python3 art_src/tools/rig_check.py art_src/rigs/<x>/<x>_parts_<dir>_vX_fix.json --seam-band 4 --labels vOld vX --sheet <out>_jointcheck.png --json <out>_jointcheck.json` → 关节自检。
5. 色板：`python3 art_src/tools/make_palette.py art_src/rigs/<x>/<x>_palette_src 12 <psd...> [--layers a,b]`（k-means，8–16 色，index 0 = 描边色，最后 = 高光，中间由暗到亮，16×16/格 + hex json）；换色变体用 `make_target_palette.py`（逐格对应源色板）。
6. 替换件检查 `swap_sheet.py <psd> out.png`；参考姿势 `ref_poses.py art_src/rigs/_poses/<x>_poses_v2.json`；对照 `rig_compare.py rotsheet|combine`。

**v2.1 关节规则**（详见 [RIG_V2_NOTES.md](https://github.com/7mouse/stellar-abyss-greybox/blob/rig-trial/art_src/rigs/RIG_V2_NOTES.md)）：
- 重叠量（1:1）：小件（前臂、小腿、手、耳、尾、芽，宽 ≤20 px）4–8 px；大件（身体、头、大腿/上臂根部）10–20 px。
- 圆头：沿骨骼方向的半椭圆，侧向半径 = 部件末端宽度。**上层件的圆头只长在父件/更上层盖住的地方，并复制父件像素**（静止时看不见）；藏在下层的圆头只长在上层覆盖区。先擦旧切口线（端部 4 px 内偏暗像素），再逐列从内部取色填。`post_ops`: `erase_outline_over`（擦远腿上方的身体轮廓）、`solidify`（补实半透明裂缝）。
- 宽配件（苔冠、菌盖、卷尾）用 `underfill` 隐藏延伸：从父件自身像素长出、压暗（`shade`），转动时露出的是父件颜色不是背景。
- 隐藏图层 = 替换件（眨眼、表情、张嘴），不进预览、不进自检。
- **rig_check 口径**：子件（连同下级）绕枢轴 ±15°/±30° 旋转，报 `worst` = 关节圆内的洞 px、`seam` = 父件边缘 4 px（`--seam-band 4`）内的洞 px；**目标 ±30° 为 0**，<1 px 视为抗锯齿。

### 3.3 地表 / 道具 / UI / 特效
- 精灵切图：`python3 art_src/tools/cut_sprites.py <config.json>` → 单张 PNG + manifest + contact。条目 `pick`（连通块）/ `rect`（含散粒的特效帧）/ `tile`（贴图）；选项 `recolor`（HSV sat/val + hue_to）、`max`（只缩不放到规格尺寸）、`black`（黑底光，alpha=亮度）、`alpha_gain`、`tint`、`erase_dark`、`open_holes`、`nine`、`split_fill`（状态条拆底框/填充/上层）。
- **接缝检测**：比值 = 环绕边差 / 内部相邻像素差，**≤1.6 判为无缝**（`seam_score`）。修法：`make_tiles.py <tiles.json>` 用最小误差切缝（image quilting）环绕，只缩不放、不交叉淡化（没有重影）；`variants` 共享 40 px 外圈的变体可任意混铺；边缘叠加条交界线固定在第 88 行，拐角用极坐标弯曲（半径 40）。旧的 `_seamless`（半偏移交叉淡化）有重影，不推荐。
- **九宫（9-slice）**：`make_ui_v2.py art_src/ui/hud_v2.json` 按九宫安全规则重建：保留四角，边取中间一列/行重复，中间平色（底板 85% 不透明）+ 周期纸纹（强度 0.08，中间区 TILE 安全）。边距表在 21f 清单「九宫边距」节；`cut_sprites` 的 `nine` 估算 = 1/3、2/3 线上从边到平坦内部的厚度 +2 px。
- 其它：`split_tree.py`（树拆树冠/底座）、`make_shadows.py`（接触阴影）、`make_ui_states.py`（冷却遮罩/按下态）、`make_ui_screens.py`（U11–U13 整屏）、`make_portrait.py`（头像圆裁）、`make_fx_extra.py`（F08 平铺笔触、F12 Lilita One OFL 位图字体）、`style_fix_v3.py`（贴花/光/图标去白边）、`derive_face.py`（整脸拆五官）。

### 3.4 总览与对照图
- `python3 art_src/tools/make_overview.py docs/level1-art-overview-<date>.png <date>`：所有第一关资产按游戏比例（1080p，主角 135 px）拼一张，带 baseline 裁切对照。
- `python3 art_src/tools/make_combat_mock.py docs/level1-combat-mock-<date>.png /workspace/art_inbox/<date>/combat_mock_1080p.png <date>`：用切好的件拼 1080p 战斗画面，左新右 baseline。
- 新批次要改这两个脚本里的行/摆放列表（村落 mock 还没写）。

---

## 4. 提示词在哪
[art_src/prompts/](https://github.com/7mouse/stellar-abyss-greybox/tree/rig-trial/art_src/prompts)：21c–21g 共 53 次生成，逐字提示词 + 宽高比 + 输出尺寸 + 参考图（`refs/` 里是当时临时拼的参考图）+ 落库文件。**21c 之前的原图（画风探索 37 张、设定图、基准图、主角/野猪部件表、10-21 11:54 的 8 张批量表）提示词无法恢复**，清单见 prompts/README.md。

**统一提示词手册**：[06-art-direction/specs/PROMPTS.md](https://github.com/7mouse/stellar-abyss-design/blob/main/06-art-direction/specs/PROMPTS.md)（设计仓库，私有）。内容包括通用风格前缀和负面词、9 类资产的模板和采用版逐字提示词、已知坑、UI 文案规范与清单、缺失提示词清单。新出图先看这份。

---

## 5. 当前版本
| 资产 | 现行版本 | 文件 | 说明 |
|---|---|---|---|
| 主角 C01/C02 | **v2.3**（f/s/b） | `art_src/rigs/hero/hero_parts_{f,s,b}_v2_3*` | v2.2 眨眼 + v2.3 表情替换件（受伤/怒/开心）；b 表情为空结构层 |
| 主角头像 C03 | v1 | `art_src/ui/hud_v2/portrait/c03_hero_portrait_{512,256}.png` | |
| 发芽野猪 C04 | f **v1.1**，s **v2.2**，b **v1.2** | `art_src/rigs/sprout_boar/sprout_boar_parts_*` | s 有远侧耳、眨眼 |
| 小猪 C05 | **WIP，未做** | 只有小叶原图 `wip/2026-10-21g/src/piglet_leaf_gen1.jpg` | 计划见 §6 |
| 根须孢子菇 C06 | **v1.2** | `art_src/rigs/root_spore_mushroom/*_v1_2*` | 张嘴替换件、根须 2 段 |
| 史莱姆 C07 | **v1.2** | `art_src/rigs/slime/*_v1_2*` | 加内核 core |
| 深苔史莱姆 C08 | **v1.2** | `art_src/rigs/deep_moss_slime/*_v1_2*` | 苔垂挂、根刺；目标色板 |
| 苔冠王野猪 C09 | **v3** | `art_src/rigs/mosscrown_king_boar/*_v3*` | 冠/耳/獠牙单独件、鬃毛、2 段腿、怒眼、张嘴头；6 个结构空层 |
| 地表 S01–S09、S18 | floor1_v2（21e 修正） | `art_src/terrain/floor1_v2/` | 悬崖 / 森林层是 21e 的（矮、重复），新版原图在 WIP |
| HUD U01–U16 | hud_v2（21e 修正） | `art_src/ui/hud_v2/` | |
| 特效 F01–F15 | fx_v1 + fx_v2（21f） | `art_src/fx/` | F12 是字体工具做的 |
| 工具 | v6（21f） | `art_src/tools/` | |
| 参考姿势 | v2 | `art_src/rigs/_poses/*_poses_v2.json`（野猪只有 v1） | |

---

## 6. P0 进度：283/318，缺 35（全部是最后一批）
状态：只有 GenerateImage 原图（已入库 `art_src/wip/2026-10-21g/src/`），**都没切、没拆、没调色**，没有 manifest / 占地 / 排序点。

| 编号 | 项 | 数 | 规格 | WIP 状态 |
|---|---|---|---|---|
| C05 | 小猪 piglet | 2 | 复用 C04 部件 ×0.7，背芽换小叶，色板浅一档 | 小叶 f/s/b 原图有；缩放 op 没写，rig 没做 |
| S10 | 篝火 | 4 | 256，燃烧 4 帧 | 原图 4 帧有；帧间木柴有抖动，需按石圈对齐 |
| S11 | 层守区能量栅栏 | 6 | 256×128，循环 4 + 升起 2 | 原图 1 张（石柱+能量墙）；计划工具做帧动画；比规格高 |
| S12 | 宝箱 | 2 | 192，关/开 | 原图有 |
| S13 | 强化祭坛 | 1 | 256×320，光由 shader | 原图有 |
| S14 | 坠落坑（出生/回归点） | 1 | 320 | 原图有 |
| S15 | 倒塌路牌 | 1 | 192 | 原图有 |
| S16 | 萤苔泉 | 1 | 280，光由 shader | 原图有 |
| S17 | 倒伏巨木 | 2 | 512×192，底座 + 树冠 | 原图有；需工具拆两层 |
| S19 | #0000 墓碑 | 1 | 96×144 | 原图（空白碑面）有；"#0000" 要用字体刻，不用 AI 字 |
| V01 | 土路平铺 | 1 | 512 | 原图有，太亮太饱和；需压色 + make_tiles |
| V02 | 培养槽 | 2 | 384×512，底座 + 玻璃罩，气泡由 shader | 空槽原图 gen2 有；需拆玻璃层 |
| V03 | 保险箱 | 2 | 256，关/开 | 原图有 |
| V04 | 强化工坊 | 3 | 384，本体 + 火光 2 帧 | 本体原图有；火光帧计划工具做 |
| V05 | 下潜井（起点，电梯已砍） | 1 | 384 | 原图有 |
| V06 | 回层入口 | 1 | 384×192 | 原图有（符文圆台 + 2 灯柱） |
| V07 | 仓库 | 1 | 384 | 原图有 |
| V08 | 补给店 | 1 | 384 | 原图有 |
| V09 | 制作台 | 1 | 384×256 | 原图有 |
| V10 | 墓志墙（含 #0000 空位） | 1 | 640×192 | 原图有；牌匾上的“汉字”是 AI 假字，要换或糊掉 |
| | **合计** | **35** | | |

同批要修的 21e 问题（原图已有，未处理）：悬崖太矮（新高悬崖原图 `cliffs_tall_strip_gen2` + `cliffs_tall_ends_gen1`，石壁约 2.5 个主角高、上沿不规则；gen1 两张柱状的已否决）；树丛重复（新的 3 款不同树丛 `forest_clumps_gen2`：针叶+枯枝 / 阔叶矮丘 / 橡树+白桦+蕨）；树冠白点（未清理）。
建筑规则：按脚底 y 排序（pivot = 脚底中心）；交互点 = 正面（南）底边中点往下 40 px；高物件拆底座 + 树冠，主角在后面时树冠半透明 50%。村落布局见 polish-spec §7.2（地图 2400×1400）。还要做：村落 mock、21g 战斗 mock（摆地标）、21g 总览和清单。

---

## 7. 已知待修问题（诚实版，21d–21f 汇总）
**角色**
1. 主角 f `hip_r` ±30° 仍有 **2.2 px** 洞（v2.2 起就有，没修）；s `shoulder_r` 0.5；孢子菇 f hip_r / arm_root_l 0.5、b arm_root_r 0.2；苔冠王 s tail_root 0.2（都 <1 px，算抗锯齿）。
2. 苔冠王 v3 新头比 v2.1 略大、偏绿（已往旧色板拉 60%）；张嘴头脸小一圈，切换时轮廓会变。b 向鬃毛和头几乎全被身体挡住；背面耳是正面耳换色。
3. 闭眼替换件是工具取肤色填椭圆 + 一条线，近看像补丁（苔冠王正面最明显），建议 AI 重出真闭眼。
4. 主角正面怒眉被刘海挡住，攻击怒在正面不明显。
5. 孢子菇侧面张嘴只有约 10 px 高；s 向菌柄有一圈很淡的浅色环。
6. 苔冠王 6 个结构空图层计入 60 张，程序侧注意没有像素。
7. AI 味：苔冠王鬃毛（叶片规整）、深苔根刺（三根雷同）。
8. 宽配件转 ±30° 露出的是压暗的父件色块（隐藏延伸），不是真画出来的结构。
**地表 / 场景**
9. 整体偏亮、对比平，像晴天；baseline 更暗、有雾和明暗对比 → 需要程序侧场景色调（暗角 + 远景雾）。
10. 画面密度不够，中间大片空草地（地标进来会好些）。
11. 石板路按 512 格铺，路边是直线；没有弯路过渡件。
12. 悬崖面只有约 1 个主角高；悬崖段之间是原图自然断口，要重叠 10–20 px；上沿草皮是一条直线（新原图已生成未切）。
13. 背景树丛 / 前景树冠是同一张图两种颜色，重复能认出来（新原图已生成未切）。
14. 树冠边缘有 1–2 px 白点（白底抠图残留），未清理。
15. 边缘条偶尔带原图石头碎片；拐角只有一种半径 40 px，窄通道需程序验证。
16. 叶隙光要压到 25–35% add。
**UI**
17. HUD 很“平”，接近通用扁平 UI 套件；纸纹 0.08 远看几乎看不出（可提到 0.12–0.15）。
18. U11–U13 是线框式布局，作为美术图很空，没有角色立绘区。
**特效**
19. F10 拾取光原图太淡，alpha ×2.2 后边缘颗粒重；F14 和 F05 很像，靠大小方向区分。
**最后一批原图（WIP）预判**
20. 建筑原图细节偏密、偏写实（培养槽金属铆钉、工坊石砖），和 Q 版角色有距离，切完要降饱和、压细节对比；墓志墙假汉字是明显 AI 痕迹；新树丛比旧的写实。

---

## 8. 提交与约束
- 只提交到 `rig-trial`；**不用 LFS，单文件 <50MB，不 force-push**。
- 推送：`git -c credential.helper= -c credential.helper='!/usr/local/bin/gh auth git-credential' push origin rig-trial`
- 新原图放 `art_src/src/<批次>/`，提示词写进 `art_src/prompts/<批次>.md`，每批出清单 + 总览 + mock 到 `docs/`。

---

## 9. 工作机遗留文件（交接补充，2026-10-21 17:4x）
- **`art_src/tools/scratch/`**：一次性辅助脚本和它们的输出日志（连通块标号、坐标网格、PSD 查看、关节洞位置 / 可视化、v2→v2.1 指标），说明见 [scratch/README.md](https://github.com/7mouse/stellar-abyss-greybox/blob/rig-trial/art_src/tools/scratch/README.md)。路径写死在旧工作机上，用前要改；日常请用 `art_src/tools/` 里的正式工具。
- **`art_src/wip/debug/`**：保留的调试图（按原目录 l1/ rigv2/ v21/）：21c 原图连通块标号图、早期参考姿势图、部件总览、关节洞检查图、v2.1 洞位置图，说明见 [debug/README.md](https://github.com/7mouse/stellar-abyss-greybox/blob/rig-trial/art_src/wip/debug/README.md)。和仓库已有文件内容相同的没有重复提交。
- `art_src/prompts/refs/21f_ref_base.png`、`21f_ref_sprout_fb.png`：21f 时拼好的参考图，记录里的提示词没有用到它们，仅存档。

### 丢弃的文件（没有入库）及原因
| 文件 | 原因 |
|---|---|
| l1/dm_chk1.png、fx_contact.png、h_contact.png、t_contact.png；v21/bd2.png | 和仓库里已有文件逐字节相同 |
| l1/attach_sheet.png（4 MB） | 工作机上全部生成图的缩略图索引，原图已入库、提示词在 prompts/；可能混有作废探索图，没有价值 |
| l1/b_v1、bb、bf、bfh、bsh、blink1、ear、ear2、face1、hf、hs、kfh、ksh、tail、mf、shell、shell_cut、sw、k2p、k2q、k_v2a、m_v1、m_v2、bars、bars2、bars3、t_tile、ov_small（.png） | 21c 切图时的一次性放大 / 单件预览、中间版本，最终结果已在 rigs/ terrain/ ui/ 的 preview / contact / overview 里 |
| rigv2/b、f、s、b_arms、boar、boar2、boar3、hb2–hb4、hf2、hs2、hs3、pb、pf、mouth、zb1、zb2、zk、zk2、zs1、zs2（.png） | v2 拆件时的整图 / 局部放大预览，最终 v2 / v2.1 preview 和对照图已入库 |
| rigv2/hero_palette_src.png、sprout_boar_palette_src.png、pal2.png | 早期色板草稿，已被 rigs/ 下的正式色板取代 |
| v21/ 其余 png（boar_far*、boar_v2/v21_full/solo、fr_b*、hb/hf/hs_full_a/b、*_solo、dbg2、neck_s） | v2.1 对照图的中间渲染，最终版已入库为 `*_v2_vs_v2_1_*.png` |
| v21/tmp/（26 MB：无圆头 PSD、部件 png、配准 PSD） | metrics.py 用的中间产物，可以用 rig_patch 关掉圆头重新生成；体积大、没有独立价值 |
| v21/__pycache__/ | Python 缓存 |
