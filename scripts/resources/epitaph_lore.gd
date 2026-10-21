class_name EpitaphLore
extends Resource
## #0000 墓碑文案。已读记在 user://profile.cfg（和教学共用 Tutorial.path）的 epitaph_0000_read。

const PROFILE_KEY := "epitaph_0000_read"

@export var lines: PackedStringArray = PackedStringArray()
@export var line_sec := 1.2
@export var flash_text := "[CRADLE] subject #0000 … record mismatch"
@export var slot_text := "#0000"

static func was_read() -> bool:
	var cf := ConfigFile.new()
	if cf.load(Tutorial.path) != OK:
		return false
	return bool(cf.get_value("profile", PROFILE_KEY, false))

static func mark_read() -> void:
	var cf := ConfigFile.new()
	cf.load(Tutorial.path)
	cf.set_value("profile", PROFILE_KEY, true)
	cf.save(Tutorial.path)
