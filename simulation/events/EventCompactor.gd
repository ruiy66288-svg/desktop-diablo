class_name EventCompactor extends RefCounted

## 同类事件合并器 (依据《02_系统架构与数值_v6.md》§2.3：同类事件合并 count，绝不丢计数)
## 纯静态、零 Node 依赖。仅合并无载荷、无特殊提示且 (类型, 深度, 因果链掩码) 完全一致的 HIT / SMELT / DROP

const SimEventScript = preload("res://simulation/events/SimEvent.gd")
const NumScript = preload("res://core/num/Num.gd")

const RESOLVED_HINT_KEY: String = "resolved"

static func _is_mergeable(ev: SimEventScript) -> bool:
	if not ev.payload.is_empty():
		return false
	if not (ev.hint.is_empty() or (ev.hint.size() == 1 and ev.hint.has(RESOLVED_HINT_KEY))):
		return false
	return (
		ev.type == SimEventScript.T.HIT
		or ev.type == SimEventScript.T.SMELT
		or ev.type == SimEventScript.T.DROP
	)

## 将事件数组中可合并事件按 (type, depth, chain_mask, resolved) 归并，保留首次出现顺序，count 与 value 严格累加
static func merge_by_type(events: Array[SimEventScript]) -> Array[SimEventScript]:
	var merged_index: Dictionary = {}
	var result: Array[SimEventScript] = []
	for ev: SimEventScript in events:
		if not _is_mergeable(ev):
			result.push_back(ev)
			continue
		var key: String = "%d:%d:%d:%s" % [
			int(ev.type), ev.depth, ev.chain_mask, str(bool(ev.hint.get(RESOLVED_HINT_KEY, false)))
		]
		if merged_index.has(key):
			var target: SimEventScript = result[int(merged_index[key])]
			target.count += ev.count
			target.value = NumScript.add(target.value, ev.value)
		else:
			merged_index[key] = result.size()
			result.push_back(ev)
	return result

## 事件总计数（用于验证合并前后 count 守恒）
static func total_count(events: Array[SimEventScript]) -> int:
	var total: int = 0
	for ev: SimEventScript in events:
		total += ev.count
	return total
