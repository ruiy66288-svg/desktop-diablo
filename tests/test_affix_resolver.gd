class_name TestAffixResolver extends RefCounted

## 词条解析器、四重保险与六槽换装测试套件 (WP-10, WP-11, WP-12)

const SimStateScript = preload("res://simulation/SimState.gd")
const SimEvent = preload("res://simulation/events/SimEvent.gd")
const EventQueue = preload("res://simulation/events/EventQueue.gd")
const AffixResolver = preload("res://simulation/events/AffixResolver.gd")
const TriggerDef = preload("res://simulation/affix/TriggerDef.gd")
const EffectDef = preload("res://simulation/affix/EffectDef.gd")
const AffixDef = preload("res://simulation/affix/AffixDef.gd")
const SignatureAffixes = preload("res://simulation/affix/SignatureAffixes.gd")
const ItemInstance = preload("res://simulation/loot/ItemInstance.gd")
const EquipSlots = preload("res://simulation/progression/EquipSlots.gd")
const DryRun = preload("res://simulation/commands/DryRun.gd")
const Num = preload("res://core/num/Num.gd")
const EventCompactor = preload("res://simulation/events/EventCompactor.gd")
const SimRunnerScript = preload("res://simulation/SimRunner.gd")
const CombatScript = preload("res://simulation/combat/Combat.gd")
const BalanceScript = preload("res://simulation/Balance.gd")

static func run_all_tests() -> bool:
	print("--- Running TestAffixResolver ---")
	var ok: bool = true
	ok = ok and test_counter_trigger_no_lost_counts()
	ok = ok and test_causal_chain_and_recursion_shield()
	ok = ok and test_signature_affixes_integration()
	ok = ok and test_dry_run_determinism()
	ok = ok and test_stress_100x_attacks_6000_ticks()
	ok = ok and test_event_compactor_conserves_counts()
	ok = ok and test_runner_affix_pipeline_frenzy_and_damage()
	ok = ok and test_runner_stress_100x_real_pipeline()
	ok = ok and test_equip_six_slots_and_dry_run_delta()
	print("TestAffixResolver: ", "PASSED" if ok else "FAILED")
	return ok

## 1. 验证计数型触发器绝对不丢数 (02 号文件 §2.3 铁律)
static func test_counter_trigger_no_lost_counts() -> bool:
	var trig = TriggerDef.new()
	trig.event_type = SimEvent.T.SMELT
	trig.mode = TriggerDef.Mode.COUNTER
	trig.threshold = 50

	var runtime: Dictionary = {"acc": 0}
	var total_fires: int = 0

	# 批次输入 12, 38, 70, 5 件熔炼 (总数 125)
	var batch = [12, 38, 70, 5]
	for count in batch:
		var ev = SimEvent.new(SimEvent.T.SMELT, 0.0, count)
		var f = trig.consume(ev, runtime, 1)
		total_fires += f

	# 125 件 / 50 = 触发 2 次，剩余 25 件在 runtime.acc
	if total_fires != 2:
		printerr("Counter trigger failed: fires expected 2, got ", total_fires)
		return false
	if runtime.acc != 25:
		printerr("Counter trigger failed: acc expected 25, got ", runtime.acc)
		return false

	print("  [✓] Counter trigger accumulator & no lost counts passed")
	return true

## 2. 验证因果链掩码 (chain_mask) 与深度上限防死循环
static func test_causal_chain_and_recursion_shield() -> bool:
	var resolver = AffixResolver.new()
	var queue = EventQueue.new()
	var state = SimStateScript.new(12345)

	# 创建两个相互触发的死循环词条 A 和 B
	# A: 受到 HIT 触发 HIT (效果)
	var af_a = AffixDef.new("loop_a", "死循环A", false)
	var tr_a = TriggerDef.new()
	tr_a.event_type = SimEvent.T.HIT
	tr_a.mode = TriggerDef.Mode.ALWAYS
	af_a.trigger = tr_a
	var ef_a = EffectDef.new()
	ef_a.emit_event_type = SimEvent.T.HIT
	ef_a.damage_mult = 1.0
	af_a.effect = ef_a

	# B: 受到 HIT 也触发 HIT (效果)
	var af_b = AffixDef.new("loop_b", "死循环B", false)
	var tr_b = TriggerDef.new()
	tr_b.event_type = SimEvent.T.HIT
	tr_b.mode = TriggerDef.Mode.ALWAYS
	af_b.trigger = tr_b
	var ef_b = EffectDef.new()
	ef_b.emit_event_type = SimEvent.T.HIT
	ef_b.damage_mult = 1.0
	af_b.effect = ef_b

	resolver.register_listener(af_a, 0, 0)
	resolver.register_listener(af_b, 0, 1)

	# 压入一个初始 HIT 事件
	queue.push_back(SimEvent.new(SimEvent.T.HIT, 10.0, 1))

	var processed = resolver.resolve_tick(state, queue, null)

	# 验证：因为 chain_mask 阻止同因果链重复触发，系统绝对不会死循环，processed 必须是有界小值
	if processed > 10:
		printerr("Chain mask recursion shield failed: processed too many events: ", processed)
		return false

	print("  [✓] Causal chain mask & infinite recursion shield passed (processed: ", processed, ")")
	return true

## 3. 验证三大签名词条解析与属性联动
static func test_signature_affixes_integration() -> bool:
	var state = SimStateScript.new(45678)
	var queue = EventQueue.new()

	# 装备杀戮狂热
	var kf_affix = SignatureAffixes.create_killing_frenzy()
	var item_kf = ItemInstance.new(101, "狂热之戒", ItemInstance.Slot.TRINKET, ItemInstance.Rarity.UNIQUE, 10, -INF)
	item_kf.affixes.push_back(kf_affix)
	state.equip_slots.equip(item_kf, state)

	# 装备连锁闪电
	var cl_affix = SignatureAffixes.create_chain_lightning()
	var item_cl = ItemInstance.new(102, "雷霆之刃", ItemInstance.Slot.WEAPON, ItemInstance.Rarity.UNIQUE, 10, 3.0)
	item_cl.affixes.push_back(cl_affix)
	state.equip_slots.equip(item_cl, state)

	# 模拟击杀事件
	queue.push_back(SimEvent.new(SimEvent.T.KILL, 10.0, 1))
	state.resolver.resolve_tick(state, queue, null)

	# 验证杀戮狂热 Buff 是否成功叠加
	if not state.buffs.has_buff("killing_frenzy"):
		printerr("Killing frenzy buff was not added")
		return false
	if state.buffs.get_stacks("killing_frenzy") != 1:
		printerr("Killing frenzy stacks mismatch: ", state.buffs.get_stacks("killing_frenzy"))
		return false

	# 模拟暴击事件触发连锁闪电
	var bus = preload("res://presentation/PresentationBus.gd").new()
	var crit_ev = SimEvent.new(SimEvent.T.CRIT, 5.0, 1)
	queue.push_back(crit_ev)
	state.resolver.resolve_tick(state, queue, bus)

	# 检查 PresentationBus 中是否收到连锁闪电派生事件
	var events_in_bus = bus.drain_all()
	var found_lightning: bool = false
	for out_ev in events_in_bus:
		if out_ev.hint.get("vfx_key") == "chain_lightning":
			found_lightning = true
			break

	if not found_lightning:
		printerr("Chain lightning derived event not found")
		return false

	print("  [✓] Signature affixes (Chain Lightning & Killing Frenzy) passed")
	return true

## 4. 验证装备干跑 (DryRun) 确定性与可复现性
static func test_dry_run_determinism() -> bool:
	var state = SimStateScript.new(777)
	var cand_item = ItemInstance.new(201, "诸界破灭斧", ItemInstance.Slot.WEAPON, ItemInstance.Rarity.UNIQUE, 25, 4.5)

	var res1 = DryRun.evaluate_candidate(state, cand_item, 99999)
	var res2 = DryRun.evaluate_candidate(state, cand_item, 99999)

	if res1["baseline_damage_log"] != res2["baseline_damage_log"]:
		printerr("DryRun determinism failed on baseline: ", res1["baseline_damage_log"], " vs ", res2["baseline_damage_log"])
		return false
	if res1["candidate_damage_log"] != res2["candidate_damage_log"]:
		printerr("DryRun determinism failed on candidate: ", res1["candidate_damage_log"], " vs ", res2["candidate_damage_log"])
		return false
	if res1["delta_pct"] != res2["delta_pct"]:
		printerr("DryRun determinism failed on delta_pct")
		return false

	print("  [✓] DryRun 30s evaluation determinism passed (delta: +", snapped(res1["delta_pct"], 0.1), "%)")
	return true

## 5. 压力测试：攻速 ×100 跑 6,000 ticks (10分钟)，帧时间 < 33ms，不丢数不死循环
static func test_stress_100x_attacks_6000_ticks() -> bool:
	var state = SimStateScript.new(888)
	var queue = EventQueue.new()
	var resolver = state.resolver

	# 装备连锁闪电和落地即爆
	var it_cl = ItemInstance.new(301, "雷神锤", ItemInstance.Slot.WEAPON, ItemInstance.Rarity.UNIQUE, 50, 4.0)
	it_cl.affixes.push_back(SignatureAffixes.create_chain_lightning())
	state.equip_slots.equip(it_cl, state)

	var it_de = ItemInstance.new(302, "爆裂护手", ItemInstance.Slot.GLOVES, ItemInstance.Rarity.UNIQUE, 50, 2.0)
	it_de.affixes.push_back(SignatureAffixes.create_drop_explosion())
	state.equip_slots.equip(it_de, state)

	# 攻速 ×100：基础间隔 0.5s -> 0.005s (每秒 200 次攻击，每 tick 20 次攻击)
	state.stats.atk_interval = 0.005
	state.stats.crit_rate = 0.50 # 50% 暴击率

	var start_msec: int = Time.get_ticks_msec()
	var ticks_count: int = 6000 # 相当于 10 分钟挂机 (10Hz)

	for t in ticks_count:
		# 每 tick 注入多次命中与暴击
		queue.push_back(SimEvent.new(SimEvent.T.CRIT, 5.0, 10))
		queue.push_back(SimEvent.new(SimEvent.T.DROP, 0.0, 5))
		resolver.resolve_tick(state, queue, null)
		state.buffs.tick()

	var elapsed_msec: int = Time.get_ticks_msec() - start_msec
	var avg_tick_ms: float = float(elapsed_msec) / float(ticks_count)

	# 验收：帧时间 < 33ms (30fps 门槛)
	if avg_tick_ms >= 33.0:
		printerr("Stress test failed: avg tick time ", avg_tick_ms, "ms >= 33ms")
		return false

	print("  [✓] Stress test 6,000 ticks @ 100x attack speed passed! Total: ", elapsed_msec, "ms (avg: ", snapped(avg_tick_ms, 0.001), " ms/tick < 33ms)")
	return true

## 6. EventCompactor：合并前后 count 严格守恒，且不合并带载荷/不同因果链的事件 (§2.3)
static func test_event_compactor_conserves_counts() -> bool:
	var events: Array[SimEvent] = []
	var expected_hit_count: int = 0
	for i: int in range(200):
		var hit: SimEvent = SimEvent.new(SimEvent.T.HIT, 1.0, 1 + (i % 3))
		expected_hit_count += hit.count
		events.push_back(hit)
	var payload_ev: SimEvent = SimEvent.new(SimEvent.T.DROP, 1.0, 5)
	payload_ev.payload = {"item_uid": 7}
	events.push_back(payload_ev)
	var chain_ev: SimEvent = SimEvent.new(SimEvent.T.HIT, 1.0, 4)
	chain_ev.chain_mask = 8
	events.push_back(chain_ev)
	expected_hit_count += 4

	var before_total: int = EventCompactor.total_count(events)
	var merged: Array[SimEvent] = EventCompactor.merge_by_type(events)
	var after_total: int = EventCompactor.total_count(merged)
	if before_total != after_total:
		printerr("EventCompactor count not conserved: ", before_total, " -> ", after_total)
		return false
	if merged.size() != 3:
		printerr("EventCompactor should keep 3 events (merged HIT, payload DROP, chained HIT), got ", merged.size())
		return false
	var hit_total: int = 0
	for m: SimEvent in merged:
		if m.type == SimEvent.T.HIT:
			hit_total += m.count
	if hit_total != expected_hit_count:
		printerr("EventCompactor HIT count mismatch: ", hit_total, " vs ", expected_hit_count)
		return false
	print("  [✓] EventCompactor count conservation passed (", before_total, " -> ", after_total, ")")
	return true

## 7. 真实 SimRunner 管线：杀戮狂热叠层加速击杀，连锁闪电派生伤害真实扣血，且词条事件透传表现队列
static func test_runner_affix_pipeline_frenzy_and_damage() -> bool:
	var bal: BalanceScript = BalanceScript.load_default() as BalanceScript

	# 7.1 杀戮狂热: 击杀叠层 atk_speed_pct，叠层后实际攻击间隔缩短
	var state: SimStateScript = SimStateScript.new(4242, bal)
	state.stats.base_gold_atk_log = 6.0
	var kf_item: ItemInstance = ItemInstance.new(11, "狂热之戒", ItemInstance.Slot.TRINKET, ItemInstance.Rarity.UNIQUE, 5, 3.0, 0.0, 1.0, bal)
	kf_item.affixes.push_back(SignatureAffixes.create_killing_frenzy())
	state.equip_item(kf_item)
	if not state.resolver.has_listeners():
		printerr("SimState.equip_item 未为含词条装备注册监听器")
		return false
	var runner: SimRunnerScript = SimRunnerScript.new(state)
	for _i: int in range(60):
		runner.step()
	if state.buffs.get_stacks("killing_frenzy") < 1:
		printerr("杀戮狂热未在真实管线中叠层")
		return false
	if state.buffs.get_stat_bonus("atk_speed_pct") <= 0.0:
		printerr("杀戮狂热攻速加成未生效")
		return false

	# 7.2 表现层透传: 处理过的 KILL 事件带 resolved 标记仍留在队列供 PresentationBus 消费
	var saw_resolved_kill: bool = false
	for ev: SimEvent in runner.queue.snapshot():
		if ev.type == SimEvent.T.KILL and bool(ev.hint.get("resolved", false)):
			saw_resolved_kill = true
			break
	if not saw_resolved_kill:
		printerr("词条管线吞掉了表现层事件 (KILL 未透传)")
		return false

	# 7.3 连锁闪电: 暴击派生事件 depth>0 且真实扣减怪物血量 (derived damage)
	var s2: SimStateScript = SimStateScript.new(777, bal)
	s2.stats.crit_rate = 0.75
	s2.stats.base_gold_atk_log = 3.0
	var cl_item: ItemInstance = ItemInstance.new(12, "雷霆之刃", ItemInstance.Slot.WEAPON, ItemInstance.Rarity.UNIQUE, 5, 3.0, 0.0, 1.0, bal)
	cl_item.affixes.push_back(SignatureAffixes.create_chain_lightning())
	s2.equip_item(cl_item)
	s2.stats.crit_rate = 0.75
	var r2: SimRunnerScript = SimRunnerScript.new(s2)
	var saw_lightning: bool = false
	for _j: int in range(80):
		r2.step()
		for ev2: SimEvent in r2.queue.snapshot():
			if ev2.hint.get("vfx_key", "") == "chain_lightning" and ev2.depth > 0:
				saw_lightning = true
	if not saw_lightning:
		printerr("连锁闪电派生事件未出现在表现队列")
		return false

	print("  [✓] Real SimRunner affix pipeline (frenzy stacks, resolved passthrough, chain lightning) passed")
	return true

## 8. 压力测试(真实管线)：攻速 ×100 跑 6,000 ticks，帧时间 < 33ms，不死循环，计数不丢
static func test_runner_stress_100x_real_pipeline() -> bool:
	var bal: BalanceScript = BalanceScript.load_default() as BalanceScript
	var state: SimStateScript = SimStateScript.new(2468, bal)
	state.stats.base_gold_atk_log = 8.0
	var it_cl: ItemInstance = ItemInstance.new(21, "雷神锤", ItemInstance.Slot.WEAPON, ItemInstance.Rarity.UNIQUE, 50, 4.0, 0.0, 1.0, bal)
	it_cl.affixes.push_back(SignatureAffixes.create_chain_lightning())
	state.equip_item(it_cl)
	var it_de: ItemInstance = ItemInstance.new(22, "爆裂护手", ItemInstance.Slot.GLOVES, ItemInstance.Rarity.UNIQUE, 50, 2.0, 0.0, 1.0, bal)
	it_de.affixes.push_back(SignatureAffixes.create_drop_explosion())
	state.equip_item(it_de)
	var it_kf: ItemInstance = ItemInstance.new(23, "狂热之戒", ItemInstance.Slot.TRINKET, ItemInstance.Rarity.UNIQUE, 50, 2.0, 0.0, 1.0, bal)
	it_kf.affixes.push_back(SignatureAffixes.create_killing_frenzy())
	state.equip_item(it_kf)

	state.stats.atk_interval = bal.base_atk_interval / 100.0
	state.stats.crit_rate = 0.5
	var runner: SimRunnerScript = SimRunnerScript.new(state)

	var worst_msec: int = 0
	var total_msec: int = 0
	var ticks_count: int = 6000
	for _t: int in range(ticks_count):
		var t0: int = Time.get_ticks_msec()
		runner.step()
		# 模拟 Game 每帧泵出表现事件，避免队列无界堆积
		while not runner.queue.is_empty():
			runner.queue.pop_front()
		var dt_ms: int = Time.get_ticks_msec() - t0
		total_msec += dt_ms
		worst_msec = maxi(worst_msec, dt_ms)

	var avg_ms: float = float(total_msec) / float(ticks_count)
	if avg_ms >= 33.0 or float(worst_msec) >= 33.0 * 4.0:
		printerr("Real pipeline stress failed: avg=", avg_ms, "ms worst=", worst_msec, "ms")
		return false
	if state.tick_count != ticks_count or state.mobs_killed_total <= 0:
		printerr("Real pipeline stress: ticks/kills abnormal ", state.tick_count, "/", state.mobs_killed_total)
		return false
	print("  [✓] Real-pipeline stress 6,000 ticks @ 100x passed (avg ", snapped(avg_ms, 0.001), " ms, worst ", worst_msec, " ms, kills ", state.mobs_killed_total, ")")
	return true

## 9. WP-12: 6 槽严格命名 + 换装返回旧装备 + DryRun 同种子可复现且强装备 Δ% > 0
static func test_equip_six_slots_and_dry_run_delta() -> bool:
	var bal: BalanceScript = BalanceScript.load_default() as BalanceScript
	var expected_slots: Array[String] = ["weapon", "helm", "chest", "gloves", "boots", "trinket"]
	if SimStateScript.EQUIP_SLOTS != expected_slots or ItemInstance.SLOT_KEYS != expected_slots or EquipSlots.SLOT_KEYS != expected_slots:
		printerr("6 槽位命名违反勘误 E10")
		return false

	var state: SimStateScript = SimStateScript.new(31337, bal)
	var weapon_a: ItemInstance = ItemInstance.new(31, "旧剑", ItemInstance.Slot.WEAPON, ItemInstance.Rarity.PURPLE, 3, 3.0, 0.2, 1.0, bal)
	var weapon_b: ItemInstance = ItemInstance.new(32, "新剑", ItemInstance.Slot.WEAPON, ItemInstance.Rarity.UNIQUE, 20, 6.0, 0.6, 2.0, bal)
	if state.equip_item(weapon_a) != null:
		printerr("首次穿戴不应返回旧装备")
		return false
	var replaced: ItemInstance = state.equip_item(weapon_b)
	if replaced == null or replaced.uid != 31:
		printerr("换装未返回被替换的旧装备")
		return false
	var removed: ItemInstance = state.unequip_slot("weapon")
	if removed == null or removed.uid != 32 or state.equipped["weapon"] != null:
		printerr("unequip_slot 异常")
		return false

	# DryRun: 同种子两次结果完全一致；强装备 Δ% > 0；DryRun 不污染源状态
	var hash_before: String = state.compute_state_hash()
	var res1: Dictionary = DryRun.evaluate_candidate(state, weapon_b)
	var res2: Dictionary = DryRun.evaluate_candidate(state, weapon_b)
	if res1["delta_pct"] != res2["delta_pct"] or res1["candidate_damage_log"] != res2["candidate_damage_log"]:
		printerr("DryRun 同种子不可复现")
		return false
	if float(res1["delta_pct"]) <= 0.0:
		printerr("强力武器 DryRun Δ% 应 > 0, 实际: ", res1["delta_pct"])
		return false
	if state.compute_state_hash() != hash_before:
		printerr("DryRun 污染了源 SimState")
		return false

	# 含词条装备经 DryRun 同样确定性（词条监听器随克隆重建）
	var kf_candidate: ItemInstance = ItemInstance.new(33, "狂热戒", ItemInstance.Slot.TRINKET, ItemInstance.Rarity.UNIQUE, 20, 5.0, 0.3, 1.5, bal)
	kf_candidate.affixes.push_back(SignatureAffixes.create_killing_frenzy())
	var k1: Dictionary = DryRun.evaluate_candidate(state, kf_candidate)
	var k2: Dictionary = DryRun.evaluate_candidate(state, kf_candidate)
	if k1["delta_pct"] != k2["delta_pct"]:
		printerr("含词条装备 DryRun 不可复现")
		return false

	print("  [✓] 6-slot equip + DryRun reproducible (weapon Δ% = ", snapped(float(res1["delta_pct"]), 0.1), ")")
	return true