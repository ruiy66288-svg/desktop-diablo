class_name Combat extends RefCounted

## 核心确定性战斗结算管线
## 依据《02_系统架构与数值_v6.md》§0 Q3 & Q6、§2.2、§9.1 与《00_开发执行总纲.md》WP-03、§2 E3、§4.3
## 规则：前 8 次攻击逐次结算，超额按二项分布聚合；溢出伤害穿透；单 tick 最多击杀 20 只；退回只改 farm_stage

const SimStateScript = preload("res://simulation/SimState.gd")
const SpawnerScript = preload("res://simulation/combat/Spawner.gd")
const SimEventScript = preload("res://simulation/events/SimEvent.gd")
const EventQueueScript = preload("res://simulation/events/EventQueue.gd")
const SmelterScript = preload("res://simulation/loot/Smelter.gd")
const ItemInstanceScript = preload("res://simulation/loot/ItemInstance.gd")
const NumScript = preload("res://core/num/Num.gd")

func step_tick(dt: float, state: SimStateScript, queue: EventQueueScript) -> int:
	# 1. 确保场上有存活怪物
	if state.mob_current_hp_log <= NumScript.ZERO or state.mob_max_hp_log <= 0.0:
		SpawnerScript.spawn_next(state)

	# 2. Boss 15 秒限时判定 (Q3 & 勘误 E3：超时失败只回退 farm_stage，绝不修改 current_stage)
	if state.is_boss:
		state.boss_timer += dt
		if state.boss_timer >= state.balance.boss_time_limit:
			state.last_fail_margin_log = state.get_boss_power_margin_log(state.current_stage)
			state.farm_stage = maxi(1, state.current_stage - 1)
			state.is_boss = false
			state.boss_timer = 0.0
			state.mobs_killed_in_stage = 0
			state.farm_kills_since_retreat = 0
			state.boss_fail_streak += 1
			if state.boss_fail_streak >= state.balance.wall_signal_fail_streak:
				queue.push_back(SimEventScript.new(SimEventScript.T.ATTENTION, float(state.current_stage)))
			SpawnerScript.spawn_next(state)
			return 0

	# 3. 攻速充能与本 tick 攻击次数计算（读取 Balance 参数，零硬编码）
	var speed_bonus: float = state.buffs.get_stat_bonus("atk_speed_pct") if state.buffs != null else 0.0
	var interval: float = maxf(state.balance.min_atk_interval, state.stats.atk_interval / (1.0 + speed_bonus))
	state.atk_progress += dt / interval
	var attacks: int = int(floor(state.atk_progress))
	state.atk_progress -= float(attacks)

	if attacks <= 0:
		return 0

	# 4. Q6 混合粒度结算：前 hybrid_individual_attacks (8) 次逐次结算，其余按二项分布聚合
	var max_individual: int = state.balance.hybrid_individual_attacks
	var max_kills: int = state.balance.max_kills_per_tick
	var individual_count: int = mini(attacks, max_individual)
	var aggregate_count: int = attacks - individual_count
	var kills_this_tick: int = 0

	# 4.1 逐击结算（仅使用 state.rng.combat 独立战斗流）
	for _i in range(individual_count):
		if kills_this_tick >= max_kills:
			break
		var hit_info: Dictionary = state.stats.roll_hit(state.rng.combat)
		var dmg_log: float = float(hit_info["damage_log"])
		var is_crit: bool = bool(hit_info["is_crit"])
		kills_this_tick += _apply_hit_damage(dmg_log, is_crit, 1, state, queue, kills_this_tick, max_kills)

	# 4.2 超额攻击按二项分布 Binomial(aggregate_count, eff_crit) 聚合结算 (Q6)
	if aggregate_count > 0 and kills_this_tick < max_kills:
		var eff_crit: float = state.stats.get_effective_crit_rate()
		var crits: int = state.rng.combat.sample_binomial(aggregate_count, eff_crit)
		var normals: int = aggregate_count - crits
		var base_dmg: float = state.stats.get_base_hit_damage_log()
		var crit_dmg: float = base_dmg + NumScript.from_float(state.stats.crit_mult)

		var total_norm_log: float = base_dmg + NumScript.from_float(float(normals)) if normals > 0 else NumScript.ZERO
		var total_crit_log: float = crit_dmg + NumScript.from_float(float(crits)) if crits > 0 else NumScript.ZERO
		var batch_total_dmg: float = NumScript.add(total_norm_log, total_crit_log)

		kills_this_tick += _apply_hit_damage(
			batch_total_dmg,
			crits > 0,
			aggregate_count,
			state,
			queue,
			kills_this_tick,
			max_kills
		)

	return kills_this_tick

## 结算词条派生伤害（连锁闪电/落地即爆等）：真实扣减当前怪血量，受单 tick 击杀上限约束，返回击杀数
func apply_derived_damage(dmg_log: float, state: SimStateScript, queue: EventQueueScript) -> int:
	return _apply_hit_damage(dmg_log, false, 1, state, queue, 0, state.balance.max_kills_per_tick)

## 执行伤害扣减与溢出伤害穿透到下一只怪（受单 tick 击杀上限 max_kills 约束）
func _apply_hit_damage(
	dmg_log: float,
	is_crit: bool,
	hit_count: int,
	state: SimStateScript,
	queue: EventQueueScript,
	current_kills: int,
	max_kills: int
) -> int:
	var kills_added: int = 0
	var cur_dmg: float = dmg_log

	while cur_dmg > NumScript.ZERO and (current_kills + kills_added) < max_kills:
		# 护盾机制 (§7.1)：每次命中至多削掉 strip_cap 的护盾；护盾未破时整击被吸收
		if state.mob_shield_cur_log > NumScript.ZERO:
			var allowed_strip: float = state.mob_shield_strip_cap_log + NumScript.from_float(float(maxi(1, hit_count)))
			var actual_strip: float = NumScript.min_num(cur_dmg, allowed_strip)
			if actual_strip >= state.mob_shield_cur_log:
				var post_shield_dmg: float = NumScript.sub(actual_strip, state.mob_shield_cur_log)
				state.mob_shield_cur_log = NumScript.ZERO
				cur_dmg = NumScript.min_num(cur_dmg, post_shield_dmg)
				if cur_dmg == NumScript.ZERO:
					break
			else:
				state.mob_shield_cur_log = NumScript.sub(state.mob_shield_cur_log, actual_strip)
				var absorb_ev: SimEventScript = SimEventScript.new(SimEventScript.T.HIT, actual_strip, hit_count)
				absorb_ev.hint = {"shield_absorb": true}
				queue.push_back(absorb_ev)
				break
		if cur_dmg >= state.mob_current_hp_log:
			kills_added += 1
			state.mobs_killed_total += 1
			var overflow_dmg: float = NumScript.sub(cur_dmg, state.mob_current_hp_log)
			var killed_stage: int = state.get_active_stage()
			var killed_was_boss: bool = state.is_boss
			var killed_max_hp: float = state.mob_max_hp_log

			state.add_income(state.balance.get_mob_gold_log(killed_stage), queue)

			var drops: Array[ItemInstanceScript] = state.loot_roller.roll_loot_for_kill(
				killed_stage,
				killed_was_boss,
				state,
				queue
			)
			for item: ItemInstanceScript in drops:
				if state.filter.should_keep(item):
					state.inventory.add_item(item, state, queue)
				else:
					SmelterScript.smelt_item(item, state, queue)

			if killed_was_boss:
				state.boss_fail_streak = 0
				state.farm_kills_since_retreat = 0
				queue.push_back(SimEventScript.new(SimEventScript.T.BOSS_KILL, killed_max_hp))
				_handle_boss_stage_clear(state, queue)
			else:
				queue.push_back(SimEventScript.new(SimEventScript.T.KILL, killed_max_hp))
				if state.farm_stage < state.current_stage:
					state.farm_kills_since_retreat += 1
				elif not state.gate_boss_cleared:
					state.mobs_killed_in_stage += 1

			SpawnerScript.spawn_next(state)
			cur_dmg = overflow_dmg
		else:
			state.mob_current_hp_log = NumScript.sub(state.mob_current_hp_log, cur_dmg)
			var ev_type: SimEventScript.T = SimEventScript.T.CRIT if is_crit else SimEventScript.T.HIT
			queue.push_back(SimEventScript.new(ev_type, cur_dmg, hit_count))
			break

	return kills_added

func _handle_boss_stage_clear(state: SimStateScript, queue: EventQueueScript) -> void:
	var band_interval: int = state.balance.band_stage_interval
	if state.enforce_toll_gates and band_interval > 0 and (state.current_stage % band_interval == 0):
		var gate_tier: int = int(state.current_stage / band_interval)
		if state.paid_gate_tier < gate_tier and not state.try_pay_next_toll():
			state.gate_boss_cleared = true
			state.is_boss = false
			state.boss_timer = 0.0
			state.mobs_killed_in_stage = 0
			return

	state.advance_to_next_stage(queue)
