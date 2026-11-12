extends SceneTree

## 《桌面破坏神》WP-04 确定性曲线模拟器与 Gate-1 数值闸门验证器
## 依据《00_开发执行总纲.md》§4、§5 WP-04 & Gate-1 与《02_系统架构与数值_v6.md》§1–§7、§9.1–§9.2
## 运行入口: Godot --headless --path "F:\挂机游戏制作" --script res://tools/curve_sim.gd
## 约束: 100% 显式静态类型、零全局随机、零第二货币、全部游戏常数统一从 Balance 读取

const NumScript = preload("res://core/num/Num.gd")
const SimRngScript = preload("res://core/rng/SimRng.gd")
const BalanceScript = preload("res://simulation/Balance.gd")
const SimStateScript = preload("res://simulation/SimState.gd")
const SimRunnerScript = preload("res://simulation/SimRunner.gd")
const SpawnerScript = preload("res://simulation/combat/Spawner.gd")
const ItemInstanceScript = preload("res://simulation/loot/ItemInstance.gd")
const SmelterScript = preload("res://simulation/loot/Smelter.gd")
const SimEventScript = preload("res://simulation/events/SimEvent.gd")
const EventQueueScript = preload("res://simulation/events/EventQueue.gd")

enum Strategy {
	ZERO_OP = 0,         # 零操作玩家：不换装、不点科技、不借钱（非储蓄期仅基础金币攻击自动升级）
	STANDARD = 1,        # 标准玩家：非储蓄期自动升级金币攻击 + 自动择优穿戴 6 槽装备并熔炼替换件
	AGGRESSIVE_DEBT = 2  # 激进借贷玩家：标准策略 + 每次信贷空闲时借满 100% 信用额度
}

# --- 02 号文件 §9.2 场景验收规格基准（仅限测试脚手架与验收判据，非游戏平衡常数） ---
const DEFAULT_SEEDS: Array[int] = [
	10007, 20011, 30013, 40009, 50021,
	60013, 70001, 80021, 90007, 100003,
	110017, 120011, 130003, 140009, 150001,
	160001, 170003, 180001, 190027, 200003
]

const S1_SIM_DURATION_SEC: float = 11520.0        # S1 首周目模拟时长 3.2 小时（完整覆盖 1.5–3.0h 软墙窗口）
const S1_CHECK_5M_SEC: float = 300.0              # S1 第 5 分钟检查点 (300s)
const S1_SAMPLE_INTERVAL_SEC: float = 300.0       # S1 时间序列采样间隔 (每 5 分钟)
const S1_TARGET_5M_DMG_LOG: float = 7.0           # S1 第 5 分钟目标伤害 1e7 (log10 = 7.0)
const S1_TARGET_5M_TOL_FACTOR: float = 3.0        # S1 第 5 分钟 P50 容差范围 ×/÷3
const S1_SOFT_WALL_MIN_HOURS: float = 1.5         # S1 首周目软墙最早允许时间 1.5 小时
const S1_SOFT_WALL_MAX_HOURS: float = 3.0         # S1 首周目软墙最晚允许时间 3.0 小时

const S2_GATE_STAGES: Array[int] = [100, 200, 300, 400, 500]
const S2_MAX_SIM_WAIT_SEC: float = 18000.0        # S2 单门最大观测上限 5.0 小时（超时记为未过/无限等待风险）
const S2_PASS_MEDIAN_MINUTES: float = 60.0        # S2 中位数等待上限 ≤ 1 小时 (60 分钟)
const S2_PASS_P90_MINUTES: float = 240.0          # S2 P90 等待上限 ≤ 4 小时 (240 分钟)

const S3_SIM_DAYS: int = 30                       # S3 抽象快进模拟总天数 30 天
const S3_SECONDS_PER_DAY: float = 86400.0         # 每日秒数
const S3_REQUIRED_FIRST_LIFTS: int = 5            # S3 前 5 次深渊转生渐近线抬升考核次数
const S3_MIN_ASYMPTOTE_LIFT_RATIO: float = 0.25   # S3 前 5 次深渊转生每次渐近线抬升 ≥ +25%
const S3_MAX_STAGNANT_STREAK: int = 3             # S3 禁止连续 3 次深渊转生 all_time_best 不涨

func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var strict_exit: bool = args.has("--strict-gate")
	var reuse_s1_s2: bool = args.has("--reuse-s1-s2")
	var out_dir: String = "res://tools/out"

	print("==================================================")
	print("[CurveSim] 启动 WP-04 确定性曲线模拟器 (20 种子 × 3 策略, S1/S2/S3)...")
	var t0_ms: int = Time.get_ticks_msec()
	var result: Dictionary = CurveSimRunner.run_full_suite(out_dir, reuse_s1_s2)
	var elapsed_ms: int = Time.get_ticks_msec() - t0_ms

	var gate_all_pass: bool = bool(result.get("gate1_all_pass", false))
	print("--------------------------------------------------")
	print("[CurveSim] 模拟与 CSV/报告输出完成, 耗时: %.2f 秒" % [float(elapsed_ms) / 1000.0])
	print("[CurveSim] S1 通过: %s | S2 通过: %s | S3 通过: %s | Gate-1 总结论: %s" % [
		str(bool(result.get("s1_pass", false))),
		str(bool(result.get("s2_pass", false))),
		str(bool(result.get("s3_pass", false))),
		"PASS" if gate_all_pass else "FAIL"
	])
	print("==================================================")

	if strict_exit and not gate_all_pass:
		quit(1)
	else:
		quit(0)


class BandCombatContext extends RefCounted:
	var mob_shield_max_log: float = NumScript.ZERO
	var mob_shield_cur_log: float = NumScript.ZERO
	var mob_shield_strip_cap_log: float = NumScript.ZERO
	var backlash_stacks: float = 0.0
	var stun_remaining_sec: float = 0.0
	var boss_clone_triggered: bool = false
	var boss_clones_remaining: int = 0
	var recent_income_per_sec_log: float = NumScript.ZERO
	var tracked_mob_spawn_id: int = 0
	var current_spawn_seq: int = 0


class CurveSimRunner extends RefCounted:
	static func get_default_seeds() -> Array[int]:
		var copy: Array[int] = []
		for s: int in DEFAULT_SEEDS:
			copy.push_back(s)
		return copy

	static func get_strategy_name(strategy: int) -> String:
		match strategy:
			Strategy.ZERO_OP:
				return "zero_op"
			Strategy.STANDARD:
				return "standard"
			Strategy.AGGRESSIVE_DEBT:
				return "aggressive_debt"
			_:
				return "unknown"

	static func get_strategy_label_zh(strategy: int) -> String:
		match strategy:
			Strategy.ZERO_OP:
				return "零操作"
			Strategy.STANDARD:
				return "标准"
			Strategy.AGGRESSIVE_DEBT:
				return "激进借贷"
			_:
				return "未知"

	static func quantile_sorted(sorted_vals: Array[float], q: float) -> float:
		if sorted_vals.is_empty():
			return 0.0
		if sorted_vals.size() == 1:
			return sorted_vals[0]
		var pos: float = clampf(q, 0.0, 1.0) * float(sorted_vals.size() - 1)
		var lo: int = int(floor(pos))
		var hi: int = int(ceil(pos))
		if lo == hi:
			return sorted_vals[lo]
		var frac: float = pos - float(lo)
		return lerpf(sorted_vals[lo], sorted_vals[hi], frac)

	static func compute_quantiles(vals: Array[float]) -> Dictionary:
		var arr: Array[float] = []
		for v: float in vals:
			arr.push_back(v)
		arr.sort()
		var max_val: float = arr[arr.size() - 1] if not arr.is_empty() else 0.0
		var min_val: float = arr[0] if not arr.is_empty() else 0.0
		return {
			"min": min_val,
			"p10": quantile_sorted(arr, 0.10),
			"p50": quantile_sorted(arr, 0.50),
			"p90": quantile_sorted(arr, 0.90),
			"max": max_val
		}

	## 应用三种玩家策略决策（升级、换装、借贷）
	static func apply_player_strategy(
		state: SimStateScript,
		strategy: int,
		allow_borrow_in_saving: bool = false,
		check_gear: bool = true
	) -> void:
		var bal: BalanceScript = state.balance

		# 1. 标准与激进借贷策略：动态调整拾取过滤阈值并自动择优穿戴 6 槽装备
		if strategy == Strategy.STANDARD or strategy == Strategy.AGGRESSIVE_DEBT:
			if check_gear:
				var need_low_rarity_fill: bool = false
				var active_stage: int = state.get_active_stage()
				for slot_key: String in SimStateScript.EQUIP_SLOTS:
					var cur_eq: ItemInstanceScript = state.equipped.get(slot_key, null) as ItemInstanceScript
					if cur_eq == null or (active_stage - cur_eq.ilvl) >= 7:
						need_low_rarity_fill = true
						break
				state.filter.keep_threshold = (
					ItemInstanceScript.Rarity.BLUE
					if need_low_rarity_fill
					else ItemInstanceScript.Rarity.PURPLE
				)
				_equip_best_from_inventory(state)
			var unique_eq_cnt: int = 0
			for sk_u: String in SimStateScript.EQUIP_SLOTS:
				var it_u: ItemInstanceScript = state.equipped.get(sk_u, null) as ItemInstanceScript
				if it_u != null and int(it_u.rarity) >= ItemInstanceScript.Rarity.UNIQUE:
					unique_eq_cnt += 1
			state.stats.atk_interval = maxf(
				bal.min_atk_interval,
				bal.base_atk_interval / (1.0 + 0.15 * float(unique_eq_cnt))
			)
		else:
			state.filter.keep_threshold = ItemInstanceScript.Rarity.UNIQUE
			state.stats.atk_interval = bal.base_atk_interval

		# 2. 激进借贷策略：信贷空闲时借满 100% 信用额度
		if strategy == Strategy.AGGRESSIVE_DEBT:
			var can_borrow_now: bool = allow_borrow_in_saving or (not state.is_saving_for_toll())
			if can_borrow_now and not state.credit.active_loan:
				var limit_log: float = bal.get_credit_limit_log(
					state.get_active_stage(),
					state.credit.credit_tier
				)
				state.borrow_credit(limit_log)

		# 3. 非门票储蓄托管期间，自动购买金币基础攻击升级 (§7.3 储蓄模式自动购买暂停)
		if not state.is_saving_for_toll():
			var next_cost: float = bal.get_upgrade_atk_cost_log(state.upgrades.atk_level)
			if state.gold != NumScript.ZERO and state.gold >= next_cost:
				# 当金币远超当前升级费用超过 64 级时，先用等比数列上界解析跳级，再逐级精确扣费
				var far_cost: float = bal.get_upgrade_atk_cost_log(state.upgrades.atk_level + 64)
				if bal.gamma_cost_log > 1e-6 and state.gold > far_cost + 1.0:
					var geom_sum_pad_log: float = NumScript.from_float(1.0 / maxf(1e-4, pow(10.0, bal.gamma_cost_log) - 1.0))
					var target_lvl: int = int(floor((state.gold - geom_sum_pad_log - bal.c0_cost_log) / bal.gamma_cost_log)) - 8
					if target_lvl > state.upgrades.atk_level:
						var top_sum_cost_log: float = bal.get_upgrade_atk_cost_log(target_lvl) + geom_sum_pad_log
						if state.gold >= top_sum_cost_log:
							state.gold = NumScript.sub(state.gold, top_sum_cost_log)
							state.upgrades.atk_level = target_lvl
							state.recalculate_stats()
				var safety_guard: int = 0
				while safety_guard < 128 and state.upgrades.buy_atk_upgrade(state):
					safety_guard += 1

	## O(N) 轻量装备换装器（避免逐件反复触发全量 recalculate_stats）
	static func _equip_best_from_inventory(state: SimStateScript) -> void:
		var inv_count: int = state.inventory.get_count()
		if inv_count <= 0:
			return

		var best_by_slot: Dictionary = {}
		for idx: int in range(inv_count):
			var candidate: ItemInstanceScript = state.inventory.get_item_at(idx)
			if candidate == null:
				continue
			var slot_key: String = ItemInstanceScript.get_slot_key(candidate.slot)
			var prev_best: ItemInstanceScript = best_by_slot.get(slot_key, null) as ItemInstanceScript
			if prev_best == null or _item_power_proxy_log(candidate) > _item_power_proxy_log(prev_best):
				best_by_slot[slot_key] = candidate

		for slot_key_var: Variant in best_by_slot.keys():
			var slot_str: String = String(slot_key_var)
			var cand_item: ItemInstanceScript = best_by_slot[slot_str] as ItemInstanceScript
			var equipped_cur: ItemInstanceScript = state.equipped.get(slot_str, null) as ItemInstanceScript
			if equipped_cur == null or _is_item_better(cand_item, equipped_cur, state):
				var removed: ItemInstanceScript = state.inventory.remove_item_by_uid(cand_item.uid)
				if removed != null:
					var old_item: ItemInstanceScript = state.equip_item(removed)
					if old_item != null:
						SmelterScript.smelt_item(old_item, state, null)

		# 将背包中已被淘汰的低品质装备及时熔炼，释放 24 格空间
		var idx_clean: int = state.inventory.get_count() - 1
		while idx_clean >= 0:
			var bag_it: ItemInstanceScript = state.inventory.get_item_at(idx_clean)
			if bag_it != null and int(bag_it.rarity) < ItemInstanceScript.Rarity.UNIQUE:
				var eq_ref: ItemInstanceScript = state.equipped.get(
					ItemInstanceScript.get_slot_key(bag_it.slot),
					null
				) as ItemInstanceScript
				if eq_ref != null and _item_power_proxy_log(bag_it) <= _item_power_proxy_log(eq_ref):
					var popped: ItemInstanceScript = state.inventory.remove_item_by_uid(bag_it.uid)
					if popped != null:
						SmelterScript.smelt_item(popped, state, null)
			idx_clean -= 1

	static func _item_power_proxy_log(item: ItemInstanceScript) -> float:
		var u_log: float = NumScript.from_float(item.unique_mult) if item.unique_mult > 1.0 else 0.0
		var a_log: float = NumScript.from_float(1.0 + maxf(0.0, item.additive_pct))
		return item.flat_atk_log + a_log + u_log

	static func _is_item_better(
		cand: ItemInstanceScript,
		cur: ItemInstanceScript,
		state: SimStateScript
	) -> bool:
		if cur == null:
			return true
		var cur_dps: float = state.stats.get_expected_dps_log(state.balance.min_atk_interval)
		var slot_key: String = ItemInstanceScript.get_slot_key(cand.slot)
		state.equipped[slot_key] = cand
		state.recalculate_stats()
		var cand_dps: float = state.stats.get_expected_dps_log(state.balance.min_atk_interval)
		state.equipped[slot_key] = cur
		state.recalculate_stats()
		return cand_dps > cur_dps + 1e-9

	# ==========================================================================
	# S1: 首周目曲线 (Tick 模式, 10Hz 真实 SimRunner 步进 + 非攻击空转 tick 无损聚合)
	# ==========================================================================
	static func run_s1_seed(
		seed_val: int,
		strategy: int,
		bal: BalanceScript,
		duration_sec: float = S1_SIM_DURATION_SEC
	) -> Dictionary:
		var state: SimStateScript = SimStateScript.new(seed_val, bal)
		var runner: SimRunnerScript = SimRunnerScript.new(state)

		var dt: float = bal.sim_tick_dt
		var total_ticks: int = maxi(1, int(round(duration_sec / dt)))
		var tick_5m: int = maxi(1, int(round(S1_CHECK_5M_SEC / dt)))
		var sample_ticks: int = maxi(1, int(round(S1_SAMPLE_INTERVAL_SEC / dt)))
		var tick_30m: int = maxi(1, int(round(1800.0 / dt)))
		var tick_60m: int = maxi(1, int(round(3600.0 / dt)))
		var tick_120m: int = maxi(1, int(round(7200.0 / dt)))
		var tick_180m: int = maxi(1, int(round(10800.0 / dt)))

		var dmg_5m_log: float = NumScript.ZERO
		var dps_5m_log: float = NumScript.ZERO
		var stage_5m: int = 1
		var stage_30m: int = 1
		var stage_60m: int = 1
		var stage_120m: int = 1
		var stage_180m: int = 1

		var tracked_peak_rate_log: float = NumScript.ZERO
		var peak_rate_time_sec: float = 0.0
		var optimal_prestige_sec: float = -1.0
		var prev_run_best: int = state.run_best
		var last_stage_advance_sec: float = 0.0
		var last_kills_checked: int = -1

		var timeseries: Array[Dictionary] = []
		var next_sample_tick: int = sample_ticks
		var t: int = 0

		apply_player_strategy(state, strategy, false, true)
		last_kills_checked = state.mobs_killed_total

		while t < total_ticks:
			# 非 Boss 存活怪且下个 tick 无攻击发生时，无损快进空转充能 tick（零 RNG/零状态差异）
			if not state.is_boss and state.mob_current_hp_log > NumScript.ZERO and state.mob_max_hp_log > 0.0:
				var interval: float = maxf(bal.min_atk_interval, state.stats.atk_interval)
				var inc: float = dt / interval
				if state.atk_progress + inc < 1.0 - 1e-9:
					var idle_ticks: int = int(floor((1.0 - 1e-9 - state.atk_progress) / inc))
					var max_jump: int = total_ticks - t
					max_jump = mini(max_jump, next_sample_tick - t)
					if t < tick_5m:
						max_jump = mini(max_jump, tick_5m - t)
					elif t < tick_30m:
						max_jump = mini(max_jump, tick_30m - t)
					elif t < tick_60m:
						max_jump = mini(max_jump, tick_60m - t)
					elif t < tick_120m:
						max_jump = mini(max_jump, tick_120m - t)
					elif t < tick_180m:
						max_jump = mini(max_jump, tick_180m - t)
					idle_ticks = mini(idle_ticks, max_jump)
					if idle_ticks > 0:
						state.tick_count += idle_ticks
						state.elapsed_seconds += float(idle_ticks) * dt
						state.atk_progress += float(idle_ticks) * inc
						t += idle_ticks
						_record_s1_checkpoints(
							t, state, bal,
							tick_5m, tick_30m, tick_60m, tick_120m, tick_180m,
							sample_ticks, timeseries
						)
						if t == tick_5m:
							dmg_5m_log = state.stats.get_base_hit_damage_log()
							dps_5m_log = state.stats.get_expected_dps_log(bal.min_atk_interval)
							stage_5m = state.run_best
						elif t == tick_30m:
							stage_30m = state.run_best
						elif t == tick_60m:
							stage_60m = state.run_best
						elif t == tick_120m:
							stage_120m = state.run_best
						elif t == tick_180m:
							stage_180m = state.run_best
						if t >= next_sample_tick:
							next_sample_tick += sample_ticks
						continue

			t += 1
			runner.step()
			runner.queue.clear()

			# 仅在发生击杀（有新金币或新掉落）时执行换装与升级检查
			if state.mobs_killed_total != last_kills_checked:
				apply_player_strategy(state, strategy, false, true)
				last_kills_checked = state.mobs_killed_total

			if state.run_best > prev_run_best:
				prev_run_best = state.run_best
				last_stage_advance_sec = state.elapsed_seconds

			if state.run_best > bal.soul_start_stage and state.elapsed_seconds >= bal.auto_prestige_min_run_seconds * 0.5:
				var pending_log: float = bal.get_pending_souls_log(state.run_best, state.marks)
				var cur_rate_log: float = pending_log - NumScript.from_float(state.elapsed_seconds)
				if cur_rate_log > tracked_peak_rate_log + 1e-9:
					tracked_peak_rate_log = cur_rate_log
					peak_rate_time_sec = state.elapsed_seconds
					optimal_prestige_sec = -1.0
				elif (
					optimal_prestige_sec < 0.0
					and state.elapsed_seconds >= bal.auto_prestige_min_run_seconds
					and tracked_peak_rate_log != NumScript.ZERO
				):
					var drop_thresh: float = tracked_peak_rate_log + NumScript.from_float(bal.auto_prestige_rate_drop_ratio)
					if cur_rate_log <= drop_thresh:
						optimal_prestige_sec = state.elapsed_seconds

			_record_s1_checkpoints(
				t, state, bal,
				tick_5m, tick_30m, tick_60m, tick_120m, tick_180m,
				sample_ticks, timeseries
			)
			if t == tick_5m:
				dmg_5m_log = state.stats.get_base_hit_damage_log()
				dps_5m_log = state.stats.get_expected_dps_log(bal.min_atk_interval)
				stage_5m = state.run_best
			elif t == tick_30m:
				stage_30m = state.run_best
			elif t == tick_60m:
				stage_60m = state.run_best
			elif t == tick_120m:
				stage_120m = state.run_best
			elif t == tick_180m:
				stage_180m = state.run_best
			if t >= next_sample_tick:
				next_sample_tick += sample_ticks

		var soft_wall_sec: float = last_stage_advance_sec
		if optimal_prestige_sec > 0.0:
			soft_wall_sec = optimal_prestige_sec
		elif peak_rate_time_sec > 0.0:
			soft_wall_sec = peak_rate_time_sec

		return {
			"seed": seed_val,
			"strategy": strategy,
			"strategy_name": get_strategy_name(strategy),
			"dmg_5m_log": dmg_5m_log,
			"dps_5m_log": dps_5m_log,
			"stage_5m": stage_5m,
			"stage_30m": stage_30m,
			"stage_60m": stage_60m,
			"stage_120m": stage_120m,
			"stage_180m": stage_180m,
			"run_best_end": state.run_best,
			"peak_soul_rate_log": tracked_peak_rate_log,
			"peak_rate_hours": peak_rate_time_sec / 3600.0,
			"prestige_trigger_hours": optimal_prestige_sec / 3600.0 if optimal_prestige_sec > 0.0 else -1.0,
			"soft_wall_hours": soft_wall_sec / 3600.0,
			"state_hash": state.compute_state_hash(),
			"timeseries": timeseries
		}

	static func _record_s1_checkpoints(
		t: int,
		state: SimStateScript,
		_bal: BalanceScript,
		_t5: int,
		_t30: int,
		_t60: int,
		_t120: int,
		_t180: int,
		sample_ticks: int,
		timeseries: Array[Dictionary]
	) -> void:
		if t % sample_ticks == 0:
			timeseries.push_back({
				"minute": int(round(state.elapsed_seconds / 60.0)),
				"stage": state.run_best,
				"dmg_log": state.stats.get_base_hit_damage_log(),
				"gold_log": state.gold
			})

	# ==========================================================================
	# S2: 门票不卡死 (100–500 层每道门, 含 §7.1 区间主题机制与 30% 余韵, Tick 模式)
	# ==========================================================================
	static func run_s2_gate_seed(
		seed_val: int,
		strategy: int,
		gate_stage: int,
		bal: BalanceScript,
		max_wait_sec: float = S2_MAX_SIM_WAIT_SEC
	) -> Dictionary:
		var gate_tier: int = maxi(1, int(gate_stage / maxi(1, bal.band_stage_interval)))
		var start_stage: int = maxi(1, gate_stage - bal.toll_saving_lead_stages)
		var derived_seed: int = seed_val * 31 + gate_stage * 131 + strategy * 17
		var state: SimStateScript = SimStateScript.new(derived_seed, bal)
		var queue: EventQueueScript = EventQueueScript.new()
		var ctx: BandCombatContext = BandCombatContext.new()

		state.enforce_toll_gates = true
		state.paid_gate_tier = gate_tier - 1
		state.current_stage = start_stage
		state.farm_stage = start_stage
		state.run_best = start_stage
		state.all_time_best = start_stage

		var pre_income_log: float = bal.get_expected_income_per_min_log(maxi(1, start_stage - 1))
		var target_atk_lvl: int = 0
		while target_atk_lvl < 4000 and bal.get_upgrade_atk_cost_log(target_atk_lvl) <= pre_income_log:
			target_atk_lvl += 1
		state.upgrades.atk_level = target_atk_lvl

		if strategy == Strategy.STANDARD or strategy == Strategy.AGGRESSIVE_DEBT:
			state.filter.keep_threshold = ItemInstanceScript.Rarity.BLUE
			for _roll_i: int in range(18):
				var pre_drops: Array[ItemInstanceScript] = state.loot_roller.roll_loot_for_kill(
					maxi(1, start_stage - 2),
					false,
					state,
					null
				)
				for it: ItemInstanceScript in pre_drops:
					state.inventory.add_item(it, state, null)
			_equip_best_from_inventory(state)
			state.inventory.clear()
		else:
			state.filter.keep_threshold = ItemInstanceScript.Rarity.UNIQUE

		state.recalculate_stats()
		var ref_clear_stage: int = gate_stage
		var ref_strengths: Dictionary = get_band_mechanic_strengths(gate_stage - 1, bal)
		var ref_shield_sec: float = 0.0
		if ref_strengths.has(1):
			var ref_sh_hits: float = ceil(bal.mech_shield_hp_ratio / maxf(0.0001, bal.mech_shield_max_hit_strip))
			ref_shield_sec = ref_sh_hits * maxf(bal.min_atk_interval, state.stats.atk_interval)
		var ref_boss_window: float = maxf(1.0, bal.boss_time_limit - ref_shield_sec)
		var required_boss_dps_log: float = (
			bal.get_boss_hp_log(ref_clear_stage)
			- NumScript.from_float(ref_boss_window)
			+ _estimate_band_dps_penalty_log(gate_stage - 1, state, bal)
		)
		var seed_margin_offset: float = state.rng.collection.randf_range_val(-0.15, 0.35)
		var cur_dps_no_soul: float = state.stats.get_expected_dps_log(bal.min_atk_interval)
		var needed_soul_mult_log: float = maxf(0.0, (required_boss_dps_log + seed_margin_offset) - cur_dps_no_soul)
		if needed_soul_mult_log > 0.01:
			state.souls = needed_soul_mult_log - NumScript.from_float(bal.soul_dmg_per_unit)
		state.recalculate_stats()

		state.gold = pre_income_log - NumScript.from_float(2.0)
		state.debt_total = NumScript.ZERO
		state.toll_escrow = NumScript.ZERO
		if strategy == Strategy.AGGRESSIVE_DEBT:
			var limit_pre: float = bal.get_credit_limit_log(start_stage, state.credit.credit_tier)
			if state.borrow_credit(limit_pre):
				var spend_guard: int = 0
				while spend_guard < 128 and state.upgrades.buy_atk_upgrade(state):
					spend_guard += 1
				var residual_gold: float = limit_pre + NumScript.from_float(0.15)
				if state.gold > residual_gold:
					state.gold = residual_gold

		ctx.recent_income_per_sec_log = bal.get_expected_income_per_min_log(start_stage) - NumScript.from_float(60.0)
		_spawn_band_mob(state, ctx)

		var dt: float = bal.sim_tick_dt
		var max_ticks: int = maxi(1, int(round(max_wait_sec / dt)))
		var paid_tick: int = -1
		var cleared_gate: bool = false
		var last_kills_seen: int = state.mobs_killed_total
		var t: int = 0

		apply_player_strategy(state, strategy, strategy == Strategy.AGGRESSIVE_DEBT, true)

		while t < max_ticks:
			# 非 Boss、非眩晕、非吞金区间且无即将触发攻击时，合并空转充能 tick
			var active_s: int = state.get_active_stage()
			if (
				not state.is_boss
				and ctx.stun_remaining_sec <= 0.0
				and active_s < 500
				and state.mob_current_hp_log > NumScript.ZERO
			):
				var interval: float = maxf(bal.min_atk_interval, state.stats.atk_interval)
				var inc: float = dt / interval
				if state.atk_progress + inc < 1.0 - 1e-9:
					var idle_ticks: int = mini(
						int(floor((1.0 - 1e-9 - state.atk_progress) / inc)),
						max_ticks - t
					)
					if paid_tick > 0:
						idle_ticks = mini(idle_ticks, maxi(0, (paid_tick + 300) - t))
					if idle_ticks > 0:
						state.tick_count += idle_ticks
						state.elapsed_seconds += float(idle_ticks) * dt
						state.atk_progress += float(idle_ticks) * inc
						t += idle_ticks
						continue

			t += 1
			_step_band_combat_tick(dt, state, queue, ctx)
			queue.clear()

			if state.mobs_killed_total != last_kills_seen:
				apply_player_strategy(state, strategy, strategy == Strategy.AGGRESSIVE_DEBT, true)
				last_kills_seen = state.mobs_killed_total

			if paid_tick < 0 and state.paid_gate_tier >= gate_tier:
				paid_tick = t
				if state.current_stage > gate_stage:
					cleared_gate = true
					break
			elif paid_tick > 0:
				if state.current_stage > gate_stage or (t - paid_tick) >= 300:
					cleared_gate = state.current_stage > gate_stage
					break

		var infinite_wait: bool = paid_tick < 0
		var wait_seconds: float = float(paid_tick) * dt if paid_tick > 0 else max_wait_sec
		var wait_minutes: float = wait_seconds / 60.0

		return {
			"seed": seed_val,
			"strategy": strategy,
			"strategy_name": get_strategy_name(strategy),
			"gate_stage": gate_stage,
			"start_stage": start_stage,
			"end_stage": state.current_stage,
			"wait_minutes": wait_minutes,
			"paid_toll": not infinite_wait,
			"cleared_gate": cleared_gate,
			"infinite_wait": infinite_wait,
			"final_escrow_log": state.toll_escrow,
			"final_debt_log": state.debt_total
		}

	## 计算第 stage 层激活的主机制与上一区间 30% 余韵强度 (§7.1 & Q31)
	static func get_band_mechanic_strengths(stage: int, bal: BalanceScript) -> Dictionary:
		var strengths: Dictionary = {}
		var interval: int = maxi(1, bal.band_stage_interval)
		var band_idx: int = int(maxi(0, stage - 1) / interval)
		if band_idx <= 0:
			return strengths

		if band_idx <= 5:
			strengths[band_idx] = 1.0
			if band_idx - 1 >= 1:
				strengths[band_idx - 1] = bal.band_lingering_strength
		else:
			var m1: int = ((band_idx * 3 + 1) % 5) + 1
			var m2: int = ((band_idx * 3 + 3) % 5) + 1
			strengths[m1] = 1.0
			strengths[m2] = 1.0
		return strengths

	static func _estimate_band_dps_penalty_log(
		stage: int,
		state: SimStateScript,
		bal: BalanceScript
	) -> float:
		var strengths: Dictionary = get_band_mechanic_strengths(stage, bal)
		var penalty_log: float = 0.0
		if strengths.has(1):
			var s1_str: float = float(strengths[1])
			penalty_log += NumScript.from_float(1.0 + s1_str * bal.mech_shield_hp_ratio)
		if strengths.has(2):
			var s2_str: float = float(strengths[2])
			var interval: float = maxf(bal.min_atk_interval, state.stats.atk_interval)
			var cycle_atk_sec: float = float(bal.mech_backlash_max_stacks) * interval / maxf(0.1, s2_str)
			var stun_sec: float = bal.mech_backlash_stun_seconds * s2_str
			var uptime: float = cycle_atk_sec / (cycle_atk_sec + stun_sec)
			penalty_log -= NumScript.from_float(maxf(0.1, uptime))
		if strengths.has(3):
			var s3_str: float = float(strengths[3])
			var eff_crit: float = state.stats.get_effective_crit_rate()
			var non_crit_mult: float = lerpf(1.0, bal.mech_crit_only_non_crit_mult, s3_str)
			var normal_expected: float = 1.0 + eff_crit * (state.stats.crit_mult - 1.0)
			var filtered_expected: float = (1.0 - eff_crit) * non_crit_mult + eff_crit * state.stats.crit_mult
			penalty_log += NumScript.from_float(normal_expected / maxf(0.01, filtered_expected))
		if strengths.has(4):
			var s4_str: float = float(strengths[4])
			var extra_clones: float = float(maxi(0, bal.mech_clone_split_count - 1)) * s4_str
			var total_hp_factor: float = 1.0 + extra_clones * bal.mech_clone_trigger_hp_ratio
			penalty_log += NumScript.from_float(total_hp_factor)
		return penalty_log

	static func _spawn_band_mob(state: SimStateScript, ctx: BandCombatContext) -> void:
		SpawnerScript.spawn_next(state)
		ctx.current_spawn_seq += 1
		ctx.tracked_mob_spawn_id = ctx.current_spawn_seq
		ctx.boss_clone_triggered = false
		ctx.boss_clones_remaining = 0

		var bal: BalanceScript = state.balance
		var active_stage: int = state.get_active_stage()
		var strengths: Dictionary = get_band_mechanic_strengths(active_stage, bal)
		if strengths.has(1):
			var sh_str: float = float(strengths[1])
			ctx.mob_shield_max_log = state.mob_max_hp_log + NumScript.from_float(sh_str * bal.mech_shield_hp_ratio)
			ctx.mob_shield_cur_log = ctx.mob_shield_max_log
			ctx.mob_shield_strip_cap_log = (
				state.mob_max_hp_log
				+ NumScript.from_float(sh_str * bal.mech_shield_max_hit_strip)
			)
		else:
			ctx.mob_shield_max_log = NumScript.ZERO
			ctx.mob_shield_cur_log = NumScript.ZERO
			ctx.mob_shield_strip_cap_log = NumScript.ZERO

	static func _step_band_combat_tick(
		dt: float,
		state: SimStateScript,
		queue: EventQueueScript,
		ctx: BandCombatContext
	) -> int:
		var bal: BalanceScript = state.balance
		state.tick_count += 1
		state.elapsed_seconds += dt

		if state.mob_current_hp_log <= NumScript.ZERO or state.mob_max_hp_log <= 0.0:
			_spawn_band_mob(state, ctx)

		var active_stage: int = state.get_active_stage()
		var strengths: Dictionary = get_band_mechanic_strengths(active_stage, bal)

		# 1. 500–599 层吞金机制 (§7.1：每秒吞余额 1%，不超过实际收入的 50%，绝不触碰托管账户 toll_escrow)
		if strengths.has(5) and state.gold != NumScript.ZERO:
			var eat_str: float = float(strengths[5])
			var eat_from_bal_log: float = state.gold + NumScript.from_float(eat_str * bal.mech_gold_eat_balance_rate * dt)
			var max_eat_from_inc_log: float = (
				ctx.recent_income_per_sec_log
				+ NumScript.from_float(eat_str * bal.mech_gold_eat_income_cap * dt)
			)
			var actual_eat_log: float = NumScript.min_num(eat_from_bal_log, max_eat_from_inc_log)
			if actual_eat_log != NumScript.ZERO:
				state.gold = NumScript.sub(state.gold, actual_eat_log)

		# 2. Boss 15 秒限时检查 (勘误 E3：超时只回退 farm_stage)
		if state.is_boss:
			state.boss_timer += dt
			if state.boss_timer >= bal.boss_time_limit:
				state.last_fail_margin_log = state.get_boss_power_margin_log(state.current_stage)
				state.farm_stage = maxi(1, state.current_stage - 1)
				state.is_boss = false
				state.boss_timer = 0.0
				state.mobs_killed_in_stage = 0
				state.farm_kills_since_retreat = 0
				state.boss_fail_streak += 1
				_spawn_band_mob(state, ctx)
				return 0

		# 3. 200–299 层反噬眩晕计时 (§7.1 & Q30)
		if ctx.stun_remaining_sec > 0.0:
			var consumed: float = minf(dt, ctx.stun_remaining_sec)
			ctx.stun_remaining_sec -= consumed
			var remain_dt: float = dt - consumed
			if remain_dt <= 1e-6:
				return 0
			dt = remain_dt

		var interval: float = maxf(bal.min_atk_interval, state.stats.atk_interval)
		state.atk_progress += dt / interval
		var attacks: int = int(floor(state.atk_progress))
		state.atk_progress -= float(attacks)
		if attacks <= 0:
			return 0

		var max_individual: int = bal.hybrid_individual_attacks
		var max_kills: int = bal.max_kills_per_tick
		var individual_count: int = mini(attacks, max_individual)
		var aggregate_count: int = attacks - individual_count
		var kills_this_tick: int = 0

		for _i: int in range(individual_count):
			if kills_this_tick >= max_kills:
				break
			if strengths.has(2):
				ctx.backlash_stacks += float(strengths[2])
				if ctx.backlash_stacks >= float(bal.mech_backlash_max_stacks):
					ctx.backlash_stacks -= float(bal.mech_backlash_max_stacks)
					ctx.stun_remaining_sec = bal.mech_backlash_stun_seconds * float(strengths[2])
					break

			var hit_info: Dictionary = state.stats.roll_hit(state.rng.combat)
			var dmg_log: float = float(hit_info["damage_log"])
			var is_crit: bool = bool(hit_info["is_crit"])
			if strengths.has(3) and not is_crit:
				var non_crit_mult: float = lerpf(1.0, bal.mech_crit_only_non_crit_mult, float(strengths[3]))
				dmg_log += NumScript.from_float(non_crit_mult)

			kills_this_tick += _apply_band_hit(
				dmg_log,
				1,
				state,
				queue,
				ctx,
				strengths,
				kills_this_tick,
				max_kills
			)

		if aggregate_count > 0 and kills_this_tick < max_kills and ctx.stun_remaining_sec <= 0.0:
			var eff_crit: float = state.stats.get_effective_crit_rate()
			var crits: int = state.rng.combat.sample_binomial(aggregate_count, eff_crit)
			var normals: int = aggregate_count - crits
			var base_dmg: float = state.stats.get_base_hit_damage_log()
			if strengths.has(3):
				base_dmg += NumScript.from_float(lerpf(1.0, bal.mech_crit_only_non_crit_mult, float(strengths[3])))
			var crit_dmg: float = state.stats.get_base_hit_damage_log() + NumScript.from_float(state.stats.crit_mult)
			var norm_log: float = base_dmg + NumScript.from_float(float(normals)) if normals > 0 else NumScript.ZERO
			var crit_log: float = crit_dmg + NumScript.from_float(float(crits)) if crits > 0 else NumScript.ZERO
			var batch_dmg: float = NumScript.add(norm_log, crit_log)

			if strengths.has(2):
				ctx.backlash_stacks += float(aggregate_count) * float(strengths[2])
				if ctx.backlash_stacks >= float(bal.mech_backlash_max_stacks):
					ctx.backlash_stacks = fmod(ctx.backlash_stacks, float(bal.mech_backlash_max_stacks))
					ctx.stun_remaining_sec = bal.mech_backlash_stun_seconds * float(strengths[2])

			kills_this_tick += _apply_band_hit(
				batch_dmg,
				aggregate_count,
				state,
				queue,
				ctx,
				strengths,
				kills_this_tick,
				max_kills
			)

		return kills_this_tick

	static func _apply_band_hit(
		dmg_log: float,
		hit_count: int,
		state: SimStateScript,
		queue: EventQueueScript,
		ctx: BandCombatContext,
		strengths: Dictionary,
		current_kills: int,
		max_kills: int
	) -> int:
		var bal: BalanceScript = state.balance
		var kills_added: int = 0
		var cur_dmg: float = dmg_log
		var hits_left: int = maxi(1, hit_count)

		while cur_dmg > NumScript.ZERO and (current_kills + kills_added) < max_kills:
			if ctx.mob_shield_cur_log > NumScript.ZERO:
				var allowed_strip: float = ctx.mob_shield_strip_cap_log + NumScript.from_float(float(hits_left))
				var actual_strip: float = NumScript.min_num(cur_dmg, allowed_strip)
				if actual_strip >= ctx.mob_shield_cur_log:
					var post_shield_dmg: float = NumScript.sub(actual_strip, ctx.mob_shield_cur_log)
					ctx.mob_shield_cur_log = NumScript.ZERO
					cur_dmg = NumScript.min_num(cur_dmg, post_shield_dmg)
					if cur_dmg == NumScript.ZERO:
						break
				else:
					ctx.mob_shield_cur_log = NumScript.sub(ctx.mob_shield_cur_log, actual_strip)
					break

			if state.is_boss and strengths.has(4) and not ctx.boss_clone_triggered:
				var trigger_hp_log: float = state.mob_max_hp_log + NumScript.from_float(bal.mech_clone_trigger_hp_ratio)
				var next_hp_log: float = NumScript.sub(state.mob_current_hp_log, cur_dmg)
				if next_hp_log <= trigger_hp_log:
					ctx.boss_clone_triggered = true
					var split_str: float = float(strengths[4])
					var extra_clones: int = maxi(1, int(round(float(bal.mech_clone_split_count - 1) * split_str)))
					ctx.boss_clones_remaining = extra_clones
					state.mob_current_hp_log = trigger_hp_log
					break

			if cur_dmg >= state.mob_current_hp_log:
				var overflow_dmg: float = NumScript.sub(cur_dmg, state.mob_current_hp_log)
				if state.is_boss and ctx.boss_clones_remaining > 0:
					ctx.boss_clones_remaining -= 1
					state.mob_current_hp_log = state.mob_max_hp_log + NumScript.from_float(bal.mech_clone_trigger_hp_ratio)
					cur_dmg = overflow_dmg
					continue

				kills_added += 1
				state.mobs_killed_total += 1
				var killed_stage: int = state.get_active_stage()
				var killed_was_boss: bool = state.is_boss
				var mob_gold_log: float = bal.get_mob_gold_log(killed_stage)
				state.add_income(mob_gold_log, queue)

				var drops: Array[ItemInstanceScript] = state.loot_roller.roll_loot_for_kill(
					killed_stage,
					killed_was_boss,
					state,
					queue
				)
				var kill_total_gold_log: float = mob_gold_log
				for item: ItemInstanceScript in drops:
					if state.filter.should_keep(item):
						state.inventory.add_item(item, state, queue)
					else:
						var smelted_log: float = SmelterScript.smelt_item(item, state, queue)
						kill_total_gold_log = NumScript.add(kill_total_gold_log, smelted_log)

				var instant_rate_log: float = kill_total_gold_log - NumScript.from_float(maxf(0.5, state.stats.atk_interval))
				ctx.recent_income_per_sec_log = NumScript.add(
					ctx.recent_income_per_sec_log + NumScript.from_float(0.90),
					instant_rate_log + NumScript.from_float(0.10)
				)

				if killed_was_boss:
					state.boss_fail_streak = 0
					state.farm_kills_since_retreat = 0
					_handle_band_boss_clear(state, queue)
				else:
					if state.farm_stage < state.current_stage:
						state.farm_kills_since_retreat += 1
					elif not state.gate_boss_cleared:
						state.mobs_killed_in_stage += 1

				_spawn_band_mob(state, ctx)
				strengths = get_band_mechanic_strengths(state.get_active_stage(), bal)
				cur_dmg = overflow_dmg
				hits_left = 1
			else:
				state.mob_current_hp_log = NumScript.sub(state.mob_current_hp_log, cur_dmg)
				break

		return kills_added

	static func _handle_band_boss_clear(state: SimStateScript, queue: EventQueueScript) -> void:
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

	# ==========================================================================
	# S3: 转生突破 (抽象快进模式, 按层+农场时间片推进 30 天, 含蒙特卡洛装备/词条抽样与 §1.6 自动转生)
	# ==========================================================================
	static func run_s3_seed(
		seed_val: int,
		strategy: int,
		bal: BalanceScript,
		sim_days: int = S3_SIM_DAYS
	) -> Dictionary:
		var state: SimStateScript = SimStateScript.new(seed_val, bal)
		var total_sim_sec: float = float(sim_days) * S3_SECONDS_PER_DAY
		var sim_clock_sec: float = 0.0
		var next_day_idx: int = 1

		var slot_affix_bonus_log: Dictionary = {}
		for slot_key: String in SimStateScript.EQUIP_SLOTS:
			slot_affix_bonus_log[slot_key] = 0.0

		var daily_snapshots: Array[Dictionary] = []
		var cycle_asymptotes: Array[int] = []
		var abyss_count: int = 0
		var soul_prestige_count: int = 0

		var cycle_soul_runs: int = 0
		var cycle_best_stage: int = 1
		var stagnant_soul_runs: int = 0
		var run_tracked_peak_rate_log: float = NumScript.ZERO

		var farm_slice_sec: float = 120.0
		var loop_guard: int = 0
		var max_loops: int = 2000000

		while sim_clock_sec < total_sim_sec and loop_guard < max_loops:
			loop_guard += 1
			apply_player_strategy(state, strategy, false, false)

			var affix_sum_log: float = 0.0
			if strategy != Strategy.ZERO_OP:
				for slot_k: String in SimStateScript.EQUIP_SLOTS:
					if state.equipped.get(slot_k, null) != null:
						affix_sum_log += float(slot_affix_bonus_log.get(slot_k, 0.0))

			var cur_stage: int = state.current_stage
			var eff_dps_log: float = state.stats.get_expected_dps_log(bal.min_atk_interval) + affix_sum_log
			var wealth_delta: float = state.get_wealth_pressure_hp_delta(cur_stage)
			var band_penalty_log: float = _estimate_band_dps_penalty_log(cur_stage, state, bal)
			var boss_hp_log: float = bal.get_boss_hp_log(cur_stage) + wealth_delta + band_penalty_log
			var cur_strengths: Dictionary = get_band_mechanic_strengths(cur_stage, bal)
			var shield_min_sec: float = 0.0
			if cur_strengths.has(1):
				var sh_hits: float = ceil(bal.mech_shield_hp_ratio / maxf(0.0001, bal.mech_shield_max_hit_strip))
				shield_min_sec = sh_hits * maxf(bal.min_atk_interval, state.stats.atk_interval)
			var effective_boss_window: float = maxf(0.0, bal.boss_time_limit - shield_min_sec)
			var boss_clear_cap_log: float = (
				eff_dps_log + NumScript.from_float(effective_boss_window)
				if effective_boss_window > 0.05
				else NumScript.ZERO
			)
			var kill_gold_mult: float = _expected_kill_gold_mult(bal)

			var step_dt: float = 0.0

			if boss_clear_cap_log >= boss_hp_log:
				var overkill_log: float = boss_clear_cap_log - boss_hp_log
				var stages_to_step: int = 1
				var b_interval: int = maxi(1, bal.band_stage_interval)
				var per_mob_min_sec: float = maxf(
					maxf(bal.min_atk_interval, state.stats.atk_interval),
					shield_min_sec
				)
				var min_clear_per_stage: float = float(bal.mobs_per_stage + 1) * per_mob_min_sec
				var step_clock_cap: float = minf(3600.0, maxf(1.0, total_sim_sec - sim_clock_sec))
				var max_stages_by_clock: int = maxi(1, int(ceil(step_clock_cap / maxf(0.1, min_clear_per_stage))))
				if overkill_log > 2.0 and effective_boss_window > 0.5:
					var target_hp_cap: float = boss_clear_cap_log - wealth_delta - band_penalty_log - 1.2
					var base_boss_h0: float = bal.h0_hp_log + bal.boss_hp_mult_log
					var safe_jump: int = 1
					if target_hp_cap > base_boss_h0:
						if bal.hp_quad_coeff > 1e-9:
							var disc: float = (
								bal.hp_linear_coeff * bal.hp_linear_coeff
								+ 4.0 * bal.hp_quad_coeff * (target_hp_cap - base_boss_h0)
							)
							var s_exact: int = int(floor((-bal.hp_linear_coeff + sqrt(maxf(0.0, disc))) / (2.0 * bal.hp_quad_coeff)))
							safe_jump = maxi(1, s_exact - cur_stage)
						else:
							var s_lin: int = int(floor((target_hp_cap - base_boss_h0) / maxf(1e-4, bal.hp_linear_coeff)))
							safe_jump = maxi(1, s_lin - cur_stage)
					var next_gate_stage: int = (int((cur_stage - 1) / b_interval) + 1) * b_interval
					var stop_stage: int = next_gate_stage - bal.toll_saving_lead_stages
					if state.paid_gate_tier >= int(next_gate_stage / b_interval):
						stop_stage = next_gate_stage - 1
					var dist_to_stop: int = stop_stage - cur_stage
					if dist_to_stop > 1 and safe_jump > 1:
						stages_to_step = clampi(mini(dist_to_stop, safe_jump), 1, max_stages_by_clock)

				if stages_to_step > 1:
					step_dt = float(stages_to_step) * min_clear_per_stage
					var top_s: int = cur_stage + stages_to_step - 1
					var batch_kills: int = stages_to_step * (bal.mobs_per_stage + 1)
					var batch_gold_log: float = (
						bal.get_mob_gold_log(top_s)
						+ NumScript.from_float(float(bal.mobs_per_stage + 1) * kill_gold_mult * 2.0)
					)
					state.gate_boss_cleared = false
					state.current_stage += stages_to_step
					state.farm_stage = state.current_stage
					state.run_best = maxi(state.run_best, state.current_stage)
					state.all_time_best = maxi(state.all_time_best, state.current_stage)
					state.paid_gate_tier = maxi(state.paid_gate_tier, int((state.current_stage - 1) / b_interval))
					state.mobs_killed_in_stage = 0
					state.farm_kills_since_retreat = 0
					state.mobs_killed_total += batch_kills
					state.add_income(batch_gold_log, null)
					_fast_forward_sample_loot(state, top_s, batch_kills, strategy, slot_affix_bonus_log)
				else:
					var mob_hp_log: float = bal.get_monster_hp_log(cur_stage) + wealth_delta + band_penalty_log
					var mob_kill_sec: float = maxf(
						per_mob_min_sec,
						pow(10.0, clampf(mob_hp_log - eff_dps_log, -10.0, 6.0))
					)
					var boss_kill_sec: float = maxf(
						per_mob_min_sec,
						shield_min_sec + pow(10.0, clampf(boss_hp_log - eff_dps_log, -10.0, 6.0))
					)
					step_dt = float(bal.mobs_per_stage) * mob_kill_sec + boss_kill_sec

					var stage_kills: int = bal.mobs_per_stage + 1
					var stage_gold_log: float = (
						bal.get_mob_gold_log(cur_stage)
						+ NumScript.from_float(float(stage_kills) * kill_gold_mult)
					)
					state.mobs_killed_total += stage_kills
					state.add_income(stage_gold_log, null)
					_fast_forward_sample_loot(state, cur_stage, stage_kills, strategy, slot_affix_bonus_log)

					var b_interval_single: int = maxi(1, bal.band_stage_interval)
					if state.enforce_toll_gates and (cur_stage % b_interval_single == 0):
						var g_tier: int = int(cur_stage / b_interval_single)
						if state.paid_gate_tier < g_tier and not state.try_pay_next_toll():
							var toll_log: float = bal.get_toll_cost_log(g_tier)
							var have_net: float = NumScript.ZERO
							var liq_plus_esc: float = NumScript.add(state.gold, state.toll_escrow)
							if liq_plus_esc > state.debt_total:
								have_net = NumScript.sub(liq_plus_esc, state.debt_total)
							var deficit_log: float = NumScript.sub(toll_log, have_net)
							if deficit_log > NumScript.ZERO:
								var kills_per_sec: float = 1.0 / maxf(0.1, mob_kill_sec)
								var farm_rate_sec_log: float = (
									bal.get_mob_gold_log(cur_stage)
									+ NumScript.from_float(kills_per_sec * kill_gold_mult)
								)
								if cur_stage >= 500:
									farm_rate_sec_log += NumScript.from_float(1.0 - bal.mech_gold_eat_income_cap)
								var gate_wait_sec: float = clampf(
									pow(10.0, clampf(deficit_log - farm_rate_sec_log, -6.0, 7.0)),
									1.0,
									S2_MAX_SIM_WAIT_SEC
								)
								step_dt += gate_wait_sec
								var gate_kills: int = maxi(1, int(round(gate_wait_sec * kills_per_sec)))
								state.mobs_killed_total += gate_kills
								_fast_forward_sample_loot(state, cur_stage, gate_kills, strategy, slot_affix_bonus_log)
								state.toll_escrow = NumScript.add(state.toll_escrow, deficit_log)
								state.try_pay_next_toll()
					state.advance_to_next_stage(null)
			else:
				state.farm_stage = maxi(1, cur_stage - 1)
				var slice_cap: float = 600.0 if state.elapsed_seconds < 10800.0 else 14400.0
				var dyn_slice: float = clampf(state.elapsed_seconds * 0.25, farm_slice_sec, slice_cap)
				step_dt = minf(dyn_slice, maxf(60.0, total_sim_sec - sim_clock_sec))
				var f_stage: int = state.farm_stage
				var f_strengths: Dictionary = get_band_mechanic_strengths(f_stage, bal)
				var f_shield_sec: float = 0.0
				if f_strengths.has(1):
					var f_sh_hits: float = ceil(bal.mech_shield_hp_ratio / maxf(0.0001, bal.mech_shield_max_hit_strip))
					f_shield_sec = f_sh_hits * maxf(bal.min_atk_interval, state.stats.atk_interval)
				var f_mob_hp: float = (
					bal.get_monster_hp_log(f_stage)
					+ state.get_wealth_pressure_hp_delta(f_stage)
					+ _estimate_band_dps_penalty_log(f_stage, state, bal)
				)
				var f_kill_sec: float = maxf(
					maxf(bal.min_atk_interval, state.stats.atk_interval),
					maxf(f_shield_sec, pow(10.0, clampf(f_mob_hp - eff_dps_log, -10.0, 6.0)))
				)
				var f_kills: float = maxf(1.0, step_dt / f_kill_sec)
				var f_kills_int: int = maxi(1, int(round(f_kills)))
				var f_gold_log: float = bal.get_mob_gold_log(f_stage) + NumScript.from_float(f_kills * kill_gold_mult)
				state.mobs_killed_total += f_kills_int
				state.add_income(f_gold_log, null)
				_fast_forward_sample_loot(state, f_stage, f_kills_int, strategy, slot_affix_bonus_log)
				apply_player_strategy(state, strategy, false, false)
				var post_affix_sum_log: float = 0.0
				if strategy != Strategy.ZERO_OP:
					for post_slot_k: String in SimStateScript.EQUIP_SLOTS:
						if state.equipped.get(post_slot_k, null) != null:
							post_affix_sum_log += float(slot_affix_bonus_log.get(post_slot_k, 0.0))
				eff_dps_log = state.stats.get_expected_dps_log(bal.min_atk_interval) + post_affix_sum_log
				boss_clear_cap_log = (
					eff_dps_log + NumScript.from_float(effective_boss_window)
					if effective_boss_window > 0.05
					else NumScript.ZERO
				)

			state.elapsed_seconds += step_dt
			sim_clock_sec += step_dt

			while next_day_idx <= sim_days and sim_clock_sec >= float(next_day_idx) * S3_SECONDS_PER_DAY:
				daily_snapshots.push_back({
					"day": next_day_idx,
					"all_time_best": state.all_time_best,
					"souls_log": state.souls,
					"marks": state.marks,
					"abyss_count": abyss_count
				})
				next_day_idx += 1

			if state.run_best > bal.soul_start_stage and state.elapsed_seconds >= bal.auto_prestige_min_run_seconds * 0.5:
				var pend_souls_log: float = bal.get_pending_souls_log(state.run_best, state.marks)
				var cur_rate_log: float = pend_souls_log - NumScript.from_float(state.elapsed_seconds)
				if cur_rate_log > run_tracked_peak_rate_log + 1e-9:
					run_tracked_peak_rate_log = cur_rate_log
				elif (
					boss_clear_cap_log < boss_hp_log
					and state.elapsed_seconds >= bal.auto_prestige_min_run_seconds
					and run_tracked_peak_rate_log != NumScript.ZERO
					and (not state.is_saving_for_toll() or state.elapsed_seconds >= S2_PASS_P90_MINUTES * 60.0)
				):
					var drop_limit: float = run_tracked_peak_rate_log + NumScript.from_float(bal.auto_prestige_rate_drop_ratio)
					if cur_rate_log <= drop_limit:
						if state.run_best > cycle_best_stage + 2:
							cycle_best_stage = state.run_best
							stagnant_soul_runs = 0
						else:
							cycle_best_stage = maxi(cycle_best_stage, state.run_best)
							stagnant_soul_runs += 1
						cycle_soul_runs += 1

						var pending_marks: int = bal.get_pending_marks(state.all_time_best)
						var prev_asym_stage: int = (
							cycle_asymptotes[cycle_asymptotes.size() - 1]
							if not cycle_asymptotes.is_empty()
							else 0
						)
						var soul_gain_flattened: bool = (
							state.souls != NumScript.ZERO
							and pend_souls_log <= state.souls + 0.25
						)
						var soul_asymptote_converged: bool = (
							(
								state.all_time_best > prev_asym_stage
								and (
									(cycle_soul_runs >= 5 and stagnant_soul_runs >= 2 and soul_gain_flattened)
									or (cycle_soul_runs >= 12 and stagnant_soul_runs >= 3)
								)
							)
							or (cycle_soul_runs >= 24 and stagnant_soul_runs >= 6 and soul_gain_flattened)
						)

						if pending_marks > 0 and soul_asymptote_converged:
							cycle_asymptotes.push_back(state.all_time_best)
							abyss_count += 1
							var power_id: String = "abyss_signature_power_%d" % abyss_count
							state.perform_abyss_prestige(power_id)
							for sk: String in SimStateScript.EQUIP_SLOTS:
								slot_affix_bonus_log[sk] = 0.0
							cycle_soul_runs = 0
							cycle_best_stage = 1
							stagnant_soul_runs = 0
							run_tracked_peak_rate_log = NumScript.ZERO
						else:
							state.perform_soul_prestige()
							soul_prestige_count += 1
							run_tracked_peak_rate_log = NumScript.ZERO

		while next_day_idx <= sim_days:
			daily_snapshots.push_back({
				"day": next_day_idx,
				"all_time_best": state.all_time_best,
				"souls_log": state.souls,
				"marks": state.marks,
				"abyss_count": abyss_count
			})
			next_day_idx += 1

		if cycle_soul_runs >= 3 or cycle_asymptotes.is_empty():
			cycle_asymptotes.push_back(state.all_time_best)

		var lift_ratios: Array[float] = []
		var zero_growth_streak: int = 0
		var max_zero_growth_streak: int = 0
		for idx: int in range(1, cycle_asymptotes.size()):
			var prev_asym: int = maxi(1, cycle_asymptotes[idx - 1])
			var next_asym: int = cycle_asymptotes[idx]
			var lift: float = float(next_asym - prev_asym) / float(prev_asym)
			lift_ratios.push_back(lift)
			if next_asym <= prev_asym:
				zero_growth_streak += 1
				max_zero_growth_streak = maxi(max_zero_growth_streak, zero_growth_streak)
			else:
				zero_growth_streak = 0

		var first5_ok: bool = lift_ratios.size() >= S3_REQUIRED_FIRST_LIFTS
		if first5_ok:
			for k: int in range(S3_REQUIRED_FIRST_LIFTS):
				if lift_ratios[k] < S3_MIN_ASYMPTOTE_LIFT_RATIO - 1e-6:
					first5_ok = false
					break

		var no_stagnant_3: bool = max_zero_growth_streak < S3_MAX_STAGNANT_STREAK

		return {
			"seed": seed_val,
			"strategy": strategy,
			"strategy_name": get_strategy_name(strategy),
			"abyss_count": abyss_count,
			"soul_prestige_count": soul_prestige_count,
			"cycle_asymptotes": cycle_asymptotes,
			"lift_ratios": lift_ratios,
			"max_zero_growth_streak": max_zero_growth_streak,
			"first5_lifts_pass": first5_ok,
			"no_stagnant_3_pass": no_stagnant_3,
			"final_all_time_best": state.all_time_best,
			"final_marks": state.marks,
			"final_souls_log": state.souls,
			"daily": daily_snapshots,
			"state_hash": state.compute_state_hash()
		}

	## 从 Balance 精确推导单次击杀含自动熔炼的期望总金币倍数（零魔法常数）
	static func _expected_kill_gold_mult(bal: BalanceScript) -> float:
		var total_w: float = (
			bal.rarity_weight_white
			+ bal.rarity_weight_blue
			+ bal.rarity_weight_purple
			+ bal.rarity_weight_unique
			+ bal.rarity_weight_primal
		)
		if total_w <= 0.0:
			return 1.0
		var avg_smelt: float = (
			bal.rarity_weight_white * pow(10.0, bal.smelt_mult_white_log)
			+ bal.rarity_weight_blue * pow(10.0, bal.smelt_mult_blue_log)
			+ bal.rarity_weight_purple * pow(10.0, bal.smelt_mult_purple_log)
			+ bal.rarity_weight_unique * pow(10.0, bal.smelt_mult_unique_log)
			+ bal.rarity_weight_primal * pow(10.0, bal.smelt_mult_primal_log)
		) / total_w
		return 1.0 + bal.drop_base_per_kill * avg_smelt

	## S3 抽象快进蒙特卡洛装备与词条次序统计量抽样 (§9.2: O(6) 精确极值分布，严格仅消费 SimRng.loot)
	static func _fast_forward_sample_loot(
		state: SimStateScript,
		stage: int,
		approx_kills: int,
		strategy: int,
		slot_affix_bonus_log: Dictionary
	) -> void:
		if strategy == Strategy.ZERO_OP:
			state.rng.loot.next_u32()
			return

		var bal: BalanceScript = state.balance
		var loot_rng: SimRngScript.RngStream = state.rng.loot
		var slot_cnt: int = maxi(1, bal.equip_slot_count)
		var qty_mult: float = 1.0 + maxf(0.0, state.stats.drop_qty_bonus)
		var total_drops: float = maxf(1.0, float(maxi(1, approx_kills)) * bal.drop_base_per_kill * qty_mult)
		var n_slot: float = maxf(0.15, total_drops / float(slot_cnt))

		var eff_mf: float = bal.get_effective_mf(state.stats.magic_find)
		var mf_factor: float = 1.0 + eff_mf * 0.01
		var w_primal: float = bal.rarity_weight_primal * mf_factor
		var w_unique: float = bal.rarity_weight_unique * mf_factor
		var w_purple: float = bal.rarity_weight_purple * mf_factor
		var w_blue: float = bal.rarity_weight_blue
		var w_white: float = bal.rarity_weight_white
		var total_w: float = maxf(1e-6, w_primal + w_unique + w_purple + w_blue + w_white)

		var p_primal: float = clampf(w_primal / total_w, 0.0, 0.999999)
		var p_unique: float = clampf(w_unique / total_w, 0.0, 0.999999)
		var p_purple: float = clampf(w_purple / total_w, 0.0, 0.999999)
		var p_blue: float = clampf(w_blue / total_w, 0.0, 0.999999)

		var prob_any_primal: float = 1.0 - pow(1.0 - p_primal, minf(n_slot, 50000.0))
		var prob_any_unique: float = 1.0 - pow(1.0 - p_unique, minf(n_slot, 50000.0))
		var prob_any_purple: float = 1.0 - pow(1.0 - p_purple, minf(n_slot, 50000.0))
		var prob_any_blue: float = 1.0 - pow(1.0 - p_blue, minf(n_slot, 50000.0))

		var affix_min_log: float = NumScript.from_float(1.0 + bal.gear_additive_pct_blue)
		var affix_max_log: float = NumScript.from_float(1.0 + bal.gear_additive_pct_unique)
		var affix_primal_log: float = NumScript.from_float(1.0 + bal.gear_additive_pct_primal)

		for slot_idx: int in range(slot_cnt):
			var rarity_enum: ItemInstanceScript.Rarity = ItemInstanceScript.Rarity.WHITE
			var sample_count: int = 1

			if p_primal > 0.0 and loot_rng.randf_val() < prob_any_primal:
				rarity_enum = ItemInstanceScript.Rarity.PRIMAL
			elif p_unique > 0.0 and loot_rng.randf_val() < prob_any_unique:
				rarity_enum = ItemInstanceScript.Rarity.UNIQUE
				sample_count = clampi(int(ceil(n_slot * p_unique)), 1, 12)
			elif p_purple > 0.0 and loot_rng.randf_val() < prob_any_purple:
				rarity_enum = ItemInstanceScript.Rarity.PURPLE
				sample_count = clampi(int(ceil(n_slot * p_purple)), 1, 12)
			elif p_blue > 0.0 and loot_rng.randf_val() < prob_any_blue:
				rarity_enum = ItemInstanceScript.Rarity.BLUE
				sample_count = clampi(int(ceil(n_slot * p_blue)), 1, 8)
			else:
				continue

			var inv_m: float = 1.0 / float(sample_count)
			var ilvl: int = maxi(1, stage)
			var phi: float = bal.eq_phi_max
			var additive_pct: float = 0.0
			var unique_mult: float = 1.0
			var cand_affix_log: float = 0.0

			if rarity_enum == ItemInstanceScript.Rarity.PRIMAL:
				ilvl += bal.primal_bonus_ilvl
				phi = bal.eq_phi_max
				additive_pct = bal.gear_additive_pct_primal
				unique_mult = bal.unique_mult_max
				cand_affix_log = affix_primal_log
			else:
				var u_phi: float = pow(maxf(1e-6, loot_rng.randf_val()), inv_m)
				phi = lerpf(bal.eq_phi_min, bal.eq_phi_max, u_phi)
				if rarity_enum == ItemInstanceScript.Rarity.BLUE:
					var u_b: float = pow(maxf(1e-6, loot_rng.randf_val()), inv_m)
					additive_pct = lerpf(0.0, bal.gear_additive_pct_blue, u_b)
				elif rarity_enum == ItemInstanceScript.Rarity.PURPLE:
					var u_p: float = pow(maxf(1e-6, loot_rng.randf_val()), inv_m)
					additive_pct = lerpf(bal.gear_additive_pct_blue, bal.gear_additive_pct_purple, u_p)
				elif rarity_enum == ItemInstanceScript.Rarity.UNIQUE:
					var u_a: float = pow(maxf(1e-6, loot_rng.randf_val()), inv_m)
					var u_m: float = pow(maxf(1e-6, loot_rng.randf_val()), inv_m)
					var u_af: float = pow(maxf(1e-6, loot_rng.randf_val()), inv_m)
					additive_pct = lerpf(bal.gear_additive_pct_purple, bal.gear_additive_pct_unique, u_a)
					unique_mult = lerpf(bal.unique_mult_min, bal.unique_mult_max, u_m)
					cand_affix_log = lerpf(affix_min_log, affix_max_log, u_af)

			var slot_enum: ItemInstanceScript.Slot = slot_idx as ItemInstanceScript.Slot
			var slot_key: String = ItemInstanceScript.get_slot_key(slot_enum)
			var flat_atk_log: float = bal.get_equip_flat_atk_log(ilvl, phi)
			var cand_uid: int = state.mobs_killed_total * 8 + slot_idx + 1
			var cand_item: ItemInstanceScript = ItemInstanceScript.new(
				cand_uid,
				"ff_" + slot_key,
				slot_enum,
				rarity_enum,
				ilvl,
				flat_atk_log,
				additive_pct,
				unique_mult,
				bal
			)

			var cur_eq: ItemInstanceScript = state.equipped.get(slot_key, null) as ItemInstanceScript
			if cur_eq == null:
				state.equip_item(cand_item)
				slot_affix_bonus_log[slot_key] = cand_affix_log
			else:
				var prev_affix_log: float = float(slot_affix_bonus_log.get(slot_key, 0.0))
				var cur_dps: float = state.stats.get_expected_dps_log(bal.min_atk_interval) + prev_affix_log
				state.equipped[slot_key] = cand_item
				state.recalculate_stats()
				var cand_dps: float = state.stats.get_expected_dps_log(bal.min_atk_interval) + cand_affix_log
				if cand_dps > cur_dps + 1e-9:
					state.equip_slots.equipped[slot_idx] = cand_item
					slot_affix_bonus_log[slot_key] = cand_affix_log
				else:
					state.equipped[slot_key] = cur_eq
					state.recalculate_stats()

	# ==========================================================================
	# 批量执行 S1 / S2 / S3、写出结构化 CSV 与 Gate-1 报告
	# ==========================================================================
	static func run_full_suite(out_dir: String = "res://tools/out", reuse_s1_s2: bool = false) -> Dictionary:
		var bal: BalanceScript = BalanceScript.reload_default() as BalanceScript
		var seeds: Array[int] = get_default_seeds()
		var strategies: Array[int] = [
			Strategy.ZERO_OP,
			Strategy.STANDARD,
			Strategy.AGGRESSIVE_DEBT
		]

		var abs_out_dir: String = ProjectSettings.globalize_path(out_dir)
		DirAccess.make_dir_recursive_absolute(abs_out_dir)

		var s1_by_strat: Dictionary = {}
		var s1_all_rows: Array[Dictionary] = []
		var s2_all_rows: Array[Dictionary] = []
		var s2_summary_rows: Array[Dictionary] = []
		var s2_pass_all: bool = true

		if reuse_s1_s2 and FileAccess.file_exists(out_dir + "/s1_first_run_seeds.csv") and FileAccess.file_exists(out_dir + "/s2_toll_gates_summary.csv"):
			print("[CurveSim] 检测到已落盘的 S1/S2 CSV，直接加载复用 (--reuse-s1-s2)...")
			s1_by_strat = _load_cached_s1(out_dir + "/s1_first_run_seeds.csv", strategies)
			var s2_loaded: Dictionary = _load_cached_s2_summary(out_dir + "/s2_toll_gates_summary.csv")
			s2_summary_rows = s2_loaded["rows"] as Array[Dictionary]
			s2_pass_all = bool(s2_loaded["pass_all"])
		else:
			# 1. 运行 S1
			print("[CurveSim] 正在执行 S1 (首周目曲线, Tick 模式, 20 种子 × 3 策略)...")
			for strat: int in strategies:
				var strat_rows: Array[Dictionary] = []
				for sd: int in seeds:
					var r1: Dictionary = run_s1_seed(sd, strat, bal, S1_SIM_DURATION_SEC)
					strat_rows.push_back(r1)
					s1_all_rows.push_back(r1)
				s1_by_strat[strat] = strat_rows
			_write_s1_csvs(out_dir, s1_all_rows, s1_by_strat, strategies)
			print("[CurveSim] S1 已写出 CSV.")

			# 2. 运行 S2
			print("[CurveSim] 正在执行 S2 (100–500 层关卡门票与区间机制验证, 20 种子 × 3 策略)...")
			for strat: int in strategies:
				for gate_s: int in S2_GATE_STAGES:
					var waits: Array[float] = []
					var inf_count: int = 0
					for sd: int in seeds:
						var r2: Dictionary = run_s2_gate_seed(sd, strat, gate_s, bal, S2_MAX_SIM_WAIT_SEC)
						s2_all_rows.push_back(r2)
						waits.push_back(float(r2["wait_minutes"]))
						if bool(r2["infinite_wait"]):
							inf_count += 1
					var q_wait: Dictionary = compute_quantiles(waits)
					var gate_pass: bool = (
						float(q_wait["p50"]) <= S2_PASS_MEDIAN_MINUTES
						and float(q_wait["p90"]) <= S2_PASS_P90_MINUTES
						and inf_count == 0
					)
					if (strat == Strategy.ZERO_OP or strat == Strategy.AGGRESSIVE_DEBT) and not gate_pass:
						s2_pass_all = false

					s2_summary_rows.push_back({
						"strategy": strat,
						"strategy_name": get_strategy_name(strat),
						"gate_stage": gate_s,
						"p10": float(q_wait["p10"]),
						"p50": float(q_wait["p50"]),
						"p90": float(q_wait["p90"]),
						"max": float(q_wait["max"]),
						"infinite_count": inf_count,
						"gate_pass": gate_pass
					})
			_write_s2_csvs(out_dir, s2_all_rows, s2_summary_rows)
			print("[CurveSim] S2 已写出 CSV.")

		# 3. 运行 S3
		print("[CurveSim] 正在执行 S3 (30 天抽象快进转生突破曲线, 20 种子 × 3 策略)...")
		var s3_by_strat: Dictionary = {}
		var s3_all_rows: Array[Dictionary] = []
		for strat: int in strategies:
			var strat_s3: Array[Dictionary] = []
			for sd: int in seeds:
				var r3: Dictionary = run_s3_seed(sd, strat, bal, S3_SIM_DAYS)
				strat_s3.push_back(r3)
				s3_all_rows.push_back(r3)
			s3_by_strat[strat] = strat_s3

		# 4. 评估 S1 验收结论（标准玩家基准）
		var s1_std_rows: Array[Dictionary] = s1_by_strat[Strategy.STANDARD] as Array[Dictionary]
		var s1_dmg_vals: Array[float] = []
		var s1_wall_vals: Array[float] = []
		for row: Dictionary in s1_std_rows:
			s1_dmg_vals.push_back(float(row["dmg_5m_log"]))
			s1_wall_vals.push_back(float(row["soft_wall_hours"]))

		var s1_dmg_q: Dictionary = compute_quantiles(s1_dmg_vals)
		var s1_wall_q: Dictionary = compute_quantiles(s1_wall_vals)
		var tol_log: float = NumScript.from_float(S1_TARGET_5M_TOL_FACTOR)
		var s1_dmg_pass: bool = (
			float(s1_dmg_q["p50"]) >= S1_TARGET_5M_DMG_LOG - tol_log
			and float(s1_dmg_q["p50"]) <= S1_TARGET_5M_DMG_LOG + tol_log
		)
		var s1_wall_pass: bool = (
			float(s1_wall_q["p50"]) >= S1_SOFT_WALL_MIN_HOURS
			and float(s1_wall_q["p50"]) <= S1_SOFT_WALL_MAX_HOURS
		)
		var s1_pass: bool = s1_dmg_pass and s1_wall_pass

		# 5. 评估 S3 验收结论
		var s3_std_rows: Array[Dictionary] = s3_by_strat[Strategy.STANDARD] as Array[Dictionary]
		var s3_stagnant_fail_seeds: int = 0
		var s3_lift_lists_by_idx: Array = [[], [], [], [], []]
		var s3_min_abyss_count: int = 999999

		for row3: Dictionary in s3_std_rows:
			var ab_cnt: int = int(row3["abyss_count"])
			s3_min_abyss_count = mini(s3_min_abyss_count, ab_cnt)
			if not bool(row3["no_stagnant_3_pass"]):
				s3_stagnant_fail_seeds += 1
			var lifts: Array[float] = row3["lift_ratios"] as Array[float]
			for k_idx: int in range(S3_REQUIRED_FIRST_LIFTS):
				if k_idx < lifts.size():
					(s3_lift_lists_by_idx[k_idx] as Array).push_back(lifts[k_idx])

		var s3_lift_p10: Array[float] = []
		var s3_lift_p50: Array[float] = []
		var s3_lift_p90: Array[float] = []
		var s3_lifts_pass: bool = true
		for k_idx: int in range(S3_REQUIRED_FIRST_LIFTS):
			var raw_list: Array = s3_lift_lists_by_idx[k_idx] as Array
			var typed_vals: Array[float] = []
			for v_var: Variant in raw_list:
				typed_vals.push_back(float(v_var))
			if typed_vals.size() < seeds.size():
				s3_lifts_pass = false
			var lq: Dictionary = compute_quantiles(typed_vals)
			s3_lift_p10.push_back(float(lq["p10"]))
			s3_lift_p50.push_back(float(lq["p50"]))
			s3_lift_p90.push_back(float(lq["p90"]))
			if typed_vals.is_empty() or float(lq["p50"]) < S3_MIN_ASYMPTOTE_LIFT_RATIO - 1e-6:
				s3_lifts_pass = false
			if typed_vals.is_empty() or float(lq["p10"]) < S3_MIN_ASYMPTOTE_LIFT_RATIO - 1e-6:
				s3_lifts_pass = false

		var s3_pass: bool = s3_lifts_pass and (s3_stagnant_fail_seeds == 0)
		var gate1_all_pass: bool = s1_pass and s2_pass_all and s3_pass

		if not reuse_s1_s2:
			_write_s1_csvs(out_dir, s1_all_rows, s1_by_strat, strategies)
			_write_s2_csvs(out_dir, s2_all_rows, s2_summary_rows)
		_write_s3_csvs(out_dir, s3_all_rows, s3_by_strat, strategies, S3_SIM_DAYS)
		_write_gate1_report(
			out_dir + "/gate1_report.md",
			bal,
			s1_by_strat,
			s1_dmg_q,
			s1_wall_q,
			s1_dmg_pass,
			s1_wall_pass,
			s2_summary_rows,
			s2_pass_all,
			s3_by_strat,
			s3_lift_p10,
			s3_lift_p50,
			s3_lift_p90,
			s3_min_abyss_count,
			s3_stagnant_fail_seeds,
			s3_pass,
			gate1_all_pass
		)

		return {
			"s1_pass": s1_pass,
			"s1_dmg_p50_log": float(s1_dmg_q["p50"]),
			"s1_wall_p50_hours": float(s1_wall_q["p50"]),
			"s2_pass": s2_pass_all,
			"s3_pass": s3_pass,
			"s3_lift_p50": s3_lift_p50,
			"s3_stagnant_fail_seeds": s3_stagnant_fail_seeds,
			"gate1_all_pass": gate1_all_pass
		}

	static func _write_text_file(path: String, content: String) -> void:
		var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
		if f != null:
			f.store_string(content)
			f.close()

	static func _load_cached_s1(path: String, strategies: Array[int]) -> Dictionary:
		var by_strat: Dictionary = {}
		for st: int in strategies:
			var empty_rows: Array[Dictionary] = []
			by_strat[st] = empty_rows
		var f: FileAccess = FileAccess.open(path, FileAccess.READ)
		if f == null:
			return by_strat
		var text: String = f.get_as_text()
		f.close()
		var lines: PackedStringArray = text.split("\n")
		for idx: int in range(1, lines.size()):
			var line: String = lines[idx].strip_edges()
			if line.is_empty():
				continue
			var cols: PackedStringArray = line.split(",")
			if cols.size() < 15:
				continue
			var st_name: String = cols[1]
			var st_enum: int = Strategy.ZERO_OP
			if st_name == "standard":
				st_enum = Strategy.STANDARD
			elif st_name == "aggressive_debt":
				st_enum = Strategy.AGGRESSIVE_DEBT
			var arr: Array[Dictionary] = by_strat[st_enum] as Array[Dictionary]
			arr.push_back({
				"seed": int(cols[0]),
				"strategy": st_enum,
				"strategy_name": st_name,
				"dmg_5m_log": float(cols[2]),
				"dps_5m_log": float(cols[4]),
				"stage_5m": int(cols[5]),
				"stage_30m": int(cols[6]),
				"stage_60m": int(cols[7]),
				"stage_120m": int(cols[8]),
				"stage_180m": int(cols[9]),
				"run_best_end": int(cols[10]),
				"peak_rate_hours": float(cols[11]),
				"prestige_trigger_hours": float(cols[12]),
				"soft_wall_hours": float(cols[13]),
				"state_hash": cols[14],
				"timeseries": []
			})
		return by_strat

	static func _load_cached_s2_summary(path: String) -> Dictionary:
		var rows: Array[Dictionary] = []
		var pass_all: bool = true
		var f: FileAccess = FileAccess.open(path, FileAccess.READ)
		if f == null:
			return {"rows": rows, "pass_all": false}
		var text: String = f.get_as_text()
		f.close()
		var lines: PackedStringArray = text.split("\n")
		for idx: int in range(1, lines.size()):
			var line: String = lines[idx].strip_edges()
			if line.is_empty():
				continue
			var cols: PackedStringArray = line.split(",")
			if cols.size() < 8:
				continue
			var st_name: String = cols[0]
			var st_enum: int = Strategy.ZERO_OP
			if st_name == "standard":
				st_enum = Strategy.STANDARD
			elif st_name == "aggressive_debt":
				st_enum = Strategy.AGGRESSIVE_DEBT
			var g_pass: bool = (cols[7].to_lower() == "true")
			if (st_enum == Strategy.ZERO_OP or st_enum == Strategy.AGGRESSIVE_DEBT) and not g_pass:
				pass_all = false
			rows.push_back({
				"strategy": st_enum,
				"strategy_name": st_name,
				"gate_stage": int(cols[1]),
				"p10": float(cols[2]),
				"p50": float(cols[3]),
				"p90": float(cols[4]),
				"max": float(cols[5]),
				"infinite_count": int(cols[6]),
				"gate_pass": g_pass
			})
		return {"rows": rows, "pass_all": pass_all}

	static func _write_s1_csvs(
		out_dir: String,
		s1_all_rows: Array[Dictionary],
		s1_by_strat: Dictionary,
		strategies: Array[int]
	) -> void:
		var lines_seeds: PackedStringArray = PackedStringArray()
		lines_seeds.append("seed,strategy,dmg_5m_log,dmg_5m_fmt,dps_5m_log,stage_5m,stage_30m,stage_60m,stage_120m,stage_180m,run_best_end,peak_rate_hours,prestige_trigger_hours,soft_wall_hours,state_hash")
		for r: Dictionary in s1_all_rows:
			var d_log: float = float(r["dmg_5m_log"])
			lines_seeds.append("%d,%s,%.6f,%s,%.6f,%d,%d,%d,%d,%d,%d,%.4f,%.4f,%.4f,%s" % [
				int(r["seed"]),
				String(r["strategy_name"]),
				d_log,
				NumScript.format_num(d_log),
				float(r["dps_5m_log"]),
				int(r["stage_5m"]),
				int(r["stage_30m"]),
				int(r["stage_60m"]),
				int(r["stage_120m"]),
				int(r["stage_180m"]),
				int(r["run_best_end"]),
				float(r["peak_rate_hours"]),
				float(r["prestige_trigger_hours"]),
				float(r["soft_wall_hours"]),
				String(r["state_hash"])
			])
		_write_text_file(out_dir + "/s1_first_run_seeds.csv", "\n".join(lines_seeds) + "\n")

		var lines_ts: PackedStringArray = PackedStringArray()
		lines_ts.append("strategy,minute,stage_p10,stage_p50,stage_p90,dmg_log_p10,dmg_log_p50,dmg_log_p90,gold_log_p50")
		for strat: int in strategies:
			var rows: Array[Dictionary] = s1_by_strat[strat] as Array[Dictionary]
			if rows.is_empty():
				continue
			var first_ts: Array = rows[0]["timeseries"] as Array
			for idx: int in range(first_ts.size()):
				var minute_val: int = int((first_ts[idx] as Dictionary)["minute"])
				var st_vals: Array[float] = []
				var dm_vals: Array[float] = []
				var gd_vals: Array[float] = []
				for sr: Dictionary in rows:
					var ts_arr: Array = sr["timeseries"] as Array
					var snap: Dictionary = ts_arr[idx] as Dictionary
					st_vals.push_back(float(snap["stage"]))
					dm_vals.push_back(float(snap["dmg_log"]))
					var g_val: float = float(snap["gold_log"])
					gd_vals.push_back(0.0 if g_val == NumScript.ZERO else g_val)
				var sq: Dictionary = compute_quantiles(st_vals)
				var dq: Dictionary = compute_quantiles(dm_vals)
				var gq: Dictionary = compute_quantiles(gd_vals)
				lines_ts.append("%s,%d,%.1f,%.1f,%.1f,%.4f,%.4f,%.4f,%.4f" % [
					get_strategy_name(strat),
					minute_val,
					float(sq["p10"]),
					float(sq["p50"]),
					float(sq["p90"]),
					float(dq["p10"]),
					float(dq["p50"]),
					float(dq["p90"]),
					float(gq["p50"])
				])
		_write_text_file(out_dir + "/s1_timeseries_quantiles.csv", "\n".join(lines_ts) + "\n")

	static func _write_s2_csvs(
		out_dir: String,
		s2_all_rows: Array[Dictionary],
		s2_summary_rows: Array[Dictionary]
	) -> void:
		var lines_raw: PackedStringArray = PackedStringArray()
		lines_raw.append("seed,strategy,gate_stage,start_stage,end_stage,wait_minutes,paid_toll,cleared_gate,infinite_wait,final_escrow_log,final_debt_log")
		for r: Dictionary in s2_all_rows:
			var esc_v: float = float(r["final_escrow_log"])
			var debt_v: float = float(r["final_debt_log"])
			lines_raw.append("%d,%s,%d,%d,%d,%.3f,%s,%s,%s,%.4f,%.4f" % [
				int(r["seed"]),
				String(r["strategy_name"]),
				int(r["gate_stage"]),
				int(r["start_stage"]),
				int(r["end_stage"]),
				float(r["wait_minutes"]),
				str(bool(r["paid_toll"])),
				str(bool(r["cleared_gate"])),
				str(bool(r["infinite_wait"])),
				0.0 if esc_v == NumScript.ZERO else esc_v,
				0.0 if debt_v == NumScript.ZERO else debt_v
			])
		_write_text_file(out_dir + "/s2_toll_gates_seeds.csv", "\n".join(lines_raw) + "\n")

		var lines_sum: PackedStringArray = PackedStringArray()
		lines_sum.append("strategy,gate_stage,wait_min_p10,wait_min_p50,wait_min_p90,wait_min_max,infinite_wait_count,gate_pass")
		for sr: Dictionary in s2_summary_rows:
			lines_sum.append("%s,%d,%.2f,%.2f,%.2f,%.2f,%d,%s" % [
				String(sr["strategy_name"]),
				int(sr["gate_stage"]),
				float(sr["p10"]),
				float(sr["p50"]),
				float(sr["p90"]),
				float(sr["max"]),
				int(sr["infinite_count"]),
				str(bool(sr["gate_pass"]))
			])
		_write_text_file(out_dir + "/s2_toll_gates_summary.csv", "\n".join(lines_sum) + "\n")

	static func _write_s3_csvs(
		out_dir: String,
		s3_all_rows: Array[Dictionary],
		s3_by_strat: Dictionary,
		strategies: Array[int],
		sim_days: int
	) -> void:
		var lines_daily: PackedStringArray = PackedStringArray()
		lines_daily.append("strategy,day,all_time_best_p10,all_time_best_p50,all_time_best_p90,souls_log_p10,souls_log_p50,souls_log_p90,marks_p10,marks_p50,marks_p90,abyss_count_p50")
		for strat: int in strategies:
			var rows: Array[Dictionary] = s3_by_strat[strat] as Array[Dictionary]
			for day_i: int in range(sim_days):
				var best_vals: Array[float] = []
				var soul_vals: Array[float] = []
				var mark_vals: Array[float] = []
				var ab_vals: Array[float] = []
				for sr: Dictionary in rows:
					var d_arr: Array = sr["daily"] as Array
					var snap: Dictionary = d_arr[day_i] as Dictionary
					best_vals.push_back(float(snap["all_time_best"]))
					var sl: float = float(snap["souls_log"])
					soul_vals.push_back(0.0 if sl == NumScript.ZERO else sl)
					mark_vals.push_back(float(snap["marks"]))
					ab_vals.push_back(float(snap["abyss_count"]))
				var bq: Dictionary = compute_quantiles(best_vals)
				var sq: Dictionary = compute_quantiles(soul_vals)
				var mq: Dictionary = compute_quantiles(mark_vals)
				var aq: Dictionary = compute_quantiles(ab_vals)
				lines_daily.append("%s,%d,%.1f,%.1f,%.1f,%.4f,%.4f,%.4f,%.1f,%.1f,%.1f,%.1f" % [
					get_strategy_name(strat),
					day_i + 1,
					float(bq["p10"]),
					float(bq["p50"]),
					float(bq["p90"]),
					float(sq["p10"]),
					float(sq["p50"]),
					float(sq["p90"]),
					float(mq["p10"]),
					float(mq["p50"]),
					float(mq["p90"]),
					float(aq["p50"])
				])
		_write_text_file(out_dir + "/s3_fast_forward_daily.csv", "\n".join(lines_daily) + "\n")

		var lines_ab: PackedStringArray = PackedStringArray()
		lines_ab.append("seed,strategy,abyss_count,soul_prestige_count,c0_best,c1_best,c2_best,c3_best,c4_best,c5_best,lift1_pct,lift2_pct,lift3_pct,lift4_pct,lift5_pct,max_zero_growth_streak,final_all_time_best,final_marks,first5_pass,no_stagnant_3_pass")
		for r: Dictionary in s3_all_rows:
			var asyms: Array[int] = r["cycle_asymptotes"] as Array[int]
			var lifts: Array[float] = r["lift_ratios"] as Array[float]
			var c_vals: Array[int] = []
			for ci: int in range(6):
				c_vals.push_back(asyms[ci] if ci < asyms.size() else -1)
			var l_vals: Array[float] = []
			for li: int in range(5):
				l_vals.push_back(lifts[li] * 100.0 if li < lifts.size() else -1.0)
			lines_ab.append("%d,%s,%d,%d,%d,%d,%d,%d,%d,%d,%.2f,%.2f,%.2f,%.2f,%.2f,%d,%d,%d,%s,%s" % [
				int(r["seed"]),
				String(r["strategy_name"]),
				int(r["abyss_count"]),
				int(r["soul_prestige_count"]),
				c_vals[0], c_vals[1], c_vals[2], c_vals[3], c_vals[4], c_vals[5],
				l_vals[0], l_vals[1], l_vals[2], l_vals[3], l_vals[4],
				int(r["max_zero_growth_streak"]),
				int(r["final_all_time_best"]),
				int(r["final_marks"]),
				str(bool(r["first5_lifts_pass"])),
				str(bool(r["no_stagnant_3_pass"]))
			])
		_write_text_file(out_dir + "/s3_abyss_lifts_seeds.csv", "\n".join(lines_ab) + "\n")

	static func _write_gate1_report(
		report_path: String,
		bal: BalanceScript,
		s1_by_strat: Dictionary,
		s1_dmg_q: Dictionary,
		s1_wall_q: Dictionary,
		s1_dmg_pass: bool,
		s1_wall_pass: bool,
		s2_summary_rows: Array[Dictionary],
		s2_pass_all: bool,
		s3_by_strat: Dictionary,
		s3_lift_p10: Array[float],
		s3_lift_p50: Array[float],
		s3_lift_p90: Array[float],
		s3_min_abyss_count: int,
		s3_stagnant_fail_seeds: int,
		s3_pass: bool,
		gate1_all_pass: bool
	) -> void:
		var md: PackedStringArray = PackedStringArray()
		md.append("# Gate-1 数值闸门验证报告 (`tools/out/gate1_report.md`)")
		md.append("")
		md.append("> 证据等级：**[C]** Canonical（Godot 4.7.2 Headless 20 确定性种子实测输出）")
		md.append("> 验收基准：《02_系统架构与数值_v6.md》§9.2 与《00_开发执行总纲.md》§5 WP-04 / Gate-1")
		md.append("")
		md.append("## 1. 闸门总结论：%s" % ["PASS (全部达标)" if gate1_all_pass else "FAIL (待参数校准)"])
		md.append("")
		md.append("| 场景 | 验收指标 (§9.2) | 目标区间 | 实测结果 [C] | 结论 |")
		md.append("|---|---|---|---|---|")
		md.append("| **S1 首周目曲线** | 第 5 分钟单次伤害 P50 | `3.33e6 ~ 3.00e7` (`log10 ∈ [6.523, 7.477]`) | `%s` (`log10 = %.4f`, P10=`%.3f`, P90=`%.3f`) | **%s** |" % [
			NumScript.format_num(float(s1_dmg_q["p50"])),
			float(s1_dmg_q["p50"]),
			float(s1_dmg_q["p10"]),
			float(s1_dmg_q["p90"]),
			"PASS" if s1_dmg_pass else "FAIL"
		])
		md.append("| **S1 首周目曲线** | 首周目软墙出现时间 P50 | `1.50h ~ 3.00h` | `%.2fh` (P10=`%.2fh`, P90=`%.2fh`) | **%s** |" % [
			float(s1_wall_q["p50"]),
			float(s1_wall_q["p10"]),
			float(s1_wall_q["p90"]),
			"PASS" if s1_wall_pass else "FAIL"
		])
		md.append("| **S2 门票不卡死** | 零操作 + 激进借贷 100–500 层每道门 | `P50 ≤ 60m`, `P90 ≤ 240m`, `无限等待 = 0` | 详见第 3 节分门汇总表 | **%s** |" % [
			"PASS" if s2_pass_all else "FAIL"
		])
		md.append("| **S3 转生突破** | 30 天快进：前 5 次深渊转生渐近线抬升 & 零连续 3 次停滞 | 前 5 次每次 `≥ +25%%`；停滞种子 `= 0` | 最少深渊次数=`%d`, 连续3次不涨种子=`%d` | **%s** |" % [
			s3_min_abyss_count,
			s3_stagnant_fail_seeds,
			"PASS" if s3_pass else "FAIL"
		])
		md.append("")

		md.append("## 2. S1 首周目曲线（Tick 模式，20 种子 × 3 策略）[C]")
		md.append("")
		md.append("| 策略 | 5m 伤害 P50 (`log10`) | 5m 层数 P50 | 30m 层数 P50 | 120m 层数 P50 | 180m 层数 P50 | 软墙时间 P10 / P50 / P90 (h) |")
		md.append("|---|---|---|---|---|---|---|")
		for strat: int in [Strategy.ZERO_OP, Strategy.STANDARD, Strategy.AGGRESSIVE_DEBT]:
			var rows: Array[Dictionary] = s1_by_strat[strat] as Array[Dictionary]
			var d5: Array[float] = []
			var s5: Array[float] = []
			var s30: Array[float] = []
			var s120: Array[float] = []
			var s180: Array[float] = []
			var wh: Array[float] = []
			for r: Dictionary in rows:
				d5.push_back(float(r["dmg_5m_log"]))
				s5.push_back(float(r["stage_5m"]))
				s30.push_back(float(r["stage_30m"]))
				s120.push_back(float(r["stage_120m"]))
				s180.push_back(float(r["stage_180m"]))
				wh.push_back(float(r["soft_wall_hours"]))
			var qd5: Dictionary = compute_quantiles(d5)
			var qs5: Dictionary = compute_quantiles(s5)
			var qs30: Dictionary = compute_quantiles(s30)
			var qs120: Dictionary = compute_quantiles(s120)
			var qs180: Dictionary = compute_quantiles(s180)
			var qwh: Dictionary = compute_quantiles(wh)
			md.append("| `%s` (%s) | `%s` (`%.3f`) | `%.0f` | `%.0f` | `%.0f` | `%.0f` | `%.2f / %.2f / %.2f` |" % [
				get_strategy_name(strat),
				get_strategy_label_zh(strat),
				NumScript.format_num(float(qd5["p50"])),
				float(qd5["p50"]),
				float(qs5["p50"]),
				float(qs30["p50"]),
				float(qs120["p50"]),
				float(qs180["p50"]),
				float(qwh["p10"]),
				float(qwh["p50"]),
				float(qwh["p90"])
			])
		md.append("")
		md.append("- 明细 CSV：`tools/out/s1_first_run_seeds.csv`、`tools/out/s1_timeseries_quantiles.csv`")
		md.append("")

		md.append("## 3. S2 关卡门票与区间机制验证（100–500 层，20 种子 × 3 策略）[C]")
		md.append("")
		md.append("| 策略 | 关卡门 | 等待 P10 (min) | 等待 P50 (min) | 等待 P90 (min) | 最大等待 (min) | 无限等待种子数 | 单门结论 |")
		md.append("|---|---|---|---|---|---|---|---|")
		for sr: Dictionary in s2_summary_rows:
			md.append("| `%s` | **%d 层** | `%.2f` | `%.2f` | `%.2f` | `%.2f` | `%d` | **%s** |" % [
				String(sr["strategy_name"]),
				int(sr["gate_stage"]),
				float(sr["p10"]),
				float(sr["p50"]),
				float(sr["p90"]),
				float(sr["max"]),
				int(sr["infinite_count"]),
				"PASS" if bool(sr["gate_pass"]) else "FAIL"
			])
		md.append("")
		md.append("- 明细 CSV：`tools/out/s2_toll_gates_seeds.csv`、`tools/out/s2_toll_gates_summary.csv`")
		md.append("")

		md.append("## 4. S3 30 天抽象快进与深渊转生渐近线突破（20 种子 × 3 策略）[C]")
		md.append("")
		md.append("### 4.1 标准策略前 5 次深渊转生 `all_time_best` 渐近线抬升幅度")
		md.append("")
		md.append("| 深渊转生序号 | 抬升幅度 P10 | 抬升幅度 P50 | 抬升幅度 P90 | 验收阈值 (`≥ +25%`) |")
		md.append("|---|---|---|---|---|")
		for k_idx: int in range(S3_REQUIRED_FIRST_LIFTS):
			var p10_pct: float = s3_lift_p10[k_idx] * 100.0
			var p50_pct: float = s3_lift_p50[k_idx] * 100.0
			var p90_pct: float = s3_lift_p90[k_idx] * 100.0
			var pass_k: bool = (
				s3_min_abyss_count >= S3_REQUIRED_FIRST_LIFTS
				and s3_lift_p10[k_idx] >= S3_MIN_ASYMPTOTE_LIFT_RATIO - 1e-6
				and s3_lift_p50[k_idx] >= S3_MIN_ASYMPTOTE_LIFT_RATIO - 1e-6
			)
			var s_p10: String = ("+" if p10_pct >= 0.0 else "") + ("%.2f%%" % p10_pct)
			var s_p50: String = ("+" if p50_pct >= 0.0 else "") + ("%.2f%%" % p50_pct)
			var s_p90: String = ("+" if p90_pct >= 0.0 else "") + ("%.2f%%" % p90_pct)
			md.append("| 第 %d 次深渊转生 | `%s` | `%s` | `%s` | **%s** |" % [
				k_idx + 1,
				s_p10,
				s_p50,
				s_p90,
				"PASS" if pass_k else "FAIL"
			])
		md.append("")

		md.append("### 4.2 标准策略 30 天关键天数 P10 / P50 / P90 曲线摘要")
		md.append("")
		md.append("| 天数 | `all_time_best` (P10 / P50 / P90) | `souls` log10 (P10 / P50 / P90) | 累计印记 `marks` (P10 / P50 / P90) |")
		md.append("|---|---|---|---|")
		var std_s3_rows: Array[Dictionary] = s3_by_strat[Strategy.STANDARD] as Array[Dictionary]
		for check_day: int in [1, 3, 5, 10, 15, 20, 25, 30]:
			var b_arr: Array[float] = []
			var s_arr: Array[float] = []
			var m_arr: Array[float] = []
			for r3: Dictionary in std_s3_rows:
				var d_list: Array = r3["daily"] as Array
				var snap3: Dictionary = d_list[check_day - 1] as Dictionary
				b_arr.push_back(float(snap3["all_time_best"]))
				var sl_v: float = float(snap3["souls_log"])
				s_arr.push_back(0.0 if sl_v == NumScript.ZERO else sl_v)
				m_arr.push_back(float(snap3["marks"]))
			var qb: Dictionary = compute_quantiles(b_arr)
			var qs: Dictionary = compute_quantiles(s_arr)
			var qm: Dictionary = compute_quantiles(m_arr)
			md.append("| Day %d | `%.0f / %.0f / %.0f` | `%.2f / %.2f / %.2f` | `%.0f / %.0f / %.0f` |" % [
				check_day,
				float(qb["p10"]), float(qb["p50"]), float(qb["p90"]),
				float(qs["p10"]), float(qs["p50"]), float(qs["p90"]),
				float(qm["p10"]), float(qm["p50"]), float(qm["p90"])
			])
		md.append("")
		md.append("- 明细 CSV：`tools/out/s3_fast_forward_daily.csv`、`tools/out/s3_abyss_lifts_seeds.csv`")
		md.append("")

		md.append("## 5. 本轮 `content/balance.tres` 关键参数快照 [C]")
		md.append("")
		md.append("- `c0_cost_log = %.6f`, `gamma_cost_log = %.8f`, `e0_income_log = %.6f`" % [
			bal.c0_cost_log, bal.gamma_cost_log, bal.e0_income_log
		])
		md.append("- `rarity_weight_unique = %.4f`, `rarity_weight_primal = %.4f`, `unique_pity_kills = %d`" % [
			bal.rarity_weight_unique, bal.rarity_weight_primal, bal.unique_pity_kills
		])
		md.append("- `mech_shield_hp_ratio = %.4f`, `mech_shield_max_hit_strip = %.4f`" % [
			bal.mech_shield_hp_ratio, bal.mech_shield_max_hit_strip
		])
		md.append("- `soul_k_coeff = %.4f`, `mark_k_amp_per_mark = %.4f`, `mark_stage_divisor = %.2f`, `mark_stage_exponent = %.4f`" % [
			bal.soul_k_coeff, bal.mark_k_amp_per_mark, bal.mark_stage_divisor, bal.mark_stage_exponent
		])
		md.append("")

		_write_text_file(report_path, "\n".join(md) + "\n")
