# art_src/tools

| 脚本 | 用途 |
| --- | --- |
| cut_partsheet.py | AI 部件拼图 → 分层 PSD。v2：配置里写了 `joints` 就自动跑圆头（先出 `<base>_raw*`，再出 `<base>`）；`--no-caps` 关掉。 |
| rig_patch.py | 不重生成，直接升级已有 PSD：平移/对齐/裁切/接回前臂（swing_attach）/重设枢轴点 + 关节圆头 + 去白边/补洞，导出 1:1、2x、预览、pivots。 |
| rig_joints.py | 公共函数：round_cap（圆头延长+重描线）、line_color、defringe、fill_holes、palette、joint_gap_test。 |
| rig_check.py | 关节自检：子部件（连同下级）绕枢轴点 ±15/±30° 旋转，统计关节附近露出的空洞像素，并出对照图。 |
| make_palette.py | k-means 源色板横条（8–16 色，含描边色和高光色）。 |
| rig_compare.py | 合并 f/s/b 为分组 PSD + 合并预览；v1 vs v2 对照图。 |

依赖：numpy、scipy、pillow、psd-tools（不需要 sklearn）。
关节配置示例见 art_src/rigs/*/*_fix_v2.json。重叠范围（1:1）：small 4–8（前臂、小腿、手、耳、尾巴、芽），big 10–20（身体、头、大腿/上臂根部）。

v2.1（2026-10-21b）：配置写 `"cap_version": 2` 用 round_cap2。上层部件的圆头只长在父部件上，并复制父部件像素；隐藏圆头只长在上层盖住的地方，先擦旧切口线，再逐列从内部取色。另外新增 `post_ops: erase_outline_over`（擦远腿上方的身体轮廓）和 `solidify`（补实半透明裂缝）。
`rig_compare.py rotsheet OUT.png old_fix.json new_fix.json neck,knee_r,... --labels v2 v2.1` 出静止+±30° 对照；`rig_check.py ... --labels v2 v2.1`。示例配置见 `art_src/rigs/*/*_fix_v2_1.json`。

## v3（2026-10-21c，第一关批量）
| 脚本 | 用途 |
| --- | --- |
| cut_partsheet.py | 新键：`canvas2x_h`（非正方画布，史莱姆 512×384）、`k`（固定缩放，让 f/b 和已有 s 同比例）；每个部件可写 `source`、`png`（预切好的部件，如五官）、`clip`、`flip_h`、`scale_x`、`swap`（替换件，存为隐藏图层）、`drop_dark`/`alpha_mul`（软高光）、`recolor_ref`（按参考区域逐通道直方图匹配换色）、`cut_dark_in`（挖掉壳内暗腔）、`keep_holes`（重新挖开尾巴圈里的白底）。joints 现在会把 `cap_version`/`post_ops` 等一起传给 rig_patch。 |
| rig_patch.py / rig_check.py | 隐藏图层（替换件）不进预览、不当圆头的遮挡、不进自检。rig_check 加 `--seam-band N`：只统计父部件边缘 N px 内的洞（菌盖、卷尾、苔冠这类宽配件转动时露出的是自身轮廓变化，不是接缝）。 |
| rig_extras.py | 在已有版本上加工具生成的图层 → 新版本：`blink`（eye_open = 头部自身像素；eye_closed = 眼周取肤色填充 + 描边色眼睑线，隐藏）、`dup_layer`（远侧耳）、`open_white`、`empty`（结构用空图层）。 |
| derive_face.py | 把 AI 画的整张脸拆成可浮动的五官（眼 L/R、嘴、腮红），颜色去掉底色混合。 |
| make_target_palette.py | 换色版目标色板，与源色板逐格对应（同 recolor_ref 的映射）。`make_palette.py` 加 `--layers`。 |
| cut_sprites.py | 地表/HUD/特效整图切成单张 PNG + manifest + contact。贴图做接缝检测（环绕边差 / 内部相邻差，>1.6 判为不无缝）并出半偏移交叉淡化的 `_seamless` 版和 2×2 平铺对照；状态条拆底框/填充/上层边框；九宫边距估算；HSV 降饱和/换色。 |
| make_ui_states.py / make_shadows.py | U09 冷却遮罩和按下态、S08 接触阴影，按轮廓/椭圆由工具生成。 |
| ref_poses.py | 用骨骼本身（绕 _pivots 转）渲染参考关键姿势表。 |
| make_overview.py | 第一关总览拼图（1080p 游戏比例，主角 135 px）。 |

## v4（2026-10-21d，地表 + HUD 重画）
| 脚本 | 用途 |
| --- | --- |
| make_tiles.py | 无缝平铺：生成图只缩不放，用最小误差切缝（image quilting）环绕，不交叉淡化，没有重影；带接缝比值。边缘透明叠加条：按颜色抠出上面那种地面，交界线固定在第 88 行；`flip` 用于从下面那种地面抠。拐角：直边条做极坐标弯曲，有外拐角和内拐角。 |
| split_tree.py | 白底上的单棵树拆成树冠和底座：按叶子色相找出树冠，零碎的小块归到合适的一边；树枝间漏出的白纸设为透明。 |
| make_ui_v2.py | UI 件按九宫安全规则重建：保留四个角，边取中间一列（一行）重复，中间平色，底板 85% 不透明。还有填充条（竖向明暗剖面 × 目标颜色）、描边着色预览、圆环挖空、图标嵌入。 |
| make_ui_screens.py | U11–U13 整屏布局，用九宫件拼成。 |
| make_combat_mock.py | 战斗对照图（1080p，主角 135 px）：新地表、道具、角色、HUD 和 combat_baseline_v2 并排。 |
| cut_sprites.py | 加了 `black`（黑底的光，alpha 取亮度）和 `max`（只缩小，缩到规格尺寸以内）。 |

## v5（2026-10-21e，风格修正）
| 脚本 | 用途 |
| --- | --- |
| make_tiles.py | 加 `variants`：`variant(A, B)` 保留 A 离边 40 px 的外圈，内部换成 B（或 A 自己错位），内外沿最小误差曲线切换，所以 A 和它的变体能任意混铺。`h_cut` 是横向切缝的辅助函数。 |
| style_fix_v3.py | 苔藓贴花 v3（取地面色、降饱和、软而不规则的 alpha 边）；叶隙光 v3（偏冷、软边）；U16 去白边并放进 128 方格。 |
| cut_sprites.py | pick 项可加 `open_holes`：被包住的白底也设为透明（戒指中间）。 |
| make_ui_v2.py | `paper`：中间区叠周期纸纹（TILE 安全），固定件的深色部分也加；`tile_center=True`：渲染到别的尺寸时中间区平铺；另出 256 纸纹平铺图。 |
| make_combat_mock.py | 场景加了悬崖带、背景树丛、前景树冠、石板变体随机选（seed 11）、散布灌木和石头。 |
| make_overview.py | 第二个参数是日期；加了石板变体、贴花 / 光 v3、悬崖和森林层一行。 |
