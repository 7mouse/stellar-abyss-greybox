class_name MinigameBase
extends Control
## 小游戏统一接口。子类实现 _begin() / _tick(delta) / _on_timeout()，用 _finish() 结束。
## start(config, context)：context 含 depth（层数）、luck、trait_bonus。
## 难度 = base_difficulty + config.difficulty_offset + depth * depth_scale − trait_bonus

enum Result { PERFECT, GOOD, FAIL }
const RESULT_NAMES := ["PERFECT", "GOOD", "FAIL"]
const RESULT_CN := ["完美", "良好", "失败"]

signal finished(result: int, score: float)

var config: MinigameConfig
var context: Dictionary
var difficulty: float = 0.0
var elapsed: float = 0.0
var active := false
var done := false

func start(p_config: MinigameConfig, p_context: Dictionary) -> void:
	config = p_config
	context = p_context
	difficulty = compute_difficulty(config, context)
	set_anchors_preset(Control.PRESET_FULL_RECT)
	await _play_telegraph()
	if done or not is_inside_tree():
		return
	var auto: int = int(context.get("auto", -1))
	if auto >= 0:
		_finish(auto, [1.0, 0.6, 0.0][auto])
		return
	elapsed = 0.0
	active = true
	_begin()

static func compute_difficulty(cfg: MinigameConfig, ctx: Dictionary) -> float:
	var t: Tunables = GameState.tunables
	return maxf(0.0, t.base_difficulty + cfg.difficulty_offset + float(ctx.get("depth", 1)) * t.depth_scale - float(ctx.get("trait_bonus", 0.0)))

## 有效深度：把难度换算回“层数”尺度，供各小游戏的随深度参数使用。
## 默认参数下等于当前层数；base_difficulty/difficulty_offset 升高或特长加成降低都会平移它。
func eff_depth() -> float:
	var t: Tunables = GameState.tunables
	return maxf(1.0, (difficulty - 1.0) / maxf(t.depth_scale, 0.01))

## 预兆提示：图标色块 + 文字 + 音效占位，0.5~1.0 秒
func _play_telegraph() -> void:
	var layer := Control.new()
	layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(layer)
	var vs := get_viewport_rect().size
	UI.rect(layer, Vector2(0, vs.y / 2 - 140), Vector2(vs.x, 280), Color(0, 0, 0, 0.55))
	UI.rect(layer, Vector2(vs.x / 2 - 360, vs.y / 2 - 60), Vector2(120, 120), config.telegraph_color)
	UI.label(layer, "！", Vector2(vs.x / 2 - 320, vs.y / 2 - 50), 72, Color.BLACK)
	UI.label(layer, config.telegraph_text, Vector2(vs.x / 2 - 210, vs.y / 2 - 50), 56, config.telegraph_color)
	Beep.play(self, 660.0, 0.15)
	UI.label(layer, "♪ 预兆音效（占位）", Vector2(vs.x / 2 - 210, vs.y / 2 + 20), 24, Color(0.8, 0.8, 0.8))
	await get_tree().create_timer(clampf(config.telegraph_sec, 0.5, 1.0)).timeout
	if is_instance_valid(layer):
		layer.queue_free()

func _process(delta: float) -> void:
	if not active:
		return
	elapsed += delta
	_tick(delta)
	if active and elapsed >= config.duration:
		_on_timeout()

func _finish(result: int, score: float) -> void:
	if done:
		return
	done = true
	active = false
	finished.emit(result, score)

# ---- 子类覆写 ----
func _begin() -> void:
	pass

func _tick(_delta: float) -> void:
	pass

func _on_timeout() -> void:
	_finish(Result.FAIL, 0.0)
