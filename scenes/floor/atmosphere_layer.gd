extends Node2D
## 全屏调色。画在世界上面、HUD 下面。grade_screen 时采样屏幕做对比；关掉则只叠暗角和雾。

var _rect: ColorRect
var _mat: ShaderMaterial
var _mod: CanvasModulate
var _rules: Atmosphere
var _key := ""

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rules = Atmosphere.data()
	_mod = CanvasModulate.new()
	_mod.name = "grade_modulate"
	_mod.color = Color.WHITE
	add_child(_mod)
	var layer := CanvasLayer.new()
	layer.layer = 8
	add_child(layer)
	_rect = ColorRect.new()
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.color = Color.WHITE
	_mat = ShaderMaterial.new()
	_rect.material = _mat
	layer.add_child(_rect)
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.offset_left = 0
	_rect.offset_top = 0
	_rect.offset_right = 0
	_rect.offset_bottom = 0
	if not _rules.changed.is_connected(_apply):
		_rules.changed.connect(_apply)
	_apply()

func _process(_delta: float) -> void:
	var live := Atmosphere.data()
	if live != _rules:
		if _rules != null and _rules.changed.is_connected(_apply):
			_rules.changed.disconnect(_apply)
		_rules = live
		if not _rules.changed.is_connected(_apply):
			_rules.changed.connect(_apply)
	var key := _snapshot()
	if key != _key:
		_apply()

func param(prop: String) -> Variant:
	return _mat.get_shader_parameter(prop)

func shader_path() -> String:
	if _mat.shader == null:
		return ""
	return _mat.shader.resource_path

func _snapshot() -> String:
	var r := _rules
	return "%s|%s|%.4f|%.4f|%.4f|%.4f|%.4f|%.4f|%.4f|%s|%s" % [r.enabled, r.grade_screen, r.brightness, r.contrast, r.vignette, r.vignette_radius, r.vignette_soft, r.fog, r.fog_start, r.fog_color, r.vignette_color]

func _apply() -> void:
	var r := _rules
	var screen := r.enabled and r.grade_screen
	_mat.shader = load("res://shaders/atmosphere.gdshader" if screen else "res://shaders/atmosphere_overlay.gdshader")
	_mat.set_shader_parameter("brightness", r.brightness)
	_mat.set_shader_parameter("contrast", r.contrast)
	_mat.set_shader_parameter("vignette", r.vignette)
	_mat.set_shader_parameter("vignette_radius", r.vignette_radius)
	_mat.set_shader_parameter("vignette_soft", r.vignette_soft)
	_mat.set_shader_parameter("fog", r.fog)
	_mat.set_shader_parameter("fog_start", r.fog_start)
	_mat.set_shader_parameter("fog_color", r.fog_color)
	_mat.set_shader_parameter("vignette_color", r.vignette_color)
	_rect.visible = r.enabled
	if screen:
		_mod.color = Color.WHITE
	else:
		var m := clampf(1.0 + r.brightness, 0.35, 1.25)
		_mod.color = Color(m, m, m, 1.0)
	_key = _snapshot()
