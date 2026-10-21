class_name TelegraphShape
extends Node2D
## 圆、线、扇预警。线沿本地 +X，调用方把节点转到出手方向。

var kind := "circle"
var length := 120.0
var width := 24.0
var radius := 80.0
var arc_deg := 90.0
var fill := 0.0
var rim_alpha := 0.4
var panel: ColorRect
var mat: ShaderMaterial

func _ready() -> void:
	panel = ColorRect.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mat = ShaderMaterial.new()
	mat.shader = load("res://shaders/telegraph.gdshader")
	panel.material = mat
	add_child(panel)
	refresh()

func refresh() -> void:
	if panel == null or mat == null:
		return
	var shape_i := 0.0
	if kind == "line":
		shape_i = 1.0
		panel.position = Vector2(0, -width * 0.5)
		panel.size = Vector2(maxf(length, 1.0), maxf(width, 1.0))
	elif kind == "wedge":
		shape_i = 2.0
		var side := radius * 2.0
		panel.position = Vector2(-radius, -radius)
		panel.size = Vector2(side, side)
	else:
		var side2 := radius * 2.0
		panel.position = Vector2(-radius, -radius)
		panel.size = Vector2(side2, side2)
	var base_a := lerpf(0.18, 0.35, clampf(fill, 0.0, 1.0))
	mat.set_shader_parameter("shape_id", shape_i)
	mat.set_shader_parameter("fill", clampf(fill, 0.0, 1.0))
	mat.set_shader_parameter("base_color", Color(0.478431, 0.164706, 0.164706, base_a))
	mat.set_shader_parameter("rim_color", Color(0.784314, 0.345098, 0.290196, rim_alpha))
	mat.set_shader_parameter("arc_deg", arc_deg)
	mat.set_shader_parameter("use_stroke", 0.0)

static func rim_from_fill(p_fill: float, windup: float, ramp: float, strike: bool) -> float:
	if strike:
		return 1.0
	if windup <= 0.001:
		return 0.85
	var start := 1.0 - clampf(ramp / windup, 0.0, 1.0)
	if p_fill <= start:
		return 0.4
	return lerpf(0.4, 0.85, clampf((p_fill - start) / maxf(0.001, 1.0 - start), 0.0, 1.0))
