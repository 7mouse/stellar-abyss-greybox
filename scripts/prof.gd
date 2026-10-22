class_name Prof
## 轻量分段计时（只在 Prof.on 时计时）：Prof.t0() / Prof.add("名字", t0)；每帧由 Game 收进环形缓冲，网页 greybox.profDump() 读
static var on := false
static var cur := {} ## 本帧：名字 -> 微秒
static var cnt := {} ## 本帧：名字 -> 次数
static var frames: Array = [] ## 最近 N 帧 [{...}]
static var max_frames := 600

static func t0() -> int:
	return Time.get_ticks_usec() if on else 0

static func add(name: String, start: int) -> void:
	if on:
		cur[name] = int(cur.get(name, 0)) + Time.get_ticks_usec() - start
		cnt[name] = int(cnt.get(name, 0)) + 1

static func count(name: String, n := 1) -> void:
	if on:
		cnt[name] = int(cnt.get(name, 0)) + n

static func end_frame(extra: Dictionary) -> void:
	if not on:
		return
	var r := extra.duplicate()
	r["us"] = cur.duplicate()
	r["n"] = cnt.duplicate()
	frames.append(r)
	if frames.size() > max_frames:
		frames.pop_front()
	cur.clear()
	cnt.clear()
