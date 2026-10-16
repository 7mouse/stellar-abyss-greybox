extends Node
## 玩家设置（autoload Settings），持久化到 user://settings.cfg

signal fast_forward_changed(on: bool)
signal changed

const SECTION := "gameplay"
var path := "user://settings.cfg"
var fast_forward := false
## user://settings.cfg [gameplay] camera_shake：0 / 50 / 100，乘在所有震屏上
var camera_shake := 100
## user://settings.cfg [gameplay] hitstop
var hitstop_enabled := true

func _ready() -> void:
	load_settings()

func load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(path) == OK:
		fast_forward = bool(cf.get_value(SECTION, "fast_forward", false))
		camera_shake = _snap_shake(int(cf.get_value(SECTION, "camera_shake", 100)))
		hitstop_enabled = bool(cf.get_value(SECTION, "hitstop", true))
	else:
		fast_forward = false
		camera_shake = 100
		hitstop_enabled = true
	fast_forward_changed.emit(fast_forward)
	changed.emit()

func shake_mul() -> float:
	return float(camera_shake) / 100.0

func _snap_shake(v: int) -> int:
	if v <= 0:
		return 0
	if v <= 50:
		return 50
	return 100

func _write(key: String, value) -> void:
	var cf := ConfigFile.new()
	cf.load(path) # 保留文件里其他设置
	cf.set_value(SECTION, key, value)
	cf.save(path)

func set_fast_forward(on: bool) -> void:
	fast_forward = on
	_write("fast_forward", on)
	fast_forward_changed.emit(on)

func set_camera_shake(pct: int) -> void:
	camera_shake = _snap_shake(pct)
	_write("camera_shake", camera_shake)
	changed.emit()

func set_hitstop_enabled(on: bool) -> void:
	hitstop_enabled = on
	_write("hitstop", on)
	if not on and is_instance_valid(Game):
		Game.clear_hitstop()
	changed.emit()

func toggle_fast_forward() -> void:
	set_fast_forward(not fast_forward)
