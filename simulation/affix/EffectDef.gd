class_name EffectDef extends Resource

## 词条效果执行定义 (依据《02_系统架构与数值_v6.md》§2.3–§2.4 & §6.2)

const SimEventScript = preload("res://simulation/events/SimEvent.gd")
const BuffsScript = preload("res://simulation/events/Buffs.gd")
const NumScript = preload("res://core/num/Num.gd")
const StatSheetScript = preload("res://simulation/StatSheet.gd")

@export var vfx_key: String = ""
@export var emit_event_type: SimEventScript.T = SimEventScript.T.HIT
@export var should_emit_event: bool = true

@export var damage_mult: float = 1.0
@export var damage_pct_max_hp: float = 0.0
@export var boss_max_hp_pct_scale: float = 0.25
@export var splash_count: int = 0
@export var splash_decay: float = 0.8
@export var force_crit: bool = false                 # 必定暴击 (处刑之锤)
@export var damage_gold_balance_pct: float = 0.0     # 伤害 = 金币余额 × 该比例 (金币风暴)
@export var extra_drop_rolls: int = 0               # 额外整套掉落判定次数 (终焉喷泉 ×5 = 4 次额外)
@export var grant_charge_key: String = ""           # 授予充能 (暗金雨)
@export var charge_max: int = 1
@export var launch_mul: float = 1.0                 # 表现层提示：喷射高度倍率 (暴击余韵 1.2)

@export var apply_buff_key: String = ""
@export var buff_duration_ticks: int = 0
@export var buff_max_stacks: int = 1
@export var buff_stat: String = ""
@export var buff_val_per_stack: float = 0.0

## 执行词条效果，返回派生出的 SimEvent 数组
func execute(ev: SimEventScript, state: RefCounted, _rolls: Dictionary = {}) -> Array[SimEventScript]:
	var out_events: Array[SimEventScript] = []

	if not apply_buff_key.is_empty() and state != null and state.get("buffs") != null:
		var buffs_mgr: BuffsScript = state.get("buffs") as BuffsScript
		if buffs_mgr != null:
			buffs_mgr.add_buff(
				apply_buff_key,
				buff_duration_ticks,
				buff_max_stacks,
				buff_stat,
				buff_val_per_stack,
				{"vfx_key": vfx_key, "launch_mul": launch_mul}
			)

	if not grant_charge_key.is_empty() and state != null and state.get("buffs") != null:
		(state.get("buffs") as BuffsScript).add_charge(grant_charge_key, 1, charge_max, {"vfx_key": vfx_key})

	if extra_drop_rolls > 0 and state != null:
		var bonus_events: Array = state.call("grant_bonus_drops", extra_drop_rolls, ev.type == SimEventScript.T.BOSS_KILL) as Array
		for be_var: Variant in bonus_events:
			out_events.push_back(be_var as SimEventScript)

	if should_emit_event:
		var base_dmg_log: float = ev.value
		var src_is_damage: bool = (
			ev.type == SimEventScript.T.HIT
			or ev.type == SimEventScript.T.CRIT
			or ev.type == SimEventScript.T.METEOR
		)
		if not src_is_damage and state != null and state.get("stats") != null:
			# 非伤害类触发源（掉落/熔炼/击杀）：以玩家当前单次基础命中伤害为基准 (§6.2 品质系数 × 单次伤害)
			base_dmg_log = (state.get("stats") as StatSheetScript).get_base_hit_damage_log()
		if damage_gold_balance_pct > 0.0 and state != null:
			var gold_log: float = float(state.get("gold"))
			if gold_log == NumScript.ZERO:
				return out_events
			base_dmg_log = gold_log + NumScript.from_float(damage_gold_balance_pct)
		elif damage_pct_max_hp > 0.0 and state != null:
			var max_hp_log: float = float(state.get("mob_max_hp_log"))
			var pct: float = damage_pct_max_hp
			if bool(state.get("is_boss")):
				pct *= boss_max_hp_pct_scale
			base_dmg_log = max_hp_log + NumScript.from_float(pct)
		elif damage_mult != 1.0:
			base_dmg_log += NumScript.from_float(damage_mult)

		if force_crit and state != null and state.get("stats") != null:
			base_dmg_log += NumScript.from_float((state.get("stats") as StatSheetScript).crit_mult)

		var primary_ev: SimEventScript = SimEventScript.new(emit_event_type, base_dmg_log, 1)
		primary_ev.hint = {
			"vfx_key": vfx_key,
			"damage_mult": damage_mult,
			"source_ev_type": int(ev.type)
		}
		if ev.payload.has("rarity"):
			primary_ev.hint["rarity"] = ev.payload["rarity"]

		out_events.push_back(primary_ev)

		if splash_count > 0:
			var cur_dmg_log: float = base_dmg_log
			for i in range(1, splash_count + 1):
				cur_dmg_log += NumScript.from_float(splash_decay)
				var splash_ev: SimEventScript = SimEventScript.new(emit_event_type, cur_dmg_log, 1)
				splash_ev.hint = {
					"vfx_key": vfx_key,
					"is_splash": true,
					"jump_index": i,
					"decay": splash_decay
				}
				out_events.push_back(splash_ev)

	return out_events
