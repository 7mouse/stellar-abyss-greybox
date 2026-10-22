# HUD v2 · 21e 风格修正（2026-10-21e，现行）
- **纸纹**：`make_ui_v2.py` 的 `paper`（`hud_v2.json` 里 0.08）给九宫件的中间区和固定件的深色部分叠一层很淡的纸纹（低频斑 + 横向细纤维）。纸纹按中间区尺寸做成**周期**的（FFT 噪声），所以引擎里中间区用 TILE 模式铺开不会出缝；用 STRETCH 也行，只是纹理会被拉开。四个角和边都不动，九宫边距不变（见下）。另出 `panels/ui_paper_grain_tile_256.png`（256 无缝灰度纹理），需要的话程序可以自己用 multiply 叠到任何面板上。U08 小图标不加纸纹。
- 渲染到别的尺寸（U11–U13、mock）时用 `nine(..., tile_center=True)`，中间区平铺而不是拉伸。
- **U16 物品图标 gen2**：9 个按同一张图重新生成（`src/ui_v2/u16_icons_gen2.jpg`），统一深色描边、Q 版手绘、平涂加少量明暗，没有光晕；`u16_icons_gen1_unused.jpg` 是 21d 的水彩版。切图 `cut_sprites.py art_src/ui/u16_icons_cut.json`（7 个按点选 pick，戒指加了 `open_holes` 把中间白底挖空；萤苔、獠牙按格子），然后 `style_fix_v3.py` 收 1 px 白边、居中放进 128×128（留 6 px）。

---

# HUD v2 细边框（hud_v2，2026-10-21d，现行）
原图在 `art_src/src/ui_v2/`，用 GenerateImage 生成，按 ui_style_v1 定稿 v2 写提示词：细线、炭黑底、米白线，少量绯红和青；不要钉子、宝石、金属斜面、厚花边。
生成和切图：`python3 art_src/tools/make_ui_v2.py art_src/ui/hud_v2.json`，图标 `cut_sprites.py art_src/ui/u16_icons_cut.json`，冷却 / 按下态 `make_ui_states.py art_src/ui/hud_v2/hud/u06_heavy.png art_src/ui/hud_v2/states`，整屏 `make_ui_screens.py art_src/ui/hud_v2 art_src/ui/hud_v2/screens`。清单和九宫边距在 `hud_v2/manifest_v2.json`。

**九宫安全**：每个框都由工具重建。四个角保留 AI 原图的像素，四条边各取原图边中间的一列（一行）重复铺满，中间是一种平色，所以怎么拉伸都只拉直线，不会把花纹拉变形。底板炭黑设为 85% 不透明（半透明底板）。

| 文件 | 尺寸 | 九宫 左/右/上/下 | 规格 |
| --- | --- | --- | --- |
| bars/u02_bar_frame + u02_fill_hp/mp/sp | 480×32；填充条 8×22 | 10/10/8/6 | U02：先画底框，再画填充（内缩 4 px，x 方向按比例拉伸或裁切） |
| bars/u10_boss_bar_frame + u10_fill_boss | 960×48 | 8/8/7/6 | U10 |
| icons/u10_boss_icon | 64 | — | U10 图标（苔冠王 v2 头部部件放进圆环） |
| frames/u07_slot | 160 | 13/13/13/12 | U07 |
| frames/u15_quality_frame + _grey/_moss/_teal/_purple/_gold | 128 | 13/13/13/13 | U15：米白线可由 shader 着色；5 色是预览 |
| frames/u03_level_badge | 96 | — | U03 |
| panels/ui_panel_window、ui_header_plate、ui_button、ui_button_hi | 515×300、442×80、152×62 | 13/15/14/14、15/16/11/11、14/14/12/12 | U11–U13 的拼装件 |
| panels/u14_card | 360×520 | 14/14/14/14 | U14（顶部圆形图标位单独贴上） |
| hud/u01、u04、u05、u06×4、u08×3 | 256、512、256、160、128 | — | 顺手按同一风格重画，替换 v1 的厚边版（U01、U04 中间挖空） |
| states/u09_* | 160 | — | U09 |
| icons_u16/u16_*（9 个） | ≤128 | — | U16 |
| screens/u11_backpack、u12_extract_result、u13_vault_storage | 1920×1080 | — | 用上面的件拼出布局，没有文字；坐标在 `screens/layout.json` |

已知问题：整体很平，像通用扁平 UI 套件，没有手绘质感；U11–U13 是线框式布局，很素；U16 图标是偏写实的水彩风，没有深色描边，和按钮风格不统一；萤苔图标的光晕切成了浅色底。

---

# HUD v1（hud_v1，2026-10-21c，已被 v2 取代）
来源 `art_src/src/hud_set_gen1.jpg`，`cut_sprites.py art_src/ui/hud_cut.json`；清单、尺寸、九宫边距在 `hud_v1/manifest.json`。

- **工具调色**：金色边框和图标饱和度降到 45–60%（`muted_frame`/`muted_icon`/`muted_quality`）；状态条的红/蓝/黄填充换成 ui_style_v1 的低饱和色：HP `#964038`、MP `#4C6E86`、SP `#968454`。原版蓝/黄条留在 `bars/_src/` 备查。
- **状态条 U02**：`u02_bar_frame.png`（炭黑底）→ 填充 `u02_fill_{hp,mp,sp}.png`（按比例裁 x）→ `u02_bar_overlay.png`（外框 + 中间菱形钉，填充区挖空）。九宫：左右 38、上 11、下 12；中间菱形钉不能拉伸，必须放在 overlay 里居中单独画。
- **九宫边距**（px，按 1/3、2/3 线测边框厚度 +2）：`u07_slot_square` 22/22/26/23（左/右/上/下）；品质框 `u15_*` 约 23–27 / 30–39；每条边中点都有菱形钉，拉伸时会变形，要么拆出来叠加，要么只按固定尺寸用。
- 规格对应：U01 头像框、U02（4）、U04 小地图外圈（箭头画在里面）、U05 攻击键、U06 4 个、U07 消耗品格、U08 背包/碎片/暂停、U09 冷却遮罩和按下态（工具生成）、U15 品质框（5 色都有，用 1 张灰色由 shader 着色）。没有：U03 等级徽章、U10 层守血条+图标、U11–U14 整屏界面、U16 物品图标（只有碎片 1 个）。
- **没解决的**：边框又厚又花（金属镶边 + 菱形钉），制作人不喜欢，工具只能降饱和，不能变细；要细框需要重新生成。

# C03 主角头像（2026-10-21f）
来源 `art_src/src/v21f/hero_portrait_gen1.jpg`（GenerateImage，D 比例约 6.5 头身胸像，定稿 v2 画风，以 hero rig 和定稿图做参考）。`make_portrait.py` 找到圆盘、往里收 6 px、做抗锯齿圆形 alpha → `hud_v2/portrait/c03_hero_portrait_{512,256}.png`。放在 U01 头像框里面（mock 里缩到 116 px，框 132 px）。
