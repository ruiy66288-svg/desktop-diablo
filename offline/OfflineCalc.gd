class_name OfflineCalc extends RefCounted

## 离线结算完整分段校准版本 (依据《02_系统架构与数值_v6.md》§3.4、Q5、§8 与《00_开发执行总纲.md》WP-17)
## 纯 RefCounted，零 Node 依赖，100% 显式静态类型
## 功能：
##  - 采样窗口 (60s) 在克隆 probe 上推演，测定每秒毛收入 (sample_gold_rate_log)
##  - 分段校准推进 (最多 30 个检查点)：
##      1. 现实 Unix 时间戳结算研究队列 (不受离线上限约束)
##      2. 结算各段金币收入 (自动执行 40% 债务/宿债抵扣与储蓄门票托管账户)
##      3. 自动购买攻击科技 (auto_buy_atk)
##      4. 关卡推进判定 (DPS 足以击杀当前 Boss 且门票缴清)
##      5. 掉落判定 (背包最多保留 20 件暗金/太古，其余自动熔炼)
##      6. 稀有 Boss 召唤符文判定 (按离线总分钟数与 bad_luck 保护判定)
##  - 铁律：绝不倒退——run_best / all_time_best / 层数 / 净财富在结算前后只增不减

const NumScript = preload("res://core/num/Num.gd")
const BalanceScript = preload("res://simulation/Balance.gd")
const SimStateScript = preload("res://simulation/SimState.gd")
const SimRunnerScript = preload("res://simulation/SimRunner.gd")
const SpawnerScript = preload("res://simulation/combat/Spawner.gd")
const ItemInstanceScript = preload("res://simulation/loot/ItemInstance.gd")
const SmelterScript = preload("res://simulation/loot/Smelter.gd")

const SECONDS_PER_HOUR: float = 3600.0
const MAX_OFFLINE_CHECKPOINTS: int = 30
const MAX_OFFLINE_KEPT_UNIQUES: int = 20

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

## 判定当前角色是否可以在离线模式下推进下一层关卡
static func _can_advance_offline_stage(state: SimStateScript) -> bool:
	var bal: BalanceScript = state.balance
	var boss_hp: float = bal.get_boss_hp_log(state.current_stage) + state.get_wealth_pressure_hp_delta(state.current_stage)
	var max_dmg_log: float = state.stats.get_expected_dps_log(bal.min_atk_interval) + NumScript.from_float(bal.boss_time_limit)
	if max_dmg_log < boss_hp:
		return false

	# 门票校验：若处于百层门前，必须能支付门票
	var band_interval: int = bal.band_stage_interval
	if state.enforce_toll_gates and band_interval > 0 and (state.current_stage % band_interval == 0):
		var gate_tier: int = int(state.current_stage / band_interval)
		if state.paid_gate_tier < gate_tier:
			if not state.try_pay_next_toll():
				return false

	return true

## 结算离线 elapsed_seconds（now_unix 为重开时刻的 Unix 秒），返回报告字典
static func settle(state: SimStateScript, elapsed_seconds: float, now_unix: int) -> Dictionary:
	var bal: BalanceScript = state.balance
	var run_best_before: int = state.run_best
	var all_time_before: int = state.all_time_best
	var stage_before: int = state.current_stage
	var debt_before: float = state.debt_total
	var legacy_debt_before: float = state.legacy_debt_minutes

	# 1. 研究：按现实时间戳推进 (现实时间结算，不受离线上限约束)
	var research_done: Array[String] = state.settle_research(now_unix)

	# 2. 封顶离线上限
	var cap_hours: float = bal.offline_cap_max_hours if state.has_tech_effect("offline_cap_24h") else bal.offline_cap_base_hours
	var cap_seconds: float = cap_hours * SECONDS_PER_HOUR
	var effective: float = clampf(elapsed_seconds, 0.0, cap_seconds)
	var gain_log: float = NumScript.ZERO
	var stages_advanced: int = 0
	var new_uniques: Array[String] = []
	var new_summon_runes: int = 0

	# 3. 分段校准推进 (最多 30 个检查点)
	if effective > 0.0:
		var num_segments: int = clampi(int(ceil(effective / 60.0)), 1, MAX_OFFLINE_CHECKPOINTS)
		var dt_segment: float = effective / float(num_segments)

		for _seg: int in range(num_segments):
			# 3.1 采样金币速率并注入本段收益（自动走 40% 还债/宿债抵扣与储蓄门票托管）
			var rate_log: float = sample_gold_rate_log(state)
			if rate_log != NumScript.ZERO:
				var seg_gold_log: float = rate_log + NumScript.from_float(dt_segment)
				gain_log = NumScript.add(gain_log, seg_gold_log)
				state.add_income(seg_gold_log)

			# 3.2 自动购买攻击科技 (若已点亮 auto_buy_atk)
			if state.has_tech_effect("auto_buy_atk") and state.upgrades != null:
				state.upgrades.buy_atk_upgrades_bulk(state, 100)

			# 3.3 尝试推进层数 (若 DPS 足够破关且缴清门票)
			if _can_advance_offline_stage(state):
				state.advance_to_next_stage()
				stages_advanced += 1
				SpawnerScript.spawn_next(state)

			# 3.4 离线掉落保留 (暗金/太古最多保留 20 件，其余自动熔炼)
			if new_uniques.size() < MAX_OFFLINE_KEPT_UNIQUES and state.loot_roller != null:
				var drops: Array[ItemInstanceScript] = state.loot_roller.roll_loot_for_kill(
					state.get_active_stage(),
					false,
					state,
					null
				)
				for item: ItemInstanceScript in drops:
					if int(item.rarity) >= int(ItemInstanceScript.Rarity.UNIQUE):
						if state.filter.should_keep(item) and state.inventory.get_count() < state.inventory.MAX_CAPACITY:
							state.inventory.add_item(item, state, null)
							state.note_item_kept(item, null)
							new_uniques.push_back(item.name)
						else:
							SmelterScript.smelt_item(item, state, null)
					else:
						SmelterScript.smelt_item(item, state, null)

		# 3.5 稀有 Boss 召唤符文判定 (按离线总分钟数，仅在 run_best >= 100 阶段)
		var total_offline_minutes: int = int(floor(effective / 60.0))
		if total_offline_minutes > 0 and state.collection_roller != null and state.run_best >= bal.abyss_min_stage:
			new_summon_runes = state.collection_roller.roll_offline_minutes(
				total_offline_minutes,
				state.rng.loot,
				bal,
				state.codex
			)

	# 4. 统计偿还债务
	var debt_repaid_log: float = NumScript.ZERO
	if debt_before != NumScript.ZERO and state.debt_total < debt_before:
		debt_repaid_log = NumScript.sub(debt_before, state.debt_total)
	if legacy_debt_before > state.legacy_debt_minutes:
		var leg_paid: float = NumScript.from_float(legacy_debt_before - state.legacy_debt_minutes)
		debt_repaid_log = NumScript.add(debt_repaid_log, leg_paid)

	# 5. 不倒退校验（防御性：任何异常都回滚到不低于结算前）
	state.run_best = maxi(state.run_best, run_best_before)
	state.all_time_best = maxi(state.all_time_best, all_time_before)
	state.current_stage = maxi(state.current_stage, stage_before)
	state.farm_stage = maxi(state.farm_stage, stage_before)

	return {
		"elapsed_seconds": elapsed_seconds,
		"effective_seconds": effective,
		"capped": elapsed_seconds > cap_seconds,
		"gold_gain_log": gain_log,
		"research_done": research_done,
		"run_best_before": run_best_before,
		"run_best_after": state.run_best,
		"all_time_best_before": all_time_before,
		"all_time_best_after": state.all_time_best,
		"stages_advanced": stages_advanced,
		"debt_repaid_log": debt_repaid_log,
		"new_uniques": new_uniques,
		"new_summon_runes": new_summon_runes
	}

## 供 SimRunner.offline_handler 使用：卡顿/睡眠超过追赶上限时调用 (§3.2)；读取系统时钟仅在此入口
static func handle_long_gap(state: SimStateScript, elapsed_seconds: float) -> void:
	settle(state, elapsed_seconds, int(Time.get_unix_time_from_system()))
