class_name Hurtbox
extends Node2D
## 受击框：脚底椭圆（rx × ry）。几何判定，不依赖物理引擎；owner_actor 实现 take_hit()

signal hurt(hitbox)

var team := "enemy"
var rx := 20.0
var ry := 12.0
var owner_actor: Node
var invulnerable := false ## 只用于显示（灰色）

func _ready() -> void:
	add_to_group("hurtbox_" + team)

## 以 rx 为基准把椭圆拉成圆后的偏移
func _norm(p: Vector2) -> Vector2:
	var d := p - global_position
	d.y *= rx / ry
	return d

func overlaps_circle(c: Vector2, r: float) -> bool:
	return _norm(c).length() <= r + rx

func overlaps_sector(origin: Vector2, dir: Vector2, r: float, arc_deg: float) -> bool:
	var d := global_position - origin
	if d.length() > r + rx:
		return false
	if arc_deg >= 360.0 or d.length() <= rx:
		return true
	return absf(rad_to_deg(dir.angle_to(d))) <= arc_deg / 2.0 + rad_to_deg(atan2(rx, d.length()))

func _draw() -> void:
	if Game.show_boxes:
		var pts := PackedVector2Array()
		for i in 24:
			var a := TAU * i / 24
			pts.append(Vector2(cos(a) * rx, sin(a) * ry))
		pts.append(pts[0])
		draw_polyline(pts, Color(0.6, 0.6, 0.6) if invulnerable else Color(0.2, 1, 0.3), 2.0)

func _process(_d: float) -> void:
	queue_redraw()
