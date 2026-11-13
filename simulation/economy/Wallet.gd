class_name Wallet extends RefCounted

## 财务与净财富压力钱包 (依据《02_系统架构与数值_v6.md》§5.1–§5.2 与《00_开发执行总纲.md》§2 E1/E4/E9、WP-06)
## 铁律：
## 1. 全项目唯一货币为 gold（严禁任何第二货币）
## 2. 净财富 W = gold - debt_total，门票托管账户 toll_escrow 绝不计入 W (E4)
## 3. 普通财富压力怪物血量最多 ×3，净负债时怪物血量最低降至 40% (E4)
## 4. 花钱仅通过降低 gold 余额使财富压力自然回落，绝无额外“消费 buff” (E9)
## 5. 借款含溢价 (1.1 + 0.5*u^2 >= 1.1)，故借款到账但尚未消费时 W 严格下降，压力绝不上升

const NumScript = preload("res://core/num/Num.gd")
const CreditScript = preload("res://simulation/economy/Credit.gd")
const BalanceScript = preload("res://simulation/Balance.gd")

const RATIO_LOG_CLAMP: float = 30.0
const MINUTES_LOG_CLAMP: float = 20.0

var gold: float = NumScript.ZERO
var debt_total: float = NumScript.ZERO
var toll_escrow: float = NumScript.ZERO
var legacy_debt_minutes: float = 0.0

var credit: CreditScript

func _init() -> void:
	credit = CreditScript.new()

## 判定当前可用金币余额是否足以支付指定开销
func can_afford(cost_log: float) -> bool:
	if cost_log == NumScript.ZERO:
		return true
	return gold != NumScript.ZERO and gold >= cost_log

## 花费金币（E9：仅扣减 gold 余额，无任何额外消费增益状态）
func spend(cost_log: float) -> bool:
	if cost_log == NumScript.ZERO:
		return true
	if not can_afford(cost_log):
		return false
	gold = NumScript.sub(gold, cost_log)
	return true

## 申请信贷借款 (§5.2 & Q26 浮动溢价 1.1 + 0.5*u^2)
func borrow(borrow_amount_log: float, stage: int, balance: BalanceScript) -> bool:
	if credit.loan_count >= credit.get_max_concurrent_loans(balance):
		return false

	var preview: Dictionary = credit.preview_borrow(stage, borrow_amount_log, balance)
	if not bool(preview.get("valid", false)):
		return false

	var repay_total_log: float = float(preview["repayment_total_log"])
	gold = NumScript.add(gold, borrow_amount_log)
	debt_total = NumScript.add(debt_total, repay_total_log)
	credit.loan_count += 1
	credit.active_loan = true
	credit.borrowed_principal_log = borrow_amount_log
	return true

## 主动使用当前金币余额偿还活跃负债，返回实际偿还的金币量 (Log10 域)
func repay_with_gold(amount_log: float) -> float:
	if amount_log == NumScript.ZERO or gold == NumScript.ZERO or debt_total == NumScript.ZERO:
		return NumScript.ZERO

	var pay_log: float = NumScript.min_num(gold, NumScript.min_num(debt_total, amount_log))
	gold = NumScript.sub(gold, pay_log)
	if pay_log >= debt_total:
		debt_total = NumScript.ZERO
		if credit.active_loan:
			credit.active_loan = false
			credit.loan_count = 0
			credit.credit_tier += 1
	else:
		debt_total = NumScript.sub(debt_total, pay_log)
	return pay_log

## 获得金币收入：先自动扣除 40% 偿还活跃债务或抵扣跨周目宿债，余下入账 gold 或 toll_escrow (§5.2 & §7.3)
func add_income(amount_log: float, balance: BalanceScript, stage: int = 1, save_to_escrow: bool = false) -> void:
	if amount_log == NumScript.ZERO:
		return

	var has_active_debt: bool = debt_total != NumScript.ZERO
	var has_legacy_debt: bool = legacy_debt_minutes > 0.0

	if has_active_debt or has_legacy_debt:
		var deduct_rate: float = balance.repayment_deduction_rate
		var repay_log: float = NumScript.mul(amount_log, NumScript.from_float(deduct_rate))
		var remain_log: float = NumScript.mul(amount_log, NumScript.from_float(maxf(0.0, 1.0 - deduct_rate)))

		if has_active_debt:
			if repay_log >= debt_total:
				debt_total = NumScript.ZERO
				if credit.active_loan:
					credit.active_loan = false
					credit.loan_count = 0
					credit.credit_tier += 1
			else:
				debt_total = NumScript.sub(debt_total, repay_log)
		elif has_legacy_debt:
			var expected_min_log: float = balance.get_expected_income_per_min_log(maxi(1, stage))
			var paid_minutes: float = pow(
				10.0,
				clampf(NumScript.div(repay_log, expected_min_log), -MINUTES_LOG_CLAMP, MINUTES_LOG_CLAMP)
			)
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

## 转生时未还清活跃债务折算出的宿债时长（分钟，Q35：m = debt / I_expected(转生时层数)），无负债返回 0
func get_prestige_legacy_minutes(stage: int, balance: BalanceScript) -> float:
	if debt_total == NumScript.ZERO:
		return 0.0
	var exp_inc_log: float = balance.get_expected_income_per_min_log(maxi(1, stage))
	return pow(10.0, clampf(NumScript.div(debt_total, exp_inc_log), -MINUTES_LOG_CLAMP, MINUTES_LOG_CLAMP))

## 转生时将未还清的活跃债务按当前层期望收入折算为跨周目宿债时长 (Q35)
func settle_prestige_debt_to_legacy(stage: int, balance: BalanceScript) -> float:
	legacy_debt_minutes += get_prestige_legacy_minutes(stage, balance)
	debt_total = NumScript.ZERO
	credit.active_loan = false
	credit.loan_count = 0
	credit.borrowed_principal_log = NumScript.ZERO
	return legacy_debt_minutes

## 获取当前净财富 W = gold - debt_total 信息（勘误 E4：严格排除 toll_escrow）
func get_net_wealth_info(stage: int, balance: BalanceScript) -> Dictionary:
	var expected_income_min: float = balance.get_expected_income_per_min_log(maxi(1, stage))

	if debt_total > gold:
		var net_debt_log: float = NumScript.sub(debt_total, gold)
		var debt_ratio: float = pow(
			10.0,
			clampf(NumScript.div(net_debt_log, expected_income_min), -RATIO_LOG_CLAMP, RATIO_LOG_CLAMP)
		)
		return {
			"is_debt": true,
			"ratio": debt_ratio,
			"signed_ratio": -debt_ratio,
			"net_log": net_debt_log
		}

	var net_gold_log: float = NumScript.sub(gold, debt_total)
	if net_gold_log == NumScript.ZERO:
		return {
			"is_debt": false,
			"ratio": 0.0,
			"signed_ratio": 0.0,
			"net_log": NumScript.ZERO
		}

	var surplus_ratio: float = pow(
		10.0,
		clampf(NumScript.div(net_gold_log, expected_income_min), -RATIO_LOG_CLAMP, RATIO_LOG_CLAMP)
	)
	return {
		"is_debt": false,
		"ratio": surplus_ratio,
		"signed_ratio": surplus_ratio,
		"net_log": net_gold_log
	}

## 计算当前环境下的净财富怪物血量修正 Δh_wealth (Log10 域, 范围 [log10(0.4), log10(3)], E4)
func get_wealth_pressure_hp_delta(stage: int, balance: BalanceScript) -> float:
	var info: Dictionary = get_net_wealth_info(stage, balance)
	var is_debt: bool = bool(info["is_debt"])
	var ratio: float = float(info["ratio"])
	return balance.get_wealth_pressure_hp_delta(is_debt, ratio)

## 计算当前净财富对应的怪物血量线性倍率（普通有界 float，范围 [0.40, 3.00]，供 HUD 直接展示）
func get_wealth_hp_multiplier(stage: int, balance: BalanceScript) -> float:
	var delta_log: float = get_wealth_pressure_hp_delta(stage, balance)
	return pow(10.0, delta_log)

## 格式化带符号的净财富 W = gold - debt_total 文本（严格不含 toll_escrow，供 HUD 展示）
func format_net_wealth() -> String:
	if debt_total > gold:
		var net_debt_log: float = NumScript.sub(debt_total, gold)
		return "-" + NumScript.format_num(net_debt_log)
	var net_gold_log: float = NumScript.sub(gold, debt_total)
	if net_gold_log == NumScript.ZERO:
		return "0"
	return NumScript.format_num(net_gold_log)

func clone() -> Wallet:
	var copy: Wallet = (get_script() as GDScript).new() as Wallet
	copy.gold = gold
	copy.debt_total = debt_total
	copy.toll_escrow = toll_escrow
	copy.legacy_debt_minutes = legacy_debt_minutes
	copy.credit = credit.clone()
	return copy
