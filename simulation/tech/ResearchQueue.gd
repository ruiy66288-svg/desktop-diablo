class_name ResearchQueue extends RefCounted

## 研究队列 (依据《02_系统架构与数值_v6.md》§5.3、Q27 与《00_开发执行总纲.md》WP-14)
## 基于 Unix 时间戳（整数秒）顺序推进：队首开始时间 = max(入队时刻, 前一项完成时刻)，离线期间按时间戳比较即可连续完成多项
## 纯 RefCounted，零 Node 依赖；时间戳由外部传入，保证 Sim 确定性

class Entry extends RefCounted:
	var node_id: String = ""
	var start_unix: int = 0
	var end_unix: int = 0

var entries: Array[Entry] = []

func size() -> int:
	return entries.size()

func is_full(max_slots: int) -> bool:
	return entries.size() >= max_slots

func contains(node_id: String) -> bool:
	for e: Entry in entries:
		if e.node_id == node_id:
			return true
	return false

## 当前队尾完成时刻（空队列返回 now_unix）
func get_tail_end_unix(now_unix: int) -> int:
	if entries.is_empty():
		return now_unix
	return maxi(now_unix, entries[entries.size() - 1].end_unix)

func push(node_id: String, now_unix: int, duration_seconds: int, max_slots: int) -> bool:
	if is_full(max_slots) or contains(node_id):
		return false
	var e: Entry = Entry.new()
	e.node_id = node_id
	e.start_unix = get_tail_end_unix(now_unix)
	e.end_unix = e.start_unix + maxi(0, duration_seconds)
	entries.push_back(e)
	return true

## 结算所有 end_unix <= now_unix 的队首项，按完成顺序返回节点 id
func settle(now_unix: int) -> Array[String]:
	var done: Array[String] = []
	while not entries.is_empty() and entries[0].end_unix <= now_unix:
		done.push_back(entries[0].node_id)
		entries.remove_at(0)
	return done

func get_head_remaining_seconds(now_unix: int) -> int:
	if entries.is_empty():
		return 0
	return maxi(0, entries[0].end_unix - now_unix)

func to_array() -> Array:
	var out: Array = []
	for e: Entry in entries:
		out.push_back({"node_id": e.node_id, "start_unix": e.start_unix, "end_unix": e.end_unix})
	return out

func load_from_array(data: Array) -> void:
	entries.clear()
	for item_var: Variant in data:
		var d: Dictionary = item_var as Dictionary
		var e: Entry = Entry.new()
		e.node_id = String(d.get("node_id", ""))
		e.start_unix = int(d.get("start_unix", 0))
		e.end_unix = int(d.get("end_unix", 0))
		entries.push_back(e)

func get_signature() -> String:
	var parts: PackedStringArray = PackedStringArray()
	for e: Entry in entries:
		parts.append("%s:%d:%d" % [e.node_id, e.start_unix, e.end_unix])
	return ",".join(parts)

func clone() -> ResearchQueue:
	var copy: ResearchQueue = (get_script() as GDScript).new() as ResearchQueue
	for e: Entry in entries:
		var c: Entry = Entry.new()
		c.node_id = e.node_id
		c.start_unix = e.start_unix
		c.end_unix = e.end_unix
		copy.entries.push_back(c)
	return copy