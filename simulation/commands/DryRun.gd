class_name DryRun extends RefCounted

## 装备试穿干跑对比器 (依据《02_系统架构与数值_v6.md》§0 Q14 & §2.1)
## 克隆确定性 SimState，同种子无头推演 30 秒，输出可复现 Δ%

const SimStateScript = preload("res://simulation/SimState.gd")
const CombatScript = preload("res://simulation/combat/Combat.gd")
const EventQueueScript = preload("res://simulation/events/EventQueue.gd")
const SimEventScript = preload("res://simulation/events/SimEvent.gd")
const SpawnerScript = preload("res://simulation/combat/Spawner.gd")
const ItemInstanceScript = preload("res://simulation/loot/ItemInstance.gd")
const AffixResolverScript = preload("res://simulation/events/AffixResolver.gd")
const BuffsScript = preload("res://simulation/events/Buffs.gd")
const NumScript = preload("res://core/num/Num.gd")

const DRY_RUN_SECONDS: float = 30.0
const MAX_DISPLAY_LOG_DELTA: float = 5.0
const PERCENT_SCALE: float = 100.0

static func evaluate_candidate(
	source_state: SimStateScript,
	candidate_item: ItemInstanceScript,
	dry_seed: int = 987654321
) -> Dictionary:
	var tick_dt: float = source_state.balance.sim_tick_dt
	var dry_ticks: int = maxi(1, int(round(DRY_RUN_SECONDS / tick_dt)))

	var base_state: SimStateScript = _clone_for_eval(source_state, dry_seed)
	var base_dmg_log: float = _run_eval_ticks(base_state, dry_ticks)

	var cand_state: SimStateScript = _clone_for_eval(source_state, dry_seed)
	if candidate_item != null:
		cand_state.equip_item(candidate_item.clone())
	var cand_dmg_log: float = _run_eval_ticks(cand_state, dry_ticks)

	var delta_pct: float = 0.0
	var delta_log: float = cand_dmg_log - base_dmg_log

	if base_dmg_log == NumScript.ZERO:
		delta_pct = PERCENT_SCALE if cand_dmg_log != NumScript.ZERO else 0.0
	elif delta_log > MAX_DISPLAY_LOG_DELTA:
		delta_pct = (pow(10.0, MAX_DISPLAY_LOG_DELTA) - 1.0) * PERCENT_SCALE
	elif delta_log < -MAX_DISPLAY_LOG_DELTA:
		delta_pct = -PERCENT_SCALE
	else:
		delta_pct = (pow(10.0, delta_log) - 1.0) * PERCENT_SCALE

	return {
		"baseline_damage_log": base_dmg_log,
		"candidate_damage_log": cand_dmg_log,
		"delta_pct": delta_pct,
		"delta_log": delta_log
	}

static func _clone_for_eval(source: SimStateScript, seed_val: int) -> SimStateScript:
	var cloned: SimStateScript = source.clone()
	cloned.rng.set_seed(seed_val)
	SpawnerScript.spawn_next(cloned)
	return cloned

static func _run_eval_ticks(state: SimStateScript, ticks: int) -> float:
	var combat: CombatScript = CombatScript.new()
	var queue: EventQueueScript = EventQueueScript.new()
	var total_dmg_log: float = NumScript.ZERO
	var dt: float = state.balance.sim_tick_dt

	for _t in range(ticks):
		combat.step_tick(dt, state, queue)
		var resolver_var: Variant = state.get("resolver")
		if resolver_var is AffixResolverScript:
			(resolver_var as AffixResolverScript).resolve_tick(state, queue, null)
		var buffs_var: Variant = state.get("buffs")
		if buffs_var is BuffsScript:
			(buffs_var as BuffsScript).tick()

		while not queue.is_empty():
			var ev: SimEventScript = queue.pop_front()
			if ev != null and (
				ev.type == SimEventScript.T.HIT
				or ev.type == SimEventScript.T.CRIT
				or ev.type == SimEventScript.T.METEOR
			):
				if ev.value > NumScript.ZERO:
					total_dmg_log = NumScript.add(total_dmg_log, ev.value)

	return total_dmg_log
