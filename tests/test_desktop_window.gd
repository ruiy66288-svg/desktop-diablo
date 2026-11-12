class_name TestDesktopWindow extends RefCounted

## WP-07 桌面常驻小窗、マウス穿透多边形、Game 最小化排空与极简 HUD 自动化测试套件
## 100% 显式静态类型，零隐式类型推导，覆盖贴角吸附、越界拉回、穿透多边形、Command 闭环与 HUD 增长

const DesktopWindowScript = preload("res://platform/DesktopWindow.gd")
const GameScript = preload("res://autoload/Game.gd")
const SimStateScript = preload("res://simulation/SimState.gd")
const MainWindowScript = preload("res://ui/MainWindow.gd")
const ThemePaletteScript = preload("res://ui/ThemePalette.gd")
const NumScript = preload("res://core/num/Num.gd")

const TEST_SAVE_PATH: String = "user://test_wp07_window_pos.json"

static func run() -> bool:
	print("[TestDesktopWindow] 开始测试 WP-07 桌面常驻小窗与极简 HUD...")

	if not _test_snap_and_clamp_math():
		return false
	if not _test_persistence_and_oob_recovery():
		return false
	if not _test_mouse_passthrough_polygons():
		return false
	if not _test_game_hud_progression_and_minimized_bus():
		return false

	print("[TestDesktopWindow] WP-07 全部单元测试 100% 通过!")
	return true

static func _test_snap_and_clamp_math() -> bool:
	var screen: Rect2i = Rect2i(Vector2i(0, 0), Vector2i(1920, 1040))
	var win: Vector2i = Vector2i(360, 480)
	var margin: int = 24

	# 四角吸附验证
	var snap_tl: Vector2i = DesktopWindowScript.compute_snapped_position(Vector2i(14, 18), win, screen, margin)
	if snap_tl != Vector2i(0, 0):
		printerr("[TestDesktopWindow] 左上角吸附错误: ", snap_tl)
		return false

	var snap_tr: Vector2i = DesktopWindowScript.compute_snapped_position(Vector2i(1544, 12), win, screen, margin)
	if snap_tr != Vector2i(1560, 0):
		printerr("[TestDesktopWindow] 右上角吸附错误: ", snap_tr)
		return false

	var snap_bl: Vector2i = DesktopWindowScript.compute_snapped_position(Vector2i(20, 545), win, screen, margin)
	if snap_bl != Vector2i(0, 560):
		printerr("[TestDesktopWindow] 左下角吸附错误: ", snap_bl)
		return false

	var snap_br: Vector2i = DesktopWindowScript.compute_snapped_position(Vector2i(1540, 542), win, screen, margin)
	if snap_br != Vector2i(1560, 560):
		printerr("[TestDesktopWindow] 右下角吸附错误: ", snap_br)
		return false

	# 单边吸附与阈值外保持验证
	var snap_right_mid: Vector2i = DesktopWindowScript.compute_snapped_position(Vector2i(1550, 260), win, screen, margin)
	if snap_right_mid != Vector2i(1560, 260):
		printerr("[TestDesktopWindow] 右边缘单轴吸附错误: ", snap_right_mid)
		return false

	var free_pos: Vector2i = DesktopWindowScript.compute_snapped_position(Vector2i(600, 260), win, screen, margin)
	if free_pos != Vector2i(600, 260):
		printerr("[TestDesktopWindow] 吸附阈值外不应发生位移: ", free_pos)
		return false

	# 副屏负坐标起点屏幕吸附验证
	var second_screen: Rect2i = Rect2i(Vector2i(-1920, 30), Vector2i(1920, 1010))
	var snap_sec_tl: Vector2i = DesktopWindowScript.compute_snapped_position(Vector2i(-1908, 42), win, second_screen, margin)
	if snap_sec_tl != Vector2i(-1920, 30):
		printerr("[TestDesktopWindow] 副屏左上角吸附错误: ", snap_sec_tl)
		return false

	return true

static func _test_persistence_and_oob_recovery() -> bool:
	var screen: Rect2i = Rect2i(Vector2i(0, 0), Vector2i(1920, 1040))
	var win: Vector2i = Vector2i(360, 480)

	# 1. 正常保存与原子重命名校验
	var target_pos: Vector2i = Vector2i(420, 210)
	var saved_ok: bool = DesktopWindowScript.save_position_to_path(target_pos, TEST_SAVE_PATH)
	if not saved_ok or not FileAccess.file_exists(TEST_SAVE_PATH):
		printerr("[TestDesktopWindow] 窗口位置原子写入失败!")
		return false
	if FileAccess.file_exists(TEST_SAVE_PATH + ".tmp"):
		printerr("[TestDesktopWindow] 原子写入后残留 .tmp 文件!")
		return false

	var f: FileAccess = FileAccess.open(TEST_SAVE_PATH, FileAccess.READ)
	var raw_json: String = f.get_as_text() if f != null else ""
	f = null
	if raw_json.find("\"version\"") == -1:
		printerr("[TestDesktopWindow] 存档 JSON 缺少 version 字段 (§4.7)!")
		_cleanup_test_save()
		return false

	var loaded_pos: Vector2i = DesktopWindowScript.load_position_from_path(TEST_SAVE_PATH, win, screen)
	if loaded_pos != target_pos:
		printerr("[TestDesktopWindow] 窗口位置读取不一致: ", loaded_pos)
		_cleanup_test_save()
		return false

	# 2. 越界负坐标自动拉回可见屏幕内
	DesktopWindowScript.save_position_to_path(Vector2i(-4000, -1200), TEST_SAVE_PATH)
	var clamped_neg: Vector2i = DesktopWindowScript.load_position_from_path(TEST_SAVE_PATH, win, screen)
	if clamped_neg != Vector2i(0, 0):
		printerr("[TestDesktopWindow] 负越界坐标未拉回屏幕内: ", clamped_neg)
		_cleanup_test_save()
		return false

	# 3. 越界超大坐标自动拉回可见屏幕右下边界内
	DesktopWindowScript.save_position_to_path(Vector2i(9600, 5400), TEST_SAVE_PATH)
	var clamped_pos: Vector2i = DesktopWindowScript.load_position_from_path(TEST_SAVE_PATH, win, screen)
	if clamped_pos != Vector2i(1560, 560):
		printerr("[TestDesktopWindow] 正越界坐标未拉回屏幕内: ", clamped_pos)
		_cleanup_test_save()
		return false

	_cleanup_test_save()
	return true

static func _cleanup_test_save() -> void:
	if FileAccess.file_exists(TEST_SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE_PATH))
	if FileAccess.file_exists(TEST_SAVE_PATH + ".tmp"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE_PATH + ".tmp"))

static func _test_mouse_passthrough_polygons() -> bool:
	# 1. 常驻圆角矩形交互多边形：四角外侧透明像素穿透，标题栏与 HUD 正常响应
	var inner_rect: Rect2 = Rect2(Vector2(2.0, 2.0), Vector2(356.0, 476.0))
	var rounded_poly: PackedVector2Array = DesktopWindowScript.build_rounded_rect_polygon(inner_rect, 12.0, 6)
	if rounded_poly.size() < 24:
		printerr("[TestDesktopWindow] 圆角穿透多边形顶点数不足: ", rounded_poly.size())
		return false
	if Geometry2D.is_point_in_polygon(Vector2(0.5, 0.5), rounded_poly):
		printerr("[TestDesktopWindow] 圆角外透明区 (0.5, 0.5) 应当穿透桌面，不应在多边形内!")
		return false
	if not Geometry2D.is_point_in_polygon(Vector2(180.0, 12.0), rounded_poly):
		printerr("[TestDesktopWindow] 标题栏交互点不在圆角交互多边形内!")
		return false
	if not Geometry2D.is_point_in_polygon(Vector2(180.0, 406.0), rounded_poly):
		printerr("[TestDesktopWindow] 底部 HUD 交互点不在圆角交互多边形内!")
		return false

	# 2. 战场穿透模式多边形：中部透明/非交互区穿透点击桌面，标题栏与底部 HUD/装备槽保持可点击
	var split_poly: PackedVector2Array = DesktopWindowScript.build_split_interactive_polygon(
		Vector2(360.0, 480.0),
		26.0,
		362.0,
		2.0,
		4.0
	)
	if Geometry2D.is_point_in_polygon(Vector2(180.0, 200.0), split_poly):
		printerr("[TestDesktopWindow] 穿透模式下中部非交互区 (180, 200) 必须穿透点击桌面!")
		return false
	if not Geometry2D.is_point_in_polygon(Vector2(180.0, 12.0), split_poly):
		printerr("[TestDesktopWindow] 穿透模式下标题栏 (180, 12) 必须保持可交互!")
		return false
	if not Geometry2D.is_point_in_polygon(Vector2(180.0, 406.0), split_poly):
		printerr("[TestDesktopWindow] 穿透模式下极简 HUD (180, 406) 必须保持可交互!")
		return false
	if not Geometry2D.is_point_in_polygon(Vector2(180.0, 448.0), split_poly):
		printerr("[TestDesktopWindow] 穿透模式下六槽装备栏 (180, 448) 必须保持可交互!")
		return false

	return true

static func _test_game_hud_progression_and_minimized_bus() -> bool:
	var game: GameScript = GameScript.new()
	game.initialize_session(20261112)
	game.set_auto_tick_enabled(false)

	var win: MainWindowScript = MainWindowScript.new()
	win.bind_game(game)
	win._ready()
	win.bind_game(game)

	# 校验 §03 冻结色板与 §02.1 初始布局尺寸
	if ThemePaletteScript.HEX_CARD_BG != "#16161C" or ThemePaletteScript.HEX_BONE_WHITE != "#E8DCC0":
		printerr("[TestDesktopWindow] 冻结 HEX 色板常量不符!")
		win.free()
		game.free()
		return false
	if win.main_card.size != Vector2(176.0, 220.0) or win.queue_card_1.size != Vector2(72.0, 90.0):
		printerr("[TestDesktopWindow] 主怪卡或排队卡初始尺寸违反 03 §02.1!")
		win.free()
		game.free()
		return false
	if win.equip_slot_views.size() != 6:
		printerr("[TestDesktopWindow] 装备槽数量不为 6!")
		win.free()
		game.free()
		return false

	# 推进 10Hz tick 直至自动打怪熔炼突破第 2 层并攒够首级金币升级费用 (Gate-1 c0_cost_log=3.3)，期间通过 UI 槽位 Command 穿戴掉落暗金加速推进
	var guard_ticks: int = 0
	var first_upg_cost: float = game.get_sim_state().upgrades.get_next_atk_cost_log(game.get_sim_state())
	while guard_ticks < 6000 and (game.get_sim_state().run_best < 2 or game.get_sim_state().gold < first_upg_cost):
		game.advance_frame(0.1)
		win._consume_presentation_events()
		if guard_ticks % 100 == 0:
			for slot_name: String in SimStateScript.EQUIP_SLOTS:
				win._on_equip_slot_clicked(slot_name)
		guard_ticks += 1
	win.refresh_hud()

	var state: SimStateScript = game.get_sim_state()
	if state.gold <= NumScript.ZERO:
		printerr("[TestDesktopWindow] 推进 350 tick 后金币未增长!")
		win.free()
		game.free()
		return false
	if state.run_best < 2:
		printerr("[TestDesktopWindow] 推进 350 tick 后层数未突破第 1 层, 当前 run_best=", state.run_best)
		win.free()
		game.free()
		return false
	if win.label_run_best.text == "第 1 层" or win.label_gold.text == "金币 0" or win.label_wealth.text == "净资 0":
		printerr("[TestDesktopWindow] HUD 文本未能随 SimState 增长同步刷新!")
		win.free()
		game.free()
		return false

	# 验证 UI 按钮通过 Command 队列修改 Sim（零直接写 SimState，§4.2）
	var prev_atk_lv: int = state.upgrades.atk_level
	win._on_btn_upgrade_atk_pressed()
	if state.upgrades.atk_level != prev_atk_lv:
		printerr("[TestDesktopWindow] UI 点击在未推进 tick 前直接篡改了 SimState，违反 Command 队列隔离!")
		win.free()
		game.free()
		return false
	game.advance_frame(0.1)
	win.refresh_hud()
	if state.upgrades.atk_level != prev_atk_lv + 1:
		printerr("[TestDesktopWindow] Command.BUY_ATK_UPGRADE 未在下一 tick 生效!")
		win.free()
		game.free()
		return false

	# 验证勘误 E8 & Q10：窗口最小化期间 SimRunner 正常推进且每帧排空消费 PresentationBus，无积压
	var ticks_before_min: int = state.tick_count
	game.set_simulated_minimized(true)
	for _min_i: int in range(100):
		game.advance_frame(0.1)
	if state.tick_count != ticks_before_min + 100:
		printerr("[TestDesktopWindow] 窗口最小化期间 SimRunner 未正常按 10Hz 推进!")
		win.free()
		game.free()
		return false
	if game.get_presentation_bus().get_pending_count() != 0:
		printerr("[TestDesktopWindow] 窗口最小化期间 PresentationBus 未被排空消费，存在积压风险!")
		win.free()
		game.free()
		return false

	game.set_simulated_minimized(false)
	game.advance_frame(0.1)
	var summary: Dictionary = game.get_last_minimized_summary()
	if int(summary.get("kills", 0)) <= 0:
		printerr("[TestDesktopWindow] 窗口最小化恢复后未生成回归击杀汇总!")
		win.free()
		game.free()
		return false

	win.free()
	game.free()
	return true
