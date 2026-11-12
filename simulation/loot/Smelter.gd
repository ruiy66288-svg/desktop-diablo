class_name Smelter extends RefCounted

## 自动熔炼与手动拾取金币结算器 (依据《02_系统架构与数值_v6.md》§0 Q12/Q13、§1.7 与《00_开发执行总纲.md》§2 E1、WP-05)
## 铁律：唯一产出货币为 gold（严禁任何第二货币），对数运算统一走 Num，全部倍率读取 Balance

const NumScript = preload("res://core/num/Num.gd")
const ItemInstanceScript = preload("res://simulation/loot/ItemInstance.gd")
const SimEventScript = preload("res://simulation/events/SimEvent.gd")
const EventQueueScript = preload("res://simulation/events/EventQueue.gd")
const BalanceScript = preload("res://simulation/Balance.gd")

## 计算指定 iLvl 与品质对应的熔炼金币收益（Log10 域）
static func get_smelt_gold_log(ilvl: int, rarity: int, bal: BalanceScript) -> float:
	var base_gold_log: float = bal.get_mob_gold_log(maxi(1, ilvl))
	var rarity_mult_log: float = bal.get_smelt_mult_log(rarity)
	return NumScript.mul(base_gold_log, rarity_mult_log)

## 熔炼单件装备，计算金币收益（Log10 域）并入账 SimState，同时向事件队列发出 SMELT 事件
static func smelt_item(item: ItemInstanceScript, state: RefCounted, queue: EventQueueScript = null) -> float:
	if item == null or state == null:
		return NumScript.ZERO
	var bal: BalanceScript = state.get("balance") as BalanceScript
	var earned_gold_log: float = get_smelt_gold_log(item.ilvl, int(item.rarity), bal)

	state.call("add_income", earned_gold_log, queue)

	if queue != null:
		var ev: SimEventScript = SimEventScript.new(SimEventScript.T.SMELT, earned_gold_log)
		ev.payload = {"item_uid": item.uid, "rarity": int(item.rarity)}
		queue.push_back(ev)

	return earned_gold_log

## 结算鼠标手动划过拾取的额外金币奖励 (Q12: 掉落归属以 Sim 为准，手动拾取通过 Command 发放 +10% 金币)
static func grant_manual_pickup_bonus(
	state: RefCounted,
	ilvl: int = -1,
	rarity: int = 0,
	queue: EventQueueScript = null
) -> float:
	if state == null:
		return NumScript.ZERO
	var bal: BalanceScript = state.get("balance") as BalanceScript
	if bal == null or bal.manual_pickup_bonus_rate <= 0.0:
		return NumScript.ZERO

	var target_ilvl: int = ilvl if ilvl > 0 else int(state.call("get_active_stage"))
	var ref_gold_log: float = get_smelt_gold_log(target_ilvl, rarity, bal)
	var bonus_rate_log: float = NumScript.from_float(bal.manual_pickup_bonus_rate)
	var bonus_gold_log: float = NumScript.mul(ref_gold_log, bonus_rate_log)

	if bonus_gold_log != NumScript.ZERO:
		state.call("add_income", bonus_gold_log, queue)

	return bonus_gold_log
