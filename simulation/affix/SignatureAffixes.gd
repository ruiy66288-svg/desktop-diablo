class_name SignatureAffixes extends RefCounted

## 三大签名特效词条加载器 (依据《02_系统架构与数值_v6.md》§6.2 与《00_开发执行总纲.md》§4.5)
## 所有数值常数统一存放于 res://content/affixes/*.tres（每个常数旁注明来源章节），代码零硬编码

const AffixDefScript = preload("res://simulation/affix/AffixDef.gd")

const CHAIN_LIGHTNING_PATH: String = "res://content/affixes/chain_lightning.tres"
const DROP_EXPLOSION_PATH: String = "res://content/affixes/drop_explosion.tres"
const KILLING_FRENZY_PATH: String = "res://content/affixes/killing_frenzy.tres"

static func _load_affix(path: String) -> AffixDefScript:
	var loaded: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REUSE)
	return loaded as AffixDefScript

static func create_chain_lightning() -> AffixDefScript:
	return _load_affix(CHAIN_LIGHTNING_PATH)

static func create_drop_explosion() -> AffixDefScript:
	return _load_affix(DROP_EXPLOSION_PATH)

static func create_killing_frenzy() -> AffixDefScript:
	return _load_affix(KILLING_FRENZY_PATH)

static func create_all() -> Array[AffixDefScript]:
	var all_affixes: Array[AffixDefScript] = []
	all_affixes.push_back(create_chain_lightning())
	all_affixes.push_back(create_drop_explosion())
	all_affixes.push_back(create_killing_frenzy())
	return all_affixes
