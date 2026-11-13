class_name SystemTray extends Node

## Windows 系统托盘常驻控制器 (依据《02_系统架构与数值_v6.md》§3.3、Q10、《03_美术风格圣经_v1.0.md》§02.6 与 WP-P15-FONT-PLAT)
## 职责：基于 Godot 4 原生 StatusIndicator + PopupMenu 提供木刻徽章托盘图标、左键一键显隐、右键四项快捷菜单与退出前强制存档
## 铁律：100% 显式静态类型，零隐式推导，零 SimState 直接写入，Headless 环境零报错降级

const BADGE_DEFAULT_SIZE_PX: int = 32
const MASTER_AUDIO_BUS_IDX: int = 0

const MENU_ID_TOGGLE_WINDOW: int = 0
const MENU_ID_TOGGLE_MUTE: int = 1
const MENU_ID_RESET_CORNER: int = 2
const MENU_ID_SAVE_AND_QUIT: int = 3

const LABEL_TOGGLE_WINDOW: String = "显示 / 隐藏小窗"
const LABEL_TOGGLE_MUTE: String = "静音 / 开启音效"
const LABEL_RESET_CORNER: String = "重置回屏幕右下角"
const LABEL_SAVE_AND_QUIT: String = "立即存档并退出"

const TOOLTIP_VISIBLE: String = "桌面破坏神 — 运行中（左键隐藏至托盘）"
const TOOLTIP_HIDDEN: String = "桌面破坏神 — 后台挂机中（左键恢复小窗）"

# 冻结色板（《03_美术风格圣经_v1.0.md》与《04_美术资产管线_v1.1.md》§1.2）
const COLOR_INK_BLACK: Color = Color(0.0862745, 0.0862745, 0.109804, 1.0) # #16161C
const COLOR_BONE_WHITE: Color = Color(0.909804, 0.862745, 0.752941, 1.0) # #E8DCC0
const COLOR_OLD_GOLD: Color = Color(0.788235, 0.627451, 0.305882, 1.0)   # #C9A04E
const COLOR_BRIGHT_GOLD: Color = Color(0.913725, 0.768627, 0.415686, 1.0) # #E9C46A

signal window_visibility_toggled(hidden_to_tray: bool)
signal mute_toggled(muted: bool)
signal reset_corner_triggered(snapped_pos: Vector2i)
signal save_and_quit_triggered(save_err: Error)

var status_indicator: StatusIndicator = null
var popup_menu: PopupMenu = null
var badge_texture: ImageTexture = null

var _desktop_window: Node = null
var _bound_game: Node = null
var _audio_muted: bool = false
var _suppress_quit_for_test: bool = false
var _save_override_path: String = ""

func _ready() -> void:
	_setup_tray_nodes()
	_sync_initial_audio_state()
	_refresh_tray_state()

func _exit_tree() -> void:
	if status_indicator != null:
		status_indicator.visible = false

## 绑定宿主 DesktopWindow 控制器
func bind_desktop_window(p_desktop_window: Node) -> void:
	_desktop_window = p_desktop_window
	_refresh_tray_state()

## 绑定外部或全局 Game 协调器（供「立即存档并退出」及隐藏态排空联动使用）
func bind_game(p_game: Node) -> void:
	_bound_game = p_game

## 测试辅助：拦截退出时的 SceneTree.quit 并允许指定测试存档路径
func configure_for_test(suppress_quit: bool, test_save_path: String = "") -> void:
	_suppress_quit_for_test = suppress_quit
	_save_override_path = test_save_path

## 程序化生成「骨白 + 旧金」木刻盾章托盘图标（零外部图片依赖，100% 原创几何刻痕）
static func build_woodcut_badge_texture(size_px: int = BADGE_DEFAULT_SIZE_PX) -> ImageTexture:
	var dim: int = maxi(16, size_px)
	var img: Image = Image.create(dim, dim, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.0, 0.0, 0.0, 0.0))

	var center: float = (float(dim) - 1.0) * 0.5
	var corner_cut: float = maxf(3.0, float(dim) * 0.16)
	var outer_margin: int = 1
	var inner_frame: int = maxi(3, int(round(float(dim) * 0.125)))

	for y: int in range(dim):
		for x: int in range(dim):
			var dx_edge: int = mini(x - outer_margin, (dim - 1 - outer_margin) - x)
			var dy_edge: int = mini(y - outer_margin, (dim - 1 - outer_margin) - y)
			if dx_edge < 0 or dy_edge < 0:
				continue
			# 八角切角木刻封蜡印章外轮廓（四角透明穿透）
			if float(dx_edge + dy_edge) < corner_cut - 0.5:
				continue

			var px_color: Color = COLOR_INK_BLACK
			var is_outer_rim: bool = (dx_edge == 0 or dy_edge == 0 or float(dx_edge + dy_edge) < corner_cut + 0.6)
			var is_inner_rim: bool = (
				(x == inner_frame or x == dim - 1 - inner_frame) and (y >= inner_frame and y <= dim - 1 - inner_frame)
			) or (
				(y == inner_frame or y == dim - 1 - inner_frame) and (x >= inner_frame and x <= dim - 1 - inner_frame)
			)

			if is_outer_rim:
				px_color = COLOR_BONE_WHITE
			elif is_inner_rim:
				px_color = COLOR_OLD_GOLD
			else:
				# 粗刀木刻斜排线暗纹底（仅偶发刻痕，保持剪影干净）
				if ((x + y) % 6 == 0) and (x > inner_frame + 1 and x < dim - 2 - inner_frame) and (y > dim / 2):
					px_color = Color(0.145, 0.141, 0.176, 1.0)

			img.set_pixel(x, y, px_color)

	# 中央骨白断债巨剑（纵轴剑脊 + 剑尖 + 护手）与旧金债契天平横梁
	var mid_x: int = dim / 2
	var top_tip_y: int = maxi(4, int(round(float(dim) * 0.19)))
	var pommel_y: int = mini(dim - 5, int(round(float(dim) * 0.81)))
	var guard_y: int = int(round(float(dim) * 0.41))
	var guard_half_w: int = maxi(4, int(round(float(dim) * 0.25)))

	# 剑身与剑脊（骨白）
	for by: int in range(top_tip_y, pommel_y + 1):
		var half_blade: int = 1 if (by > top_tip_y + 1 and by < pommel_y - 2) else 0
		for bx: int in range(mid_x - half_blade, mid_x + half_blade + 1):
			if bx >= 0 and bx < dim and by >= 0 and by < dim:
				img.set_pixel(bx, by, COLOR_BONE_WHITE)

	# 剑格 / 债契天平横梁（亮镀金 + 旧金）
	for gx: int in range(mid_x - guard_half_w, mid_x + guard_half_w + 1):
		if gx >= 0 and gx < dim:
			img.set_pixel(gx, guard_y, COLOR_BRIGHT_GOLD)
			if guard_y + 1 < dim:
				img.set_pixel(gx, guard_y + 1, COLOR_OLD_GOLD)

	# 左右天平垂链与金盘（旧金点缀）
	var pan_left_x: int = mid_x - guard_half_w + 1
	var pan_right_x: int = mid_x + guard_half_w - 1
	var pan_drop: int = maxi(3, int(round(float(dim) * 0.18)))
	for cy: int in range(guard_y + 2, mini(dim - 5, guard_y + 2 + pan_drop)):
		img.set_pixel(pan_left_x, cy, COLOR_OLD_GOLD)
		img.set_pixel(pan_right_x, cy, COLOR_OLD_GOLD)
	var pan_y: int = mini(dim - 5, guard_y + 2 + pan_drop)
	for dx: int in range(-1, 2):
		if pan_left_x + dx >= 2 and pan_left_x + dx < dim - 2:
			img.set_pixel(pan_left_x + dx, pan_y, COLOR_BRIGHT_GOLD)
		if pan_right_x + dx >= 2 and pan_right_x + dx < dim - 2:
			img.set_pixel(pan_right_x + dx, pan_y, COLOR_BRIGHT_GOLD)

	# 剑首金印（亮镀金）
	for py: int in range(maxi(2, top_tip_y - 1), top_tip_y + 1):
		img.set_pixel(mid_x, py, COLOR_BRIGHT_GOLD)

	return ImageTexture.create_from_image(img)

func _setup_tray_nodes() -> void:
	if badge_texture == null:
		badge_texture = build_woodcut_badge_texture(BADGE_DEFAULT_SIZE_PX)

	if popup_menu == null:
		popup_menu = PopupMenu.new()
		popup_menu.name = "TrayPopupMenu"
		popup_menu.add_item(LABEL_TOGGLE_WINDOW, MENU_ID_TOGGLE_WINDOW)
		popup_menu.add_check_item(LABEL_TOGGLE_MUTE, MENU_ID_TOGGLE_MUTE)
		popup_menu.add_separator()
		popup_menu.add_item(LABEL_RESET_CORNER, MENU_ID_RESET_CORNER)
		popup_menu.add_item(LABEL_SAVE_AND_QUIT, MENU_ID_SAVE_AND_QUIT)
		popup_menu.id_pressed.connect(_on_popup_menu_id_pressed)
		add_child(popup_menu)

	if status_indicator == null:
		status_indicator = StatusIndicator.new()
		status_indicator.name = "TrayStatusIndicator"
		status_indicator.icon = badge_texture
		status_indicator.tooltip = TOOLTIP_VISIBLE
		status_indicator.visible = DisplayServer.get_name() != "headless"
		status_indicator.pressed.connect(_on_status_indicator_pressed)
		add_child(status_indicator)
		status_indicator.menu = status_indicator.get_path_to(popup_menu)

func _sync_initial_audio_state() -> void:
	if AudioServer.get_bus_count() > MASTER_AUDIO_BUS_IDX:
		_audio_muted = AudioServer.is_bus_mute(MASTER_AUDIO_BUS_IDX)
	_update_mute_menu_check()

## 处理原生托盘图标鼠标点击：左键单击一键切换小窗显示/隐藏
func handle_tray_pressed(mouse_button: int, _mouse_position: Vector2i = Vector2i.ZERO) -> void:
	if mouse_button == MOUSE_BUTTON_LEFT:
		toggle_window_visibility()

func _on_status_indicator_pressed(mouse_button: int, mouse_position: Vector2i) -> void:
	handle_tray_pressed(mouse_button, mouse_position)

func _on_popup_menu_id_pressed(menu_id: int) -> void:
	activate_menu_item(menu_id)

## 触发右键菜单指定动作（同时供系统回调与自动化测试直接驱动）
func activate_menu_item(menu_id: int) -> void:
	match menu_id:
		MENU_ID_TOGGLE_WINDOW:
			toggle_window_visibility()
		MENU_ID_TOGGLE_MUTE:
			toggle_audio_mute()
		MENU_ID_RESET_CORNER:
			reset_window_to_corner()
		MENU_ID_SAVE_AND_QUIT:
			save_and_quit()

## 一键切换窗口显示 / 隐藏至托盘
func toggle_window_visibility() -> bool:
	var target_dw: Node = _resolve_desktop_window()
	if target_dw != null and target_dw.has_method("toggle_hidden_to_tray"):
		var now_hidden: bool = bool(target_dw.call("toggle_hidden_to_tray"))
		_refresh_tray_state()
		window_visibility_toggled.emit(now_hidden)
		return now_hidden
	return false

## 查询当前是否已隐藏至系统托盘
func is_window_hidden_to_tray() -> bool:
	var target_dw: Node = _resolve_desktop_window()
	if target_dw != null and target_dw.has_method("is_hidden_to_tray"):
		return bool(target_dw.call("is_hidden_to_tray"))
	return false

## 切换全局静音 / 开启音效（同步 AudioServer Master 总线与主界面 SfxMixer）
func toggle_audio_mute() -> bool:
	return set_audio_muted(not _audio_muted)

func set_audio_muted(muted: bool) -> bool:
	_audio_muted = muted
	if AudioServer.get_bus_count() > MASTER_AUDIO_BUS_IDX:
		AudioServer.set_bus_mute(MASTER_AUDIO_BUS_IDX, _audio_muted)

	var host_win: Node = _resolve_host_main_window()
	if host_win != null:
		var mixer_variant: Variant = host_win.get("sfx_mixer")
		if mixer_variant is Object and (mixer_variant as Object).has_method("set_muted"):
			(mixer_variant as Object).call("set_muted", _audio_muted)

	_update_mute_menu_check()
	mute_toggled.emit(_audio_muted)
	return _audio_muted

func is_audio_muted() -> bool:
	return _audio_muted

## 重置小窗回当前屏幕工作区默认右下角，若处于隐藏态则一并唤醒显示
func reset_window_to_corner() -> Vector2i:
	var target_dw: Node = _resolve_desktop_window()
	var snapped_pos: Vector2i = Vector2i.ZERO
	if target_dw != null:
		if target_dw.has_method("is_hidden_to_tray") and bool(target_dw.call("is_hidden_to_tray")):
			target_dw.call("set_hidden_to_tray", false)
		if target_dw.has_method("reset_to_default_corner"):
			snapped_pos = target_dw.call("reset_to_default_corner") as Vector2i
	_refresh_tray_state()
	reset_corner_triggered.emit(snapped_pos)
	return snapped_pos

## 立即原子化保存当前游戏存档并安全退出进程
func save_and_quit() -> Error:
	var save_err: Error = ERR_UNCONFIGURED
	var game_node: Node = _resolve_game_node()
	if game_node != null and game_node.has_method("save_current_game"):
		if _save_override_path.is_empty():
			save_err = int(game_node.call("save_current_game")) as Error
		else:
			save_err = int(game_node.call("save_current_game", _save_override_path)) as Error

	if status_indicator != null:
		status_indicator.visible = false

	save_and_quit_triggered.emit(save_err)

	if not _suppress_quit_for_test and get_tree() != null:
		get_tree().quit(0)
	return save_err

func get_menu_item_texts() -> Array[String]:
	var texts: Array[String] = []
	if popup_menu == null:
		return texts
	for idx: int in range(popup_menu.item_count):
		if not popup_menu.is_item_separator(idx):
			texts.append(popup_menu.get_item_text(idx))
	return texts

func _refresh_tray_state() -> void:
	if status_indicator == null:
		return
	var hidden: bool = is_window_hidden_to_tray()
	status_indicator.tooltip = TOOLTIP_HIDDEN if hidden else TOOLTIP_VISIBLE

func _update_mute_menu_check() -> void:
	if popup_menu == null:
		return
	var mute_idx: int = popup_menu.get_item_index(MENU_ID_TOGGLE_MUTE)
	if mute_idx >= 0:
		popup_menu.set_item_checked(mute_idx, _audio_muted)

func _resolve_desktop_window() -> Node:
	if _desktop_window != null:
		return _desktop_window
	var p: Node = get_parent()
	if p != null and p.has_method("reset_to_default_corner"):
		return p
	return null

func _resolve_host_main_window() -> Node:
	var dw: Node = _resolve_desktop_window()
	if dw != null and dw.get_parent() != null:
		return dw.get_parent()
	return null

func _resolve_game_node() -> Node:
	if _bound_game != null:
		return _bound_game
	var dw: Node = _resolve_desktop_window()
	if dw != null and dw.has_method("resolve_game_node"):
		var resolved_from_dw: Variant = dw.call("resolve_game_node")
		if resolved_from_dw is Node:
			return resolved_from_dw as Node
	var host_win: Node = _resolve_host_main_window()
	if host_win != null:
		var gref: Variant = host_win.get("game_ref")
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
