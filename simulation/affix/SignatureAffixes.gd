class_name SignatureAffixes extends RefCounted

## 12 条特效 / 构筑词条加载器 (依据《02_系统架构与数值_v6.md》§2.4、§6.2 与《00_开发执行总纲.md》§4.5)
## 所有数值常数统一存放于 res://content/affixes/*.tres（每个常数旁注明来源章节），代码零硬编码
## 注：「落地即爆」沿用既有 id `drop_explosion`（表现层 shader 为 ground_slam），避免破坏存档与 UI 引用

const AffixDefScript = preload("res://simulation/affix/AffixDef.gd")

const AFFIX_IDS: Array[String] = [
	"chain_lightning", "drop_explosion", "killing_frenzy",
	"executioner_hammer", "gold_storm", "meteor_shower", "doomsday_fountain",
	"crit_afterglow", "unique_rain", "multi_strike", "deadly_precision", "usurer_ward"
]
const AFFIX_DIR: String = "res://content/affixes/"

static func get_by_id(affix_id: String) -> AffixDefScript:
	if not AFFIX_IDS.has(affix_id):
		return null
	return ResourceLoader.load(AFFIX_DIR + affix_id + ".tres", "", ResourceLoader.CACHE_MODE_REUSE) as AffixDefScript

static func create_chain_lightning() -> AffixDefScript:
	return get_by_id("chain_lightning")

static func create_drop_explosion() -> AffixDefScript:
	return get_by_id("drop_explosion")

static func create_killing_frenzy() -> AffixDefScript:
	return get_by_id("killing_frenzy")

static func create_all() -> Array[AffixDefScript]:
	var all_affixes: Array[AffixDefScript] = []
	for affix_id: String in AFFIX_IDS:
		all_affixes.push_back(get_by_id(affix_id))
	return all_affixes