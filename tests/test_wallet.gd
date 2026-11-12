class_name TestWallet extends RefCounted

## WP-06 自动化验收测试套件：净财富压力 Wallet、×3 上限、40% 负债保底、托管隔离与“借款未花前压力绝不上升”
## 依据《00_开发执行总纲.md》§2 E1/E4/E9、§4、§5 WP-06 与《02_系统架构与数值_v6.md》§5.1–§5.2、Q23/Q26/Q35/Q36

const WalletScript = preload("res://simulation/economy/Wallet.gd")
const BalanceScript = preload("res://simulation/Balance.gd")
const SimStateScript = preload("res://simulation/SimState.gd")
const SimRunnerScript = preload("res://simulation/SimRunner.gd")
const CommandScript = preload("res://simulation/commands/Command.gd")
const SpawnerScript = preload("res://simulation/combat/Spawner.gd")
const NumScript = preload("res://core/num/Num.gd")

const FLOAT_TOL: float = 1e-5

static func run() -> bool:
	print("[TestWallet] 开始测试 WP-06 净财富钱包、×3 上限、40% 负债下限与借款防怪变强机制...")

	if not _test_wealth_pressure_bounds_and_escrow_exclusion():
		return false
	if not _test_borrow_never_increases_pressure():
		return false
	if not _test_spending_and_debt_repayment_and_legacy():
		return false

	print("[TestWallet] WP-06 净财富压力与信贷钱包全部验收项 100% 验证通过!")
	return true

## 1. 验证净财富压力分段曲线：0<=W<=I 零修正、W>=9I 严格封顶 ×3、净负债严格封底 40%、toll_escrow 绝不计入 W (E4)
static func _test_wealth_pressure_bounds_and_escrow_exclusion() -> bool:
	var bal: BalanceScript = BalanceScript.load_default() as BalanceScript
	var wallet: WalletScript = WalletScript.new()
	var stage: int = 20
	var income_min_log: float = bal.get_expected_income_per_min_log(stage)

	# 1.1 W = 0 与 W = 0.8 * I: 血量倍率严格为 1.0x (delta = 0)
	if absf(wallet.get_wealth_pressure_hp_delta(stage, bal)) > FLOAT_TOL:
		printerr("[TestWallet] W = 0 时财富压力不为 0!")
		return false
	if absf(wallet.get_wealth_hp_multiplier(stage, bal) - 1.0) > FLOAT_TOL:
		printerr("[TestWallet] W = 0 时血量倍率不为 1.0!")
		return false

	wallet.gold = NumScript.mul(income_min_log, NumScript.from_float(0.8))
	if absf(wallet.get_wealth_pressure_hp_delta(stage, bal)) > FLOAT_TOL:
		printerr("[TestWallet] 0 <= W <= I (0.8I) 时财富压力应为 0!")
		return false

	# 1.2 W = 4 * I: log10(4) * 0.5 = log10(2) -> 血量倍率 2.0x
	wallet.gold = NumScript.mul(income_min_log, NumScript.from_float(4.0))
	var mult_4i: float = wallet.get_wealth_hp_multiplier(stage, bal)
	if absf(mult_4i - 2.0) > 1e-3:
		printerr("[TestWallet] W = 4I 时血量倍率期望 2.0x, 实际: ", mult_4i)
		return false

	# 1.3 W = 9 * I 及极端囤钱 W = 10,000 * I: 普通财富压力严格封顶 ×3.0 (E4)
	wallet.gold = NumScript.mul(income_min_log, NumScript.from_float(9.0))
	var mult_9i: float = wallet.get_wealth_hp_multiplier(stage, bal)
	wallet.gold = NumScript.mul(income_min_log, NumScript.from_float(10000.0))
	var mult_extreme: float = wallet.get_wealth_hp_multiplier(stage, bal)
	if absf(mult_9i - 3.0) > 1e-3 or absf(mult_extreme - 3.0) > 1e-3:
		printerr("[TestWallet] 正净财富压力未严格封顶 ×3.0! 9I=", mult_9i, " 10000I=", mult_extreme)
		return false

	# 1.4 勘误 E4 铁律: 巨额 toll_escrow 绝不计入净财富 W
	wallet.gold = NumScript.ZERO
	wallet.debt_total = NumScript.ZERO
	wallet.toll_escrow = 80.0
	if absf(wallet.get_wealth_pressure_hp_delta(stage, bal)) > FLOAT_TOL:
		printerr("[TestWallet] 违反勘误 E4: toll_escrow 被错误计入净财富 W!")
		return false
	if wallet.format_net_wealth() != "0":
		printerr("[TestWallet] format_net_wealth() 错误包含了 toll_escrow: ", wallet.format_net_wealth())
		return false

	# 1.5 净负债下限: 负债 10 * I 与 100 * I 时，血量倍率严格封底在 0.40x (40%, E4)
	wallet.toll_escrow = NumScript.ZERO
	wallet.debt_total = NumScript.mul(income_min_log, NumScript.from_float(10.0))
	var mult_debt_10i: float = wallet.get_wealth_hp_multiplier(stage, bal)
	wallet.debt_total = NumScript.mul(income_min_log, NumScript.from_float(100.0))
	var mult_debt_100i: float = wallet.get_wealth_hp_multiplier(stage, bal)
	if absf(mult_debt_10i - 0.40) > 1e-3 or absf(mult_debt_100i - 0.40) > 1e-3:
		printerr("[TestWallet] 净负债怪物血量下限未严格封底在 40%! 10I=", mult_debt_10i, " 100I=", mult_debt_100i)
		return false

	print("[TestWallet] 财富压力分段曲线 [0.40x .. 3.00x] 与 toll_escrow 隔离验证通过!")
	return true

## 2. WP-06 核心验收：借款还没花出去时，无论初始余额为 0 还是已囤钱 > I，财富压力绝不上升!
static func _test_borrow_never_increases_pressure() -> bool:
	var bal: BalanceScript = BalanceScript.load_default() as BalanceScript
	var stage: int = 15
	var utilizations: Array[float] = [0.2, 0.5, 1.0]

	# 场景 A: 初始零资产借款 (u = 20%, 50%, 100%)
	for u: float in utilizations:
		var w_zero: WalletScript = WalletScript.new()
		var delta_before: float = w_zero.get_wealth_pressure_hp_delta(stage, bal)
		var limit_log: float = w_zero.credit.get_credit_limit_log(stage, bal)
		var borrow_log: float = NumScript.mul(limit_log, NumScript.from_float(u))

		var preview: Dictionary = w_zero.credit.preview_borrow(stage, borrow_log, bal)
		if u >= 0.999 and absf(float(preview["repayment_mult"]) - 1.60) > FLOAT_TOL:
			printerr("[TestWallet] 借满额度时溢价倍率不为 1.6x!")
			return false

		if not w_zero.borrow(borrow_log, stage, bal):
			printerr("[TestWallet] 借款失败! u=", u)
			return false

		var delta_after: float = w_zero.get_wealth_pressure_hp_delta(stage, bal)
		if delta_after > delta_before or delta_after > 0.0:
			printerr("[TestWallet] 严重违规: 零余额借款未消费时压力上升! u=", u, " delta=", delta_after)
			return false

	# 场景 B: 初始已有正净财富 W = 5 * I (压力 > 0) 时借款未花 -> 因溢价 >= 1.1x, W 下降, 压力绝不上升
	var income_log: float = bal.get_expected_income_per_min_log(stage)
	for u_rich: float in utilizations:
		var w_rich: WalletScript = WalletScript.new()
		w_rich.gold = NumScript.mul(income_log, NumScript.from_float(5.0))
		var rich_before: float = w_rich.get_wealth_pressure_hp_delta(stage, bal)
		var rich_limit: float = w_rich.credit.get_credit_limit_log(stage, bal)
		var rich_borrow: float = NumScript.mul(rich_limit, NumScript.from_float(u_rich))
		if not w_rich.borrow(rich_borrow, stage, bal):
			printerr("[TestWallet] 囤钱状态下借款失败!")
			return false
		var rich_after: float = w_rich.get_wealth_pressure_hp_delta(stage, bal)
		if rich_after > rich_before + FLOAT_TOL:
			printerr("[TestWallet] 严重违规: 囤钱状态下借款未花导致压力上升! before=", rich_before, " after=", rich_after)
			return false

	# 场景 C: 实战 SimState + Command.make_borrow 联动检验怪物实际生成血量不上升
	var state: SimStateScript = SimStateScript.new(202606, bal)
	state.current_stage = stage
	state.farm_stage = stage
	state.run_best = stage
	state.all_time_best = stage
	SpawnerScript.spawn_next(state)
	var mob_hp_before_loan: float = state.mob_max_hp_log

	var runner: SimRunnerScript = SimRunnerScript.new(state)
	var full_limit_log: float = state.credit.get_credit_limit_log(stage, bal)
	state.stats.atk_interval = 10.0
	runner.enqueue_command(CommandScript.make_borrow(full_limit_log))
	runner.step()

	SpawnerScript.spawn_next(state)
	var mob_hp_after_loan_unspent: float = state.mob_max_hp_log
	if mob_hp_after_loan_unspent > mob_hp_before_loan + FLOAT_TOL:
		printerr("[TestWallet] 实战怪物血量在借款未花时错误上涨! before=", mob_hp_before_loan, " after=", mob_hp_after_loan_unspent)
		return false

	print("[TestWallet] 借款未消费压力绝不上升（零余额 + 正财富 + SimState 实战三场景）100% 验证通过!")
	return true

## 3. 验证花钱削弱怪物仅靠余额下降 (E9)、40% 收入自动抵扣升级信用、以及转生宿债时长结算 (Q35)
static func _test_spending_and_debt_repayment_and_legacy() -> bool:
	var bal: BalanceScript = BalanceScript.load_default() as BalanceScript
	var stage: int = 12
	var income_log: float = bal.get_expected_income_per_min_log(stage)

	# 3.1 勘误 E9: 花钱通过降低余额使怪物变弱，与同样目标余额直接赋值的血量修正严格相等（无额外消费 buff）
	var w_spend: WalletScript = WalletScript.new()
	w_spend.gold = NumScript.mul(income_log, NumScript.from_float(9.0))
	var cost_8i: float = NumScript.mul(income_log, NumScript.from_float(8.0))
	if not w_spend.spend(cost_8i):
		printerr("[TestWallet] Wallet.spend 扣款失败!")
		return false
	var delta_after_spend: float = w_spend.get_wealth_pressure_hp_delta(stage, bal)

	var w_ref: WalletScript = WalletScript.new()
	w_ref.gold = w_spend.gold
	var delta_ref: float = w_ref.get_wealth_pressure_hp_delta(stage, bal)
	if absf(delta_after_spend - delta_ref) > FLOAT_TOL or absf(delta_after_spend) > FLOAT_TOL:
		printerr("[TestWallet] 违反勘误 E9: 花钱后压力与纯粹余额公式不一致! spend=", delta_after_spend, " ref=", delta_ref)
		return false

	# 3.2 借款并花光后，收入按 40% 自动还债，还清后信用等级 +1
	var w_loan: WalletScript = WalletScript.new()
	var limit_0: float = w_loan.credit.get_credit_limit_log(stage, bal)
	w_loan.borrow(limit_0, stage, bal)
	var delta_unspent: float = w_loan.get_wealth_pressure_hp_delta(stage, bal)
	w_loan.spend(w_loan.gold)
	var delta_spent: float = w_loan.get_wealth_pressure_hp_delta(stage, bal)
	if delta_spent >= delta_unspent:
		printerr("[TestWallet] 花掉借来的金币后，怪物血量未进一步降低!")
		return false

	# 单笔大额收入结清债务 (40% * 10 * debt >= debt)
	var big_income_log: float = w_loan.debt_total + 1.0
	w_loan.add_income(big_income_log, bal, stage)
	if w_loan.debt_total != NumScript.ZERO or w_loan.credit.active_loan:
		printerr("[TestWallet] 大额收入 40% 抵扣未结清活跃债务!")
		return false
	if w_loan.credit.credit_tier != 1:
		printerr("[TestWallet] 还清借款后信用等级未提升至 1! 实际: ", w_loan.credit.credit_tier)
		return false

	# 3.3 Q35 转生未还债务换算为宿债时长并在新周目继续按 40% 抵扣
	var state_p: SimStateScript = SimStateScript.new(3333, bal)
	state_p.current_stage = 60
	state_p.farm_stage = 60
	state_p.run_best = 60
	state_p.all_time_best = 60
	var p_limit: float = state_p.credit.get_credit_limit_log(60, bal)
	state_p.borrow_credit(p_limit)
	state_p.spend_gold(state_p.gold)
	state_p.perform_soul_prestige()

	# 借满 10 分钟额度 * 1.6x 溢价 = 16.0 分钟宿债时长
	if absf(state_p.legacy_debt_minutes - 16.0) > 1e-2 or state_p.debt_total != NumScript.ZERO:
		printerr("[TestWallet] Q35 转生宿债折算异常! 期望 16.0 分钟, 实际: ", state_p.legacy_debt_minutes)
		return false

	# 新周目在第 1 层获得 10 分钟期望收入 -> 40% 抵扣 4.0 分钟宿债，剩余 12.0 分钟
	var stage1_10m_income: float = NumScript.mul(bal.get_expected_income_per_min_log(1), NumScript.from_float(10.0))
	state_p.add_income(stage1_10m_income)
	if absf(state_p.legacy_debt_minutes - 12.0) > 1e-2:
		printerr("[TestWallet] 新周目宿债 40% 抵扣时长不准确! 期望剩余 12.0 分钟, 实际: ", state_p.legacy_debt_minutes)
		return false

	print("[TestWallet] E9 花钱减压、40% 收入还债升阶与 Q35 跨周目宿债抵扣验证通过!")
	return true
