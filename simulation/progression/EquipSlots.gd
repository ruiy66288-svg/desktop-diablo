class_name EquipSlots extends RefCounted

## 六槽位装备管理器 (依据《02_系统架构与数值_v6.md》§1.2 &《00_开发执行总纲.md》§2 E10)
## 6 槽位: weapon / helm / chest / gloves / boots / trinket

const ItemInstanceScript = preload("res://simulation/loot/ItemInstance.gd")
const AffixDefScript = preload("res://simulation/affix/AffixDef.gd")
const AffixResolverScript = preload("res://simulation/events/AffixResolver.gd")
const BalanceScript = preload("res://simulation/Balance.gd")
const StatSheetScript = preload("res://simulation/StatSheet.gd")
const NumScript = preload("res://core/num/Num.gd")

const SLOT_KEYS: Array[String] = [
	"weapon",
	"helm",
	"chest",
	"gloves",
	"boots",
	"trinket"
]

var equipped: Dictionary = {}

func _init() -> void:
	equipped = {}

func equip(item: ItemInstanceScript, state: RefCounted = null) -> ItemInstanceScript:
	if item == null:
		return null

	var slot_val: int = int(item.slot)
	var prev: ItemInstanceScript = equipped.get(slot_val, null) as ItemInstanceScript
	equipped[slot_val] = item

	if state != null:
		var state_eq_var: Variant = state.get("equipped")
		if state_eq_var is Dictionary:
			var slot_str: String = ItemInstanceScript.get_slot_key(item.slot)
			(state_eq_var as Dictionary)[slot_str] = item
		recalculate_and_apply(state)

	return prev

func unequip(slot_val: int, state: RefCounted = null) -> ItemInstanceScript:
	if not equipped.has(slot_val):
		return null

	var item: ItemInstanceScript = equipped[slot_val] as ItemInstanceScript
	equipped.erase(slot_val)

	if state != null:
		recalculate_and_apply(state)

	return item

func get_item(slot_val: int) -> ItemInstanceScript:
	return equipped.get(slot_val, null) as ItemInstanceScript

func get_all_equipped() -> Array[ItemInstanceScript]:
	var list: Array[ItemInstanceScript] = []
	for v: Variant in equipped.values():
		var it: ItemInstanceScript = v as ItemInstanceScript
		if it != null:
			list.push_back(it)
	return list

func recalculate_and_apply(state: RefCounted) -> void:
	if state == null:
		return

	var bal: BalanceScript = state.get("balance") as BalanceScript
	var stats: StatSheetScript = state.get("stats") as StatSheetScript

	var total_gear_atk_log: float = NumScript.ZERO
	var total_add_pct: float = 0.0
	var total_unique_log: float = 0.0

	stats.crit_rate = bal.base_crit_rate
	stats.crit_mult = bal.base_crit_mult

	for v: Variant in equipped.values():
		var it: ItemInstanceScript = v as ItemInstanceScript
		if it == null:
			continue
		if it.flat_atk_log != NumScript.ZERO:
			total_gear_atk_log = NumScript.add(total_gear_atk_log, it.flat_atk_log)
		total_add_pct += it.additive_pct
		if it.unique_mult > 1.0:
			total_unique_log += NumScript.from_float(it.unique_mult)

		for af_var: Variant in it.affixes:
			if af_var is AffixDefScript:
				var af: AffixDefScript = af_var as AffixDefScript
				if af.is_passive:
					match af.stat_key:
						"additive_percent":
							total_add_pct += af.stat_val
						"crit_rate":
							stats.crit_rate += af.stat_val
						"crit_mult":
							stats.crit_mult += af.stat_val

	stats.gear_flat_atk_log = total_gear_atk_log
	stats.additive_percent = total_add_pct
	stats.unique_mults_sum_log = total_unique_log

	var resolver_obj: Variant = state.get("resolver")
	if resolver_obj is AffixResolverScript:
		var resolver: AffixResolverScript = resolver_obj as AffixResolverScript
		resolver.clear_listeners()
		for slot_key_var: Variant in equipped.keys():
			var s_idx: int = int(slot_key_var)
			var it_ref: ItemInstanceScript = equipped[s_idx] as ItemInstanceScript
			for af_idx in range(it_ref.affixes.size()):
				var af_entry: Variant = it_ref.affixes[af_idx]
				if af_entry is AffixDefScript:
					var r_af: AffixDefScript = af_entry as AffixDefScript
					if not r_af.is_passive:
						resolver.register_listener(r_af, s_idx, af_idx)
