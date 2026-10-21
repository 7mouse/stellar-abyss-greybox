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
