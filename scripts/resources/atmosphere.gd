class_name Atmosphere
extends Resource
## 第一关之后的画面：压暗、对比、暗角、远景雾，以及视差和崖壁缩放。
## data/atmosphere.tres。F1「画面」分组里改，当前这一层马上跟着变。

@export var enabled := true
@export var grade_screen := true ## 屏幕采样调色。关掉则只叠暗角和雾，并压暗画布
@export var brightness := -0.14
@export var contrast := 1.28
@export var vignette := 0.62
@export var vignette_radius := 0.48
@export var vignette_soft := 0.70
@export var fog := 0.40
@export var fog_start := 0.28
@export var fog_color := Color(0.08, 0.10, 0.09, 1)
@export var vignette_color := Color(0.01, 0.012, 0.01, 1)
@export var back_parallax := 0.40 ## 后景树林：越小越贴在画面上
@export var front_parallax := 1.20 ## 前景树冠：大于 1 比地面走得快
@export var back_modulate := 0.86
@export var front_modulate := 0.78
@export var cliff_scale := 0.92

static func data() -> Atmosphere:
	return load("res://data/atmosphere.tres")
