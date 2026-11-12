class_name Smelter extends RefCounted

## 自动熔炼炉 (依据《02_系统架构与数值_v6.md》§0 Q13 & §1.7 与《00_开发执行总纲.md》§2 E1)
## 唯一产出货币为 gold（严禁任何第二货币），全部倍率读取 Balance

const ItemInstanceScript = preload("res://simulation/loot/ItemInstance.gd")
const SimEventScript = preload("res://simulation/events/SimEvent.gd")
const EventQueueScript = preload("res://simulation/events/EventQueue.gd")
const BalanceScript = preload("res://simulation/Balance.gd")

## 熔炼单件装备，计算金币收益（Log10 域）并入账 SimState
static func smelt_item(item: ItemInstanceScript, state: RefCounted, queue: EventQueueScript = null) -> float:
	var bal: BalanceScript = state.get("balance") as BalanceScript
	var base_gold_log: float = bal.get_mob_gold_log(item.ilvl)
	var rarity_mult_log: float = bal.get_smelt_mult_log(int(item.rarity))
	var earned_gold_log: float = base_gold_log + rarity_mult_log

	state.call("add_income", earned_gold_log, queue)

	if queue != null:
		var ev: SimEventScript = SimEventScript.new(SimEventScript.T.SMELT, earned_gold_log)
		ev.payload = {"item_uid": item.uid, "rarity": int(item.rarity)}
		queue.push_back(ev)

	return earned_gold_log
