class_name ItemInstance extends RefCounted

## 装备实例数据结构 (依据《02_系统架构与数值_v6.md》§1.2、§1.7 与《00_开发执行总纲.md》§2 E10)
## 6 槽位严格锁定为 weapon / helm / chest / gloves / boots / trinket

const NumScript = preload("res://core/num/Num.gd")
const BalanceScript = preload("res://simulation/Balance.gd")
const AffixDefScript = preload("res://simulation/affix/AffixDef.gd")

enum Rarity {
	WHITE = 0,   # 白装 (普通)
	BLUE = 1,    # 蓝装 (魔法)
	PURPLE = 2,  # 紫装 (稀有)
	UNIQUE = 3,  # 暗金 (传奇独立乘区)
	PRIMAL = 4   # 太古绯红 (满 roll + iLvl+5 + 额外 1 词条)
}

enum Slot {
	WEAPON = 0,  # weapon: 武器
	HELM = 1,    # helm: 头盔
	CHEST = 2,   # chest: 胸甲
	GLOVES = 3,  # gloves: 手套
	BOOTS = 4,   # boots: 靴子
	TRINKET = 5  # trinket: 饰品
}

const SLOT_KEYS: Array[String] = [
	"weapon",
	"helm",
	"chest",
	"gloves",
	"boots",
	"trinket"
]

var uid: int = 0
var name: String = ""
var slot: Slot = Slot.WEAPON
var rarity: Rarity = Rarity.WHITE
var ilvl: int = 1
var flat_atk_log: float = NumScript.ZERO
var additive_pct: float = 0.0
var unique_mult: float = 1.0
var bonus_affix_slots: int = 0
var affixes: Array = []
var score: float = 0.0

func _init(
	p_uid: int,
	p_name: String,
	p_slot: Slot,
	p_rarity: Rarity,
	p_ilvl: int,
	p_atk_log: float,
	p_additive_pct: float = 0.0,
	p_unique_mult: float = 1.0,
	p_balance: BalanceScript = null
) -> void:
	uid = p_uid
	name = p_name
	slot = p_slot
	rarity = p_rarity
	ilvl = p_ilvl
	flat_atk_log = p_atk_log
	additive_pct = p_additive_pct
	unique_mult = maxf(1.0, p_unique_mult)
	calc_score(p_balance)

static func get_slot_key(p_slot: Slot) -> String:
	var idx: int = clampi(int(p_slot), 0, SLOT_KEYS.size() - 1)
	return SLOT_KEYS[idx]

static func slot_from_key(slot_key: String) -> Slot:
	var idx: int = SLOT_KEYS.find(slot_key)
	if idx < 0:
		return Slot.WEAPON
	return idx as Slot

func get_slot_name_key() -> String:
	return get_slot_key(slot)

## 计算装备综合评分（用于 24 格背包满溢时自动淘汰评分最低项, Q13）
func calc_score(p_balance: BalanceScript = null) -> float:
	var bal: BalanceScript = p_balance if p_balance != null else (BalanceScript.load_default() as BalanceScript)
	var rarity_val: float = float(rarity) * bal.score_rarity_weight
	var ilvl_val: float = float(ilvl) * bal.score_ilvl_weight
	var atk_val: float = flat_atk_log if flat_atk_log != NumScript.ZERO else 0.0
	var mult_val: float = NumScript.from_float(unique_mult) if unique_mult > 1.0 else 0.0
	score = rarity_val + ilvl_val + atk_val + mult_val
	return score

## 本装备词条覆盖的克制标签（去重，供卡墙克制高亮, §7.2）
func get_counter_tags() -> Array[String]:
	var tags: Array[String] = []
	for a: Variant in affixes:
		if a is AffixDefScript:
			for t: String in (a as AffixDefScript).counter_tags:
				if not tags.has(t):
					tags.push_back(t)
	return tags

## 是否克制给定机制标签集合（任一命中即克制）
func counters(counter_tags_needed: Array[String]) -> bool:
	var mine: Array[String] = get_counter_tags()
	for t: String in counter_tags_needed:
		if mine.has(t):
			return true
	return false

func clone() -> ItemInstance:
	var copy: ItemInstance = (get_script() as GDScript).new(
		uid,
		name,
		slot,
		rarity,
		ilvl,
		flat_atk_log,
		additive_pct,
		unique_mult
	) as ItemInstance
	copy.bonus_affix_slots = bonus_affix_slots
	copy.affixes = affixes.duplicate()
	copy.score = score
	return copy
