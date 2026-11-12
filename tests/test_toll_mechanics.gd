class_name TestTollMechanics extends RefCounted

## WP-15 验收：第 100 层门票 + 储蓄托管 + 护盾机制；零操作模拟自行通过第 100 层门；卡墙/储蓄文案正确
## 依据《02_系统架构与数值_v6.md》§7.1–§7.3、Q31、Q32、Q36

const SimStateScript = preload("res://simulation/SimState.gd")
const SimRunnerScript = preload("res://simulation/SimRunner.gd")
const CombatScript = preload("res://simulation/combat/Combat.gd")
const SpawnerScript = preload("res://simulation/combat/Spawner.gd")
const EventQueueScript = preload("res://simulation/events/EventQueue.gd")
const BandRulesScript = preload("res://simulation/mechanics/BandRules.gd")
const MechanicDefScript = preload("res://simulation/mechanics/MechanicDef.gd")
const TollScript = preload("res://simulation/economy/Toll.gd")
const BalanceScript = preload("res://simulation/Balance.gd")
const NumScript = preload("res://core/num/Num.gd")

const EPS: float = 1e-9
const MAX_ZERO_OP_TICKS: int = 6000

static func run() -> bool:
	print("[TestTollMechanics] 开始测试 WP-15 第 100 层门票/储蓄托管/护盾机制...")
	if not _test_band_rules():
		return false
	if not _test_shield_combat():
		return false
	if not _test_zero_op_passes_gate_100():
		return false
	if not _test_wall_hints():
		return false
	print("[TestTollMechanics] WP-15 全部验收项 100% 通过!")
	return true

static func _test_band_rules() -> bool:
	var bal: BalanceScript = BalanceScript.load_default() as BalanceScript
	if not BandRulesScript.get_strengths(100, bal).is_empty():
		printerr("[TestTollMechanics] 第 100 层(区间 0) 不应有主题机制")
		return false
	var s101: Dictionary = BandRulesScript.get_strengths(101, bal)
	if absf(float(s101.get(int(MechanicDefScript.Kind.SHIELD), 0.0)) - 1.0) > EPS:
		printerr("[TestTollMechanics] 101 层护盾应满强度")
		return false
	var s201: Dictionary = BandRulesScript.get_strengths(201, bal)
	if absf(float(s201.get(int(MechanicDefScript.Kind.SHIELD), 0.0)) - bal.band_lingering_strength) > EPS:
		printerr("[TestTollMechanics] 201 层护盾余韵应为 30%")
		return false
	if BandRulesScript.get_shield_def() == null:
		printerr("[TestTollMechanics] shield.tres 加载失败")
		return false
	print("[TestTollMechanics] 区间机制强度/余韵规则通过")
	return true

static func _test_shield_combat() -> bool:
	var bal: BalanceScript = BalanceScript.load_default() as BalanceScript
	var state: SimStateScript = SimStateScript.new(1515, bal)
	state.all_time_best = 150
	state.run_best = 150
	state.current_stage = 150
	state.farm_stage = 150
	SpawnerScript.spawn_next(state)
	var hp: float = state.mob_max_hp_log
	if absf(state.mob_shield_max_log - (hp + NumScript.from_float(bal.mech_shield_hp_ratio))) > EPS:
		printerr("[TestTollMechanics] 护盾量应为 50% 最大生命")
		return false
	if absf(state.mob_shield_strip_cap_log - (hp + NumScript.from_float(bal.mech_shield_max_hit_strip))) > EPS:
		printerr("[TestTollMechanics] 每击削盾上限应为 max_hit_strip × 最大生命")
		return false

	var combat: CombatScript = CombatScript.new()
	var q: EventQueueScript = EventQueueScript.new()
	var hits_to_break: int = int(ceil(bal.mech_shield_hp_ratio / bal.mech_shield_max_hit_strip))
	var big_hit: float = hp + 1.0   # 单击伤害 = 10 倍怪物生命，仍受护盾限制
	for i: int in range(hits_to_break):
		var kills: int = combat.apply_derived_damage(big_hit, state, q)
		if kills != 0 or absf(state.mob_current_hp_log - hp) > EPS:
			printerr("[TestTollMechanics] 护盾未破前第 ", i + 1, " 击不应伤到怪物本体")
			return false
	if state.mob_shield_cur_log != NumScript.ZERO:
		printerr("[TestTollMechanics] ", hits_to_break, " 击后护盾应被击破")
		return false
	if combat.apply_derived_damage(big_hit, state, q) < 1:
		printerr("[TestTollMechanics] 护盾破后下一击应击杀")
		return false

	# 100 层及以下无护盾
	var low: SimStateScript = SimStateScript.new(1516, bal)
	low.current_stage = 100
	low.farm_stage = 100
	low.run_best = 100
	SpawnerScript.spawn_next(low)
	if low.mob_shield_max_log != NumScript.ZERO:
		printerr("[TestTollMechanics] 第 100 层不应有护盾")
		return false
	print("[TestTollMechanics] 护盾: ", hits_to_break, " 击破盾、单击上限、100 层无盾验证通过")
	return true

static func _test_zero_op_passes_gate_100() -> bool:
	var bal: BalanceScript = BalanceScript.load_default() as BalanceScript
	var state: SimStateScript = SimStateScript.new(100100, bal)
	state.all_time_best = 95
	state.run_best = 95
	state.current_stage = 95
	state.farm_stage = 95
	state.stats.base_gold_atk_log = 40.0   # 远强于第 95–101 层，隔离门票机制本身（零操作：不换装/不点科技/不借钱）
	state.stats.atk_interval = 0.05
	var runner: SimRunnerScript = SimRunnerScript.new(state)

	var saw_saving_or_waiting: bool = false
	var saw_escrow: bool = false
	var saw_waiting: bool = false
	var wealth_with_escrow_ok: bool = true
	var passed_tick: int = -1
	for t: int in range(MAX_ZERO_OP_TICKS):
		runner.step()
		runner.queue.clear()
		var phase: String = TollScript.get_phase(state)
		if phase == TollScript.PHASE_SAVING or phase == TollScript.PHASE_WAITING:
			saw_saving_or_waiting = true
			var hint: String = TollScript.get_hint_text(state)
			if hint.is_empty() or hint.find("门票") < 0:
				printerr("[TestTollMechanics] 储蓄/等待期提示文案缺失: ", phase)
				return false
		if phase == TollScript.PHASE_WAITING:
			saw_waiting = true
		if state.toll_escrow != NumScript.ZERO:
			saw_escrow = true
			# E4: 托管金币不进入净财富压力
			var delta_with: float = state.get_wealth_pressure_hp_delta()
			var escrow_saved: float = state.toll_escrow
			state.toll_escrow = NumScript.ZERO
			var delta_without: float = state.get_wealth_pressure_hp_delta()
			state.toll_escrow = escrow_saved
			if absf(delta_with - delta_without) > EPS:
				wealth_with_escrow_ok = false
		if state.paid_gate_tier >= 1 and state.current_stage >= 101:
			passed_tick = t
			break

	if passed_tick < 0:
		printerr("[TestTollMechanics] 零操作 ", MAX_ZERO_OP_TICKS, " ticks 内未通过第 100 层门! stage=", state.current_stage, " paid=", state.paid_gate_tier)
		return false
	if not saw_saving_or_waiting or not saw_escrow:
		printerr("[TestTollMechanics] 未观察到储蓄模式/托管账户")
		return false
	if not wealth_with_escrow_ok:
		printerr("[TestTollMechanics] 托管金币被计入净财富 (违反 E4)")
		return false
	if state.run_best < 101 or state.gate_boss_cleared:
		printerr("[TestTollMechanics] 过门后状态异常")
		return false
	print("[TestTollMechanics] 零操作自行通过第 100 层门: tick=", passed_tick, ", 等待态=", saw_waiting, ", run_best=", state.run_best)
	return true

static func _test_wall_hints() -> bool:
	var bal: BalanceScript = BalanceScript.load_default() as BalanceScript
	var shield_state: SimStateScript = SimStateScript.new(1, bal)
	shield_state.current_stage = 150
	shield_state.farm_stage = 150
	shield_state.run_best = 150
	shield_state.boss_fail_streak = bal.wall_signal_fail_streak - 1
	if TollScript.get_phase(shield_state) != TollScript.PHASE_NONE:
		printerr("[TestTollMechanics] 连败不足 N 次不应提示卡墙")
		return false
	shield_state.boss_fail_streak = bal.wall_signal_fail_streak
	if TollScript.get_phase(shield_state) != TollScript.PHASE_WALL_SHIELD or TollScript.get_hint_text(shield_state).find("护盾") < 0:
		printerr("[TestTollMechanics] 护盾墙文案错误: ", TollScript.get_hint_text(shield_state))
		return false
	var power_state: SimStateScript = SimStateScript.new(2, bal)
	power_state.current_stage = 60
	power_state.farm_stage = 60
	power_state.run_best = 60
	power_state.boss_fail_streak = bal.wall_signal_fail_streak
	if TollScript.get_phase(power_state) != TollScript.PHASE_WALL_POWER or TollScript.get_hint_text(power_state).find("借钱") < 0:
		printerr("[TestTollMechanics] 数值墙文案错误")
		return false
	print("[TestTollMechanics] 卡墙文案(护盾墙/数值墙)与阈值验证通过")
	return true