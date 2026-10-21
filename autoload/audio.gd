extends Node
## 音乐和音效。总线：Master（主音量）、Music、SFX、Ambience。
## 占位音是 beep。曲目 id 不写死成音效编号，音效编号只出现在各自的触发点。

const RULES_PATH := "res://data/audio/music_rules.tres"
const VOICES := 12

var rules: MusicRules
var bed_id := ""
var bed_gain := 0.0
var bed_target := 0.0
var combat_gain := 0.0
var combat_pressure := false
var combat_hold := -1.0
var boss_id := ""
var boss_gain := 0.0
var arm_boss := ""
var sting_id := ""
var sting_gain := 0.0
var reduced := false
var lowpass := 0.0 ## 1 = 低通全关，0 = 打开
var lowpass_target := 0.0
var mode := ""
var bar_t := 0.0
var silence_left := 0.0
var cut_left := -1.0
var step_manual := false ## 测试时自己 tick，不跟 _process

var _lp: AudioEffectLowPassFilter
var _bed: AudioStreamPlayer
var _combat: AudioStreamPlayer
var _boss: AudioStreamPlayer
var _sting: AudioStreamPlayer
var _voices: Array[AudioStreamPlayer] = []
var _voice_i := 0
var loops := {}
var _holds := {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_bus("Music")
	_bus("SFX")
	_bus("Ambience")
	var mb := AudioServer.get_bus_index("Music")
	if AudioServer.get_bus_effect_count(mb) == 0:
		_lp = AudioEffectLowPassFilter.new()
		_lp.cutoff_hz = 20000.0
		AudioServer.add_bus_effect(mb, _lp)
	else:
		_lp = AudioServer.get_bus_effect(mb, 0) as AudioEffectLowPassFilter
	rules = load(RULES_PATH)
	_bed = _mk("Music")
	_combat = _mk("Music")
	_boss = _mk("Music")
	_sting = _mk("Music")
	apply_volumes()

func _process(delta: float) -> void:
	if step_manual:
		return
	tick(delta)
	_decay_holds()

func _bus(bus_name: String) -> int:
	var i := AudioServer.get_bus_index(bus_name)
	if i >= 0:
		return i
	AudioServer.add_bus()
	i = AudioServer.bus_count - 1
	AudioServer.set_bus_name(i, bus_name)
	AudioServer.set_bus_send(i, "Master")
	return i

func _mk(bus_name: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = bus_name
	p.process_mode = Node.PROCESS_MODE_ALWAYS
	p.volume_db = -80.0
	add_child(p)
	return p

func apply_volumes() -> void:
	_vol("Master", Settings.vol_master)
	_vol("Music", Settings.vol_music)
	_vol("SFX", Settings.vol_sfx)
	_vol("Ambience", Settings.vol_ambience)

func _vol(bus_name: String, linear: float) -> void:
	var i := AudioServer.get_bus_index(bus_name)
	if i < 0:
		return
	AudioServer.set_bus_volume_db(i, linear_to_db(maxf(linear, 0.0001)) if linear > 0.001 else -80.0)

func _freq(id: String) -> float:
	var h := id.hash()
	if h < 0:
		h = -h
	return 140.0 + float(h % 520)

func _approach(cur: float, target: float, sec: float, dt: float) -> float:
	if sec <= 0.001:
		return target
	return move_toward(cur, target, dt / sec)

func tick(dt: float) -> void:
	if rules == null or dt <= 0.0:
		return
	var lp_dt := dt
	match mode:
		"floor":
			_tick_floor(dt)
		"boss":
			_tick_boss(dt)
		"silence":
			silence_left -= dt
			bed_gain = 0.0
			combat_gain = 0.0
			boss_gain = 0.0
			if silence_left <= 0.0:
				lp_dt = maxf(0.0, -silence_left)
				_start_explore_muffled()
			else:
				lp_dt = 0.0
		"dead":
			_tick_dead(dt)
		_:
			pass
	if lowpass > 0.001 or lowpass_target > 0.001:
		lowpass = _approach(lowpass, lowpass_target, rules.lowpass_sec, lp_dt)
	_sync_all()

func _tick_floor(dt: float) -> void:
	bed_gain = _approach(bed_gain, bed_target, rules.explore_fade_sec, dt)
	if combat_pressure:
		combat_hold = -1.0
		combat_gain = _approach(combat_gain, 1.0, rules.combat_in_sec, dt)
	elif combat_gain > 0.001 or combat_hold >= 0.0:
		var fade_dt := dt
		if combat_hold < 0.0:
			combat_hold = rules.combat_out_sec
		if combat_hold > 0.0:
			var use := minf(combat_hold, fade_dt)
			combat_hold -= use
			fade_dt -= use
		if combat_hold <= 0.0 and fade_dt > 0.0:
			combat_gain = _approach(combat_gain, 0.0, rules.combat_fade_sec, fade_dt)
	_advance_bar(dt)

func _tick_boss(dt: float) -> void:
	bed_gain = _approach(bed_gain, 0.0, rules.boss_fade_sec, dt)
	combat_gain = _approach(combat_gain, 0.0, rules.boss_fade_sec, dt)
	combat_hold = -1.0
	_advance_bar(dt)

func _tick_dead(dt: float) -> void:
	var sec := maxf(rules.death_cut_sec, 0.05)
	bed_gain = _approach(bed_gain, 0.0, sec, dt)
	combat_gain = _approach(combat_gain, 0.0, sec, dt)
	boss_gain = _approach(boss_gain, 0.0, sec, dt)
	cut_left -= dt
	if cut_left <= 0.0 and sting_id == "":
		sting_id = "BGM-06"
		sting_gain = 1.0
		bed_gain = 0.0
		combat_gain = 0.0
		boss_gain = 0.0
		bed_id = ""
		boss_id = ""
		arm_boss = ""

func _advance_bar(dt: float) -> void:
	var bar := maxf(rules.bar_sec, 0.05)
	bar_t += dt
	while bar_t >= bar:
		bar_t -= bar
		if arm_boss != "":
			boss_id = arm_boss
			boss_gain = 1.0
			arm_boss = ""

func _start_explore_muffled() -> void:
	mode = "floor"
	reduced = false
	bed_id = "BGM-02"
	bed_gain = 0.0
	bed_target = 1.0
	combat_gain = 0.0
	combat_pressure = false
	combat_hold = -1.0
	boss_id = ""
	boss_gain = 0.0
	arm_boss = ""
	lowpass = 1.0
	lowpass_target = 0.0
	silence_left = 0.0

func _clear_music() -> void:
	bed_id = ""
	bed_gain = 0.0
	bed_target = 0.0
	combat_gain = 0.0
	combat_pressure = false
	combat_hold = -1.0
	boss_id = ""
	boss_gain = 0.0
	arm_boss = ""
	sting_id = ""
	sting_gain = 0.0
	lowpass = 0.0
	lowpass_target = 0.0
	silence_left = 0.0
	cut_left = -1.0

func enter_village(p_reduced: bool) -> void:
	_stop_all_loops()
	_clear_music()
	mode = "village"
	reduced = p_reduced
	bed_id = "BGM-01"
	bed_target = rules.reduced_gain if p_reduced else 1.0
	bed_gain = bed_target
	_sync_all()

func enter_floor() -> void:
	_stop_all_loops()
	_clear_music()
	mode = "floor"
	reduced = false
	bed_id = "BGM-02"
	bed_gain = 0.0
	bed_target = 1.0
	bar_t = 0.0
	_sync_all()

func enter_boss() -> void:
	if mode == "boss" or mode == "dead":
		return
	mode = "boss"
	if arm_boss != "BGM-04b":
		arm_boss = "BGM-04"
	bed_target = 0.0
	combat_hold = -1.0

func notify_boss_hp(ratio: float) -> void:
	if mode != "boss" or rules == null:
		return
	if ratio > rules.boss_hp_ratio:
		return
	if boss_id == "BGM-04b" or arm_boss == "BGM-04b":
		return
	arm_boss = "BGM-04b"

func boss_dead() -> void:
	if mode == "dead":
		return
	boss_id = ""
	boss_gain = 0.0
	arm_boss = ""
	combat_gain = 0.0
	combat_pressure = false
	bed_gain = 0.0
	bed_id = ""
	bed_target = 0.0
	mode = "silence"
	silence_left = rules.boss_silence_sec if rules else 1.0
	sting_id = ""
	sting_gain = 0.0
	_sync_all()

func extract_success() -> void:
	sting_id = "BGM-05"
	sting_gain = 1.0
	_sync_all()

func player_dead() -> void:
	if mode == "dead":
		return
	mode = "dead"
	cut_left = rules.death_cut_sec if rules else 0.3
	arm_boss = ""
	combat_pressure = false
	sting_id = ""
	sting_gain = 0.0

func set_combat_pressure(on: bool) -> void:
	combat_pressure = on

func _sync_all() -> void:
	if _lp:
		_lp.cutoff_hz = lerpf(500.0, 20000.0, 1.0 - clampf(lowpass, 0.0, 1.0))
	_sync(_bed, bed_id, bed_gain)
	_sync(_combat, "BGM-03" if combat_gain > 0.02 else "", combat_gain)
	_sync(_boss, boss_id, boss_gain)
	_sync(_sting, sting_id, sting_gain)

func _sync(p: AudioStreamPlayer, id: String, gain: float) -> void:
	if p == null:
		return
	var cur := str(p.get_meta("bid", ""))
	if id != cur:
		p.set_meta("bid", id)
		p.stop()
		if id != "":
			var w := Beep.tone(_freq(id), 0.5, 0.28).duplicate()
			w.loop_mode = AudioStreamWAV.LOOP_FORWARD
			w.loop_begin = 0
			w.loop_end = 0
			p.stream = w
	var audible := id != "" and gain > 0.02
	p.volume_db = linear_to_db(maxf(gain, 0.001)) if audible else -80.0
	if audible and not p.playing:
		p.play()
	elif not audible and p.playing:
		p.stop()

func sfx(id: String, bus := "SFX") -> void:
	if id == "":
		return
	var p := _voice()
	p.bus = bus
	p.stream = Beep.tone(_freq(id), 0.18, 0.35)
	p.volume_db = -6.0
	p.play()

func loop(id: String, bus := "SFX") -> void:
	if id == "" or loops.has(id):
		return
	var p := AudioStreamPlayer.new()
	p.bus = bus
	p.process_mode = Node.PROCESS_MODE_ALWAYS
	var w := Beep.tone(_freq(id), 0.45, 0.2).duplicate()
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_begin = 0
	w.loop_end = 0
	p.stream = w
	p.volume_db = -8.0
	add_child(p)
	p.play()
	loops[id] = p

func stop_loop(id: String) -> void:
	if not loops.has(id):
		_holds.erase(id)
		return
	var p: AudioStreamPlayer = loops[id]
	loops.erase(id)
	_holds.erase(id)
	if is_instance_valid(p):
		p.stop()
		p.queue_free()

func hold(id: String, bus := "SFX") -> void:
	_holds[id] = Engine.get_frames_drawn()
	loop(id, bus)

func _decay_holds() -> void:
	var frame := Engine.get_frames_drawn()
	for id in _holds.keys():
		if int(_holds[id]) < frame:
			stop_loop(str(id))

func _stop_all_loops() -> void:
	for id in loops.keys():
		stop_loop(str(id))

func _voice() -> AudioStreamPlayer:
	for p in _voices:
		if not p.playing:
			return p
	if _voices.size() < VOICES:
		var p := _mk("SFX")
		_voices.append(p)
		return p
	_voice_i = (_voice_i + 1) % _voices.size()
	return _voices[_voice_i]
