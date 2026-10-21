class_name QualityFrame
extends RefCounted

const TIERS := {"grey": 0.0, "moss": 1.0, "cyan": 2.0, "purple": 3.0, "gold": 4.0}

static func tier_of(item: ItemData) -> String:
	if item == null:
		return "grey"
	if item.quality != "":
		return item.quality
	match item.category:
		"material":
			return "moss"
		"rare_material":
			return "purple"
		"shard", "equipment":
			return "cyan"
		"key_item":
			return "gold"
		_:
			return "grey"

static func apply(rect: ColorRect, tier_name: String) -> ShaderMaterial:
	var mat := rect.material as ShaderMaterial
	if mat == null or mat.shader == null or mat.shader.resource_path != "res://shaders/quality_border.gdshader":
		mat = ShaderMaterial.new()
		mat.shader = load("res://shaders/quality_border.gdshader")
		rect.material = mat
	var tier: float = float(TIERS.get(tier_name, 0.0))
	var pres := Presentation.data()
	mat.set_shader_parameter("tier", tier)
	mat.set_shader_parameter("flow_speed", pres.flow_speed)
	mat.set_shader_parameter("time_sec", Time.get_ticks_msec() / 1000.0)
	return mat
