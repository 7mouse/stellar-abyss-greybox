# 第 1 层地表 v2（floor1_v2，2026-10-21d，现行）
全部重新生成：GenerateImage，参考 combat_baseline_v2，提示词写的是日式手绘、软笔触、低饱和、高俯视，不要写实噪点、不要像素。原图在 `art_src/src/terrain_v2/`，名字带 `_unused` 的是没采用的版本。

| 步骤 | 命令 / 配置 |
| --- | --- |
| 平铺 + 边缘 + 拐角 | `python3 art_src/tools/make_tiles.py art_src/terrain/terrain_floor1_v2_tiles.json` → `floor1_v2/tiles/`、`edges/`，`manifest_tiles.json` 里有接缝比值 |
| 石头 / 废墟 | `cut_sprites.py art_src/terrain/terrain_floor1_v2_rocks_ruins.json` → `props_rocks_ruins/` |
| 灌木 / 菌环 / 苔藓贴花 | `cut_sprites.py art_src/terrain/terrain_floor1_v2_bushes_decals.json` → `props_bushes_decals/` |
| 叶隙光斑 | `cut_sprites.py art_src/terrain/terrain_floor1_v2_leaflight.json` → `light/`（黑底，alpha 取亮度，叠加模式） |
| 大树 | `split_tree.py <src> art_src/terrain/floor1_v2/trees s03_tree_autumn 512 768 0.02,0.11`（绿树用色相 `0.15,0.45`）→ 整树 / `_crown` / `_base`，同画布可直接叠；`.json` 里有排序 y |

- **平铺 512**：1024 原图整张缩到 576（只缩不放），再用最小误差切缝环绕成 512：越过边界的 64 px 沿差异最小的曲线接回对边，切缝两侧只羽化 2 px，不做交叉淡化，所以没有重影。接缝比值（≤1.6 算过）：苔绿 1.09/1.02，秋色 1.00/0.99，灰石 1.15/0.89，大块灰石 1.03/0.92，水面 0.74/1.12。苔绿降了饱和、压暗了一点（desat 0.78，val 0.93），和 baseline 的地面接近。
- **边缘 512×128**：透明叠加条，只盖住交界线。原图是上下两种地面，按颜色抠出上面那种的边缘（草簇 / 落叶）；交界线在第 88 行，上面的地面放在线以上。`s02_edge_moss_stone`：苔绿在上、灰石在下。`s02_edge_autumn_moss`：秋色在上、苔绿在下（原图上下翻转后抠落叶）。x 方向同样做了切缝环绕（0.97 / 1.00）。竖边把条旋转 90°。
- **拐角 128×128**：直边条沿圆角（半径 40）做极坐标弯曲。`_corner_outer`：上面那种地面占左上象限；`_corner_inner`：除右下象限外都是上面那种地面。中心 (64,64) 对准格子交点；其他朝向用翻转得到。
- 用法示例见 `art_src/tools/make_combat_mock.py`（石路两侧的直边、内拐角，秋色格的外拐角）。
- 已知问题：小卵石形状太规则；边缘条偶尔带几块原图里的石头碎片；苔藓贴花颜色太浅、像贴纸；512 网格的直线在石路两侧还看得出。

---

# 第 1 层地表 v1（floor1_v1，2026-10-21c，已被 v2 取代，留作对照）
来源 `art_src/src/terrain_floor1_set_gen1.jpg`，`cut_sprites.py art_src/terrain/terrain_floor1_cut.json` 切出，清单和接缝分数在 `floor1_v1/manifest.json`。

- `tiles/`、`edges/`：`<name>.png` 是原图直切（137–140 px 方块，水 120 px；边缘条 772×60）。**原样都不无缝**：环绕边差 / 内部相邻差 = 2.7–3.4（横向）、1.5–2.1（纵向），判定线 1.6。`<name>_seamless.png` 是工具修过的版本（半偏移交叉淡化），比值降到 0.9–1.6；代价是中间一圈有重影、变软（灰石最明显）。`_seamless_512.png` 是放大到规格 512 的版本，原图分辨率不够，会糊。`*_tiling_check.png`：左边原图 2×2，右边修过的 2×2。
- 规格对应：S01 苔绿 / 灰石 / 水面有，**秋色没有**（`s01_ground_roots` 是根须泥地，额外）；S02 只有两条直边（苔↔石墙、苔↔根须），没有拐角，也不是规格要的苔绿↔秋色。
- `props/`：灌木 2、矮灌丛 1（S04）、废墟 2（S06）、大石 1（S05）、发光蘑菇丛（S18）、树桩 2（装饰，不是 S03 大树）。`decals/`：苔藓斑块（S07）。`shadows/`：接触阴影 3 档（S08，工具生成）。
- 画风：整体偏写实、细节密，和角色的日式手绘不完全统一；发光蘑菇边缘带白色光晕（原图的光在白底上）。
