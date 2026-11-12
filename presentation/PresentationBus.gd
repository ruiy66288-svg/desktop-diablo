class_name PresentationBus extends RefCounted

## 模拟层到渲染层的单向事件环形/缓冲总线 (依据《02_系统架构与数值_v6.md》§2.1、Q10 与勘误 E8)
## Sim 层仅负责只读推送，表现层按帧排空消费；最小化时持续汇总防恢复暴冲

const SimEventScript = preload("res://simulation/events/SimEvent.gd")
const NumScript = preload("res://core/num/Num.gd")

const RARE_SUMMARY_CAP: int = 32

var _events: Array[RefCounted] = []

# 离线/最小化积攒的回归汇总数据 (Q10: 最小化恢复时不喷射上千散落物，而是播一次受控汇总)
var minimized_summary: Dictionary = {
	"kills": 0,
	"drops_count": 0,
	"smelt_gold": 0.0,
	"smelt_gold_log": NumScript.ZERO,
	"rare_drops": []
}

func push(ev: RefCounted) -> void:
	if ev != null:
		_events.push_back(ev)

## 正常渲染状态下排空并消费所有待处理事件
func drain_all() -> Array[RefCounted]:
	if _events.is_empty():
		return []
	var res: Array[RefCounted] = _events.duplicate()
	_events.clear()
	return res

## 窗口最小化或完全被遮挡时消费事件 (Q10 & E8 铁律: 避免恢复时瞬间实例化数千节点)
func drain_for_minimized() -> void:
	if _events.is_empty():
		return

	var rare_list: Array = minimized_summary["rare_drops"] as Array
	var cur_smelt_log: float = float(minimized_summary["smelt_gold_log"])

	for ev_raw: RefCounted in _events:
		var ev: SimEventScript = ev_raw as SimEventScript
		if ev == null:
			continue
		match ev.type:
			SimEventScript.T.KILL, SimEventScript.T.BOSS_KILL:
				minimized_summary["kills"] = int(minimized_summary["kills"]) + maxi(1, ev.count)
			SimEventScript.T.DROP:
				minimized_summary["drops_count"] = int(minimized_summary["drops_count"]) + maxi(1, ev.count)
				var rarity: int = int(ev.payload.get("rarity", 0))
				if rarity >= 3 and rare_list.size() < RARE_SUMMARY_CAP:
					rare_list.push_back(ev.payload.duplicate())
			SimEventScript.T.SMELT:
				minimized_summary["smelt_gold"] = float(minimized_summary["smelt_gold"]) + ev.value
				cur_smelt_log = NumScript.add(cur_smelt_log, ev.value)

	minimized_summary["smelt_gold_log"] = cur_smelt_log
	_events.clear()

## 恢复窗口时提取回归汇总数据并重置
func fetch_and_reset_minimized_summary() -> Dictionary:
	var copy: Dictionary = minimized_summary.duplicate(true)
	minimized_summary = {
		"kills": 0,
		"drops_count": 0,
		"smelt_gold": 0.0,
		"smelt_gold_log": NumScript.ZERO,
		"rare_drops": []
	}
	return copy

func get_pending_count() -> int:
	return _events.size()
