class_name TestLootInventory extends RefCounted

const SimStateScript = preload("res://simulation/SimState.gd")
const ItemInstanceScript = preload("res://simulation/loot/ItemInstance.gd")
const SmelterScript = preload("res://simulation/loot/Smelter.gd")
const FilterScript = preload("res://simulation/loot/Filter.gd")
const InventoryScript = preload("res://simulation/loot/Inventory.gd")
const NumScript = preload("res://core/num/Num.gd")

static func run() -> bool:
	print("[TestLootInventory] 开始测试 WP-05 掉落、过滤、熔炼与 24 格背包...")

	var state: SimStateScript = SimStateScript.new(12345)
	var filter: FilterScript = FilterScript.new(ItemInstanceScript.Rarity.UNIQUE)

	# 1. 过滤测试: 白装与蓝装必须被判定为不可保留 (false)
	var white_item: ItemInstanceScript = ItemInstanceScript.new(1, "粗制之武器", ItemInstanceScript.Slot.WEAPON, ItemInstanceScript.Rarity.WHITE, 1, 2.0)
	var blue_item: ItemInstanceScript = ItemInstanceScript.new(2, "淬火之武器", ItemInstanceScript.Slot.WEAPON, ItemInstanceScript.Rarity.BLUE, 1, 2.0)
	var unique_item: ItemInstanceScript = ItemInstanceScript.new(3, "深渊之武器", ItemInstanceScript.Slot.WEAPON, ItemInstanceScript.Rarity.UNIQUE, 1, 3.0)

	if filter.should_keep(white_item):
		printerr("[TestLootInventory] 过滤器错误: 白装不应保留!")
		return false
	if filter.should_keep(blue_item):
		printerr("[TestLootInventory] 过滤器错误: 蓝装不应保留!")
		return false
	if not filter.should_keep(unique_item):
		printerr("[TestLootInventory] 过滤器错误: 暗金应该保留!")
		return false

	# 2. 自动熔炼测试: 白装熔炼后必须产生金币收入
	var gold_before: float = state.gold
	var earned: float = SmelterScript.smelt_item(white_item, state)
	if earned <= NumScript.ZERO or state.gold <= gold_before:
		printerr("[TestLootInventory] 熔炼未产生金币收益!")
		return false
	print("[TestLootInventory] 白装自动熔炼正常, 产出金币: ", NumScript.format_num(earned))

	# 3. 24 格背包满溢自动熔炼最低分测试 (Q13)
	var inv: InventoryScript = InventoryScript.new()
	for i in range(24):
		var it: ItemInstanceScript = ItemInstanceScript.new(100 + i, "暗金测试_" + str(i), ItemInstanceScript.Slot.WEAPON, ItemInstanceScript.Rarity.UNIQUE, i + 1, 3.0)
		inv.add_item(it, state)

	if inv.get_count() != 24:
		printerr("[TestLootInventory] 背包满格数量不为 24: ", inv.get_count())
		return false

	# 尝试存入第 25 件强力太古装备 (ilvl 100, 评分远超第一件)
	var super_item: ItemInstanceScript = ItemInstanceScript.new(999, "太古神器", ItemInstanceScript.Slot.WEAPON, ItemInstanceScript.Rarity.PRIMAL, 100, 10.0)
	var gold_pre_overflow: float = state.gold
	var kept: bool = inv.add_item(super_item, state)

	if not kept:
		printerr("[TestLootInventory] 强力装备未能存入背包!")
		return false
	if inv.get_count() != 24:
		printerr("[TestLootInventory] 满溢后背包格数异常: ", inv.get_count())
		return false
	if inv.get_item_at(23).uid != 999:
		printerr("[TestLootInventory] 强力装备未在背包末尾!")
		return false
	if state.gold <= gold_pre_overflow:
		printerr("[TestLootInventory] 被淘汰的旧装备未执行熔炼返金!")
		return false

	print("[TestLootInventory] 24 格背包满格智能淘汰熔炼 100% 验证通过!")
	return true
