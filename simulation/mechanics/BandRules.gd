class_name BandRules extends RefCounted

## 每 100 层机制变阵规则 (依据《02_系统架构与数值_v6.md》§7.1 & Q31 与《00_开发执行总纲.md》WP-15)
## 区间编号 band = floor((stage - 1) / 100)；1–100 层无机制（保证 WP-03 哈希不变）
## 前 500 层（band 1..5）：当前区间主题机制满强度，上一区间保留 band_lingering_strength (30%) 余韵
## 600+ 层（band >= 6）：以 band 为确定性种子，从 5 种机制中抽 2 种不同机制满强度组合
## 与 tools/curve_sim.gd 的 get_band_mechanic_strengths 口径完全一致（Gate-1 已验收）

const BalanceScript = preload("res://simulation/Balance.gd")
const MechanicDefScript = preload("res://simulation/mechanics/MechanicDef.gd")

const MECHANIC_PATHS: Dictionary = {
	1: "res://content/mechanics/shield.tres",
	2: "res://content/mechanics/backlash.tres",
	3: "res://content/mechanics/crit_only.tres",
	4: "res://content/mechanics/split_boss.tres",
	5: "res://content/mechanics/gold_devour.tres"
}
const FIXED_BAND_LAST: int = 5      # 前 500 层按固定顺序 (Q31)
const KIND_COUNT: int = 5           # 机制池大小
const ROTATION_STEP: int = 3        # 双机制轮换的确定性步长（与 curve_sim 一致）

static var _def_cache: Dictionary = {}

static func get_band_index(stage: int, bal: BalanceScript) -> int:
	var interval: int = maxi(1, bal.band_stage_interval)
	return int(maxi(0, stage - 1) / interval)

## 返回 {机制 Kind(int): 强度(float)}
static func get_strengths(stage: int, bal: BalanceScript) -> Dictionary:
	var strengths: Dictionary = {}
	var band_idx: int = get_band_index(stage, bal)
	if band_idx <= 0:
		return strengths
	if band_idx <= FIXED_BAND_LAST:
		strengths[band_idx] = 1.0
		if band_idx - 1 >= 1:
			strengths[band_idx - 1] = bal.band_lingering_strength
		return strengths
	var m1: int = ((band_idx * ROTATION_STEP + 1) % KIND_COUNT) + 1
	var m2: int = ((band_idx * ROTATION_STEP + 3) % KIND_COUNT) + 1
	strengths[m1] = 1.0
	strengths[m2] = 1.0
	return strengths

static func get_shield_strength(stage: int, bal: BalanceScript) -> float:
	var strengths: Dictionary = get_strengths(stage, bal)
	return float(strengths.get(int(MechanicDefScript.Kind.SHIELD), 0.0))

static func get_mechanic_def(kind: int) -> MechanicDefScript:
	if _def_cache.has(kind):
		return _def_cache[kind] as MechanicDefScript
	if not MECHANIC_PATHS.has(kind):
		return null
	var def: MechanicDefScript = ResourceLoader.load(String(MECHANIC_PATHS[kind])) as MechanicDefScript
	_def_cache[kind] = def
	return def

static func get_shield_def() -> MechanicDefScript:
	return get_mechanic_def(int(MechanicDefScript.Kind.SHIELD))

static func get_all_defs() -> Array[MechanicDefScript]:
	var out: Array[MechanicDefScript] = []
	for kind_var: Variant in MECHANIC_PATHS.keys():
		out.push_back(get_mechanic_def(int(kind_var)))
	return out