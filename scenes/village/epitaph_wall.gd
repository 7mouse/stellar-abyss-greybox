extends Panel2
## 墓志铭墙：所有前任。死过 ≥ epitaph0_min_deaths 次后最底部多一条灰色 #0000；焦点停 2 秒后逐字“修复”

var ghost: Button
var blank_0000: Button
var focus_t := 0.0
var fix_progress := -1.0

func _init() -> void:
	title = "墓志铭墙"

func _fill() -> void:
	if Lineage.epitaphs.is_empty():
		text("还没有前任。", 26, Color(0.7, 0.7, 0.7))
	for e in Lineage.epitaphs:
		btn("%s　Lv%d　—　第 %d 层　—　死因：%s" % [e.name, int(e.level), int(e.depth), e.cause], func(): pass)
	_append_ghost_entry()
	_append_blank_slot()

func _append_blank_slot() -> void:
	blank_0000 = null
	if not EpitaphLore.was_read():
		return
	var lore: EpitaphLore = load("res://data/lore/epitaph_0000.tres")
	blank_0000 = btn(lore.slot_text, func(): pass)
	blank_0000.add_theme_color_override("font_color", Color(0.42, 0.42, 0.46))
	blank_0000.add_theme_color_override("font_focus_color", Color(0.55, 0.55, 0.58))

func _append_ghost_entry() -> void:
	ghost = null
	if Lineage.epitaphs.size() < Game.clues.epitaph0_min_deaths:
		return
	var fixed: bool = Lineage.flags.get("clue_epitaph0", false)
	ghost = btn(Game.clues.epitaph0_fixed if fixed else Game.clues.epitaph0_raw, func(): pass)
	ghost.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
	ghost.add_theme_color_override("font_focus_color", Color(0.75, 0.75, 0.75))
	fix_progress = 1.0 if fixed else -1.0

func ghost_text() -> String:
	return ghost.text if ghost else ""

func _process(delta: float) -> void:
	if ghost == null or not is_instance_valid(ghost):
		return
	if fix_progress >= 1.0:
		return
	if fix_progress >= 0.0:
		fix_progress = minf(1.0, fix_progress + delta / 1.0)
		var raw := Game.clues.epitaph0_raw
		var fixed := Game.clues.epitaph0_fixed
		var n := int(fixed.length() * fix_progress)
		ghost.text = fixed.substr(0, n) + raw.substr(mini(n, raw.length()))
		if fix_progress >= 1.0:
			ghost.text = fixed
			Lineage.flags["clue_epitaph0"] = true
			Lineage.save()
			if Game.run:
				Game.run.see_clue("epitaph0")
			Game.set_meta("clue_epitaph0_seen", true)
		return
	if ghost.has_focus():
		focus_t += delta
		if focus_t >= Game.clues.epitaph0_hover_sec:
			fix_progress = 0.0
	else:
		focus_t = 0.0
