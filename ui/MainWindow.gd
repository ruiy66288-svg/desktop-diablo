class_name MainWindow extends Control

## 《桌面破坏神》360×480 桌面常驻小窗与极简 HUD 主界面 (依据《03_美术风格圣经_v1.0.md》§01–§03、《02_系统架构与数值_v6.md》§3.3、§9.1 与 WP-07)
## 铁律：
## 1. 100% 显式静态类型，零隐式类型推导
## 2. 严格只读访问 SimState；一切修改通过 Game.submit_command 走 Command 队列
## 3. 100% 纯代码 StyleBoxFlat 与程序化版画绘制，零 AI UI 图片，严守冻结 HEX 色板

const GameScript = preload("res://autoload/Game.gd")
const SimStateScript = preload("res://simulation/SimState.gd")
const SimEventScript = preload("res://simulation/events/SimEvent.gd")
const ItemInstanceScript = preload("res://simulation/loot/ItemInstance.gd")
const NumScript = preload("res://core/num/Num.gd")
const DesktopWindowScript = preload("res://platform/DesktopWindow.gd")
const ThemePaletteScript = preload("res://ui/ThemePalette.gd")
const MonsterCardViewScript = preload("res://ui/MonsterCardView.gd")
const EquipSlotViewScript = preload("res://ui/EquipSlotView.gd")
const LootFountainScript = preload("res://presentation/loot/LootFountain.gd")
const FloatingTextLayerScript = preload("res://presentation/battle/FloatingTextLayer.gd")
const VfxManagerScript = preload("res://presentation/vfx/VfxManager.gd")
const SfxMixerScript = preload("res://presentation/audio/SfxMixer.gd")

const WINDOW_WIDTH: float = 360.0
const WINDOW_HEIGHT: float = 480.0
const TITLE_BAR_HEIGHT: float = 24.0
const HEADER_TOP_Y: float = 24.0
const HEADER_HEIGHT: float = 40.0
const BATTLE_TOP_Y: float = 64.0
const BATTLE_BOTTOM_Y: float = 324.0
const LOOT_FLOOR_TOP_Y: float = 324.0
const HUD_TOP_Y: float = 392.0
const HUD_HEIGHT: float = 28.0
const EQUIP_TOP_Y: float = 424.0

const MAIN_CARD_POS: Vector2 = Vector2(24.0, 84.0)
const MAIN_CARD_SIZE: Vector2 = Vector2(176.0, 220.0)
const BOSS_CARD_POS: Vector2 = Vector2(76.0, 64.0)
const BOSS_CARD_SIZE: Vector2 = Vector2(208.0, 260.0)
const QUEUE_CARD_1_POS: Vector2 = Vector2(252.0, 94.0)
const QUEUE_CARD_2_POS: Vector2 = Vector2(252.0, 198.0)
const QUEUE_CARD_SIZE: Vector2 = Vector2(72.0, 90.0)

var game_ref: GameScript = null
var _owns_local_game: bool = false
var desktop_window: DesktopWindowScript = null

var background_panel: Panel = null
var paper_noise_rect: TextureRect = null
var title_bar: Control = null
var label_title: Label = null
var btn_passthrough: Button = null
var btn_close: Button = null

var label_run_best: Label = null
var label_stage_detail: Label = null
var label_mob_name: Label = null
var hp_bar: ProgressBar = null

var battlefield_layer: Control = null
var main_card: MonsterCardViewScript = null
var queue_card_1: MonsterCardViewScript = null
var queue_card_2: MonsterCardViewScript = null

var label_loot_stats: Label = null
var btn_upgrade_atk: Button = null

var hud_panel: PanelContainer = null
var label_gold: Label = null
var label_wealth: Label = null
var label_pressure: Label = null

var equip_slots_box: HBoxContainer = null
var equip_slot_views: Dictionary = {}

var loot_fountain: LootFountainScript = null
var vfx_manager: VfxManagerScript = null
var floating_text: FloatingTextLayerScript = null
var sfx_mixer: SfxMixerScript = null

var _capture_preview_path: String = ""
var _capture_after_sec: float = 0.0
var _capture_elapsed_sec: float = 0.0
var _capture_done: bool = false

func _ready() -> void:
	custom_minimum_size = Vector2(WINDOW_WIDTH, WINDOW_HEIGHT)
	if get_parent() == null:
		size = Vector2(WINDOW_WIDTH, WINDOW_HEIGHT)

	if background_panel == null:
		_build_window_hierarchy()

	if desktop_window == null:
		desktop_window = DesktopWindowScript.new()
		desktop_window.name = "DesktopWindow"
		add_child(desktop_window)

	if loot_fountain == null:
		loot_fountain = LootFountainScript.new()
		loot_fountain.name = "LootFountain"
		loot_fountain.manual_pickup_triggered.connect(_on_manual_pickup_triggered)
		add_child(loot_fountain)

	if vfx_manager == null:
		vfx_manager = VfxManagerScript.new()
		vfx_manager.name = "VfxManager"
		add_child(vfx_manager)

	if floating_text == null:
		floating_text = FloatingTextLayerScript.new()
		floating_text.name = "FloatingTextLayer"
		floating_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
		floating_text.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(floating_text)

	if sfx_mixer == null:
		sfx_mixer = SfxMixerScript.new()

	if game_ref == null:
		var tree_game: GameScript = GameScript.resolve_from_tree(get_tree())
		if tree_game != null:
			bind_game(tree_game)
		else:
			var fallback_game: GameScript = GameScript.new()
			fallback_game.name = "LocalGameSession"
			add_child(fallback_game)
			_owns_local_game = true
			bind_game(fallback_game)

	_parse_capture_user_args()
	refresh_hud()

## 绑定外部或全局 Game 会话协调器（支持测试环境注入独立确定性会话）
func bind_game(p_game: GameScript) -> void:
	if game_ref != null and game_ref.restored_from_minimized.is_connected(_on_restored_from_minimized):
		game_ref.restored_from_minimized.disconnect(_on_restored_from_minimized)
	game_ref = p_game
	if game_ref != null and not game_ref.restored_from_minimized.is_connected(_on_restored_from_minimized):
		game_ref.restored_from_minimized.connect(_on_restored_from_minimized)
	if label_run_best != null:
		refresh_hud()

func _process(delta: float) -> void:
	if game_ref == null:
		return
	_consume_presentation_events()
	refresh_hud()

	if not _capture_done and not _capture_preview_path.is_empty():
		_capture_elapsed_sec += delta
		if _capture_elapsed_sec >= _capture_after_sec:
			_capture_done = true
			_capture_viewport_and_quit()

func _parse_capture_user_args() -> void:
	var user_args: PackedStringArray = OS.get_cmdline_user_args()
	var target_sec: float = 25.0
	for arg: String in user_args:
		if arg.begins_with("--capture-preview="):
			_capture_preview_path = arg.trim_prefix("--capture-preview=")
		elif arg.begins_with("--capture-after-sec="):
			target_sec = maxf(0.5, float(arg.trim_prefix("--capture-after-sec=")))
	if not _capture_preview_path.is_empty():
		_capture_after_sec = target_sec

func _capture_viewport_and_quit() -> void:
	await RenderingServer.frame_post_draw
	var vp: Viewport = get_viewport()
	if vp != null and vp.get_texture() != null:
		var img: Image = vp.get_texture().get_image()
		if img != null:
			var err: Error = img.save_png(_capture_preview_path)
			var state: SimStateScript = game_ref.get_sim_state()
			var win_pos: Vector2i = desktop_window.get_current_window_position() if desktop_window != null else Vector2i.ZERO
			var win_sz: Vector2i = DesktopWindowScript.get_active_window_size()
			print("[WP-07 Preview] Saved=%s err=%d win_pos=%s win_size=%s run_best=%d cur_stage=%d gold=%s W=%s mult=%.2f" % [
				_capture_preview_path,
				int(err),
				str(win_pos),
				str(win_sz),
				state.run_best if state != null else 0,
				state.current_stage if state != null else 0,
				NumScript.format_num(state.gold) if state != null else "0",
				state.wallet.format_net_wealth() if state != null else "0",
				state.get_wealth_hp_multiplier() if state != null else 1.0
			])
	if get_tree() != null:
		get_tree().quit(0)

func _build_window_hierarchy() -> void:
	# 1. 伪磨砂圆角窗底 (#0E0F14, alpha=0.85, 圆角 12, 1px #FFFFFF14 描边 + 3% 程序化纸纹噪点)
	background_panel = Panel.new()
	background_panel.name = "BackgroundPanel"
	background_panel.position = Vector2(2.0, 2.0)
	background_panel.size = Vector2(WINDOW_WIDTH - 4.0, WINDOW_HEIGHT - 4.0)
	background_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	background_panel.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	background_panel.add_theme_stylebox_override("panel", ThemePaletteScript.make_window_panel_style())
	add_child(background_panel)

	paper_noise_rect = TextureRect.new()
	paper_noise_rect.name = "PaperNoiseOverlay"
	paper_noise_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	paper_noise_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	paper_noise_rect.texture = ThemePaletteScript.get_paper_noise_texture()
	paper_noise_rect.stretch_mode = TextureRect.STRETCH_TILE
	background_panel.add_child(paper_noise_rect)

	# 2. 0–24 顶部程序化标题栏（支持拖拽、战场穿透切换、退出）
	title_bar = Control.new()
	title_bar.name = "TitleBar"
	title_bar.position = Vector2(0.0, 0.0)
	title_bar.size = Vector2(WINDOW_WIDTH, TITLE_BAR_HEIGHT)
	title_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	title_bar.gui_input.connect(_on_title_bar_gui_input)
	add_child(title_bar)

	label_title = Label.new()
	label_title.name = "LabelTitle"
	label_title.position = Vector2(14.0, 3.0)
	label_title.size = Vector2(160.0, 18.0)
	label_title.text = "◆ 桌面破坏神"
	label_title.add_theme_font_size_override("font_size", 11)
	label_title.add_theme_color_override("font_color", ThemePaletteScript.color_bone_shadow())
	title_bar.add_child(label_title)

	btn_passthrough = Button.new()
	btn_passthrough.name = "BtnPassthrough"
	btn_passthrough.position = Vector2(WINDOW_WIDTH - 68.0, 3.0)
	btn_passthrough.size = Vector2(34.0, 18.0)
	btn_passthrough.focus_mode = Control.FOCUS_NONE
	btn_passthrough.text = "常驻"
	btn_passthrough.tooltip_text = "切换中部非交互区鼠标穿透"
	btn_passthrough.add_theme_font_size_override("font_size", 10)
	btn_passthrough.add_theme_color_override("font_color", ThemePaletteScript.color_bone_shadow())
	btn_passthrough.add_theme_stylebox_override(
		"normal",
		ThemePaletteScript.make_button_style(ThemePaletteScript.color_card_bg(), ThemePaletteScript.color_iron_gray(), 3)
	)
	btn_passthrough.add_theme_stylebox_override(
		"hover",
		ThemePaletteScript.make_button_style(ThemePaletteScript.color_card_bg(), ThemePaletteScript.color_old_gold(), 3)
	)
	btn_passthrough.add_theme_stylebox_override(
		"pressed",
		ThemePaletteScript.make_button_style(ThemePaletteScript.color_card_bg(), ThemePaletteScript.color_old_gold_bright(), 3)
	)
	btn_passthrough.pressed.connect(_on_btn_passthrough_pressed)
	title_bar.add_child(btn_passthrough)

	btn_close = Button.new()
	btn_close.name = "BtnClose"
	btn_close.position = Vector2(WINDOW_WIDTH - 30.0, 3.0)
	btn_close.size = Vector2(20.0, 18.0)
	btn_close.focus_mode = Control.FOCUS_NONE
	btn_close.text = "×"
	btn_close.add_theme_font_size_override("font_size", 12)
	btn_close.add_theme_color_override("font_color", ThemePaletteScript.color_bone_shadow())
	btn_close.add_theme_stylebox_override(
		"normal",
		ThemePaletteScript.make_button_style(ThemePaletteScript.color_card_bg(), ThemePaletteScript.color_iron_gray(), 3)
	)
	btn_close.add_theme_stylebox_override(
		"hover",
		ThemePaletteScript.make_button_style(ThemePaletteScript.color_blood_ink(), ThemePaletteScript.color_old_gold(), 3)
	)
	btn_close.pressed.connect(_on_btn_close_pressed)
	title_bar.add_child(btn_close)

	# 3. 24–64 层数与怪物血条区 (02 §9.1: 大字 run_best，小字 current_stage / farm_stage)
	var header_root: Control = Control.new()
	header_root.name = "HeaderBand"
	header_root.position = Vector2(14.0, HEADER_TOP_Y)
	header_root.size = Vector2(WINDOW_WIDTH - 28.0, HEADER_HEIGHT)
	header_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(header_root)

	label_run_best = Label.new()
	label_run_best.name = "LabelRunBest"
	label_run_best.position = Vector2(0.0, 1.0)
	label_run_best.size = Vector2(118.0, 20.0)
	label_run_best.text = "第 1 层"
	label_run_best.add_theme_font_size_override("font_size", 14)
	label_run_best.add_theme_color_override("font_color", ThemePaletteScript.color_bone_white())
	header_root.add_child(label_run_best)

	label_stage_detail = Label.new()
	label_stage_detail.name = "LabelStageDetail"
	label_stage_detail.position = Vector2(96.0, 3.0)
	label_stage_detail.size = Vector2(236.0, 18.0)
	label_stage_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label_stage_detail.text = "挑战 1 · 刷怪 1 (0/10)"
	label_stage_detail.add_theme_font_size_override("font_size", 11)
	label_stage_detail.add_theme_color_override("font_color", ThemePaletteScript.color_bone_shadow())
	header_root.add_child(label_stage_detail)

	hp_bar = ProgressBar.new()
	hp_bar.name = "HpBar"
	hp_bar.position = Vector2(0.0, 24.0)
	hp_bar.custom_minimum_size = Vector2(246.0, 10.0)
	hp_bar.size = Vector2(246.0, 10.0)
	hp_bar.min_value = 0.0
	hp_bar.max_value = 100.0
	hp_bar.value = 100.0
	hp_bar.show_percentage = false
	hp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hp_bar.add_theme_font_size_override("font_size", 6)
	hp_bar.add_theme_stylebox_override("background", ThemePaletteScript.make_hp_track_style())
	hp_bar.add_theme_stylebox_override("fill", ThemePaletteScript.make_hp_fill_style())
	header_root.add_child(hp_bar)

	label_mob_name = Label.new()
	label_mob_name.name = "LabelMobName"
	label_mob_name.position = Vector2(252.0, 20.0)
	label_mob_name.size = Vector2(80.0, 16.0)
	label_mob_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label_mob_name.text = "守财亡骸"
	label_mob_name.add_theme_font_size_override("font_size", 10)
	label_mob_name.add_theme_color_override("font_color", ThemePaletteScript.color_ash_gray())
	header_root.add_child(label_mob_name)

	# 4. 64–324 战场区：主怪卡 176×220 + 右侧 2 张排队卡 72×90；Boss 时 208×260 居中且隐藏排队卡 (03 §02.1)
	battlefield_layer = Control.new()
	battlefield_layer.name = "Battlefield"
	battlefield_layer.position = Vector2.ZERO
	battlefield_layer.size = Vector2(WINDOW_WIDTH, WINDOW_HEIGHT)
	battlefield_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(battlefield_layer)

	main_card = MonsterCardViewScript.new()
	main_card.name = "MainMonsterCard"
	main_card.position = MAIN_CARD_POS
	main_card.size = MAIN_CARD_SIZE
	main_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main_card.setup_role(MonsterCardViewScript.CardRole.MAIN_MOB, "守财亡骸")
	battlefield_layer.add_child(main_card)

	queue_card_1 = MonsterCardViewScript.new()
	queue_card_1.name = "QueueCard1"
	queue_card_1.position = QUEUE_CARD_1_POS
	queue_card_1.size = QUEUE_CARD_SIZE
	queue_card_1.mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_card_1.setup_role(MonsterCardViewScript.CardRole.QUEUE_MOB, "待战 #1")
	battlefield_layer.add_child(queue_card_1)

	queue_card_2 = MonsterCardViewScript.new()
	queue_card_2.name = "QueueCard2"
	queue_card_2.position = QUEUE_CARD_2_POS
	queue_card_2.size = QUEUE_CARD_SIZE
	queue_card_2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_card_2.setup_role(MonsterCardViewScript.CardRole.QUEUE_MOB, "待战 #2")
	battlefield_layer.add_child(queue_card_2)

	# 5. 324–392 掉落地面与快捷攻击淬炼按钮（通过 Command 闭环消费金币）
	var ground_line: ColorRect = ColorRect.new()
	ground_line.name = "LootGroundLine"
	ground_line.position = Vector2(16.0, 362.0)
	ground_line.size = Vector2(WINDOW_WIDTH - 32.0, 1.0)
	ground_line.color = ThemePaletteScript.color_iron_gray()
	ground_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ground_line)

	label_loot_stats = Label.new()
	label_loot_stats.name = "LabelLootStats"
	label_loot_stats.position = Vector2(16.0, 367.0)
	label_loot_stats.size = Vector2(176.0, 20.0)
	label_loot_stats.text = "击杀 0 · 背包 0/24"
	label_loot_stats.add_theme_font_size_override("font_size", 10)
	label_loot_stats.add_theme_color_override("font_color", ThemePaletteScript.color_ash_gray())
	add_child(label_loot_stats)

	btn_upgrade_atk = Button.new()
	btn_upgrade_atk.name = "BtnUpgradeAtk"
	btn_upgrade_atk.position = Vector2(198.0, 365.0)
	btn_upgrade_atk.size = Vector2(146.0, 22.0)
	btn_upgrade_atk.focus_mode = Control.FOCUS_NONE
	btn_upgrade_atk.text = "淬炼攻击 Lv.0 (1,995)"
	btn_upgrade_atk.add_theme_font_size_override("font_size", 10)
	btn_upgrade_atk.add_theme_color_override("font_color", ThemePaletteScript.color_bone_white())
	btn_upgrade_atk.add_theme_color_override("font_disabled_color", ThemePaletteScript.color_ash_gray())
	btn_upgrade_atk.add_theme_stylebox_override(
		"normal",
		ThemePaletteScript.make_button_style(ThemePaletteScript.color_card_bg(), ThemePaletteScript.color_old_gold(), 3)
	)
	btn_upgrade_atk.add_theme_stylebox_override(
		"hover",
		ThemePaletteScript.make_button_style(ThemePaletteScript.color_card_bg(), ThemePaletteScript.color_old_gold_bright(), 3)
	)
	btn_upgrade_atk.add_theme_stylebox_override(
		"pressed",
		ThemePaletteScript.make_button_style(ThemePaletteScript.color_card_bg(), ThemePaletteScript.color_bone_white(), 3)
	)
	btn_upgrade_atk.add_theme_stylebox_override(
		"disabled",
		ThemePaletteScript.make_button_style(ThemePaletteScript.color_card_bg(), ThemePaletteScript.color_iron_gray(), 3)
	)
	btn_upgrade_atk.pressed.connect(_on_btn_upgrade_atk_pressed)
	add_child(btn_upgrade_atk)

	# 6. 392–420 极简 HUD 资产栏 (#16161C 卡底 + 旧金描边，实时展示 金币 / 净资产 W / 怪物血量倍率)
	hud_panel = PanelContainer.new()
	hud_panel.name = "HudBar"
	hud_panel.position = Vector2(12.0, HUD_TOP_Y)
	hud_panel.size = Vector2(WINDOW_WIDTH - 24.0, HUD_HEIGHT)
	hud_panel.add_theme_stylebox_override(
		"panel",
		ThemePaletteScript.make_card_style(ThemePaletteScript.color_old_gold(), 4, 1)
	)
	add_child(hud_panel)

	var hud_row: HBoxContainer = HBoxContainer.new()
	hud_row.name = "HudRow"
	hud_row.alignment = BoxContainer.ALIGNMENT_CENTER
	hud_row.add_theme_constant_override("separation", 6)
	hud_panel.add_child(hud_row)

	label_gold = Label.new()
	label_gold.name = "LabelGold"
	label_gold.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label_gold.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label_gold.text = "金币 0"
	label_gold.add_theme_font_size_override("font_size", 11)
	label_gold.add_theme_color_override("font_color", ThemePaletteScript.color_coin_gold())
	hud_row.add_child(label_gold)

	label_wealth = Label.new()
	label_wealth.name = "LabelWealth"
	label_wealth.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label_wealth.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label_wealth.text = "净资 0"
	label_wealth.add_theme_font_size_override("font_size", 11)
	label_wealth.add_theme_color_override("font_color", ThemePaletteScript.color_bone_white())
	hud_row.add_child(label_wealth)

	label_pressure = Label.new()
	label_pressure.name = "LabelPressure"
	label_pressure.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label_pressure.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label_pressure.text = "血量 ×1.00"
	label_pressure.add_theme_font_size_override("font_size", 11)
	label_pressure.add_theme_color_override("font_color", ThemePaletteScript.color_bone_shadow())
	hud_row.add_child(label_pressure)

	# 7. 420–476 六个装备槽（每个 48×48，间距 8，总宽 328，左右对称留白 16px）
	equip_slots_box = HBoxContainer.new()
	equip_slots_box.name = "EquipSlots"
	equip_slots_box.position = Vector2(16.0, EQUIP_TOP_Y)
	equip_slots_box.size = Vector2(328.0, 48.0)
	equip_slots_box.add_theme_constant_override("separation", 8)
	add_child(equip_slots_box)

	equip_slot_views.clear()
	for slot_key: String in SimStateScript.EQUIP_SLOTS:
		var slot_btn: EquipSlotViewScript = EquipSlotViewScript.new()
		slot_btn.name = "Slot_" + slot_key
		slot_btn.setup_slot(slot_key)
		slot_btn.pressed.connect(_on_equip_slot_clicked.bind(slot_key))
		equip_slots_box.add_child(slot_btn)
		equip_slot_views[slot_key] = slot_btn

## 排空并消费 PresentationBus 事件，驱动喷泉弹道、单层飘字、签名特效与音效预算 (WP-08)
func _consume_presentation_events() -> void:
	if sfx_mixer != null:
		sfx_mixer.begin_frame()

	var events: Array = game_ref.drain_presentation_events()
	if events.is_empty() or main_card == null:
		return

	var state: SimStateScript = game_ref.get_sim_state()
	var card_center: Vector2 = main_card.position + main_card.size * 0.5
	var dmg_origin: Vector2 = Vector2(card_center.x, BATTLE_TOP_Y + 42.0)

	for raw_ev: Variant in events:
		var ev: SimEventScript = raw_ev as SimEventScript
		if ev == null:
			continue

		if ev.hint.has("vfx_key") and vfx_manager != null and state != null:
			var vfx_key: String = str(ev.hint.get("vfx_key", ""))
			match vfx_key:
				"chain_lightning":
					var jump_idx: int = int(ev.hint.get("jump_index", 1))
					var jump_target: Vector2 = queue_card_1.position + queue_card_1.size * 0.5
					if jump_idx >= 2:
						jump_target = queue_card_2.position + queue_card_2.size * 0.5
					vfx_manager.spawn_chain_lightning(card_center, jump_target, jump_idx)
				"drop_explosion":
					vfx_manager.spawn_drop_explosion(card_center, int(ev.hint.get("rarity", 0)))
				"killing_frenzy":
					vfx_manager.spawn_killing_frenzy(card_center, state.buffs.get_stacks("killing_frenzy"))

		match ev.type:
			SimEventScript.T.HIT:
				main_card.trigger_hit_flash()
				if floating_text != null:
					floating_text.add_floating_text(
						NumScript.format_num(ev.value),
						dmg_origin + Vector2(randf_range(-22.0, 22.0), randf_range(-10.0, 14.0)),
						ThemePaletteScript.color_bone_white(),
						false
					)
				if sfx_mixer != null and vfx_manager != null:
					sfx_mixer.request_play_sound("hit", vfx_manager.budget)
			SimEventScript.T.CRIT:
				main_card.trigger_hit_flash()
				if vfx_manager != null:
					vfx_manager.spawn_crit_ring(card_center)
				if floating_text != null:
					floating_text.add_floating_text(
						NumScript.format_num(ev.value) + "!",
						dmg_origin + Vector2(randf_range(-26.0, 26.0), randf_range(-12.0, 12.0)),
						ThemePaletteScript.color_crit_core(),
						true
					)
				if sfx_mixer != null and vfx_manager != null:
					sfx_mixer.request_play_sound("crit", vfx_manager.budget)
			SimEventScript.T.DROP:
				var rarity: int = int(ev.payload.get("rarity", 0))
				var ilvl: int = int(ev.payload.get("ilvl", 1))
				var launch_mul: float = float(ev.hint.get("launch_mul", 1.0))
				if loot_fountain != null:
					var spawn_count: int = mini(maxi(1, ev.count), 4)
					for _d: int in range(spawn_count):
						loot_fountain.spawn_drop(card_center, rarity, launch_mul, ilvl)
				if vfx_manager != null and rarity >= 3:
					vfx_manager.spawn_edge_alert(rarity)
				if sfx_mixer != null and vfx_manager != null:
					var sfx_id: String = "drop_rare" if rarity >= 3 else "drop_normal"
					sfx_mixer.request_play_sound(sfx_id, vfx_manager.budget)
			SimEventScript.T.STAGE_UP:
				if floating_text != null:
					floating_text.add_floating_text(
						"第 %d 层" % int(round(ev.value)),
						Vector2(WINDOW_WIDTH * 0.5, BATTLE_TOP_Y + 22.0),
						ThemePaletteScript.color_old_gold_bright(),
						true
					)

func _on_manual_pickup_triggered(ilvl: int, rarity: int) -> void:
	if game_ref != null:
		game_ref.request_manual_pickup(ilvl, rarity)

## 窗口从最小化恢复时播一次受控回归汇总喷泉（绝不一次涌出上千掉落，Q10 & E8）
func _on_restored_from_minimized(summary: Dictionary) -> void:
	if loot_fountain == null or main_card == null:
		return
	var card_center: Vector2 = main_card.position + main_card.size * 0.5
	var rare_list: Array = summary.get("rare_drops", []) as Array
	var spawned_rare: int = 0
	for rare_raw: Variant in rare_list:
		if spawned_rare >= 5:
			break
		if rare_raw is Dictionary:
			var rare_dict: Dictionary = rare_raw as Dictionary
			loot_fountain.spawn_drop(card_center, int(rare_dict.get("rarity", 3)), 1.15, int(rare_dict.get("ilvl", 1)))
			spawned_rare += 1

	var total_drops: int = int(summary.get("drops_count", 0))
	var normal_summary: int = mini(3, total_drops)
	for _i: int in range(normal_summary):
		loot_fountain.spawn_drop(card_center, 1, 1.0, 1)

	if floating_text != null and total_drops > 0:
		floating_text.add_floating_text(
			"回归 +%d 掉落" % total_drops,
			Vector2(WINDOW_WIDTH * 0.5, BATTLE_TOP_Y + 28.0),
			ThemePaletteScript.color_old_gold_bright(),
			true
		)

## 只读读取 SimState 刷新全部极简 HUD 指标（层数、金币、净资产 W、财富压力血量倍率）
func refresh_hud() -> void:
	if game_ref == null or label_run_best == null:
		return
	var state: SimStateScript = game_ref.get_sim_state()
	if state == null:
		return

	# 1. 层数展示 (§9.1: 大字显示 run_best，小字显示 current_stage / farm_stage 状态)
	label_run_best.text = "第 %d 层" % state.run_best
	if state.is_boss:
		var remain_sec: float = maxf(0.0, state.balance.boss_time_limit - state.boss_timer)
		label_stage_detail.text = "挑战 %d · 首领 %.1fs" % [state.current_stage, remain_sec]
		label_stage_detail.add_theme_color_override("font_color", ThemePaletteScript.color_old_gold_bright())
	elif state.farm_stage < state.current_stage:
		label_stage_detail.text = "挑战 %d · 退刷 %d (%d/%d)" % [
			state.current_stage,
			state.farm_stage,
			state.farm_kills_since_retreat,
			state.balance.farm_retry_kills
		]
		label_stage_detail.add_theme_color_override("font_color", ThemePaletteScript.color_old_gold())
	else:
		label_stage_detail.text = "挑战 %d · 刷怪 %d (%d/%d)" % [
			state.current_stage,
			state.farm_stage,
			state.mobs_killed_in_stage,
			state.balance.mobs_per_stage
		]
		label_stage_detail.add_theme_color_override("font_color", ThemePaletteScript.color_bone_shadow())

	# 2. 怪物血条与主怪卡/排队卡布局切换 (03 §02.1)
	var hp_ratio: float = 0.0
	if state.mob_max_hp_log > 0.0 and state.mob_current_hp_log > NumScript.ZERO:
		hp_ratio = clampf(pow(10.0, clampf(state.mob_current_hp_log - state.mob_max_hp_log, -20.0, 1.0)), 0.0, 1.0)
	hp_bar.value = hp_ratio * 100.0

	var delta_h: float = state.get_wealth_pressure_hp_delta()
	if state.is_boss:
		label_mob_name.text = "深渊魔主"
		label_mob_name.add_theme_color_override("font_color", ThemePaletteScript.color_old_gold_bright())
		main_card.position = BOSS_CARD_POS
		main_card.size = BOSS_CARD_SIZE
		main_card.setup_role(MonsterCardViewScript.CardRole.BOSS_MOB, "深渊魔主")
		queue_card_1.visible = false
		queue_card_2.visible = false
	else:
		label_mob_name.text = "守财亡骸"
		label_mob_name.add_theme_color_override("font_color", ThemePaletteScript.color_ash_gray())
		main_card.position = MAIN_CARD_POS
		main_card.size = MAIN_CARD_SIZE
		main_card.setup_role(MonsterCardViewScript.CardRole.MAIN_MOB, "守财亡骸")
		var remain_mobs: int = maxi(0, state.balance.mobs_per_stage - state.mobs_killed_in_stage)
		queue_card_1.visible = remain_mobs >= 1 or state.farm_stage < state.current_stage
		queue_card_2.visible = remain_mobs >= 2 or state.farm_stage < state.current_stage
		queue_card_1.update_combat_visuals(1.0, delta_h, 0.0)
		queue_card_2.update_combat_visuals(1.0, delta_h, 0.0)

	main_card.update_combat_visuals(hp_ratio, delta_h, main_card.hit_flash)

	# 3. 极简 HUD 核心数值：金币 (gold)、净资产 (W = gold - debt_total)、财富压力血量倍率
	label_gold.text = "金币 %s" % NumScript.format_num(state.gold)

	var wealth_info: Dictionary = state.get_net_wealth_info()
	var is_debt: bool = bool(wealth_info.get("is_debt", false))
	var net_log: float = float(wealth_info.get("net_log", NumScript.ZERO))
	var net_str: String = state.wallet.format_net_wealth()
	if is_debt:
		label_wealth.text = "净资 %s" % net_str
		label_wealth.add_theme_color_override("font_color", ThemePaletteScript.color_old_gold_bright())
	elif net_log == NumScript.ZERO:
		label_wealth.text = "净资 0"
		label_wealth.add_theme_color_override("font_color", ThemePaletteScript.color_bone_shadow())
	else:
		label_wealth.text = "净资 +%s" % net_str
		label_wealth.add_theme_color_override("font_color", ThemePaletteScript.color_bone_white())

	var hp_mult: float = state.get_wealth_hp_multiplier()
	label_pressure.text = "血量 ×%.2f" % hp_mult
	if hp_mult > 1.01:
		label_pressure.add_theme_color_override("font_color", ThemePaletteScript.color_old_gold_bright())
	elif hp_mult < 0.99:
		label_pressure.add_theme_color_override("font_color", ThemePaletteScript.color_bone_white())
	else:
		label_pressure.add_theme_color_override("font_color", ThemePaletteScript.color_bone_shadow())

	# 4. 掉落统计与金币攻击升级按钮状态（只读判定余额是否足够）
	label_loot_stats.text = "击杀 %d · 背包 %d/%d" % [
		state.mobs_killed_total,
		state.inventory.get_count(),
		state.balance.inventory_max_slots
	]
	var next_cost_log: float = state.upgrades.get_next_atk_cost_log(state)
	var can_afford_atk: bool = state.gold != NumScript.ZERO and state.gold >= next_cost_log
	btn_upgrade_atk.disabled = not can_afford_atk
	btn_upgrade_atk.text = "淬炼攻击 Lv.%d (%s)" % [
		state.upgrades.atk_level,
		NumScript.format_num(next_cost_log)
	]

	# 5. 六槽装备只读映射
	for slot_key: String in SimStateScript.EQUIP_SLOTS:
		var slot_view: EquipSlotViewScript = equip_slot_views.get(slot_key, null) as EquipSlotViewScript
		if slot_view == null:
			continue
		var eq_item: ItemInstanceScript = state.equipped.get(slot_key, null) as ItemInstanceScript
		if eq_item == null:
			slot_view.set_item_state(false, -1, 0)
		else:
			slot_view.set_item_state(true, int(eq_item.rarity), eq_item.ilvl)

func _on_btn_upgrade_atk_pressed() -> void:
	if game_ref != null:
		game_ref.request_buy_atk_upgrade(1)

func _on_equip_slot_clicked(slot_key: String) -> void:
	if game_ref == null:
		return
	var state: SimStateScript = game_ref.get_sim_state()
	if state == null:
		return

	# 从背包中只读检索同部位最高评分装备，若优于当前穿戴则投递 Command.EQUIP_ITEM
	var cur_equipped: ItemInstanceScript = state.equipped.get(slot_key, null) as ItemInstanceScript
	var best_score: float = cur_equipped.score if cur_equipped != null else -1.0
	var best_uid: int = -1

	for i: int in range(state.inventory.get_count()):
		var inv_item: ItemInstanceScript = state.inventory.get_item_at(i)
		if inv_item != null and ItemInstanceScript.get_slot_key(inv_item.slot) == slot_key:
			if inv_item.score > best_score:
				best_score = inv_item.score
				best_uid = inv_item.uid

	if best_uid >= 0:
		game_ref.request_equip_uid(best_uid)

func _on_btn_passthrough_pressed() -> void:
	if desktop_window == null:
		return
	var next_mode: bool = not desktop_window.battle_passthrough_enabled
	desktop_window.set_battle_passthrough_enabled(
		next_mode,
		Vector2(WINDOW_WIDTH, WINDOW_HEIGHT),
		HEADER_TOP_Y + 2.0,
		HUD_TOP_Y - 30.0
	)
	if next_mode:
		btn_passthrough.text = "穿透"
		btn_passthrough.add_theme_color_override("font_color", ThemePaletteScript.color_old_gold_bright())
	else:
		btn_passthrough.text = "常驻"
		btn_passthrough.add_theme_color_override("font_color", ThemePaletteScript.color_bone_shadow())

func _on_btn_close_pressed() -> void:
	if get_tree() != null:
		get_tree().quit()

func _on_title_bar_gui_input(event: InputEvent) -> void:
	if desktop_window == null:
		return
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				var start_mouse: Vector2i = DisplayServer.mouse_get_position()
				desktop_window.begin_drag(start_mouse)
			else:
				desktop_window.end_drag()
	elif event is InputEventMouseMotion:
		if desktop_window.is_dragging():
			var cur_mouse: Vector2i = DisplayServer.mouse_get_position()
			desktop_window.update_drag(cur_mouse)
