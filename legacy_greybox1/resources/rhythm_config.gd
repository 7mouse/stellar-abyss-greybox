class_name RhythmConfig
extends MinigameConfig
## 第 6 组 节奏按键

@export var bpm: float = 100.0
@export var bpm_per_depth: float = 10.0
@export var bpm_max: float = 180.0
@export var note_count: int = 4
@export var notes_per_depth: int = 1
@export var note_count_max: int = 8
@export var perfect_ms: float = 50.0
@export var good_ms: float = 120.0
@export var good_weight: float = 0.75 ## GOOD 命中计 0.75 个
@export var perfect_ratio: float = 0.9 ## 命中比例 ≥ 此值 → PERFECT
@export var good_ratio: float = 0.6
@export var lead_beats: int = 2 ## 第一个音符前的空拍

func bpm_at(d: float) -> float:
	return minf(bpm_max, bpm + maxf(0.0, d - 1.0) * bpm_per_depth)

func notes_at(d: float) -> int:
	return clampi(note_count + int(floor(maxf(0.0, d - 1.0))) * notes_per_depth, 4, note_count_max)
