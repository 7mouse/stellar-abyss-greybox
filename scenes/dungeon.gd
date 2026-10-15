extends Control
## 迷宫层：分支节点图。

const TYPE_COLORS := {
	"combat": Color(0.75, 0.25, 0.25), "chest": Color(0.8, 0.65, 0.15), "event": Color(0.35, 0.5, 0.8),
	"rest": Color(0.3, 0.7, 0.4), "exit": Color(0.85, 0.85, 0.85),
}
const EVENT_TEXTS := [
	"墙上刻着一行字：“这里的一切都是真实的。”（事件占位）",
	"你听见远处有人在哼一首熟悉的歌。（事件占位）",
	"一块发光的石板，上面写着看不懂的说明书。（事件占位）",
]

var fd: Dictionary
var buttons := {}
var header: Label
var popup_node: Control = null
var popup_kind := "" ## "" / "message" / "exit"

func _ready() -> void:
	fd = GameState.floor_data
	UI.rect(self, Vector2.ZERO, Vector2(1920, 1080), Color(0.1, 0.1, 0.13))
	header = UI.label(self, "", Vector2(60, 30), 34)
	UI.label(self, "红=战斗 黄=宝箱 蓝=事件 绿=休息 白=出口    方向键/摇杆选择，确认键前进", Vector2(60, 1010), 24, Color(0.7, 0.7, 0.7))
	for nd in fd.nodes:
		var b := UI.button(self, DungeonGen.TYPE_CN[nd.type], visit.bind(nd.id), Vector2(150, 90), TYPE_COLORS[nd.type])
		b.position = node_pos(nd) - Vector2(75, 45)
		buttons[nd.id] = b
	_refresh()

func node_pos(nd: Dictionary) -> Vector2:
	var x: float = 180.0 + nd.col * (1560.0 / maxf(1.0, fd.cols - 1))
	var y: float = 540.0 + (nd.row - (nd.rows - 1) / 2.0) * 220.0
	return Vector2(x, y)

func _draw() -> void:
	for nd in fd.nodes:
		for t in nd.next:
			var c := Color(0.5, 0.5, 0.55) if not nd.visited else Color(0.9, 0.9, 0.5)
			draw_line(node_pos(nd), node_pos(fd.nodes[t]), c, 4.0)
	if GameState.current_node >= 0:
		draw_circle(node_pos(fd.nodes[GameState.current_node]) + Vector2(0, -70), 14, Color(1, 1, 0.3))

func reachable() -> Array:
	return DungeonGen.reachable_from(fd, GameState.current_node)

func _refresh() -> void:
	header.text = ("第 %d 层" + ("（最终层）" if GameState.is_final_floor() else ("/共 %d 层" % GameState.tunables.final_floor if GameState.tunables.final_floor > 0 else ""))) % GameState.depth + "    HP %d/%d    掉落倍率 %d%%    背包 %d/%d 格（材料 %d  碎片 %d）" % [GameState.player_hp, GameState.tunables.player_max_hp, roundi(GameState.loot_mult * 100), GameState.inventory.size(), GameState.tunables.backpack_slots, GameState.run_loot.material, GameState.run_loot.shard]
	if popup_node == null and not GameState.pending_loot.is_empty():
		_discard_choice()
		return
	var r := reachable()
	var first: Button = null
	for id in buttons:
		var b: Button = buttons[id]
		b.disabled = not (id in r) or popup_node != null
		b.modulate = Color(1, 1, 1, 0.45) if fd.nodes[id].visited else Color.WHITE
		if not b.disabled and first == null:
			first = b
	if first and popup_node == null:
		first.grab_focus.call_deferred()
	queue_redraw()

func visit(id: int) -> void:
	if popup_node != null or not (id in reachable()):
		return
	GameState.current_node = id
	var nd: Dictionary = fd.nodes[id]
	var first_time: bool = not nd.visited
	nd.visited = true
	match nd.type:
		"combat":
			GameState.start_battle()
			return
		"chest":
			if first_time:
				var t := GameState.tunables
				var rng := RandomNumberGenerator.new()
				rng.seed = hash([GameState.run_seed, GameState.depth, id, "chest"])
				var m := GameState.add_loot("material", t.chest_material)
				var sh := GameState.roll_drop(t.chest_shard_rate, t.chest_shard, rng)
				var s := GameState.add_loot("shard", sh) if sh > 0 else 0
				_message("打开宝箱：材料 +%d，记忆碎片 +%d" % [m, s])
			else:
				_message("宝箱已经空了。")
		"event":
			_message(EVENT_TEXTS[id % EVENT_TEXTS.size()])
		"rest":
			var h := GameState.heal_rest()
			_message("在篝火旁休息，回复 %d 点生命。" % h)
		"exit":
			if GameState.is_final_floor():
				_clear_popup()
			else:
				_exit_choice()
	_refresh()

func _message(text: String) -> void:
	var p := UI.popup(self, text)
	popup_node = p.panel
	popup_kind = "message"
	var b := UI.button(p.box, "确定", dismiss_message)
	b.grab_focus.call_deferred()

func dismiss_message() -> void:
	_close_popup()

func _exit_choice() -> void:
	var p := UI.popup(self, "找到了出口。要怎么做？")
	popup_node = p.panel
	popup_kind = "exit"
	var b1 := UI.button(p.box, "撤离（带出全部战利品，下局从第 1 层开始）", choose_withdraw, Vector2(760, 80), Color(0.2, 0.45, 0.3))
	UI.button(p.box, "继续深入（第 %d 层，掉落倍率 +%d%%）" % [GameState.depth + 1, roundi(GameState.tunables.loot_bonus_per_depth * 100)], choose_descend, Vector2(760, 80), Color(0.5, 0.25, 0.25))
	b1.grab_focus.call_deferred()

## 背包已满：选择丢弃背包里的一格，或放弃新物品
func _discard_choice() -> void:
	var it: Dictionary = GameState.pending_loot[0]
	var p := UI.popup(self, "背包已满（%d/%d 格）。新物品：%s\n选择要丢弃的一格，或放弃新物品" % [GameState.inventory.size(), GameState.tunables.backpack_slots, GameState.item_name(it)])
	popup_node = p.panel
	popup_kind = "discard"
	var grid := GridContainer.new()
	grid.columns = 4
	p.box.add_child(grid)
	var first: Button = null
	for i in GameState.inventory.size():
		var col := Color(0.45, 0.4, 0.2) if GameState.inventory[i].kind == "material" else Color(0.35, 0.3, 0.6)
		var b := UI.button(grid, "丢弃 " + GameState.item_name(GameState.inventory[i]), choose_discard_slot.bind(i), Vector2(280, 64), col)
		if first == null:
			first = b
	UI.button(p.box, "放弃新物品（%s）" % GameState.item_name(it), choose_discard_new, Vector2(600, 72), Color(0.5, 0.25, 0.25))
	first.grab_focus.call_deferred()
	_refresh_buttons_only()

func choose_discard_slot(i: int) -> void:
	GameState.discard_slot(i)
	_close_popup()

func choose_discard_new() -> void:
	GameState.discard_pending()
	_close_popup()

func _refresh_buttons_only() -> void:
	for id in buttons:
		buttons[id].disabled = true

## 最终层出口：恭喜通关 → 迷宫重置（假结局占位）
func _clear_popup() -> void:
	var p := UI.popup(self, "恭喜通关！\n向导：“你已经走到了迷宫的尽头。”\n……然而，迷宫的入口再次打开了。（假结局占位）")
	popup_node = p.panel
	popup_kind = "clear"
	var b := UI.button(p.box, "确定（战利品全部带出，迷宫重置）", choose_clear_confirm, Vector2(640, 80), Color(0.6, 0.5, 0.2))
	b.grab_focus.call_deferred()

func choose_clear_confirm() -> void:
	_close_popup()
	GameState.clear_dungeon()

func _close_popup() -> void:
	if popup_node:
		popup_node.queue_free()
	popup_node = null
	popup_kind = ""
	_refresh()

func choose_withdraw() -> void:
	_close_popup()
	GameState.end_run(true)

func choose_descend() -> void:
	_close_popup()
	GameState.descend()
	GameState.goto(GameState.SCN_DUNGEON)
