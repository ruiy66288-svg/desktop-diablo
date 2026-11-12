class_name Game extends Node

## 《桌面破坏神》全局唯一 Autoload 协调器 (依据《02_系统架构与数值_v6.md》§3.1–§3.2、Q10 与《00_开发执行总纲.md》E8、§4.2)
## 职责：持有 SimState（只读暴露）、SimRunner（10Hz 固定步长）、PresentationBus（最小化仍照常排空消费）及 Command 只写投递通道
## 铁律：表现层与平台层严禁直接写 SimState，一切状态变更必须经 submit_command 走 CommandQueue 闭环

const SimStateScript = preload("res://simulation/SimState.gd")
const SimRunnerScript = preload("res://simulation/SimRunner.gd")
const BalanceScript = preload("res://simulation/Balance.gd")
const CommandScript = preload("res://simulation/commands/Command.gd")
const PresentationBusScript = preload("res://presentation/PresentationBus.gd")
const SimEventScript = preload("res://simulation/events/SimEvent.gd")

const AUTOLOAD_NODE_NAME: String = "GameAutoload"
const DEFAULT_MASTER_SEED: int = 20261112
const UNCONSUMED_BUS_SAFETY_CAP: int = 512

signal sim_ticked(steps: int)
signal restored_from_minimized(summary: Dictionary)

var _state: SimStateScript = null
var _runner: SimRunnerScript = null
var _bus: PresentationBusScript = null
var _was_minimized: bool = false
var _force_minimized_for_test: bool = false
var _auto_tick_enabled: bool = true
var _last_minimized_summary: Dictionary = {}

static func resolve_from_tree(tree: SceneTree) -> Game:
	if tree == null or tree.root == null:
		return null
	var node_a: Node = tree.root.get_node_or_null(AUTOLOAD_NODE_NAME)
	if node_a is Game:
		return node_a as Game
	var node_b: Node = tree.root.get_node_or_null("Game")
	if node_b is Game:
		return node_b as Game
	return null

func _ready() -> void:
	if _state == null or _runner == null or _bus == null:
		initialize_session(DEFAULT_MASTER_SEED)
	set_process(true)

## 初始化或重置模拟会话
func initialize_session(seed_val: int = DEFAULT_MASTER_SEED, p_balance: BalanceScript = null) -> void:
	var bal: BalanceScript = p_balance if p_balance != null else (BalanceScript.load_default() as BalanceScript)
	_state = SimStateScript.new(seed_val, bal)
	_runner = SimRunnerScript.new(_state)
	_bus = PresentationBusScript.new()
	_was_minimized = false
	_last_minimized_summary = {}

func _process(delta: float) -> void:
	if not _auto_tick_enabled:
		return
	advance_frame(delta)

## 单帧推进入口：驱动 10Hz SimRunner 并在最小化状态下持续排空消费 PresentationBus (勘误 E8 & Q10)
func advance_frame(delta: float) -> int:
	if _runner == null or _state == null or _bus == null:
		return 0

	var steps: int = _runner.advance(delta)
	_pump_runner_events_to_bus()

	var minimized: bool = is_window_minimized()
	if minimized:
		_was_minimized = true
		_bus.drain_for_minimized()
	else:
		if _was_minimized:
			_was_minimized = false
			_last_minimized_summary = _bus.fetch_and_reset_minimized_summary()
			restored_from_minimized.emit(_last_minimized_summary)
		elif _bus.get_pending_count() > UNCONSUMED_BUS_SAFETY_CAP:
			# 无视图监听时的安全泄压防线，防止环形缓冲无限堆积
			_bus.drain_for_minimized()

	if steps > 0:
		sim_ticked.emit(steps)
	return steps

func _pump_runner_events_to_bus() -> void:
	while not _runner.queue.is_empty():
		var ev: SimEventScript = _runner.queue.pop_front()
		if ev != null:
			_bus.push(ev)

## 只读获取权威模拟状态快照（严禁调用方直接修改其内部字段，§4.2）
func get_sim_state() -> SimStateScript:
	return _state

func get_runner() -> SimRunnerScript:
	return _runner

func get_presentation_bus() -> PresentationBusScript:
	return _bus

## 供活跃 UI 视图按帧排空表现层事件；最小化期间已被 drain_for_minimized 消费故返回空数组
func drain_presentation_events() -> Array:
	if _bus == null or is_window_minimized():
		return []
	return _bus.drain_all()

func get_last_minimized_summary() -> Dictionary:
	return _last_minimized_summary

func set_auto_tick_enabled(enabled: bool) -> void:
	_auto_tick_enabled = enabled

func set_simulated_minimized(minimized: bool) -> void:
	_force_minimized_for_test = minimized

func is_window_minimized() -> bool:
	if _force_minimized_for_test:
		return true
	if DisplayServer.get_name() == "headless":
		return false
	return DisplayServer.window_get_mode(DisplayServer.MAIN_WINDOW_ID) == DisplayServer.WINDOW_MODE_MINIMIZED

## 唯一合法修改 Sim 入口：向权威命令队列投递只写 Command (§2.1 & §4.2)
func submit_command(cmd: CommandScript) -> void:
	if cmd == null or _runner == null:
		return
	_runner.enqueue_command(cmd)

func request_buy_atk_upgrade(count: int = 1) -> void:
	submit_command(CommandScript.make_buy_atk(count))

func request_manual_pickup(ilvl: int = -1, rarity: int = 0) -> void:
	submit_command(CommandScript.make_manual_pickup(ilvl, rarity))

func request_equip_uid(item_uid: int) -> void:
	submit_command(CommandScript.make_equip_uid(item_uid))

func request_smelt_uid(item_uid: int) -> void:
	submit_command(CommandScript.make_smelt_uid(item_uid))

func request_borrow_credit(amount_log: float) -> void:
	submit_command(CommandScript.make_borrow(amount_log))

func request_repay_credit(amount_log: float) -> void:
	submit_command(CommandScript.make_repay(amount_log))

func request_soul_prestige() -> void:
	submit_command(CommandScript.make_soul_prestige())
