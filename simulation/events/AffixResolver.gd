class_name AffixResolver extends RefCounted

## 词条事件解析器与四重递归安全防线 (依据《02_系统架构与数值_v6.md》§2.3)

const SimEventScript = preload("res://simulation/events/SimEvent.gd")
const EventQueueScript = preload("res://simulation/events/EventQueue.gd")
const AffixDefScript = preload("res://simulation/affix/AffixDef.gd")
const BalanceScript = preload("res://simulation/Balance.gd")

class AffixListener extends RefCounted:
	var bit: int = 0
	var def: AffixDefScript
	var runtime: Dictionary = {}
	var tick_budget: int = 0
	var rolls: Dictionary = {}

var _listeners: Array[AffixListener] = []
var _listeners_by_type: Dictionary = {}
var current_tick: int = 0

func register_listener(affix_def: AffixDefScript, slot_idx: int, affix_idx: int, rolls: Dictionary = {}) -> void:
	if affix_def == null or affix_def.is_passive or affix_def.trigger == null or affix_def.effect == null:
		return

	var l: AffixListener = AffixListener.new()
	l.bit = 1 << ((slot_idx * 4 + affix_idx) % 60)
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

## 核心解析循环 (四重保险，上限统一从 Balance 读取)
func resolve_tick(state: RefCounted, queue: EventQueueScript, presentation_bus: RefCounted = null) -> int:
	current_tick += 1

	var bal: BalanceScript = state.get("balance") as BalanceScript if state != null else BalanceScript.load_default()
	var max_depth: int = bal.resolver_max_depth
	var max_events: int = bal.resolver_max_events_per_tick
	var max_spill: int = bal.resolver_max_spill

	for l: AffixListener in _listeners:
		l.tick_budget = l.def.budget_per_tick

	var processed: int = 0
	var rng_ref: RefCounted = state.get("rng") as RefCounted if state != null else null

	while not queue.is_empty() and processed < max_events:
		var ev: SimEventScript = queue.pop_front()
		if ev == null:
			break
		processed += 1

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

			for _k in range(fires):
				var out_events: Array[SimEventScript] = l.def.effect.execute(ev, state, l.rolls)
				for out: SimEventScript in out_events:
					out.depth = ev.depth + 1
					out.chain_mask = ev.chain_mask | l.bit

					if out.depth > max_depth:
						if state != null and state.has_method("overflow_reward"):
							state.call("overflow_reward", out)
						continue

					queue.push_back(out)

	if queue.size() > max_spill:
		queue.compact_same_type(bal.event_compact_threshold)

	return processed
