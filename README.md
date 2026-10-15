# Stellar Abyss 灰盒 2（俯视 2D 即时动作肉鸽）

Godot 4.7.2 / GDScript，色块占位美术，中文 UI，键盘 + 手柄。规格见 `docs/greybox2-spec.md`、数值见 `docs/greybox2-numbers.md`。
旧的回合制节点图原型已废弃：代码移到 `legacy_greybox1/`（带 `.gdignore`，引擎不加载），最终版本打了标签 `greybox1-final`。

网页版（单线程导出）：https://7mouse.github.io/stellar-abyss-greybox/

## 操作
| 动作 | 键盘 / 鼠标 | 手柄 |
|---|---|---|
| 移动 | WASD / 方向键 | 左摇杆 / 十字键 |
| 瞄准 | 鼠标（没有瞄准输入时跟移动方向） | 右摇杆 |
| 普攻三连 | J / 鼠标左键 | X |
| 冲刺（无敌帧，可取消普攻） | 空格 / Shift | A |
| 技能“根须横扫” | K / Q / 鼠标右键 | Y |
| 互动 | E / F | B |
| 菜单确认 / 返回 | 回车 / Esc | A / B |
| 调试面板 | F1 / ` | Back |

## 流程
起程村（培养槽、保险箱、墓志铭墙、强化台、下潜井口、布告栏、老冒险者）→ 第 1~3 层（入口 → 战斗房 ×3~4 → 篝火 → 层守房/撤离点，0~2 个宝箱/强化支路）→ 撤离结算（放入保险箱）或 死亡（墓志铭 → 培养槽 → 遗志 3 选 1）→ 回村。新个体叫“林·#000N”，等级继承 30%（向下取整，最低 1），熟练度记录 50%（不生效），遗志按原效果 50% 生效（`legacy_rules.tres` 的 `legacy_power`）。

## 目录
- `autoload/`：`game.gd`（场景流转、当前局、输入、网页钩子）、`lineage.gd`（跨死亡存档 `user://lineage.json`）、`log.gd`（CSV）、`settings.gd`
- `data/`：全部参数 `.tres`（`tools/data/gen_data.py` 可按数值表重新生成默认值）
- `scenes/`：`village/`、`floor/`、`actors/`（主角、敌人基类、层守）、`combat/`（攻击框/受击框/弹/飘字）、`ui/`
- `scripts/`：`floor_gen.gd`（房间模板 + 生成 + 走通检查）、`stats.gd`（属性修正、特质/缺陷）、`boons.gd`、`items.gd`、`debug_panel.gd`、`resources/`

## 调试面板（F1）
分组折叠：调试按钮、玩家、攻击、敌人、层守（含词缀勾选）、楼层、掉落、遗志、保险箱、线索。改动立即生效，每个资源可“导出 .tres”到 `user://export/`（网页版直接下载）。按钮：上帝模式、无限冲刺、显示受击框/攻击框、刷怪（种类 × 数量）、跳到第 n 层、直接打出层守、给予/移除强化、杀死自己、材料 +50、清空存档、下载 CSV、刷 1000 只怪（掉落统计）、种子。

## 试玩 CSV（`user://`，网页版“下载 CSV”逐个下载）
`floors.csv`、`hits.csv`（面板可关）、`deaths.csv`，都带 `clue_seen` 列。

## 测试
```
tests/run_tests.sh          # 字体覆盖检查 + 无头验收（退出码 0 = 通过）
godot --headless --export-release "Web" build/web/index.html
node tools/web/check.mjs <url> <下载目录> <截图目录>   # 需要 puppeteer-core 与 Chrome
python3 tools/font/font_tool.py build <NotoSansSC.ttf>  # 新增中文后重建字体子集
```
