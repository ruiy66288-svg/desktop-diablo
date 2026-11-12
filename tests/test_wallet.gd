class_name TestWallet extends RefCounted

const WalletScript = preload("res://simulation/economy/Wallet.gd")
const BalanceScript = preload("res://simulation/Balance.gd")
const NumScript = preload("res://core/num/Num.gd")

static func run() -> bool:
	print("[TestWallet] 开始测试 WP-06 净财富钱包与借款防怪变强机制...")

	var bal: BalanceScript = BalanceScript.load_default()
	var wallet: WalletScript = WalletScript.new()
	var stage: int = 10

	# 1. 初始状态: 零金币零负债，财富压力修正严格为 0
	var delta_0: float = wallet.get_wealth_pressure_hp_delta(stage, bal)
	if absf(delta_0) > 1e-6:
		printerr("[TestWallet] 初始财富压力不为 0: ", delta_0)
		return false

	# 2. 借款核心铁律验收: 借款到账但未花出去时，怪物血量绝不能上升!
	var limit_log: float = wallet.credit.get_credit_limit_log(stage, bal)
	var borrowed: bool = wallet.borrow(limit_log, stage, bal)
	if not borrowed:
		printerr("[TestWallet] 借款失败!")
		return false

	var delta_after_borrow: float = wallet.get_wealth_pressure_hp_delta(stage, bal)
	if delta_after_borrow > 0.0:
		printerr("[TestWallet] 漏洞复现: 借款未花前居然导致怪变强! delta = ", delta_after_borrow)
		return false

	print("[TestWallet] 借款未花前压力判定正常 (delta <= 0): ", delta_after_borrow)

	# 3. 消费花钱后: 金币归零但负债留存，怪物血量应进一步降低
	wallet.gold = NumScript.ZERO
	var delta_spent: float = wallet.get_wealth_pressure_hp_delta(stage, bal)
	if delta_spent >= delta_after_borrow:
		printerr("[TestWallet] 消费花光金币后怪物未进一步削弱!")
		return false
	print("[TestWallet] 花光借款后怪物血量进一步被削弱: ", delta_spent)

	# 4. 还款与信用升级
	var initial_tier: int = wallet.credit.credit_tier
	wallet.add_income(wallet.debt_total + 1.0, bal, stage)
	if wallet.debt_total != NumScript.ZERO:
		printerr("[TestWallet] 债务未彻底还清!")
		return false
	if wallet.credit.credit_tier != initial_tier + 1:
		printerr("[TestWallet] 还清债务后信用等级未升级!")
		return false

	print("[TestWallet] WP-06 净财富压力与信贷钱包 100% 验证通过!")
	return true
