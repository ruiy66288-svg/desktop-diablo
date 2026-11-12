class_name EventQueue extends RefCounted

## 延迟 FIFO 事件队列 (依据《02_系统架构与数值_v6.md》§2.2–§2.3)
## 纯 RefCounted，零 Node 依赖

const SimEventScript = preload("res://simulation/events/SimEvent.gd")
const NumScript = preload("res://core/num/Num.gd")
const BalanceScript = preload("res://simulation/Balance.gd")

var _queue: Array[SimEventScript] = []

func push_back(ev: SimEventScript) -> void:
	_queue.push_back(ev)

func pop_front() -> SimEventScript:
	if _queue.is_empty():
		return null
	return _queue.pop_front()

func is_empty() -> bool:
	return _queue.is_empty()

func size() -> int:
	return _queue.size()

func clear() -> void:
	_queue.clear()

## 压缩队列中无特殊载荷的同类高频事件，绝不丢失 count 计数 (§2.3)
func compact_same_type(p_threshold: int = -1) -> void:
	var threshold: int = p_threshold
	if threshold < 0:
		threshold = BalanceScript.load_default().event_compact_threshold
	if _queue.size() <= threshold:
		return

	var compacted: Dictionary = {}
	var other_events: Array[SimEventScript] = []

	for ev: SimEventScript in _queue:
		var is_mergeable: bool = ev.payload.is_empty() and (
			ev.type == SimEventScript.T.HIT
			or ev.type == SimEventScript.T.SMELT
			or ev.type == SimEventScript.T.DROP
		)
		if is_mergeable:
			var key: int = int(ev.type)
			if not compacted.has(key):
				compacted[key] = ev
			else:
				var target: SimEventScript = compacted[key] as SimEventScript
				target.count += ev.count
				target.value = NumScript.add(target.value, ev.value)
		else:
			other_events.push_back(ev)

	_queue.clear()
	for merged_var: Variant in compacted.values():
		var merged_ev: SimEventScript = merged_var as SimEventScript
		_queue.push_back(merged_ev)
	for other_ev: SimEventScript in other_events:
		_queue.push_back(other_ev)
