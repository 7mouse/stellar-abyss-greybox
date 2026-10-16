extends Node2D
## 一层开放地图：MapGen 生成一整张有机地形的平层地图，没有房间和门。
## 主角从起点出发，路上遇到巡逻组和营地（EnemyAI：视野锥、声音、联动、回归；AggroDirector：追击 ≤6、前摇 ≤3）；
## 走进层守区入口线 → 开口升起能量栅栏、层守出现；层守死后栅栏撤掉、撤离点亮起（撤离或下潜，进入下一层后无法返回）。

signal guard_killed
signal exit_activated
signal guard_zone_entered

const TYPE_NAMES := {"start": "起点", "guard": "层守区", "camp": "营地", "shrine": "神龛", "field": "野地", "grove": "林地", "ruin": "废墟"}
const TYPE_COLORS := {"start": Color(0.16, 0.2, 0.18), "guard": Color(0.22, 0.12, 0.14), "camp": Color(0.2, 0.15, 0.12),
	"shrine": Color(0.14, 0.15, 0.24), "field": Color(0.15, 0.17, 0.15), "grove": Color(0.12, 0.18, 0.13), "ruin": Color(0.17, 0.16, 0.15)}
const AGGRO_DEFAULT := preload("res://data/aggro_rules.tres")

var fd: FloorData
var layout: Dictionary
var depth := 1
var player: Player
var cam: FollowCam
var hud: Hud
var world: Node2D
var nav_region: NavigationRegion2D
var aggro: AggroRules
var wall_rects: Array = []
var interactables: Array = [] ## {pos, text, cb, enabled(Callable), id, key, hold}
var used := {} ## 互动 key -> true（每个只能用一次）
var guard: Guard
var guard_dead := false
var guard_rect := Rect2()
var guard_trigger: Area2D
var fence_bodies: Array = []
var exit_active := false
var exit_pos := Vector2.ZERO
var exit_rect: ColorRect
var camps_state := {} ## chunk id -> {alive, total, cleared, shrine_rect}
var rng := RandomNumberGenerator.new()
var guard_t0 := -1.0
var exit_activated_at := -1.0
var guard_killed_at := -1.0
var popup_open := false
var corpse_taken := false
var hold_key := ""
var hold_t := 0.0
var gen_ms := 0.0
var bake_ms := 0.0
var nav_ready := false
var chunk_overlay: Node2D
var director: AggroDirector
var aggro_overlay: Node2D ## 调试：视野锥和声音圈
var noises: Array = [] ## [pos, radius, t]
var visited := {} ## 探索过的区块 id
var minimap: Minimap
var _aggro_sync_t := 0.0
var player_in_thicket := false ## 树丛潜行（敌人视野 ×0.7），每 0.1 秒更新
var _thicket_t := 0.0

func _ready() -> void:
	if Game.run == null:
		Game.start_run.call_deferred()
		return
	depth = Game.run.depth
	fd = Game.floor_data(depth)
	aggro = AGGRO_DEFAULT.effective(fd.aggro_override)
	NoiseBus.rules = aggro
	NoiseBus.reset()
	director = AggroDirector.new()
	director.rules = aggro
	director.rng.seed = hash([Game.run.seed, depth, "aggro"])
	add_child(director)
	NoiseBus.noise.connect(_on_noise)
	var t0 := Time.get_ticks_usec()
	layout = MapGen.generate(Game.run.seed, depth, fd)
	gen_ms = (Time.get_ticks_usec() - t0) / 1000.0
	rng.seed = hash([Game.run.seed, depth, "floor"])
	world = Node2D.new()
	world.y_sort_enabled = true
	add_child(world)
	_build_map()
	_bake_nav()
	print("[map] 第 %d 层：区块 %d，生成 %.1f ms，导航烘焙 %.1f ms" % [depth, layout.chunks.size(), gen_ms, bake_ms])
	player = Player.new()
	player.depth = depth
	player.position = layout.start_pos
	world.add_child(player)
	player.hp = Game.run.hp
	player.refresh_stats()
	player.hp = mini(Game.run.hp, player.max_hp)
	player.died.connect(_on_player_died)
	player.dashed.connect(_on_dashed)
	_spawn_patrols()
	_spawn_camps()
	_build_aggro_overlay()
	cam = FollowCam.new()
	cam.target = player
	cam.smooth_sec = Game.player_stats.cam_smooth_sec
	add_child(cam)
	cam.make_current()
	cam.snap()
	hud = Hud.new()
	hud.player = player
	add_child(hud)
	minimap = Minimap.new()
	minimap.setup(self)
	hud.add_child(minimap)
	Game.run.floor_stats = {"t0": Time.get_ticks_msec() / 1000.0, "combat_sec": 0.0, "guard_sec": 0.0, "hp_start": player.hp, "dmg_taken": 0, "kills": 0, "level_start": Game.level()}
	hud.show_toast("第 %d 层 · 苔根林窟" % depth)

# ---------- 构建 ----------
func _build_map() -> void:
	var cp: float = layout.chunk_px
	# 地面与障碍：整张图两张贴图（每地形格 1 像素，线性过滤放大），看不到区块
	var imgs := MapGen.terrain_images(layout)
	for i in 2:
		var spr := Sprite2D.new()
		spr.texture = ImageTexture.create_from_image(imgs[i])
		spr.centered = false
		spr.scale = Vector2.ONE * MapGen.TCELL
		spr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		spr.z_index = -10 if i == 0 else -4
		add_child(spr)
	for r in layout.border:
		_solid(r, Color(0.22, 0.19, 0.16))
	for c in layout.chunks:
		for r in MapGen.chunk_walls(c):
			_solid(r, MapGen.KIND_COLORS[MapGen.T_RUIN])
		for i in c.obstacles.size():
			_solid(c.obstacles[i], Color(0, 0, 0, 0), true, MapGen.blocks_sight(c.obstacle_kinds[i]))
	# 层守区：入口栅栏 + 入口线触发器
	guard_rect = MapGen.chunk_rect(layout.chunks[layout.guard_chunk], cp)
	NoiseBus.wall_rect = guard_rect
	for e in layout.guard_entrances:
		fence_bodies.append(_solid(e.gap, Color(0.4, 0.85, 1.0), false))
	_set_fence(false)
	guard_trigger = Area2D.new()
	guard_trigger.collision_layer = 0
	guard_trigger.collision_mask = 2
	guard_trigger.monitorable = false
	var tcs := CollisionShape2D.new()
	var tsh := RectangleShape2D.new()
	tsh.size = guard_rect.grow(-60).size
	tcs.shape = tsh
	tcs.position = guard_rect.get_center()
	guard_trigger.add_child(tcs)
	add_child(guard_trigger)
	guard_trigger.body_entered.connect(_on_guard_zone_body)
	# 篝火（层守区入口外侧）、撤离点（层守区内侧）
	var fp: Vector2 = layout.campfire_pos
	UI.rect(self, fp - Vector2(30, 30), Vector2(60, 60), Color(1, 0.55, 0.15)).z_index = -5
	_add_interact(fp, "篝火：回复 %d%% HP" % roundi(fd.campfire_heal * 100), _use_campfire.bind("campfire"), func(): return not used.has("campfire"), "campfire", "campfire")
	exit_pos = layout.exit_pos
	exit_rect = UI.rect(self, exit_pos - Vector2(50, 50), Vector2(100, 100), Color(0.3, 0.3, 0.35))
	exit_rect.z_index = -5
	_add_interact(exit_pos, "撤离点", _use_exit, func(): return exit_active, "exit", "exit")
	# 前任尸体（起点区块）
	if Lineage.corpse.get("depth", 0) == depth:
		var cpos: Vector2 = layout.start_pos + Vector2(-160, 120)
		UI.rect(self, cpos - Vector2(36, 14), Vector2(72, 28), Color(0.55, 0.55, 0.6)).z_index = -5
		UI.label(self, "前任残留的数据实体", cpos + Vector2(-100, -60), 22, Color(0.7, 0.7, 0.8))
		_add_interact(cpos, "回收前任遗物", _take_corpse, func(): return not corpse_taken, "corpse", "corpse")
	# 强化神龛（无守卫）
	for i in layout.shrines.size():
		var c := MapGen.chunk_rect(layout.chunks[layout.shrines[i]], cp).get_center()
		var k := "shrine_%d" % i
		UI.rect(self, c - Vector2(30, 40), Vector2(60, 80), Color(0.55, 0.5, 1)).z_index = -5
		_add_interact(c, "强化神龛：3 选 1", _boon_altar.bind(k), func(): return not used.has(k), "shrine", k)
	# 营地神龛（清空营地后点亮）
	for cs in layout.spawn_points.camp:
		var k := "camp_shrine_%d" % cs.chunk
		var sr := UI.rect(self, cs.center - Vector2(30, 40), Vector2(60, 80), Color(0.3, 0.3, 0.4))
		sr.z_index = -5
		camps_state[cs.chunk] = {"alive": 0, "total": 0, "cleared": false, "shrine_rect": sr}
		var cid: int = cs.chunk
		_add_interact(cs.center, "营地神龛：3 选 1", _boon_altar.bind(k), func(): return camps_state[cid].cleared and not used.has(k), "camp_shrine", k)
	# 宝箱（长按 0.6 秒）、资源点（长按 1.0 秒）
	var sp: Dictionary = layout.spawn_points
	for i in sp.chest.size():
		var p: Vector2 = sp.chest[i]
		var k := "chest_%d" % i
		var r := UI.rect(self, p - Vector2(36, 26), Vector2(72, 52), Color(0.85, 0.7, 0.25))
		r.z_index = -5
		_add_interact(p, "打开宝箱", _open_chest.bind(k, r), func(): return not used.has(k), "chest", k, 0.6)
	for i in sp.node.size():
		var p: Vector2 = sp.node[i]
		var k := "node_%d" % i
		var r := UI.rect(self, p - Vector2(24, 24), Vector2(48, 48), Color(0.35, 0.95, 0.7))
		r.z_index = -5
		_add_interact(p, "采集萤苔丛", _take_node.bind(k, r), func(): return not used.has(k), "node", k, 1.0)
	_build_overlay()

## opaque = 挡视线和子弹（物理层 1 + OPAQUE_LAYER）；水、断崖只在层 1（只挡移动）
func _solid(r: Rect2, color: Color, wall := true, opaque := true) -> StaticBody2D:
	var sb := StaticBody2D.new()
	sb.collision_layer = 1 | (MapGen.OPAQUE_LAYER if opaque else 0)
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
	sb.set_meta("r", r)
	if wall:
		wall_rects.append(r)
	return sb

func _set_fence(up: bool) -> void:
	for sb in fence_bodies:
		(sb.get_meta("shape") as CollisionShape2D).set_deferred("disabled", not up)
		(sb.get_meta("rect") as ColorRect).visible = up

func fence_up() -> bool:
	return fence_bodies.any(func(sb): return (sb.get_meta("rect") as ColorRect).visible)

## 导航：外框为可走区域，全部实心矩形为障碍，agent_radius 24，运行时烘焙一次（整层一个 NavigationRegion2D）
func _bake_nav() -> void:
	var t0 := Time.get_ticks_usec()
	nav_region = get_node_or_null("Nav")
	if nav_region == null:
		nav_region = NavigationRegion2D.new()
		nav_region.name = "Nav"
		add_child(nav_region)
	var np := NavigationPolygon.new()
	np.agent_radius = 24.0
	var src := NavigationMeshSourceGeometryData2D.new()
	var b: Rect2 = layout.bounds
	src.add_traversable_outline(_rect_poly(b))
	for r in MapGen.all_solids(layout):
		src.add_obstruction_outline(_rect_poly(r))
	NavigationServer2D.bake_from_source_geometry_data(np, src)
	nav_region.navigation_polygon = np
	bake_ms = (Time.get_ticks_usec() - t0) / 1000.0
	nav_ready = np.get_polygon_count() > 0

static func _rect_poly(r: Rect2) -> PackedVector2Array:
	return PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])

func _add_interact(pos: Vector2, text: String, cb: Callable, enabled: Callable, id: String, key := "", hold := 0.0) -> void:
	interactables.append({"pos": pos, "text": text, "cb": cb, "enabled": enabled, "id": id, "key": key if key != "" else id, "hold": hold})

# ---------- 区块网格（F1 面板“显示区块网格”） ----------
func _build_overlay() -> void:
	chunk_overlay = Node2D.new()
	chunk_overlay.z_index = 50
	chunk_overlay.visible = false
	add_child(chunk_overlay)
	var cp: float = layout.chunk_px
	for c in layout.chunks:
		var rc := MapGen.chunk_rect(c, cp)
		var ln := Line2D.new()
		ln.width = 4
		ln.default_color = Color(1, 1, 0.3, 0.6)
		ln.points = PackedVector2Array([rc.position, Vector2(rc.end.x, rc.position.y), rc.end, Vector2(rc.position.x, rc.end.y), rc.position])
		chunk_overlay.add_child(ln)
		var mark := "（最短路）" if layout.path.has(c.id) else ""
		UI.label(chunk_overlay, "#%d %s%s" % [c.id, TYPE_NAMES[c.type], mark], rc.position + Vector2(24, 20), 40, Color(1, 1, 0.5))

func show_chunk_grid(on: bool) -> void:
	if chunk_overlay:
		chunk_overlay.visible = on

func chunk_label(id: int) -> String:
	return "#%d %s" % [id, TYPE_NAMES[layout.chunks[id].type]]

## 地图统计（F1 面板）：生成数量 + 场上活着的普通怪
func map_stats() -> Dictionary:
	var s := MapGen.stats(layout)
	s["enemies_alive"] = get_tree().get_nodes_in_group("enemies").filter(func(e): return e != guard).size()
	s["gen_ms"] = gen_ms
	s["bake_ms"] = bake_ms
	return s

func map_stats_text() -> String:
	var s := map_stats()
	return "第 %d 层（种子 %d）：区块 %d（普通 %d），最短路 %d 区块\n巡逻组 %d（%d 只），营地 %d（%d 只），场上普通怪 %d\n宝箱 %d，资源点 %d，强化神龛 %d，营地神龛 %d\n生成 %.1f ms，导航烘焙 %.1f ms" % [
		depth, layout.seed, s.chunks, s.normal_chunks, s.path_len, s.patrol_groups, s.patrol_enemies, s.camps, s.camp_enemies, s.enemies_alive,
		s.chests, s.nodes, s.shrines, s.camps, s.gen_ms, s.bake_ms]

# ---------- 刷怪 ----------
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

func spawn_enemy(eid: String, pos: Vector2, group := "") -> EnemyBase:
	var e := EnemyBase.new()
	e.setup(Game.enemies[eid], depth, fd)
	e.position = pos
	e.home_pos = pos
	e.use_nav = nav_ready
	e.set_meta("group", group)
	world.add_child(e)
	return e

## 地图怪：挂 EnemyAI。style = walk（巡逻）/ post（射手驻守）/ camp（营地待机）；route = 巡逻路线（含队形偏移）
func _map_enemy(eid: String, pos: Vector2, group: String, style := "", route: Array = []) -> EnemyBase:
	var e := spawn_enemy(eid, pos, group)
	e.rules = aggro
	e.no_go = guard_rect
	if style == "":
		style = "post" if eid == "rootshot" else "walk"
	var ai := EnemyAI.new()
	ai.setup(e, aggro, director, self, style, route)
	e.ai = ai
	e.add_child(ai)
	e.state = EnemyBase.S.PATROL
	return e

func _spawn_patrols() -> void:
	var gi := 0
	for p in layout.spawn_points.patrol:
		var c: Vector2 = p.points[0]
		for i in p.size:
			var off := Vector2(45, 0).rotated(TAU * i / p.size)
			var eid := _pick_enemy()
			var route: Array = p.points.map(func(q): return q + off)
			_map_enemy(eid, c + off, "p%d" % gi, "", route)
		gi += 1

func _spawn_camps() -> void:
	for cs in layout.spawn_points.camp:
		var st: Dictionary = camps_state[cs.chunk]
		for i in cs.size:
			var e := _map_enemy(_pick_enemy(), cs.center + Vector2(150, 0).rotated(TAU * i / cs.size), "c%d" % cs.chunk, "camp")
			e.set_meta("camp", cs.chunk)
			e.died.connect(_on_camp_member_died.bind(cs.chunk))
		st.alive = cs.size
		st.total = cs.size

func _on_camp_member_died(_e: EnemyBase, cid: int) -> void:
	var st: Dictionary = camps_state[cid]
	st.alive -= 1
	if st.alive <= 0 and not st.cleared:
		st.cleared = true
		(st.shrine_rect as ColorRect).color = Color(0.55, 0.5, 1)
		Game.run.floor_stats["camps_cleared"] = int(Game.run.floor_stats.get("camps_cleared", 0)) + 1
		hud.show_toast("营地已清空：营地神龛亮起")

func enemies_in_group(gid: String) -> Array:
	return get_tree().get_nodes_in_group("enemies").filter(func(e): return e.get_meta("group", "") == gid)

func guard_zone_enemies() -> Array:
	return get_tree().get_nodes_in_group("enemies").filter(func(e): return e.get_meta("summoned", false))

# ---------- 每帧 ----------
func _physics_process(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	var fighting := false
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.state != EnemyBase.S.IDLE and e.state != EnemyBase.S.RETURN and e.state != EnemyBase.S.PATROL and e.state != EnemyBase.S.ALERT:
			fighting = true
			break
	if fighting and Game.run.floor_stats.has("combat_sec"):
		Game.run.floor_stats.combat_sec += delta
	if guard_t0 >= 0.0 and not guard_dead and Game.run.floor_stats.has("guard_sec"):
		Game.run.floor_stats.guard_sec += delta
	if guard and is_instance_valid(guard):
		hud.show_boss(guard)
	else:
		hud.show_boss(null)
	var it := nearest_interactable()
	_tick_hold(it, delta)
	if it.is_empty():
		hud.prompt.text = ""
	elif it.hold > 0.0:
		hud.prompt.text = "【长按 E / 手柄B】%s%s" % [it.text, ("（%d%%）" % roundi(hold_t / it.hold * 100)) if hold_key == it.key else ""]
	else:
		hud.prompt.text = "【E / 手柄B】" + it.text
	if exit_rect:
		exit_rect.color = Color(0.4, 1, 0.6) if exit_active else Color(0.3, 0.3, 0.35)
	if chunk_overlay and Game.debug_panel and "show_chunks" in Game.debug_panel:
		chunk_overlay.visible = Game.debug_panel.show_chunks
	_thicket_t -= delta
	if _thicket_t <= 0.0:
		_thicket_t = 0.1
		player_in_thicket = MapGen.near_thicket(layout, player.global_position, aggro.thicket_edge_px)
	var k := MapGen.chunk_at(layout, player.global_position)
	if k >= 0 and not visited.has(k):
		visited[k] = true
		Game.run.floor_stats["chunks_visited"] = visited.size()
	Game.run.floor_stats["chasers_peak"] = director.chasers_peak
	_aggro_sync_t -= delta
	if _aggro_sync_t <= 0.0:
		_aggro_sync_t = 0.5
		AGGRO_DEFAULT.effective(fd.aggro_override, aggro) ## F1 面板改动同步到本层生效的参数（同一个对象，所有敌人立即读到）
	_tick_aggro_overlay(delta)

func _tick_hold(it: Dictionary, delta: float) -> void:
	if it.is_empty() or it.hold <= 0.0 or popup_open or get_tree().paused or not Input.is_action_pressed("interact"):
		hold_key = ""
		hold_t = 0.0
		return
	if hold_key != it.key:
		hold_key = it.key
		hold_t = 0.0
	hold_t += delta
	if hold_t >= it.hold:
		hold_key = ""
		hold_t = 0.0
		it.cb.call()

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

## 按一下互动；需要长按的（宝箱、资源点）这里不触发，由 _tick_hold 计时
func interact() -> bool:
	var it := nearest_interactable()
	if it.is_empty() or popup_open or it.hold > 0.0:
		return false
	it.cb.call()
	return true

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
func _use_campfire(key: String) -> void:
	used[key] = true
	var n := roundi(player.max_hp * fd.campfire_heal)
	player.heal(n)
	hud.show_toast("篝火回复 %d HP" % n)

func _open_chest(key: String, vis: ColorRect = null) -> void:
	used[key] = true
	NoiseBus.emit_kind(player.global_position, "chest")
	if vis:
		vis.color = Color(0.4, 0.35, 0.2)
	var got := fd.chest_loot.roll(rng, 1.0 + float(player.mods.get("rare_drop_pct", 0)))
	var names: Array = []
	for st in got:
		Game.run.add_item(st)
		names.append("%s ×%d" % [st.item.display_name, st.count])
	hud.show_toast("宝箱：" + "，".join(names))

func _take_node(key: String, vis: ColorRect = null) -> void:
	used[key] = true
	if vis:
		vis.color = Color(0.2, 0.3, 0.25)
	Game.run.floor_stats["nodes_taken"] = int(Game.run.floor_stats.get("nodes_taken", 0)) + 1
	var names: Array = []
	if fd.node_loot:
		for st in fd.node_loot.roll(rng):
			Game.run.add_item(st)
			names.append("%s ×%d" % [st.item.display_name, st.count])
	hud.show_toast("采集：" + "，".join(names))

func _boon_altar(key: String) -> void:
	used[key] = true
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
func _on_guard_zone_body(body: Node) -> void:
	if body == player and guard == null and not guard_dead:
		_enter_guard_zone.call_deferred() ## 物理回调里不能直接加物体

func _enter_guard_zone() -> void:
	if guard != null or guard_dead or not is_inside_tree():
		return
	_set_fence(true)
	spawn_guard()
	guard_zone_entered.emit()

func spawn_guard() -> Guard:
	guard = Guard.new()
	guard.setup_guard(fd.guard, depth)
	guard.position = layout.guard_pos
	guard.use_nav = nav_ready
	guard.set_meta("zone", true)
	guard.died.connect(_on_guard_died)
	guard.summon_requested.connect(_on_summon)
	world.add_child(guard)
	guard_t0 = Time.get_ticks_msec() / 1000.0
	return guard

## 召唤物刷新点：层守区内的随机空地，离主角 ≥ min_player_dist
func zone_point(min_player_dist := 160.0) -> Vector2:
	var rc := guard_rect.grow(-110)
	var solids := MapGen.all_solids(layout)
	for i in 60:
		var p := Vector2(rng.randf_range(rc.position.x, rc.end.x), rng.randf_range(rc.position.y, rc.end.y))
		if not MapGen.is_free(p, solids, 50.0):
			continue
		if player and p.distance_to(player.global_position) < min_player_dist and i < 50:
			continue
		return p
	return rc.get_center()

func _on_summon(eid: String, n: int) -> void:
	for i in n:
		var e := spawn_enemy(eid, zone_point(160.0), "summon")
		e.set_meta("summoned", true)

## 层守区入口（第一个开口）内侧 / 外侧的点
func guard_entry_pos(inside := true) -> Vector2:
	var e: Dictionary = layout.guard_entrances[0]
	return e.gap.get_center() + Vector2(e.dir) * (-200.0 if inside else 200.0)

## 调试：传送到层守区入口外侧（篝火旁），走进去即开战
func debug_guard() -> void:
	player.global_position = layout.campfire_pos
	cam.snap()

## 调试 / 测试：直接走进层守区（触发栅栏和层守）
func debug_enter_guard_zone() -> void:
	player.global_position = guard_entry_pos(true)
	cam.snap()

func _on_guard_died(_g: EnemyBase) -> void:
	guard_dead = true
	guard_killed_at = Time.get_ticks_msec() / 1000.0
	_guard_log_flash()
	guard_killed.emit()
	for e in guard_zone_enemies():
		e.queue_free()
	await get_tree().create_timer(0.5, false).timeout
	if not is_inside_tree():
		return
	_set_fence(false)
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

# ---------- 调试：视野锥和声音圈、追击计数 ----------
func _on_noise(pos: Vector2, radius: float, _kind: String) -> void:
	noises.append([pos, radius, 0.8])

func _build_aggro_overlay() -> void:
	aggro_overlay = Node2D.new()
	aggro_overlay.z_index = 40
	aggro_overlay.visible = false
	aggro_overlay.draw.connect(_draw_aggro_overlay)
	add_child(aggro_overlay)

func show_aggro_debug() -> bool:
	return Game.debug_panel != null and Game.debug_panel.get("show_aggro") == true

func _tick_aggro_overlay(delta: float) -> void:
	for n in noises:
		n[2] -= delta
	noises = noises.filter(func(n): return n[2] > 0.0)
	aggro_overlay.visible = show_aggro_debug()
	if aggro_overlay.visible:
		aggro_overlay.queue_redraw()
	if Game.debug_panel and Game.debug_panel.has_method("set_aggro_counts"):
		Game.debug_panel.set_aggro_counts(director.chasing_count(), director.windup_count(), director.chasers_peak, director.attackers_peak)

const STATE_COLORS := {EnemyBase.S.PATROL: Color(0.4, 1, 0.5, 0.18), EnemyBase.S.ALERT: Color(1, 0.9, 0.3, 0.25), EnemyBase.S.RETURN: Color(0.5, 0.6, 1, 0.15)}

func _draw_aggro_overlay() -> void:
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.ai == null or e.ai.sleeping:
			continue
		var col: Color = STATE_COLORS.get(e.state, Color(1, 0.3, 0.3, 0.22))
		var r: float = e.ai.sight_range()
		var ang: float = deg_to_rad(e.ai.sight_angle())
		var pts := PackedVector2Array([e.global_position])
		var base: float = e.facing.angle()
		for i in 17:
			pts.append(e.global_position + Vector2.from_angle(base - ang / 2 + ang * i / 16.0) * r)
		if ang >= TAU - 0.01:
			pts.remove_at(0)
		aggro_overlay.draw_colored_polygon(pts, col)
		aggro_overlay.draw_arc(e.global_position, e.rules.sense_radius, 0, TAU, 32, Color(1, 1, 1, 0.3), 2)
	for n in noises:
		aggro_overlay.draw_arc(n[0], n[1], 0, TAU, 64, Color(0.4, 0.8, 1, clampf(n[2], 0, 1)), 4)

## 网页性能检查：主角周围刷 n 只地图怪并开打（greybox.perfRing()）
func debug_perf_ring(n: int) -> void:
	var c := player.global_position
	var ring: Array = []
	for i in n:
		ring.append(_map_enemy(["mushling", "rootshot", "shellbug"][i % 3], c + Vector2(260, 0).rotated(TAU * i / n), "perf"))
	await get_tree().physics_frame
	if is_instance_valid(ring[0]):
		ring[0].ai.enter_chase("perf")
