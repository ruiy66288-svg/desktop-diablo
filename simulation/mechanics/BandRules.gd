class_name BandRules extends RefCounted

## 每 100 层机制变阵规则 (依据《02_系统架构与数值_v6.md》§7.1 & Q31 与《00_开发执行总纲.md》WP-15)
## 区间编号 band = floor((stage - 1) / 100)；当前区间主题机制满强度，上一区间保留 band_lingering_strength (30%) 余韵
## 与 tools/curve_sim.gd 的 get_band_mechanic_strengths 口径完全一致（Gate-1 已验收）

const BalanceScript = preload("res://simulation/Balance.gd")
const MechanicDefScript = preload("res://simulation/mechanics/MechanicDef.gd")

const SHIELD_DEF_PATH: String = "res://content/mechanics/shield.tres"
const FIXED_BAND_LAST: int = 5   # 前 500 层按固定顺序 (Q31)，之后轮换（原型不实装）

static func get_band_index(stage: int, bal: BalanceScript) -> int:
	var interval: int = maxi(1, bal.band_stage_interval)
	return int(maxi(0, stage - 1) / interval)

## 返回 {机制 Kind(int): 强度(float)}
static func get_strengths(stage: int, bal: BalanceScript) -> Dictionary:
	var strengths: Dictionary = {}
	var band_idx: int = get_band_index(stage, bal)
	if band_idx <= 0 or band_idx > FIXED_BAND_LAST:
		return strengths
	strengths[band_idx] = 1.0
	if band_idx - 1 >= 1:
		strengths[band_idx - 1] = bal.band_lingering_strength
	return strengths

static func get_shield_strength(stage: int, bal: BalanceScript) -> float:
	var strengths: Dictionary = get_strengths(stage, bal)
	return float(strengths.get(int(MechanicDefScript.Kind.SHIELD), 0.0))

static func get_shield_def() -> MechanicDefScript:
	return ResourceLoader.load(SHIELD_DEF_PATH) as MechanicDefScript