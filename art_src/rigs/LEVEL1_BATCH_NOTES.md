# 第一关美术批次 2026-10-21c

全部是 AI 原图直接用工具切，不手修（制作人约定）。新增或改的工具见 `art_src/tools/README_rig_tools.md` 的 v3 一节。
复现（仓库根目录）：

    # 怪物拆件（joints + cap_version 2 = v2.1 关节做法）
    python3 art_src/tools/cut_partsheet.py art_src/rigs/<name>/<name>_<f|s|b>_cut*.json
    # 眨眼替换件 / 远侧耳 / 结构空图层
    python3 art_src/tools/rig_extras.py art_src/rigs/<name>/*_extras_*.json
    # 关节自检（±15/±30°）
    python3 art_src/tools/rig_check.py art_src/rigs/<name>/<base>_fix.json --seam-band 4 --labels - v1 --sheet <base>_jointcheck.png --json <base>_jointcheck.json
    # 参考姿势
    python3 art_src/tools/ref_poses.py art_src/rigs/_poses/*_poses_v1.json
    # 地表 / HUD / 特效
    python3 art_src/tools/cut_sprites.py art_src/terrain/terrain_floor1_cut.json   # ui/hud_cut.json, fx/fx_cut.json
    python3 art_src/tools/make_overview.py docs/level1-art-overview-2026-10-21c.png

## 现行版本（程序导入用这些）
| 角色 | 朝向 / 文件 | 部件 PNG |
| --- | --- | --- |
| 主角 hero | `hero_parts_{f,s,b}_v2_2*.psd`，`parts_v2_2/` | 39 + 眨眼 6（f 开/闭 L/R、s 开/闭 R；s 的 L 和 b 的 4 个是空图层） |
| 发芽野猪 sprout_boar | f `sprout_boar_parts_f_v1_1`（`parts_f_v1_1/`）、s `sprout_boar_parts_s_v2_2`（`parts_v2_2/`）、b `sprout_boar_parts_b_v1_1`（`parts_b_v1_1/`） | 11 + 12 + 7 |
| 根须孢子菇 root_spore_mushroom | `root_spore_mushroom_parts_{f,s,b}_v1_1`，`parts_{f,s,b}_v1_1/` | 13 + 9 + 6 |
| 史莱姆 slime | `slime_parts_v1_1`（256×192，1 向），`parts_v1_1/` | 8 |
| 深苔史莱姆 deep_moss_slime | `deep_moss_slime_parts_v1_1`，`parts_v1_1/`；目标色板 `deep_moss_slime_palette_target` | 10 |
| 苔冠王野猪 mosscrown_king_boar | `mosscrown_king_boar_parts_{f,s,b}_v2_1`（320×320，重画版），`parts_v2_1/`；备用件 `spares_v2/` | 27 + 备用 7 |

替换件（eye_closed_* 等）在 PSD 里是**隐藏图层**，pivots.json 的 `swap` 列出名字；预览 `*_preview_swaps.png` 显示闭眼状态。

## 做法和取舍
- **原图选择**：史莱姆用 gen2（眼、嘴、高光是分开的部件，gen1 双眼连在一起）。苔冠王野猪 gen1 偏写实，按负责人要求重新生成了 `mosscrown_king_boar_partsheet_v2_gen1.jpg`（日式手绘、Q 版、低饱和，参考野猪部件表和基准图），用 v2 切；gen1 不再用。
- **野猪 f/b 对齐 s**：固定缩放 `k`（f 1.42、b 1.54），让身高和侧面一致；颜色和侧面共用 `sprout_boar_palette_src`（f/b 像素到色板的平均距离 11.8/11.7，侧面自己是 10.9）。正面头部自带耳朵（原图如此），所以正面没有单独的耳朵部件；背面看不到头，`head_b` 是空图层。
- **侧面远侧耳 `ear_far_s`**：复制 `ear_s`，向鼻子方向移 (28,−12)，压暗 18%，放在头后面，枢轴 `ear_far_root`。同时把侧面尾巴圈里被填成白色的洞重新挖开。
- **眨眼**：`eye_open_*` 就是头部原来的眼睛像素（静止时完全一样）；`eye_closed_*` 用眼周的肤色（眼周一圈取较亮的一半的中位色）填椭圆，再画一条描边色的眼睑线。f/s 有眼睛的朝向都做了；背面是空图层。史莱姆、孢子菇的眼睛本来就是单独部件，只加闭眼。
- **孢子菇**：脸是一整张圆盘，用 `derive_face.py` 拆成眼 L/R、嘴、腮红，浮在菌柄上；侧面用同一只眼压窄 25%。根须只有 1 段（规范要 2 段），嘴只有闭合。
- **深苔史莱姆**：身体用史莱姆的身体，按原图深苔身体区域逐通道换色（同一映射生成目标色板）；外壳挖掉内侧暗腔；苔簇 `moss_tuft`。破壳时隐藏 `shell` + `moss_tuft`。
- **苔冠王野猪 v2**：头部原图里苔冠、耳朵、獠牙是画在一起的，所以 f/s 的头是一整块；背面苔冠是单独部件。腿只有 1 段（规范 2 段），没有鬃毛 mesh、怒眼替换件。备用件（苔冠、发光芽、耳 L/R、獠牙 L/R、尾巴）在 `spares_v2/`。

## 关节自检（±30°，px@1:1；`worst` = 旧口径，`seam` = 父部件边缘 4px 内）
| 角色 | 结果 |
| --- | --- |
| 野猪 f v1 | 全部 0 |
| 野猪 b v1 | 腿、芽 0；`tail_root` 40.5 / seam 13.8（卷尾转动露出的是尾巴自己的轮廓变化，见 jointcheck 图） |
| 孢子菇 f/s/b | 根须 0（侧面 hip_r 4.2 / 2.5）；手 2.2–8.2；`cap_root` 166–455 / seam 55–67：菌盖很宽，转 30° 时盖沿离开背景，不是接缝；实际动作菌盖只摆 ±10° |
| 苔冠王 f | 全部 0 |
| 苔冠王 s | 头、腿 0；`tail_root` 12.8 / 7.0 |
| 苔冠王 b | 头、腿、尾 0；`crown_root` 55.5 / 40（苔冠是宽配件，同上） |
| 主角、野猪 s | 关节没动，沿用 v2.1 结果（只有正面 hip_r 0.8） |
史莱姆、深苔史莱姆没有转动关节（全身形变），不做此项。

## 参考动作
`<name>/ref/<name>_ref_poses_v1.png`：主角、野猪、孢子菇（侧面）、史莱姆、深苔史莱姆、苔冠王（侧面），都有待机 / 移动 / 攻击 / 受击，苔冠王另有号令咆哮 3 个关键姿势（前蹄扬起、身体后仰、张嘴）。由骨骼直接转出来，节奏写在每行左边。张嘴、怒眼没有替换件，第 3 个咆哮姿势只能抬头示意。

# 2026-10-21f：缺件补齐（第 4 项）
新原图都在 `art_src/src/v21f/`（GenerateImage，按现有 rig 和定稿 v2 做参考图；工具裁切，不手绘）。当前版本：

| 角色 | 版本 | 本批加了什么 |
| --- | --- | --- |
| 主角 | f/s/b **v2.3** | 表情替换件 `expr_hurt/angry/happy_{f,s}`（`hero_expressions_gen1`，按头部 alpha IoU 0.90 对位，只取脸部肤色区，头发不跳）；中性 = 头本身；b 是空的结构图层。正面怒眉被刘海挡住，看起来主要是眼神变化 |
| 根须孢子菇 | f/s/b **v1.2** | 张嘴替换件 `mouth_open_{f,s}`（b 空）；根须拆成 2 段 `root_{r,l}_{a,b}_*`，膝点 `root_mid_{r,l}` 选在根干最细的那一行（主干 / 根爪交界）；菌盖、手、根下面都加了隐藏延伸 |
| 发芽野猪 | b **v1.2** | 只加卷尾下面的隐藏延伸（`underfill`），其它不变 |
| 史莱姆 | **v1.2** | C07 内核 `core`（半透明 0.5，在身体和高光之间） |
| 深苔史莱姆 | **v1.2** | 内核 + C08 `moss_hang`（苔垂挂 2 条）+ `root_spikes`（根刺 3 根，压暗 0.82，在苔壳下面）；身体高光的彩虹斑降饱和修掉 |
| 苔冠王 | f/s/b **v3** | 换成**不带配件的 AI 头**，苔冠、耳 L/R、獠牙 L/R 都是单独件（`spares_v2/` 原图件）；鬃毛 `mane_{f,s,b}_mesh`（`king_boar_mane_gen1`）；4 条腿各 2 段（`leg_*_{a,b}_*`，膝点 `knee_*`）；怒眼 `eye_angry_*`、张嘴头 `head_roar_{f,s}`（替换件）；苔冠 / 耳 / 獠牙 / 尾 / 膝下面都有隐藏延伸 |

每向 20 件（苔冠、头、獠牙 L/R、耳 L/R、鬃毛、身体、前腿 L/R×2、后腿 L/R×2、尾、眼 开/闭/怒），另加 1 张张嘴头。**结构性空图层**（这个方向看不到，图层在但没像素）：f `tail_f`；b `tusk_{r,l}_b`、`eye_open/closed/angry` 3 组、`head_roar_b`。s 的远耳、远獠牙画了（压暗 0.8），基本被头挡住。b 的鬃毛被身体挡住，只在头转动时露出。

## 关节自检 21f（±30°，px@1:1；`worst` / `seam`）
| 角色 | 结果 |
| --- | --- |
| 苔冠王 f v3 | 全部 0/0（14 个关节：头、耳×2、獠牙×2、苔冠、肩×2、髋×2、膝×4） |
| 苔冠王 s v3 | 全部 0/0，只有 `tail_root` 0.2/0.2（15 个关节） |
| 苔冠王 b v3 | 全部 0/0（13 个关节） |
| 孢子菇 f v1.2 | `cap_root` 0/0（旧 455.2/67）；hip_r 0.5、arm_root_l 0.5，其它 0 |
| 孢子菇 s v1.2 | 全部 0/0（旧 cap 165.8/57） |
| 孢子菇 b v1.2 | `cap_root` 0/0（旧 239.5/55）；arm_root_r 0.2，其它 0 |
| 野猪 b v1.2 | 全部 0/0（`tail_root` 旧 40.5/13.8） |
| 主角 f/s/b v2.3 | b 全 0；s shoulder_r 0.5；f hip_r 2.2（v2.2 同一口径也是 2.2，替换件没改关节） |

隐藏延伸的代价：苔冠、菌盖转到 ±30° 时，原来被盖住的地方露出的是父部件颜色压暗（0.72–0.8）的一块，不是背景。苔冠那块看起来像一层暗色苔垫，菌盖那块像菌盖下面的阴影。实际动作只转 ±10° 左右，基本看不到。

## 参考动作 v2
`<name>/ref/<name>_ref_poses_v2.png`（配置 `_poses/<name>_poses_v2.json`）：苔冠王咆哮第 3 个姿势用**真的张嘴头** `head_roar_s` + 怒眼，冲撞的蓄力 / 冲出也用怒眼，走路加了膝盖弯曲；主角新增“表情”一行（中性 / 受伤 / 攻击怒 / 开心），攻击用怒，受击用受伤；孢子菇吐孢时张嘴，根须膝盖弯曲；深苔史莱姆破壳时隐藏苔壳、苔簇、苔垂挂、根刺。替换件一览：`*_swapsheet.png`。
