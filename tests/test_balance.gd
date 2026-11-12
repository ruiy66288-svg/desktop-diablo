class_name TestBalance extends RefCounted

const BalanceScript = preload("res://simulation/Balance.gd")
const NumScript = preload("res://core/num/Num.gd")

static func run() -> bool:
	print("[TestBalance] 开始测试 WP-02 Balance 全局常数与资源加载...")

	# 0. 验证 res://content/balance.tres 真实加载成功且每项配置均有来源章节注释
	var loaded_res: Resource = ResourceLoader.load("res://content/balance.tres")
	if loaded_res == null or not (loaded_res is BalanceScript):
		printerr("[TestBalance] 无法加载 res://content/balance.tres 或类型非 Balance!")
		return false

	var bal: BalanceScript = loaded_res as BalanceScript

	var tres_file: FileAccess = FileAccess.open("res://content/balance.tres", FileAccess.READ)
	if tres_file == null:
		printerr("[TestBalance] 无法读取 res://content/balance.tres 文本!")
		return false
	var tres_text: String = tres_file.get_as_text()
	tres_file.close()

	var in_resource_body: bool = false
	var annotated_prop_count: int = 0
	for raw_line: String in tres_text.split("\n"):
		var line: String = raw_line.strip_edges()
		if line == "[resource]":
			in_resource_body = true
			continue
		if not in_resource_body or line.is_empty() or line.begins_with(";") or line.begins_with("script ="):
			continue
		if not line.contains("; 来源:"):
			printerr("[TestBalance] balance.tres 存在缺少来源章节注释的常数行: ", line)
			return false
		annotated_prop_count += 1

	if annotated_prop_count < 60:
		printerr("[TestBalance] balance.tres 录入常数数量不足 (§1.2-1.7, §5, §7): ", annotated_prop_count)
		return false

	# 1. 验证第 1 层与第 25 层怪物血量二次增长 (§1.3)
	var hp_25: float = bal.get_monster_hp_log(25)
	if absf(hp_25 - 7.4885) > 0.01:
		printerr("[TestBalance] 第 25 层怪物血量计算错误: ", hp_25)
		return false

	# 2. 验证 Boss 血量为小怪 10 倍 (+1.0 log)
	var boss_hp_25: float = bal.get_boss_hp_log(25)
	if absf(boss_hp_25 - (hp_25 + 1.0)) > 1e-6:
		printerr("[TestBalance] Boss 血量倍率错误!")
		return false

	# 3. 验证借贷溢价公式 Q26: 1.1 + 0.5 * u^2
	if absf(bal.get_credit_repayment_mult(0.0) - 1.1) > 1e-6:
		printerr("[TestBalance] 零额度借贷溢价错误!")
		return false
	if absf(bal.get_credit_repayment_mult(1.0) - 1.6) > 1e-6:
		printerr("[TestBalance] 满额度借贷溢价错误!")
		return false
	if absf(bal.get_credit_repayment_mult(0.5) - 1.225) > 1e-6:
		printerr("[TestBalance] 半额度借贷溢价错误!")
		return false

	# 4. 验证财富压力边界 Q23 & 勘误 E4
	var extreme_wealth_delta: float = bal.get_wealth_pressure_hp_delta(false, 1000.0)
	if absf(extreme_wealth_delta - bal.max_wealth_hp_mult_log) > 1e-6:
		printerr("[TestBalance] 囤钱财富压力上限封顶失效: ", extreme_wealth_delta)
		return false

	var nine_min_delta: float = bal.get_wealth_pressure_hp_delta(false, 9.0)
	if absf(nine_min_delta - bal.max_wealth_hp_mult_log) > 1e-5:
		printerr("[TestBalance] 9 分钟收入财富压力应恰好抵达 ×3 上限: ", nine_min_delta)
		return false

	var extreme_debt_delta: float = bal.get_wealth_pressure_hp_delta(true, 100.0)
	if absf(extreme_debt_delta - bal.min_debt_hp_mult_log) > 1e-6:
		printerr("[TestBalance] 负债削弱怪物血量下限封底失效: ", extreme_debt_delta)
		return false

	# 5. 验证门票价格公式 Q32 (第 100 层门票 = 30 分钟设计期望收入)
	var toll_1: float = bal.get_toll_cost_log(1)
	var income_100: float = bal.get_expected_income_per_min_log(100)
	if absf(toll_1 - (income_100 + NumScript.from_float(30.0))) > 1e-6:
		printerr("[TestBalance] 关卡门票公式错误!")
		return false

	# 6. 验证灵魂、深渊印记、威能槽与 D2 递减 MF 公式 (§1.4, §1.5, §1.7)
	# 6a) 在 BalanceScript.new() 纸面默认常数上验证《02》原始纸面数值
	var paper_bal: BalanceScript = BalanceScript.new()
	if paper_bal.get_pending_souls_log(50, 0) != NumScript.ZERO:
		printerr("[TestBalance] 50 层及以下不应产出灵魂!")
		return false
	if absf(paper_bal.get_pending_souls_log(70, 0) - 1.0) > 1e-6:
		printerr("[TestBalance] 70 层零印记灵魂产出应为 log10=1.0 (10 灵魂)!")
		return false
	if absf(paper_bal.get_effective_soul_k(5) - 0.10) > 1e-6:
		printerr("[TestBalance] 纸面默认下 5 枚印记应使 k 翻倍至 0.10!")
		return false
	if paper_bal.get_pending_marks(99) != 0 or paper_bal.get_pending_marks(100) != 1 or paper_bal.get_pending_marks(400) != 8:
		printerr("[TestBalance] 纸面默认深渊印记产出公式 floor((s/100)^1.5) 计算错误!")
		return false

	# 6b) 在 res://content/balance.tres 实装配置上验证公式关系一致性 (兼容 Gate-1 调参)
	if bal.get_pending_souls_log(bal.soul_start_stage, 0) != NumScript.ZERO:
		printerr("[TestBalance] balance.tres 灵魂起始层及以下不应产出灵魂!")
		return false
	var expected_k5: float = bal.soul_k_coeff * (1.0 + bal.mark_k_amp_per_mark * 5.0)
	if absf(bal.get_effective_soul_k(5) - expected_k5) > 1e-6:
		printerr("[TestBalance] balance.tres 印记放大灵魂指数公式计算错误!")
		return false
	var below_div_stage: int = int(floor(bal.mark_stage_divisor)) - 1
	var at_div_stage: int = int(ceil(bal.mark_stage_divisor))
	var expected_marks_400: int = int(floor(pow(400.0 / bal.mark_stage_divisor, bal.mark_stage_exponent)))
	if bal.get_pending_marks(below_div_stage) != 0 or bal.get_pending_marks(at_div_stage) < 1 or bal.get_pending_marks(400) != expected_marks_400:
		printerr("[TestBalance] balance.tres 深渊印记次线性/幂次公式计算错误!")
		return false
	if bal.get_vault_slot_count(0) != 1 or bal.get_vault_slot_count(10) != 3:
		printerr("[TestBalance] 卡奈威能槽数量公式错误!")
		return false
	if absf(bal.get_effective_mf(250.0) - 125.0) > 1e-6:
		printerr("[TestBalance] D2 递减 MF 公式错误!")
		return false

	print("[TestBalance] WP-02 Balance 数值模型与 ", annotated_prop_count, " 项带注释常数全部验证通过!")
	return true
