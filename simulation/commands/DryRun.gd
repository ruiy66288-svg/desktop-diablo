class_name DryRun extends RefCounted

## 装备试穿干跑对比器 (依据《02_系统架构与数值_v6.md》§0 Q14 & §2.1 与《00_开发执行总纲.md》WP-12)
## 克隆确定性 SimState（含 SimRng / Buffs / 词条监听器），用真实 SimRunner 同种子无头推演，输出可复现 Δ%
## 时长/默认种子/展示上限全部读取 Balance；伤害统计 = 干跑期间全部 HIT / CRIT / METEOR 事件（含词条派生）

const SimStateScript = preload("res://simulation/SimState.gd")
const SimRunnerScript = preload("res://simulation/SimRunner.gd")
const EventQueueScript = preload("res://simulation/events/EventQueue.gd")
const SimEventScript = preload("res://simulation/events/SimEvent.gd")
const SpawnerScript = preload("res://simulation/combat/Spawner.gd")
const ItemInstanceScript = preload("res://simulation/loot/ItemInstance.gd")
const BalanceScript = preload("res://simulation/Balance.gd")
const NumScript = preload("res://core/num/Num.gd")

const PERCENT_SCALE: float = 100.0

## 评估候选装备：返回 baseline/candidate 干跑总伤害 (log10) 与 delta_pct / delta_log
static func evaluate_candidate(
	source_state: SimStateScript,
	candidate_item: ItemInstanceScript,
	dry_seed: int = -1,
	against_rare_boss: bool = false
) -> Dictionary:
	var bal: BalanceScript = source_state.balance
	var seed_val: int = dry_seed if dry_seed >= 0 else bal.dry_run_default_seed
	var dry_ticks: int = maxi(1, int(round(bal.dry_run_seconds / bal.sim_tick_dt)))

	var base_state: SimStateScript = _clone_for_eval(source_state, seed_val, against_rare_boss)
	var base_dmg_log: float = _run_eval_ticks(base_state, dry_ticks)

	var cand_state: SimStateScript = _clone_for_eval(source_state, seed_val, against_rare_boss)
	if candidate_item != null:
		cand_state.equip_item(candidate_item.clone())
	var cand_dmg_log: float = _run_eval_ticks(cand_state, dry_ticks)

	var delta_log: float = 0.0
	var delta_pct: float = 0.0
	if base_dmg_log == NumScript.ZERO:
		delta_pct = PERCENT_SCALE if cand_dmg_log != NumScript.ZERO else 0.0
	else:
		delta_log = cand_dmg_log - base_dmg_log
		if delta_log > bal.dry_run_display_cap_log:
			delta_pct = (pow(10.0, bal.dry_run_display_cap_log) - 1.0) * PERCENT_SCALE
		elif delta_log < -bal.dry_run_display_cap_log:
			delta_pct = -PERCENT_SCALE
		else:
			delta_pct = (pow(10.0, delta_log) - 1.0) * PERCENT_SCALE

	return {
		"baseline_damage_log": base_dmg_log,
		"candidate_damage_log": cand_dmg_log,
		"delta_pct": delta_pct,
		"delta_log": delta_log
	}

static func _clone_for_eval(source: SimStateScript, seed_val: int, against_rare_boss: bool = false) -> SimStateScript:
	var cloned: SimStateScript = source.clone()
	cloned.command_queue.clear()
	cloned.rng.set_seed(seed_val)
	if against_rare_boss:
		cloned.is_rare_boss_active = true
		SpawnerScript.spawn_rare_boss(cloned)
	else:
		SpawnerScript.spawn_next(cloned)
	return cloned

static func _run_eval_ticks(state: SimStateScript, ticks: int) -> float:
	var runner: SimRunnerScript = SimRunnerScript.new(state)
	var total_dmg_log: float = NumScript.ZERO

	for _t: int in range(ticks):
		runner.step()
		while not runner.queue.is_empty():
			var ev: SimEventScript = runner.queue.pop_front()
			if ev == null:
				continue
			# 实际造成伤害 = 击杀怪物血量 + 未击杀命中的伤害；depth > 0 的派生事件已由 Combat 真实结算并重新产生 KILL/HIT，跳过避免重复计数
			if ev.depth > 0:
				continue
			if (
				ev.type == SimEventScript.T.HIT
				or ev.type == SimEventScript.T.CRIT
				or ev.type == SimEventScript.T.METEOR
				or ev.type == SimEventScript.T.KILL
				or ev.type == SimEventScript.T.BOSS_KILL
			):
				if ev.value != NumScript.ZERO:
					total_dmg_log = NumScript.add(total_dmg_log, ev.value)

	return total_dmg_log
