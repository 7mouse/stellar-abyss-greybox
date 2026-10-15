# Stellar Abyss 灰盒原型

回合制战斗 + 实时小游戏判定的 2D 搜打撤迷宫下潜 Roguelite 灰盒。引擎 **Godot 4.7（GDScript）**，美术全部是色块占位。

世界观：主角穿越到异世界，要通关迷宫才能回去；每局从第 1 层开始。

## 打开与运行
1. 安装 [Godot 4.7 标准版](https://godotengine.org/download)（不需要 .NET 版）。
2. 打开 Godot → 导入 → 选择本仓库的 `project.godot`。
3. 按 F5 运行（主场景是营地 `scenes/camp.tscn`）。

命令行运行：`godot --path .`

## 网页版（HTML5）
- 线上地址（启用 GitHub Pages 后）：https://7mouse.github.io/stellar-abyss-greybox/
- 单线程版（不需要 COOP/COEP 头，GitHub Pages 可直接托管），内置中文字体 `assets/fonts/NotoSansSC-Greybox.ttf`（Noto Sans SC 子集，OFL 许可见同目录）。
- 本地导出：`godot --headless --export-release "Web" build/web/index.html`，然后 `cd build/web && python3 -m http.server 8000`，浏览器打开 http://localhost:8000 。
- 网页里 F1 可能被浏览器占用，可用 **`** 键（数字 1 左边）或手柄 Back 打开调试面板。
- 试玩数据：结算界面或调试面板点“下载 CSV”，浏览器会下载 `playtest_log.csv`。
- 新增中文文案后运行 `python3 tools/font/font_tool.py build <NotoSansSC[wght].ttf>` 重新生成字体子集；`tests/run_tests.sh` 会检查缺字。
- 本地无头浏览器检查：`npm i puppeteer-core` 后 `node tools/web/check.mjs http://localhost:8000/index.html /tmp/dl /tmp/shots`。
- 推送到 main 后由 `.github/workflows/pages.yml` 自动测试、导出并部署。

## 操作（键盘 / 手柄）
| 功能 | 键盘 | 手柄 |
|---|---|---|
| 菜单移动 | 方向键 | 十字键 / 左摇杆 |
| 确认 | 回车 / 空格 | A |
| 小游戏确认 / 格挡 / 节奏 / 掷骰 | 空格 / J / Z | A |
| 连击方向 / 躲球移动 / 猜拳（←石头 ↑剪刀 →布） | 方向键 / WASD | 十字键 / 左摇杆 |
| 切换战斗目标 | ← → 或 Q / E | LB / RB |
| 调试面板 | F1 或 ` | Back / Select |

## 自动测试
```
tests/run_tests.sh      # 无头跑全部验收，引擎报错也算失败
```
退出码 0 表示 T1~T10 验收用例全部通过（含 T6 的 1000 次概率模拟、纯手柄/纯键盘走完一局）。

## 试玩数据
每次小游戏判定都会追加一行到 `user://playtest_log.csv`（Windows：`%APPDATA%\Godot\app_userdata\Stellar Abyss 灰盒原型\`，Linux：`~/.local/share/godot/app_userdata/Stellar Abyss 灰盒原型/`）。
列：`time,run_id,depth,minigame,group,kind,result,score,judge_sec（操作耗时）,total_sec（含预兆）,auto`。F1 面板可清空日志。

## 目录
- `scripts/game_state.gd`：全局状态（autoload），场景流转、局内背包、局外材料、技能等级、层数、输入映射
- `scripts/dungeon_gen.gd`：迷宫层生成（固定种子可复现）
- `scripts/debug_panel.gd`：F1 调试面板（骨架）
- `scripts/resources/`：可调参数的 Resource 类型；数据在 `data/*.tres`
- `minigames/minigame_base.gd`：小游戏统一接口 `MinigameBase`
- `minigames/combo_dodge.*`：T4 第 1 组 连击闪避/格挡（敌人近战连击时触发）
- `minigames/chase_balls.*`：T5 第 2 组 追逐躲球（敌人追踪弹时触发）
- `minigames/luck_game.*`：T6 第 5 组 猜拳 / 骰子（技能“猜拳一击”“命运骰击”）
- `minigames/rhythm_keys.*`：T7 第 6 组 节奏按键（技能“节奏连斩”）
- `scenes/calibration.*`：节奏输入延迟校准（营地入口）
- `scenes/`：营地、迷宫、战斗、结算
- `tests/`：自动验收脚本

## 进度
- [x] T1 项目骨架  - [x] T2 迷宫层  - [x] T3 回合制战斗框架
- [x] T4 连击闪避/格挡  - [x] T5 追逐躲球  - [x] T6 猜拳/骰子  - [x] T7 节奏按键
- [x] T8 搜刮与 12 格背包  - [x] T9 极简营地  - [x] T10 调试面板与 CSV 记录
