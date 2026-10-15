class_name Beep
extends RefCounted
## 生成占位音效（节拍器 / 预兆）

static var _cache := {}

static func tone(freq: float, dur: float = 0.04, vol: float = 0.5) -> AudioStreamWAV:
	var key := "%s_%s_%s" % [freq, dur, vol]
	if _cache.has(key):
		return _cache[key]
	var rate := 44100
	var n := int(rate * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var env := 1.0 - float(i) / n
		var v := int(clampf(sin(TAU * freq * i / rate) * env * vol, -1.0, 1.0) * 32767)
		data.encode_s16(i * 2, v)
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = data
	_cache[key] = w
	return w

static func play(parent: Node, freq: float, dur: float = 0.04) -> void:
	var p := AudioStreamPlayer.new()
	p.stream = tone(freq, dur)
	parent.add_child(p)
	p.play()
	p.finished.connect(p.queue_free)
