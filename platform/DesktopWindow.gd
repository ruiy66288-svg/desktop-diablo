class_name DesktopWindow extends Control

## 桌面常驻无边框小窗平台控制器 (依据《02_系统架构与数值_v6.md》§3.3、Q10、《03_美术风格圣经_v1.0.md》§02.6 与 WP-07 / WP-P15-FONT-PLAT)
## 职责：
## 1. 原生/脚本兜底拖拽、四角与边缘吸附、带 version 原子持久化位置记忆（越界自动拉回）、鼠标穿透多边形
## 2. Windows 系统托盘常驻挂载（SystemTray）与隐藏至托盘期间联动 Game.set_simulated_minimized 持续排空 PresentationBus
## 3. Windows DWM 圆角与磨砂属性安全探测封装（无边框逐像素透明模式下防黑底守卫，Headless 模式零报错降级）
## 铁律：100% 显式静态类型，零 SimState 写入，零硬编码未封装魔法数

const SystemTrayScript = preload("res://platform/SystemTray.gd")

const SAVE_FORMAT_VERSION: int = 1
const DEFAULT_SAVE_PATH: String = "user://window_pos.json"
const DEFAULT_SNAP_MARGIN_PX: int = 24
const DEFAULT_CORNER_INSET_PX: Vector2i = Vector2i(24, 36)
const DEFAULT_WINDOW_SIZE: Vector2i = Vector2i(360, 480)
const DEFAULT_CORNER_RADIUS: float = 12.0
const DEFAULT_OUTER_INSET_PX: float = 2.0
const DEFAULT_CORNER_SEGMENTS: int = 6
const DEFAULT_TOP_BAR_BOTTOM_Y: float = 26.0
const DEFAULT_BOTTOM_HUD_TOP_Y: float = 388.0
const PASSTHROUGH_SPINE_WIDTH_PX: float = 4.0

# Windows 11 DWM 构建号基线与安全策略常量
const WIN11_MIN_BUILD_NUMBER: int = 22000
const DWM_CORNER_POLICY_POLYGON_12PX: String = "polygon_and_stylebox_12px"
const DWM_FROSTED_POLICY_SHADER_CARD: String = "card_alpha_and_paper_noise_safe"
const DWM_FROSTED_POLICY_HEADLESS: String = "headless_noop"

signal passthrough_mode_changed(battle_passthrough: bool)
signal window_snapped(snapped_pos: Vector2i)
signal tray_visibility_changed(hidden_to_tray: bool)

@export var snap_margin_px: int = DEFAULT_SNAP_MARGIN_PX
@export var save_path: String = DEFAULT_SAVE_PATH
@export var prefer_native_drag: bool = true
@export var battle_passthrough_enabled: bool = false
@export var auto_mount_system_tray: bool = true

var system_tray: SystemTrayScript = null

var _is_manual_dragging: bool = false
var _awaiting_native_drag_end: bool = false
var _native_drag_seen_pressed: bool = false
var _drag_start_mouse_pos: Vector2i = Vector2i.ZERO
var _drag_start_window_pos: Vector2i = Vector2i.ZERO
var _last_applied_position: Vector2i = Vector2i.ZERO
var _saved_pos_before_tray_hide: Vector2i = Vector2i.ZERO
var _hidden_to_tray: bool = false
var _bound_game: Node = null
var _dwm_status: Dictionary = {}
var _current_passthrough_polygon: PackedVector2Array = PackedVector2Array()

func _ready() -> void:
	set_process(true)
	_dwm_status = apply_safe_dwm_policy()
	restore_window_position()
	apply_mouse_passthrough(
		Vector2(float(DEFAULT_WINDOW_SIZE.x), float(DEFAULT_WINDOW_SIZE.y)),
		DEFAULT_TOP_BAR_BOTTOM_Y,
		DEFAULT_BOTTOM_HUD_TOP_Y
	)
	if auto_mount_system_tray and system_tray == null:
		system_tray = SystemTrayScript.new()
		system_tray.name = "SystemTray"
		system_tray.bind_desktop_window(self)
		if _bound_game != null:
			system_tray.bind_game(_bound_game)
		add_child(system_tray)

func _process(_delta: float) -> void:
	if _hidden_to_tray:
		# 双保险：确保隐藏至托盘后才晚绑定的 Game 会话同样进入最小化排空态，杜绝 PresentationBus 积压
		var g: Node = resolve_game_node()
		if g != null and g.has_method("is_window_minimized") and not bool(g.call("is_window_minimized")):
			if g.has_method("set_simulated_minimized"):
				g.call("set_simulated_minimized", true)

	if not _awaiting_native_drag_end:
		return
	var left_pressed: bool = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	if left_pressed:
		_native_drag_seen_pressed = true
		return
	# Win32 原生模态拖拽结束释放鼠标左键后，自动执行贴边/贴角吸附与位置落盘
	if _native_drag_seen_pressed or not left_pressed:
		end_drag()

## 绑定外部 Game 协调器引用（可选，未显式绑定时自动从父窗口 game_ref 或 SceneTree 解析）
func bind_game(p_game: Node) -> void:
	_bound_game = p_game
	if system_tray != null:
		system_tray.bind_game(p_game)
	if _hidden_to_tray and _bound_game != null and _bound_game.has_method("set_simulated_minimized"):
		_bound_game.call("set_simulated_minimized", true)

## 解析关联的 Game 会话节点
func resolve_game_node() -> Node:
	if _bound_game != null:
		return _bound_game
	var parent_node: Node = get_parent()
	if parent_node != null:
		var gref: Variant = parent_node.get("game_ref")
		if gref is Node:
			return gref as Node
	var tree: SceneTree = get_tree()
	if tree != null and tree.root != null:
		var n1: Node = tree.root.get_node_or_null("GameAutoload")
		if n1 != null:
			return n1
		var n2: Node = tree.root.get_node_or_null("Game")
		if n2 != null:
			return n2
	return null

func get_system_tray() -> SystemTrayScript:
	return system_tray

## 判定当前是否处于无窗口 Headless 环境
static func is_headless_display() -> bool:
	return DisplayServer.get_name() == "headless"

## 解析 Windows 版本字符串中的 Build 号（如 "10.0.26200" -> 26200；非数字或非 Windows 返回 0）
static func parse_windows_build_number(version_str: String) -> int:
	if version_str.is_empty():
		return 0
	var parts: PackedStringArray = version_str.split(".")
	if parts.size() >= 3 and parts[2].is_valid_int():
		return int(parts[2])
	for token: String in parts:
		if token.is_valid_int() and int(token) >= 10240:
			return int(token)
	return 0

## 探测 Windows DWM 圆角与系统磨砂（Mica/Acrylic）兼容性，并给出防黑底安全策略
## 说明：在 Win32 + OpenGL Compatibility + borderless + per_pixel_transparency 组合下，
## 强开 OS 级 DWM 系统背板（Mica/Acrylic 或扩展标题栏合成）会覆盖帧缓冲 Alpha 导致整窗变纯黑底；
## 本封装自动识别该风险并锁定「OS 逐像素透明保真 + 多边形圆角穿透 + 卡片级半透明磨砂底纹」安全模式。
static func probe_dwm_capabilities(
	os_name_override: String = "",
	os_version_override: String = "",
	headless_override: int = -1,
	per_pixel_transparent_override: int = -1
) -> Dictionary:
	var headless: bool = is_headless_display() if headless_override < 0 else (headless_override > 0)
	var os_name: String = OS.get_name() if os_name_override.is_empty() else os_name_override
	var os_ver: String = OS.get_version() if os_version_override.is_empty() else os_version_override
	var is_win: bool = (os_name == "Windows")
	var win_build: int = parse_windows_build_number(os_ver) if is_win else 0
	var is_win11_or_newer: bool = is_win and (win_build >= WIN11_MIN_BUILD_NUMBER)

	var per_pixel_trans: bool = true
	if per_pixel_transparent_override >= 0:
		per_pixel_trans = (per_pixel_transparent_override > 0)
	else:
		var allow_pp: bool = bool(ProjectSettings.get_setting("display/window/per_pixel_transparency/allowed", true))
		var win_trans: bool = bool(ProjectSettings.get_setting("display/window/size/transparent", true))
		var vp_trans: bool = bool(ProjectSettings.get_setting("rendering/viewport/transparent_background", true))
		per_pixel_trans = allow_pp and win_trans and vp_trans

	var renderer_method: String = str(ProjectSettings.get_setting("rendering/renderer/rendering_method", "gl_compatibility"))
	var native_hwnd: int = 0
	if not headless and is_win and ClassDB.class_has_method("DisplayServer", "window_get_native_handle"):
		native_hwnd = DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE, DisplayServer.MAIN_WINDOW_ID)

	var os_supports_dwm_api: bool = is_win11_or_newer and not headless and native_hwnd != 0
	# 核心防黑底守卫：无边框逐像素透明模式下绝不启用 OS 级 DWM Backdrop/ExtendToTitle，保持透明通道纯净不黑底
	var prevent_black_bg_guard: bool = per_pixel_trans
	var use_os_dwm_backdrop: bool = os_supports_dwm_api and (not prevent_black_bg_guard)

	return {
		"headless": headless,
		"os_name": os_name,
		"os_version": os_ver,
		"windows_build": win_build,
		"is_windows_11_plus": is_win11_or_newer,
		"renderer_method": renderer_method,
		"native_hwnd_available": native_hwnd != 0,
		"per_pixel_transparency_active": per_pixel_trans,
		"os_dwm_api_capable": os_supports_dwm_api,
		"os_dwm_backdrop_enabled": use_os_dwm_backdrop,
		"prevent_black_bg_guard": prevent_black_bg_guard,
		"corner_policy": DWM_FROSTED_POLICY_HEADLESS if headless else DWM_CORNER_POLICY_POLYGON_12PX,
		"frosted_policy": DWM_FROSTED_POLICY_HEADLESS if headless else DWM_FROSTED_POLICY_SHADER_CARD
	}

## 应用安全窗口透明与 DWM 防黑底策略（Headless 下安全无操作返回状态字典）
func apply_safe_dwm_policy() -> Dictionary:
	var caps: Dictionary = probe_dwm_capabilities()
	_dwm_status = caps
	if bool(caps.get("headless", true)):
		return caps

	if ClassDB.class_has_method("DisplayServer", "window_set_flag"):
		# 确保无边框与逐像素透明标志位稳固，同时显式关闭 EXTEND_TO_TITLE 防止 Windows DWM 接管背景造成黑底
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true, DisplayServer.MAIN_WINDOW_ID)
		if bool(caps.get("per_pixel_transparency_active", true)):
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_TRANSPARENT, true, DisplayServer.MAIN_WINDOW_ID)
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_EXTEND_TO_TITLE, false, DisplayServer.MAIN_WINDOW_ID)
	return caps

func get_dwm_status() -> Dictionary:
	if _dwm_status.is_empty():
		_dwm_status = probe_dwm_capabilities()
	return _dwm_status

## 获取当前活动屏幕可用工作区（Headless 下返回标准 1920×1040 兜底工作区供逻辑验证）
static func get_active_usable_rect() -> Rect2i:
	if is_headless_display():
		return Rect2i(Vector2i(0, 0), Vector2i(1920, 1040))
	var screen_idx: int = DisplayServer.window_get_current_screen(DisplayServer.MAIN_WINDOW_ID)
	var rect: Rect2i = DisplayServer.screen_get_usable_rect(screen_idx)
	if rect.size.x <= 0 or rect.size.y <= 0:
		return Rect2i(Vector2i(0, 0), Vector2i(1920, 1040))
	return rect

## 获取当前窗口像素尺寸（Headless 或异常尺寸下回退 360×480）
static func get_active_window_size() -> Vector2i:
	if is_headless_display():
		return DEFAULT_WINDOW_SIZE
	var win_size: Vector2i = DisplayServer.window_get_size(DisplayServer.MAIN_WINDOW_ID)
	if win_size.x <= 0 or win_size.y <= 0:
		return DEFAULT_WINDOW_SIZE
	return win_size

## 将窗口坐标夹紧至可见屏幕工作区内（防止拔插副屏或改分辨率后窗口丢失在屏幕外）
static func clamp_position_to_screen(pos: Vector2i, win_size: Vector2i, usable_rect: Rect2i) -> Vector2i:
	var min_x: int = usable_rect.position.x
	var min_y: int = usable_rect.position.y
	var max_x: int = maxi(min_x, usable_rect.position.x + usable_rect.size.x - win_size.x)
	var max_y: int = maxi(min_y, usable_rect.position.y + usable_rect.size.y - win_size.y)
	var clamped_x: int = clampi(pos.x, min_x, max_x)
	var clamped_y: int = clampi(pos.y, min_y, max_y)
	return Vector2i(clamped_x, clamped_y)

## 计算边缘与四角磁吸坐标（先执行越界夹紧，再判定四边/四角吸附阈值）
static func compute_snapped_position(
	pos: Vector2i,
	win_size: Vector2i,
	usable_rect: Rect2i,
	snap_threshold: int = DEFAULT_SNAP_MARGIN_PX
) -> Vector2i:
	var clamped: Vector2i = clamp_position_to_screen(pos, win_size, usable_rect)
	var threshold: int = maxi(0, snap_threshold)

	var left_edge: int = usable_rect.position.x
	var right_edge: int = maxi(left_edge, usable_rect.position.x + usable_rect.size.x - win_size.x)
	var top_edge: int = usable_rect.position.y
	var bottom_edge: int = maxi(top_edge, usable_rect.position.y + usable_rect.size.y - win_size.y)

	var final_x: int = clamped.x
	var final_y: int = clamped.y

	var dist_left: int = absi(clamped.x - left_edge)
	var dist_right: int = absi(right_edge - clamped.x)
	if dist_left <= threshold and dist_left <= dist_right:
		final_x = left_edge
	elif dist_right <= threshold:
		final_x = right_edge

	var dist_top: int = absi(clamped.y - top_edge)
	var dist_bottom: int = absi(bottom_edge - clamped.y)
	if dist_top <= threshold and dist_top <= dist_bottom:
		final_y = top_edge
	elif dist_bottom <= threshold:
		final_y = bottom_edge

	return Vector2i(final_x, final_y)

## 计算首次启动默认右下角常驻坐标
static func compute_default_corner_position(
	win_size: Vector2i,
	usable_rect: Rect2i,
	inset: Vector2i = DEFAULT_CORNER_INSET_PX
) -> Vector2i:
	var raw_pos: Vector2i = Vector2i(
		usable_rect.position.x + usable_rect.size.x - win_size.x - inset.x,
		usable_rect.position.y + usable_rect.size.y - win_size.y - inset.y
	)
	return clamp_position_to_screen(raw_pos, win_size, usable_rect)

## 原子化写入窗口位置 JSON（符合总纲 §4.7：带 version 字段，先写 .tmp 再替换正式文件）
static func save_position_to_path(pos: Vector2i, target_path: String = DEFAULT_SAVE_PATH) -> bool:
	if target_path.is_empty():
		return false

	var tmp_path: String = target_path + ".tmp"
	var file: FileAccess = FileAccess.open(tmp_path, FileAccess.WRITE)
	if file == null:
		return false

	var payload: Dictionary = {
		"version": SAVE_FORMAT_VERSION,
		"x": pos.x,
		"y": pos.y
	}
	file.store_string(JSON.stringify(payload, "\t"))
	file.flush()
	file = null

	var abs_tmp: String = ProjectSettings.globalize_path(tmp_path)
	var abs_target: String = ProjectSettings.globalize_path(target_path)
	if FileAccess.file_exists(target_path):
		var rm_err: Error = DirAccess.remove_absolute(abs_target)
		if rm_err != OK:
			return false

	var rename_err: Error = DirAccess.rename_absolute(abs_tmp, abs_target)
	return rename_err == OK

## 读取持久化的窗口坐标并强制夹紧至当前可见屏幕范围；缺失或损坏时回退至默认右下角
static func load_position_from_path(
	target_path: String,
	win_size: Vector2i,
	usable_rect: Rect2i,
	fallback_inset: Vector2i = DEFAULT_CORNER_INSET_PX
) -> Vector2i:
	if not target_path.is_empty() and FileAccess.file_exists(target_path):
		var file: FileAccess = FileAccess.open(target_path, FileAccess.READ)
		if file != null:
			var json_text: String = file.get_as_text()
			file = null
			var parser: JSON = JSON.new()
			if parser.parse(json_text) == OK and typeof(parser.data) == TYPE_DICTIONARY:
				var dict_data: Dictionary = parser.data as Dictionary
				var ver: int = int(dict_data.get("version", 1))
				if ver >= 1 and dict_data.has("x") and dict_data.has("y"):
					var raw_saved: Vector2i = Vector2i(
						int(dict_data["x"]),
						int(dict_data["y"])
					)
					return clamp_position_to_screen(raw_saved, win_size, usable_rect)

	return compute_default_corner_position(win_size, usable_rect, fallback_inset)

## 生成圆角矩形交互区多边形（圆角外透明区点击直接穿透至系统桌面）
static func build_rounded_rect_polygon(
	rect: Rect2,
	radius: float = DEFAULT_CORNER_RADIUS,
	corner_segments: int = DEFAULT_CORNER_SEGMENTS
) -> PackedVector2Array:
	var poly: PackedVector2Array = PackedVector2Array()
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return poly

	var max_r: float = minf(rect.size.x, rect.size.y) * 0.5
	var r: float = clampf(radius, 0.0, max_r)
	var segs: int = maxi(1, corner_segments)

	if r <= 0.01:
		poly.push_back(rect.position)
		poly.push_back(Vector2(rect.position.x + rect.size.x, rect.position.y))
		poly.push_back(rect.position + rect.size)
		poly.push_back(Vector2(rect.position.x, rect.position.y + rect.size.y))
		return poly

	var centers: Array[Vector2] = [
		Vector2(rect.position.x + rect.size.x - r, rect.position.y + r),
		Vector2(rect.position.x + rect.size.x - r, rect.position.y + rect.size.y - r),
		Vector2(rect.position.x + r, rect.position.y + rect.size.y - r),
		Vector2(rect.position.x + r, rect.position.y + r)
	]
	var start_angles: Array[float] = [-PI * 0.5, 0.0, PI * 0.5, PI]

	for corner_idx: int in range(4):
		var c: Vector2 = centers[corner_idx]
		var a0: float = start_angles[corner_idx]
		for step_idx: int in range(segs + 1):
			var t: float = float(step_idx) / float(segs)
			var angle: float = a0 + t * (PI * 0.5)
			poly.push_back(c + Vector2(cos(angle), sin(angle)) * r)

	return poly

## 生成「标题栏 + 底部 HUD/装备槽」连通凹多边形，使中部非交互区点击直接穿透桌面
static func build_split_interactive_polygon(
	viewport_size: Vector2,
	top_bar_bottom_y: float = DEFAULT_TOP_BAR_BOTTOM_Y,
	bottom_hud_top_y: float = DEFAULT_BOTTOM_HUD_TOP_Y,
	inset_px: float = DEFAULT_OUTER_INSET_PX,
	spine_width_px: float = PASSTHROUGH_SPINE_WIDTH_PX
) -> PackedVector2Array:
	var left_x: float = clampf(inset_px, 0.0, viewport_size.x * 0.25)
	var right_x: float = maxf(left_x + 8.0, viewport_size.x - left_x)
	var top_y: float = clampf(inset_px, 0.0, viewport_size.y * 0.25)
	var bottom_y: float = maxf(top_y + 16.0, viewport_size.y - top_y)

	var top_band_y: float = clampf(top_bar_bottom_y, top_y + 4.0, bottom_y - 12.0)
	var bottom_band_y: float = clampf(bottom_hud_top_y, top_band_y + 4.0, bottom_y - 4.0)
	var spine_x: float = clampf(left_x + maxf(1.0, spine_width_px), left_x + 1.0, right_x - 4.0)

	var poly: PackedVector2Array = PackedVector2Array()
	poly.push_back(Vector2(left_x, top_y))
	poly.push_back(Vector2(right_x, top_y))
	poly.push_back(Vector2(right_x, top_band_y))
	poly.push_back(Vector2(spine_x, top_band_y))
	poly.push_back(Vector2(spine_x, bottom_band_y))
	poly.push_back(Vector2(right_x, bottom_band_y))
	poly.push_back(Vector2(right_x, bottom_y))
	poly.push_back(Vector2(left_x, bottom_y))
	return poly

## 恢复并应用窗口位置
func restore_window_position() -> Vector2i:
	var usable_rect: Rect2i = get_active_usable_rect()
	var win_size: Vector2i = get_active_window_size()
	var restored_pos: Vector2i = load_position_from_path(
		save_path,
		win_size,
		usable_rect,
		DEFAULT_CORNER_INSET_PX
	)
	_apply_os_window_position(restored_pos)
	return restored_pos

## 重置小窗位置回当前屏幕默认右下角并原子化落盘
func reset_to_default_corner(inset: Vector2i = DEFAULT_CORNER_INSET_PX) -> Vector2i:
	var usable_rect: Rect2i = get_active_usable_rect()
	var win_size: Vector2i = get_active_window_size()
	var default_pos: Vector2i = compute_default_corner_position(win_size, usable_rect, inset)
	_apply_os_window_position(default_pos)
	save_position_to_path(default_pos, save_path)
	window_snapped.emit(default_pos)
	return default_pos

## 设置窗口是否隐藏至系统托盘（隐藏期间联动 Game.set_simulated_minimized 持续排空 PresentationBus，满足 02 Q10）
func set_hidden_to_tray(hidden: bool) -> void:
	if _hidden_to_tray == hidden:
		return
	if hidden:
		_saved_pos_before_tray_hide = get_current_window_position()
	_hidden_to_tray = hidden

	var parent_ctrl: Control = get_parent() as Control
	if parent_ctrl != null and parent_ctrl != self:
		parent_ctrl.visible = not hidden

	var g: Node = resolve_game_node()
	if g != null and g.has_method("set_simulated_minimized"):
		g.call("set_simulated_minimized", hidden)

	if not is_headless_display():
		if hidden:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED, DisplayServer.MAIN_WINDOW_ID)
		else:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED, DisplayServer.MAIN_WINDOW_ID)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true, DisplayServer.MAIN_WINDOW_ID)
			apply_safe_dwm_policy()
			_apply_os_window_position(_saved_pos_before_tray_hide)
			apply_mouse_passthrough(
				Vector2(float(DEFAULT_WINDOW_SIZE.x), float(DEFAULT_WINDOW_SIZE.y)),
				DEFAULT_TOP_BAR_BOTTOM_Y,
				DEFAULT_BOTTOM_HUD_TOP_Y
			)
			if ClassDB.class_has_method("DisplayServer", "window_move_to_foreground"):
				DisplayServer.window_move_to_foreground(DisplayServer.MAIN_WINDOW_ID)

	tray_visibility_changed.emit(_hidden_to_tray)

## 一键切换隐藏至系统托盘 / 唤醒显示
func toggle_hidden_to_tray() -> bool:
	set_hidden_to_tray(not _hidden_to_tray)
	return _hidden_to_tray

func is_hidden_to_tray() -> bool:
	return _hidden_to_tray

## 开始窗口拖拽：优先走 V-01 验证通过的 DisplayServer.window_start_drag，脚本偏移作兜底
func begin_drag(mouse_screen_pos: Vector2i) -> void:
	if _can_use_native_drag():
		_is_manual_dragging = false
		_awaiting_native_drag_end = true
		_native_drag_seen_pressed = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
		DisplayServer.window_start_drag(DisplayServer.MAIN_WINDOW_ID)
		return

	_awaiting_native_drag_end = false
	_is_manual_dragging = true
	_drag_start_mouse_pos = mouse_screen_pos
	_drag_start_window_pos = get_current_window_position()

## 脚本兜底拖拽移动更新
func update_drag(mouse_screen_pos: Vector2i) -> Vector2i:
	if not _is_manual_dragging:
		return get_current_window_position()
	var offset: Vector2i = mouse_screen_pos - _drag_start_mouse_pos
	var raw_pos: Vector2i = _drag_start_window_pos + offset
	var clamped_pos: Vector2i = clamp_position_to_screen(
		raw_pos,
		get_active_window_size(),
		get_active_usable_rect()
	)
	_apply_os_window_position(clamped_pos)
	return clamped_pos

## 结束拖拽：执行四角/贴边吸附并原子落盘
func end_drag() -> Vector2i:
	if not _is_manual_dragging and not _awaiting_native_drag_end:
		return get_current_window_position()

	_is_manual_dragging = false
	_awaiting_native_drag_end = false
	_native_drag_seen_pressed = false

	var cur_pos: Vector2i = get_current_window_position()
	var snapped_pos: Vector2i = compute_snapped_position(
		cur_pos,
		get_active_window_size(),
		get_active_usable_rect(),
		snap_margin_px
	)
	_apply_os_window_position(snapped_pos)
	save_position_to_path(snapped_pos, save_path)
	window_snapped.emit(snapped_pos)
	return snapped_pos

func is_dragging() -> bool:
	return _is_manual_dragging or _awaiting_native_drag_end

func get_current_window_position() -> Vector2i:
	if is_headless_display():
		return _last_applied_position
	return DisplayServer.window_get_position(DisplayServer.MAIN_WINDOW_ID)

func get_current_passthrough_polygon() -> PackedVector2Array:
	return _current_passthrough_polygon

## 切换中部战场鼠标穿透模式并立即刷新 OS 穿透多边形
func set_battle_passthrough_enabled(
	enabled: bool,
	viewport_size: Vector2 = Vector2(float(DEFAULT_WINDOW_SIZE.x), float(DEFAULT_WINDOW_SIZE.y)),
	top_bar_bottom_y: float = DEFAULT_TOP_BAR_BOTTOM_Y,
	bottom_hud_top_y: float = DEFAULT_BOTTOM_HUD_TOP_Y
) -> PackedVector2Array:
	battle_passthrough_enabled = enabled
	var poly: PackedVector2Array = apply_mouse_passthrough(
		viewport_size,
		top_bar_bottom_y,
		bottom_hud_top_y
	)
	passthrough_mode_changed.emit(battle_passthrough_enabled)
	return poly

## 计算并向 DisplayServer 下发鼠标穿透多边形
func apply_mouse_passthrough(
	viewport_size: Vector2,
	top_bar_bottom_y: float = DEFAULT_TOP_BAR_BOTTOM_Y,
	bottom_hud_top_y: float = DEFAULT_BOTTOM_HUD_TOP_Y
) -> PackedVector2Array:
	if battle_passthrough_enabled:
		_current_passthrough_polygon = build_split_interactive_polygon(
			viewport_size,
			top_bar_bottom_y,
			bottom_hud_top_y,
			DEFAULT_OUTER_INSET_PX,
			PASSTHROUGH_SPINE_WIDTH_PX
		)
	else:
		var inner_rect: Rect2 = Rect2(
			Vector2(DEFAULT_OUTER_INSET_PX, DEFAULT_OUTER_INSET_PX),
			Vector2(
				maxf(1.0, viewport_size.x - DEFAULT_OUTER_INSET_PX * 2.0),
				maxf(1.0, viewport_size.y - DEFAULT_OUTER_INSET_PX * 2.0)
			)
		)
		_current_passthrough_polygon = build_rounded_rect_polygon(
			inner_rect,
			DEFAULT_CORNER_RADIUS,
			DEFAULT_CORNER_SEGMENTS
		)

	if not is_headless_display() and ClassDB.class_has_method("DisplayServer", "window_set_mouse_passthrough"):
		DisplayServer.window_set_mouse_passthrough(_current_passthrough_polygon, DisplayServer.MAIN_WINDOW_ID)

	return _current_passthrough_polygon

func _can_use_native_drag() -> bool:
	if not prefer_native_drag or is_headless_display():
		return false
	return ClassDB.class_has_method("DisplayServer", "window_start_drag")

func _apply_os_window_position(pos: Vector2i) -> void:
	_last_applied_position = pos
	if not is_headless_display():
		DisplayServer.window_set_position(pos, DisplayServer.MAIN_WINDOW_ID)
