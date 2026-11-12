class_name StatSheet extends RefCounted

## 《桌面破坏神》角色实时属性面板 (依据《02_系统架构与数值_v6.md》§1.2 单次伤害对数双轨模型)
## 纯 RefCounted，零 Node 依赖，零硬编码常数

const NumScript = preload("res://core/num/Num.gd")
const SimRngScript = preload("res://core/rng/SimRng.gd")
const BalanceScript = preload("res://simulation/Balance.gd")

# 1. 基础区 (指数叠加): log10(B_gold + sum(F_i))
var base_gold_atk_log: float = 2.0
var gear_flat_atk_log: float = NumScript.ZERO

# 2. 加法区 (线性百分比，自带稀释): log10(1 + P)
var additive_percent: float = 0.0

# 3. 暗金与威能独立乘区 (log10 域直接相加): sum(log10(1 + m_j))
var unique_mults_sum_log: float = 0.0

# 4. 灵魂乘区与深渊乘区 (log10 域)
var soul_mult_log: float = 0.0
var abyss_mult_log: float = 0.0

# 5. 有界战斗与掉落副属性 (严禁放入 log 域, §1.1 & §4.4)
var atk_interval: float = 0.50
var crit_rate: float = 0.05
var crit_rate_cap: float = 0.75
var crit_mult: float = 1.50
var magic_find: float = 0.0
var drop_qty_bonus: float = 0.0

func _init(p_balance: BalanceScript = null) -> void:
	var bal: BalanceScript = p_balance if p_balance != null else BalanceScript.load_default()
	sync_from_balance(bal)

## 从 Balance 同步初始基础属性
func sync_from_balance(balance: BalanceScript) -> void:
	base_gold_atk_log = balance.b0_atk_log
	atk_interval = balance.base_atk_interval
	crit_rate = balance.base_crit_rate
	crit_rate_cap = balance.crit_rate_cap
	crit_mult = balance.base_crit_mult

## 获取受上限约束的有效暴击率
func get_effective_crit_rate() -> float:
	return clampf(crit_rate, 0.0, crit_rate_cap)

## 计算单次普通命中（未暴击）伤害 d_hit (Log10 域, §1.2)
func get_base_hit_damage_log() -> float:
	var base_atk: float = NumScript.add(base_gold_atk_log, gear_flat_atk_log)
	var add_log: float = NumScript.from_float(1.0 + maxf(0.0, additive_percent))
	return base_atk + add_log + unique_mults_sum_log + soul_mult_log + abyss_mult_log

## 计算期望每秒伤害 DPS (Log10 域，供重试判定与模拟评估读取)
func get_expected_dps_log(min_interval: float) -> float:
	var base_hit: float = get_base_hit_damage_log()
	var eff_crit: float = get_effective_crit_rate()
	var avg_crit_factor: float = 1.0 + eff_crit * maxf(0.0, crit_mult - 1.0)
	var eff_interval: float = maxf(min_interval, atk_interval)
	return base_hit + NumScript.from_float(avg_crit_factor) - NumScript.from_float(eff_interval)

## 使用战斗随机流判定单次攻击暴击与最终伤害 (Log10 域)
func roll_hit(rng_source: RefCounted) -> Dictionary:
	var eff_crit: float = get_effective_crit_rate()
	var is_crit: bool = false
	if rng_source is SimRngScript:
		is_crit = (rng_source as SimRngScript).combat.roll_chance(eff_crit)
	elif rng_source is SimRngScript.RngStream:
		is_crit = (rng_source as SimRngScript.RngStream).roll_chance(eff_crit)

	var dmg_log: float = get_base_hit_damage_log()
	if is_crit:
		dmg_log += NumScript.from_float(crit_mult)

	return {
		"is_crit": is_crit,
		"damage_log": dmg_log
	}

func clone() -> StatSheet:
	var copy: StatSheet = (get_script() as GDScript).new() as StatSheet
	copy.base_gold_atk_log = base_gold_atk_log
	copy.gear_flat_atk_log = gear_flat_atk_log
	copy.additive_percent = additive_percent
	copy.unique_mults_sum_log = unique_mults_sum_log
	copy.soul_mult_log = soul_mult_log
	copy.abyss_mult_log = abyss_mult_log
	copy.atk_interval = atk_interval
	copy.crit_rate = crit_rate
	copy.crit_rate_cap = crit_rate_cap
	copy.crit_mult = crit_mult
	copy.magic_find = magic_find
	copy.drop_qty_bonus = drop_qty_bonus
	return copy
