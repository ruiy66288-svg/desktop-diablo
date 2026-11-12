class_name PresentationBus extends RefCounted

## 模拟层到渲染层的单向事件环形/缓冲总线 (依据 02号文件 §2.1 & Q10 防线)
## Sim 层仅负责只读推送，表现层按帧排空消费

const SimEvent = preload("res://simulation/events/SimEvent.gd")

var _events: Array = []
var _lock: bool = false

# 离线/最小化积攒的统计数据 (Q10: 最小化恢复时不喷射上千散落物，而是汇总弹窗)
var minimized_summary: Dictionary = {
	"kills": 0,
	"drops_count": 0,
	"smelt_gold": 0.0,
	"rare_drops": []
}

func push(ev: RefCounted) -> void:
	_events.push_back(ev)

## 正常渲染状态下排空并消费所有待处理事件
func drain_all() -> Array:
	if _events.is_empty():
		return []
	var res := _events.duplicate()
	_events.clear()
	return res

## 窗口最小化或完全被遮挡时消费事件 (Q10 铁律: 避免恢复时瞬间实例化数千节点)
func drain_for_minimized() -> void:
	if _events.is_empty():
		return

	for ev in _events:
		match ev.type:
			SimEvent.T.KILL, SimEvent.T.BOSS_KILL:
				minimized_summary["kills"] += 1
			SimEvent.T.DROP:
				minimized_summary["drops_count"] += ev.count
				var rarity: int = ev.payload.get("rarity", 0)
				if rarity >= 3: # 暗金及以上保留摘要记录
					minimized_summary["rare_drops"].push_back(ev.payload)
			SimEvent.T.SMELT:
				minimized_summary["smelt_gold"] += ev.value

	_events.clear()

## 恢复窗口时提取回归汇总数据并重置
func fetch_and_reset_minimized_summary() -> Dictionary:
	var copy: Dictionary = minimized_summary.duplicate(true)
	minimized_summary = {
		"kills": 0,
		"drops_count": 0,
		"smelt_gold": 0.0,
		"rare_drops": []
	}
	return copy

func get_pending_count() -> int:
	return _events.size()
