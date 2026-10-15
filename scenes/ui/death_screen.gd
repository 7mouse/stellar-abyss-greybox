extends Control
## 死亡：墓志铭（名字、层数、死因）→ 最后 0.2 秒乱码 + 55Hz 心跳 → 培养槽苏醒（占位 2 秒）→ 遗志选择

var label: Label
var sub: Label
var garbled := false

func _ready() -> void:
	UI.rect(self, Vector2.ZERO, Vector2(1920, 1080), Color(0.04, 0.03, 0.04))
	var d: Dictionary = Game.last_death
	var text := "%s　Lv%d\n倒在第 %d 层　死因：%s" % [d.get("name", ""), d.get("level", 1), d.get("depth", 0), d.get("cause", "")]
	label = UI.label(self, text, Vector2(560, 420), 44)
	sub = UI.label(self, "未带出的记忆碎片丢失 %d 个（载入备份时没同步的那部分记忆）" % d.get("lost_shards", 0), Vector2(560, 560), 26, Color(0.7, 0.6, 0.7))
	_run(text)

func _run(text: String) -> void:
	var c := Game.clues
	await get_tree().create_timer(2.2 - c.death_garble_sec).timeout
	label.text = c.death_garble
	garbled = true
	Beep.play(self, c.heartbeat_hz, 0.3)
	if Game.last_death.has("clue_seen"):
		if not "death_garble" in Game.last_death.clue_seen:
			Game.last_death.clue_seen.append("death_garble")
	await get_tree().create_timer(c.death_garble_sec).timeout
	label.text = text
	await get_tree().create_timer(0.5).timeout
	label.text = "培养槽中……新的个体正在苏醒"
	sub.text = ""
	await get_tree().create_timer(Lineage.legacy_rules.wake_sec).timeout
	Game.goto(Game.SCN_LEGACY)
