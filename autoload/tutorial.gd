extends Node
## 新手引导。步骤记在 user://profile.cfg 的 tutorial_done；整局结束后 sealed，下一局不再触发。
## 外部事件走 notify(event_id)。T2/T3/T4 用 boss_enter、boss_first_telegraph、elite_first_seen、armor_broken_first。
## 深苔史莱姆不是新的教学步骤。T3 第一次遇到时调用 on_elite_first_seen()，厚苔打破时调用 on_thickmoss_broken()。
## 这条提示排在层主名条之前。精英、厚苔和技能 2 都还没做，不会自己触发。

const STEPS: PackedStringArray = ["move", "attack", "dash", "loot", "stealth", "fire", "boss", "extract", "death", "charm"]

var rules: TutorialRules = preload("res://data/tutorial/tutorial_rules.tres")
var path := "user://profile.cfg"
var hold_world := false
var done := {}
var sealed := false
var death_line := ""
var hint := ""
var banner := ""
var shows := {}
var active := ""
var show_left := 0.0
var retry := {}
var cone_left := 0.0
var banner_left := 0.0
var telegraph_left := 0
var exit_mark := false
var hooked := {} ## 给还没接上的事件留的计数

var _moved := 0.0
var _floor_t := 0.0
var _on_floor := false
var _near_fight := false
var _fight_cleared := false
var _combo := false
var _threat := false
var _dash_n := 0
var _dash_dodged := false
var _near_loot := false
var _looted := false
var _spotted: Node = null
var _chased := false
var _stealth_clear := false
var _near_fire := false
var _hp_full := false
var _used_fire := false
var _boss_zone := false
var _elite_seen := false
var _moss_broken := false
var _charge_dodged := false
var _guard_dead := false
var _extracted := false
var _charm := false
var _run_id := ""
var _saw_floor := false
var _epitaph := false
var _last_pos := Vector2.INF
var _fight_group := ""
var _fight_seen := false
var _flash_node: CanvasItem
var _flash_t := 0.0
var _flash_n := 0
var _hint: Label
var _banner: Label
var _cone: Node2D

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load()
	var layer := CanvasLayer.new()
	layer.layer = 30
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(layer)
	_hint = Label.new()
	_hint.position = Vector2(360, 960)
	_hint.size = Vector2(1200, 80)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.add_theme_font_size_override("font_size", 30)
	_hint.add_theme_color_override("font_color", Color(1, 0.95, 0.6))
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint.visible = false
	layer.add_child(_hint)
	_banner = Label.new()
	_banner.position = Vector2(360, 160)
	_banner.size = Vector2(1200, 90)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.add_theme_font_size_override("font_size", 64)
	_banner.add_theme_color_override("font_color", Color(0.95, 0.85, 0.55))
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.visible = false
	layer.add_child(_banner)
	_cone = Node2D.new()
	_cone.top_level = true
	_cone.z_index = 45
	_cone.visible = false
	_cone.draw.connect(_draw_cone)
	add_child(_cone)
	Game.run_ended.connect(func(_ok): notify("run_ended"))

func _process(delta: float) -> void:
	if not hold_world:
		_gather(delta)
		_evaluate()
	_tick(delta)

func notify(event_id: String, arg = null) -> void:
	match event_id:
		"dash":
			_dash_n += 1
		"dash_dodge":
			_dash_dodged = true
		"combo":
			_combo = true
		"threat":
			_threat = true
		"loot":
			_looted = true
		"fire":
			_used_fire = true
		"spotted":
			if arg is Node and is_instance_valid(arg):
				_spotted = arg
		"chased":
			_chased = true
		"boss_enter":
			_boss_zone = true
		"boss_first_telegraph":
			_arm_telegraph(arg if arg is CanvasItem else null)
		"boss_charge_dodged":
			_charge_dodged = true
		"guard_dead":
			_guard_dead = true
		"extract":
			_extracted = true
		"charm":
			_charm = true
		"death":
			_on_death()
		"village":
			_on_village()
		"run_ended":
			_on_run_ended()
		"elite_first_seen":
			_elite_seen = true
			hooked[event_id] = int(hooked.get(event_id, 0)) + 1
		"thickmoss_broken":
			_moss_broken = true
			hooked[event_id] = int(hooked.get(event_id, 0)) + 1
		"armor_broken_first":
			hooked[event_id] = int(hooked.get(event_id, 0)) + 1
		_:
			hooked[event_id] = int(hooked.get(event_id, 0)) + 1
	_evaluate()

func reset_progress() -> void:
	done.clear()
	sealed = false
	shows.clear()
	retry.clear()
	active = ""
	hint = ""
	banner = ""
	show_left = 0.0
	cone_left = 0.0
	banner_left = 0.0
	exit_mark = false
	death_line = ""
	_epitaph = false
	_flash_node = null
	_flash_n = 0
	_clear_run_flags()
	_run_id = ""
	_saw_floor = false
	_save()

func is_done(id: String) -> bool:
	return sealed or done.has(id)

func is_sealed() -> bool:
	return sealed

func prompts_shown(id: String) -> int:
	return int(shows.get(id, 0))

func hint_text() -> String:
	return hint if active != "" else ""

func banner_text() -> String:
	return banner if banner_left > 0.0 else ""

func wants_exit_marker() -> bool:
	return exit_mark and not sealed

func take_epitaph_flash() -> bool:
	var v := _epitaph
	_epitaph = false
	return v

func telegraph_played() -> bool:
	return done.has("boss_telegraph")

## T3：玩家第一次遇见深苔史莱姆。精英还没做，现在没有调用点。
func on_elite_first_seen() -> void:
	notify("elite_first_seen")

## T3：厚苔被打破。破甲还没做，现在没有调用点。提示会立刻完成。
func on_thickmoss_broken() -> void:
	notify("thickmoss_broken")

func debug_setup(s: Dictionary) -> void:
	hold_world = true
	_moved = float(s.get("moved", _moved))
	_floor_t = float(s.get("floor_t", _floor_t))
	_on_floor = bool(s.get("on_floor", _on_floor))
	_near_fight = bool(s.get("near_fight", _near_fight))
	_fight_cleared = bool(s.get("fight_cleared", _fight_cleared))
	_combo = bool(s.get("combo", _combo))
	_threat = bool(s.get("threat", _threat))
	_dash_n = int(s.get("dash_count", _dash_n))
	_dash_dodged = bool(s.get("dash_dodged", _dash_dodged))
	_near_loot = bool(s.get("near_loot", _near_loot))
	_looted = bool(s.get("looted", _looted))
	_chased = bool(s.get("chased", _chased))
	_stealth_clear = bool(s.get("stealth_clear", _stealth_clear))
	_near_fire = bool(s.get("near_fire", _near_fire))
	_hp_full = bool(s.get("hp_full", _hp_full))
	_used_fire = bool(s.get("used_fire", _used_fire))
	_boss_zone = bool(s.get("boss_zone", _boss_zone))
	_charge_dodged = bool(s.get("charge_dodged", _charge_dodged))
	_guard_dead = bool(s.get("guard_dead", _guard_dead))
	_extracted = bool(s.get("extracted", _extracted))
	_charm = bool(s.get("charm", _charm))
	if s.get("spotted", false):
		_spotted = self
	_evaluate()

func debug_advance(dt: float) -> void:
	_tick(dt)
	_evaluate()

func _gather(delta: float) -> void:
	var run_id := Game.run.id if Game.run else ""
	if run_id != _run_id:
		if _run_id != "" and _saw_floor and not sealed:
			_seal()
		_run_id = run_id
		_clear_run_flags()
		_saw_floor = false
	var scene := get_tree().current_scene
	var floor := scene if scene != null and scene.get("layout") != null and scene.get("player") != null else null
	_on_floor = floor != null and Game.run != null and Game.run.depth == 1
	if not _on_floor:
		_near_fight = false
		_near_loot = false
		_near_fire = false
		_last_pos = Vector2.INF
		return
	_saw_floor = true
	_floor_t += delta
	var p: Node2D = floor.player
	if _last_pos != Vector2.INF:
		_moved += p.global_position.distance_to(_last_pos)
	_last_pos = p.global_position
	_hp_full = p.get("hp") >= p.get("max_hp")
	_near_fight = false
	if _fight_group == "":
		_fight_group = _pick_fight_group(floor)
	var alive := 0
	for e in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(e):
			continue
		if _fight_group != "" and str(e.get_meta("group", "")) == _fight_group:
			alive += 1
			if p.global_position.distance_to(e.global_position) <= rules.attack_range_px:
				_near_fight = true
	if alive > 0:
		_fight_seen = true
		_fight_cleared = false
	elif _fight_seen:
		_fight_cleared = true
	_near_loot = false
	for it in floor.interactables:
		if it.id in ["chest", "node", "corpse"] and it.enabled.call() and p.global_position.distance_to(it.pos) <= rules.loot_px:
			_near_loot = true
	var fire: Vector2 = floor.layout.campfire_pos
	_near_fire = p.global_position.distance_to(fire) <= rules.fire_px
	if _spotted != null and is_instance_valid(_spotted):
		_stealth_clear = _spotted.get("state") == EnemyBase.S.PATROL and not _chased
	else:
		_spotted = null
	if floor.get("guard_dead"):
		_guard_dead = true
func _pick_fight_group(floor) -> String:
	var best := ""
	var bd := INF
	var i := 0
	var start: Vector2 = floor.layout.start_pos
	for p in floor.layout.spawn_points.patrol:
		var d: float = start.distance_to(p.points[0])
		if d < bd:
			bd = d
			best = "p%d" % i
		i += 1
	return best

func _evaluate() -> void:
	if sealed:
		active = ""
		hint = ""
		exit_mark = false
		return
	_step_move()
	_step_attack()
	_step_dash()
	_step_loot()
	_step_stealth()
	_step_fire()
	_step_thickmoss()
	_step_boss()
	_step_extract()
	_step_charm()
	if active != "" and not done.has(active):
		hint = _line(active)
	elif active != "" and done.has(active):
		hint = _line(active)

func _step_move() -> void:
	if done.has("move"):
		return
	if _moved >= rules.move_px:
		_finish("move", false)
		return
	if _on_floor and _floor_t >= rules.move_delay_sec:
		_show("move")

func _step_attack() -> void:
	if done.has("attack"):
		return
	if _combo or _fight_cleared:
		_finish("attack", false)
		return
	if _near_fight:
		_show("attack")

func _step_dash() -> void:
	if done.has("dash"):
		return
	if _dash_dodged or _dash_n >= rules.dash_uses_skip:
		_finish("dash", false)
		return
	if _threat:
		_show("dash")

func _step_loot() -> void:
	if done.has("loot"):
		return
	if _looted:
		_finish("loot", false)
		return
	if _near_loot:
		_show("loot")

func _step_stealth() -> void:
	if done.has("stealth"):
		return
	if _chased:
		_finish("stealth", false)
		return
	if _stealth_clear and shows.get("stealth", 0) > 0:
		_finish("stealth", false)
		return
	if _spotted != null and is_instance_valid(_spotted):
		_show("stealth")
		if active == "stealth" and cone_left <= 0.0 and not done.has("stealth_cone"):
			cone_left = rules.cone_sec
			done["stealth_cone"] = true

func _step_fire() -> void:
	if done.has("fire"):
		return
	if _used_fire:
		_finish("fire", false)
		return
	if _near_fire:
		if _hp_full:
			_show("fire")
			_finish("fire", true)
		else:
			_show("fire")

## 不是十步之一。只在钩子到来时占底部提示，并且排在层主教学前面。
func _step_thickmoss() -> void:
	if done.has("thickmoss"):
		return
	if _moss_broken:
		_finish("thickmoss", false)
		return
	if _elite_seen:
		_show("thickmoss")

func _step_boss() -> void:
	if _elite_seen and not done.has("thickmoss"):
		return
	if _boss_zone and not done.has("boss_banner"):
		done["boss_banner"] = true
		banner = rules.boss_name
		banner_left = rules.banner_sec
		_save()
	if done.has("boss"):
		return
	if _charge_dodged:
		_finish("boss", false)

func _step_extract() -> void:
	if done.has("extract"):
		return
	if _extracted:
		_finish("extract", false)
		exit_mark = false
		return
	if _guard_dead:
		_show("extract")
		exit_mark = true

func _step_charm() -> void:
	if done.has("charm"):
		return
	if _charm:
		_show("charm")
		_finish("charm", true)

func _show(id: String) -> void:
	if done.has(id):
		return
	if int(shows.get(id, 0)) >= rules.max_shows and active != id:
		return
	if float(retry.get(id, 0.0)) > 0.0 and active != id:
		return
	if active != "" and active != id:
		return
	if active != id:
		shows[id] = int(shows.get(id, 0)) + 1
		active = id
		show_left = rules.hint_sec
	hint = _line(id)

func _finish(id: String, keep: bool) -> void:
	if done.has(id):
		return
	done[id] = true
	if not keep and active == id:
		active = ""
		hint = ""
		show_left = 0.0
	_save()

func _line(id: String) -> String:
	match id:
		"move":
			return rules.move_text % InputGlyph.move()
		"attack":
			return rules.attack_text % InputGlyph.attack()
		"dash":
			return rules.dash_text % InputGlyph.dash()
		"loot":
			return rules.loot_text % InputGlyph.interact()
		"stealth":
			return rules.stealth_text
		"fire":
			return rules.fire_full_text if _hp_full else rules.fire_text
		"thickmoss":
			return rules.thickmoss_text % InputGlyph.skill2()
		"extract":
			return rules.extract_text
		"charm":
			return rules.charm_text
		_:
			return ""

func _tick(delta: float) -> void:
	for k in retry.keys():
		if active == k:
			continue
		retry[k] = maxf(0.0, float(retry[k]) - delta)
	if active != "":
		show_left = maxf(0.0, show_left - delta)
		var a := 1.0
		if show_left < 0.35:
			a = show_left / 0.35
		_hint.modulate.a = a
		_hint.text = hint
		_hint.visible = hint != "" and a > 0.02
		if show_left <= 0.0:
			var id := active
			active = ""
			hint = ""
			_hint.visible = false
			if not done.has(id) and int(shows.get(id, 0)) < rules.max_shows:
				retry[id] = rules.retry_sec
	else:
		_hint.visible = false
	banner_left = maxf(0.0, banner_left - delta)
	_banner.visible = banner_left > 0.0 and banner != ""
	_banner.text = banner
	_banner.modulate.a = 1.0 if banner_left > 0.3 else banner_left / 0.3
	cone_left = maxf(0.0, cone_left - delta)
	if _cone != null:
		_cone.visible = cone_left > 0.0 and _spotted is Node2D and is_instance_valid(_spotted)
		if _cone.visible:
			_cone.global_position = (_spotted as Node2D).global_position
			_cone.queue_redraw()
	if _flash_node != null and is_instance_valid(_flash_node) and _flash_n > 0:
		_flash_t += delta
		_flash_node.modulate.a = 1.0 if int(_flash_t / 0.12) % 2 == 0 else 0.1
		if _flash_t >= 0.24 * float(rules.telegraph_flashes):
			_flash_node.modulate.a = 1.0
			_flash_node = null
			_flash_n = 0

func _draw_cone() -> void:
	if _spotted == null or not is_instance_valid(_spotted) or _spotted.get("ai") == null:
		return
	var ai = _spotted.ai
	var ang := deg_to_rad(ai.sight_angle())
	var r: float = ai.sight_range()
	var pts := PackedVector2Array([Vector2.ZERO])
	var base: float = (_spotted as Node2D).facing.angle() - _cone.global_rotation
	for i in 17:
		pts.append(Vector2.from_angle(base - ang / 2.0 + ang * float(i) / 16.0) * r)
	_cone.draw_colored_polygon(pts, Color(1, 0.85, 0.3, 0.28))

func _arm_telegraph(visual: CanvasItem) -> void:
	if sealed or done.has("boss_telegraph"):
		return
	done["boss_telegraph"] = true
	_save()
	if visual == null:
		return
	_flash_node = visual
	_flash_n = rules.telegraph_flashes
	_flash_t = 0.0

func _on_death() -> void:
	if sealed or done.has("death"):
		return
	death_line = rules.death_text
	_epitaph = true
	shows["death"] = int(shows.get("death", 0)) + 1

func _on_village() -> void:
	_on_floor = false
	_near_fight = false
	_near_loot = false
	_near_fire = false
	_threat = false
	if death_line != "":
		_finish("death", false)
		death_line = ""

func _on_run_ended() -> void:
	if sealed:
		return
	if _saw_floor or not shows.is_empty() or not done.is_empty():
		_seal()

func _seal() -> void:
	sealed = true
	for id in STEPS:
		done[id] = true
	active = ""
	hint = ""
	exit_mark = false
	_save()

func _clear_run_flags() -> void:
	_moved = 0.0
	_floor_t = 0.0
	_on_floor = false
	_near_fight = false
	_fight_cleared = false
	_combo = false
	_threat = false
	_dash_n = 0
	_dash_dodged = false
	_near_loot = false
	_looted = false
	_spotted = null
	_chased = false
	_stealth_clear = false
	_near_fire = false
	_hp_full = false
	_used_fire = false
	_boss_zone = false
	_elite_seen = false
	_moss_broken = false
	_charge_dodged = false
	_guard_dead = false
	_extracted = false
	_charm = false
	_fight_group = ""
	_fight_seen = false
	_last_pos = Vector2.INF
	exit_mark = false

func _load() -> void:
	var cf := ConfigFile.new()
	if cf.load(path) != OK:
		return
	sealed = bool(cf.get_value("profile", "sealed", false))
	var raw = cf.get_value("profile", "tutorial_done", PackedStringArray())
	done.clear()
	if raw is PackedStringArray:
		for id in raw:
			done[id] = true
	elif raw is String and raw != "":
		for id in raw.split(",", false):
			done[id] = true

func _save() -> void:
	var cf := ConfigFile.new()
	cf.load(path)
	var ids := PackedStringArray()
	for k in done.keys():
		ids.append(str(k))
	cf.set_value("profile", "tutorial_done", ids)
	cf.set_value("profile", "sealed", sealed)
	cf.save(path)
