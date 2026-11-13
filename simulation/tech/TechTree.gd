class_name TechTree extends RefCounted

## 科技树 (依据《02_系统架构与数值_v6.md》§5.3、Q27–Q28 与《00_开发执行总纲.md》WP-14)
## 12 个节点（战斗/经济/信贷/自动化 各 3 个；tier>=5 的深层节点需深渊印记解锁, §5.3）；永不随转生重置；节点数据在 res://content/tech/*.tres

const TechNodeDefScript = preload("res://simulation/tech/TechNodeDef.gd")
const BalanceScript = preload("res://simulation/Balance.gd")

const NODE_PATHS: Array[String] = [
	"res://content/tech/combat_edge.tres",
	"res://content/tech/combat_crit.tres",
	"res://content/tech/eco_scavenger.tres",
	"res://content/tech/eco_drops.tres",
	"res://content/tech/credit_line.tres",
	"res://content/tech/auto_upgrade.tres",
	"res://content/tech/combat_mastery.tres",
	"res://content/tech/eco_golden.tres",
	"res://content/tech/credit_dual_loan.tres",
	"res://content/tech/credit_discount.tres",
	"res://content/tech/offline_cap_24h.tres",
	"res://content/tech/auto_repay.tres"
]

var defs: Dictionary = {}
var researched: Array[String] = []
## 调试模式：研究时长按「秒」而非「分钟」计（00 号文件 WP-14）
var debug_seconds_mode: bool = false

func _init() -> void:
	for path: String in NODE_PATHS:
		var def: TechNodeDefScript = ResourceLoader.load(path) as TechNodeDefScript
		if def != null:
			defs[def.id] = def

func get_def(node_id: String) -> TechNodeDefScript:
	return defs.get(node_id, null) as TechNodeDefScript

func get_all_defs() -> Array[TechNodeDefScript]:
	var out: Array[TechNodeDefScript] = []
	for v: Variant in defs.values():
		out.push_back(v as TechNodeDefScript)
	out.sort_custom(func(a: TechNodeDefScript, b: TechNodeDefScript) -> bool:
		if a.tier != b.tier:
			return a.tier < b.tier
		return a.id < b.id)
	return out

func has_researched(node_id: String) -> bool:
	return researched.has(node_id)

func mark_researched(node_id: String) -> void:
	if defs.has(node_id) and not researched.has(node_id):
		researched.push_back(node_id)

func get_effect_total(effect_key: String) -> float:
	var total: float = 0.0
	for node_id: String in researched:
		var def: TechNodeDefScript = get_def(node_id)
		if def != null and def.effect_key == effect_key:
			total += def.effect_val
	return total

func get_research_duration_seconds(def: TechNodeDefScript, bal: BalanceScript) -> int:
	return int(ceil(bal.get_tech_research_seconds(def.tier, debug_seconds_mode)))

func get_signature() -> String:
	var ids: Array[String] = researched.duplicate()
	ids.sort()
	return ",".join(ids)

func clone() -> TechTree:
	var copy: TechTree = (get_script() as GDScript).new() as TechTree
	copy.researched = researched.duplicate()
	copy.debug_seconds_mode = debug_seconds_mode
	return copy