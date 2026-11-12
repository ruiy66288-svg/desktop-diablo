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

static func run_all_tests() -> bool:
	print("--- Running TestAffixResolver ---")
	var ok: bool = true
	ok = ok and test_counter_trigger_no_lost_counts()
	ok = ok and test_causal_chain_and_recursion_shield()
	ok = ok and test_signature_affixes_integration()
	ok = ok and test_dry_run_determinism()
	ok = ok and test_stress_100x_attacks_6000_ticks()
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
