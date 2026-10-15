class_name MinigameConfig
extends Resource
## 单个小游戏的配置

@export var id: String = ""
@export var display_name: String = ""
@export_enum("attack", "defense") var kind: String = "attack"
@export var group: int = 0 ## 对应概念文档里的技能组编号（1/2/5/6...）
@export_file("*.tscn") var scene_path: String = ""
@export var telegraph_sec: float = 0.7 ## 预兆时长，限制在 0.5~1.0
@export var telegraph_text: String = ""
@export var telegraph_color: Color = Color(1, 0.8, 0.2)
@export var duration: float = 3.0 ## 最长时长（秒），超时判 FAIL
@export var difficulty_offset: float = 0.0
