extends Node
## 玩家设置（autoload Settings），持久化到 user://settings.cfg

signal fast_forward_changed(on: bool)

const SECTION := "gameplay"
var path := "user://settings.cfg"
var fast_forward := false

func _ready() -> void:
	load_settings()

func load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(path) == OK:
		fast_forward = bool(cf.get_value(SECTION, "fast_forward", false))
	else:
		fast_forward = false
	fast_forward_changed.emit(fast_forward)

func set_fast_forward(on: bool) -> void:
	fast_forward = on
	var cf := ConfigFile.new()
	cf.load(path) # 保留文件里其他设置
	cf.set_value(SECTION, "fast_forward", on)
	cf.save(path)
	fast_forward_changed.emit(on)

func toggle_fast_forward() -> void:
	set_fast_forward(not fast_forward)
