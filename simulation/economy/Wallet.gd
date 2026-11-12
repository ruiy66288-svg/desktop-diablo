class_name Wallet extends RefCounted

## 财务与净财富钱包 (依据《02_系统架构与数值_v6.md》§5.1–§5.2 与《00_开发执行总纲.md》§2 E4)
## 铁律：财富压力统一按净财富 W = gold - debt_total 计算；toll_escrow 绝不计入 W；借款未消费绝不导致怪变强

const NumScript = preload("res://core/num/Num.gd")
const CreditScript = preload("res://simulation/economy/Credit.gd")
const BalanceScript = preload("res://simulation/Balance.gd")

var gold: float = NumScript.ZERO
var debt_total: float = NumScript.ZERO
var toll_escrow: float = NumScript.ZERO
var legacy_debt_minutes: float = 0.0

var credit: CreditScript

func _init() -> void:
	credit = CreditScript.new()

## 申请信贷 (依据 Q26 浮动溢价公式 1.1 + 0.5*u^2)
func borrow(borrow_amount_log: float, stage: int, balance: BalanceScript) -> bool:
	if credit.active_loan:
		return false

	var preview: Dictionary = credit.preview_borrow(stage, borrow_amount_log, balance)
	if not bool(preview.get("valid", false)):
		return false

	var repay_total_log: float = float(preview["repayment_total_log"])
	gold = NumScript.add(gold, borrow_amount_log)
	debt_total = NumScript.add(debt_total, repay_total_log)
	credit.active_loan = true
	credit.borrowed_principal_log = borrow_amount_log
	return true

## 获得收入（自动扣除 40% 还债/抵扣宿债）
func add_income(amount_log: float, balance: BalanceScript, stage: int = 1, save_to_escrow: bool = false) -> void:
	if amount_log == NumScript.ZERO:
		return

	var has_active_debt: bool = debt_total != NumScript.ZERO
	var has_legacy_debt: bool = legacy_debt_minutes > 0.0

	if has_active_debt or has_legacy_debt:
		var deduct_rate: float = balance.repayment_deduction_rate
		var repay_log: float = amount_log + NumScript.from_float(deduct_rate)
		var remain_log: float = amount_log + NumScript.from_float(maxf(0.0, 1.0 - deduct_rate))

		if has_active_debt:
			if repay_log >= debt_total:
				debt_total = NumScript.ZERO
				if credit.active_loan:
					credit.active_loan = false
					credit.credit_tier += 1
			else:
				debt_total = NumScript.sub(debt_total, repay_log)
		elif has_legacy_debt:
			var expected_min_log: float = balance.get_expected_income_per_min_log(stage)
			var paid_minutes: float = pow(10.0, clampf(repay_log - expected_min_log, -20.0, 20.0))
			legacy_debt_minutes = maxf(0.0, legacy_debt_minutes - paid_minutes)

		if save_to_escrow:
			toll_escrow = NumScript.add(toll_escrow, remain_log)
		else:
			gold = NumScript.add(gold, remain_log)
	else:
		if save_to_escrow:
			toll_escrow = NumScript.add(toll_escrow, amount_log)
		else:
			gold = NumScript.add(gold, amount_log)

## 获取当前净财富比值信息（严格排除 toll_escrow, E4）
func get_net_wealth_info(stage: int, balance: BalanceScript) -> Dictionary:
	var expected_income_min: float = balance.get_expected_income_per_min_log(stage)

	if debt_total > gold:
		var net_debt_log: float = NumScript.sub(debt_total, gold)
		var debt_ratio: float = pow(10.0, clampf(net_debt_log - expected_income_min, -30.0, 30.0))
		return {"is_debt": true, "ratio": debt_ratio, "net_log": net_debt_log}

	var net_gold_log: float = NumScript.sub(gold, debt_total)
	if net_gold_log == NumScript.ZERO:
		return {"is_debt": false, "ratio": 0.0, "net_log": NumScript.ZERO}

	var surplus_ratio: float = pow(10.0, clampf(net_gold_log - expected_income_min, -30.0, 30.0))
	return {"is_debt": false, "ratio": surplus_ratio, "net_log": net_gold_log}

## 计算当前环境下的净财富与怪物血量修正 Δh_wealth (Log10 域, E4)
func get_wealth_pressure_hp_delta(stage: int, balance: BalanceScript) -> float:
	var info: Dictionary = get_net_wealth_info(stage, balance)
	var is_debt: bool = bool(info["is_debt"])
	var ratio: float = float(info["ratio"])
	return balance.get_wealth_pressure_hp_delta(is_debt, ratio)

func clone() -> Wallet:
	var copy: Wallet = (get_script() as GDScript).new() as Wallet
	copy.gold = gold
	copy.debt_total = debt_total
	copy.toll_escrow = toll_escrow
	copy.legacy_debt_minutes = legacy_debt_minutes
	copy.credit = credit.clone()
	return copy
