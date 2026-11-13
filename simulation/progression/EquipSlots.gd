class_name EquipSlots extends RefCounted

## 六槽位装备管理器 (依据《02_系统架构与数值_v6.md》§1.2、§1.5 与《00_开发执行总纲.md》§2 E10)
## 6 槽位: weapon / helm / chest / gloves / boots / trinket；深渊永久威能槽 (vault) 与 6 槽并列生效
## recalculate_and_apply：重建反应型词条监听器 + 汇总被动词条属性到 state.passive_totals，随后统一由 SimState.recalculate_stats 落到 StatSheet

const ItemInstanceScript = preload("res://simulation/loot/ItemInstance.gd")
const AffixDefScript = preload("res://simulation/affix/AffixDef.gd")
const SignatureAffixesScript = preload("res://simulation/affix/SignatureAffixes.gd")

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

	var totals: Dictionary = {}
	var resolver_obj: Variant = state.get("resolver")
	var has_resolver: bool = resolver_obj != null
	if has_resolver:
		resolver_obj.call("clear_listeners")

	# 6 槽装备词条
	for slot_key_var: Variant in equipped.keys():
		var s_idx: int = int(slot_key_var)
		var it_ref: ItemInstanceScript = equipped[s_idx] as ItemInstanceScript
		if it_ref == null:
			continue
		for af_idx: int in range(it_ref.affixes.size()):
			var af_entry: Variant = it_ref.affixes[af_idx]
			if af_entry is AffixDefScript:
				_apply_affix(af_entry as AffixDefScript, s_idx, af_idx, totals, resolver_obj)

	# 深渊永久威能槽（与 6 槽并列，槽位编号接在装备槽之后）
	var vault_var: Variant = state.get("vault_powers")
	if vault_var is Array:
		var vault_list: Array = vault_var as Array
		for v_idx: int in range(vault_list.size()):
			var def: AffixDefScript = SignatureAffixesScript.get_by_id(String(vault_list[v_idx]))
			if def != null:
				_apply_affix(def, SLOT_KEYS.size() + v_idx, 0, totals, resolver_obj)

	state.set("passive_totals", totals)
	if state.has_method("recalculate_stats"):
		state.call("recalculate_stats")

func _apply_affix(def: AffixDefScript, slot_idx: int, affix_idx: int, totals: Dictionary, resolver_obj: Variant) -> void:
	if def.is_passive:
		if not def.stat_key.is_empty():
			totals[def.stat_key] = float(totals.get(def.stat_key, 0.0)) + def.stat_val
		for extra_key: Variant in def.extra_stats.keys():
			var k: String = String(extra_key)
			totals[k] = float(totals.get(k, 0.0)) + float(def.extra_stats[extra_key])
	elif resolver_obj != null:
		resolver_obj.call("register_listener", def, slot_idx, affix_idx)