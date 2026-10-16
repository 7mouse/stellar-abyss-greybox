class_name Minimap
extends Control
## 圆形小地图（右上角）。地形仍按 4×4 格合成一块来画，不画区块网格。
## 没去过的地方盖暗色，箭头指向撤离点。层主区用一个小点标出。

var floor_node: Node
var tex: ImageTexture
var fog_img: Image
var fog_tex: ImageTexture
var scale_f := 1.0
var block_px := 256.0
var revealed := 0
var _t := 0.0
const SIDE := 248.0
const REVEAL_PX := 640.0
var _disc: Control

func setup(f: Node) -> void:
	floor_node = f
	var L: Dictionary = f.layout
	var b: Rect2 = L.bounds
	scale_f = SIDE / b.size.x
	size = Vector2(SIDE, SIDE)
	position = Vector2(1920 - SIDE - 28, 108)
	var T: Dictionary = L.terrain
	block_px = T.cell * 4.0
	var imgs := MapGen.terrain_images(L)
	var g: Image = imgs[0]
	g.blend_rect(imgs[1], Rect2i(Vector2i.ZERO, g.get_size()), Vector2i.ZERO)
	var bw := int(ceil(T.nx / 4.0))
	var bh := int(ceil(T.ny / 4.0))
	g.resize(bw, bh, Image.INTERPOLATE_BILINEAR)
	tex = ImageTexture.create_from_image(g)
	fog_img = Image.create(bw, bh, false, Image.FORMAT_RGBA8)
	fog_img.fill(Color(0, 0, 0, 0.5))
	fog_tex = ImageTexture.create_from_image(fog_img)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_disc = _MapDisc.new()
	_disc.size = size
	_disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_disc.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_disc.set("map_tex", tex)
	_disc.set("fog", fog_tex)
	_disc.z_index = -1
	add_child(_disc)

func reveal(pos: Vector2) -> void:
	var changed := false
	var r := int(ceil(REVEAL_PX / block_px))
	var c := Vector2i((pos / block_px).floor())
	for y in range(c.y - r, c.y + r + 1):
		for x in range(c.x - r, c.x + r + 1):
			if x < 0 or y < 0 or x >= fog_img.get_width() or y >= fog_img.get_height():
				continue
			if (Vector2(x + 0.5, y + 0.5) * block_px).distance_to(pos) > REVEAL_PX:
				continue
			if fog_img.get_pixel(x, y).a > 0.0:
				fog_img.set_pixel(x, y, Color(0, 0, 0, 0))
				revealed += 1
				changed = true
	if changed:
		fog_tex.update(fog_img)

func is_revealed(pos: Vector2) -> bool:
	var c := Vector2i((pos / block_px).floor())
	return fog_img.get_pixel(clampi(c.x, 0, fog_img.get_width() - 1), clampi(c.y, 0, fog_img.get_height() - 1)).a == 0.0

var _dirty := true
var _last_pp := Vector2.INF

func is_visited(id: int) -> bool:
	return floor_node.visited.has(id)

func _process(d: float) -> void:
	var _p := Prof.t0()
	_prof_process(d)
	Prof.add("minimap_proc", _p)

func _prof_process(d: float) -> void:
	_t -= d
	if _t <= 0.0 and floor_node and floor_node.player and is_instance_valid(floor_node.player):
		_t = 0.25
		reveal(floor_node.player.global_position)
		_dirty = true
	if floor_node and floor_node.player and is_instance_valid(floor_node.player):
		var pp := to_map(floor_node.player.global_position)
		if pp.distance_squared_to(_last_pp) >= 0.25:
			_last_pp = pp
			_dirty = true
	if _dirty:
		_dirty = false
		if _disc:
			_disc.queue_redraw()
		queue_redraw()

func to_map(p: Vector2) -> Vector2:
	if floor_node == null:
		return p * scale_f
	var b: Rect2 = floor_node.layout.bounds
	return Vector2(p.x * size.x / b.size.x, p.y * size.y / b.size.y)

func _draw() -> void:
	var _p := Prof.t0()
	_prof_draw()
	Prof.add("minimap_draw", _p)

func _prof_draw() -> void:
	if floor_node == null:
		return
	var c := size * 0.5
	var rad := size.x * 0.5 - 2.0
	draw_arc(c, rad, 0, TAU, 48, Color(0.9, 0.86, 0.76, 0.95), 3.0, true)
	var gr: Rect2 = floor_node.guard_rect
	var gc := _clamp_ring(to_map(gr.get_center()), c, rad - 10.0)
	draw_circle(gc, 5, Color(0.9, 0.35, 0.4, 0.95))
	if floor_node.player and is_instance_valid(floor_node.player):
		var pp := _clamp_ring(to_map(floor_node.player.global_position), c, rad - 16.0)
		draw_circle(pp, 5, Color(1, 0.95, 0.85))
		var ep := to_map(floor_node.exit_pos)
		if Tutorial.wants_exit_marker():
			var mp := _clamp_ring(ep, c, rad - 12.0)
			draw_circle(mp, 8, Color(0.95, 0.85, 0.2, 0.95))
			draw_arc(mp, 12, 0, TAU, 16, Color(1, 0.95, 0.5), 2.0, true)
		var d := ep - pp
		if d.length() > 12.0:
			var u := d.normalized()
			var tip := _clamp_ring(pp + u * 20.0, c, rad - 8.0)
			draw_colored_polygon(PackedVector2Array([tip, tip - u * 12.0 + u.orthogonal() * 6.0, tip - u * 12.0 - u.orthogonal() * 6.0]), Color(0.25, 0.95, 0.92))

func _clamp_ring(p: Vector2, c: Vector2, rad: float) -> Vector2:
	var d := p - c
	if d.length() > rad:
		return c + d.normalized() * rad
	return p

class _MapDisc extends Control:
	var map_tex: Texture2D
	var fog: Texture2D

	func _draw() -> void:
		var pts := PackedVector2Array()
		var uvs := PackedVector2Array()
		var cols := PackedColorArray()
		var n := 36
		var c := size * 0.5
		var rad := size.x * 0.5 - 1.0
		for i in n:
			var a := TAU * float(i) / float(n)
			var o := Vector2(cos(a), sin(a))
			pts.append(c + o * rad)
			uvs.append(Vector2(0.5, 0.5) + o * 0.5)
			cols.append(Color.WHITE)
		if map_tex:
			draw_polygon(pts, cols, uvs, map_tex)
		if fog:
			draw_polygon(pts, cols, uvs, fog)
