class_name SimRunner extends RefCounted

## 固定步长确定性模拟时钟 (10Hz，最多追赶 50 个 tick，依据《02_系统架构与数值_v6.md》§2.1、§3.2 & WP-03/WP-05)
## 纯 RefCounted，零 Node 依赖，参数统一由 Balance 驱动

const SimStateScript = preload("res://simulation/SimState.gd")
const CommandScript = preload("res://simulation/commands/Command.gd")
const CommandQueueScript = preload("res://simulation/commands/CommandQueue.gd")
const CombatScript = preload("res://simulation/combat/Combat.gd")
const EventQueueScript = preload("res://simulation/events/EventQueue.gd")
const SimEventScript = preload("res://simulation/events/SimEvent.gd")
const EventCompactorScript = preload("res://simulation/events/EventCompactor.gd")
const AffixResolverScript = preload("res://simulation/events/AffixResolver.gd")
const NumScript = preload("res://core/num/Num.gd")

const TICK_EPS: float = 1e-9

var state: SimStateScript
var combat: CombatScript
var queue: EventQueueScript
var command_queue: CommandQueueScript
var offline_handler: Callable = Callable()

var _acc: float = 0.0
var _last_step_kills: int = 0

func _init(p_state: SimStateScript, p_offline_handler: Callable = Callable()) -> void:
	state = p_state
	combat = CombatScript.new()
	queue = EventQueueScript.new()
	command_queue = CommandQueueScript.new()
	offline_handler = p_offline_handler

## 将外部只写指令送入权威队列，在下一 tick 起始处确定性消费
func push_command(cmd: CommandScript) -> void:
	if command_queue != null:
		command_queue.push(cmd)

func enqueue_command(cmd: CommandScript) -> void:
	push_command(cmd)

func get_last_step_kills() -> int:
	return _last_step_kills

func get_accumulator() -> float:
	return _acc

## 执行单次固定步长 (默认 0.1s = 10Hz；按 §3.2 顺序：先处理 commands → combat → 事件压缩)
func step() -> int:
	if command_queue != null and not command_queue.is_empty():
		command_queue.drain_and_apply(state, queue)
	var state_cq_var: Variant = state.get("command_queue")
	if state_cq_var is CommandQueueScript:
		var state_cq: CommandQueueScript = state_cq_var as CommandQueueScript
		if not state_cq.is_empty():
			state_cq.drain_and_apply(state, queue)

	# 自动化分支「自动升级」：非门前储蓄期按 Balance 上限自动购买金币攻击升级 (§5.3 & §7.3)
	if state.has_tech_effect("auto_buy_atk") and not state.is_saving_for_toll():
		state.upgrades.buy_atk_upgrades_bulk(state, state.balance.auto_buy_max_per_tick)

	var tick_dt: float = state.balance.sim_tick_dt
	state.tick_count += 1
	state.elapsed_seconds += tick_dt
	_last_step_kills = combat.step_tick(tick_dt, state, queue)
	_last_step_kills += _run_affix_pipeline()
	state.buffs.tick()

	if state.elapsed_seconds > 0.0:
		var pending_souls: float = state.balance.get_pending_souls_log(state.run_best, state.marks)
		if pending_souls != NumScript.ZERO:
			var rate_log: float = NumScript.div(pending_souls, NumScript.from_float(state.elapsed_seconds))
			state.peak_soul_rate_log = NumScript.max_num(state.peak_soul_rate_log, rate_log)

	queue.compact_same_type(state.balance.event_compact_threshold)
	return _last_step_kills

## 词条管线：仅在身上有反应型词条时启用（零词条零开销，保证既有哈希不变）
## 流程：Resolver 处理本 tick 事件 → 已处理事件带 resolved 标记回填队列（表现层照常消费）→ 派生伤害真实结算
func _run_affix_pipeline() -> int:
	var resolver: AffixResolverScript = state.resolver
	if resolver == null or not resolver.has_listeners():
		return 0

	resolver.collect_processed = true
	resolver.resolve_tick(state, queue, null)

	for done_ev: SimEventScript in resolver.processed_log:
		done_ev.hint[EventCompactorScript.RESOLVED_HINT_KEY] = true
		queue.push_back(done_ev)

	var derived_kills: int = 0
	for dmg_ev: SimEventScript in resolver.derived_damage_events:
		if dmg_ev.value != NumScript.ZERO:
			derived_kills += combat.apply_derived_damage(dmg_ev.value, state, queue)
	resolver.derived_damage_events.clear()
	return derived_kills

## 外部传入真实帧间隔 delta 驱动时钟；最多追赶 max_catchup_ticks (50) 个 tick，返回本次执行的 tick 数
func advance(delta: float) -> int:
	if delta <= 0.0:
		return 0

	var tick_dt: float = state.balance.sim_tick_dt
	var max_ticks: int = state.balance.max_catchup_ticks
	_acc += delta

	if _acc > float(max_ticks) * tick_dt:
		if offline_handler.is_valid():
			offline_handler.call(state, _acc)
			_acc = 0.0
			return 0
		_acc = float(max_ticks) * tick_dt

	var steps_run: int = 0
	while _acc >= tick_dt - TICK_EPS and steps_run < max_ticks:
		_acc = maxf(0.0, _acc - tick_dt)
		step()
		steps_run += 1

	return steps_run
