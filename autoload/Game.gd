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
const SaveServiceScript = preload("res://persistence/SaveService.gd")
const OfflineCalcScript = preload("res://offline/OfflineCalc.gd")

const AUTOLOAD_NODE_NAME: String = "GameAutoload"
const DEFAULT_MASTER_SEED: int = 20261112
const UNCONSUMED_BUS_SAFETY_CAP: int = 512
const DEFAULT_SAVE_PATH: String = "user://save.json"
const AUTO_SAVE_INTERVAL_SEC: float = 30.0

signal sim_ticked(steps: int)
signal restored_from_minimized(summary: Dictionary)
signal offline_settled(summary: Dictionary)
signal mute_toggled(muted: bool)

var _state: SimStateScript = null
var _runner: SimRunnerScript = null
var _bus: PresentationBusScript = null
var _was_minimized: bool = false
var _force_minimized_for_test: bool = false
var _auto_tick_enabled: bool = true
var _last_minimized_summary: Dictionary = {}
var _last_offline_summary: Dictionary = {}
var _auto_save_enabled: bool = false
var _auto_save_path: String = DEFAULT_SAVE_PATH
var _auto_save_elapsed: float = 0.0
var _audio_muted: bool = false

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
func initialize_session(seed_val: int = DEFAULT_MASTER_SEED, p_balance: BalanceScript = null, debug_seconds_mode: bool = false) -> void:
	var bal: BalanceScript = p_balance if p_balance != null else (BalanceScript.load_default() as BalanceScript)
	_state = SimStateScript.new(seed_val, bal)
	if _state.tech != null:
		_state.tech.debug_seconds_mode = debug_seconds_mode
	_runner = SimRunnerScript.new(_state, Callable(OfflineCalcScript, "handle_long_gap"))
	_bus = PresentationBusScript.new()
	_was_minimized = false
	_last_minimized_summary = {}
	_last_offline_summary = {}

func _process(delta: float) -> void:
	if not _auto_tick_enabled:
		return
	advance_frame(delta)
	if _auto_save_enabled:
		_auto_save_elapsed += delta
		if _auto_save_elapsed >= AUTO_SAVE_INTERVAL_SEC:
			_auto_save_elapsed = 0.0
			save_current_game(_auto_save_path)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_current_game(_auto_save_path)

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
		if _state.research_queue != null and not _state.research_queue.entries.is_empty():
			_runner.enqueue_command(CommandScript.make_settle_research(Time.get_unix_time_from_system()))
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

func request_start_research(node_id: String, now_unix: float = -1.0) -> void:
	var ts: float = now_unix if now_unix >= 0.0 else Time.get_unix_time_from_system()
	submit_command(CommandScript.make_start_research(node_id, ts))

func request_settle_research(now_unix: float = -1.0) -> void:
	var ts: float = now_unix if now_unix >= 0.0 else Time.get_unix_time_from_system()
	submit_command(CommandScript.make_settle_research(ts))

func request_abyss_prestige(extract_power_id: String = "") -> void:
	submit_command(CommandScript.make_abyss_prestige(extract_power_id))

func request_equip_vault_power(affix_id: String) -> void:
	submit_command(CommandScript.make_equip_vault_power(affix_id))

func request_unequip_vault_power(affix_id: String) -> void:
	submit_command(CommandScript.make_unequip_vault_power(affix_id))

func request_ack_signal(kind: int) -> void:
	submit_command(CommandScript.make_ack_signal(kind))

func set_audio_muted(muted: bool) -> bool:
	_audio_muted = muted
	if DisplayServer.get_name() != "headless" and AudioServer.get_bus_count() > 0:
		AudioServer.set_bus_mute(0, _audio_muted)
	mute_toggled.emit(_audio_muted)
	return _audio_muted

func toggle_audio_mute() -> bool:
	return set_audio_muted(not _audio_muted)

func is_audio_muted() -> bool:
	if DisplayServer.get_name() != "headless" and AudioServer.get_bus_count() > 0:
		_audio_muted = AudioServer.is_bus_mute(0)
	return _audio_muted

func enable_auto_persistence(save_path: String = DEFAULT_SAVE_PATH) -> void:
	_auto_save_path = save_path
	_auto_save_enabled = true
	_auto_save_elapsed = 0.0

func get_last_offline_summary() -> Dictionary:
	return _last_offline_summary

func save_current_game(save_path: String = DEFAULT_SAVE_PATH, now_unix: float = -1.0) -> Error:
	if _state == null:
		return ERR_UNCONFIGURED
	var err: Error = SaveServiceScript.save_to_file(_state, save_path)
	if err == OK:
		var ts: float = now_unix if now_unix >= 0.0 else Time.get_unix_time_from_system()
		var meta_path: String = save_path + ".meta.json"
		var f: FileAccess = FileAccess.open(meta_path, FileAccess.WRITE)
		if f != null:
			f.store_string(JSON.stringify({"last_save_unix": ts}))
			f.close()
	return err

func load_saved_game(save_path: String = DEFAULT_SAVE_PATH, now_unix: float = -1.0, p_balance: BalanceScript = null) -> Dictionary:
	var bal: BalanceScript = p_balance if p_balance != null else (BalanceScript.load_default() as BalanceScript)
	var loaded: SimStateScript = SaveServiceScript.load_from_file(save_path, bal)
	if loaded == null:
		return {"loaded": false}
	_state = loaded
	_runner = SimRunnerScript.new(_state, Callable(OfflineCalcScript, "handle_long_gap"))
	_bus = PresentationBusScript.new()
	_was_minimized = false
	_last_minimized_summary = {}

	var ts: float = now_unix if now_unix >= 0.0 else Time.get_unix_time_from_system()
	var last_unix: float = ts
	var meta_path: String = save_path + ".meta.json"
	if FileAccess.file_exists(meta_path):
		var mf: FileAccess = FileAccess.open(meta_path, FileAccess.READ)
		if mf != null:
			var parsed: Variant = JSON.parse_string(mf.get_as_text())
			mf.close()
			if parsed is Dictionary:
				last_unix = float((parsed as Dictionary).get("last_save_unix", ts))

	var elapsed: float = maxf(0.0, ts - last_unix)
	_last_offline_summary = OfflineCalcScript.settle(_state, elapsed, ts)
	_last_offline_summary["loaded"] = true
	offline_settled.emit(_last_offline_summary)
	return _last_offline_summary
