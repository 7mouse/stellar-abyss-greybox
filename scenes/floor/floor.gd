extends Node2D
## 一层开放地图：MapGen 生成一整张有机地形的平层地图，没有房间和门。
## 主角从起点出发，路上遇到巡逻组和营地（EnemyAI：视野锥、声音、联动、回归；AggroDirector：追击 ≤6、前摇 ≤3）；
## 走进层主区入口线 → 开口升起能量栅栏、层主出现；层主死后栅栏撤掉、撤离点亮起（撤离或下潜，进入下一层后无法返回）。

signal guard_killed
signal exit_activated
signal guard_zone_entered

const TYPE_NAMES := {"start": "起点", "guard": "层主区", "camp": "营地", "shrine": "神龛", "field": "野地", "grove": "林地", "ruin": "废墟"}
const TYPE_COLORS := {"start": Color(0.16, 0.2, 0.18), "guard": Color(0.22, 0.12, 0.14), "camp": Color(0.2, 0.15, 0.12),
	"shrine": Color(0.14, 0.15, 0.24), "field": Color(0.15, 0.17, 0.15), "grove": Color(0.12, 0.18, 0.13), "ruin": Color(0.17, 0.16, 0.15)}
const AGGRO_DEFAULT := preload("res://data/aggro_rules.tres")
const Floor1DressScript := preload("res://scenes/floor/floor1_dress.gd")

var fd: FloorData
var _first_run := true
var epitaph_line: Label
var _epitaph_reading := false
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
var killed_ids: Array = [] ## 本层已击杀的地图怪 id（p组:序号 / c营地:序号），回村后再进来不刷新
var channeling := false
var channel_t := 0.0
var _recall_done := false
var _recall_was_blocked := false
var last_recall_hint := ""
var guard: Guard
var guard_dead := false
var guard_rect := Rect2()
var guard_trigger: Area2D
var fence_bodies: Array = []
var arena_hazards: Array = []
var _calm_t := 1e9 ## 距离上次战斗的秒数
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
	Audio.enter_floor()
	Audio.loop("SFX-47", "Ambience")
	depth = Game.run.depth
	Game.recall.settle_on_floor_entry()
	fd = Game.floor_data(depth)
	aggro = AGGRO_DEFAULT.effective(fd.aggro_override)
	NoiseBus.rules = aggro
	NoiseBus.reset()
	director = AggroDirector.new()
	director.rules = aggro
	director.rng.seed = hash([Game.run.seed, depth, "aggro"])
	add_child(director)
	NoiseBus.noise.connect(_on_noise)
	var first_run := _floor1_first_run()
	var t0 := Time.get_ticks_usec()
	layout = MapGen.generate(Game.run.seed, depth, fd, first_run)
	gen_ms = (Time.get_ticks_usec() - t0) / 1000.0
	_apply_floor_memory()
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
	player.damaged.connect(_on_player_damaged)
	player.dashed.connect(_on_dashed)
	_spawn_patrols()
	_spawn_camps()
	_spawn_landmarks()
	_build_aggro_overlay()
	cam = FollowCam.new()
	cam.target = player
	cam.smooth_sec = Game.player_stats.cam_smooth_sec
	var lim: Rect2 = layout.bounds.grow(float(fd.map_border_px))
	cam.limit_rect = lim
	add_child(cam)
	cam.make_current()
	cam.snap()
	_attach_look()
	hud = Hud.new()
	hud.player = player
	add_child(hud)
	minimap = Minimap.new()
	minimap.setup(self)
	hud.add_child(minimap)
	Game.run.floor_stats = {"t0": Time.get_ticks_msec() / 1000.0, "combat_sec": 0.0, "guard_sec": 0.0, "hp_start": player.hp, "dmg_taken": 0, "kills": 0, "level_start": Game.level(),
		"chunks_visited": 0, "encounters": 0, "chasers_peak": 0, "camps_cleared": 0, "nodes_taken": 0,
		"charm_used": 0, "charm_floor": 0, "charm_interrupted": 0, "charm_source": Game.run.charm_source if Game.recall.carrying() else ""}
	hud.show_toast("第 %d 层 · 苔根林窟 · %s" % [depth, fd.ecology.display_name] if fd.ecology else "第 %d 层 · 苔根林窟" % depth)

# ---------- 构建 ----------
func _build_map() -> void:
	var cp: float = layout.chunk_px
	# 地面与障碍：预先合成一张贴图（每地形格 1 像素，线性过滤放大），看不到区块。
	# 性能：原来地面、障碍两张整图各铺满一次屏幕，网页软件渲染下填充耗时导致掉帧，合成后只画一次
	var imgs := MapGen.terrain_images(layout)
	var comp: Image = imgs[0]
	comp.blend_rect(imgs[1], Rect2i(Vector2i.ZERO, comp.get_size()), Vector2i.ZERO)
	var tex_scale := MapGen.TCELL
	if depth == 1:
		comp = Floor1DressScript.bake(layout, comp, int(Game.run.seed))
		tex_scale = Floor1DressScript.WORLD_PER_TEX
	var spr := Sprite2D.new()
	spr.texture = ImageTexture.create_from_image(comp)
	spr.centered = false
	spr.scale = Vector2.ONE * tex_scale
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	spr.z_index = -10
	add_child(spr)
	if depth == 1:
		spr.set_meta("floor1_stones", true)
	terrain_sprites.append(spr)
	for r in layout.border:
		_solid(r, Color(0.22, 0.19, 0.16))
	for c in layout.chunks:
		for r in MapGen.chunk_walls(c):
			_solid(r, MapGen.KIND_COLORS[MapGen.T_RUIN])
		for i in c.obstacles.size():
			_solid(c.obstacles[i], Color(0, 0, 0, 0), true, MapGen.blocks_sight(c.obstacle_kinds[i]))
		if c.get("no_recall", false):
			var rc := MapGen.chunk_rect(c, cp)
			var tint := UI.rect(self, rc.position, rc.size, Color(0.55, 0.12, 0.12, 0.16))
			tint.z_index = -8
			UI.label(self, "陷阱", rc.get_center() + Vector2(-36, -24), 40, Color(1, 0.45, 0.4))
	# 层主区：入口栅栏 + 入口线触发器
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
	# 篝火（层主区入口外侧）、撤离点（层主区内侧）
	var fp: Vector2 = layout.campfire_pos
	UI.rect(self, fp - Vector2(30, 30), Vector2(60, 60), Color(1, 0.55, 0.15)).z_index = -5
	_add_interact(fp, "篝火：回复 %d%% HP" % roundi(fd.campfire_heal * 100), _use_campfire.bind("campfire"), func(): return not used.has("campfire"), "campfire", "campfire")
	exit_pos = layout.exit_pos
	exit_rect = UI.rect(self, exit_pos - Vector2(70, 70), Vector2(140, 140), Color(0.12, 0.28, 0.32, 0.55))
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
		var r := UI.rect(self, p - Vector2(36, 26), Vector2(72, 52), Color(0.4, 0.35, 0.2) if used.has(k) else Color(0.85, 0.7, 0.25))
		r.z_index = -5
		_add_interact(p, "打开宝箱", _open_chest.bind(k, r), func(): return not used.has(k), "chest", k, 0.6)
	for i in sp.node.size():
		var p: Vector2 = sp.node[i]
		var k := "node_%d" % i
		var r := UI.rect(self, p - Vector2(24, 24), Vector2(48, 48), Color(0.2, 0.3, 0.25) if used.has(k) else Color(0.35, 0.95, 0.7))
		r.z_index = -5
		_add_interact(p, "采集萤苔丛", _take_node.bind(k, r), func(): return not used.has(k), "node", k, 1.0)
	# 环境机关（生态 §8.1）
	for h in sp.get("hazard", []):
		_spawn_hazard(fd.ecology.hazards[h.idx], h.pos, false)
	_build_overlay()

## 机关节点；arena = 层主场地机关（层主死后清掉）
func _spawn_hazard(hd: HazardData, pos: Vector2, arena: bool) -> Hazard:
	var h: Hazard
	match hd.id:
		"spore_pod": h = SporePod.new()
		"root_snare": h = RootSnare.new()
		"falling_rock": h = FallingRock.new()
		_: return null
	h.setup(hd, pos, arena)
	world.add_child(h)
	if arena:
		arena_hazards.append(h)
	return h

## 层主场地机关：阶段 1 进场就放，或只在二阶段出现（落石）
func _spawn_arena_hazards(phase: int) -> void:
	var lord := fd.lord()
	if lord == null or lord.arena_hazard == null or lord.arena_hazard.id == "root_pillar":
		return
	if lord.arena_hazard_phase2_only != (phase == 2):
		return
	var pts: Array = []
	for i in lord.arena_hazard_count:
		var p := zone_point(200.0)
		for t in 30:
			if pts.all(func(q): return q.distance_to(p) >= 220.0) and p.distance_to(layout.exit_pos) > 140.0:
				break
			p = zone_point(200.0)
		pts.append(p)
		_spawn_hazard(lord.arena_hazard, p, true)

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
	if color.a > 0.0: ## 透明的障碍体不建 ColorRect（画面由地形贴图负责，省掉上千个空绘制）
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
		var trap := " 陷阱" if c.get("no_recall", false) else ""
		UI.label(chunk_overlay, "#%d %s%s%s" % [c.id, TYPE_NAMES[c.type], mark, trap], rc.position + Vector2(24, 20), 40, Color(1, 1, 0.5))

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
	s["ecology"] = fd.ecology.display_name if fd.ecology else "—"
	s["lord"] = fd.lord().display_name if fd.lord() else "—"
	var hz := {}
	for h in layout.spawn_points.get("hazard", []):
		var n: String = fd.ecology.hazards[h.idx].display_name
		hz[n] = int(hz.get(n, 0)) + 1
	s["hazards"] = hz
	var cnt := {}
	var tot := 0
	for e in get_tree().get_nodes_in_group("enemies"):
		if e != guard and not e.has_meta("summoned"):
			cnt[e.data.id] = int(cnt.get(e.data.id, 0)) + 1
			tot += 1
	s["enemy_ratio"] = cnt.keys().map(func(k): return "%s %.2f" % [Game.enemies[k].display_name, float(cnt[k]) / maxi(1, tot)])
	return s

func map_stats_text() -> String:
	var s := map_stats()
	return "第 %d 层（种子 %d）：区块 %d（普通 %d），最短路 %d 区块\n巡逻组 %d（%d 只），营地 %d（%d 只），场上普通怪 %d\n宝箱 %d，资源点 %d，强化神龛 %d，营地神龛 %d\n生成 %.1f ms，导航烘焙 %.1f ms" % [
		depth, layout.seed, s.chunks, s.normal_chunks, s.path_len, s.patrol_groups, s.patrol_enemies, s.camps, s.camp_enemies, s.enemies_alive,
		s.chests, s.nodes, s.shrines, s.camps, s.gen_ms, s.bake_ms] + "\n生态：%s　层主：%s\n敌种比例：%s\n机关：%s" % [s.ecology, s.lord, " / ".join(s.enemy_ratio), " ".join(s.hazards.keys().map(func(k): return "%s ×%d" % [k, s.hazards[k]]))]

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

## 菌环中心那只史莱姆。T5 把落点交给地标；靠近后精英自己通知教学。
func spawn_elite(pos: Vector2, group := "") -> EnemyBase:
	var e := spawn_enemy("shellbug", pos, group)
	e.make_thickmoss_elite()
	return e

func enemy_data(eid: String) -> EnemyData:
	if Game.enemies.has(eid):
		return Game.enemies[eid]
	return load("res://data/enemies/%s.tres" % eid)

func spawn_enemy(eid: String, pos: Vector2, group := "") -> EnemyBase:
	var data := enemy_data(eid)
	var e := EnemyBase.new()
	e.setup(data, depth, fd)
	e.position = pos
	e.home_pos = pos
	e.use_nav = nav_ready
	e.set_meta("group", group)
	world.add_child(e)
	return e

## 地图怪：挂 EnemyAI。style = walk（巡逻）/ post（射手驻守）/ camp（营地待机）；route = 巡逻路线（含队形偏移）
func _map_enemy(eid: String, pos: Vector2, group: String, style := "", route: Array = [], rid := "") -> EnemyBase:
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
	if rid != "":
		e.set_meta("rid", rid)
		e.died.connect(_on_tracked_died)
	return e

func _on_tracked_died(e: EnemyBase) -> void:
	var id := str(e.get_meta("rid", ""))
	if id != "" and not killed_ids.has(id):
		killed_ids.append(id)

## 地标演员：不进 spawn_points，所以宝箱 / 资源点 / 机关 / 巡逻的数量统计不变。
func _spawn_landmarks() -> void:
	var hd: HazardData = load("res://data/hazards/spore_pod.tres")
	for lm in layout.get("landmarks", []):
		_draw_landmark(lm)
		match str(lm.id):
			"lm_first_fight":
				var posts: Array = lm.get("posts", [lm.pos, lm.pos])
				for p in posts:
					var e := _map_enemy("mushling", p, "lm_first_fight", "post")
					e.set_meta("landmark", true)
			"lm_spring":
				var r := UI.rect(self, lm.pos - Vector2(28, 28), Vector2(56, 56), Color(0.35, 0.9, 0.6))
				r.z_index = -5
				var hold: float = float(lm.get("interact", 2.5))
				_add_interact(lm.pos, "采集萤苔泉", _take_node.bind("lm_spring", r), func(): return not used.has("lm_spring"), "node", "lm_spring", hold)
			"lm_fallen_tree":
				if lm.has("chest"):
					var cpos: Vector2 = lm.chest
					var r := UI.rect(self, cpos - Vector2(36, 26), Vector2(72, 52), Color(0.85, 0.7, 0.25))
					r.z_index = -5
					_add_interact(cpos, "打开宝箱", _open_chest.bind("lm_tree_chest", r), func(): return not used.has("lm_tree_chest"), "chest", "lm_tree_chest", 0.6)
			"lm_fairy_ring":
				for p in lm.get("pods", []):
					var h := _spawn_hazard(hd, p, false)
					if h:
						h.set_meta("landmark", true)
				var elite := _map_enemy("shellbug", lm.pos, "lm_fairy", "post")
				elite.make_thickmoss_elite()
				elite.set_meta("landmark", true)
			"lm_epitaph":
				var hold: float = float(lm.get("interact", 1.0))
				_add_interact(lm.pos, "读墓碑", _read_epitaph, func(): return not _epitaph_reading, "epitaph", "lm_epitaph", hold)

func _draw_landmark(lm: Dictionary) -> void:
	match str(lm.id):
		"lm_crater":
			var s := float(lm.radius) * 2.0
			var r := UI.rect(self, lm.pos - Vector2(s, s) * 0.5, Vector2(s, s), Color(0.22, 0.18, 0.14, 0.45))
			r.z_index = -6
			UI.label(self, lm.name, lm.pos + Vector2(-40, 20), 22, Color(0.75, 0.7, 0.6))
		"lm_first_fight":
			var r := UI.rect(self, lm.pos - Vector2(16, 40), Vector2(32, 48), Color(0.45, 0.32, 0.16))
			r.z_index = -6
			UI.label(self, lm.name, lm.pos + Vector2(-48, -70), 22, Color(0.8, 0.7, 0.5))
		"lm_spring":
			var light := float(lm.get("light", 300.0))
			var glow := UI.rect(self, lm.pos - Vector2(light, light), Vector2(light, light) * 2.0, Color(0.45, 0.95, 0.6, 0.08))
			glow.z_index = -7
			UI.label(self, lm.name, lm.pos + Vector2(-40, -48), 22, Color(0.6, 1.0, 0.75))
		"lm_fallen_tree":
			if lm.has("bar"):
				var bar: Rect2 = lm.bar
				var foot := Node2D.new()
				foot.position = Vector2(bar.position.x + bar.size.x * 0.5, bar.position.y + bar.size.y)
				world.add_child(foot)
				UI.rect(foot, Vector2(-bar.size.x * 0.5, -bar.size.y), bar.size, Color(0.28, 0.16, 0.08))
				var crown_h := maxf(64.0, bar.size.y * 1.6)
				var crown_w := maxf(80.0, bar.size.x * 0.55)
				var crown := CrownOccluder.new()
				world.add_child(crown)
				crown.setup(Rect2(bar.get_center().x - crown_w * 0.5, bar.position.y - crown_h * 0.8, crown_w, crown_h), Color(0.22, 0.48, 0.18, 0.9))
			for b in lm.get("bushes", []):
				var bush := UI.rect(self, b - Vector2(16, 12), Vector2(32, 24), Color(0.18, 0.42, 0.16))
				bush.z_index = -6
			UI.label(self, lm.name, lm.pos + Vector2(-48, -36), 22, Color(0.7, 0.85, 0.55))
		"lm_fairy_ring":
			var s := float(lm.radius) * 2.0
			var r := UI.rect(self, lm.pos - Vector2(s, s) * 0.5, Vector2(s, s), Color(0.45, 0.25, 0.6, 0.18))
			r.z_index = -6
			UI.label(self, lm.name, lm.pos + Vector2(-24, -20), 22, Color(0.8, 0.6, 1.0))
		"lm_epitaph":
			var r := UI.rect(self, lm.pos - Vector2(18, 48), Vector2(36, 72), Color(0.62, 0.62, 0.66))
			r.z_index = -6
			UI.label(self, "#0000", lm.pos + Vector2(-28, -78), 22, Color(0.85, 0.85, 0.9))

func _spawn_patrols() -> void:
	var gi := 0
	for p in layout.spawn_points.patrol:
		var c: Vector2 = p.points[0]
		for i in p.size:
			var off := Vector2(45, 0).rotated(TAU * i / p.size)
			var eid := _pick_enemy() ## 跳过已击杀的也要掷一次，回来时活着的还是原来的种类
			var rid := "p%d:%d" % [gi, i]
			if not killed_ids.has(rid):
				var route: Array = p.points.map(func(q): return q + off)
				_map_enemy(eid, c + off, "p%d" % gi, "", route, rid)
		gi += 1

func _spawn_camps() -> void:
	for cs in layout.spawn_points.camp:
		var st: Dictionary = camps_state[cs.chunk]
		var alive := 0
		for i in cs.size:
			var eid := _pick_enemy()
			var rid := "c%d:%d" % [cs.chunk, i]
			if killed_ids.has(rid):
				continue
			var e := _map_enemy(eid, cs.center + Vector2(150, 0).rotated(TAU * i / cs.size), "c%d" % cs.chunk, "camp", [], rid)
			e.set_meta("camp", cs.chunk)
			e.died.connect(_on_camp_member_died.bind(cs.chunk))
			alive += 1
		st.alive = alive
		st.total = cs.size
		if alive == 0 and cs.size > 0:
			st.cleared = true
			(st.shrine_rect as ColorRect).color = Color(0.55, 0.5, 1)

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
	var _p := Prof.t0()
	_prof_physics_process(delta)
	Prof.add("floor", _p)

func _prof_physics_process(delta: float) -> void:
	if player == null or not is_instance_valid(player) or Game.run == null:
		return
	var fighting := false
	var press := false
	var reach: float = Audio.rules.combat_range
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.state != EnemyBase.S.IDLE and e.state != EnemyBase.S.RETURN and e.state != EnemyBase.S.PATROL and e.state != EnemyBase.S.ALERT:
			fighting = true
		if e.state == EnemyBase.S.CHASE and e.global_position.distance_to(player.global_position) <= reach:
			press = true
		if fighting and press:
			break
	if not Audio.step_manual:
		Audio.set_combat_pressure(press)
		if guard and is_instance_valid(guard) and guard.max_hp > 0 and guard.state != EnemyBase.S.DEAD:
			Audio.notify_boss_hp(float(guard.hp) / float(guard.max_hp))
	if fighting and Game.run.floor_stats.has("combat_sec"):
		Game.run.floor_stats.combat_sec += delta
	# 交战次数（CSV encounters）：脱战超过 encounter_gap_sec 后再进入战斗算新的一次
	if fighting:
		if _calm_t >= aggro.encounter_gap_sec:
			Game.run.floor_stats["encounters"] = int(Game.run.floor_stats.get("encounters", 0)) + 1
		_calm_t = 0.0
	else:
		_calm_t += delta
	if guard_t0 >= 0.0 and not guard_dead and Game.run.floor_stats.has("guard_sec"):
		Game.run.floor_stats.guard_sec += delta
	if guard and is_instance_valid(guard):
		hud.show_boss(guard)
	else:
		hud.show_boss(null)
	_tick_recall(delta)
	var it := nearest_interactable()
	_tick_hold(it, delta)
	if it.is_empty():
		hud.prompt.text = ""
	elif it.hold > 0.0:
		hud.prompt.text = "【长按 %s】%s%s" % [InputGlyph.interact(), it.text, ("（%d%%）" % roundi(hold_t / it.hold * 100)) if hold_key == it.key else ""]
	else:
		hud.prompt.text = "【%s】%s" % [InputGlyph.interact(), it.text]
	if exit_rect:
		exit_rect.color = Color(0.3, 0.95, 0.88, 0.92) if exit_active else Color(0.12, 0.28, 0.32, 0.55)
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

## 物理 R / RB 同时绑了技能 2 和回村符。技能 2 吃掉这次按键；单独的 recall 动作事件仍回村。
func skill2_takes_key(e: InputEvent) -> bool:
	if e is InputEventAction:
		return e.action == "skill2"
	return e.is_action("skill2")

func _unhandled_input(e: InputEvent) -> void:
	if get_tree().paused:
		return
	if e.is_action_pressed("recall") and not skill2_takes_key(e):
		try_recall()
	elif channeling and e.is_action_pressed("ui_cancel"):
		interrupt_recall()
		get_viewport().set_input_as_handled()
	elif e.is_action_pressed("interact"):
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
func _read_epitaph() -> void:
	if _epitaph_reading:
		return
	_epitaph_reading = true
	Audio.sfx("SFX-42")
	var lore: EpitaphLore = load("res://data/lore/epitaph_0000.tres")
	var fresh := not EpitaphLore.was_read()
	if epitaph_line == null:
		epitaph_line = UI.label(hud, "", Vector2(360, 600), 28, Color(0.92, 0.9, 0.84))
		epitaph_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		epitaph_line.custom_minimum_size = Vector2(1200, 140)
		epitaph_line.size = Vector2(1200, 140)
	for i in lore.lines.size():
		var line: String = lore.lines[i]
		epitaph_line.text = line
		epitaph_line.visible = true
		await get_tree().create_timer(lore.line_sec, true, true).timeout
		if not is_inside_tree():
			return
	epitaph_line.text = ""
	epitaph_line.visible = false
	if fresh:
		EpitaphLore.mark_read()
		SysLog.flash(lore.flash_text)
	_epitaph_reading = false

func _use_campfire(key: String) -> void:
	used[key] = true
	Tutorial.notify("fire")
	Audio.loop("SFX-36", "Ambience")
	var n := roundi(player.max_hp * fd.campfire_heal)
	player.heal(n)
	hud.show_toast("篝火回复 %d HP" % n)

func _open_chest(key: String, vis: ColorRect = null) -> void:
	used[key] = true
	Tutorial.notify("loot")
	Audio.sfx("SFX-31")
	NoiseBus.emit_kind(player.global_position, "chest")
	if vis:
		vis.color = Color(0.4, 0.35, 0.2)
	var got := fd.chest_loot.roll(rng, 1.0 + float(player.mods.get("rare_drop_pct", 0)))
	var names: Array = []
	for st in got:
		Game.run.add_item(st)
		names.append("%s ×%d" % [st.item.display_name, st.count])
	if Game.recall.roll_chest(key):
		names.append(Game.recall.dropped_name())
	hud.show_toast("宝箱：" + "，".join(names))

func _take_node(key: String, vis: ColorRect = null) -> void:
	used[key] = true
	Tutorial.notify("loot")
	Audio.loop("SFX-35", "Ambience")
	get_tree().create_timer(2.5, true, true).timeout.connect(func() -> void: Audio.stop_loop("SFX-35"))
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
	Tutorial.notify("loot")
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

# ---------- 层主 ----------
func _on_guard_zone_body(body: Node) -> void:
	if body == player and guard == null and not guard_dead:
		_enter_guard_zone.call_deferred() ## 物理回调里不能直接加物体
		Tutorial.notify("boss_enter")

func _enter_guard_zone() -> void:
	if guard != null or guard_dead or not is_inside_tree():
		return
	_set_fence(true)
	Audio.enter_boss()
	spawn_guard()
	guard_zone_entered.emit()

func spawn_guard() -> Guard:
	guard = Guard.new()
	guard.setup_guard(fd.lord(), depth)
	guard.position = layout.guard_pos
	guard.use_nav = nav_ready
	guard.set_meta("zone", true)
	guard.died.connect(_on_guard_died)
	guard.summon_requested.connect(_on_summon)
	guard.phase2_started.connect(_spawn_arena_hazards.bind(2))
	world.add_child(guard)
	guard_t0 = Time.get_ticks_msec() / 1000.0
	_spawn_arena_hazards(1)
	return guard

## 召唤物刷新点：层主区内的随机空地，离主角 ≥ min_player_dist
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
		var pos := zone_point(160.0)
		if eid == "piglet" and guard != null:
			pos = guard.global_position + Vector2.from_angle(TAU * float(i) / maxf(1.0, float(n))) * 120.0
		if eid == "piglet":
			Audio.sfx("SFX-52")
		var e := spawn_enemy(eid, pos, "summon")
		e.set_meta("summoned", true)
		e.set_meta("lord", guard.get_instance_id() if guard else 0)

## 层主区入口（第一个开口）内侧 / 外侧的点
func guard_entry_pos(inside := true) -> Vector2:
	var e: Dictionary = layout.guard_entrances[0]
	return e.gap.get_center() + Vector2(e.dir) * (-200.0 if inside else 200.0)

## 调试：传送到层主区入口外侧（篝火旁），走进去即开战
func debug_guard() -> void:
	player.global_position = layout.campfire_pos
	cam.snap()

## 调试 / 测试：直接走进层主区（触发栅栏和层主）
func debug_enter_guard_zone() -> void:
	player.global_position = guard_entry_pos(true)
	cam.snap()

func _on_guard_died(_g: EnemyBase) -> void:
	Game.recall.on_lord_killed(depth)
	guard_dead = true
	guard_killed_at = Time.get_ticks_msec() / 1000.0
	_guard_log_flash()
	guard_killed.emit()
	Tutorial.notify("guard_dead")
	for e in guard_zone_enemies():
		e.queue_free()
	for h in arena_hazards:
		if is_instance_valid(h):
			h.queue_free()
	arena_hazards.clear()
	var exit_wait := Time.get_ticks_msec()
	while Time.get_ticks_msec() - exit_wait < 500:
		if not is_inside_tree():
			return
		await get_tree().process_frame
	if not is_inside_tree():
		return
	_set_fence(false)
	exit_active = true
	Audio.sfx("SFX-37")
	exit_activated_at = Time.get_ticks_msec() / 1000.0
	exit_activated.emit()
	hud.show_toast("撤离点已亮起")

## 线索 2：层主第一次被击杀必定闪现，之后按 log_repeat_chance
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

## 方案 A（§9）：撤离点只在层主死后出现；层主战前不能撤离也不能下潜
func choose_exit(descend: bool) -> bool:
	if not guard_dead or not exit_active:
		return false
	Game.run.hp = player.hp
	Tutorial.notify("extract")
	if descend and depth < Game.FINAL_FLOOR:
		Game.log_floor("descend")
		Game.descend()
	else:
		Game.log_floor("extract")
		Audio.sfx("SFX-38")
		Audio.extract_success()
		Game.extract()
	return true

func _on_player_died(cause: String) -> void:
	interrupt_recall()
	Game.run.hp = 0
	Game.log_floor("death")
	Game.on_player_died(cause)

func _on_player_damaged(_amount: int) -> void:
	if channeling:
		interrupt_recall()

# ---------- 回村符 ----------
func recall_blocked() -> bool:
	if player == null:
		return false
	if guard_rect.has_point(player.global_position):
		return true
	var k := MapGen.chunk_at(layout, player.global_position)
	return k >= 0 and bool(layout.chunks[k].get("no_recall", false))

func _show_recall_block() -> void:
	last_recall_hint = Game.recall.blocked_hint
	if hud:
		hud.show_toast(last_recall_hint)

func try_recall() -> bool:
	if _recall_done or channeling or popup_open or player == null or player.state == Player.S.DEAD:
		return false
	if Game.run == null or Game.run.count_of(RecallCharm.ITEM_ID) <= 0:
		if hud:
			hud.show_toast("没有回村符")
		return false
	if recall_blocked():
		_show_recall_block()
		return false
	if not Game.recall.can_use():
		last_recall_hint = Game.recall.sealed_hint if not Game.recall.carrying() else "这一局已经用过回村符"
		if hud:
			hud.show_toast(last_recall_hint)
		return false
	channeling = true
	channel_t = 0.0
	player.input_enabled = false
	player.velocity = Vector2.ZERO
	Audio.sfx("SFX-39")
	return true

func interrupt_recall() -> void:
	if not channeling:
		return
	channeling = false
	channel_t = 0.0
	Audio.sfx("SFX-40")
	if player:
		player.input_enabled = true
	Game.run.floor_stats["charm_interrupted"] = int(Game.run.floor_stats.get("charm_interrupted", 0)) + 1
	if hud:
		hud.show_toast("引导被打断，回村符没有消耗")

func _tick_recall(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	var blocked := recall_blocked()
	if blocked and not _recall_was_blocked:
		_show_recall_block()
	if blocked and channeling:
		interrupt_recall()
	_recall_was_blocked = blocked
	if hud:
		if channeling:
			hud.channel_label.text = "回村引导 %.1f / %.1f 秒" % [channel_t, Game.recall.channel_sec]
		elif blocked and Game.run != null and Game.run.count_of(RecallCharm.ITEM_ID) > 0:
			hud.channel_label.text = Game.recall.blocked_hint
		elif Game.recall.can_use():
			hud.channel_label.text = Game.recall.use_hint
		elif Game.run != null and Game.run.count_of(RecallCharm.ITEM_ID) > 0:
			hud.channel_label.text = Game.recall.sealed_hint
		else:
			hud.channel_label.text = ""
	if not channeling:
		return
	channel_t += delta
	player.velocity = Vector2.ZERO
	if channel_t >= Game.recall.channel_sec:
		_finish_recall()

func _finish_recall() -> void:
	if _recall_done:
		return
	_recall_done = true
	channeling = false
	if player:
		player.input_enabled = true
	if not Game.recall.consume():
		_recall_done = false
		return
	_snapshot_floor()
	Game.run.hp = player.hp
	Game.run.floor_stats["charm_used"] = 1
	Game.run.floor_stats["charm_floor"] = depth
	Game.run.floor_stats["charm_source"] = Game.run.charm_source
	Game.run.charm_recalled = true
	Game.log_floor("recall")
	Game.recall_to_village()

func _snapshot_floor() -> void:
	var picked: Array = []
	for k in used:
		picked.append(k)
	Game.run.floor_memory[depth] = {
		"seed": Game.run.seed,
		"killed": killed_ids.duplicate(),
		"picked": picked,
		"guard_dead": guard_dead,
		"corpse_taken": corpse_taken,
		"first_run": _first_run,
	}

## 首局墓碑必出。回到同一层时沿用当时的首局标记，地图和巡逻点才跟种子一致。
func _floor1_first_run() -> bool:
	_first_run = true
	if depth != 1 or Game.run == null:
		return true
	var mem: Dictionary = Game.run.floor_memory.get(depth, {})
	if mem.has("first_run"):
		_first_run = bool(mem.first_run)
		return _first_run
	_first_run = int(Lineage.flags.get("floor1_visits", 0)) == 0
	Lineage.flags["floor1_visits"] = int(Lineage.flags.get("floor1_visits", 0)) + 1
	Lineage.save()
	return _first_run

func _apply_floor_memory() -> void:
	var mem: Dictionary = Game.run.floor_memory.get(depth, {})
	if mem.is_empty():
		return
	for k in mem.get("picked", []):
		used[str(k)] = true
	killed_ids = []
	for id in mem.get("killed", []):
		killed_ids.append(str(id))
	corpse_taken = bool(mem.get("corpse_taken", false))
	guard_dead = bool(mem.get("guard_dead", false))
	if guard_dead:
		exit_active = true

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

func _attach_look() -> void:
	var layer := preload("res://scenes/floor/atmosphere_layer.gd").new()
	layer.name = "Atmosphere"
	add_child(layer)
	if depth != 1:
		return
	var dress: Node = Floor1DressScript.new()
	dress.name = "Floor1Dress"
	add_child(dress)
	dress.call("build", self, cam, layout)

## 网页性能检查：主角周围刷 n 只地图怪并开打（greybox.perfRing()）
## 性能实验：按名字隐藏一类画面（terrain / obstacles_tex / minimap / hud / world / solids）
var terrain_sprites: Array = []
func debug_set_visible(what: String, on: bool) -> void:
	match what:
		"terrain": terrain_sprites[0].visible = on
		"minimap": minimap.visible = on
		"hud": hud.visible = on
		"world": world.visible = on
		"solids":
			for c in get_children():
				if c is StaticBody2D: c.visible = on

func debug_perf_ring(n: int) -> void:
	var c := player.global_position
	var ring: Array = []
	for i in n:
		ring.append(_map_enemy(["mushling", "rootshot", "shellbug"][i % 3], c + Vector2(260, 0).rotated(TAU * i / n), "perf"))
	await get_tree().physics_frame
	if is_instance_valid(ring[0]):
		ring[0].ai.enter_chase("perf")
