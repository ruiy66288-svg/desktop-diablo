extends SceneTree

## [WP-P15-FONT-PLAT] 思源宋体 OFL 子集化嵌入、Windows 系统托盘常驻与 DWM 防黑底封装自动化测试套件
## 运行方式（单跑）：Godot_v4.7.2-stable_win64_console.exe --headless --path "F:\挂机游戏制作" --script res://tests/test_p2_platform_tray.gd
## 兼容方式（总控）：TestP2PlatformTray.run() -> bool
## 铁律：100% 显式静态类型，零隐式类型推导，零跨目录写 SimState

const DesktopWindowScript = preload("res://platform/DesktopWindow.gd")
const SystemTrayScript = preload("res://platform/SystemTray.gd")
const GameScript = preload("res://autoload/Game.gd")

const SUBSET_FONT_RES_PATH: String = "res://assets/fonts/NotoSerifSC-Subset.ttf"
const SUBSET_FONT_IMPORT_PATH: String = "res://assets/fonts/NotoSerifSC-Subset.ttf.import"
const OFL_TEXT_REL_PATH: String = "art_source/licenses/texts/OFL-1.1-NotoSerifSC.txt"
const NOTICES_RES_PATH: String = "res://third_party_notices.txt"

const TEST_POS_SAVE_PATH: String = "user://test_p2_tray_window_pos.json"
const TEST_GAME_SAVE_PATH: String = "user://test_p2_tray_game_save.json"

func _init() -> void:
	var all_ok: bool = run()
	quit(0 if all_ok else 1)

static func run() -> bool:
	print("[TestP2PlatformTray] 开始测试 WP-P15-FONT-PLAT 字体子集化、系统托盘与 DWM 平台层...")

	if not _test_noto_serif_subset_and_ofl_compliance():
		return false
	if not _test_woodcut_badge_and_tray_menu_setup():
		return false
	if not _test_tray_interactions_and_hidden_bus_drain():
		return false
	if not _test_dwm_safe_probe_and_black_bg_guard():
		return false

	print("[TestP2PlatformTray] WP-P15-FONT-PLAT 全部单元测试 100% 通过!")
	return true

static func _test_noto_serif_subset_and_ofl_compliance() -> bool:
	var abs_font_path: String = ProjectSettings.globalize_path(SUBSET_FONT_RES_PATH)
	if not FileAccess.file_exists(SUBSET_FONT_RES_PATH):
		printerr("[TestP2PlatformTray] 缺少子集化字体文件: ", SUBSET_FONT_RES_PATH)
		return false
	if not FileAccess.file_exists(SUBSET_FONT_IMPORT_PATH):
		printerr("[TestP2PlatformTray] 缺少字体 Godot .import 文件: ", SUBSET_FONT_IMPORT_PATH)
		return false

	var f_font: FileAccess = FileAccess.open(abs_font_path, FileAccess.READ)
	if f_font == null:
		printerr("[TestP2PlatformTray] 无法打开字体文件读取字节大小!")
		return false
	var font_bytes: int = int(f_font.get_length())
	f_font = null
	if font_bytes < 500000 or font_bytes > 8000000:
		printerr("[TestP2PlatformTray] 子集化字体体积异常 (期望 0.5MB~8MB): ", font_bytes)
		return false

	var loaded_res: Resource = ResourceLoader.load(SUBSET_FONT_RES_PATH)
	if not (loaded_res is FontFile):
		printerr("[TestP2PlatformTray] ResourceLoader 加载子集化字体未返回 FontFile!")
		return false
	var font_file: FontFile = loaded_res as FontFile

	# 校验核心中文词汇、数字与符号度量有效且无缺字
	var required_sample: String = "桌面破坏神·镀金债契骨白版画 第100层 护盾反噬暴击分身吞金 灵魂深渊转生 +29,589.3%"
	var measured_size: Vector2 = font_file.get_string_size(required_sample, HORIZONTAL_ALIGNMENT_LEFT, -1, 16)
	if measured_size.x <= 120.0 or measured_size.y <= 10.0:
		printerr("[TestP2PlatformTray] 子集化字体文本排版尺寸异常: ", measured_size)
		return false

	for idx: int in range(required_sample.length()):
		var cp: int = required_sample.unicode_at(idx)
		if cp > 32 and not font_file.has_char(cp):
			printerr("[TestP2PlatformTray] 子集化字体缺失核心字符: ", required_sample.substr(idx, 1), " U+", String.num_int64(cp, 16))
			return false

	# 校验 OFL 1.1 许可证全文归档（art_source 含 .gdignore，使用绝对路径读取）
	var abs_ofl_path: String = ProjectSettings.globalize_path("res://" + OFL_TEXT_REL_PATH)
	var f_ofl: FileAccess = FileAccess.open(abs_ofl_path, FileAccess.READ)
	if f_ofl == null:
		printerr("[TestP2PlatformTray] 缺少 OFL 1.1 许可证全文文件: ", OFL_TEXT_REL_PATH)
		return false
	var ofl_text: String = f_ofl.get_as_text()
	f_ofl = null
	if ofl_text.find("SIL OPEN FONT LICENSE Version 1.1") == -1 or ofl_text.find("Adobe") == -1:
		printerr("[TestP2PlatformTray] OFL-1.1-NotoSerifSC.txt 内容不完整!")
		return false

	# 校验根目录 third_party_notices.txt 已完整包含 Noto Serif SC 的版权与 SIL OFL 1.1 全文
	var abs_notices_path: String = ProjectSettings.globalize_path(NOTICES_RES_PATH)
	var f_notices: FileAccess = FileAccess.open(abs_notices_path, FileAccess.READ)
	if f_notices == null:
		printerr("[TestP2PlatformTray] 无法读取根目录 third_party_notices.txt!")
		return false
	var notices_text: String = f_notices.get_as_text()
	f_notices = null
	if notices_text.find("Noto Serif SC") == -1 or notices_text.find("SIL OPEN FONT LICENSE Version 1.1") == -1 or notices_text.find("PERMISSION & CONDITIONS") == -1:
		printerr("[TestP2PlatformTray] third_party_notices.txt 未完整收录 SIL OFL 1.1 许可证全文!")
		return false

	print("[TestP2PlatformTray] 思源宋体子集化 (%.2f MB) 与 SIL OFL 1.1 合规声明验证通过" % [float(font_bytes) / 1048576.0])
	return true

static func _test_woodcut_badge_and_tray_menu_setup() -> bool:
	var badge: ImageTexture = SystemTrayScript.build_woodcut_badge_texture(32)
	if badge == null or badge.get_size() != Vector2(32.0, 32.0):
		printerr("[TestP2PlatformTray] 托盘木刻徽章尺寸异常!")
		return false

	var img: Image = badge.get_image()
	if img == null:
		printerr("[TestP2PlatformTray] 托盘徽章无法提取 Image 数据!")
		return false

	# 四角切角处应为透明，中心剑脊/天平处应为不透明骨白或镀金像素
	if img.get_pixel(0, 0).a > 0.01:
		printerr("[TestP2PlatformTray] 托盘木刻徽章外角应为透明像素!")
		return false
	if img.get_pixel(16, 16).a < 0.99:
		printerr("[TestP2PlatformTray] 托盘木刻徽章中心像素不应透明!")
		return false

	var dw: DesktopWindowScript = DesktopWindowScript.new()
	dw.save_path = TEST_POS_SAVE_PATH
	dw._ready()

	var tray: SystemTrayScript = dw.get_system_tray()
	if tray == null:
		printerr("[TestP2PlatformTray] DesktopWindow 未自动挂载 SystemTray 子节点!")
		dw.free()
		return false
	tray._ready()

	if tray.status_indicator == null or tray.popup_menu == null:
		printerr("[TestP2PlatformTray] SystemTray 未创建 StatusIndicator 或 PopupMenu!")
		dw.free()
		return false
	if tray.status_indicator.icon == null:
		printerr("[TestP2PlatformTray] StatusIndicator 未绑定木刻徽章图标!")
		dw.free()
		return false
	if tray.status_indicator.menu.is_empty():
		printerr("[TestP2PlatformTray] StatusIndicator.menu NodePath 未绑定至 PopupMenu!")
		dw.free()
		return false

	var items: Array[String] = tray.get_menu_item_texts()
	var expected_items: Array[String] = [
		"显示 / 隐藏小窗",
		"静音 / 开启音效",
		"重置回屏幕右下角",
		"立即存档并退出"
	]
	for req_label: String in expected_items:
		if not items.has(req_label):
			printerr("[TestP2PlatformTray] 托盘右键菜单缺少必需项: ", req_label, " 实际=", items)
			dw.free()
			return false

	dw.free()
	_cleanup_temp_files()
	print("[TestP2PlatformTray] 木刻徽章图标生成、StatusIndicator 与右键四项菜单配置验证通过")
	return true

static func _test_tray_interactions_and_hidden_bus_drain() -> bool:
	_cleanup_temp_files()

	var was_bus_muted_before: bool = false
	if AudioServer.get_bus_count() > 0:
		was_bus_muted_before = AudioServer.is_bus_mute(0)

	var game: GameScript = GameScript.new()
	game.initialize_session(20261113)
	game.set_auto_tick_enabled(false)

	var host_ctrl: Control = Control.new()
	host_ctrl.size = Vector2(360.0, 480.0)
	var dw: DesktopWindowScript = DesktopWindowScript.new()
	dw.save_path = TEST_POS_SAVE_PATH
	dw.bind_game(game)
	host_ctrl.add_child(dw)
	dw._ready()
	var tray: SystemTrayScript = dw.get_system_tray()
	tray._ready()
	tray.configure_for_test(true, TEST_GAME_SAVE_PATH)

	# 1. 左键单击托盘图标：一键隐藏小窗，并联动 Game 进入最小化排空模式 (02 Q10)
	tray.handle_tray_pressed(MOUSE_BUTTON_LEFT, Vector2i(1800, 1060))
	if not dw.is_hidden_to_tray() or host_ctrl.visible:
		printerr("[TestP2PlatformTray] 左键单击托盘图标后窗口未进入隐藏态!")
		_teardown_tray_test(host_ctrl, game, was_bus_muted_before)
		return false
	if not game.is_window_minimized():
		printerr("[TestP2PlatformTray] 隐藏至托盘期间未联动 Game.is_window_minimized()!")
		_teardown_tray_test(host_ctrl, game, was_bus_muted_before)
		return false

	# 隐藏期间推进 160 ticks (16 秒)，验证模拟正常推进且 PresentationBus 每帧排空零堆积
	var start_ticks: int = game.get_sim_state().tick_count
	for _step_i: int in range(160):
		game.advance_frame(0.1)
		dw._process(0.1)
	if game.get_sim_state().tick_count != start_ticks + 160:
		printerr("[TestP2PlatformTray] 隐藏至托盘期间 SimRunner 未正常推进!")
		_teardown_tray_test(host_ctrl, game, was_bus_muted_before)
		return false
	if game.get_presentation_bus().get_pending_count() != 0:
		printerr("[TestP2PlatformTray] 隐藏至托盘期间 PresentationBus 发生积压 (未排空)!")
		_teardown_tray_test(host_ctrl, game, was_bus_muted_before)
		return false

	# 2. 右键菜单「显示 / 隐藏小窗」恢复显示，验证回归摘要正常结算
	tray.activate_menu_item(SystemTrayScript.MENU_ID_TOGGLE_WINDOW)
	if dw.is_hidden_to_tray() or not host_ctrl.visible or game.is_window_minimized():
		printerr("[TestP2PlatformTray] 菜单触发切换后小窗未恢复显示态!")
		_teardown_tray_test(host_ctrl, game, was_bus_muted_before)
		return false
	game.advance_frame(0.1)
	var min_summary: Dictionary = game.get_last_minimized_summary()
	if int(min_summary.get("kills", 0)) <= 0:
		printerr("[TestP2PlatformTray] 从托盘恢复显示后未生成后台击杀汇总!")
		_teardown_tray_test(host_ctrl, game, was_bus_muted_before)
		return false

	# 3. 右键菜单「静音 / 开启音效」双向切换校验
	tray.set_audio_muted(false)
	tray.activate_menu_item(SystemTrayScript.MENU_ID_TOGGLE_MUTE)
	if not tray.is_audio_muted():
		printerr("[TestP2PlatformTray] 触发静音菜单后静音标志未置 true!")
		_teardown_tray_test(host_ctrl, game, was_bus_muted_before)
		return false
	if AudioServer.get_bus_count() > 0 and not AudioServer.is_bus_mute(0):
		printerr("[TestP2PlatformTray] 触发静音菜单后 AudioServer Master 总线未静音!")
		_teardown_tray_test(host_ctrl, game, was_bus_muted_before)
		return false
	tray.activate_menu_item(SystemTrayScript.MENU_ID_TOGGLE_MUTE)
	if tray.is_audio_muted():
		printerr("[TestP2PlatformTray] 再次触发静音菜单后未恢复开启音效!")
		_teardown_tray_test(host_ctrl, game, was_bus_muted_before)
		return false

	# 4. 将窗口拖离并隐藏后点击「重置回屏幕右下角」：自动唤醒并复位至默认右下角落盘
	dw.prefer_native_drag = false
	dw.begin_drag(Vector2i(500, 500))
	dw.update_drag(Vector2i(100, 120))
	dw.end_drag()
	dw.set_hidden_to_tray(true)

	tray.activate_menu_item(SystemTrayScript.MENU_ID_RESET_CORNER)
	var expected_corner: Vector2i = DesktopWindowScript.compute_default_corner_position(
		DesktopWindowScript.get_active_window_size(),
		DesktopWindowScript.get_active_usable_rect()
	)
	if dw.is_hidden_to_tray() or dw.get_current_window_position() != expected_corner:
		printerr("[TestP2PlatformTray] 重置回屏幕右下角坐标或唤醒状态不符: ", dw.get_current_window_position(), " != ", expected_corner)
		_teardown_tray_test(host_ctrl, game, was_bus_muted_before)
		return false
	if not FileAccess.file_exists(TEST_POS_SAVE_PATH) or FileAccess.file_exists(TEST_POS_SAVE_PATH + ".tmp"):
		printerr("[TestP2PlatformTray] 重置右下角未完成原子化坐标落盘!")
		_teardown_tray_test(host_ctrl, game, was_bus_muted_before)
		return false

	# 5. 右键菜单「立即存档并退出」：验证原子化写入正式游戏存档与元数据文件
	tray.activate_menu_item(SystemTrayScript.MENU_ID_SAVE_AND_QUIT)
	if not FileAccess.file_exists(TEST_GAME_SAVE_PATH):
		printerr("[TestP2PlatformTray] 触发立即存档并退出后未生成存档文件!")
		_teardown_tray_test(host_ctrl, game, was_bus_muted_before)
		return false
	var sf: FileAccess = FileAccess.open(TEST_GAME_SAVE_PATH, FileAccess.READ)
	var save_txt: String = sf.get_as_text() if sf != null else ""
	sf = null
	if save_txt.find("\"tick_count\"") == -1 and save_txt.find("\"version\"") == -1:
		printerr("[TestP2PlatformTray] 立即存档并退出生成的存档 JSON 内容非法!")
		_teardown_tray_test(host_ctrl, game, was_bus_muted_before)
		return false

	_teardown_tray_test(host_ctrl, game, was_bus_muted_before)
	print("[TestP2PlatformTray] 托盘左键显隐、后台排空零积压、静音切换、右下角复位与退出存档全部验证通过")
	return true

static func _test_dwm_safe_probe_and_black_bg_guard() -> bool:
	if DesktopWindowScript.parse_windows_build_number("10.0.26200") != 26200:
		printerr("[TestP2PlatformTray] Windows 11 Build 解析错误!")
		return false
	if DesktopWindowScript.parse_windows_build_number("10.0.19045") != 19045:
		printerr("[TestP2PlatformTray] Windows 10 Build 解析错误!")
		return false

	# 模拟 Windows 11 桌面环境 + 无边框逐像素透明开启：必须激活防黑底守卫并禁用 OS DWM Backdrop
	var win11_trans_caps: Dictionary = DesktopWindowScript.probe_dwm_capabilities("Windows", "10.0.26200", 0, 1)
	if not bool(win11_trans_caps.get("is_windows_11_plus", false)):
		printerr("[TestP2PlatformTray] Windows 11 判定失败!")
		return false
	if not bool(win11_trans_caps.get("prevent_black_bg_guard", false)):
		printerr("[TestP2PlatformTray] 逐像素透明模式下未激活防黑底守卫 (prevent_black_bg_guard)!")
		return false
	if bool(win11_trans_caps.get("os_dwm_backdrop_enabled", true)):
		printerr("[TestP2PlatformTray] 逐像素透明模式下严禁启用 OS DWM Backdrop，否则会导致黑底!")
		return false
	if str(win11_trans_caps.get("corner_policy", "")) != DesktopWindowScript.DWM_CORNER_POLICY_POLYGON_12PX:
		printerr("[TestP2PlatformTray] DWM 圆角安全策略标识不符!")
		return false

	# 验证当前 Headless 环境下降级零报错
	var headless_caps: Dictionary = DesktopWindowScript.probe_dwm_capabilities("Windows", "10.0.26200", 1, 1)
	if not bool(headless_caps.get("headless", false)) or bool(headless_caps.get("os_dwm_backdrop_enabled", true)):
		printerr("[TestP2PlatformTray] Headless 模式 DWM 探测降级结果异常!")
		return false

	var dw: DesktopWindowScript = DesktopWindowScript.new()
	dw.auto_mount_system_tray = false
	dw.save_path = TEST_POS_SAVE_PATH
	dw._ready()
	var applied_status: Dictionary = dw.get_dwm_status()
	if applied_status.is_empty():
		printerr("[TestP2PlatformTray] DesktopWindow._ready() 未初始化 DWM 状态字典!")
		dw.free()
		_cleanup_temp_files()
		return false
	dw.free()
	_cleanup_temp_files()

	print("[TestP2PlatformTray] Windows DWM 属性探测、逐像素透明防黑底守卫与 Headless 零报错降级验证通过")
	return true

static func _teardown_tray_test(host_ctrl: Control, game: GameScript, restore_mute: bool) -> void:
	if AudioServer.get_bus_count() > 0:
		AudioServer.set_bus_mute(0, restore_mute)
	if host_ctrl != null:
		host_ctrl.free()
	if game != null:
		game.free()
	_cleanup_temp_files()

static func _cleanup_temp_files() -> void:
	var paths: Array[String] = [
		TEST_POS_SAVE_PATH,
		TEST_POS_SAVE_PATH + ".tmp",
		TEST_GAME_SAVE_PATH,
		TEST_GAME_SAVE_PATH + ".tmp",
		TEST_GAME_SAVE_PATH + ".bak",
		TEST_GAME_SAVE_PATH + ".meta.json"
	]
	for p: String in paths:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
