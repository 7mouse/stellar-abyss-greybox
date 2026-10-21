class_name Presentation
extends Resource
## 顶冠、预警边缘和品质流光。data/presentation.tres。

@export var occluder_alpha := 0.5
@export var occluder_fade_sec := 0.15
@export var rim_ramp_sec := 0.3
@export var flow_speed := 0.25

static func data() -> Presentation:
	return load("res://data/presentation.tres")
