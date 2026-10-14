# Stellar Abyss 灰盒原型

回合制战斗 + 实时小游戏判定的 2D 搜打撤迷宫下潜 Roguelite 灰盒。引擎 **Godot 4.7（GDScript）**，美术全部是色块占位。

世界观：主角穿越到异世界，要通关迷宫才能回去；每局从第 1 层开始。

## 打开与运行
1. 安装 [Godot 4.7 标准版](https://godotengine.org/download)（不需要 .NET 版）。
2. 打开 Godot → 导入 → 选择本仓库的 `project.godot`。
3. 按 F5 运行（主场景是营地 `scenes/camp.tscn`）。

命令行运行：`godot --path .`

## 操作（键盘 / 手柄）
| 功能 | 键盘 | 手柄 |
|---|---|---|
| 菜单移动 | 方向键 | 十字键 / 左摇杆 |
| 确认 | 回车 / 空格 | A |
| 小游戏操作 | 空格 / J / Z | A |
| 切换战斗目标 | ← → 或 Q / E | LB / RB |
| 调试面板 | F1 | Back / Select |

## 自动测试
```
godot --headless --import --quit          # 首次：生成类缓存
godot --headless res://tests/test_main.tscn
```
退出码 0 表示 T1~T3 验收用例全部通过。

## 目录
- `scripts/game_state.gd`：全局状态（autoload），场景流转、局内背包、局外材料、技能等级、层数、输入映射
- `scripts/dungeon_gen.gd`：迷宫层生成（固定种子可复现）
- `scripts/debug_panel.gd`：F1 调试面板（骨架）
- `scripts/resources/`：可调参数的 Resource 类型；数据在 `data/*.tres`
- `minigames/minigame_base.gd`：小游戏统一接口 `MinigameBase`
- `minigames/timing_bar.*`：占位小游戏“时机条”（正式小游戏 T4~T7 替换）
- `scenes/`：营地、迷宫、战斗、结算
- `tests/`：自动验收脚本

## 进度
- [x] T1 项目骨架  - [x] T2 迷宫层  - [x] T3 回合制战斗框架
- [ ] T4~T10
