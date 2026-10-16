class_name Minimap
extends Control
## 小地图（右上角，规格 3.3）：地形格每 4×4 合成 1 个像素块来画，不画区块网格。
## 没去过的地方盖暗色，主角周围 reveal_px 内的像素块点亮；主角白点；层主区从开局就标出，主角旁边画指向层主区的箭头。

var floor_node: Node
var tex: ImageTexture
var fog_img: Image
var fog_tex: ImageTexture
var scale_f := 1.0
var block_px := 256.0 ## 1 个像素块 = 4 个地形格
var revealed := 0
var _t := 0.0
const W := 260.0
const REVEAL_PX := 640.0

func setup(f: Node) -> void:
	floor_node = f
	var L: Dictionary = f.layout
	var b: Rect2 = L.bounds
	scale_f = W / b.size.x
	size = Vector2(W, b.size.y * scale_f)
	position = Vector2(1920 - W - 30, 40)
	var T: Dictionary = L.terrain
	block_px = T.cell * 4.0
	var imgs := MapGen.terrain_images(L)
	var g: Image = imgs[0]
	g.blend_rect(imgs[1], Rect2i(Vector2i.ZERO, g.get_size()), Vector2i.ZERO)
	var bw := int(ceil(T.nx / 4.0))
	var bh := int(ceil(T.ny / 4.0))
	g.resize(bw, bh, Image.INTERPOLATE_BILINEAR) ## 4×4 格合成 1 块
	tex = ImageTexture.create_from_image(g)
	fog_img = Image.create(bw, bh, false, Image.FORMAT_RGBA8)
	fog_img.fill(Color(0, 0, 0, 0.65))
	fog_tex = ImageTexture.create_from_image(fog_img)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

## 点亮 pos 周围 REVEAL_PX 内的像素块
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
	queue_redraw()

func to_map(p: Vector2) -> Vector2:
	return p * scale_f

func _draw() -> void:
	var _p := Prof.t0()
	_prof_draw()
	Prof.add("minimap_draw", _p)

func _prof_draw() -> void:
	if floor_node == null:
		return
	draw_rect(Rect2(Vector2(-4, -4), size + Vector2(8, 8)), Color(0, 0, 0, 0.6))
	draw_texture_rect(tex, Rect2(Vector2.ZERO, size), false)
	draw_texture_rect(fog_tex, Rect2(Vector2.ZERO, size), false)
	var gr: Rect2 = floor_node.guard_rect
	draw_rect(Rect2(to_map(gr.position), gr.size * scale_f), Color(0.95, 0.3, 0.9, 0.9), false, 3)
	var gc := to_map(gr.get_center())
	draw_circle(gc, 6, Color(0.95, 0.3, 0.9))
	if floor_node.player and is_instance_valid(floor_node.player):
		var pp := to_map(floor_node.player.global_position)
		draw_circle(pp, 5, Color(1, 1, 1))
		var d := gc - pp
		if d.length() > 14:
			var u := d.normalized()
			var tip := pp + u * 22
			draw_colored_polygon(PackedVector2Array([tip, pp + u * 10 + u.orthogonal() * 7, pp + u * 10 - u.orthogonal() * 7]), Color(0.95, 0.3, 0.9))
