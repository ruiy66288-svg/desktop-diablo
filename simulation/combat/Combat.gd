class_name Combat extends RefCounted

## 核心确定性战斗结算管线
## 依据《02_系统架构与数值_v6.md》§0 Q3 & Q6、§2.2、§7.1、§9.1 与《00_开发执行总纲.md》WP-03、WP-15、§2 E3、§4.3
## 规则：前 8 次攻击逐次结算，超额按二项分布聚合；溢出伤害穿透；单 tick 最多击杀 20 只；退回只改 farm_stage
## 百层主题机制（§7.1，数学口径与 tools/curve_sim.gd BandCombatContext 完全一致）：
##   护盾 / 反噬眩晕 / 只吃暴击 / 分身 / 吞金；1–100 层 strengths 为空，走与 WP-03 完全相同的路径（哈希不变）

const SimStateScript = preload("res://simulation/SimState.gd")
const SpawnerScript = preload("res://simulation/combat/Spawner.gd")
const SimEventScript = preload("res://simulation/events/SimEvent.gd")
const EventQueueScript = preload("res://simulation/events/EventQueue.gd")
const SmelterScript = preload("res://simulation/loot/Smelter.gd")
const ItemInstanceScript = preload("res://simulation/loot/ItemInstance.gd")
const BandRulesScript = preload("res://simulation/mechanics/BandRules.gd")
const MechanicDefScript = preload("res://simulation/mechanics/MechanicDef.gd")
const BalanceScript = preload("res://simulation/Balance.gd")
const NumScript = preload("res://core/num/Num.gd")

const KIND_SHIELD: int = MechanicDefScript.Kind.SHIELD
const KIND_BACKLASH: int = MechanicDefScript.Kind.BACKLASH
const KIND_CRIT_ONLY: int = MechanicDefScript.Kind.CRIT_ONLY
const KIND_CLONE: int = MechanicDefScript.Kind.CLONE
const KIND_GOLD_EAT: int = MechanicDefScript.Kind.GOLD_EAT

const UNIQUE_RAIN_CHARGE_KEY: String = "unique_rain"
const STUN_EPS: float = 1e-6

func step_tick(dt: float, state: SimStateScript, queue: EventQueueScript) -> int:
	var bal: BalanceScript = state.balance
	var tick_dt: float = dt

	# 1. 确保场上有存活怪物
	if state.mob_current_hp_log <= NumScript.ZERO or state.mob_max_hp_log <= 0.0:
		SpawnerScript.spawn_next(state)

	var strengths: Dictionary = BandRulesScript.get_strengths(state.get_active_stage(), bal)

	# 1.5 吞金 (§7.1)：每秒吞余额 1%，不超过近期收入的 50%，绝不触碰 toll_escrow
	if strengths.has(KIND_GOLD_EAT) and state.gold != NumScript.ZERO:
		_apply_gold_eat(tick_dt, float(strengths[KIND_GOLD_EAT]), state)

	# 2. Boss 15 秒限时判定 (Q3 & 勘误 E3：超时失败只回退 farm_stage，绝不修改 current_stage)
	if state.is_boss:
		state.boss_timer += tick_dt
		if state.boss_timer >= bal.boss_time_limit:
			state.last_fail_margin_log = state.get_boss_power_margin_log(state.current_stage)
			state.farm_stage = maxi(1, state.current_stage - 1)
			state.is_boss = false
			state.boss_timer = 0.0
			state.mobs_killed_in_stage = 0
			state.farm_kills_since_retreat = 0
			state.boss_fail_streak += 1
			if state.boss_fail_streak >= bal.wall_signal_fail_streak:
				queue.push_back(SimEventScript.new(SimEventScript.T.ATTENTION, float(state.current_stage)))
			SpawnerScript.spawn_next(state)
			return 0

	# 2.5 反噬眩晕计时 (§7.1 & Q30)：眩晕期间暂停普攻进度
	var eff_dt: float = tick_dt
	if state.stun_remaining_sec > 0.0:
		var consumed: float = minf(eff_dt, state.stun_remaining_sec)
		state.stun_remaining_sec -= consumed
		eff_dt -= consumed
		if eff_dt <= STUN_EPS:
			return 0

	# 3. 攻速充能与本 tick 攻击次数计算（读取 Balance 参数，零硬编码）
	var speed_bonus: float = state.buffs.get_stat_bonus("atk_speed_pct") if state.buffs != null else 0.0
	var interval: float = maxf(bal.min_atk_interval, state.stats.atk_interval / (1.0 + speed_bonus))
	state.atk_progress += eff_dt / interval
	var attacks: int = int(floor(state.atk_progress))
	state.atk_progress -= float(attacks)

	if attacks <= 0:
		return 0

	# 4. Q6 混合粒度结算：前 hybrid_individual_attacks (8) 次逐次结算，其余按二项分布聚合
	var max_individual: int = bal.hybrid_individual_attacks
	var max_kills: int = bal.max_kills_per_tick
	var individual_count: int = mini(attacks, max_individual)
	var aggregate_count: int = attacks - individual_count
	var kills_this_tick: int = 0
	var cond_bonus_log: float = state.get_conditional_damage_bonus_log()
	var crit_only_mult: float = 1.0
	if strengths.has(KIND_CRIT_ONLY):
		crit_only_mult = lerpf(1.0, bal.mech_crit_only_non_crit_mult, float(strengths[KIND_CRIT_ONLY]))

	# 4.1 逐击结算（仅使用 state.rng.combat 独立战斗流）
	for _i: int in range(individual_count):
		if kills_this_tick >= max_kills:
			break
		if strengths.has(KIND_BACKLASH):
			state.backlash_stacks += float(strengths[KIND_BACKLASH])
			if state.backlash_stacks >= float(bal.mech_backlash_max_stacks):
				state.backlash_stacks -= float(bal.mech_backlash_max_stacks)
				state.stun_remaining_sec = bal.mech_backlash_stun_seconds * float(strengths[KIND_BACKLASH])
				break
		var hit_info: Dictionary = state.stats.roll_hit(state.rng.combat)
		var dmg_log: float = float(hit_info["damage_log"]) + cond_bonus_log
		var is_crit: bool = bool(hit_info["is_crit"])
		if strengths.has(KIND_CRIT_ONLY) and not is_crit:
			var before_log: float = dmg_log
			dmg_log += NumScript.from_float(crit_only_mult)
			state.record_mech_absorbed(KIND_CRIT_ONLY, NumScript.sub(before_log, dmg_log))
		kills_this_tick += _apply_hit_damage(dmg_log, is_crit, 1, state, queue, kills_this_tick, max_kills)

	# 4.2 超额攻击按二项分布 Binomial(aggregate_count, eff_crit) 聚合结算 (Q6)
	if aggregate_count > 0 and kills_this_tick < max_kills and state.stun_remaining_sec <= 0.0:
		var eff_crit: float = state.stats.get_effective_crit_rate()
		var crits: int = state.rng.combat.sample_binomial(aggregate_count, eff_crit)
		var normals: int = aggregate_count - crits
		var base_dmg: float = state.stats.get_base_hit_damage_log() + cond_bonus_log
		var crit_dmg: float = base_dmg + NumScript.from_float(state.stats.crit_mult)
		var normal_unit: float = base_dmg
		if strengths.has(KIND_CRIT_ONLY):
			normal_unit = base_dmg + NumScript.from_float(crit_only_mult)

		var total_norm_log: float = normal_unit + NumScript.from_float(float(normals)) if normals > 0 else NumScript.ZERO
		var total_crit_log: float = crit_dmg + NumScript.from_float(float(crits)) if crits > 0 else NumScript.ZERO
		var batch_total_dmg: float = NumScript.add(total_norm_log, total_crit_log)

		if strengths.has(KIND_CRIT_ONLY) and normals > 0:
			var raw_norm_log: float = base_dmg + NumScript.from_float(float(normals))
			state.record_mech_absorbed(KIND_CRIT_ONLY, NumScript.sub(raw_norm_log, total_norm_log))

		if strengths.has(KIND_BACKLASH):
			state.backlash_stacks += float(aggregate_count) * float(strengths[KIND_BACKLASH])
			if state.backlash_stacks >= float(bal.mech_backlash_max_stacks):
				state.backlash_stacks = fmod(state.backlash_stacks, float(bal.mech_backlash_max_stacks))
				state.stun_remaining_sec = bal.mech_backlash_stun_seconds * float(strengths[KIND_BACKLASH])

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

## 吞金：min(余额 × 比例 × 强度 × dt, 近期每秒收入 × 上限 × 强度 × dt)，负债护印可减免
func _apply_gold_eat(dt: float, eat_strength: float, state: SimStateScript) -> void:
	var bal: BalanceScript = state.balance
	var str_eff: float = eat_strength * state.get_gold_eat_factor()
	if str_eff <= 0.0:
		return
	var eat_from_bal_log: float = state.gold + NumScript.from_float(str_eff * bal.mech_gold_eat_balance_rate * dt)
	var max_eat_from_inc_log: float = state.recent_income_per_sec_log + NumScript.from_float(str_eff * bal.mech_gold_eat_income_cap * dt)
	var actual_eat_log: float = NumScript.min_num(eat_from_bal_log, max_eat_from_inc_log)
	if actual_eat_log != NumScript.ZERO:
		state.gold = NumScript.sub(state.gold, actual_eat_log)
		state.record_mech_absorbed(KIND_GOLD_EAT, actual_eat_log)

## 结算词条派生伤害（连锁闪电/落地即爆等）：真实扣减当前怪血量，受单 tick 击杀上限约束，返回击杀数
## 触发类伤害不叠反噬；只吃暴击区间按玩家自身暴击率独立判定 (§7.1)
func apply_derived_damage(dmg_log: float, state: SimStateScript, queue: EventQueueScript) -> int:
	var bal: BalanceScript = state.balance
	var strengths: Dictionary = BandRulesScript.get_strengths(state.get_active_stage(), bal)
	var final_dmg: float = dmg_log
	if strengths.has(KIND_CRIT_ONLY):
		var is_crit: bool = state.rng.combat.roll_chance(state.stats.get_effective_crit_rate())
		if not is_crit:
			var mult: float = lerpf(1.0, bal.mech_crit_only_non_crit_mult, float(strengths[KIND_CRIT_ONLY]))
			var before_log: float = final_dmg
			final_dmg += NumScript.from_float(mult)
			state.record_mech_absorbed(KIND_CRIT_ONLY, NumScript.sub(before_log, final_dmg))
	return _apply_hit_damage(final_dmg, false, 1, state, queue, 0, bal.max_kills_per_tick)

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
	var bal: BalanceScript = state.balance
	var strengths: Dictionary = BandRulesScript.get_strengths(state.get_active_stage(), bal)
	var kills_added: int = 0
	var cur_dmg: float = dmg_log

	while cur_dmg > NumScript.ZERO and (current_kills + kills_added) < max_kills:
		# 护盾机制 (§7.1)：每次命中至多削掉 strip_cap 的护盾；护盾未破时整击被吸收
		if state.mob_shield_cur_log > NumScript.ZERO:
			var allowed_strip: float = state.mob_shield_strip_cap_log + NumScript.from_float(float(maxi(1, hit_count)))
			var actual_strip: float = NumScript.min_num(cur_dmg, allowed_strip)
			state.record_mech_absorbed(KIND_SHIELD, actual_strip)
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

		# 分身机制 (§7.1)：Boss 血量首次降至触发线时分裂，需全部击杀
		if state.is_boss and strengths.has(KIND_CLONE) and not state.boss_clone_triggered:
			var trigger_hp_log: float = state.mob_max_hp_log + NumScript.from_float(bal.mech_clone_trigger_hp_ratio)
			var next_hp_log: float = NumScript.sub(state.mob_current_hp_log, cur_dmg)
			if next_hp_log <= trigger_hp_log:
				state.boss_clone_triggered = true
				var split_str: float = float(strengths[KIND_CLONE])
				state.boss_clones_remaining = maxi(1, int(round(float(bal.mech_clone_split_count - 1) * split_str)))
				state.mob_current_hp_log = trigger_hp_log
				break

		if cur_dmg >= state.mob_current_hp_log:
			var overflow_dmg: float = NumScript.sub(cur_dmg, state.mob_current_hp_log)
			if state.is_boss and state.boss_clones_remaining > 0:
				state.boss_clones_remaining -= 1
				state.mob_current_hp_log = state.mob_max_hp_log + NumScript.from_float(bal.mech_clone_trigger_hp_ratio)
				cur_dmg = overflow_dmg
				continue

			if not strengths.is_empty():
				state.record_mech_dealt(state.mob_current_hp_log)

			kills_added += 1
			state.mobs_killed_total += 1
			var killed_stage: int = state.get_active_stage()
			var killed_was_boss: bool = state.is_boss
			var killed_max_hp: float = state.mob_max_hp_log
			var mob_gold_log: float = bal.get_mob_gold_log(killed_stage)

			state.add_income(mob_gold_log, queue)

			# 暗金雨充能 (§2.4)：下一次击杀掉落 ×N 且品质保底
			var drop_mult: int = 1
			var rarity_floor: int = 0
			if state.buffs.consume_charge(UNIQUE_RAIN_CHARGE_KEY):
				drop_mult = bal.unique_rain_drop_mult
				rarity_floor = bal.unique_rain_rarity_floor

			var drops: Array[ItemInstanceScript] = state.loot_roller.roll_loot_for_kill(
				killed_stage,
				killed_was_boss,
				state,
				queue,
				drop_mult,
				rarity_floor
			)
			var kill_total_gold_log: float = mob_gold_log
			for item: ItemInstanceScript in drops:
				if state.filter.should_keep(item):
					state.inventory.add_item(item, state, queue)
					state.note_item_kept(item, queue)
				else:
					var smelted_log: float = SmelterScript.smelt_item(item, state, queue)
					kill_total_gold_log = NumScript.add(kill_total_gold_log, smelted_log)

			if not strengths.is_empty():
				var instant_rate_log: float = kill_total_gold_log - NumScript.from_float(maxf(bal.mech_income_min_interval, state.stats.atk_interval))
				state.recent_income_per_sec_log = NumScript.add(
					state.recent_income_per_sec_log + NumScript.from_float(1.0 - bal.mech_income_ema_new),
					instant_rate_log + NumScript.from_float(bal.mech_income_ema_new)
				)

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
			strengths = BandRulesScript.get_strengths(state.get_active_stage(), bal)
			cur_dmg = overflow_dmg
		else:
			if not strengths.is_empty():
				state.record_mech_dealt(cur_dmg)
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
