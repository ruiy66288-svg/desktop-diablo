class_name Inventory extends RefCounted

## 24 格背包管理器 (依据《02_系统架构与数值_v6.md》§0 Q13 & WP-05: 容量读取 Balance，满格时自动熔炼评分最低项)
## 纯 RefCounted，零 Node 依赖

const ItemInstanceScript = preload("res://simulation/loot/ItemInstance.gd")
const SmelterScript = preload("res://simulation/loot/Smelter.gd")
const EventQueueScript = preload("res://simulation/events/EventQueue.gd")
const BalanceScript = preload("res://simulation/Balance.gd")

var items: Array[ItemInstanceScript] = []

## 尝试将新装备收入背包；满 24 格时淘汰并自动熔炼评分最低项（若新装备自身最低则直接熔炼新装备）
func add_item(new_item: ItemInstanceScript, state: RefCounted, queue: EventQueueScript = null) -> bool:
	if new_item == null:
		return false
	var bal: BalanceScript = state.get("balance") as BalanceScript
	var max_slots: int = bal.inventory_max_slots if bal != null else (BalanceScript.load_default() as BalanceScript).inventory_max_slots

	if items.size() < max_slots:
		items.push_back(new_item)
		return true

	var lowest_idx: int = 0
	var lowest_score: float = items[0].score
	for i: int in range(1, items.size()):
		if items[i].score < lowest_score:
			lowest_score = items[i].score
			lowest_idx = i

	if new_item.score > lowest_score:
		var discarded: ItemInstanceScript = items[lowest_idx]
		items.remove_at(lowest_idx)
		SmelterScript.smelt_item(discarded, state, queue)
		items.push_back(new_item)
		return true

	SmelterScript.smelt_item(new_item, state, queue)
	return false

func find_item_by_uid(uid: int) -> ItemInstanceScript:
	for i: int in range(items.size()):
		if items[i].uid == uid:
			return items[i]
	return null

func remove_item_by_uid(uid: int) -> ItemInstanceScript:
	for i: int in range(items.size()):
		if items[i].uid == uid:
			var item: ItemInstanceScript = items[i]
			items.remove_at(i)
			return item
	return null

func get_lowest_score_item() -> ItemInstanceScript:
	if items.is_empty():
		return null
	var lowest_item: ItemInstanceScript = items[0]
	for i: int in range(1, items.size()):
		if items[i].score < lowest_item.score:
			lowest_item = items[i]
	return lowest_item

func get_item_at(idx: int) -> ItemInstanceScript:
	if idx >= 0 and idx < items.size():
		return items[idx]
	return null

func is_full(max_slots: int) -> bool:
	return items.size() >= max_slots

func get_count() -> int:
	return items.size()

func clear() -> void:
	items.clear()

func clone() -> Inventory:
	var copy: Inventory = (get_script() as GDScript).new() as Inventory
	for it: ItemInstanceScript in items:
		copy.items.push_back(it.clone())
	return copy
