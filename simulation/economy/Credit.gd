class_name Credit extends RefCounted

## 信贷管理器 (依据《02_系统架构与数值_v6.md》§5.2 & Q26 与《00_开发执行总纲.md》§4.4、WP-06)
## 纯 RefCounted，零 Node 依赖，零硬编码常数

const NumScript = preload("res://core/num/Num.gd")
const BalanceScript = preload("res://simulation/Balance.gd")

const FLOAT_EPS: float = 1e-9

var credit_tier: int = 0
var tier_bonus: int = 0   # 科技树「信用背书」带来的额外等级 (不改变 credit_tier 升阶计数)
var active_loan: bool = false
var borrowed_principal_log: float = NumScript.ZERO

## 计算当前信用等级允许的最大借款额度 limit = I * 10 * 1.5^tier (Log10 域)
func get_credit_limit_log(stage: int, balance: BalanceScript) -> float:
	return balance.get_credit_limit_log(stage, credit_tier + tier_bonus)

## 判定在当前信用状态下该借款金额是否可申请
func can_borrow(stage: int, borrow_log: float, balance: BalanceScript) -> bool:
	if active_loan:
		return false
	var preview: Dictionary = preview_borrow(stage, borrow_log, balance)
	return bool(preview.get("valid", false))

## 签约前预览借款信息：借款额、总还款额、溢价倍率与预计还清所需收入时长
func preview_borrow(stage: int, borrow_log: float, balance: BalanceScript) -> Dictionary:
	if borrow_log == NumScript.ZERO:
		return {"valid": false, "reason": "借款金额必须大于 0"}

	var limit_log: float = get_credit_limit_log(stage, balance)
	if borrow_log > limit_log + FLOAT_EPS:
		return {"valid": false, "reason": "超过当前信用额度"}

	var u: float = clampf(pow(10.0, NumScript.div(borrow_log, limit_log)), 0.0, 1.0)
	var repayment_mult: float = balance.get_credit_repayment_mult(u)
	var repayment_total_log: float = NumScript.mul(borrow_log, NumScript.from_float(repayment_mult))

	var income_min: float = balance.get_expected_income_per_min_log(stage)
	var repay_speed_log: float = NumScript.mul(income_min, NumScript.from_float(balance.repayment_deduction_rate))
	var est_minutes: float = pow(10.0, NumScript.div(repayment_total_log, repay_speed_log))

	return {
		"valid": true,
		"limit_log": limit_log,
		"utilization": u,
		"repayment_mult": repayment_mult,
		"repayment_total_log": repayment_total_log,
		"est_minutes": est_minutes
	}

func clone() -> Credit:
	var copy: Credit = (get_script() as GDScript).new() as Credit
	copy.credit_tier = credit_tier
	copy.tier_bonus = tier_bonus
	copy.active_loan = active_loan
	copy.borrowed_principal_log = borrowed_principal_log
	return copy
