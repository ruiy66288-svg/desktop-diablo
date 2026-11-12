class_name CommandQueue extends RefCounted

## Simulation 权威指令 FIFO 队列与确定性执行器
## 依据《02_系统架构与数值_v6.md》§2.1、§3.2、Q12 与《00_开发执行总纲.md》§4.2、WP-05
## 铁律：表现层只读 Sim，外部输入一律封装为 Command 入队，在 SimRunner.step() 起始处按 FIFO 顺序确定性结算

const NumScript = preload("res://core/num/Num.gd")
const CommandScript = preload("res://simulation/commands/Command.gd")
const BalanceScript = preload("res://simulation/Balance.gd")
const ItemInstanceScript = preload("res://simulation/loot/ItemInstance.gd")
const SmelterScript = preload("res://simulation/loot/Smelter.gd")
const FilterScript = preload("res://simulation/loot/Filter.gd")
const InventoryScript = preload("res://simulation/loot/Inventory.gd")
const UpgradesScript = preload("res://simulation/progression/Upgrades.gd")
const EventQueueScript = preload("res://simulation/events/EventQueue.gd")

var _pending: Array[CommandScript] = []

func push(cmd: CommandScript) -> void:
	if cmd != null:
		_pending.push_back(cmd)

func enqueue(cmd: CommandScript) -> void:
	push(cmd)

func is_empty() -> bool:
	return _pending.is_empty()

func size() -> int:
	return _pending.size()

func clear() -> void:
	_pending.clear()

func pop_front() -> CommandScript:
	if _pending.is_empty():
		return null
	var cmd: CommandScript = _pending[0]
	_pending.remove_at(0)
	return cmd

## 在 tick 起始处按 FIFO 顺序消费并应用全部待处理指令，返回成功执行的指令条数
func drain_and_apply(state: RefCounted, event_queue: EventQueueScript = null) -> int:
	var executed_count: int = 0
	while not _pending.is_empty():
		var cmd: CommandScript = pop_front()
		if cmd != null and apply_command(cmd, state, event_queue):
			executed_count += 1
	return executed_count

## 确定性执行单条外部指令
func apply_command(cmd: CommandScript, state: RefCounted, event_queue: EventQueueScript = null) -> bool:
	if cmd == null or state == null:
		return false

	var bal: BalanceScript = state.get("balance") as BalanceScript

	match cmd.type:
		CommandScript.Type.BUY_ATK_UPGRADE:
			var count: int = maxi(1, int(cmd.payload.get("count", 1)))
			var upgrades: UpgradesScript = state.get("upgrades") as UpgradesScript
			if upgrades == null:
				return false
			return upgrades.buy_atk_upgrades_bulk(state, count) > 0

		CommandScript.Type.MANUAL_PICKUP:
			if cmd.payload.has("base_gold_log"):
				var base_log: float = float(cmd.payload["base_gold_log"])
				if base_log == NumScript.ZERO or bal.manual_pickup_bonus_rate <= 0.0:
					return false
				var bonus_log: float = NumScript.mul(base_log, NumScript.from_float(bal.manual_pickup_bonus_rate))
				state.call("add_income", bonus_log, event_queue)
				return true
			var ilvl_arg: int = int(cmd.payload.get("ilvl", -1))
			var rarity_arg: int = int(cmd.payload.get("rarity", 0))
			var bonus_earned: float = SmelterScript.grant_manual_pickup_bonus(state, ilvl_arg, rarity_arg, event_queue)
			return bonus_earned != NumScript.ZERO

		CommandScript.Type.EQUIP_ITEM:
			var inv: InventoryScript = state.get("inventory") as InventoryScript
			var to_equip: ItemInstanceScript = null
			if cmd.payload.has("item_uid") and inv != null:
				var uid: int = int(cmd.payload["item_uid"])
				to_equip = inv.remove_item_by_uid(uid)
			elif cmd.payload.get("item") is ItemInstanceScript:
				to_equip = cmd.payload["item"] as ItemInstanceScript
			if to_equip == null:
				return false
			var prev_equipped: ItemInstanceScript = state.call("equip_item", to_equip) as ItemInstanceScript
			if prev_equipped != null and inv != null:
				inv.add_item(prev_equipped, state, event_queue)
			return true

		CommandScript.Type.SMELT_ITEM:
			var inv_smelt: InventoryScript = state.get("inventory") as InventoryScript
			if inv_smelt == null or not cmd.payload.has("item_uid"):
				return false
			var smelt_uid: int = int(cmd.payload["item_uid"])
			var target_item: ItemInstanceScript = inv_smelt.remove_item_by_uid(smelt_uid)
			if target_item == null:
				return false
			SmelterScript.smelt_item(target_item, state, event_queue)
			return true

		CommandScript.Type.SET_FILTER_THRESHOLD:
			var flt: FilterScript = state.get("filter") as FilterScript
			if flt == null or not cmd.payload.has("threshold"):
				return false
			flt.set_threshold(int(cmd.payload["threshold"]))
			return true

		CommandScript.Type.BORROW_CREDIT:
			var borrow_log: float = float(cmd.payload.get("amount_log", NumScript.ZERO))
			return bool(state.call("borrow_credit", borrow_log))

		CommandScript.Type.REPAY_CREDIT:
			var debt_now: float = float(state.get("debt_total"))
			var repay_log: float = float(cmd.payload.get("amount_log", debt_now))
			if state.has_method("repay_debt_with_gold"):
				var paid_log: float = float(state.call("repay_debt_with_gold", repay_log))
				return paid_log != NumScript.ZERO
			return false

		CommandScript.Type.SOUL_PRESTIGE:
			var preview: Dictionary = state.call("get_soul_prestige_preview") as Dictionary
			if not bool(preview.get("can_prestige", false)):
				return false   # 无可获灵魂时拒绝转生，避免白白清空进度
			state.call("perform_soul_prestige")
			return true

		CommandScript.Type.START_RESEARCH:
			return bool(state.call("start_research", String(cmd.payload.get("node_id", "")), int(cmd.payload.get("now_unix", 0))))

		CommandScript.Type.SETTLE_RESEARCH:
			var settled: Array = state.call("settle_research", int(cmd.payload.get("now_unix", 0)), event_queue) as Array
			return not settled.is_empty()

		CommandScript.Type.ABYSS_PRESTIGE:
			var power_id: String = String(cmd.payload.get("extract_power_id", ""))
			state.call("perform_abyss_prestige", power_id)
			return true

	return false

func clone() -> CommandQueue:
	var copy: CommandQueue = (get_script() as GDScript).new() as CommandQueue
	for cmd: CommandScript in _pending:
		copy._pending.push_back(cmd.clone())
	return copy
