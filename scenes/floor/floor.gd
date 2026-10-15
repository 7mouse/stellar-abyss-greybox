extends Node2D
## 一层迷宫：房间拼接、房门规则、战斗波次、篝火、宝箱/强化支路、层守房与撤离点。
## 战斗房怪没清完门不开；层守房进门锁门，层守死后撤离点亮起；本层房间可以回头走，进入下一层后无法返回。

signal room_entered(id: int)
signal guard_killed
signal exit_activated

var fd: FloorData
var layout: Dictionary
var depth := 1
var player: Player
var cam: FollowCam
var hud: Hud
var world: Node2D
var rooms_state := {} ## id -> {cleared, wave, spawning, rewarded, used}
var door_bodies := {} ## id -> [StaticBody2D]
var door_rects := {} ## id -> [ColorRect]
var wall_rects: Array = []
var interactables: Array = [] ## {pos, text, cb, enabled(Callable), id}
var current_room := -1
var guard: Guard
var guard_dead := false
var exit_active := false
var exit_pos := Vector2.ZERO
var exit_rect: ColorRect
var rng := RandomNumberGenerator.new()
var combat_t0 := -1.0
var guard_t0 := -1.0
var exit_activated_at := -1.0
var guard_killed_at := -1.0
var popup_open := false
var corpse_taken := false

func _ready() -> void:
	if Game.run == null:
		Game.start_run.call_deferred()
		return
	depth = Game.run.depth
	fd = Game.floor_data(depth)
	layout = FloorGen.generate(Game.run.seed, depth, fd)
	rng.seed = hash([Game.run.seed, depth, "floor"])
	world = Node2D.new()
	world.y_sort_enabled = true
	add_child(world)
	_build()
	player = Player.new()
	player.depth = depth
	player.position = FloorGen.room_center(layout.rooms[layout.entrance])
	world.add_child(player)
	player.hp = Game.run.hp
	player.refresh_stats()
	player.hp = mini(Game.run.hp, player.max_hp)
	player.died.connect(_on_player_died)
	player.dashed.connect(_on_dashed)
	cam = FollowCam.new()
	cam.target = player
	cam.smooth_sec = Game.player_stats.cam_smooth_sec
	add_child(cam)
	cam.make_current()
	cam.snap()
	hud = Hud.new()
	hud.player = player
	add_child(hud)
	Game.run.floor_stats = {"t0": Time.get_ticks_msec() / 1000.0, "combat_sec": 0.0, "guard_sec": 0.0, "hp_start": player.hp, "dmg_taken": 0, "kills": 0, "level_start": Game.level()}
	hud.show_toast("第 %d 层 · 苔根林窟" % depth)

# ---------- 构建 ----------
func _build() -> void:
	for r in layout.rooms:
		var rc := FloorGen.room_rect(r)
		var col: Color = {"entrance": Color(0.16, 0.2, 0.18), "combat": Color(0.15, 0.17, 0.15), "campfire": Color(0.22, 0.18, 0.12),
			"guard": Color(0.22, 0.12, 0.14), "chest": Color(0.18, 0.18, 0.12), "boon": Color(0.14, 0.15, 0.24)}[r.type]
		var fl := UI.rect(self, rc.position, rc.size, col)
		fl.z_index = -10
		rooms_state[r.id] = {"cleared": r.type != "combat", "wave": 0, "spawning": false, "rewarded": false, "used": false}
		var w := FloorGen.room_walls(r)
		for wr in w.walls:
			_solid(wr, Color(0.32, 0.27, 0.22))
		for o in FloorGen.room_obstacles(r):
			_solid(o, Color(0.3, 0.33, 0.25))
		door_bodies[r.id] = []
		door_rects[r.id] = []
		for d in w.doors:
			var g: Rect2 = w.doors[d]
			var sb := _solid(g, Color(0.75, 0.35, 0.2), false)
			door_bodies[r.id].append(sb)
			door_rects[r.id].append(sb.get_meta("rect"))
		_set_doors(r.id, false)
		var c := rc.get_center()
		match r.type:
			"campfire":
				UI.rect(self, c - Vector2(30, 30), Vector2(60, 60), Color(1, 0.55, 0.15)).z_index = -5
				_add_interact(c, "篝火：回复 %d%% HP" % roundi(fd.campfire_heal * 100), _use_campfire.bind(r.id), func(): return not rooms_state[r.id].used, "campfire")
			"chest":
				UI.rect(self, c - Vector2(36, 26), Vector2(72, 52), Color(0.85, 0.7, 0.25)).z_index = -5
				_add_interact(c, "打开宝箱", _open_chest.bind(r.id), func(): return not rooms_state[r.id].used, "chest")
			"boon":
				UI.rect(self, c - Vector2(30, 40), Vector2(60, 80), Color(0.55, 0.5, 1)).z_index = -5
				_add_interact(c, "强化祭坛：3 选 1", _boon_altar.bind(r.id), func(): return not rooms_state[r.id].used, "boon")
			"guard":
				exit_pos = c + Vector2(0, -260)
				exit_rect = UI.rect(self, exit_pos - Vector2(50, 50), Vector2(100, 100), Color(0.3, 0.3, 0.35))
				exit_rect.z_index = -5
				_add_interact(exit_pos, "撤离点", _use_exit, func(): return exit_active, "exit")
			"entrance":
				if Lineage.corpse.get("depth", 0) == depth:
					var cp := c + Vector2(-160, 120)
					UI.rect(self, cp - Vector2(36, 14), Vector2(72, 28), Color(0.55, 0.55, 0.6)).z_index = -5
					UI.label(self, "前任残留的数据实体", cp + Vector2(-100, -60), 22, Color(0.7, 0.7, 0.8))
					_add_interact(cp, "回收前任遗物", _take_corpse, func(): return not corpse_taken, "corpse")

func _solid(r: Rect2, color: Color, wall := true) -> StaticBody2D:
	var sb := StaticBody2D.new()
	sb.collision_layer = 1
	sb.collision_mask = 0
	var cs := CollisionShape2D.new()
	var sh := RectangleShape2D.new()
	sh.size = r.size
	cs.shape = sh
	cs.position = r.get_center()
	sb.add_child(cs)
	add_child(sb)
	var vis := UI.rect(self, r.position, r.size, color)
	vis.z_index = -4
	sb.set_meta("rect", vis)
	sb.set_meta("shape", cs)
	if wall:
		wall_rects.append(r)
	return sb

func _set_doors(id: int, locked: bool) -> void:
	for sb in door_bodies[id]:
		(sb.get_meta("shape") as CollisionShape2D).set_deferred("disabled", not locked)
		(sb.get_meta("rect") as ColorRect).visible = locked

func doors_locked(id: int) -> bool:
	return door_rects[id].any(func(r): return r.visible)

func _add_interact(pos: Vector2, text: String, cb: Callable, enabled: Callable, id: String) -> void:
	interactables.append({"pos": pos, "text": text, "cb": cb, "enabled": enabled, "id": id})

# ---------- 每帧 ----------
func room_at(p: Vector2) -> int:
	for r in layout.rooms:
		if FloorGen.room_rect(r).grow(-30).has_point(p):
			return r.id
	return -1

func _physics_process(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	var rid := room_at(player.global_position)
	if rid >= 0 and rid != current_room:
		current_room = rid
		_on_enter_room(rid)
	if combat_t0 >= 0.0:
		Game.run.floor_stats.combat_sec += delta
	if guard_t0 >= 0.0 and not guard_dead:
		Game.run.floor_stats.guard_sec += delta
	_tick_waves()
	if guard and is_instance_valid(guard):
		hud.show_boss(guard)
	else:
		hud.show_boss(null)
	var it := nearest_interactable()
	hud.prompt.text = ("【E / 手柄B】" + it.text) if not it.is_empty() else ""
	if exit_rect:
		exit_rect.color = Color(0.4, 1, 0.6) if exit_active else Color(0.3, 0.3, 0.35)

func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("interact") and not get_tree().paused:
		interact()

func nearest_interactable() -> Dictionary:
	var best := {}
	var bd := Game.player_stats.interact_range + 40.0
	for it in interactables:
		if it.enabled.call():
			var d: float = player.global_position.distance_to(it.pos)
			if d <= bd:
				bd = d
				best = it
	return best

func interact() -> bool:
	var it := nearest_interactable()
	if it.is_empty() or popup_open:
		return false
	it.cb.call()
	return true

func _on_enter_room(id: int) -> void:
	room_entered.emit(id)
	var r: Dictionary = layout.rooms[id]
	var st: Dictionary = rooms_state[id]
	if r.type == "combat" and not st.cleared and st.wave == 0:
		_set_doors(id, true)
		combat_t0 = Time.get_ticks_msec() / 1000.0
		_spawn_wave(id)
	elif r.type == "guard" and guard == null and not guard_dead:
		_set_doors(id, true)
		spawn_guard()

# ---------- 战斗房 ----------
func _wave_size() -> int:
	return rng.randi_range(fd.wave_size_min, fd.wave_size_max)

func _pick_enemy() -> String:
	var mix := fd.mix()
	var tot := 0.0
	for k in mix:
		tot += mix[k]
	var x := rng.randf() * tot
	for k in mix:
		x -= mix[k]
		if x < 0.0:
			return k
	return mix.keys()[0]

func free_point(id: int, min_player_dist := 260.0) -> Vector2:
	var r: Dictionary = layout.rooms[id]
	var rc := FloorGen.room_rect(r).grow(-110)
	var obs := FloorGen.room_obstacles(r)
	for i in 60:
		var p := Vector2(rng.randf_range(rc.position.x, rc.end.x), rng.randf_range(rc.position.y, rc.end.y))
		if obs.any(func(o): return o.grow(50).has_point(p)):
			continue
		if player and p.distance_to(player.global_position) < min_player_dist and i < 50:
			continue
		return p
	return rc.get_center()

func _spawn_wave(id: int) -> void:
	var st: Dictionary = rooms_state[id]
	st.wave += 1
	for i in _wave_size():
		spawn_enemy(_pick_enemy(), free_point(id), id)

func spawn_enemy(eid: String, pos: Vector2, room := -1) -> EnemyBase:
	var e := EnemyBase.new()
	e.setup(Game.enemies[eid], depth, fd)
	e.position = pos
	e.walls = wall_rects
	e.set_meta("room", room)
	world.add_child(e)
	return e

func enemies_in_room(id: int) -> Array:
	return get_tree().get_nodes_in_group("enemies").filter(func(e): return e.get_meta("room", -1) == id)

func _tick_waves() -> void:
	for id in rooms_state:
		var st: Dictionary = rooms_state[id]
		if st.cleared or st.wave == 0 or st.spawning:
			continue
		if enemies_in_room(id).is_empty():
			if st.wave < fd.waves:
				st.spawning = true
				_next_wave_later(id)
			else:
				_room_cleared(id)

func _next_wave_later(id: int) -> void:
	await get_tree().create_timer(fd.wave_delay, false).timeout
	if not is_inside_tree():
		return
	rooms_state[id].spawning = false
	_spawn_wave(id)

func _room_cleared(id: int) -> void:
	var st: Dictionary = rooms_state[id]
	st.cleared = true
	_set_doors(id, false)
	combat_t0 = -1.0
	hud.show_toast("房间已清空")
	if fd.boon_rooms and (id == layout.first_combat or id == layout.last_combat) and not st.rewarded:
		st.rewarded = true
		offer_boons()

# ---------- 强化 3 选 1 ----------
func offer_boons() -> void:
	var opts := Boons.offer(Game.run.boons, rng)
	if opts.is_empty():
		hud.show_toast("强化已全部获得")
		return
	popup_open = true
	var items := opts.map(func(b): return {"text": "%s：%s" % [b.display_name, b.desc]})
	var p := ChoicePopup.open(self, "选择一个强化", items, Game.auto_pick)
	var i: int = await p.chosen
	popup_open = false
	give_boon(opts[i])

func give_boon(b: BoonData) -> void:
	Game.run.add_boon(b)
	player.refresh_stats()
	hud.show_toast("获得强化：" + b.display_name)

func _on_dashed(_from: Vector2, to: Vector2) -> void:
	var dmg := int(player.mods.get("afterimage_dmg", 0))
	if dmg <= 0:
		return
	var h := Hitbox.new()
	h.team = "player"
	h.source_name = "残影"
	h.position = to
	world.add_child(h)
	h.begin(dmg, 70.0, 360.0, Vector2.RIGHT)
	await get_tree().create_timer(0.5, false).timeout
	if is_instance_valid(h):
		h.queue_free()

# ---------- 互动 ----------
func _use_campfire(id: int) -> void:
	rooms_state[id].used = true
	var n := roundi(player.max_hp * fd.campfire_heal)
	player.heal(n)
	hud.show_toast("篝火回复 %d HP" % n)

func _open_chest(id: int) -> void:
	rooms_state[id].used = true
	var got := fd.chest_loot.roll(rng, 1.0 + float(player.mods.get("rare_drop_pct", 0)))
	var names: Array = []
	for st in got:
		Game.run.add_item(st)
		names.append("%s ×%d" % [st.item.display_name, st.count])
	hud.show_toast("宝箱：" + "，".join(names))

func _boon_altar(id: int) -> void:
	rooms_state[id].used = true
	offer_boons()

func _take_corpse() -> void:
	corpse_taken = true
	var c := Lineage.corpse
	var msg := []
	if String(c.get("item", "")) != "":
		var it := Items.get_item(c.item)
		Game.run.add_item(ItemStack.new(it, 1))
		msg.append(it.display_name)
	else:
		Game.run.add_item(ItemStack.new(Items.get_item("moss"), Lineage.legacy_rules.corpse_fallback_mats))
		msg.append("萤苔 ×%d" % Lineage.legacy_rules.corpse_fallback_mats)
	if int(c.get("shards", 0)) > 0:
		Game.run.shards_carried += int(c.shards)
		msg.append("记忆碎片 ×%d" % int(c.shards))
	Lineage.corpse = {}
	Lineage.save()
	player.refresh_stats()
	hud.show_toast("回收：" + "，".join(msg))

# ---------- 层守 ----------
func spawn_guard() -> Guard:
	var gr: Dictionary = layout.rooms[layout.guard]
	guard = Guard.new()
	guard.setup_guard(fd.guard, depth)
	guard.position = FloorGen.room_center(gr) + Vector2(0, -80)
	guard.walls = wall_rects
	guard.set_meta("room", gr.id)
	guard.died.connect(_on_guard_died)
	guard.summon_requested.connect(_on_summon)
	world.add_child(guard)
	guard_t0 = Time.get_ticks_msec() / 1000.0
	return guard

func _on_summon(eid: String, n: int) -> void:
	for i in n:
		var e := spawn_enemy(eid, free_point(layout.guard, 160.0), layout.guard)
		e.set_meta("summoned", true)

## 调试：直接打出层守（传送到层守房）
func debug_guard() -> void:
	var gr: Dictionary = layout.rooms[layout.guard]
	for r in layout.rooms:
		if r.type == "combat":
			rooms_state[r.id].cleared = true
			_set_doors(r.id, false)
	player.global_position = FloorGen.room_center(gr) + Vector2(0, 250)
	cam.snap()

func _on_guard_died(_g: EnemyBase) -> void:
	guard_dead = true
	guard_killed_at = Time.get_ticks_msec() / 1000.0
	_guard_log_flash()
	guard_killed.emit()
	for e in enemies_in_room(layout.guard):
		e.queue_free()
	await get_tree().create_timer(0.5, false).timeout
	if not is_inside_tree():
		return
	_set_doors(layout.guard, false)
	exit_active = true
	exit_activated_at = Time.get_ticks_msec() / 1000.0
	exit_activated.emit()
	hud.show_toast("撤离点已亮起")

## 线索 2：层守第一次被击杀必定闪现，之后按 log_repeat_chance
func _guard_log_flash() -> void:
	var key := "guard_seen_%d" % depth
	var first: bool = not Lineage.flags.get(key, false)
	if first or Game.rng.randf() < Game.clues.log_repeat_chance:
		Lineage.flags[key] = true
		Lineage.save()
		var t := Game.clues.guard_log(depth).replace("{gen}", "%04d" % int(Lineage.current().gen_no)).replace("{yield}", "%.1f" % (Game.run.kills * 0.1))
		SysLog.flash(t)
		Game.run.see_clue("guard_log_%d" % depth)

# ---------- 撤离点 ----------
func _use_exit() -> void:
	popup_open = true
	var opts := [{"text": "撤离：回村结算（带回全部收获）"}]
	if depth < Game.FINAL_FLOOR:
		opts.append({"text": "下潜：进入第 %d 层（回复 %d%% HP，无法返回本层）" % [depth + 1, roundi(Game.player_stats.heal_between_floors * 100)]})
	var p := ChoicePopup.open(self, "撤离点", opts)
	var i: int = await p.chosen
	popup_open = false
	choose_exit(i == 1)

func choose_exit(descend: bool) -> void:
	Game.run.hp = player.hp
	if descend and depth < Game.FINAL_FLOOR:
		Game.log_floor("descend")
		Game.descend()
	else:
		Game.log_floor("extract")
		Game.extract()

func _on_player_died(cause: String) -> void:
	Game.run.hp = 0
	Game.log_floor("death")
	Game.on_player_died(cause)
