extends Node
## 第一关地表：石板三变体烤进一张地面图，弯边贴花盖住格子交界，崖壁和前后景树林分开画。
## 只服务第 1 层。不改碰撞。

const WORLD_PER_TEX := 2.0
const TILE_WORLD := 512.0
const BOUND_TEX := 44 ## 苔侧 88px，按 2 世界像素 1 纹素
const LIP_TEX := 20
const CELL_TEX := 32 ## 64 / WORLD_PER_TEX
const STONE := [
	"res://art_src/terrain/floor1_v2/tiles/s01_ground_stone.png",
	"res://art_src/terrain/floor1_v2/tiles/s01_ground_stone_v2.png",
	"res://art_src/terrain/floor1_v2/tiles/s01_ground_stone_v3.png",
]
const EDGE := "res://art_src/terrain/floor1_v2/edges/s02_edge_moss_stone.png"
const CORNER_IN := "res://art_src/terrain/floor1_v2/edges/s02_edge_moss_stone_corner_inner.png"
const CORNER_OUT := "res://art_src/terrain/floor1_v2/edges/s02_edge_moss_stone_corner_outer.png"
const CLIFF_A := "res://art_src/terrain/floor1_v2/cliffs/cliff_straight_a.png"
const CLIFF_B := "res://art_src/terrain/floor1_v2/cliffs/cliff_straight_b.png"
const CLIFF_C := "res://art_src/terrain/floor1_v2/cliffs/cliff_straight_c.png"
const CLIFF_OUT := "res://art_src/terrain/floor1_v2/cliffs/cliff_corner_outer.png"
const CLIFF_IN := "res://art_src/terrain/floor1_v2/cliffs/cliff_corner_inner.png"
const CLIFF_END := "res://art_src/terrain/floor1_v2/cliffs/cliff_end_rubble.png"
const STRAIGHTS := [CLIFF_A, CLIFF_B, CLIFF_C]
const BACK_GREEN := "res://art_src/terrain/floor1_v2/forest/forest_back_green.png"
const BACK_AUTUMN := "res://art_src/terrain/floor1_v2/forest/forest_back_autumn.png"
const FRONT_GREEN := "res://art_src/terrain/floor1_v2/forest/canopy_front_green.png"
const FRONT_AUTUMN := "res://art_src/terrain/floor1_v2/forest/canopy_front_autumn.png"

var cliff_sprites: Array[Sprite2D] = []
var back_sprites: Array[Sprite2D] = []
var front_sprites: Array[Sprite2D] = []
var _anchor: Dictionary = {}
var _used: Dictionary = {}
var _floor: Node2D
var _cam: FollowCam
var last_center := Vector2.ZERO
var last_back := 0.0

static func variant_of(tx: int, ty: int, seed: int) -> int:
	var n: int = tx * 374761393 + ty * 668265263 + seed * 1442695041
	n = (n ^ (n >> 13)) * 1274126177
	n = n ^ (n >> 16)
	return posmod(n, 3)

static func bake(layout: Dictionary, ground: Image, seed: int) -> Image:
	var t0 := Time.get_ticks_usec()
	var tw := int(round(ground.get_width() * MapGen.TCELL / WORLD_PER_TEX))
	var th := int(round(ground.get_height() * MapGen.TCELL / WORLD_PER_TEX))
	var base := ground.duplicate()
	base.resize(tw, th, Image.INTERPOLATE_BILINEAR)
	var img := base.duplicate()
	var tile := int(TILE_WORLD / WORLD_PER_TEX)
	var stones: Array[Image] = []
	for p in STONE:
		stones.append(_texel(p, tile, tile))
	var tiles_x := int(ceil(float(tw) / float(tile)))
	var tiles_y := int(ceil(float(th) / float(tile)))
	for ty in tiles_y:
		for tx in tiles_x:
			_blit(img, stones[variant_of(tx, ty, seed)], 0, 0, tile, tile, tx * tile, ty * tile)
	for ch in layout.chunks:
		for r in ch.obstacles:
			var rr: Rect2 = r
			var dx := int(rr.position.x / WORLD_PER_TEX)
			var dy := int(rr.position.y / WORLD_PER_TEX)
			var dw := int(rr.size.x / WORLD_PER_TEX)
			var dh := int(rr.size.y / WORLD_PER_TEX)
			_blit(img, base, dx, dy, dw, dh, dx, dy)
	var T: Dictionary = layout.terrain
	var g: PackedByteArray = T.cells
	var nx: int = T.nx
	var ny: int = T.ny
	var strip := _texel(EDGE, tile, int(128.0 / WORLD_PER_TEX))
	var strip_flip := strip.duplicate()
	strip_flip.flip_y()
	var vstrip := strip.duplicate()
	vstrip.rotate_90(1) ## 左转 90 度，苔边到左侧
	var vflip := vstrip.duplicate()
	vflip.flip_x()
	_paint_edges(img, g, nx, ny, strip, strip_flip, vstrip, vflip)
	var out_base := _texel(CORNER_OUT, int(128.0 / WORLD_PER_TEX), int(128.0 / WORLD_PER_TEX))
	var in_base := _texel(CORNER_IN, int(128.0 / WORLD_PER_TEX), int(128.0 / WORLD_PER_TEX))
	var out_r: Array[Image] = []
	var in_r: Array[Image] = []
	for i in 4:
		out_r.append(_rotated(out_base, i))
		in_r.append(_rotated(in_base, i))
	_paint_corners(img, g, nx, ny, out_r, in_r)
	print("[map] 第一关地表烘焙 %.1f ms（%d×%d）" % [(Time.get_ticks_usec() - t0) / 1000.0, tw, th])
	return img

func build(floor: Node2D, cam: FollowCam, layout: Dictionary) -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_floor = floor
	_cam = cam
	var rules := Atmosphere.data()
	var b: Rect2 = layout.bounds
	var inset := b.grow(-80.0)
	_run(inset.position, Vector2(inset.end.x, inset.position.y), 0.0, false, rules.cliff_scale)
	_run(Vector2(inset.position.x, inset.end.y), inset.end, 0.0, true, rules.cliff_scale)
	_run(inset.position, Vector2(inset.position.x, inset.end.y), PI * 0.5, false, rules.cliff_scale)
	_run(Vector2(inset.end.x, inset.position.y), inset.end, -PI * 0.5, false, rules.cliff_scale)
	_add_cliff(CLIFF_OUT, inset.position, 0.0, false, false, rules.cliff_scale)
	_add_cliff(CLIFF_OUT, Vector2(inset.end.x, inset.position.y), PI * 0.5, false, false, rules.cliff_scale)
	_add_cliff(CLIFF_OUT, inset.end, PI, false, false, rules.cliff_scale)
	_add_cliff(CLIFF_OUT, Vector2(inset.position.x, inset.end.y), -PI * 0.5, false, false, rules.cliff_scale)
	var start: Vector2 = layout.start_pos
	var y := start.y - 300.0
	var gap0 := start.x - 140.0
	var gap1 := start.x + 140.0
	_run(Vector2(start.x - 980.0, y), Vector2(gap0, y), 0.0, false, rules.cliff_scale)
	_run(Vector2(gap1, y), Vector2(start.x + 980.0, y), 0.0, false, rules.cliff_scale)
	_add_cliff(CLIFF_END, Vector2(gap0, y + 10.0), 0.0, false, false, rules.cliff_scale)
	_add_cliff(CLIFF_END, Vector2(gap1, y + 10.0), 0.0, true, false, rules.cliff_scale)
	_add_cliff(CLIFF_IN, Vector2(gap0 - 30.0, y + 90.0), 0.0, false, false, rules.cliff_scale)
	_add_cliff(CLIFF_IN, Vector2(gap1 + 30.0, y + 90.0), 0.0, true, false, rules.cliff_scale)
	var back_g := load(BACK_GREEN) as Texture2D
	var back_a := load(BACK_AUTUMN) as Texture2D
	var front_g := load(FRONT_GREEN) as Texture2D
	var front_a := load(FRONT_AUTUMN) as Texture2D
	var bf := rules.back_parallax
	var ff := rules.front_parallax
	var backs: Array[Vector2] = [Vector2(-460, -260), Vector2(-120, -300), Vector2(240, -250), Vector2(620, -290)]
	for i in backs.size():
		var anchor: Vector2 = start + backs[i] / bf
		_add_tree(back_g if i % 2 == 0 else back_a, anchor, false, i == 3, false, -8)
	var fronts: Array[Vector2] = [Vector2(-620, -320), Vector2(640, -300), Vector2(-160, 320), Vector2(520, 300)]
	for i in fronts.size():
		var anchor2: Vector2 = start + fronts[i] / ff
		var tex: Texture2D = front_g if i % 2 == 0 else front_a
		_add_tree(tex, anchor2, true, false, i >= 2, 24)
	var step := 0
	var x := b.position.x
	while x < b.end.x:
		var yy := b.position.y
		while yy < b.end.y:
			var anchor3 := Vector2(x, yy)
			if anchor3.distance_to(start) > 900.0:
				var far := step % 2 == 0
				_add_tree(back_g if far else back_a, anchor3, false, step % 3 == 0, false, -8)
				if step % 4 == 0:
					_add_tree(front_g if far else front_a, anchor3 + Vector2(180, 80), true, false, step % 8 == 0, 24)
			step += 1
			yy += 1500.0
		x += 1600.0

func piece_count() -> int:
	return _used.size()

func _process(_delta: float) -> void:
	var rules := Atmosphere.data()
	var sc := rules.cliff_scale
	for spr in cliff_sprites:
		spr.scale = Vector2(sc, sc)
	if _cam == null or not is_instance_valid(_cam):
		return
	var center := _cam.get_screen_center_position()
	last_center = center
	last_back = rules.back_parallax
	for spr2 in back_sprites:
		var anchor: Vector2 = _anchor[spr2]
		var f := rules.back_parallax
		spr2.global_position = anchor + (center - anchor) * (1.0 - f)
		var m := rules.back_modulate
		spr2.modulate = Color(m, m, m, 1.0)
	for spr3 in front_sprites:
		var anchor4: Vector2 = _anchor[spr3]
		var f2 := rules.front_parallax
		spr3.global_position = anchor4 + (center - anchor4) * (1.0 - f2)
		var m2 := rules.front_modulate
		spr3.modulate = Color(m2, m2, m2, 1.0)

func anchor_of(spr: Sprite2D) -> Vector2:
	return _anchor[spr]

static func _texel(path: String, w: int, h: int) -> Image:
	var tex := load(path) as Texture2D
	var im := tex.get_image()
	if im.is_compressed():
		im.decompress()
	im.convert(Image.FORMAT_RGBA8)
	if im.get_width() != w or im.get_height() != h:
		im.resize(w, h, Image.INTERPOLATE_LANCZOS)
	return im

static func _rotated(src: Image, times: int) -> Image:
	var im := src.duplicate()
	for _i in times:
		im.rotate_90(0)
	return im

static func _open(g: PackedByteArray, nx: int, ny: int, x: int, y: int) -> bool:
	if x < 0 or y < 0 or x >= nx or y >= ny:
		return false
	return g[y * nx + x] == 0

static func _paint_edges(img: Image, g: PackedByteArray, nx: int, ny: int, strip: Image, strip_flip: Image, vstrip: Image, vflip: Image) -> void:
	for y in ny + 1:
		var x := 0
		while x < nx:
			var above := _open(g, nx, ny, x, y - 1)
			var below := _open(g, nx, ny, x, y)
			if above == below:
				x += 1
				continue
			var x0 := x
			x += 1
			while x < nx and _open(g, nx, ny, x, y - 1) == above and _open(g, nx, ny, x, y) == below:
				x += 1
			var moss_above := below and not above
			var src: Image = strip if moss_above else strip_flip
			var dest_y := y * CELL_TEX - (BOUND_TEX if moss_above else LIP_TEX)
			var dest_x := x0 * CELL_TEX
			_span_x(img, src, dest_x, dest_y, (x - x0) * CELL_TEX, dest_x)
	for x2 in nx + 1:
		var y2 := 0
		while y2 < ny:
			var left := _open(g, nx, ny, x2 - 1, y2)
			var right := _open(g, nx, ny, x2, y2)
			if left == right:
				y2 += 1
				continue
			var y0 := y2
			y2 += 1
			while y2 < ny and _open(g, nx, ny, x2 - 1, y2) == left and _open(g, nx, ny, x2, y2) == right:
				y2 += 1
			var moss_left := right and not left
			var src_v: Image = vstrip if moss_left else vflip
			var dest_x2 := x2 * CELL_TEX - (BOUND_TEX if moss_left else LIP_TEX)
			var dest_y2 := y0 * CELL_TEX
			_span_y(img, src_v, dest_x2, dest_y2, (y2 - y0) * CELL_TEX, dest_y2)

static func _paint_corners(img: Image, g: PackedByteArray, nx: int, ny: int, out_r: Array[Image], in_r: Array[Image]) -> void:
	var side := int(128.0 / WORLD_PER_TEX)
	for y in ny + 1:
		for x in nx + 1:
			var nw := _open(g, nx, ny, x - 1, y - 1)
			var ne := _open(g, nx, ny, x, y - 1)
			var sw := _open(g, nx, ny, x - 1, y)
			var se := _open(g, nx, ny, x, y)
			var cnt := int(nw) + int(ne) + int(sw) + int(se)
			var piece: Image = null
			if cnt == 1:
				piece = out_r[_quad(nw, ne, sw, se, true)]
			elif cnt == 3:
				piece = in_r[_quad(nw, ne, sw, se, false)]
			else:
				continue
			_blend(img, piece, 0, 0, side, side, x * CELL_TEX - side / 2, y * CELL_TEX - side / 2)

static func _quad(nw: bool, ne: bool, sw: bool, se: bool, want: bool) -> int:
	if se == want:
		return 0
	if sw == want:
		return 1
	if nw == want:
		return 2
	return 3

static func _span_x(dst: Image, src: Image, dest_x: int, dest_y: int, width: int, src_x0: int) -> void:
	var left := width
	var sx := posmod(src_x0, src.get_width())
	var dx := dest_x
	var sh := src.get_height()
	while left > 0:
		var take := mini(left, src.get_width() - sx)
		_blend(dst, src, sx, 0, take, sh, dx, dest_y)
		left -= take
		dx += take
		sx = 0

static func _span_y(dst: Image, src: Image, dest_x: int, dest_y: int, height: int, src_y0: int) -> void:
	var left := height
	var sy := posmod(src_y0, src.get_height())
	var dy := dest_y
	var sw := src.get_width()
	while left > 0:
		var take := mini(left, src.get_height() - sy)
		_blend(dst, src, 0, sy, sw, take, dest_x, dy)
		left -= take
		dy += take
		sy = 0

static func _blit(dst: Image, src: Image, sx: int, sy: int, sw: int, sh: int, dx: int, dy: int) -> void:
	var r := _clip(src, dst, sx, sy, sw, sh, dx, dy)
	if r.x < 0:
		return
	dst.blit_rect(src, Rect2i(int(r.x), int(r.y), int(r.z), int(r.w)), Vector2i(dx if dx >= 0 else 0, dy if dy >= 0 else 0))

static func _blend(dst: Image, src: Image, sx: int, sy: int, sw: int, sh: int, dx: int, dy: int) -> void:
	var r := _clip(src, dst, sx, sy, sw, sh, dx, dy)
	if r.x < 0:
		return
	var odx := dx
	var ody := dy
	if odx < 0:
		odx = 0
	if ody < 0:
		ody = 0
	dst.blend_rect(src, Rect2i(int(r.x), int(r.y), int(r.z), int(r.w)), Vector2i(odx, ody))

## 返回源矩形 (sx, sy, sw, sh)；裁掉则 x 为 -1。
static func _clip(src: Image, dst: Image, sx: int, sy: int, sw: int, sh: int, dx: int, dy: int) -> Vector4i:
	if sw <= 0 or sh <= 0:
		return Vector4i(-1, 0, 0, 0)
	if dx < 0:
		sx -= dx
		sw += dx
		dx = 0
	if dy < 0:
		sy -= dy
		sh += dy
		dy = 0
	if sx < 0:
		dx -= sx
		sw += sx
		sx = 0
	if sy < 0:
		dy -= sy
		sh += sy
		sy = 0
	sw = mini(sw, src.get_width() - sx)
	sh = mini(sh, src.get_height() - sy)
	sw = mini(sw, dst.get_width() - dx)
	sh = mini(sh, dst.get_height() - dy)
	if sw <= 0 or sh <= 0:
		return Vector4i(-1, 0, 0, 0)
	return Vector4i(sx, sy, sw, sh)

func _run(a: Vector2, b: Vector2, rot: float, flip_v: bool, scale: float) -> void:
	var dir := b - a
	var length := dir.length()
	if length < 8.0:
		return
	var n := dir / length
	var cursor := 0.0
	var i := 0
	while cursor < length - 30.0:
		var path: String = STRAIGHTS[i % STRAIGHTS.size()]
		var tex := load(path) as Texture2D
		var w := tex.get_width() * scale
		if cursor + w * 0.45 > length:
			break
		_add_cliff(path, a + n * (cursor + w * 0.5), rot, false, flip_v, scale)
		cursor += w - 18.0
		i += 1

func _add_cliff(path: String, pos: Vector2, rot: float, flip_h: bool, flip_v: bool, scale: float) -> void:
	var spr := Sprite2D.new()
	spr.texture = load(path)
	spr.centered = true
	spr.position = pos
	spr.rotation = rot
	spr.flip_h = flip_h
	spr.flip_v = flip_v
	spr.scale = Vector2(scale, scale)
	spr.z_index = -6
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_floor.add_child(spr)
	cliff_sprites.append(spr)
	_used[path] = true

func _add_tree(tex: Texture2D, anchor: Vector2, front: bool, flip_h: bool, flip_v: bool, z: int) -> void:
	var spr := Sprite2D.new()
	spr.texture = tex
	spr.centered = true
	spr.flip_h = flip_h
	spr.flip_v = flip_v
	spr.z_index = z
	spr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_floor.add_child(spr)
	_anchor[spr] = anchor
	if front:
		front_sprites.append(spr)
	else:
		back_sprites.append(spr)
	spr.global_position = anchor
