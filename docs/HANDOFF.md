# 第一关交接

记录时间：2026-10-21。分支哈希取自当时的 `git ls-remote --heads origin`。之后若有人推送，以远端为准。

可玩线是 `level1-polish`（T1–T11）。预览部署在 `/open-map/`。`main` 只负责站点根路径。

策划交接在另一个仓库。当前环境没有读权限，下面这个链接打不开（HTTP 404），短哈希也换不成完整哈希：

- 仓库：`7mouse/stellar-abyss-design`
- 路径：`07-prototype/handoff-design-2026-10-21.md`
- 提交：`996e395`

美术交接在本仓库 `rig-trial` 的 [docs/ART_HANDOFF.md](https://github.com/7mouse/stellar-abyss-greybox/blob/rig-trial/docs/ART_HANDOFF.md)。

## 分支地图

| 分支 | 远端哈希 | 用途 |
| --- | --- | --- |
| `main` | `c590c03cee3d01222e49d27333d5acaaf9a728ef` | 部署站点根路径。Pages 工作流始终以这个 ref 运行。 |
| `open-map-m1` | `7c38c2eb24780a936e195146aa33c65de2c3041c` | 部署 `/open-map/` 预览。只快进，不强推。写本文时指向 T10。预览验收通过后，会再快进到包含本文的提交；玩法与 `7c38c2e` 相同，只多了文档。 |
| `level1-polish` | `7c38c2eb24780a936e195146aa33c65de2c3041c` | 第一关精修 T1–T11，以及本交接。写本文时远端是上一格；本文提交后，尖端就是这次提交。 |
| `level1-t12` | `a37da1be15e465b3b408c3218c121ac6d7eee894` | 骨骼接入。PR [#2](https://github.com/7mouse/stellar-abyss-greybox/pull/2)。尖端是 WIP，帧率未过合并线。 |
| `rig-trial` | `760ed19631bc4878120ddc5f09886a2a69e9700c` | 骨骼试绑和美术素材。PR [#1](https://github.com/7mouse/stellar-abyss-greybox/pull/1)。尖端是 `docs/ART_HANDOFF.md`。`d0fbc51` 是其祖先，21g 半成品交接。 |
| `level1-atmo` | `2dc79c57751b9d32c258026f95c1698898ca1624` | 氛围后处理 WIP。无头 629 通过 / 0 失败。网页帧时间和对照截图没做。 |

`git ls-remote --heads origin` 当时只有这六支。

## 待合并 PR

两支都开着，现在都不要合。

1. 先修 [#2](https://github.com/7mouse/stellar-abyss-greybox/pull/2)（`level1-t12` → `level1-polish`）。帧时间还停在中位 33.3 ms，尖端 `a37da1b` 没有重跑整套。按下面的方向去掉每只怪的 SubViewport，中位回到 16.7 ms，并在新提交上跑完全套，再快进进 `level1-polish`。它的基线就是精修线，先不要进 `main`。
2. [#1](https://github.com/7mouse/stellar-abyss-greybox/pull/1)（`rig-trial` → `main`）继续当试绑和素材仓库。目标写的是 `main`，里面不是可玩线。`5f2a113..a959593` 以及之后的 `d0fbc51`、`760ed19` 重导进骨骼线之后，随 #2 一起进 `level1-polish`。整支 `rig-trial` 先不要合进 `main`。

## 如何构建、运行、测试、部署

Godot **4.7.2** stable。`project.godot` 的 features 是 4.7，渲染器 `gl_compatibility`。网页导出用单线程模板（`web_nothreads`），因为 GitHub Pages 不发 COOP/COEP。主场景是 `scenes/village/village.tscn`。键盘和手柄都能玩，可调项在 `.tres` 和 F1 面板。

测试在仓库根目录：

```bash
bash tests/run_tests.sh
```

种子默认 `424242`。要换种子就设环境变量 `TEST_SEED`。脚本先跑 `tools/font/font_tool.py check`，再 `godot --headless --import`，然后无头跑 `res://tests/test_main.tscn`，超时 900 秒。输出里有 `SCRIPT ERROR`，或某一行以 `ERROR:` 开头，就算失败。退出时的 RID / ObjectDB 泄漏警告不算失败。

网页导出（预设名 `Web`，见 `export_presets.cfg`）：

```bash
godot --headless --export-release "Web" build/web/index.html
```

部署看两个工作流：

- `.github/workflows/pages.yml`，名字「网页版部署」。始终以 `main` 为 ref。一次检出两份：`main` 和 `open-map-m1`。两边都跑 `tests/run_tests.sh`，再导出到 `site/`（根路径）和 `site/open-map/`。`main` 自己的 push 会直接触发。
- `.github/workflows/preview-trigger.yml` 在 `open-map-m1` push 时，用 `workflow_dispatch` 去调 `pages.yml --ref main`。所以预览部署的 Actions 头提交仍是 `main`，要在日志里看 preview 检出的哈希。

预览地址：<https://7mouse.github.io/stellar-abyss-greybox/open-map/>

`perfRing` 用 `tools/web/perf.mjs`。它依赖 `puppeteer-core`，Chrome 启动参数里带 `--use-angle=swiftshader`。默认 `FRAMES=600`。同一浏览器里依次测：空白页、村子（进村后再等 12 秒）、点击画面中央并调用 `greybox.startRun()`、第 1 层清空敌人、原有巡逻怪、`greybox.perfRing()` 的 12 只混战。要看的是最后一段「第1层-12只战斗」的中位和 p95，写在输出目录的 `summary.json` 的 `fight`。

```bash
node tools/web/perf.mjs https://7mouse.github.io/stellar-abyss-greybox/open-map/ /tmp/perf-out
```

无头软件渲染下，帧间隔按大约 16.7 ms 一档跳（60 Hz 的一帧）。同一档里，中位 16.7 ms、p95 在 33.3 和 33.4 ms 之间，都算同一档，0.1 ms 是舍入。掉到下一档，是中位变成约 33.3 ms，或 p95 到约 50 ms。`8823eec` 的预览四次都是中位 16.7 ms、p95 33.4 ms。判断退化要看多数次有没有掉档。

## T1–T13

种子都是 424242。测试数是该提交上 `tests/run_tests.sh` 的全绿结果。T1 的验收用例落在后面的 `0f8e0b5`，所以 T1 自己没有单独的套件数字。

| 项 | 提交 | 测试 |
| --- | --- | --- |
| T1 打击感 | `e0d3c2d` | 验收在 T8 的 `0f8e0b5`：420 通过 / 0 失败 |
| T8 新手引导 | `9ca64e9`、`0f8e0b5`、`9e522c0` | `0f8e0b5`：420 通过 / 0 失败。厚苔提示 `9e522c0`：427 通过 / 0 失败 |
| T2 破甲突刺 | `194b75a` | 439 通过 / 0 失败 |
| T3 深苔史莱姆 | `a10172d` | 457 通过 / 0 失败 |
| T4 苔冠王野猪 | `69f939a` | 505 通过 / 0 失败 |
| T5 六个地标 | `f7d455c` | 515 通过 / 0 失败 |
| T6 墓志铭 #0000 | `1153bbe` | 531 通过 / 0 失败 |
| T9 村落 | `a2fdee7` | 546 通过 / 0 失败 |
| T11 遮挡和预警 | `8823eec` | 574 通过 / 0 失败 |
| T7 音频 | `4b1290c` | 595 通过 / 0 失败 |
| T10 商店 | `7c38c2e` | 613 通过 / 0 失败 |
| T12 骨骼 | `level1-t12` 的 `7966e5c` | 642 通过 / 0 失败。帧率退化，未合并。尖端 WIP 是 `a37da1b`（`63c93ed..a37da1b`），这版没有重跑测试 |
| T13 验收 | 未做 | — |

这些哈希用 `git log` 对过：T1–T11 在 `level1-polish` 上按上表顺序；`7966e5c`、`63c93ed`、`a37da1b` 在 `level1-t12` 上。

## 未完成事项

### T12 帧率退化

`level1-t12` 最新是 `a37da1b`（WIP，范围 `63c93ed..a37da1b`）。这版 WIP 没有重跑测试。最近一次全过的是 `7966e5c`，642 通过 / 0 失败。写分支地图时 `rig-trial` 最新是 `760ed19`；用户交代过的 `d0fbc51` 是它的祖先（21g 半成品）。

定位（与 `a37da1b` 的提交说明一致）：

- 中位帧时间 16.7 → 33.3 ms，已经定位到画面内约 7 只菌猪各自的 SubViewport，绘制调用约 57 → 166。
- 以下都不是主因：CPU 蒙皮（约 0.13–0.17 ms）、眨眼、九宫格、AnimationPlayer。
- 视口停更但节点仍在树上，中位不变；整棵移出场景树后，中位回到 16.7。
- 没有重建尖峰时 logicMs 约 32 ms（基线 `7c38c2e` 是 31.1）；第一次挂上视口时仍有 20–26 ms 尖峰。
- 缩小视口、减描边、每帧只重绘 1 只，都没把中位拉回来。
- 提交说明里最近一次：菌猪不重绘且精灵藏起，120 帧里 59 帧 ≤ 16.7，中位仍 33.2，logicMs 33.3。

建议方向：去掉每只怪的 SubViewport，直接在主画布绘制 Skeleton2D（描边改用 shader 或预烘），或者让同种怪共用一个视口。

### 美术还没重导

`rig-trial` 的 `5f2a113..a959593` 没有重导进游戏：苔冠王 v3、蘑菇 v1.2、主角 v2.3、史莱姆 v1.2、发芽野猪背面 v1.2、特效。重导后角度限制可以恢复到 ±30°，但主角正面 `hip_r` 仍有 2.2 px 缝，要保持限角。再往后的 `d0fbc51`（21g，只生成了原图）和 `760ed19`（美术交接文档）也还没进可玩线。

### 动作时长

- 主角正面和背面缺 `move` / `attack` / `hit`。侧面有。缺的状态会落到 idle。
- 攻击片段、挨打片段长于玩法时长（0.30 秒 / 0.15 秒）。

### 氛围和验收

- 氛围后处理是半成品，在 `level1-atmo` 的 `2dc79c5`。无头 629 通过 / 0 失败。网页帧时间和跟基准图的左右对照没做。前后景树林素材是后景 2 张、前景 2 张，场景里各摆了至少 4 丛。
- T13 验收还没做。

## 已知问题

- 不要运行 `tools/data/gen_data.py`。它会写出过时的 boss 数值。
- Skeleton2D 必须用 CPU 权重。Compatibility 渲染器的 GPU 蒙皮会裁切。
- `art_src/rigs/sprout_boar/` 对应代码 id `mushling`（场景 `mushling_s.tscn` / `mushling_f.tscn` / `mushling_b.tscn`）。
- `art_src/` 里有空的 `.gdignore`，Godot 不导入这棵树。不用 Git LFS。单个文件保持在 50 MB 以下。
- 地表和 HUD 边框美术正在重生。

## 关键文件

在 `rig-trial` 上：

- `docs/rig-parts-spec.md`
- `docs/level1-tech-plan.md`（本分支这份已加「已过时」说明，正文从 `rig-trial` 取来）
- `docs/level1-polish-spec.md`
- `docs/ART_HANDOFF.md`
- `scenes/dev/rig_viewer.tscn`
- `art_src/`：`ref/` 参考，`src/` 原图，`prompts/` 提示词，`rigs/` 拆件（含 `sprout_boar/`、`hero/`、`mosscrown_king_boar/`、`slime/`、`root_spore_mushroom/`），`terrain/`，`ui/`，`fx/`，`wip/`，`tools/`

在 `level1-t12` 上，可玩线还没有：

- `data/rig_bone_limits.json`
- `scenes/rigs/rig_visual.gd`、`scenes/rigs/rig_present.gd`
- `tools/rig/import_rig.py`、`tools/rig/build_scenes.gd`

在 `level1-polish` 上：

- 关卡：`scenes/floor/floor.gd`、`scenes/floor/floor.tscn`、`scenes/floor/follow_cam.gd`、`scripts/map_gen.gd`、`data/floors/floor_1.tres`、`scripts/resources/floor_data.gd`
- 战斗：`scenes/actors/player.gd`、`scenes/actors/enemy_base.gd`、`scenes/actors/enemy_ai.gd`、`scenes/actors/guard.gd`、`scenes/combat/hitbox.gd`、`scenes/combat/hurtbox.gd`、`autoload/hit_feedback.gd`、`data/feel/hit_feel.tres`、`data/attacks/`
- 仇恨和生态：`scripts/aggro_director.gd`、`autoload/noise_bus.gd`、`data/ecology/`
- 存档和日志：`autoload/lineage.gd`（`user://lineage.json`）、`autoload/game.gd`、`autoload/log.gd`（`user://floors.csv`、`hits.csv`、`deaths.csv`）。墓志铭已读记在 `user://profile.cfg`
- 村落：`scenes/village/village.gd`、`scenes/village/shop.gd`、`scenes/village/craft_ui.gd`、`scenes/village/epitaph_wall.gd`、`scenes/village/warehouse_ui.gd`、`scenes/village/bag_ui.gd`、`scenes/village/vault_ui.gd`
- 音频：`autoload/audio.gd`、`data/audio/music_rules.tres`
- 商店：`data/shop_rules.tres`、`scripts/resources/shop_rules.gd`
- 教学和设置：`autoload/tutorial.gd`、`autoload/settings.gd`、`scripts/debug_panel.gd`（F1）
- 氛围半成品在 `level1-atmo`：`data/atmosphere.tres`、`scenes/floor/atmosphere_layer.gd`、`scenes/floor/floor1_dress.gd`
