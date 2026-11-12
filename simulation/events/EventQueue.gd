class_name EventQueue extends RefCounted

## 延迟 FIFO 事件队列 (依据《02_系统架构与数值_v6.md》§2.2–§2.3)
## 纯 RefCounted，零 Node 依赖

const SimEventScript = preload("res://simulation/events/SimEvent.gd")
const EventCompactorScript = preload("res://simulation/events/EventCompactor.gd")
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

## 只读快照（浅拷贝数组，事件对象共享）
func snapshot() -> Array[SimEventScript]:
	return _queue.duplicate()

## 压缩队列中无特殊载荷的同类高频事件，绝不丢失 count 计数 (§2.3)
func compact_same_type(p_threshold: int = -1) -> void:
	var threshold: int = p_threshold
	if threshold < 0:
		threshold = (BalanceScript.load_default() as BalanceScript).event_compact_threshold
	if _queue.size() <= threshold:
		return
	_queue = EventCompactorScript.merge_by_type(_queue)
