class_name TestCredit extends RefCounted

## WP-13 验收：信贷溢价 1.1 + 0.5u²、借满总还款 1.6 倍、签约预览与实际结算一致、40% 收入抵扣、信用升阶
## 依据《02_系统架构与数值_v6.md》§5.2、Q26、Q35

const SimStateScript = preload("res://simulation/SimState.gd")
const SimRunnerScript = preload("res://simulation/SimRunner.gd")
const WalletScript = preload("res://simulation/economy/Wallet.gd")
const CommandScript = preload("res://simulation/commands/Command.gd")
const BalanceScript = preload("res://simulation/Balance.gd")
const NumScript = preload("res://core/num/Num.gd")

const EPS: float = 1e-9

static func run() -> bool:
	print("[TestCredit] 开始测试 WP-13 信贷溢价、预览一致性、40% 抵扣与信用升阶...")
	if not _test_full_limit_is_1_6x_and_premium_curve():
		return false
	if not _test_preview_matches_settlement():
		return false
	if not _test_limits_and_single_loan():
		return false
	if not _test_income_deduction_and_tier_upgrade():
		return false
	if not _test_commands_borrow_repay():
		return false
	print("[TestCredit] WP-13 全部验收项 100% 通过!")
	return true

static func _test_full_limit_is_1_6x_and_premium_curve() -> bool:
	var bal: BalanceScript = BalanceScript.load_default() as BalanceScript
	var stage: int = 20
	var w: WalletScript = WalletScript.new()
	var limit_log: float = w.credit.get_credit_limit_log(stage, bal)
	var preview: Dictionary = w.credit.preview_borrow(stage, limit_log, bal)
	if absf(float(preview["repayment_mult"]) - 1.6) > EPS or absf(float(preview["utilization"]) - 1.0) > EPS:
		printerr("[TestCredit] 借满额度溢价应为 1.6x, 实际: ", preview["repayment_mult"])
		return false
	if not w.borrow(limit_log, stage, bal):
		printerr("[TestCredit] 借满额度失败")
		return false
	# 总还款额 / 本金 = 1.6：log 域差值 = log10(1.6)
	if absf((w.debt_total - w.gold) - NumScript.from_float(1.6)) > EPS:
		printerr("[TestCredit] 借满后 总还款/本金 != 1.6")
		return false

	# 溢价曲线 1.1 + 0.5u²: u = 0.3 -> 1.145
	var w2: WalletScript = WalletScript.new()
	var p30: Dictionary = w2.credit.preview_borrow(stage, limit_log + NumScript.from_float(0.3), bal)
	if absf(float(p30["repayment_mult"]) - 1.145) > EPS:
		printerr("[TestCredit] u=0.3 溢价应为 1.145x, 实际: ", p30["repayment_mult"])
		return false
	print("[TestCredit] 借满 1.6x / u=0.3 -> 1.145x 验证通过")
	return true

static func _test_preview_matches_settlement() -> bool:
	var bal: BalanceScript = BalanceScript.load_default() as BalanceScript
	var stage: int = 33
	for u: float in [0.1, 0.3, 0.5, 0.8, 1.0]:
		var w: WalletScript = WalletScript.new()
		var limit_log: float = w.credit.get_credit_limit_log(stage, bal)
		var borrow_log: float = limit_log + NumScript.from_float(u)
		var preview: Dictionary = w.credit.preview_borrow(stage, borrow_log, bal)
		if not bool(preview["valid"]):
			printerr("[TestCredit] 预览应有效 u=", u)
			return false
		if not w.borrow(borrow_log, stage, bal):
			printerr("[TestCredit] 实际借款失败 u=", u)
			return false
		if absf(w.debt_total - float(preview["repayment_total_log"])) > EPS:
			printerr("[TestCredit] 预览总还款与实际负债不一致 u=", u)
			return false
		if absf(w.gold - borrow_log) > EPS:
			printerr("[TestCredit] 到账金额与预览借款额不一致 u=", u)
			return false
	# 预计还清时长：借满 = 1.6 × 10 分钟收入 ÷ (40% 收入/分钟) = 40 分钟
	var wf: WalletScript = WalletScript.new()
	var full: Dictionary = wf.credit.preview_borrow(stage, wf.credit.get_credit_limit_log(stage, bal), bal)
	if absf(float(full["est_minutes"]) - 40.0) > 1e-6:
		printerr("[TestCredit] 借满预计还清时长应为 40 分钟, 实际: ", full["est_minutes"])
		return false
	print("[TestCredit] 签约预览与实际结算 100% 一致 (预计还清 ", full["est_minutes"], " 分钟)")
	return true

static func _test_limits_and_single_loan() -> bool:
	var bal: BalanceScript = BalanceScript.load_default() as BalanceScript
	var stage: int = 12
	var w: WalletScript = WalletScript.new()
	var limit_log: float = w.credit.get_credit_limit_log(stage, bal)
	if bool(w.credit.preview_borrow(stage, limit_log + 0.01, bal)["valid"]):
		printerr("[TestCredit] 超额度借款应无效")
		return false
	if bool(w.credit.preview_borrow(stage, NumScript.ZERO, bal)["valid"]):
		printerr("[TestCredit] 0 借款应无效")
		return false
	if not w.borrow(limit_log, stage, bal):
		printerr("[TestCredit] 首笔借款失败")
		return false
	var debt_before: float = w.debt_total
	if w.borrow(limit_log, stage, bal) or w.debt_total != debt_before:
		printerr("[TestCredit] 并发第二笔借款应被拒绝 (单笔并发)")
		return false
	print("[TestCredit] 额度上限与单笔并发限制验证通过")
	return true

static func _test_income_deduction_and_tier_upgrade() -> bool:
	var bal: BalanceScript = BalanceScript.load_default() as BalanceScript
	var stage: int = 25
	var w: WalletScript = WalletScript.new()
	var limit0: float = w.credit.get_credit_limit_log(stage, bal)
	w.borrow(limit0, stage, bal)
	w.spend(w.gold)
	var debt0: float = w.debt_total
	var income_log: float = debt0
	w.add_income(income_log, bal, stage)
	var expected_debt: float = NumScript.sub(debt0, income_log + NumScript.from_float(0.4))
	var expected_gold: float = income_log + NumScript.from_float(0.6)
	if absf(w.debt_total - expected_debt) > 1e-6 or absf(w.gold - expected_gold) > 1e-6:
		printerr("[TestCredit] 40% 收入抵扣不精确: debt=", w.debt_total, " exp=", expected_debt, " gold=", w.gold, " exp=", expected_gold)
		return false
	# 还清：一笔足够大的收入
	w.add_income(w.debt_total + 2.0, bal, stage)
	if w.debt_total != NumScript.ZERO or w.credit.active_loan or w.credit.credit_tier != 1:
		printerr("[TestCredit] 还清后应升阶 tier=1")
		return false
	var lim1: float = w.credit.get_credit_limit_log(stage, bal)
	if absf((lim1 - limit0) - NumScript.from_float(1.5)) > 1e-9:
		printerr("[TestCredit] 升阶后额度应 ×1.5")
		return false
	print("[TestCredit] 40% 抵扣精确、还清升阶、额度 ×1.5 验证通过")
	return true

static func _test_commands_borrow_repay() -> bool:
	var bal: BalanceScript = BalanceScript.load_default() as BalanceScript
	var state: SimStateScript = SimStateScript.new(5150, bal)
	state.stats.atk_interval = 100.0
	var runner: SimRunnerScript = SimRunnerScript.new(state)
	var limit_log: float = state.credit.get_credit_limit_log(state.get_active_stage(), bal)
	runner.enqueue_command(CommandScript.make_borrow(limit_log))
	runner.step()
	if not state.credit.active_loan or state.debt_total == NumScript.ZERO:
		printerr("[TestCredit] Command.BORROW_CREDIT 未生效")
		return false
	# 主动还款：用金币余额偿还全部负债需要 gold >= debt，借满后 gold 不足 -> 仅偿还可用部分
	var debt_before: float = state.debt_total
	runner.enqueue_command(CommandScript.make_repay(state.gold))
	runner.step()
	if state.debt_total >= debt_before:
		printerr("[TestCredit] Command.REPAY_CREDIT 未减少负债")
		return false
	print("[TestCredit] BORROW/REPAY Command 经队列确定性生效")
	return true