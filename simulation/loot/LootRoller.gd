class_name LootRoller extends RefCounted

## 确定性掉落生成器 (依据《02_系统架构与数值_v6.md》§1.7 与《00_开发执行总纲.md》§2 E10、§4.3)
## 严格且仅使用 SimRng.loot 独立随机流，绝不污染 combat / collection 流；全部常数读取 Balance

const ItemInstanceScript = preload("res://simulation/loot/ItemInstance.gd")
const SimEventScript = preload("res://simulation/events/SimEvent.gd")
const EventQueueScript = preload("res://simulation/events/EventQueue.gd")
const SimRngScript = preload("res://core/rng/SimRng.gd")
const BalanceScript = preload("res://simulation/Balance.gd")
const StatSheetScript = preload("res://simulation/StatSheet.gd")

const SLOT_DISPLAY_NAMES: Array[String] = ["武器", "头盔", "胸甲", "手套", "靴子", "饰品"]
const RARITY_PREFIXES: Array[String] = ["粗制", "淬火", "铭文", "深渊", "太古"]

var _unique_pity_counter: int = 0
var _first_run_pity_triggered: bool = false
var _next_uid: int = 1

func get_pity_counter() -> int:
	return _unique_pity_counter

func is_first_run_pity_triggered() -> bool:
	return _first_run_pity_triggered

## 执行单次击杀掉落判定（仅消费 state.rng.loot）
func roll_loot_for_kill(
	stage: int,
	is_boss: bool,
	state: RefCounted,
	queue: EventQueueScript = null
) -> Array[ItemInstanceScript]:
	_unique_pity_counter += 1
	var drops: Array[ItemInstanceScript] = []

	var bal: BalanceScript = state.get("balance") as BalanceScript
	var stats: StatSheetScript = state.get("stats") as StatSheetScript
	var sim_rng: SimRngScript = state.get("rng") as SimRngScript
	var loot_stream: SimRngScript.RngStream = sim_rng.loot

	# 1. 掉落件数: 1.2 * (1 + drop_qty_bonus)，Boss 为基础固定倍数，单次上限 drop_max_per_kill
	var qty_mult: float = 1.0 + maxf(0.0, stats.drop_qty_bonus)
	var expected_qty: float = float(bal.boss_drop_base_count) * qty_mult if is_boss else bal.drop_base_per_kill * qty_mult
	var base_count: int = int(floor(expected_qty))
	var frac_chance: float = expected_qty - float(base_count)
	if loot_stream.roll_chance(frac_chance):
		base_count += 1
	var drop_count: int = clampi(base_count, 0, bal.drop_max_per_kill)

	# 2. 逐件生成装备
	var prestige_count: int = int(state.get("prestige_count"))
	var eff_mf: float = bal.get_effective_mf(stats.magic_find)

	for _i in range(drop_count):
		var item: ItemInstanceScript = _generate_item(stage, prestige_count, eff_mf, bal, loot_stream)
		drops.push_back(item)
		if queue != null:
			var ev: SimEventScript = SimEventScript.new(SimEventScript.T.DROP, item.flat_atk_log)
			ev.payload = {
				"item_uid": item.uid,
				"rarity": int(item.rarity),
				"slot": ItemInstanceScript.get_slot_key(item.slot)
			}
			queue.push_back(ev)

	return drops

func _generate_item(
	stage: int,
	prestige_count: int,
	eff_mf: float,
	bal: BalanceScript,
	loot_stream: SimRngScript.RngStream
) -> ItemInstanceScript:
	var uid: int = _next_uid
	_next_uid += 1

	var slot_max_idx: int = maxi(0, bal.equip_slot_count - 1)
	var slot_idx: int = loot_stream.randi_range_val(0, slot_max_idx)
	var slot_enum: ItemInstanceScript.Slot = slot_idx as ItemInstanceScript.Slot

	# 品质权重 (MF 按比例放大紫/暗金/太古权重)
	var mf_factor: float = 1.0 + eff_mf * 0.01
	var w_primal: float = bal.rarity_weight_primal * mf_factor
	var w_unique: float = bal.rarity_weight_unique * mf_factor
	var w_purple: float = bal.rarity_weight_purple * mf_factor
	var w_blue: float = bal.rarity_weight_blue
	var w_white: float = bal.rarity_weight_white
	var total_weight: float = w_primal + w_unique + w_purple + w_blue + w_white

	var rarity_enum: ItemInstanceScript.Rarity = ItemInstanceScript.Rarity.WHITE

	# 首周目 140 次击杀暗金保底 (§1.7: 只用于首周目的 75 秒节点)
	if prestige_count == 0 and not _first_run_pity_triggered and _unique_pity_counter >= bal.unique_pity_kills:
		rarity_enum = ItemInstanceScript.Rarity.UNIQUE
		_unique_pity_counter = 0
		_first_run_pity_triggered = true
	else:
		var roll_val: float = loot_stream.randf_range_val(0.0, total_weight)
		if roll_val < w_primal:
			rarity_enum = ItemInstanceScript.Rarity.PRIMAL
			_unique_pity_counter = 0
			_first_run_pity_triggered = true
		elif roll_val < w_primal + w_unique:
			rarity_enum = ItemInstanceScript.Rarity.UNIQUE
			_unique_pity_counter = 0
			_first_run_pity_triggered = true
		elif roll_val < w_primal + w_unique + w_purple:
			rarity_enum = ItemInstanceScript.Rarity.PURPLE
		elif roll_val < w_primal + w_unique + w_purple + w_blue:
			rarity_enum = ItemInstanceScript.Rarity.BLUE
		else:
			rarity_enum = ItemInstanceScript.Rarity.WHITE

	# iLvl 与太古满 roll 规则 (§1.2 & §1.7)
	var ilvl: int = maxi(1, stage)
	var phi: float = bal.eq_phi_max
	if rarity_enum == ItemInstanceScript.Rarity.PRIMAL:
		ilvl += bal.primal_bonus_ilvl
		phi = bal.eq_phi_max
	else:
		phi = loot_stream.randf_range_val(bal.eq_phi_min, bal.eq_phi_max)

	var flat_atk_log: float = bal.get_equip_flat_atk_log(ilvl, phi)
	var additive_pct: float = 0.0
	var unique_mult: float = 1.0

	match rarity_enum:
		ItemInstanceScript.Rarity.BLUE:
			additive_pct = loot_stream.randf_range_val(0.0, bal.gear_additive_pct_blue)
		ItemInstanceScript.Rarity.PURPLE:
			additive_pct = loot_stream.randf_range_val(bal.gear_additive_pct_blue, bal.gear_additive_pct_purple)
		ItemInstanceScript.Rarity.UNIQUE:
			additive_pct = loot_stream.randf_range_val(bal.gear_additive_pct_purple, bal.gear_additive_pct_unique)
			unique_mult = loot_stream.randf_range_val(bal.unique_mult_min, bal.unique_mult_max)
		ItemInstanceScript.Rarity.PRIMAL:
			additive_pct = bal.gear_additive_pct_primal
			unique_mult = bal.unique_mult_max
		_:
			pass

	var item_name: String = _build_item_name(slot_idx, int(rarity_enum))
	return ItemInstanceScript.new(
		uid,
		item_name,
		slot_enum,
		rarity_enum,
		ilvl,
		flat_atk_log,
		additive_pct,
		unique_mult,
		bal
	)

func _build_item_name(slot_idx: int, rarity_idx: int) -> String:
	var s_idx: int = clampi(slot_idx, 0, SLOT_DISPLAY_NAMES.size() - 1)
	var r_idx: int = clampi(rarity_idx, 0, RARITY_PREFIXES.size() - 1)
	return RARITY_PREFIXES[r_idx] + "之" + SLOT_DISPLAY_NAMES[s_idx]

func clone() -> LootRoller:
	var copy: LootRoller = (get_script() as GDScript).new() as LootRoller
	copy._unique_pity_counter = _unique_pity_counter
	copy._first_run_pity_triggered = _first_run_pity_triggered
	copy._next_uid = _next_uid
	return copy
