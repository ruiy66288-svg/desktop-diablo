class_name TestLootInventory extends RefCounted

## WP-05 自动化验收测试套件：掉落、D2 递减 MF、首周目保底、过滤（品质 >= X）、自动熔炼、24 格背包淘汰与 Command 队列
## 依据《00_开发执行总纲.md》§2 E1/E10、§4、§5 WP-05 与《02_系统架构与数值_v6.md》Q12、Q13、§1.7、§2.1

const SimStateScript = preload("res://simulation/SimState.gd")
const SimRunnerScript = preload("res://simulation/SimRunner.gd")
const BalanceScript = preload("res://simulation/Balance.gd")
const ItemInstanceScript = preload("res://simulation/loot/ItemInstance.gd")
const SmelterScript = preload("res://simulation/loot/Smelter.gd")
const FilterScript = preload("res://simulation/loot/Filter.gd")
const InventoryScript = preload("res://simulation/loot/Inventory.gd")
const CommandScript = preload("res://simulation/commands/Command.gd")
const EventQueueScript = preload("res://simulation/events/EventQueue.gd")
const SimEventScript = preload("res://simulation/events/SimEvent.gd")
const NumScript = preload("res://core/num/Num.gd")

const FLOAT_TOL: float = 1e-5

static func run() -> bool:
	print("[TestLootInventory] 开始测试 WP-05 掉落、过滤、自动熔炼、24 格背包与 Command 队列...")

	if not _test_filter_and_white_blue_100pct_smelt():
		return false
	if not _test_inventory_24_slots_eviction():
		return false
	if not _test_loot_roller_caps_mf_pity_primal():
		return false
	if not _test_upgrades_and_command_queue_determinism():
		return false

	print("[TestLootInventory] WP-05 全部子项 100% 验证通过!")
	return true

## 1. 验证 Filter（保留品质 >= X）及实战中白装与蓝装 100% 被自动熔炼为 gold（严禁第二货币）
static func _test_filter_and_white_blue_100pct_smelt() -> bool:
	var bal: BalanceScript = BalanceScript.load_default() as BalanceScript
	var state: SimStateScript = SimStateScript.new(12345, bal)
	var filter: FilterScript = FilterScript.new(ItemInstanceScript.Rarity.UNIQUE)

	var white_item: ItemInstanceScript = ItemInstanceScript.new(
		1, "粗制之武器", ItemInstanceScript.Slot.WEAPON, ItemInstanceScript.Rarity.WHITE, 5, 2.5, 0.0, 1.0, bal
	)
	var blue_item: ItemInstanceScript = ItemInstanceScript.new(
		2, "淬火之头盔", ItemInstanceScript.Slot.HELM, ItemInstanceScript.Rarity.BLUE, 5, 2.5, 0.1, 1.0, bal
	)
	var purple_item: ItemInstanceScript = ItemInstanceScript.new(
		3, "铭文之胸甲", ItemInstanceScript.Slot.CHEST, ItemInstanceScript.Rarity.PURPLE, 5, 2.5, 0.3, 1.0, bal
	)
	var unique_item: ItemInstanceScript = ItemInstanceScript.new(
		4, "深渊之手套", ItemInstanceScript.Slot.GLOVES, ItemInstanceScript.Rarity.UNIQUE, 5, 3.0, 0.6, 2.0, bal
	)
	var primal_item: ItemInstanceScript = ItemInstanceScript.new(
		5, "太古之饰品", ItemInstanceScript.Slot.TRINKET, ItemInstanceScript.Rarity.PRIMAL, 10, 4.0, 1.2, 3.6, bal
	)

	# 默认阈值 UNIQUE: 白/蓝/紫均不保留，暗金/太古保留
	if filter.should_keep(white_item) or filter.should_keep(blue_item) or filter.should_keep(purple_item):
		printerr("[TestLootInventory] 默认 UNIQUE 阈值错误保留了低品质装备!")
		return false
	if not filter.should_keep(unique_item) or not filter.should_keep(primal_item):
		printerr("[TestLootInventory] 默认 UNIQUE 阈值未保留暗金/太古装备!")
		return false

	# 动态调整阈值 >= PURPLE: 白/蓝依然 100% 拒绝，紫/暗金/太古保留
	filter.set_threshold(ItemInstanceScript.Rarity.PURPLE)
	if filter.should_keep(white_item) or filter.should_keep(blue_item):
		printerr("[TestLootInventory] PURPLE 阈值下白装或蓝装未被过滤!")
		return false
	if not filter.should_keep(purple_item) or not filter.should_keep(unique_item):
		printerr("[TestLootInventory] PURPLE 阈值未保留紫装/暗金!")
		return false

	# 单件熔炼验证: 白装与蓝装均严格产出 gold 且写入 SMELT 事件
	var eq: EventQueueScript = EventQueueScript.new()
	var gold_0: float = state.gold
	var earned_white: float = SmelterScript.smelt_item(white_item, state, eq)
	var gold_1: float = state.gold
	var earned_blue: float = SmelterScript.smelt_item(blue_item, state, eq)
	if earned_white <= NumScript.ZERO or gold_1 <= gold_0:
		printerr("[TestLootInventory] 白装熔炼未产生 gold 收益!")
		return false
	if earned_blue <= earned_white or state.gold <= gold_1:
		printerr("[TestLootInventory] 蓝装熔炼倍率或 gold 入账异常!")
		return false

	# 连续实战 300 ticks 检验: 掉落的白装和蓝装必须 100% 被熔炼，背包中白蓝数量严格为 0
	var combat_state: SimStateScript = SimStateScript.new(20261113, bal)
	combat_state.filter.set_threshold(ItemInstanceScript.Rarity.PURPLE)
	combat_state.stats.base_gold_atk_log = 4.0
	var combat_eq: EventQueueScript = EventQueueScript.new()
	var total_white_blue_drops: int = 0
	var total_smelt_events: int = 0

	for _k: int in range(200):
		var drops: Array[ItemInstanceScript] = combat_state.loot_roller.roll_loot_for_kill(
			10, false, combat_state, combat_eq
		)
		for it: ItemInstanceScript in drops:
			if int(it.rarity) <= int(ItemInstanceScript.Rarity.BLUE):
				total_white_blue_drops += 1
			if combat_state.filter.should_keep(it):
				combat_state.inventory.add_item(it, combat_state, combat_eq)
			else:
				SmelterScript.smelt_item(it, combat_state, combat_eq)

	while not combat_eq.is_empty():
		var ev: SimEventScript = combat_eq.pop_front()
		if ev != null and ev.type == SimEventScript.T.SMELT:
			total_smelt_events += ev.count

	if total_white_blue_drops <= 0 or total_smelt_events < total_white_blue_drops:
		printerr("[TestLootInventory] 批量掉落中白/蓝装未 100% 触发熔炼事件! drops=", total_white_blue_drops, " smelts=", total_smelt_events)
		return false

	for idx: int in range(combat_state.inventory.get_count()):
		var kept_it: ItemInstanceScript = combat_state.inventory.get_item_at(idx)
		if int(kept_it.rarity) <= int(ItemInstanceScript.Rarity.BLUE):
			printerr("[TestLootInventory] 背包中混入了白装或蓝装! rarity=", int(kept_it.rarity))
			return false

	print("[TestLootInventory] 白装与蓝装 100% 自动熔炼验证通过 (累计熔炼白蓝 ", total_white_blue_drops, " 件)")
	return true

## 2. 验证 24 格固定背包容量：满格时准确熔掉评分最低项（含新物品评分高于最低与低于最低两种分支）
static func _test_inventory_24_slots_eviction() -> bool:
	var bal: BalanceScript = BalanceScript.load_default() as BalanceScript
	var state: SimStateScript = SimStateScript.new(54321, bal)
	var inv: InventoryScript = InventoryScript.new()

	# 填满 24 格 (uid 100..123, iLvl 10..33 -> uid=100, iLvl=10 的评分严格最低)
	for i: int in range(bal.inventory_max_slots):
		var ilvl_val: int = 10 + i
		var it: ItemInstanceScript = ItemInstanceScript.new(
			100 + i,
			"暗金测试_" + str(i),
			ItemInstanceScript.Slot.WEAPON,
			ItemInstanceScript.Rarity.UNIQUE,
			ilvl_val,
			bal.get_equip_flat_atk_log(ilvl_val, 0.8),
			0.5,
			2.0,
			bal
		)
		var added: bool = inv.add_item(it, state)
		if not added:
			printerr("[TestLootInventory] 未满 24 格时入包失败!")
			return false

	if inv.get_count() != 24:
		printerr("[TestLootInventory] 背包容量不等于 24: ", inv.get_count())
		return false

	# 分支 A: 存入更高分太古装备 (uid=999, iLvl=80) -> 应淘汰并熔掉评分最低的 uid=100
	var high_item: ItemInstanceScript = ItemInstanceScript.new(
		999, "太古神兵", ItemInstanceScript.Slot.WEAPON, ItemInstanceScript.Rarity.PRIMAL, 80, 12.0, 1.2, 3.6, bal
	)
	var gold_before_a: float = state.gold
	var eq_a: EventQueueScript = EventQueueScript.new()
	var kept_high: bool = inv.add_item(high_item, state, eq_a)
	if not kept_high or inv.get_count() != 24:
		printerr("[TestLootInventory] 高分装备入包或容量保持 24 失败!")
		return false
	if inv.find_item_by_uid(100) != null:
		printerr("[TestLootInventory] 满包时未淘汰原评分最低的 uid=100!")
		return false
	if inv.find_item_by_uid(999) == null:
		printerr("[TestLootInventory] 高分装备 uid=999 未留在背包中!")
		return false
	if state.gold <= gold_before_a:
		printerr("[TestLootInventory] 被淘汰的最低分旧装备未熔炼成 gold!")
		return false

	# 分支 B: 存入评分低于当前全部 24 件的装备 (uid=50, iLvl=1) -> 应直接熔掉 uid=50，原 24 件不动
	var low_item: ItemInstanceScript = ItemInstanceScript.new(
		50, "低阶暗金", ItemInstanceScript.Slot.BOOTS, ItemInstanceScript.Rarity.UNIQUE, 1, 2.0, 0.4, 1.8, bal
	)
	var gold_before_b: float = state.gold
	var kept_low: bool = inv.add_item(low_item, state, eq_a)
	if kept_low or inv.get_count() != 24 or inv.find_item_by_uid(50) != null:
		printerr("[TestLootInventory] 低分新物品不应挤掉背包内更高分物品!")
		return false
	if state.gold <= gold_before_b:
		printerr("[TestLootInventory] 低分溢出新物品未自动熔炼成 gold!")
		return false

	print("[TestLootInventory] 24 格背包满格淘汰最低分（双向分支）100% 验证通过!")
	return true

## 3. 验证 LootRoller 单次 30 件上限、D2 递减 MF、首周目 140 杀保底及太古属性 (§1.7)
static func _test_loot_roller_caps_mf_pity_primal() -> bool:
	var bal: BalanceScript = BalanceScript.load_default() as BalanceScript

	# 3.1 单次击杀掉落上限 30 件
	var s_cap: SimStateScript = SimStateScript.new(777, bal)
	s_cap.stats.drop_qty_bonus = 100.0
	var cap_drops: Array[ItemInstanceScript] = s_cap.loot_roller.roll_loot_for_kill(20, true, s_cap)
	if cap_drops.size() != bal.drop_max_per_kill or cap_drops.size() != 30:
		printerr("[TestLootInventory] 单次击杀掉落未封顶在 30 件! 实际: ", cap_drops.size())
		return false

	# 3.2 D2 递减 MF 公式 MF * 250 / (MF + 250)
	var eff_250: float = bal.get_effective_mf(250.0)
	if absf(eff_250 - 125.0) > FLOAT_TOL:
		printerr("[TestLootInventory] D2 递减 MF 计算不准确! MF=250 期望 125, 实际: ", eff_250)
		return false

	# 3.3 首周目 140 次击杀暗金保底 (§1.7)
	var s_pity: SimStateScript = SimStateScript.new(888, bal)
	var got_unique_within_140: bool = false
	for _kill_idx: int in range(bal.unique_pity_kills):
		var kill_drops: Array[ItemInstanceScript] = s_pity.loot_roller.roll_loot_for_kill(5, false, s_pity)
		for d_it: ItemInstanceScript in kill_drops:
			if int(d_it.rarity) >= int(ItemInstanceScript.Rarity.UNIQUE):
				got_unique_within_140 = true
	if not got_unique_within_140 or not s_pity.loot_roller.is_first_run_pity_triggered():
		printerr("[TestLootInventory] 首周目 140 次击杀内未触发暗金保底!")
		return false

	# 3.4 太古绯红检验: 满 roll (phi_max) + iLvl+5 + 额外 1 词条槽
	var s_primal: SimStateScript = SimStateScript.new(314159, bal)
	s_primal.stats.magic_find = 5000.0
	s_primal.stats.drop_qty_bonus = 20.0
	var found_primal: ItemInstanceScript = null
	for _try_idx: int in range(400):
		var p_drops: Array[ItemInstanceScript] = s_primal.loot_roller.roll_loot_for_kill(30, true, s_primal)
		for p_it: ItemInstanceScript in p_drops:
			if p_it.rarity == ItemInstanceScript.Rarity.PRIMAL:
				found_primal = p_it
				break
		if found_primal != null:
			break
	if found_primal == null:
		printerr("[TestLootInventory] 高 MF 采样未生成太古装备供检验!")
		return false
	var expected_ilvl: int = 30 + bal.primal_bonus_ilvl
	var expected_atk_log: float = bal.get_equip_flat_atk_log(expected_ilvl, bal.eq_phi_max)
	if found_primal.ilvl != expected_ilvl or absf(found_primal.flat_atk_log - expected_atk_log) > FLOAT_TOL:
		printerr("[TestLootInventory] 太古装备未满足 iLvl+5 或满 roll!")
		return false
	if found_primal.bonus_affix_slots != bal.primal_extra_affixes:
		printerr("[TestLootInventory] 太古装备未携带额外 1 词条标记!")
		return false

	print("[TestLootInventory] LootRoller 30 件上限、D2 MF、140 杀保底与太古满 roll 验证通过!")
	return true

## 4. 验证 Upgrades 与 CommandQueue 在 SimRunner.step() 中的确定性执行（含 Q12 手动拾取 +10% 金币）
static func _test_upgrades_and_command_queue_determinism() -> bool:
	var bal: BalanceScript = BalanceScript.load_default() as BalanceScript

	# 4.1 手动拾取 +10% 金币 (Q12)
	var s_cmd: SimStateScript = SimStateScript.new(9001, bal)
	var runner_cmd: SimRunnerScript = SimRunnerScript.new(s_cmd)
	var stage_check: int = 10
	var expected_bonus_log: float = NumScript.mul(
		SmelterScript.get_smelt_gold_log(stage_check, 0, bal),
		NumScript.from_float(bal.manual_pickup_bonus_rate)
	)
	runner_cmd.enqueue_command(CommandScript.make_manual_pickup(stage_check, 0))
	# 为避免战斗击杀金币混入对比，暂时拉长攻击间隔让本 tick 仅结算 Command
	s_cmd.stats.atk_interval = 10.0
	runner_cmd.step()
	if not NumScript.eq(s_cmd.gold, expected_bonus_log, 1e-6):
		printerr("[TestLootInventory] MANUAL_PICKUP 指令奖励不等于 +10% 基准金币! 实际=", s_cmd.gold, " 期望=", expected_bonus_log)
		return false

	# 4.2 购买攻击升级、过滤阈值切换、换装与手动熔炼全走 CommandQueue
	s_cmd.gold = 8.0
	var weapon_a: ItemInstanceScript = ItemInstanceScript.new(
		501, "测试长剑A", ItemInstanceScript.Slot.WEAPON, ItemInstanceScript.Rarity.UNIQUE, 12, 4.2, 0.5, 2.0, bal
	)
	var weapon_b: ItemInstanceScript = ItemInstanceScript.new(
		502, "测试重剑B", ItemInstanceScript.Slot.WEAPON, ItemInstanceScript.Rarity.UNIQUE, 20, 5.5, 0.7, 2.5, bal
	)
	s_cmd.inventory.add_item(weapon_a, s_cmd)
	s_cmd.inventory.add_item(weapon_b, s_cmd)

	runner_cmd.enqueue_command(CommandScript.make_buy_atk(3))
	runner_cmd.enqueue_command(CommandScript.make_set_filter(ItemInstanceScript.Rarity.PURPLE))
	runner_cmd.enqueue_command(CommandScript.make_equip_uid(501))
	runner_cmd.enqueue_command(CommandScript.make_equip_uid(502))
	runner_cmd.enqueue_command(CommandScript.make_smelt_uid(501))
	runner_cmd.step()

	if s_cmd.upgrades.atk_level != 3:
		printerr("[TestLootInventory] Command BUY_ATK_UPGRADE 未升至 3 级! 实际: ", s_cmd.upgrades.atk_level)
		return false
	if s_cmd.filter.get_threshold() != int(ItemInstanceScript.Rarity.PURPLE):
		printerr("[TestLootInventory] Command SET_FILTER_THRESHOLD 未生效!")
		return false
	var cur_weapon: ItemInstanceScript = s_cmd.equipped["weapon"] as ItemInstanceScript
	if cur_weapon == null or cur_weapon.uid != 502:
		printerr("[TestLootInventory] Command EQUIP_ITEM 换装未生效!")
		return false
	if s_cmd.inventory.find_item_by_uid(501) != null:
		printerr("[TestLootInventory] Command SMELT_ITEM 未将替换回背包的旧武器熔炼!")
		return false

	# 4.3 双实例同种子 + 同帧注入相同 Command 序列 -> 状态哈希 100% 一致
	var sa: SimStateScript = SimStateScript.new(424242, bal)
	var sb: SimStateScript = SimStateScript.new(424242, bal)
	sa.gold = 6.0
	sb.gold = 6.0
	var ra: SimRunnerScript = SimRunnerScript.new(sa)
	var rb: SimRunnerScript = SimRunnerScript.new(sb)

	for t: int in range(200):
		if t == 10:
			ra.enqueue_command(CommandScript.make_buy_atk(2))
			rb.enqueue_command(CommandScript.make_buy_atk(2))
		elif t == 50:
			ra.enqueue_command(CommandScript.make_manual_pickup(5, 1))
			rb.enqueue_command(CommandScript.make_manual_pickup(5, 1))
		elif t == 100:
			ra.enqueue_command(CommandScript.make_set_filter(ItemInstanceScript.Rarity.PURPLE))
			rb.enqueue_command(CommandScript.make_set_filter(ItemInstanceScript.Rarity.PURPLE))
		ra.step()
		rb.step()

	if sa.compute_state_hash() != sb.compute_state_hash():
		printerr("[TestLootInventory] 同种子同 Command 序列推演后状态哈希不一致!")
		return false

	print("[TestLootInventory] Upgrades 与 CommandQueue 确定性闭环 100% 验证通过!")
	return true
