# 主角 / 发芽野猪 部件 v2（2026-10-21）

来源：rig-trial ce37efe 的 v1 部件（src2x PSD），未重新生成图，全部脚本处理。
复现（在仓库根目录）：
    python3 art_src/tools/rig_patch.py art_src/rigs/hero/hero_{f,s,b}_fix_v2.json art_src/rigs/sprout_boar/sprout_boar_s_fix_v2.json
    python3 art_src/tools/rig_check.py <fix.json> --prev <v1_src2x.psd> <v1_pivots.json> --sheet ... --json ...
    python3 art_src/tools/make_palette.py art_src/rigs/hero/hero_palette_src 13 art_src/rigs/hero/hero_parts_{f,s,b}_v2_src2x.psd

## 交付
- 每个朝向：`*_v2.psd`（1:1，256²）、`*_v2_src2x.psd`（512²）、`*_v2_preview.png`、`*_v2_pivots.json`（含每个关节的重叠量日志）、`parts_v2/*.png`（1:1 整画布）。
- 主角合并：`hero_parts_v2.psd` / `hero_parts_v2_src2x.psd`（组 f/s/b，结构同 hero_parts_v1.psd）、`hero_parts_v2_preview.png`。
- 色板：`hero_palette_src.png`（12 色）、`sprout_boar_palette_src.png`（11 色），16×16/格；index 0 = 描边色，最后一格 = 高光，中间由暗到亮；同名 .json 给 hex。
- 对照：`*_v1_vs_v2.png`；关节自检：`*_v2_jointcheck.png/.json`。
- 图层名、顺序与 v1 完全一致（没有改绘制顺序），`_pivots` 层仍是品红点。

## 改动
- 所有关节端：沿骨骼方向加半椭圆圆头，侧向半径 = 部件自身末端宽度（吃掉平切角，不留缺口），颜色从部件内部挤出，外圈重描线（描边色取自真实线稿像素）。原有像素一律不删。
  - 压在上层、看得见的一端取区间下限 +1px（小件 ≈5，大件 ≈11）；被盖住的一端取接近上限（小件 ≈7.5，大件 ≈19.5）。
  - 大腿/上臂的远端（膝、肘）按小件 4–8 处理；根部（髋、肩）按大件 10–20。
  - 侧面脖子：头压在躯干上，所以改为躯干领口往上长，且只长在头的下面（静止时看不见，转头时补缝）。
- 正面：右臂（上臂+前臂+肩/肘/腕点）整体内移 10px；围巾左移 23px，领口中心 = neck x（120）；围巾顶部按下颌弧线裁掉 28px，嘴（y84–86）完全露出；围巾与头部（下巴+脖子）重叠 14–17px，与胸口重叠约 27px（围巾本身是披挂，未裁短）。
- 背面：forearm_r_b 原先在护腕外侧约 8px 悬空，绕手腕点转 30° 让肘端压进护腕 6px（手位置基本不变，前臂变成垂直下垂）；forearm_l_b（连同 sword_b）向躯干内移 4px，肘点重设到前臂与上臂的重叠中心。
- 野猪：leg_front_l_s 肩点移到肚子边缘，腿根向上接入约 10px（在身体下层，看不见）；尾巴根圆头 7px。
- 清理：去白边（边缘偏亮像素换成内部颜色）；head_s 耳后 v1 去红留下的洞已用周边颜色平滑填上。

# v2.1（2026-10-21b，按程序对 v2 的反馈）

来源仍是 v1 src2x PSD，全部脚本处理，没重新生成图。v2 文件原样保留，v2.1 是新文件（`*_v2_1*`、`parts_v2_1/`）。
复现（仓库根目录）：

    python3 art_src/tools/rig_patch.py art_src/rigs/sprout_boar/sprout_boar_s_fix_v2_1.json art_src/rigs/hero/hero_{f,s,b}_fix_v2_1.json
    python3 art_src/tools/rig_check.py art_src/rigs/hero/hero_b_fix_v2_1.json --prev art_src/rigs/hero/hero_parts_b_v2_src2x.psd art_src/rigs/hero/hero_parts_b_v2_pivots.json --labels v2 v2.1 --sheet art_src/rigs/hero/hero_parts_b_v2_1_jointcheck.png --json art_src/rigs/hero/hero_parts_b_v2_1_jointcheck.json   # f/s 和野猪同理
    python3 art_src/tools/rig_compare.py rotsheet art_src/rigs/hero/hero_b_v2_vs_v2_1_rot.png art_src/rigs/hero/hero_b_fix_v2.json art_src/rigs/hero/hero_b_fix_v2_1.json neck,knee_r,knee_l,elbow_r --labels v2 v2.1
    python3 art_src/tools/rig_compare.py combine art_src/rigs/hero/hero_parts_v2_1 art_src/rigs/hero/hero_parts_{f,s,b}_v2_1.psd

配置里写 `"cap_version": 2` 就走新的 `rig_joints.round_cap2`；不写还是 v2 的 round_cap，重跑 v2 配置和仓库里的 v2 结果逐像素一致（已核对）。

## 交付
- 每个朝向：`*_v2_1.psd`（256²）、`*_v2_1_src2x.psd`（512²）、`*_v2_1_preview.png`、`*_v2_1_pivots.json`（log 里记录了每个关节的圆头、擦线数量和 post_ops）、`parts_v2_1/*.png`；主角合并 `hero_parts_v2_1.psd` / `hero_parts_v2_1_src2x.psd` / `hero_parts_v2_1_preview.png`。
- 图层名、顺序、`_pivots` 层和 v2 一样。色板 `*_palette_src.png/json` 没改（md5 和 v2 相同）。
- 对照图：
  - 静止：`hero/hero_parts_v2_vs_v2_1.png`、`sprout_boar/sprout_boar_parts_v2_vs_v2_1.png`
  - 静止+转动（头、膝 ±30°，野猪四条腿和尾巴）：`hero/hero_{f,s,b}_v2_vs_v2_1_rot.png`、`sprout_boar/sprout_boar_v2_vs_v2_1_rot.png`
  - 放大细节：`sprout_boar/sprout_boar_v2_vs_v2_1_detail.png`（四条腿和尾巴，整图和单件各一行）、`hero/hero_b_v2_vs_v2_1_forearm_r.png`
  - 关节自检：`*_v2_1_jointcheck.png/.json`（左 v2、右 v2.1，用同样的圆盘半径）。

## 改动（对应程序 5 条）
1. **露出的圆头不再深一档**：部件画在父部件上面时（野猪近侧两条腿、耳朵、芽，主角上臂/前臂/小腿/头等），圆头只长在父部件或更上层盖住的地方，盖在父部件上的那段直接取父部件自己的像素，静止时看不见。旧的端线保留，仍是可见的边界。全部 4 个朝向都按这个规则处理了，不止野猪。
   - 静止合成图在圆头区域的亮度差（0–255，均值/p95）：野猪后近腿 v2 50.7/127 → v2.1 0.2/0；前近腿 37.9/139 → 0/0；芽 67.5/120 → 1.6/12。主角小腿（侧面）28.9/32.4 → 1.0/1.7；正面头 16.3 → 0；背面前臂_r 29.4 → 0.3。
   - 同样的检查还发现：「藏在下层」的圆头在 v2 里有一部分伸出了上层的轮廓（比如背面上臂顶部比肩甲高出 12px，背面小腿圆头在大腿外露出）。v2.1 把这类圆头限制为只长在上层盖住的地方：背面肩_r 32.8 → 2.0，背面膝 31.6/20.3 → 2.0/2.1。
2. **先擦旧切口线再加圆头，颜色从内部取**：每一列先在部件内部往里 4px 的位置取 3px 中位色（去掉线稿像素），再擦掉端部 4px 内比这个颜色暗的像素；更深一点的锯齿切口，要非常暗的像素才擦，两侧轮廓线保留。圆头逐列用同一个颜色填，不再压暗，只给新轮廓描线。野猪远侧两条腿用 2.5px 取色，因为它们会露出肚子下面一点。
   - 擦掉的旧切口像素（1:1）：野猪 后远腿 15、前远腿 18、尾巴 8；主角各朝向每个关节 16–78。
   - 延长段平均亮度减去内部亮度（负数表示偏暗）：野猪 后远腿 −24.2 → −6.1，前远腿 −29.2 → −6.0，尾巴 +27.5 → +2.1。
   - 旧端线 4px 内的暗像素：野猪远腿 2/4 → 0/0，尾巴 5 → 0。主角背面膝 46/53 → 10/32，侧面大腿膝端 58/57 → 31/16。主角的皮甲本身纹理就暗，所以数值不会降到 0。
3. **±30° 洞**：rig_check（disc 与 v2 相同）头和膝全部为 0。
   - 头：正面 3.2 → 0（躯干领口只在头下面往上长 19.5px、宽 13）；侧面 4.5 → 0（领口 19.5 → 22.5，宽 9 → 15，同时把 head_s 里 26px 半透明裂缝补实）；背面 0 → 0。
   - 膝：背面 4.2/3.5 → 0/0（大腿膝端的圆头复制小腿像素，所以看不见，长度 5.5 → 10）；正面、侧面 0 → 0。
   - 其余关节全是 0，只有正面 hip_r 是 0.8（见遗留问题）。野猪全部 0。
4. **背面右手**：查实**指尖外面没有圆头**。把 v1 的 forearm_r_b 绕手腕转 30.1°（不加圆头），底边同样是 187.5，所以多出来的长度来自 v2 的 swing_attach 把手转成竖直。v2.1 保留 swing，再把 forearm_r_b 整条往上移 6px：底边 187.5 → 181.5，等于左手底边 181.5。手的像素和 v1 一样，指尖外没有新增像素。
5. **远侧腿在肚边那圈线**：新增 post_op `erase_outline_over`。远腿上方 2.5px 宽的身体外轮廓（腿两侧再留 1.5px，让腿侧线还能接上身体轮廓），用身体内部颜色替换：body_s_mesh 57px、head_s 28px（前远腿是从头的下巴下面伸出来的）。腿自己的旧切口线由第 2 条擦掉。前远腿的圆头允许在肚子下面露出 1–2px，相当于腿自然接进肚子；只允许它在被盖住的地方生长的话，±30° 会有 3.2px 的洞。

## 枢轴点变化（相对 v2）
- 背面 `wrist_r`：(180.7, 171.1) → (180.7, 165.1)，随 forearm_r_b 上移 6。
- 背面 `elbow_r`：(172.0, 144.7) → (168.4, 141.1)，上移 6 后用 pivot_to_overlap 重设到上臂和前臂重叠区的中心。
- 其他朝向、其他点、野猪：都没变。
- 程序侧：v2 导入时给 forearm_r_b 整条加的 −7px 程序位移要去掉，v2.1 的部件和枢轴点已经包含这次修正（6px，对齐左手）。

## 工具改动
- `rig_joints.py`：新增 `round_cap2`（区分可见/隐藏、擦旧切口、逐列内部取色）、`column_fill`、`erase_outline_over`、`solidify`。修正了 bridge 与半椭圆交界处那一行半透明缝（v2 的 round_cap 也有，v2 文件没动）。
- `rig_patch.py`：
  - 新的配置键：`cap_version`、`fill_inset`、`erase_cut`；每个关节可写 `<side>_erase_cut`、`<side>_cap_w`、`<side>_cover_only`、`<side>_over`、`<side>_target`。
  - 新增 `post_ops`（`erase_outline_over`、`clip_below`），以及 `solidify` 清理。
  - 隐藏圆头默认只长在上层盖住的地方（`hidden_caps_only_under_cover`）。
- `rig_check.py`：加 `--labels`。
- `rig_compare.py`：加 `rotsheet` 和 `--labels`。

## 遗留问题
- 正面 hip_r 在 ±30° 有 0.8px 洞：大腿往外摆时，外侧露出的地方在躯干轮廓外面。v2 靠一块看得见的圆头盖住（静止时多出约 42px）；v2.1 宁可留 0.8px，也不要静止时出现凸块。要补的话，把该关节写 `child_cover_only: false`。
- 近侧腿、上臂等画在上层的部件，端线（锯齿状切口）仍是可见边界，是原图里的线；程序导入时会换成填色。如果想要更平滑，需要在原图里重画。
- 前远腿露在肚子下面的 1–2px 是平涂（逐列取色），比较近看能看出纹理少了一点。
- 远腿上方的身体轮廓擦掉以后，腿大幅前后摆时，肚边那一段没有轮廓线。
- 正面 arm_upper_r_f 画在围巾上面这一点，v2.1 的图层顺序没改（程序导入时已经处理），沿用 v2 顺序。
- 表情替换和参考动作仍然要等机器修好。
- v2 遗留的 head_s 耳后模糊、背面右臂不对称这两条没处理。
