class_name TestCombatSim extends RefCounted

const SimStateScript = preload("res://simulation/SimState.gd")
const SimRunnerScript = preload("res://simulation/SimRunner.gd")
const BalanceScript = preload("res://simulation/Balance.gd")
const NumScript = preload("res://core/num/Num.gd")
const SimRngScript = preload("res://core/rng/SimRng.gd")

static func run() -> bool:
	print("[TestCombatSim] 开始测试 WP-03 核心战斗管线、边界约束与 10,000 ticks 确定性哈希...")

	var bal: BalanceScript = BalanceScript.load_default()

	# 1. 验证基础推层与金币产出
	var s1: SimStateScript = SimStateScript.new(42, bal)
	s1.stats.base_gold_atk_log = 2.70
	var runner1: SimRunnerScript = SimRunnerScript.new(s1)

	for _i in range(100):
		runner1.step()

	if s1.mobs_killed_total == 0:
		printerr("[TestCombatSim] 100 ticks 内未产生任何怪物击杀!")
		return false
	if s1.gold <= NumScript.ZERO:
		printerr("[TestCombatSim] 击杀后未获得金币收入!")
		return false

	print("[TestCombatSim] 基础推层战斗正常, 累计击杀: ", s1.mobs_killed_total, ", 金币: ", NumScript.format_num(s1.gold))

	# 2. 验证 SimRng 三条独立种子流互不污染 (§4.3)
	var rng_a: SimRngScript = SimRngScript.new(777777)
	var rng_b: SimRngScript = SimRngScript.new(777777)
	for _i in range(500):
		rng_a.loot.next_u32()
		rng_a.collection.next_u32()
	for _i in range(50):
		if rng_a.combat.next_u32() != rng_b.combat.next_u32():
			printerr("[TestCombatSim] loot/collection 流推进污染了 combat 独立流!")
			return false

	# 3. 验证勘误 E3（退回只改 farm_stage）与 §9.1 四个层数变量不变量，以及 E4/E10
	var expected_slots: Array[String] = ["weapon", "helm", "chest", "gloves", "boots", "trinket"]
	if SimStateScript.EQUIP_SLOTS != expected_slots:
		printerr("[TestCombatSim] 6 槽位命名不符合勘误 E10!")
		return false

	var s_retreat: SimStateScript = SimStateScript.new(2026, bal)
	s_retreat.all_time_best = 5
	s_retreat.run_best = 5
	s_retreat.current_stage = 5
	s_retreat.farm_stage = 5
	s_retreat.mobs_killed_in_stage = bal.mobs_per_stage
	s_retreat.stats.base_gold_atk_log = 0.0
	var r_retreat: SimRunnerScript = SimRunnerScript.new(s_retreat)

	for _i in range(160):
		r_retreat.step()

	if s_retreat.current_stage != 5 or s_retreat.run_best != 5 or s_retreat.all_time_best != 5:
		printerr("[TestCombatSim] 违反勘误 E3: Boss 超时退回时错误修改了 current_stage / run_best!")
		return false
	if s_retreat.farm_stage != 4:
		printerr("[TestCombatSim] Boss 超时后 farm_stage 未退回第 4 层: ", s_retreat.farm_stage)
		return false

	# 验证勘误 E4: 巨额 toll_escrow 绝不产生财富压力
	var delta_before_escrow: float = s_retreat.get_wealth_pressure_hp_delta(4)
	s_retreat.toll_escrow = 50.0
	var delta_after_escrow: float = s_retreat.get_wealth_pressure_hp_delta(4)
	if absf(delta_before_escrow - delta_after_escrow) > 1e-9:
		printerr("[TestCombatSim] 违反勘误 E4: toll_escrow 被计入了净财富压力!")
		return false

	# 变强后应自动重试并突破第 5 层
	s_retreat.stats.base_gold_atk_log = 8.0
	for _i in range(20):
		r_retreat.step()
	if s_retreat.current_stage < 6 or s_retreat.run_best < 6 or s_retreat.farm_stage != s_retreat.current_stage:
		printerr("[TestCombatSim] 变强后未自动重试突破当前挑战层!")
		return false

	# 4. 验证 Q6 混合粒度结算（>8 次攻击聚合）+ 溢出穿透 + 单 tick 最多击杀 20 只
	var s_cap: SimStateScript = SimStateScript.new(8888, bal)
	s_cap.stats.atk_interval = 0.01
	s_cap.stats.base_gold_atk_log = 40.0
	var r_cap: SimRunnerScript = SimRunnerScript.new(s_cap)
	var one_tick_kills: int = r_cap.step()
	if one_tick_kills != bal.max_kills_per_tick or s_cap.mobs_killed_total != 20:
		printerr("[TestCombatSim] 单 tick 溢出穿透击杀上限未严格封顶在 20 只! 实际: ", one_tick_kills)
		return false

	# 5. 验证 SimRunner 固定步长与最多追赶 50 ticks (§3.2 & WP-03)
	var s_catchup: SimStateScript = SimStateScript.new(9999, bal)
	var r_catchup: SimRunnerScript = SimRunnerScript.new(s_catchup)
	var ticks_small: int = r_catchup.advance(0.35)
	if ticks_small != 3:
		printerr("[TestCombatSim] advance(0.35) 应推进 3 个 tick, 实际: ", ticks_small)
		return false
	var ticks_huge: int = r_catchup.advance(12.0)
	if ticks_huge != bal.max_catchup_ticks or ticks_huge != 50:
		printerr("[TestCombatSim] SimRunner 未封顶在最多追赶 50 个 tick! 实际: ", ticks_huge)
		return false

	# 6. 验证 10,000 ticks 确定性状态哈希完全一致 (WP-03 核心验收)
	print("[TestCombatSim] 正在验证同种子 10,000 ticks 确定性状态哈希...")
	var seed_test: int = 987654321

	var sa: SimStateScript = SimStateScript.new(seed_test, bal)
	sa.stats.base_gold_atk_log = 2.50
	var ra: SimRunnerScript = SimRunnerScript.new(sa)
	for _i in range(10000):
		ra.step()

	var sb: SimStateScript = SimStateScript.new(seed_test, bal)
	sb.stats.base_gold_atk_log = 2.50
	var rb: SimRunnerScript = SimRunnerScript.new(sb)
	for _i in range(10000):
		rb.step()

	var sc: SimStateScript = SimStateScript.new(seed_test + 1, bal)
	sc.stats.base_gold_atk_log = 2.50
	var rc: SimRunnerScript = SimRunnerScript.new(sc)
	for _i in range(10000):
		rc.step()

	var hash_a: String = sa.compute_state_hash()
	var hash_b: String = sb.compute_state_hash()
	var hash_c: String = sc.compute_state_hash()

	if hash_a != hash_b:
		printerr("[TestCombatSim] 10,000 ticks 状态哈希不一致! A=", hash_a, " B=", hash_b)
		return false
	if hash_a == hash_c:
		printerr("[TestCombatSim] 不同种子 10,000 ticks 哈希意外碰撞!")
		return false

	print("[TestCombatSim] 10,000 ticks 确定性状态哈希 100% 一致: ", hash_a)
	return true
