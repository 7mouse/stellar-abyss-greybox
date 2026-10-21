extends Node
## 玩家设置（autoload Settings），持久化到 user://settings.cfg

signal fast_forward_changed(on: bool)
signal changed

const SECTION := "gameplay"
const AUDIO := "audio"
var path := "user://settings.cfg"
var fast_forward := false
## user://settings.cfg [gameplay] camera_shake：0 / 50 / 100，乘在所有震屏上
var camera_shake := 100
## user://settings.cfg [gameplay] hitstop
var hitstop_enabled := true
## user://settings.cfg [audio] master / music / sfx / ambience，0 到 1
var vol_master := 1.0
var vol_music := 1.0
var vol_sfx := 1.0
var vol_ambience := 1.0

func _ready() -> void:
	load_settings()

func load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(path) == OK:
		fast_forward = bool(cf.get_value(SECTION, "fast_forward", false))
		camera_shake = _snap_shake(int(cf.get_value(SECTION, "camera_shake", 100)))
		hitstop_enabled = bool(cf.get_value(SECTION, "hitstop", true))
		vol_master = _snap_vol(float(cf.get_value(AUDIO, "master", 1.0)))
		vol_music = _snap_vol(float(cf.get_value(AUDIO, "music", 1.0)))
		vol_sfx = _snap_vol(float(cf.get_value(AUDIO, "sfx", 1.0)))
		vol_ambience = _snap_vol(float(cf.get_value(AUDIO, "ambience", 1.0)))
	else:
		fast_forward = false
		camera_shake = 100
		hitstop_enabled = true
		vol_master = 1.0
		vol_music = 1.0
		vol_sfx = 1.0
		vol_ambience = 1.0
	fast_forward_changed.emit(fast_forward)
	changed.emit()
	if is_instance_valid(Audio):
		Audio.apply_volumes()

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

func _snap_vol(v: float) -> float:
	return clampf(v, 0.0, 1.0)

func set_bus_volume(bus: String, linear: float) -> void:
	linear = _snap_vol(linear)
	var key := bus
	match bus:
		"master":
			vol_master = linear
		"music":
			vol_music = linear
		"sfx":
			vol_sfx = linear
		"ambience":
			vol_ambience = linear
		_:
			return
	var cf := ConfigFile.new()
	cf.load(path)
	cf.set_value(AUDIO, key, linear)
	cf.save(path)
	if is_instance_valid(Audio):
		Audio.apply_volumes()
	changed.emit()

func set_hitstop_enabled(on: bool) -> void:
	hitstop_enabled = on
	_write("hitstop", on)
	if not on and is_instance_valid(Game):
		Game.clear_hitstop()
	changed.emit()

func toggle_fast_forward() -> void:
	set_fast_forward(not fast_forward)
