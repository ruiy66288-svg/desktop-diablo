class_name DesktopWindow extends Control

## 桌面常驻无边框小窗平台控制器 (依据《02_系统架构与数值_v6.md》§3.3、《03_美术风格圣经_v1.0.md》§02.6 与 WP-07)
## 职责：原生/脚本兜底拖拽、四角与边缘吸附、带 version 原子持久化位置记忆（越界自动拉回）、鼠标穿透多边形
## 铁律：100% 显式静态类型，零 SimState 写入，零硬编码未封装魔法数

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

signal passthrough_mode_changed(battle_passthrough: bool)
signal window_snapped(snapped_pos: Vector2i)

@export var snap_margin_px: int = DEFAULT_SNAP_MARGIN_PX
@export var save_path: String = DEFAULT_SAVE_PATH
@export var prefer_native_drag: bool = true
@export var battle_passthrough_enabled: bool = false

var _is_manual_dragging: bool = false
var _awaiting_native_drag_end: bool = false
var _native_drag_seen_pressed: bool = false
var _drag_start_mouse_pos: Vector2i = Vector2i.ZERO
var _drag_start_window_pos: Vector2i = Vector2i.ZERO
var _last_applied_position: Vector2i = Vector2i.ZERO
var _current_passthrough_polygon: PackedVector2Array = PackedVector2Array()

func _ready() -> void:
	set_process(true)
	restore_window_position()
	apply_mouse_passthrough(
		Vector2(float(DEFAULT_WINDOW_SIZE.x), float(DEFAULT_WINDOW_SIZE.y)),
		DEFAULT_TOP_BAR_BOTTOM_Y,
		DEFAULT_BOTTOM_HUD_TOP_Y
	)

func _process(_delta: float) -> void:
	if not _awaiting_native_drag_end:
		return
	var left_pressed: bool = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	if left_pressed:
		_native_drag_seen_pressed = true
		return
	# Win32 原生模态拖拽结束释放鼠标左键后，自动执行贴边/贴角吸附与位置落盘
	if _native_drag_seen_pressed or not left_pressed:
		end_drag()

## 判定当前是否处于无窗口 Headless 环境
static func is_headless_display() -> bool:
	return DisplayServer.get_name() == "headless"

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
