class_name SignatureAffixes extends RefCounted

## 三大签名特效词条定义工厂 (依据《02_系统架构与数值_v6.md》§6.2)

const AffixDefScript = preload("res://simulation/affix/AffixDef.gd")
const TriggerDefScript = preload("res://simulation/affix/TriggerDef.gd")
const EffectDefScript = preload("res://simulation/affix/EffectDef.gd")
const SimEventScript = preload("res://simulation/events/SimEvent.gd")

static func create_chain_lightning() -> AffixDefScript:
	var affix: AffixDefScript = AffixDefScript.new("chain_lightning", "连锁闪电", false)
	affix.desc_template = "暴击触发连锁闪电，对排队目标造成溅射伤害"
	affix.budget_per_tick = 8

	var trig: TriggerDefScript = TriggerDefScript.new()
	trig.event_type = SimEventScript.T.CRIT
	trig.mode = TriggerDefScript.Mode.ALWAYS
	affix.trigger = trig

	var eff: EffectDefScript = EffectDefScript.new()
	eff.vfx_key = "chain_lightning"
	eff.emit_event_type = SimEventScript.T.HIT
	eff.damage_mult = 0.6
	eff.splash_count = 3
	eff.splash_decay = 0.8
	affix.effect = eff

	return affix

static func create_drop_explosion() -> AffixDefScript:
	var affix: AffixDefScript = AffixDefScript.new("drop_explosion", "落地即爆", false)
	affix.desc_template = "掉落物落地引发冲击波，造成品质溅射伤害"
	affix.budget_per_tick = 12

	var trig: TriggerDefScript = TriggerDefScript.new()
	trig.event_type = SimEventScript.T.DROP
	trig.mode = TriggerDefScript.Mode.ALWAYS
	affix.trigger = trig

	var eff: EffectDefScript = EffectDefScript.new()
	eff.vfx_key = "drop_explosion"
	eff.emit_event_type = SimEventScript.T.HIT
	eff.damage_mult = 1.0
	eff.splash_count = 0
	affix.effect = eff

	return affix

static func create_killing_frenzy() -> AffixDefScript:
	var affix: AffixDefScript = AffixDefScript.new("killing_frenzy", "杀戮狂热", false)
	affix.desc_template = "击杀后叠加攻速增益，无击杀超时清零"
	affix.budget_per_tick = 10

	var trig: TriggerDefScript = TriggerDefScript.new()
	trig.event_type = SimEventScript.T.KILL
	trig.mode = TriggerDefScript.Mode.ALWAYS
	affix.trigger = trig

	var eff: EffectDefScript = EffectDefScript.new()
	eff.vfx_key = "killing_frenzy"
	eff.should_emit_event = false
	eff.apply_buff_key = "killing_frenzy"
	eff.buff_duration_ticks = 20
	eff.buff_max_stacks = 10
	eff.buff_stat = "atk_speed_pct"
	eff.buff_val_per_stack = 0.15
	affix.effect = eff

	return affix
