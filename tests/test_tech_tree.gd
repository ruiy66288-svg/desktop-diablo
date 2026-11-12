class_name TestTechTree extends RefCounted

## WP-14 验收：6 节点科技树 + 5 格研究队列（Unix 时间戳，调试模式按秒计），「关闭游戏→等待→重开」研究按时完成并生效
## 依据《02_系统架构与数值_v6.md》§5.3、Q27、Q28

const SimStateScript = preload("res://simulation/SimState.gd")
const SimRunnerScript = preload("res://simulation/SimRunner.gd")
const CommandScript = preload("res://simulation/commands/Command.gd")
const ResearchQueueScript = preload("res://simulation/tech/ResearchQueue.gd")
const BalanceScript = preload("res://simulation/Balance.gd")
const NumScript = preload("res://core/num/Num.gd")
const SimEventScript = preload("res://simulation/events/SimEvent.gd")

const T0: int = 1_800_000_000

static func run() -> bool:
	print("[TestTechTree] 开始测试 WP-14 科技树与研究队列...")
	if not _test_catalog_and_validation():
		return false
	if not _test_queue_capacity_and_timestamps():
		return false
	if not _test_close_wait_reopen_and_effects():
		return false
	if not _test_auto_buy_prestige_and_determinism():
		return false
	print("[TestTechTree] WP-14 全部验收项 100% 通过!")
	return true

static func _make_state(seed_val: int) -> SimStateScript:
	var state: SimStateScript = SimStateScript.new(seed_val, BalanceScript.load_default() as BalanceScript)
	state.tech.debug_seconds_mode = true
	state.gold = 50.0
	return state

static func _test_catalog_and_validation() -> bool:
	var state: SimStateScript = _make_state(1)
	if state.tech.defs.size() != 6:
		printerr("[TestTechTree] 原型应有 6 个科技节点, 实际: ", state.tech.defs.size())
		return false
	var branches: Dictionary = {}
	for def: Variant in state.tech.defs.values():
		branches[(def as Object).get("branch")] = true
	if branches.size() != 4:
		printerr("[TestTechTree] 应覆盖 4 个分支 (战斗/经济/信贷/自动化), 实际: ", branches.keys())
		return false
	if state.start_research("no_such_node", T0):
		printerr("[TestTechTree] 未知节点应被拒绝")
		return false
	if state.start_research("combat_crit", T0):
		printerr("[TestTechTree] 前置未满足(未研究也未排队)应被拒绝")
		return false
	var poor: SimStateScript = _make_state(2)
	poor.gold = NumScript.ZERO
	if poor.start_research("combat_edge", T0) or poor.research_queue.size() != 0:
		printerr("[TestTechTree] 金币不足应被拒绝且不入队")
		return false
	if not state.start_research("combat_edge", T0) or state.start_research("combat_edge", T0):
		printerr("[TestTechTree] 首次研究应成功、重复入队应被拒绝")
		return false
	print("[TestTechTree] 6 节点/4 分支与前置、金币、重复校验通过")
	return true

static func _test_queue_capacity_and_timestamps() -> bool:
	var state: SimStateScript = _make_state(3)
	var bal: BalanceScript = state.balance
	var order: Array[String] = ["combat_edge", "eco_scavenger", "credit_line", "auto_upgrade", "combat_crit"]
	for node_id: String in order:
		if not state.start_research(node_id, T0):
			printerr("[TestTechTree] 入队失败: ", node_id)
			return false
	if state.research_queue.size() != bal.tech_queue_max_slots or bal.tech_queue_max_slots != 5:
		printerr("[TestTechTree] 研究队列应为 5 格")
		return false
	if state.start_research("eco_drops", T0):
		printerr("[TestTechTree] 第 6 个入队应因队列满被拒绝")
		return false
	# 调试模式 tier1 = ceil(2 * 2.2) = 5 秒，tier2 = ceil(2 * 2.2^2) = 10 秒；队列顺序串行
	var e0: ResearchQueueScript.Entry = state.research_queue.entries[0]
	var e1: ResearchQueueScript.Entry = state.research_queue.entries[1]
	var e4: ResearchQueueScript.Entry = state.research_queue.entries[4]
	if e0.start_unix != T0 or e0.end_unix != T0 + 5 or e1.start_unix != T0 + 5 or e1.end_unix != T0 + 10:
		printerr("[TestTechTree] 队列时间戳不是串行 tier1=5s")
		return false
	if e4.end_unix != T0 + 5 * 4 + 10:
		printerr("[TestTechTree] 队尾完成时刻错误: ", e4.end_unix)
		return false
	# 正常模式（非调试）按分钟计：tier1 = 2 × 2.2 分钟
	var normal: SimStateScript = SimStateScript.new(4, bal)
	normal.gold = 50.0
	normal.start_research("combat_edge", T0)
	var secs: int = normal.research_queue.entries[0].end_unix - T0
	if secs != int(ceil(bal.get_tech_research_seconds(1, false))) or secs <= 60:
		printerr("[TestTechTree] 非调试模式应按分钟计, 实际秒数: ", secs)
		return false
	print("[TestTechTree] 5 格队列、串行时间戳、调试(秒)/正常(分钟)时长验证通过")
	return true

static func _test_close_wait_reopen_and_effects() -> bool:
	var state: SimStateScript = _make_state(5)
	var bal: BalanceScript = state.balance
	var base_hit: float = state.stats.get_base_hit_damage_log()
	var limit_before: float = state.credit.get_credit_limit_log(state.get_active_stage(), bal)
	for node_id: String in ["combat_edge", "eco_scavenger", "credit_line", "combat_crit"]:
		state.start_research(node_id, T0)

	# 「关闭游戏」：仅序列化队列与已研究列表；等待 3 秒后重开 → 仅第 1 项完成前不应有任何完成
	var saved_queue: Array = state.research_queue.to_array()
	var saved_researched: Array[String] = state.tech.researched.duplicate()
	var reopened: SimStateScript = _make_state(5)
	reopened.gold = state.gold
	reopened.research_queue.load_from_array(saved_queue)
	reopened.tech.researched = saved_researched.duplicate()
	if not reopened.settle_research(T0 + 3).is_empty() or not reopened.tech.researched.is_empty():
		printerr("[TestTechTree] 未到期不应完成研究")
		return false
	# 重开时已过去很久：按时间戳一次结算全部到期项，顺序 = 队列顺序
	var done: Array[String] = reopened.settle_research(T0 + 100_000)
	var expected_done: Array[String] = ["combat_edge", "eco_scavenger", "credit_line", "combat_crit"]
	if done != expected_done or reopened.research_queue.size() != 0:
		printerr("[TestTechTree] 离线结算应按序完成全部 4 项: ", done)
		return false

	# 效果生效：加法区 +25%、暴击 +10%、额度 ×1.5(tier_bonus)、收入 +30%
	if absf(reopened.stats.additive_percent - 0.25) > 1e-9:
		printerr("[TestTechTree] combat_edge 加法区 +25% 未生效: ", reopened.stats.additive_percent)
		return false
	var hit_after: float = reopened.stats.get_base_hit_damage_log()
	if absf((hit_after - base_hit) - NumScript.from_float(1.25)) > 1e-9:
		printerr("[TestTechTree] 单次伤害应提升 log10(1.25)")
		return false
	if absf(reopened.stats.crit_rate_bonus - 0.10) > 1e-9:
		printerr("[TestTechTree] combat_crit 暴击 +10% 未生效")
		return false
	var limit_after: float = reopened.credit.get_credit_limit_log(reopened.get_active_stage(), bal)
	if absf((limit_after - limit_before) - NumScript.from_float(bal.credit_limit_tier_growth)) > 1e-9:
		printerr("[TestTechTree] credit_line 额度 ×1.5 未生效")
		return false
	reopened.gold = NumScript.ZERO
	reopened.add_income(3.0)
	if absf(reopened.gold - (3.0 + NumScript.from_float(1.3))) > 1e-9:
		printerr("[TestTechTree] eco_scavenger 收入 +30% 未生效: ", reopened.gold)
		return false

	# 完成时发出 ATTENTION(research_done) 事件
	var ev_state: SimStateScript = _make_state(6)
	ev_state.start_research("auto_upgrade", T0)
	var runner: SimRunnerScript = SimRunnerScript.new(ev_state)
	runner.enqueue_command(CommandScript.make_settle_research(T0 + 50))
	runner.step()
	var saw_attention: bool = false
	for ev: SimEventScript in runner.queue.snapshot():
		if ev.payload.get("signal", "") == "research_done" and ev.payload.get("node_id", "") == "auto_upgrade":
			saw_attention = true
	if not saw_attention or not ev_state.tech.has_researched("auto_upgrade"):
		printerr("[TestTechTree] SETTLE_RESEARCH 未完成研究或未发出 ATTENTION")
		return false
	print("[TestTechTree] 关闭→等待→重开 按时间戳完成研究并生效 (4 项效果全部验证)")
	return true

static func _test_auto_buy_prestige_and_determinism() -> bool:
	# 自动升级：研究完成后，非储蓄期 SimRunner 自动购买金币攻击升级
	var state: SimStateScript = _make_state(7)
	state.start_research("auto_upgrade", T0)
	state.settle_research(T0 + 1000)
	state.gold = 20.0
	state.stats.atk_interval = 100.0
	var runner: SimRunnerScript = SimRunnerScript.new(state)
	runner.step()
	if state.upgrades.atk_level <= 0:
		printerr("[TestTechTree] auto_upgrade 未自动购买攻击升级")
		return false
	if state.upgrades.atk_level > state.balance.auto_buy_max_per_tick:
		printerr("[TestTechTree] 自动购买超出每 tick 上限")
		return false

	# 科技永不随转生重置 (Q28)
	state.perform_soul_prestige()
	if not state.tech.has_researched("auto_upgrade"):
		printerr("[TestTechTree] 转生后科技被重置")
		return false

	# 同种子同操作 → 状态哈希一致
	var a: SimStateScript = _make_state(9)
	var b: SimStateScript = _make_state(9)
	for s: SimStateScript in [a, b]:
		s.start_research("combat_edge", T0)
		s.start_research("eco_scavenger", T0)
		s.settle_research(T0 + 7)
	if a.compute_state_hash() != b.compute_state_hash():
		printerr("[TestTechTree] 同种子同操作哈希不一致")
		return false
	print("[TestTechTree] 自动升级、转生保留科技、确定性哈希验证通过")
	return true