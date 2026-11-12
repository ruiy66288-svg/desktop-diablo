class_name OfflineCalc extends RefCounted

## 离线结算最小版本 (依据《02_系统架构与数值_v6.md》§3.4、Q5 与《00_开发执行总纲.md》WP-17)
## 只推进「研究队列」与「金币」：
##  - 研究：按 Unix 时间戳差结算（不受离线上限约束，研究是现实时间推进）
##  - 金币：克隆当前 Sim 无债务/无门票干跑一个校准采样窗口，得到每秒毛收入后外推，封顶 offline_cap_base_hours
##          外推所得毛收入经 SimState.add_income 入账，因此自动享受 40% 还债/宿债抵扣与门前托管规则
## 铁律：绝不倒退——run_best / all_time_best / 层数 / 装备 / 科技 在结算前后只增不减（结算本身不推进层数）
## 纯 RefCounted，零 Node 依赖；时间戳由调用方传入以保证确定性

const NumScript = preload("res://core/num/Num.gd")
const BalanceScript = preload("res://simulation/Balance.gd")
const SimStateScript = preload("res://simulation/SimState.gd")
const SimRunnerScript = preload("res://simulation/SimRunner.gd")
const SpawnerScript = preload("res://simulation/combat/Spawner.gd")

const SECONDS_PER_HOUR: float = 3600.0

## 校准采样：克隆状态（无债务、无宿债、关闭门票托管）推进 sample_seconds，返回每秒毛收入 (log10)，无收入返回 -INF
static func sample_gold_rate_log(state: SimStateScript) -> float:
	var bal: BalanceScript = state.balance
	var probe: SimStateScript = state.clone()
	probe.command_queue.clear()
	probe.debt_total = NumScript.ZERO
	probe.legacy_debt_minutes = 0.0
	probe.toll_escrow = NumScript.ZERO
	probe.gold = NumScript.ZERO
	probe.enforce_toll_gates = false
	probe.tech.researched = state.tech.researched.duplicate()
	SpawnerScript.spawn_next(probe)
	var runner: SimRunnerScript = SimRunnerScript.new(probe)
	var ticks: int = maxi(1, int(round(bal.offline_sample_seconds / bal.sim_tick_dt)))
	var gold_start: float = probe.gold
	for _t: int in range(ticks):
		runner.step()
		runner.queue.clear()
	if probe.gold == NumScript.ZERO:
		return NumScript.ZERO
	var gained: float = NumScript.sub(probe.gold, gold_start)
	if gained == NumScript.ZERO:
		return NumScript.ZERO
	return NumScript.div(gained, NumScript.from_float(bal.offline_sample_seconds))

## 结算离线 elapsed_seconds（now_unix 为重开时刻的 Unix 秒），返回报告字典
static func settle(state: SimStateScript, elapsed_seconds: float, now_unix: int) -> Dictionary:
	var bal: BalanceScript = state.balance
	var run_best_before: int = state.run_best
	var all_time_before: int = state.all_time_best
	var stage_before: int = state.current_stage

	# 1. 研究：按时间戳推进
	var research_done: Array[String] = state.settle_research(now_unix)

	# 2. 金币：校准外推，封顶离线上限
	var cap_seconds: float = bal.offline_cap_base_hours * SECONDS_PER_HOUR
	var effective: float = clampf(elapsed_seconds, 0.0, cap_seconds)
	var gain_log: float = NumScript.ZERO
	if effective > 0.0:
		var rate_log: float = sample_gold_rate_log(state)
		if rate_log != NumScript.ZERO:
			gain_log = rate_log + NumScript.from_float(effective)
			state.add_income(gain_log)

	# 3. 不倒退校验（防御性：任何异常都回滚到不低于结算前）
	state.run_best = maxi(state.run_best, run_best_before)
	state.all_time_best = maxi(state.all_time_best, all_time_before)
	state.current_stage = maxi(state.current_stage, stage_before)

	return {
		"elapsed_seconds": elapsed_seconds,
		"effective_seconds": effective,
		"capped": elapsed_seconds > cap_seconds,
		"gold_gain_log": gain_log,
		"research_done": research_done,
		"run_best_before": run_best_before,
		"run_best_after": state.run_best,
		"all_time_best_before": all_time_before,
		"all_time_best_after": state.all_time_best
	}

## 供 SimRunner.offline_handler 使用：卡顿/睡眠超过追赶上限时调用 (§3.2)；读取系统时钟仅在此入口
static func handle_long_gap(state: SimStateScript, elapsed_seconds: float) -> void:
	settle(state, elapsed_seconds, int(Time.get_unix_time_from_system()))