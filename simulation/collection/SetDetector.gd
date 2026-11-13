class_name SetDetector extends RefCounted

## 隐藏套装检测器 (依据《02_系统架构与数值_v6.md》§8.1 & §8.4)
## 检测 6 槽装备与深渊威能槽是否激活套装，首次激活永久记录进图鉴

const SetDefScript = preload("res://simulation/collection/SetDef.gd")
const ItemInstanceScript = preload("res://simulation/loot/ItemInstance.gd")
const AffixDefScript = preload("res://simulation/affix/AffixDef.gd")
const CodexScript = preload("res://persistence/Codex.gd")

const SET_PATHS: Array[String] = [
	"res://content/sets/set_thunder_debt.tres",
	"res://content/sets/set_greed_covenant.tres",
	"res://content/sets/set_abyss_execution.tres"
]

static var _cached_sets: Array[SetDefScript] = []

static func get_all_sets() -> Array[SetDefScript]:
	if not _cached_sets.is_empty():
		return _cached_sets
	for path: String in SET_PATHS:
		if ResourceLoader.exists(path):
			var s: SetDefScript = ResourceLoader.load(path) as SetDefScript
			if s != null:
				_cached_sets.push_back(s)
	return _cached_sets

## 收集当前所有激活的词条 ID 列表（包括 6 槽装备词条与深渊威能槽）
static func collect_active_affix_ids(state: RefCounted) -> Array[String]:
	var ids: Array[String] = []
	var eq_var: Variant = state.get("equipped")
	if eq_var is Dictionary:
		var eq_d: Dictionary = eq_var as Dictionary
		for it_var: Variant in eq_d.values():
			if it_var is ItemInstanceScript:
				var it: ItemInstanceScript = it_var as ItemInstanceScript
				for a: Variant in it.affixes:
					if a is AffixDefScript:
						var aid: String = (a as AffixDefScript).id
						if not ids.has(aid):
							ids.push_back(aid)

	var vp_var: Variant = state.get("vault_powers")
	if vp_var is Array:
		for v: Variant in (vp_var as Array):
			var vid: String = String(v)
			if not ids.has(vid):
				ids.push_back(vid)
	return ids

## 检测当前激活的隐藏套装列表
static func detect_active_sets(state: RefCounted, codex: CodexScript = null) -> Array[SetDefScript]:
	var active: Array[SetDefScript] = []
	var affix_ids: Array[String] = collect_active_affix_ids(state)
	for s_def: SetDefScript in get_all_sets():
		var matched: bool = true
		for req: String in s_def.required_affix_ids:
			if not affix_ids.has(req):
				matched = false
				break
		if matched:
			active.push_back(s_def)
			if codex != null:
				codex.unlock_set(s_def.id)
	return active

## 汇总激活套装的属性加成到 totals 字典中
static func apply_set_bonuses(state: RefCounted, totals: Dictionary, codex: CodexScript = null) -> void:
	var active_sets: Array[SetDefScript] = detect_active_sets(state, codex)
	for s_def: SetDefScript in active_sets:
		for k_var: Variant in s_def.bonus_stats.keys():
			var k: String = String(k_var)
			var val: float = float(s_def.bonus_stats[k_var])
			totals[k] = float(totals.get(k, 0.0)) + val
