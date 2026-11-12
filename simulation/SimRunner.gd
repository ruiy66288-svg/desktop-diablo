class_name SimRunner extends RefCounted

## 固定步长确定性模拟时钟 (10Hz，最多追赶 50 个 tick，依据《02_系统架构与数值_v6.md》§3.2 & WP-03)
## 纯 RefCounted，零 Node 依赖，参数统一由 Balance 驱动

const SimStateScript = preload("res://simulation/SimState.gd")
const CombatScript = preload("res://simulation/combat/Combat.gd")
const EventQueueScript = preload("res://simulation/events/EventQueue.gd")
const NumScript = preload("res://core/num/Num.gd")

var state: SimStateScript
var combat: CombatScript
var queue: EventQueueScript
var offline_handler: Callable = Callable()

var _acc: float = 0.0
var _last_step_kills: int = 0

func _init(p_state: SimStateScript, p_offline_handler: Callable = Callable()) -> void:
	state = p_state
	combat = CombatScript.new()
	queue = EventQueueScript.new()
	offline_handler = p_offline_handler

func get_last_step_kills() -> int:
	return _last_step_kills

func get_accumulator() -> float:
	return _acc

## 执行单次固定步长 (默认 0.1s = 10Hz)
func step() -> int:
	var tick_dt: float = state.balance.sim_tick_dt
	state.tick_count += 1
	state.elapsed_seconds += tick_dt
	_last_step_kills = combat.step_tick(tick_dt, state, queue)

	if state.elapsed_seconds > 0.0:
		var pending_souls: float = state.balance.get_pending_souls_log(state.run_best, state.marks)
		if pending_souls != NumScript.ZERO:
			var rate_log: float = pending_souls - NumScript.from_float(state.elapsed_seconds)
			state.peak_soul_rate_log = NumScript.max_num(state.peak_soul_rate_log, rate_log)

	queue.compact_same_type(state.balance.event_compact_threshold)
	return _last_step_kills

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
	while _acc >= tick_dt - 1e-9 and steps_run < max_ticks:
		_acc = maxf(0.0, _acc - tick_dt)
		step()
		steps_run += 1

	return steps_run
