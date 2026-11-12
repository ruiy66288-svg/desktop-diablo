extends RefCounted

## D5 UI 交互面板专项测试 (`WP-13` 信贷预览与借贷、`WP-14` 科技树与研究队列、`WP-15` 门票/护盾提示)
## 铁律：100% 显式静态类型，零 :=；UI 只读 SimState，所有状态变更通过 Game.request_* -> Command 队列

const GameScript = preload("res://autoload/Game.gd")
const MainWindowScript = preload("res://ui/MainWindow.gd")
const SystemsDrawerScript = preload("res://ui/SystemsDrawer.gd")
const SimStateScript = preload("res://simulation/SimState.gd")
const NumScript = preload("res://core/num/Num.gd")

static func run() -> bool:
	var ok: bool = true
	ok = _test_credit_drawer_flow() and ok
	ok = _test_tech_drawer_flow() and ok
	ok = _test_toll_drawer_view() and ok
	return ok

static func _test_credit_drawer_flow() -> bool:
	var game: GameScript = GameScript.new()
	game.initialize_session(20261113, null, true)

	var win: MainWindowScript = MainWindowScript.new()
	win.bind_game(game)
	win._ready()

	win.open_systems_drawer(SystemsDrawerScript.TabKind.CREDIT)
	if not win.systems_drawer.visible or win.systems_drawer.get_active_tab() != SystemsDrawerScript.TabKind.CREDIT:
		push_error("[test_d5_ui] Expected SystemsDrawer open on CREDIT tab")
		win.free()
		game.free()
		return false

	win.systems_drawer.set_selected_utilization(1.0)
	var preview: Dictionary = win.systems_drawer.get_credit_preview_snapshot()
	if not bool(preview.get("valid", false)):
		push_error("[test_d5_ui] Expected valid credit preview")
		win.free()
		game.free()
		return false

	var mult: float = float(preview.get("repayment_mult", 0.0))
	if not is_equal_approx(mult, 1.6):
		push_error("[test_d5_ui] Expected u=1.0 repayment_mult=1.6, got %.4f" % mult)
		win.free()
		game.free()
		return false

	var expected_debt_log: float = float(preview.get("repayment_total_log", NumScript.ZERO))
	win.systems_drawer._on_borrow_pressed()
	game.advance_frame(0.2)

	var state: SimStateScript = game.get_sim_state()
	if not state.credit.active_loan or absf(state.debt_total - expected_debt_log) > 1e-4:
		push_error("[test_d5_ui] Expected active_loan=true and debt_total matching preview (got %.4f vs %.4f)" % [state.debt_total, expected_debt_log])
		win.free()
		game.free()
		return false

	win.free()
	game.free()
	print("[test_d5_ui] _test_credit_drawer_flow PASS")
	return true

static func _test_tech_drawer_flow() -> bool:
	var game: GameScript = GameScript.new()
	game.initialize_session(20261113, null, true)
	var state: SimStateScript = game.get_sim_state()
	state.gold = 10.0

	var win: MainWindowScript = MainWindowScript.new()
	win.bind_game(game)
	win._ready()

	win.open_systems_drawer(SystemsDrawerScript.TabKind.TECH)
	win.systems_drawer._on_research_node_pressed("combat_edge")
	game.advance_frame(0.2)

	if state.research_queue.entries.size() != 1:
		push_error("[test_d5_ui] Expected 1 queued research entry, got %d" % state.research_queue.entries.size())
		win.free()
		game.free()
		return false

	game.request_settle_research(Time.get_unix_time_from_system() + 100.0)
	game.advance_frame(0.2)

	if not state.tech.has_researched("combat_edge"):
		push_error("[test_d5_ui] Expected combat_edge researched after settle_research")
		win.free()
		game.free()
		return false

	win.free()
	game.free()
	print("[test_d5_ui] _test_tech_drawer_flow PASS")
	return true

static func _test_toll_drawer_view() -> bool:
	var game: GameScript = GameScript.new()
	game.initialize_session(20261113, null, true)

	var win: MainWindowScript = MainWindowScript.new()
	win.bind_game(game)
	win._ready()

	win.open_systems_drawer(SystemsDrawerScript.TabKind.TOLL)
	win.refresh_hud()

	if not win.systems_drawer.visible or win.systems_drawer.get_active_tab() != SystemsDrawerScript.TabKind.TOLL:
		push_error("[test_d5_ui] Expected SystemsDrawer open on TOLL tab")
		win.free()
		game.free()
		return false

	win.close_systems_drawer()
	if win.systems_drawer.visible:
		push_error("[test_d5_ui] Expected SystemsDrawer closed")
		win.free()
		game.free()
		return false

	win.free()
	game.free()
	print("[test_d5_ui] _test_toll_drawer_view PASS")
	return true
