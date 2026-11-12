extends RefCounted

## D6 UI 与 Game 协调器集成测试 (`WP-16` 灵魂转生 UI + `WP-17` 自动读存档与离线结算闭环)
## 铁律：100% 显式静态类型，零 :=；UI 只读 SimState，所有状态变更通过 Game.request_* -> Command 队列

const GameScript = preload("res://autoload/Game.gd")
const MainWindowScript = preload("res://ui/MainWindow.gd")
const SystemsDrawerScript = preload("res://ui/SystemsDrawer.gd")
const SimStateScript = preload("res://simulation/SimState.gd")
const ItemInstanceScript = preload("res://simulation/loot/ItemInstance.gd")
const NumScript = preload("res://core/num/Num.gd")

const TEST_SAVE_PATH: String = "user://test_d6_ui_save.json"

static func run() -> bool:
	var ok: bool = true
	ok = _test_prestige_drawer_flow() and ok
	ok = _test_game_save_load_offline_flow() and ok
	return ok

static func _test_prestige_drawer_flow() -> bool:
	var game: GameScript = GameScript.new()
	game.initialize_session(20261113, null, true)
	var state: SimStateScript = game.get_sim_state()
	state.run_best = 120
	state.all_time_best = 120
	state.current_stage = 120
	var wpn: ItemInstanceScript = ItemInstanceScript.new(
		88001,
		"转生测试剑",
		ItemInstanceScript.Slot.WEAPON,
		ItemInstanceScript.Rarity.UNIQUE,
		15,
		3.0,
		0.2,
		1.2,
		state.balance
	)
	state.equip_item(wpn)

	var win: MainWindowScript = MainWindowScript.new()
	win.bind_game(game)
	win._ready()

	win.open_systems_drawer(SystemsDrawerScript.TabKind.PRESTIGE)
	if not win.systems_drawer.visible or win.systems_drawer.get_active_tab() != SystemsDrawerScript.TabKind.PRESTIGE:
		push_error("[test_d6_ui] Expected SystemsDrawer open on PRESTIGE tab")
		win.free()
		game.free()
		return false

	var pv: Dictionary = win.systems_drawer.get_prestige_preview_snapshot()
	if not bool(pv.get("can_prestige", false)) or int(pv.get("kept_equipped_count", 0)) != 1:
		push_error("[test_d6_ui] Expected can_prestige=true and kept_equipped_count=1")
		win.free()
		game.free()
		return false

	win.systems_drawer._on_prestige_pressed()
	game.advance_frame(0.2)

	if state.current_stage != 1 or state.equipped.get("weapon", null) == null:
		push_error("[test_d6_ui] Expected current_stage reset to 1 and weapon kept after prestige")
		win.free()
		game.free()
		return false

	win.free()
	game.free()
	print("[test_d6_ui] _test_prestige_drawer_flow PASS")
	return true

static func _test_game_save_load_offline_flow() -> bool:
	_cleanup_test_files()

	var game_a: GameScript = GameScript.new()
	game_a.initialize_session(20261113, null, true)
	var state_a: SimStateScript = game_a.get_sim_state()
	state_a.run_best = 12
	state_a.all_time_best = 12
	state_a.current_stage = 12
	state_a.upgrades.atk_level = 5
	state_a.recalculate_stats()

	var t0: float = 1700000000.0
	var save_err: Error = game_a.save_current_game(TEST_SAVE_PATH, t0)
	if save_err != OK:
		push_error("[test_d6_ui] Expected save_current_game OK, got %d" % int(save_err))
		game_a.free()
		return false

	var game_b: GameScript = GameScript.new()
	var off: Dictionary = game_b.load_saved_game(TEST_SAVE_PATH, t0 + 120.0)
	if not bool(off.get("loaded", false)):
		push_error("[test_d6_ui] Expected load_saved_game loaded=true")
		game_a.free()
		game_b.free()
		_cleanup_test_files()
		return false

	var eff_sec: float = float(off.get("effective_seconds", 0.0))
	var state_b: SimStateScript = game_b.get_sim_state()
	if not is_equal_approx(eff_sec, 120.0) or state_b.run_best < 12:
		push_error("[test_d6_ui] Expected effective_seconds=120.0 and run_best>=12, got %.1f / %d" % [eff_sec, state_b.run_best])
		game_a.free()
		game_b.free()
		_cleanup_test_files()
		return false

	game_a.free()
	game_b.free()
	_cleanup_test_files()
	print("[test_d6_ui] _test_game_save_load_offline_flow PASS (offline 120s, gold=%s)" % NumScript.format_num(float(off.get("gold_gain_log", NumScript.ZERO))))
	return true

static func _cleanup_test_files() -> void:
	for p: String in [TEST_SAVE_PATH, TEST_SAVE_PATH + ".meta.json", TEST_SAVE_PATH + ".bak", TEST_SAVE_PATH + ".tmp"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
