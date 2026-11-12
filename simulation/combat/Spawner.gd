class_name Spawner extends RefCounted

## 确定性怪物生成器 (依据《02_系统架构与数值_v6.md》§0 Q3、§1.3、§5.1 与《00_开发执行总纲.md》§2 E3/E4)
## 纯 RefCounted，零 Node 依赖

const SimStateScript = preload("res://simulation/SimState.gd")
const BalanceScript = preload("res://simulation/Balance.gd")
const NumScript = preload("res://core/num/Num.gd")
const BandRulesScript = preload("res://simulation/mechanics/BandRules.gd")

static func spawn_next(state: SimStateScript) -> void:
	_spawn_core(state)
	_apply_band_shield(state)

## 每 100 层主题机制：护盾 (§7.1) —— 护盾量 = 强度 × 50% 最大生命；每次命中最多削掉 强度 × strip% 最大生命
static func _apply_band_shield(state: SimStateScript) -> void:
	var bal: BalanceScript = state.balance
	var strength: float = BandRulesScript.get_shield_strength(state.get_active_stage(), bal)
	if strength <= 0.0:
		state.mob_shield_max_log = NumScript.ZERO
		state.mob_shield_cur_log = NumScript.ZERO
		state.mob_shield_strip_cap_log = NumScript.ZERO
		return
	state.mob_shield_max_log = state.mob_max_hp_log + NumScript.from_float(strength * bal.mech_shield_hp_ratio)
	state.mob_shield_cur_log = state.mob_shield_max_log
	state.mob_shield_strip_cap_log = state.mob_max_hp_log + NumScript.from_float(strength * bal.mech_shield_max_hit_strip)

static func _spawn_core(state: SimStateScript) -> void:
	# 1. 若处于退回刷怪状态 (farm_stage < current_stage)，检查是否已变强可自动重试 Boss (Q3 & E3)
	if state.farm_stage < state.current_stage:
		if state.should_retry_current_stage():
			state.farm_stage = state.current_stage
			state.farm_kills_since_retreat = 0
			state.mobs_killed_in_stage = state.balance.mobs_per_stage
		else:
			var farm_delta_hp: float = state.get_wealth_pressure_hp_delta(state.farm_stage)
			state.is_boss = false
			state.boss_timer = 0.0
			state.mob_max_hp_log = state.balance.get_monster_hp_log(state.farm_stage) + farm_delta_hp
			state.mob_current_hp_log = state.mob_max_hp_log
			return

	# 2. 若当前分界层 Boss 已击杀但等待攒够门票过门，继续在该层刷普通小怪攒托管门票 (§7.3)
	if state.gate_boss_cleared:
		var gate_delta_hp: float = state.get_wealth_pressure_hp_delta(state.current_stage)
		state.is_boss = false
		state.boss_timer = 0.0
		state.mob_max_hp_log = state.balance.get_monster_hp_log(state.current_stage) + gate_delta_hp
		state.mob_current_hp_log = state.mob_max_hp_log
		return

	# 3. 正常推进层 (farm_stage == current_stage)：10 只小怪后生成 15 秒限时 Boss
	var stage_delta_hp: float = state.get_wealth_pressure_hp_delta(state.current_stage)
	if state.mobs_killed_in_stage < state.balance.mobs_per_stage:
		state.is_boss = false
		state.boss_timer = 0.0
		state.mob_max_hp_log = state.balance.get_monster_hp_log(state.current_stage) + stage_delta_hp
		state.mob_current_hp_log = state.mob_max_hp_log
	else:
		state.is_boss = true
		state.boss_timer = 0.0
		state.mob_max_hp_log = state.balance.get_boss_hp_log(state.current_stage) + stage_delta_hp
		state.mob_current_hp_log = state.mob_max_hp_log
