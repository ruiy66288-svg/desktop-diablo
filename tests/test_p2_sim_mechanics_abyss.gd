class_name TestP2SimMechanicsAbyss extends RefCounted

## Phase 1.5 + Phase 2 模拟内核专项验收：
## 1) 100–600+ 区间机制 (shield / backlash / crit_only / split_boss / gold_devour) + 30% 跨段残留 + 600+ 双机制轮转
## 2) 卡关归因 (get_wall_hint / ItemInstance.counters) 与 Attention Signals 去重/优先级/ACK
## 3) 12 个标志性词条 (.tres 加载 + 新机制触发验证)
## 4) 深渊轮回 (run_best >= 100, ΔM, Q35 债务转化, 宝库威能萃取与槽位上限)
## 5) 12 节点科技树 (印记门槛, 双贷, 还款折扣, 24h 离线上限, 自动还款) + 存档往返

const BalanceScript = preload("res://simulation/Balance.gd")
const SimStateScript = preload("res://simulation/SimState.gd")
const SimRunnerScript = preload("res://simulation/SimRunner.gd")
const CommandScript = preload("res://simulation/commands/Command.gd")
const EventQueueScript = preload("res://simulation/events/EventQueue.gd")
const SimEventScript = preload("res://simulation/events/SimEvent.gd")
const BandRulesScript = preload("res://simulation/mechanics/BandRules.gd")
const MechanicDefScript = preload("res://simulation/mechanics/MechanicDef.gd")
const CombatScript = preload("res://simulation/combat/Combat.gd")
const SpawnerScript = preload("res://simulation/combat/Spawner.gd")
const SignatureAffixesScript = preload("res://simulation/affix/SignatureAffixes.gd")
const AffixDefScript = preload("res://simulation/affix/AffixDef.gd")
const ItemInstanceScript = preload("res://simulation/loot/ItemInstance.gd")
const SignalsScript = preload("res://simulation/attention/Signals.gd")
const SaveServiceScript = preload("res://persistence/SaveService.gd")
const OfflineCalcScript = preload("res://offline/OfflineCalc.gd")
const NumScript = preload("res://core/num/Num.gd")

const T0: int = 1_800_000_000

static func run() -> bool:
	print("[TestP2Sim] 开始 Phase 2 模拟内核专项验收...")
	if not _test_band_rules_and_mechanics():
		return false
	if not _test_wall_hint_and_signals():
		return false
	if not _test_12_affixes():
		return false
	if not _test_abyss_prestige_and_vault():
		return false
	if not _test_tech_12_and_save_roundtrip():
		return false
	print("[TestP2Sim] Phase 2 模拟内核专项验收 100% 通过!")
	return true

static func _make_state(seed_val: int = 2026) -> SimStateScript:
	var bal: BalanceScript = BalanceScript.load_default() as BalanceScript
	var state: SimStateScript = SimStateScript.new(seed_val, bal)
	state.tech.debug_seconds_mode = true
	return state

static func _make_item_with_affix(slot: ItemInstanceScript.Slot, affix_id: String, rarity: ItemInstanceScript.Rarity = ItemInstanceScript.Rarity.UNIQUE) -> ItemInstanceScript:
	var item: ItemInstanceScript = ItemInstanceScript.new(
		9001,
		"测试装备_" + affix_id,
		slot,
		rarity,
		100,
		3.0
	)
	var affix: AffixDefScript = SignatureAffixesScript.get_by_id(affix_id)
	if affix != null:
		item.affixes.push_back(affix)
	return item

static func _test_band_rules_and_mechanics() -> bool:
	var bal: BalanceScript = BalanceScript.load_default() as BalanceScript
	var combat: CombatScript = CombatScript.new()

	# 1-100 无机制，确保 WP-03 10k tick 确定性哈希不变
	var s100: Dictionary = BandRulesScript.get_strengths(100, bal)
	if not s100.is_empty():
		printerr("[TestP2Sim] stage 100 不应有区间机制: ", s100)
		return false
	# 101: shield=1.0
	var s101: Dictionary = BandRulesScript.get_strengths(101, bal)
	if not is_equal_approx(float(s101.get(int(MechanicDefScript.Kind.SHIELD), 0.0)), 1.0):
		printerr("[TestP2Sim] stage 101 shield 强度应为 1.0: ", s101)
		return false
	# 201: backlash=1.0 + shield=0.3 残留
	var s201: Dictionary = BandRulesScript.get_strengths(201, bal)
	if not is_equal_approx(float(s201.get(int(MechanicDefScript.Kind.BACKLASH), 0.0)), 1.0) or not is_equal_approx(float(s201.get(int(MechanicDefScript.Kind.SHIELD), 0.0)), 0.3):
		printerr("[TestP2Sim] stage 201 应为 backlash=1.0 + shield=0.3: ", s201)
		return false
	# 600+: 双机制轮转
	var s600: Dictionary = BandRulesScript.get_strengths(600, bal)
	if s600.size() < 2:
		printerr("[TestP2Sim] stage 600 应激活双机制轮转: ", s600)
		return false

	# 实测 shield (101) 刷怪带护盾
	var state: SimStateScript = _make_state(101)
	state.current_stage = 101
	state.farm_stage = 101
	state.run_best = 101
	state.all_time_best = 101
	SpawnerScript.spawn_next(state)
	if state.mob_shield_max_log <= NumScript.ZERO or state.mob_shield_cur_log <= NumScript.ZERO:
		printerr("[TestP2Sim] stage 101 怪物应带有能量护盾")
		return false

	# 实测 backlash (205): 普攻叠层至 40 眩晕 2.0s，衍生伤害不叠层
	var state_bl: SimStateScript = _make_state(205)
	var q_bl: EventQueueScript = EventQueueScript.new()
	state_bl.current_stage = 205
	state_bl.farm_stage = 205
	state_bl.run_best = 205
	state_bl.all_time_best = 205
	state_bl.stats.base_gold_atk_log = 1.0
	state_bl.stats.crit_rate = 0.0
	state_bl.stats.atk_interval = 0.1
	SpawnerScript.spawn_next(state_bl)
	state_bl.mob_max_hp_log = 20.0
	state_bl.mob_current_hp_log = 20.0
	state_bl.mob_shield_cur_log = NumScript.ZERO
	state_bl.mob_shield_max_log = NumScript.ZERO
	combat.apply_derived_damage(1.0, state_bl, q_bl)
	if state_bl.backlash_stacks != 0.0:
		printerr("[TestP2Sim] 衍生伤害不应叠加反伤层数, 实际: ", state_bl.backlash_stacks)
		return false
	state_bl.backlash_stacks = 39.0
	state_bl.atk_progress = 1.0
	combat.step_tick(0.1, state_bl, q_bl)
	if state_bl.stun_remaining_sec <= 0.0 or state_bl.backlash_stacks != 0.0:
		printerr("[TestP2Sim] 第 40 层反伤应触发眩晕并清零层数: stun=", state_bl.stun_remaining_sec, " stacks=", state_bl.backlash_stacks)
		return false

	# 实测 crit_only (305): 非暴击仅造成 5% 伤害，记录吸收量到 mech_absorbed_log[CRIT_ONLY]
	var state_co: SimStateScript = _make_state(305)
	var q_co: EventQueueScript = EventQueueScript.new()
	state_co.current_stage = 305
	state_co.farm_stage = 305
	state_co.run_best = 305
	state_co.all_time_best = 305
	state_co.stats.base_gold_atk_log = 2.0 # 100
	state_co.stats.crit_rate = 0.0
	state_co.stats.atk_interval = 0.1
	SpawnerScript.spawn_next(state_co)
	state_co.mob_max_hp_log = 10.0
	state_co.mob_current_hp_log = 10.0
	state_co.mob_shield_cur_log = NumScript.ZERO
	state_co.mob_shield_max_log = NumScript.ZERO
	state_co.atk_progress = 1.0
	combat.step_tick(0.1, state_co, q_co)
	if state_co.mech_absorbed_log[MechanicDefScript.Kind.CRIT_ONLY] <= NumScript.ZERO:
		printerr("[TestP2Sim] crit_only 应记录吸收伤害到 mech_absorbed_log")
		return false

	# 实测 split_boss (405): Boss HP <= 50% 分裂 4 个分身
	var state_sb: SimStateScript = _make_state(405)
	var q_sb: EventQueueScript = EventQueueScript.new()
	state_sb.current_stage = 405
	state_sb.farm_stage = 405
	state_sb.run_best = 405
	state_sb.all_time_best = 405
	state_sb.mobs_killed_in_stage = state_sb.balance.mobs_per_stage
	SpawnerScript.spawn_next(state_sb)
	state_sb.is_boss = true
	state_sb.mob_max_hp_log = 4.0 # 10000
	state_sb.mob_current_hp_log = NumScript.from_float(4000.0)
	state_sb.mob_shield_cur_log = NumScript.ZERO
	state_sb.mob_shield_max_log = NumScript.ZERO
	state_sb.stats.base_gold_atk_log = 2.0
	state_sb.stats.crit_rate = 0.0
	state_sb.stats.atk_interval = 0.1
	state_sb.atk_progress = 1.0
	combat.step_tick(0.1, state_sb, q_sb)
	if not state_sb.boss_clone_triggered or state_sb.boss_clones_remaining != 3:
		printerr("[TestP2Sim] split_boss 应在 <=50% HP 时分裂分身: triggered=", state_sb.boss_clone_triggered, " rem=", state_sb.boss_clones_remaining)
		return false

	# 实测 gold_devour (505): 吞噬受 50% 近期收入封顶且不碰 toll_escrow
	var state_gd: SimStateScript = _make_state(505)
	var q_gd: EventQueueScript = EventQueueScript.new()
	state_gd.current_stage = 505
	state_gd.farm_stage = 505
	state_gd.run_best = 505
	state_gd.all_time_best = 505
	state_gd.gold = 6.0 # 1e6
	state_gd.toll_escrow = 4.0 # 1e4
	state_gd.recent_income_per_sec_log = 2.0 # 100/s -> cap 50/s
	SpawnerScript.spawn_next(state_gd)
	state_gd.mob_max_hp_log = 20.0
	state_gd.mob_current_hp_log = 20.0
	state_gd.stats.atk_interval = 100.0
	state_gd.atk_progress = 0.0
	var gold_before: float = NumScript.to_float(state_gd.gold)
	combat.step_tick(0.1, state_gd, q_gd)
	var lost: float = gold_before - NumScript.to_float(state_gd.gold)
	if lost <= 0.0 or lost > 6.0: # 0.1s * 50/s = 5.0
		printerr("[TestP2Sim] gold_devour 0.1s 吞噬应受 50% 收入封顶 (~5.0), 实际损失: ", lost)
		return false
	if not is_equal_approx(state_gd.toll_escrow, 4.0):
		printerr("[TestP2Sim] gold_devour 严禁动用 toll_escrow")
		return false

	return true

static func _test_wall_hint_and_signals() -> bool:
	var state: SimStateScript = _make_state(303)
	state.current_stage = 105
	state.farm_stage = 105
	state.run_best = 105
	state.all_time_best = 105
	state.boss_fail_streak = 5
	state.mech_absorbed_log[MechanicDefScript.Kind.SHIELD] = 3.0 # 1000
	state.mech_dealt_log = 2.0 # 100
	var hint: Dictionary = state.get_wall_hint()
	if not bool(hint.get("active", false)) or String(hint.get("mechanic_id", "")) != "shield":
		printerr("[TestP2Sim] get_wall_hint 应触发 shield 归因: ", hint)
		return false
	var item_counter: ItemInstanceScript = _make_item_with_affix(ItemInstanceScript.Slot.WEAPON, "multi_strike")
	if not item_counter.counters(["multi_hit", "chain"]):
		printerr("[TestP2Sim] multi_strike 应克制 multi_hit/chain")
		return false

	# Signals 优先级与去重与 ACK
	var q: EventQueueScript = EventQueueScript.new()
	state.update_attention_signals(q)
	if not state.signals.is_active(SignalsScript.Kind.WALL_HINT):
		printerr("[TestP2Sim] update_attention_signals 应激活 WALL_HINT")
		return false
	state.raise_signal(SignalsScript.Kind.RESEARCH_DONE, {"node_id": "test"}, q)
	state.raise_signal(SignalsScript.Kind.RESEARCH_DONE, {"node_id": "test"}, q)
	if state.signals.get_active_kinds().size() != 2:
		printerr("[TestP2Sim] 相同 Kind 信号应去重, 实际数量: ", state.signals.get_active_kinds().size())
		return false
	var top: Dictionary = state.signals.get_top()
	if int(top.get("kind", -1)) != SignalsScript.Kind.RESEARCH_DONE:
		printerr("[TestP2Sim] RESEARCH_DONE 优先级应高于 WALL_HINT, 实际 top: ", top)
		return false
	var runner: SimRunnerScript = SimRunnerScript.new(state)
	runner.push_command(CommandScript.make_ack_signal(SignalsScript.Kind.RESEARCH_DONE))
	runner.step()
	if state.signals.is_active(SignalsScript.Kind.RESEARCH_DONE):
		printerr("[TestP2Sim] ACK_SIGNAL 应消除对应信号")
		return false
	return true

static func _test_12_affixes() -> bool:
	var all_defs: Array[AffixDefScript] = SignatureAffixesScript.create_all()
	if all_defs.size() != 12:
		printerr("[TestP2Sim] 应加载 12 个标志性词条, 实际: ", all_defs.size())
		return false
	var expected_ids: Array[String] = [
		"chain_lightning", "drop_explosion", "killing_frenzy",
		"executioner_hammer", "gold_storm", "meteor_shower",
		"doomsday_fountain", "crit_afterglow", "unique_rain",
		"multi_strike", "deadly_precision", "usurer_ward",
	]
	for aid: String in expected_ids:
		if SignatureAffixesScript.get_by_id(aid) == null:
			printerr("[TestP2Sim] 缺失词条定义: ", aid)
			return false

	var combat: CombatScript = CombatScript.new()

	# 验证 executioner_hammer 满 25 个 TIMER 触发爆发必定暴击
	var state_eh: SimStateScript = _make_state(404)
	state_eh.resolver.collect_processed = true
	var q_eh: EventQueueScript = EventQueueScript.new()
	state_eh.equip_slots.equip(_make_item_with_affix(ItemInstanceScript.Slot.WEAPON, "executioner_hammer"), state_eh)
	for i: int in range(25):
		q_eh.push_back(SimEventScript.new(SimEventScript.T.TIMER, 0.0, 1))
	state_eh.resolver.resolve_tick(state_eh, q_eh, null)
	if state_eh.resolver.derived_damage_events.is_empty():
		printerr("[TestP2Sim] executioner_hammer 满 25 次 TIMER 未触发衍生伤害")
		return false

	# 验证 unique_rain 充能与击杀消耗
	var state_ur: SimStateScript = _make_state(505)
	var q2: EventQueueScript = EventQueueScript.new()
	state_ur.buffs.add_charge("unique_rain", 1, 1)
	if state_ur.buffs.get_charges("unique_rain") != 1:
		printerr("[TestP2Sim] Buffs 充能机制异常")
		return false
	SpawnerScript.spawn_next(state_ur)
	state_ur.mob_max_hp_log = 0.0
	state_ur.mob_current_hp_log = 0.0
	state_ur.stats.base_gold_atk_log = 3.0
	state_ur.stats.atk_interval = 0.1
	state_ur.atk_progress = 1.0
	combat.step_tick(0.1, state_ur, q2)
	if state_ur.buffs.get_charges("unique_rain") != 0:
		printerr("[TestP2Sim] 击杀后未消耗 unique_rain 充能")
		return false
	return true

static func _test_abyss_prestige_and_vault() -> bool:
	var state: SimStateScript = _make_state(606)
	state.all_time_best = 99
	state.run_best = 99
	if bool(state.get_abyss_prestige_preview().get("can_prestige", false)):
		printerr("[TestP2Sim] run_best=99 不应允许深渊轮回")
		return false

	state.all_time_best = 400
	state.run_best = 400 # (400/100)^1.5 = 8
	state.current_stage = 400
	state.farm_stage = 350
	state.gold = 5.0
	state.souls = 3.0
	state.equip_slots.equip(_make_item_with_affix(ItemInstanceScript.Slot.WEAPON, "deadly_precision", ItemInstanceScript.Rarity.PRIMAL), state)
	var extractable: Array[String] = state.collect_extractable_affix_ids()
	if not extractable.has("deadly_precision"):
		printerr("[TestP2Sim] 应可萃取已装备的 deadly_precision")
		return false

	var preview: Dictionary = state.get_abyss_prestige_preview()
	var expected_marks: int = state.balance.get_pending_marks(state.all_time_best)
	if not bool(preview.get("can_prestige", false)) or int(preview.get("pending_marks", 0)) != expected_marks:
		printerr("[TestP2Sim] 400 层深渊轮回预览应得 ", expected_marks, " 印记: ", preview)
		return false

	var gained: int = state.perform_abyss_prestige("deadly_precision")
	if gained != expected_marks or state.marks != expected_marks:
		printerr("[TestP2Sim] 深渊轮回后印记应为 ", expected_marks, ", 实际: ", state.marks)
		return false
	if state.current_stage != 1 or state.run_best != 1 or state.all_time_best != 400:
		printerr("[TestP2Sim] 深渊轮回层数重置/保留异常")
		return false
	if not state.unlocked_vault_powers.has("deadly_precision"):
		printerr("[TestP2Sim] 应已解锁 deadly_precision 宝库威能")
		return false
	# marks=5 -> 1 + floor(5/5) = 2 槽
	if state.get_max_vault_slots() != 2:
		printerr("[TestP2Sim] marks=5 时宝库槽位应为 2, 实际: ", state.get_max_vault_slots())
		return false
	if not state.vault_powers.has("deadly_precision"):
		printerr("[TestP2Sim] 萃取后应自动装配进空闲威能槽")
		return false
	if state.stats.crit_mult <= state.balance.base_crit_mult:
		printerr("[TestP2Sim] 宝库威能 deadly_precision 应直接提升暴伤面板")
		return false
	if not state.unequip_vault_power("deadly_precision"):
		printerr("[TestP2Sim] 应成功卸下宝库威能")
		return false
	if not state.equip_vault_power("deadly_precision"):
		printerr("[TestP2Sim] 卸下后应可重新装备宝库威能")
		return false
	return true

static func _test_tech_12_and_save_roundtrip() -> bool:
	var state: SimStateScript = _make_state(707)
	# 未获得印记前不可研究 tier-5 深渊节点 combat_mastery
	state.gold = 20.0
	if state.start_research("combat_mastery", T0):
		printerr("[TestP2Sim] 无印记且无前置时不应可研究 combat_mastery")
		return false

	# 双贷与还款折扣与 24h 离线
	state.tech.mark_researched("credit_dual_loan")
	state.tech.mark_researched("credit_discount")
	state.tech.mark_researched("offline_cap_24h")
	state.recalculate_stats()
	if state.credit.get_max_concurrent_loans(state.balance) != 2:
		printerr("[TestP2Sim] credit_dual_loan 应使同时贷款上限=2")
		return false
	if state.credit.repay_discount <= 0.0:
		printerr("[TestP2Sim] credit_discount 应使还款折扣 > 0")
		return false

	var off_res: Dictionary = OfflineCalcScript.settle(state, 100000, T0 + 100000)
	if int(off_res.get("effective_seconds", 0)) != 86400:
		printerr("[TestP2Sim] offline_cap_24h 应将离线封顶提升至 86400s, 实际: ", off_res)
		return false

	# SaveService 序列化/反序列化 Phase 2 字段
	state.marks = 5
	state.unlocked_vault_powers = ["deadly_precision", "usurer_ward"]
	state.vault_powers = ["deadly_precision"]
	state.backlash_stacks = 12.0
	state.credit.loan_count = 1
	var save_dict: Dictionary = SaveServiceScript.serialize(state)
	var loaded: SimStateScript = SaveServiceScript.deserialize(save_dict, state.balance)
	if loaded == null:
		printerr("[TestP2Sim] SaveService.deserialize 返回 null")
		return false
	if loaded.marks != 5 or loaded.vault_powers.size() != 1 or loaded.unlocked_vault_powers.size() != 2:
		printerr("[TestP2Sim] 存档往返未保留 marks/vault_powers")
		return false
	if loaded.backlash_stacks != 12.0 or loaded.credit.loan_count != 1:
		printerr("[TestP2Sim] 存档往返未保留 backlash_stacks/loan_count")
		return false
	return true
