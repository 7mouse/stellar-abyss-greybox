class_name CrownOccluder
extends Node2D
## 顶冠。永远画在角色上面。主角脚底进入矩形（从上边向下收 20%）时渐隐。

var zone := Rect2()
var shown := 1.0
var swatch: ColorRect
var _color := Color(0.35, 0.55, 0.28, 0.85)

func _ready() -> void:
	z_index = 20
	z_as_relative = false
	swatch = ColorRect.new()
	swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(swatch)
	_apply_swatch()

func setup(world_rect: Rect2, color: Color) -> void:
	zone = world_rect
	_color = color
	if is_inside_tree():
		global_position = world_rect.position
	else:
		position = world_rect.position
	_apply_swatch()

func _apply_swatch() -> void:
	if swatch == null:
		return
	swatch.position = Vector2.ZERO
	swatch.size = zone.size
	swatch.color = _color

func _process(delta: float) -> void:
	var pres := Presentation.data()
	var inside := false
	var shrunk := zone
	shrunk.position.y += zone.size.y * 0.2
	shrunk.size.y *= 0.8
	for p in get_tree().get_nodes_in_group("player"):
		if is_instance_valid(p) and shrunk.has_point(p.global_position):
			inside = true
			break
	var goal := pres.occluder_alpha if inside else 1.0
	var step := delta / maxf(0.01, pres.occluder_fade_sec)
	shown = move_toward(shown, goal, step)
	modulate.a = shown
