class_name SfxMixer extends RefCounted

## 性能友好型音效调度器 (依据《02_系统架构与数值_v6.md》§3.3 & §6.3 规范)
## 同帧同类音效合并，随机音高 ±5%，单类并发上限 4，并与 VfxBudget 单帧总上限 6 协同

const VfxBudgetScript = preload("res://presentation/VfxBudget.gd")

const MAX_CONCURRENT_PER_TYPE: int = 4
const PITCH_MIN: float = 0.95
const PITCH_MAX: float = 1.05

var _played_counts_this_frame: Dictionary = {}
var _merged_counts_this_frame: Dictionary = {}

func begin_frame() -> void:
	_played_counts_this_frame.clear()
	_merged_counts_this_frame.clear()

## 请求播放音效 (带并发限制、VfxBudget 协同与随机音高计算)
## 返回 Dictionary: {"play": bool, "pitch_scale": float, "merged": bool}
func request_play_sound(sound_id: String, budget: VfxBudgetScript = null) -> Dictionary:
	var current_count: int = int(_played_counts_this_frame.get(sound_id, 0))
	if current_count >= MAX_CONCURRENT_PER_TYPE:
		_merged_counts_this_frame[sound_id] = int(_merged_counts_this_frame.get(sound_id, 0)) + 1
		return {"play": false, "pitch_scale": 1.0, "merged": true}

	if budget != null and not budget.request_sfx():
		_merged_counts_this_frame[sound_id] = int(_merged_counts_this_frame.get(sound_id, 0)) + 1
		return {"play": false, "pitch_scale": 1.0, "merged": true}

	_played_counts_this_frame[sound_id] = current_count + 1
	var pitch: float = randf_range(PITCH_MIN, PITCH_MAX)
	return {"play": true, "pitch_scale": pitch, "merged": false}

func get_merged_count(sound_id: String) -> int:
	return int(_merged_counts_this_frame.get(sound_id, 0))
