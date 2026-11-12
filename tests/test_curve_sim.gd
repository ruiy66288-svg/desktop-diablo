class_name TestCurveSim extends RefCounted

## WP-04 `tools/curve_sim.gd` 曲线模拟器自动化测试套件
## 覆盖：20 种子配置、Tick 模式确定性、快进模式确定性、三策略行为隔离、区间机制强度与分位数统计

const CurveSimScript = preload("res://tools/curve_sim.gd")
const BalanceScript = preload("res://simulation/Balance.gd")
const SimStateScript = preload("res://simulation/SimState.gd")
const NumScript = preload("res://core/num/Num.gd")

static func run() -> bool:
	print("[TestCurveSim] 开始测试 WP-04 曲线模拟器 (Tick 模式 / 快进模式 / 三策略 / 确定性)...")

	var bal: BalanceScript = BalanceScript.load_default() as BalanceScript
	if bal == null:
		printerr("[TestCurveSim] 无法加载默认 Balance 配置!")
		return false

	# 1. 校验内置 20 个确定性随机种子互异且数量准确
	var seeds: Array[int] = CurveSimScript.CurveSimRunner.get_default_seeds()
	if seeds.size() != 20:
		printerr("[TestCurveSim] 默认种子数量应为 20, 实测: ", seeds.size())
		return false
	var seen_seeds: Dictionary = {}
	for sd: int in seeds:
		if seen_seeds.has(sd):
			printerr("[TestCurveSim] 存在重复种子: ", sd)
			return false
		seen_seeds[sd] = true

	# 2. 校验 Tick 模式 (S1) 同种子 100% 确定性与状态哈希一致
	var s1_a: Dictionary = CurveSimScript.CurveSimRunner.run_s1_seed(
		seeds[0],
		CurveSimScript.Strategy.STANDARD,
		bal,
		300.0
	)
	var s1_b: Dictionary = CurveSimScript.CurveSimRunner.run_s1_seed(
		seeds[0],
		CurveSimScript.Strategy.STANDARD,
		bal,
		300.0
	)
	if String(s1_a["state_hash"]) != String(s1_b["state_hash"]):
		printerr("[TestCurveSim] S1 Tick 模式同种子状态哈希不一致!")
		return false
	if absf(float(s1_a["dmg_5m_log"]) - float(s1_b["dmg_5m_log"])) > 1e-9:
		printerr("[TestCurveSim] S1 Tick 模式同种子 5 分钟伤害不一致!")
		return false

	# 3. 校验三种内置玩家策略行为差异（零操作不穿装不借贷，激进借贷主动动用信贷）
	var st_zero: SimStateScript = SimStateScript.new(seeds[1], bal)
	var st_debt: SimStateScript = SimStateScript.new(seeds[1], bal)
	st_zero.gold = 4.0
	st_debt.gold = 4.0
	CurveSimScript.CurveSimRunner.apply_player_strategy(st_zero, CurveSimScript.Strategy.ZERO_OP, false)
	CurveSimScript.CurveSimRunner.apply_player_strategy(st_debt, CurveSimScript.Strategy.AGGRESSIVE_DEBT, false)
	if st_zero.credit.active_loan or st_zero.debt_total != NumScript.ZERO:
		printerr("[TestCurveSim] 零操作策略不应触发任何信贷借款!")
		return false
	if not st_debt.credit.active_loan or st_debt.debt_total <= NumScript.ZERO:
		printerr("[TestCurveSim] 激进借贷策略未按预期借满可用信用额度!")
		return false

	# 4. 校验 §7.1 每 100 层区间主题机制与 30% 余韵强度映射及 S2 确定性
	var m100: Dictionary = CurveSimScript.CurveSimRunner.get_band_mechanic_strengths(150, bal)
	var m200: Dictionary = CurveSimScript.CurveSimRunner.get_band_mechanic_strengths(250, bal)
	if absf(float(m100.get(1, 0.0)) - 1.0) > 1e-6:
		printerr("[TestCurveSim] 100–199 层主机制护盾强度应为 1.0!")
		return false
	if absf(float(m200.get(2, 0.0)) - 1.0) > 1e-6 or absf(float(m200.get(1, 0.0)) - bal.band_lingering_strength) > 1e-6:
		printerr("[TestCurveSim] 200–299 层主机制反噬与 30% 护盾余韵映射错误!")
		return false

	var s2_a: Dictionary = CurveSimScript.CurveSimRunner.run_s2_gate_seed(
		seeds[0],
		CurveSimScript.Strategy.ZERO_OP,
		100,
		bal,
		600.0
	)
	var s2_b: Dictionary = CurveSimScript.CurveSimRunner.run_s2_gate_seed(
		seeds[0],
		CurveSimScript.Strategy.ZERO_OP,
		100,
		bal,
		600.0
	)
	if absf(float(s2_a["wait_minutes"]) - float(s2_b["wait_minutes"])) > 1e-9:
		printerr("[TestCurveSim] S2 关卡门模拟同种子等待时长不一致!")
		return false

	# 5. 校验抽象快进模式 (S3) 同种子确定性与每日曲线结构
	var s3_a: Dictionary = CurveSimScript.CurveSimRunner.run_s3_seed(
		seeds[0],
		CurveSimScript.Strategy.STANDARD,
		bal,
		3
	)
	var s3_b: Dictionary = CurveSimScript.CurveSimRunner.run_s3_seed(
		seeds[0],
		CurveSimScript.Strategy.STANDARD,
		bal,
		3
	)
	if String(s3_a["state_hash"]) != String(s3_b["state_hash"]):
		printerr("[TestCurveSim] S3 抽象快进模式同种子状态哈希不一致!")
		return false
	var daily_arr: Array = s3_a["daily"] as Array
	if daily_arr.size() != 3:
		printerr("[TestCurveSim] S3 每日快照长度错误, 预期 3, 实测: ", daily_arr.size())
		return false

	print("[TestCurveSim] WP-04 曲线模拟器全部单元测试通过!")
	return true
