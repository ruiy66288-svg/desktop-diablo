class_name TestP2UiCodexSummonReport extends RefCounted

## 阶段 2 UI 闭环单元测试 (WP-P2-UI-2)
## 覆盖：
## 1. CodexSummonPanel 三合一抽屉 (图鉴·套装 / 召唤·首领 / 外观·幻化)
## 2. 契约大执政官召唤、战斗态立绘/倒计时/撤退与零损失返还
## 3. 外观与太古木刻幻化槽位同步
## 4. ReturnReportModal 离线回归报告卡展示与战利品领取
## 5. Game.gd 独立 Codex 持久化与离线回归信号闭环
## 铁律：100% 显式静态类型，零 :=，零 dust

const GameScript = preload("res://autoload/Game.gd")
const SimStateScript = preload("res://simulation/SimState.gd")
const BalanceScript = preload("res://simulation/Balance.gd")
const CodexScript = preload("res://persistence/Codex.gd")
const CodexSummonPanelScript = preload("res://ui/CodexSummonPanel.gd")
const ReturnReportModalScript = preload("res://ui/ReturnReportModal.gd")
const MainWindowScript = preload("res://ui/MainWindow.gd")
const EquipSlotViewScript = preload("res://ui/EquipSlotView.gd")

static func run() -> bool:
	print("--- Running TestP2UiCodexSummonReport ---")

	if not _test_codex_summon_panel_tabs():
		printerr("[TestP2UiCodexSummonReport] FAILED: _test_codex_summon_panel_tabs")
		return false

	if not _test_summon_and_abort_rare_boss_flow():
		printerr("[TestP2UiCodexSummonReport] FAILED: _test_summon_and_abort_rare_boss_flow")
		return false

	if not _test_transmog_application():
		printerr("[TestP2UiCodexSummonReport] FAILED: _test_transmog_application")
		return false

	if not _test_return_report_modal():
		printerr("[TestP2UiCodexSummonReport] FAILED: _test_return_report_modal")
		return false

	if not _test_codex_persistence_via_game():
		printerr("[TestP2UiCodexSummonReport] FAILED: _test_codex_persistence_via_game")
		return false

	print("--- TestP2UiCodexSummonReport: ALL 5/5 PASSED ---")
	return true

static func _test_codex_summon_panel_tabs() -> bool:
	var game: GameScript = GameScript.new()
	game.initialize_session(12345)

	var panel: CodexSummonPanelScript = CodexSummonPanelScript.new()
	panel.bind_game(game)

	# 1. 默认标签
	panel.open_tab(0)
	if panel.get_active_tab() != CodexSummonPanelScript.TabKind.CODEX_SETS:
		printerr("[CodexPanel] Tab 0 mismatch")
		panel.free()
		game.free()
		return false

	# 2. 切换到召唤标签
	panel.open_tab(1)
	if panel.get_active_tab() != CodexSummonPanelScript.TabKind.SUMMON_ARCHON:
		printerr("[CodexPanel] Tab 1 mismatch")
		panel.free()
		game.free()
		return false

	# 3. 切换到幻化标签
	panel.open_tab(2)
	if panel.get_active_tab() != CodexSummonPanelScript.TabKind.COSMETICS_TRANSMOG:
		printerr("[CodexPanel] Tab 2 mismatch")
		panel.free()
		game.free()
		return false

	panel.close_drawer()
	if panel.visible:
		printerr("[CodexPanel] close_drawer failed")
		panel.free()
		game.free()
		return false

	panel.free()
	game.free()
	return true

static func _test_summon_and_abort_rare_boss_flow() -> bool:
	var game: GameScript = GameScript.new()
	game.initialize_session(88888)
	var state: SimStateScript = game.get_sim_state()
	var codex: CodexScript = state.ensure_codex()
	codex.summon_runes = 2

	var main_win: MainWindowScript = MainWindowScript.new()
	main_win._build_window_hierarchy()
	main_win.bind_game(game)

	# 初始非稀有 Boss 态
	main_win.refresh_hud()
	if main_win.btn_retreat_rare_boss.visible:
		printerr("[RareBossFlow] Retreat button should be hidden initially")
		main_win.free()
		game.free()
		return false

	# 发起召唤
	game.request_summon_rare_boss()
	game.advance_frame(0.1) # 执行 Command 队列

	if not state.is_rare_boss_active:
		printerr("[RareBossFlow] state.is_rare_boss_active should be true")
		main_win.free()
		game.free()
		return false
	if codex.summon_runes != 1:
		printerr("[RareBossFlow] Rune should be consumed (expected 1, got %d)" % codex.summon_runes)
		main_win.free()
		game.free()
		return false

	# 刷新 UI 并验证战斗态
	main_win.refresh_hud()
	if not main_win.btn_retreat_rare_boss.visible:
		printerr("[RareBossFlow] Retreat button should be visible during rare boss")
		main_win.free()
		game.free()
		return false
	if not main_win.label_mob_name.text.begins_with("契约大执政官"):
		printerr("[RareBossFlow] Label mob name should begin with 契约大执政官, got: ", main_win.label_mob_name.text)
		main_win.free()
		game.free()
		return false

	# 主动撤退（零损失返还符文）
	game.request_abort_rare_boss()
	game.advance_frame(0.1)

	if state.is_rare_boss_active:
		printerr("[RareBossFlow] state.is_rare_boss_active should be false after abort")
		main_win.free()
		game.free()
		return false
	if codex.summon_runes != 2:
		printerr("[RareBossFlow] Rune should be refunded (expected 2, got %d)" % codex.summon_runes)
		main_win.free()
		game.free()
		return false

	main_win.refresh_hud()
	if main_win.btn_retreat_rare_boss.visible:
		printerr("[RareBossFlow] Retreat button should be hidden after abort")
		main_win.free()
		game.free()
		return false

	main_win.free()
	game.free()
	return true

static func _test_transmog_application() -> bool:
	var game: GameScript = GameScript.new()
	game.initialize_session(99999)
	var state: SimStateScript = game.get_sim_state()

	var slot_view: EquipSlotViewScript = EquipSlotViewScript.new()
	slot_view.setup_slot("weapon")

	# 初始无幻化
	if not slot_view.transmog_id.is_empty():
		printerr("[Transmog] Initial transmog should be empty")
		slot_view.free()
		game.free()
		return false

	# 发送武器幻化指令
	game.request_set_transmog("weapon", "transmog_archon_blade")
	game.advance_frame(0.1)

	if state.get_transmog("weapon") != "transmog_archon_blade":
		printerr("[Transmog] SimState transmog mismatch: ", state.get_transmog("weapon"))
		slot_view.free()
		game.free()
		return false

	slot_view.set_transmog_id(state.get_transmog("weapon"))
	if slot_view.transmog_id != "transmog_archon_blade":
		printerr("[Transmog] SlotView transmog mismatch")
		slot_view.free()
		game.free()
		return false

	# 饰品槽幻化测试
	var trinket_view: EquipSlotViewScript = EquipSlotViewScript.new()
	trinket_view.setup_slot("trinket")
	game.request_set_transmog("trinket", "unique_trinket")
	game.advance_frame(0.1)
	trinket_view.set_transmog_id(state.get_transmog("trinket"))
	if trinket_view.transmog_id != "unique_trinket":
		printerr("[Transmog] Trinket SlotView transmog mismatch")
		trinket_view.free()
		slot_view.free()
		game.free()
		return false

	trinket_view.free()
	slot_view.free()
	game.free()
	return true

static func _test_return_report_modal() -> bool:
	var modal: ReturnReportModalScript = ReturnReportModalScript.new()
	var signal_box: Array[bool] = [false]

	modal.claimed.connect(func(_summary: Dictionary) -> void:
		signal_box[0] = true
	)

	var mock_summary: Dictionary = {
		"elapsed_seconds": 7200.0,
		"effective_seconds": 7200.0,
		"capped": false,
		"gold_gain_log": 8.5,
		"research_done": ["tech_1", "tech_2"],
		"run_best_before": 100,
		"run_best_after": 125,
		"stages_advanced": 25,
		"debt_repaid_log": 4.2,
		"new_uniques": ["雷霆之刃"],
		"new_summon_runes": 1
	}

	modal.show_report(mock_summary)
	if not modal.visible:
		printerr("[ReturnReport] Modal should be visible after show_report")
		modal.free()
		return false

	modal._on_claim_pressed()
	if not signal_box[0]:
		printerr("[ReturnReport] Claimed signal was not received")
		modal.free()
		return false
	if modal.visible:
		printerr("[ReturnReport] Modal should be hidden after claim")
		modal.free()
		return false

	modal.free()
	return true

static func _test_codex_persistence_via_game() -> bool:
	var save_path: String = "user://test_p2_save.json"
	var codex_path: String = "user://test_p2_codex.json"

	var g1: GameScript = GameScript.new()
	g1.initialize_session(77777)
	var s1: SimStateScript = g1.get_sim_state()
	var c1: CodexScript = s1.ensure_codex()
	c1.save_path = codex_path
	c1.summon_runes = 5
	c1.unlock_unique("thunder_blade")
	c1.unlock_cosmetic("transmog_archon_blade")

	var err: Error = g1.save_current_game(save_path)
	if err != OK:
		printerr("[Persistence] save_current_game failed: ", err)
		g1.free()
		return false

	# 另建会话载入
	var g2: GameScript = GameScript.new()
	g2.initialize_session(11111)
	var res: Dictionary = g2.load_saved_game(save_path)
	if not bool(res.get("loaded", false)):
		printerr("[Persistence] load_saved_game failed")
		g2.free()
		g1.free()
		return false

	var s2: SimStateScript = g2.get_sim_state()
	var c2: CodexScript = s2.ensure_codex()
	if c2.summon_runes != 5:
		printerr("[Persistence] Codex runes mismatch: expected 5, got %d" % c2.summon_runes)
		g2.free()
		g1.free()
		return false
	if not c2.uniques.has("thunder_blade"):
		printerr("[Persistence] Codex unique thunder_blade not loaded")
		g2.free()
		g1.free()
		return false
	if not c2.cosmetics.has("transmog_archon_blade"):
		printerr("[Persistence] Codex cosmetic transmog_archon_blade not loaded")
		g2.free()
		g1.free()
		return false

	g2.free()
	g1.free()

	# 清理测试存档
	for p: String in [save_path, save_path + ".meta.json", codex_path, codex_path + ".bak"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))

	return true
