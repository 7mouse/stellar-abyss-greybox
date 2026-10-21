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
