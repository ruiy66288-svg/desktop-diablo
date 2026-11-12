class_name AffixResolver extends RefCounted

## 词条事件解析器与四重递归安全防线 (依据《02_系统架构与数值_v6.md》§2.3 与《00_开发执行总纲.md》WP-10)
## ① 深度上限 → 溢出奖励  ② 因果链掩码同链仅触发一次  ③ 每词条每 tick 预算  ④ 全局每 tick 事件上限
## 上限常数统一从 Balance 读取；超出 max_spill 的队列走 EventCompactor 合并（绝不丢计数）

const SimEventScript = preload("res://simulation/events/SimEvent.gd")
const EventQueueScript = preload("res://simulation/events/EventQueue.gd")
const EventCompactorScript = preload("res://simulation/events/EventCompactor.gd")
const AffixDefScript = preload("res://simulation/affix/AffixDef.gd")
const BalanceScript = preload("res://simulation/Balance.gd")

const BIT_SLOTS_TOTAL: int = 60            # int64 安全位宽 (6 槽 × 4 条 = 24 位实际使用)
const AFFIXES_PER_SLOT: int = 4

class AffixListener extends RefCounted:
	var bit: int = 0
	var def: AffixDefScript
	var runtime: Dictionary = {}
	var tick_budget: int = 0
	var rolls: Dictionary = {}

var _listeners: Array[AffixListener] = []
var _listeners_by_type: Dictionary = {}
var current_tick: int = 0

## SimRunner 使用：开启后，本 tick 处理过的全部事件（含派生）会按序记录，供回填表现队列
var collect_processed: bool = false
var processed_log: Array[SimEventScript] = []
## 本 tick 由词条派生出的、带伤害语义的事件（HIT/CRIT/METEOR），供 Combat 真实结算
var derived_damage_events: Array[SimEventScript] = []
var last_overflow_count: int = 0

func register_listener(affix_def: AffixDefScript, slot_idx: int, affix_idx: int, rolls: Dictionary = {}) -> void:
	if affix_def == null or affix_def.is_passive or affix_def.trigger == null or affix_def.effect == null:
		return

	var l: AffixListener = AffixListener.new()
	l.bit = 1 << ((slot_idx * AFFIXES_PER_SLOT + affix_idx) % BIT_SLOTS_TOTAL)
	l.def = affix_def
	l.runtime = {"acc": 0, "last_fired_tick": -999999}
	l.tick_budget = affix_def.budget_per_tick
	l.rolls = rolls

	_listeners.push_back(l)

	var ev_type: int = int(affix_def.trigger.event_type)
	if not _listeners_by_type.has(ev_type):
		var typed_arr: Array[AffixListener] = []
		_listeners_by_type[ev_type] = typed_arr
	var bucket: Array[AffixListener] = _listeners_by_type[ev_type] as Array[AffixListener]
	bucket.push_back(l)

func clear_listeners() -> void:
	_listeners.clear()
	_listeners_by_type.clear()

func has_listeners() -> bool:
	return not _listeners.is_empty()

func get_listener_count() -> int:
	return _listeners.size()

func _is_damage_event(ev: SimEventScript) -> bool:
	return (
		ev.type == SimEventScript.T.HIT
		or ev.type == SimEventScript.T.CRIT
		or ev.type == SimEventScript.T.METEOR
	)

## 核心解析循环 (四重保险)，返回本 tick 处理的事件数
func resolve_tick(state: RefCounted, queue: EventQueueScript, presentation_bus: RefCounted = null) -> int:
	current_tick += 1
	processed_log.clear()
	derived_damage_events.clear()
	last_overflow_count = 0

	var bal: BalanceScript = (state.get("balance") as BalanceScript) if state != null else (BalanceScript.load_default() as BalanceScript)
	var max_depth: int = bal.resolver_max_depth
	var max_events: int = bal.resolver_max_events_per_tick
	var max_spill: int = bal.resolver_max_spill

	for l: AffixListener in _listeners:
		l.tick_budget = l.def.budget_per_tick

	var processed: int = 0
	var rng_ref: RefCounted = (state.get("rng") as RefCounted) if state != null else null

	# 开始时队列长度作为本轮已有事件边界之外，已 resolved 的旧事件直接透传不计入预算
	while not queue.is_empty() and processed < max_events:
		var ev: SimEventScript = queue.pop_front()
		if ev == null:
			break

		if bool(ev.hint.get(EventCompactorScript.RESOLVED_HINT_KEY, false)):
			if collect_processed:
				processed_log.push_back(ev)
			continue

		processed += 1
		if collect_processed:
			processed_log.push_back(ev)

		if presentation_bus != null and presentation_bus.has_method("push"):
			presentation_bus.call("push", ev)

		var ev_key: int = int(ev.type)
		if not _listeners_by_type.has(ev_key):
			continue

		var candidate_listeners: Array[AffixListener] = _listeners_by_type[ev_key] as Array[AffixListener]
		for l: AffixListener in candidate_listeners:
			if (ev.chain_mask & l.bit) != 0:
				continue
			if l.tick_budget <= 0:
				continue

			var fires: int = l.def.trigger.consume(ev, l.runtime, current_tick, rng_ref)
			fires = mini(fires, l.tick_budget)
			l.tick_budget -= fires

			if fires <= 0:
				continue

			for _k: int in range(fires):
				var out_events: Array[SimEventScript] = l.def.effect.execute(ev, state, l.rolls)
				for out: SimEventScript in out_events:
					out.depth = ev.depth + 1
					out.chain_mask = ev.chain_mask | l.bit

					if out.depth > max_depth:
						last_overflow_count += 1
						if state != null and state.has_method("overflow_reward"):
							state.call("overflow_reward", out)
						continue

					if collect_processed and _is_damage_event(out):
						derived_damage_events.push_back(out)
					queue.push_back(out)

	if queue.size() > max_spill:
		queue.compact_same_type(bal.event_compact_threshold)

	return processed

func clone() -> AffixResolver:
	return (get_script() as GDScript).new() as AffixResolver
