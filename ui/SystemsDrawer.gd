class_name SystemsDrawer extends PanelContainer

## D5 紧凑系统抽屉 (信贷 / 科技研究 / 第100层门票与护盾提示)
## 铁律：
## 1. 100% 显式静态类型，零 :=
## 2. 严格只读访问 SimState；一切操作经 Game.request_* 走 Command 队列
## 3. 严格遵守「镀金债契 · 骨白版画」HEX 色板与 360×480 布局约束

const GameScript = preload("res://autoload/Game.gd")
const SimStateScript = preload("res://simulation/SimState.gd")
const ThemePaletteScript = preload("res://ui/ThemePalette.gd")
const NumScript = preload("res://core/num/Num.gd")
const TollScript = preload("res://simulation/economy/Toll.gd")
const TechNodeDefScript = preload("res://simulation/tech/TechNodeDef.gd")
const ArtRegistryScript = preload("res://ui/ArtRegistry.gd")
const ItemInstanceScript = preload("res://simulation/loot/ItemInstance.gd")

enum TabKind {
	CREDIT = 0,
	TECH = 1,
	TOLL = 2,
	PRESTIGE = 3
}

var _game_ref: GameScript = null
var _active_tab: int = TabKind.CREDIT
var _selected_util: float = 1.0

var _btn_tab_credit: Button = null
var _btn_tab_tech: Button = null
var _btn_tab_toll: Button = null
var _btn_tab_prestige: Button = null
var _content_box: VBoxContainer = null

# Credit tab widgets
var _credit_view: VBoxContainer = null
var _lbl_credit_status: Label = null
var _lbl_credit_preview: Label = null
var _btn_util_30: Button = null
var _btn_util_60: Button = null
var _btn_util_100: Button = null
var _btn_borrow: Button = null
var _btn_repay: Button = null

# Tech tab widgets
var _tech_view: VBoxContainer = null
var _lbl_tech_queue: Label = null
var _lbl_auto_status: Label = null
var _tech_nodes_list: VBoxContainer = null
var _tech_node_rows: Dictionary = {}

# Toll tab widgets
var _toll_view: VBoxContainer = null
var _lbl_toll_status: Label = null
var _toll_progress_bar: ProgressBar = null
var _lbl_toll_hint: Label = null

# Prestige tab widgets
var _prestige_view: VBoxContainer = null
var _lbl_prestige_preview: Label = null
var _lbl_offline_summary: Label = null
var _btn_prestige: Button = null
var _btn_abyss_prestige: Button = null
var _lbl_abyss_preview: Label = null
var _extract_picker_box: VBoxContainer = null
var _vault_container: VBoxContainer = null
var _vault_slots_box: HBoxContainer = null
var _unlocked_powers_box: VBoxContainer = null
var _selected_extract_power: String = ""

func _init() -> void:
	name = "SystemsDrawer"
	position = Vector2(16.0, 118.0)
	size = Vector2(328.0, 268.0)
	visible = false
	z_index = 24

	var panel_sb: StyleBoxFlat = ThemePaletteScript.make_card_style(
		ThemePaletteScript.color_old_gold(),
		4,
		1
	)
	panel_sb.content_margin_left = 10.0
	panel_sb.content_margin_right = 10.0
	panel_sb.content_margin_top = 8.0
	panel_sb.content_margin_bottom = 8.0
	add_theme_stylebox_override("panel", panel_sb)

	_build_ui()

func bind_game(p_game: GameScript) -> void:
	_game_ref = p_game

func open_tab(tab_idx: int = -1) -> void:
	if tab_idx >= 0:
		_active_tab = clampi(tab_idx, TabKind.CREDIT, TabKind.PRESTIGE)
		_sync_tab_visibility()
	visible = true
	refresh_view()

func close_drawer() -> void:
	visible = false

func get_active_tab() -> int:
	return _active_tab

func set_selected_utilization(util: float) -> void:
	_selected_util = clampf(util, 0.1, 1.0)
	refresh_view()

func get_credit_preview_snapshot() -> Dictionary:
	if _game_ref == null:
		return {"valid": false}
	var state: SimStateScript = _game_ref.get_sim_state()
	if state == null or state.credit == null:
		return {"valid": false}
	var stage: int = state.get_active_stage()
	var limit_log: float = state.credit.get_credit_limit_log(stage, state.balance)
	var borrow_log: float = NumScript.mul(limit_log, NumScript.from_float(_selected_util))
	return state.credit.preview_borrow(stage, borrow_log, state.balance)

func _build_ui() -> void:
	var root_vbox: VBoxContainer = VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 6)
	add_child(root_vbox)

	var header: HBoxContainer = HBoxContainer.new()
	header.add_theme_constant_override("separation", 4)
	root_vbox.add_child(header)

	_btn_tab_credit = _make_tab_button("信贷", TabKind.CREDIT)
	_btn_tab_tech = _make_tab_button("科技", TabKind.TECH)
	_btn_tab_toll = _make_tab_button("门票", TabKind.TOLL)
	_btn_tab_prestige = _make_tab_button("转生", TabKind.PRESTIGE)
	header.add_child(_btn_tab_credit)
	header.add_child(_btn_tab_tech)
	header.add_child(_btn_tab_toll)
	header.add_child(_btn_tab_prestige)

	var close_btn: Button = Button.new()
	close_btn.name = "BtnCloseDrawer"
	close_btn.text = "关闭"
	close_btn.custom_minimum_size = Vector2(44.0, 22.0)
	close_btn.add_theme_font_size_override("font_size", 11)
	close_btn.add_theme_color_override("font_color", ThemePaletteScript.color_bone_white())
	close_btn.pressed.connect(close_drawer)
	header.add_child(close_btn)

	_content_box = VBoxContainer.new()
	_content_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_vbox.add_child(_content_box)

	_build_credit_tab()
	_build_tech_tab()
	_build_toll_tab()
	_build_prestige_tab()
	_sync_tab_visibility()

func _make_tab_button(title: String, tab_idx: int) -> Button:
	var btn: Button = Button.new()
	btn.text = title
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.custom_minimum_size = Vector2(0.0, 22.0)
	btn.add_theme_font_size_override("font_size", 11)
	btn.pressed.connect(_on_tab_selected.bind(tab_idx))
	return btn

func _build_credit_tab() -> void:
	_credit_view = VBoxContainer.new()
	_credit_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_credit_view.add_theme_constant_override("separation", 6)
	_content_box.add_child(_credit_view)

	var top_box: HBoxContainer = HBoxContainer.new()
	top_box.add_theme_constant_override("separation", 8)
	_credit_view.add_child(top_box)

	var ledger_tex: Texture2D = ArtRegistryScript.get_wealth_ledger_texture()
	if ledger_tex != null:
		var ledger_rect: TextureRect = TextureRect.new()
		ledger_rect.custom_minimum_size = Vector2(36.0, 36.0)
		ledger_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ledger_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ledger_rect.texture = ledger_tex
		ledger_rect.material = ArtRegistryScript.make_palette_material(ThemePaletteScript.color_old_gold_bright(), false, 1.0)
		top_box.add_child(ledger_rect)

	_lbl_credit_status = Label.new()
	_lbl_credit_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lbl_credit_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lbl_credit_status.add_theme_font_size_override("font_size", 10)
	_lbl_credit_status.add_theme_color_override("font_color", ThemePaletteScript.color_bone_white())
	top_box.add_child(_lbl_credit_status)

	var util_row: HBoxContainer = HBoxContainer.new()
	util_row.add_theme_constant_override("separation", 6)
	_credit_view.add_child(util_row)

	_btn_util_30 = Button.new()
	_btn_util_30.text = "借 30%"
	_btn_util_30.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_btn_util_30.add_theme_font_size_override("font_size", 11)
	_btn_util_30.pressed.connect(set_selected_utilization.bind(0.3))
	util_row.add_child(_btn_util_30)

	_btn_util_60 = Button.new()
	_btn_util_60.text = "借 60%"
	_btn_util_60.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_btn_util_60.add_theme_font_size_override("font_size", 11)
	_btn_util_60.pressed.connect(set_selected_utilization.bind(0.6))
	util_row.add_child(_btn_util_60)

	_btn_util_100 = Button.new()
	_btn_util_100.text = "满额 100%"
	_btn_util_100.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_btn_util_100.add_theme_font_size_override("font_size", 11)
	_btn_util_100.pressed.connect(set_selected_utilization.bind(1.0))
	util_row.add_child(_btn_util_100)

	_lbl_credit_preview = Label.new()
	_lbl_credit_preview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lbl_credit_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_lbl_credit_preview.add_theme_font_size_override("font_size", 11)
	_lbl_credit_preview.add_theme_color_override("font_color", ThemePaletteScript.color_old_gold_bright())
	_credit_view.add_child(_lbl_credit_preview)

	var action_row: HBoxContainer = HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 6)
	_credit_view.add_child(action_row)

	_btn_borrow = Button.new()
	_btn_borrow.name = "BtnBorrowCredit"
	_btn_borrow.text = "签约借款"
	_btn_borrow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_btn_borrow.add_theme_font_size_override("font_size", 11)
	_btn_borrow.pressed.connect(_on_borrow_pressed)
	action_row.add_child(_btn_borrow)

	_btn_repay = Button.new()
	_btn_repay.name = "BtnRepayCredit"
	_btn_repay.text = "还清债务"
	_btn_repay.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_btn_repay.add_theme_font_size_override("font_size", 11)
	_btn_repay.pressed.connect(_on_repay_pressed)
	action_row.add_child(_btn_repay)

func _build_tech_tab() -> void:
	_tech_view = VBoxContainer.new()
	_tech_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tech_view.add_theme_constant_override("separation", 6)
	_content_box.add_child(_tech_view)

	_lbl_tech_queue = Label.new()
	_lbl_tech_queue.add_theme_font_size_override("font_size", 11)
	_lbl_tech_queue.add_theme_color_override("font_color", ThemePaletteScript.color_old_gold_bright())
	_tech_view.add_child(_lbl_tech_queue)

	_lbl_auto_status = Label.new()
	_lbl_auto_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lbl_auto_status.add_theme_font_size_override("font_size", 10)
	_lbl_auto_status.add_theme_color_override("font_color", ThemePaletteScript.color_bone_white())
	_tech_view.add_child(_lbl_auto_status)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tech_view.add_child(scroll)

	_tech_nodes_list = VBoxContainer.new()
	_tech_nodes_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tech_nodes_list.add_theme_constant_override("separation", 4)
	scroll.add_child(_tech_nodes_list)

func _build_toll_tab() -> void:
	_toll_view = VBoxContainer.new()
	_toll_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_toll_view.add_theme_constant_override("separation", 8)
	_content_box.add_child(_toll_view)

	_lbl_toll_status = Label.new()
	_lbl_toll_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lbl_toll_status.add_theme_font_size_override("font_size", 11)
	_lbl_toll_status.add_theme_color_override("font_color", ThemePaletteScript.color_bone_white())
	_toll_view.add_child(_lbl_toll_status)

	_toll_progress_bar = ProgressBar.new()
	_toll_progress_bar.custom_minimum_size = Vector2(0.0, 14.0)
	_toll_progress_bar.max_value = 100.0
	_toll_progress_bar.show_percentage = true
	_toll_view.add_child(_toll_progress_bar)

	_lbl_toll_hint = Label.new()
	_lbl_toll_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lbl_toll_hint.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_lbl_toll_hint.add_theme_font_size_override("font_size", 11)
	_lbl_toll_hint.add_theme_color_override("font_color", ThemePaletteScript.color_old_gold_bright())
	_toll_view.add_child(_lbl_toll_hint)

func _build_prestige_tab() -> void:
	_prestige_view = VBoxContainer.new()
	_prestige_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_prestige_view.add_theme_constant_override("separation", 6)
	_content_box.add_child(_prestige_view)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_prestige_view.add_child(scroll)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 6)
	scroll.add_child(vbox)

	_lbl_prestige_preview = Label.new()
	_lbl_prestige_preview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lbl_prestige_preview.add_theme_font_size_override("font_size", 10)
	_lbl_prestige_preview.add_theme_color_override("font_color", ThemePaletteScript.color_bone_white())
	vbox.add_child(_lbl_prestige_preview)

	_btn_prestige = Button.new()
	_btn_prestige.name = "BtnSoulPrestige"
	_btn_prestige.text = "灵魂转生 (保留身上 6 件装备与科技)"
	_btn_prestige.custom_minimum_size = Vector2(0.0, 24.0)
	_btn_prestige.add_theme_font_size_override("font_size", 11)
	_btn_prestige.pressed.connect(_on_prestige_pressed)
	vbox.add_child(_btn_prestige)

	# 深渊轮回与卡奈魔盒
	var sep: HSeparator = HSeparator.new()
	vbox.add_child(sep)

	_lbl_abyss_preview = Label.new()
	_lbl_abyss_preview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lbl_abyss_preview.add_theme_font_size_override("font_size", 10)
	_lbl_abyss_preview.add_theme_color_override("font_color", ThemePaletteScript.color_old_gold_bright())
	vbox.add_child(_lbl_abyss_preview)

	_btn_abyss_prestige = Button.new()
	_btn_abyss_prestige.name = "BtnAbyssPrestige"
	_btn_abyss_prestige.text = "深渊印记转生 (萃取选中词条)"
	_btn_abyss_prestige.custom_minimum_size = Vector2(0.0, 24.0)
	_btn_abyss_prestige.add_theme_font_size_override("font_size", 11)
	_btn_abyss_prestige.pressed.connect(_on_abyss_prestige_pressed)
	vbox.add_child(_btn_abyss_prestige)

	_extract_picker_box = VBoxContainer.new()
	_extract_picker_box.add_theme_constant_override("separation", 2)
	vbox.add_child(_extract_picker_box)

	# 魔盒威能台容器
	_vault_container = VBoxContainer.new()
	_vault_container.add_theme_constant_override("separation", 4)
	vbox.add_child(_vault_container)

	var v_title: Label = Label.new()
	v_title.text = "卡奈魔盒威能台 (点击卸下 / 点击装配)"
	v_title.add_theme_font_size_override("font_size", 10)
	v_title.add_theme_color_override("font_color", ThemePaletteScript.color_old_gold())
	_vault_container.add_child(v_title)

	_vault_slots_box = HBoxContainer.new()
	_vault_slots_box.add_theme_constant_override("separation", 4)
	_vault_container.add_child(_vault_slots_box)

	_unlocked_powers_box = VBoxContainer.new()
	_unlocked_powers_box.add_theme_constant_override("separation", 2)
	_vault_container.add_child(_unlocked_powers_box)

	_lbl_offline_summary = Label.new()
	_lbl_offline_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lbl_offline_summary.add_theme_font_size_override("font_size", 9)
	_lbl_offline_summary.add_theme_color_override("font_color", ThemePaletteScript.color_bone_shadow())
	vbox.add_child(_lbl_offline_summary)

func get_prestige_preview_snapshot() -> Dictionary:
	if _game_ref == null:
		return {"can_prestige": false}
	var state: SimStateScript = _game_ref.get_sim_state()
	if state == null:
		return {"can_prestige": false}
	return state.get_soul_prestige_preview()

func _on_tab_selected(tab_idx: int) -> void:
	_active_tab = tab_idx
	_sync_tab_visibility()
	refresh_view()

func _sync_tab_visibility() -> void:
	_credit_view.visible = (_active_tab == TabKind.CREDIT)
	_tech_view.visible = (_active_tab == TabKind.TECH)
	_toll_view.visible = (_active_tab == TabKind.TOLL)
	_prestige_view.visible = (_active_tab == TabKind.PRESTIGE)

	_btn_tab_credit.add_theme_color_override(
		"font_color",
		ThemePaletteScript.color_old_gold_bright() if _active_tab == TabKind.CREDIT else ThemePaletteScript.color_bone_shadow()
	)
	_btn_tab_tech.add_theme_color_override(
		"font_color",
		ThemePaletteScript.color_old_gold_bright() if _active_tab == TabKind.TECH else ThemePaletteScript.color_bone_shadow()
	)
	_btn_tab_toll.add_theme_color_override(
		"font_color",
		ThemePaletteScript.color_old_gold_bright() if _active_tab == TabKind.TOLL else ThemePaletteScript.color_bone_shadow()
	)
	_btn_tab_prestige.add_theme_color_override(
		"font_color",
		ThemePaletteScript.color_old_gold_bright() if _active_tab == TabKind.PRESTIGE else ThemePaletteScript.color_bone_shadow()
	)

func refresh_view() -> void:
	if not visible or _game_ref == null:
		return
	var state: SimStateScript = _game_ref.get_sim_state()
	if state == null:
		return

	match _active_tab:
		TabKind.CREDIT:
			_refresh_credit_tab(state)
		TabKind.TECH:
			_refresh_tech_tab(state)
		TabKind.TOLL:
			_refresh_toll_tab(state)
		TabKind.PRESTIGE:
			_refresh_prestige_tab(state)

func _refresh_credit_tab(state: SimStateScript) -> void:
	var stage: int = state.get_active_stage()
	var limit_log: float = state.credit.get_credit_limit_log(stage, state.balance)
	var max_loans: int = state.credit.get_max_concurrent_loans(state.balance)
	var active_count: int = state.credit.loan_count
	var discount: float = state.tech.get_effect_total("credit_repay_discount")
	var discount_str: String = (" (还款折扣 -%.0f%%)" % (discount * 100.0)) if discount > 0.0 else ""

	_lbl_credit_status.text = "信用等级: Tier %d%s | 最大额度: %s\n当前负债: %s | 贷款并发: %d / %d 笔\n状态: %s" % [
		state.credit.credit_tier,
		discount_str,
		NumScript.format_num(limit_log),
		NumScript.format_num(state.debt_total),
		active_count,
		max_loans,
		"还债中 (每笔收入扣 40%)" if state.credit.active_loan else "无活跃贷款"
	]

	var preview: Dictionary = get_credit_preview_snapshot()
	if active_count >= max_loans:
		_lbl_credit_preview.text = "已达并发贷款上限 (%d 笔)，还清后可继续借款或信用升阶。" % max_loans
		_btn_borrow.disabled = true
	elif bool(preview.get("valid", false)):
		var borrow_log: float = NumScript.mul(limit_log, NumScript.from_float(_selected_util))
		_lbl_credit_preview.text = "签约预览 (使用率 %.0f%%):\n借款到账: %s  |  溢价倍率: ×%.3f\n总还款额: %s  |  预计还清: %.1f 分钟" % [
			float(preview.get("utilization", 0.0)) * 100.0,
			NumScript.format_num(borrow_log),
			float(preview.get("repayment_mult", 1.0)),
			NumScript.format_num(float(preview.get("repayment_total_log", NumScript.ZERO))),
			float(preview.get("est_minutes", 0.0))
		]
		_btn_borrow.disabled = false
	else:
		_lbl_credit_preview.text = str(preview.get("reason", "当前不可借款"))
		_btn_borrow.disabled = true

	_btn_repay.disabled = (state.debt_total == NumScript.ZERO or state.gold == NumScript.ZERO)

func _refresh_tech_tab(state: SimStateScript) -> void:
	if state.tech == null or state.research_queue == null:
		return
	var now_unix: float = Time.get_unix_time_from_system()
	var q_count: int = state.research_queue.entries.size()
	var head_rem: float = state.research_queue.get_head_remaining_seconds(now_unix)
	_lbl_tech_queue.text = "研究队列: %d / 5  |  当前剩余: %.0fs" % [q_count, maxf(0.0, head_rem)]

	var auto_up_active: bool = state.has_tech_effect("auto_buy_atk")
	var auto_repay_active: bool = state.has_tech_effect("auto_repay")
	var saving_toll: bool = state.is_saving_for_toll()
	var auto_up_str: String = "未解锁"
	if auto_up_active:
		auto_up_str = "暂缓(门票储蓄中)" if saving_toll else "运行中 (Lv.%d)" % state.upgrades.atk_level
	var auto_repay_str: String = "未解锁"
	if auto_repay_active:
		auto_repay_str = "还债中" if state.debt_total != NumScript.ZERO else "运行中(无债务)"
	_lbl_auto_status.text = "自动化状态: 自动升级[%s] | 自动还款[%s]" % [auto_up_str, auto_repay_str]

	var defs: Array = state.tech.get_all_defs()
	if _tech_node_rows.is_empty():
		for raw_def: Variant in defs:
			var ndef: TechNodeDefScript = raw_def as TechNodeDefScript
			if ndef == null:
				continue
			var row: HBoxContainer = HBoxContainer.new()
			row.add_theme_constant_override("separation", 6)

			var info_lbl: Label = Label.new()
			info_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			info_lbl.add_theme_font_size_override("font_size", 10)
			row.add_child(info_lbl)

			var act_btn: Button = Button.new()
			act_btn.custom_minimum_size = Vector2(72.0, 22.0)
			act_btn.add_theme_font_size_override("font_size", 9)
			act_btn.pressed.connect(_on_research_node_pressed.bind(ndef.id))
			row.add_child(act_btn)

			_tech_nodes_list.add_child(row)
			_tech_node_rows[ndef.id] = {"label": info_lbl, "button": act_btn}

	for raw_def: Variant in defs:
		var ndef: TechNodeDefScript = raw_def as TechNodeDefScript
		if ndef == null or not _tech_node_rows.has(ndef.id):
			continue
		var entry: Dictionary = _tech_node_rows[ndef.id]
		var info_lbl: Label = entry["label"] as Label
		var act_btn: Button = entry["button"] as Button

		var researched: bool = state.tech.has_researched(ndef.id)
		var queued: bool = _is_node_queued(state.research_queue.entries, ndef.id)
		var prereq_ok: bool = ndef.prereq_id.is_empty() or state.tech.has_researched(ndef.prereq_id)
		var marks_ok: bool = state.marks >= ndef.requires_marks
		var can_afford: bool = state.gold >= ndef.cost_gold_log

		var branch_cn: String = "通用"
		match ndef.branch:
			"combat":
				branch_cn = "战斗"
			"economy":
				branch_cn = "经济"
			"credit":
				branch_cn = "信贷"
			"automation":
				branch_cn = "自动"
		var mark_req_str: String = (" · 需印记×%d" % ndef.requires_marks) if ndef.requires_marks > 0 else ""
		info_lbl.text = "【%s】%s (T%d%s)\n%s" % [branch_cn, ndef.display_name, ndef.tier, mark_req_str, ndef.desc]

		if researched:
			info_lbl.add_theme_color_override("font_color", ThemePaletteScript.color_old_gold_bright())
			act_btn.text = "已研究"
			act_btn.disabled = true
		elif queued:
			info_lbl.add_theme_color_override("font_color", ThemePaletteScript.color_bone_white())
			act_btn.text = "排队中"
			act_btn.disabled = true
		elif not prereq_ok:
			info_lbl.add_theme_color_override("font_color", ThemePaletteScript.color_ash_gray())
			act_btn.text = "需前置"
			act_btn.disabled = true
		elif not marks_ok:
			info_lbl.add_theme_color_override("font_color", ThemePaletteScript.color_ash_gray())
			act_btn.text = "需印记%d" % ndef.requires_marks
			act_btn.disabled = true
		else:
			info_lbl.add_theme_color_override("font_color", ThemePaletteScript.color_bone_white())
			act_btn.text = "研究(%s)" % NumScript.format_num(ndef.cost_gold_log)
			act_btn.disabled = (not can_afford) or (q_count >= 5)

func _refresh_toll_tab(state: SimStateScript) -> void:
	var st: Dictionary = TollScript.get_status(state)
	var gate_stage: int = int(st.get("gate_stage", 100))
	var toll_log: float = float(st.get("toll_log", NumScript.ZERO))
	var net_log: float = float(st.get("net_assets_log", NumScript.ZERO))
	var progress: float = float(st.get("progress", 0.0))
	var has_shield: bool = state.mob_shield_max_log > NumScript.ZERO

	_lbl_toll_status.text = "下一门槛: 第 %d 层  |  门票需求: %s\n当前可用净资: %s  |  托管储蓄: %s\n储蓄模式: %s  |  护盾词条: %s" % [
		gate_stage,
		NumScript.format_num(toll_log) if toll_log != NumScript.ZERO else "已全部缴清",
		NumScript.format_num(net_log),
		NumScript.format_num(state.toll_escrow),
		"开启 (自动攒门票)" if bool(st.get("saving", false)) else "未触发",
		"护盾激活" if has_shield else "无"
	]
	_toll_progress_bar.value = progress * 100.0
	var hint_txt: String = TollScript.get_hint_text(state)
	_lbl_toll_hint.text = hint_txt if not hint_txt.is_empty() else "当前无卡墙或储蓄提示，正常推进中。"

func _on_borrow_pressed() -> void:
	if _game_ref == null:
		return
	var state: SimStateScript = _game_ref.get_sim_state()
	if state == null or state.credit == null:
		return
	var stage: int = state.get_active_stage()
	var limit_log: float = state.credit.get_credit_limit_log(stage, state.balance)
	var borrow_log: float = NumScript.mul(limit_log, NumScript.from_float(_selected_util))
	_game_ref.request_borrow_credit(borrow_log)

func _on_repay_pressed() -> void:
	if _game_ref == null:
		return
	var state: SimStateScript = _game_ref.get_sim_state()
	if state == null:
		return
	_game_ref.request_repay_credit(state.debt_total)

func _is_node_queued(entries: Array, node_id: String) -> bool:
	for entry_raw: Variant in entries:
		var entry: Dictionary = entry_raw as Dictionary
		if str(entry.get("node_id", "")) == node_id:
			return true
	return false

func _refresh_prestige_tab(state: SimStateScript) -> void:
	var pv: Dictionary = state.get_soul_prestige_preview()
	var can_prestige: bool = bool(pv.get("can_prestige", false))
	var pending_log: float = float(pv.get("pending_souls_log", NumScript.ZERO))
	var after_log: float = float(pv.get("souls_after_log", NumScript.ZERO))
	var debt_add: float = float(pv.get("legacy_debt_added_minutes", 0.0))
	var debt_total: float = float(pv.get("legacy_debt_total_minutes", 0.0))
	var kept_eq: int = int(pv.get("kept_equipped_count", 0))

	_lbl_prestige_preview.text = "【灵魂转生】本轮: 第 %d 层 | 灵魂: +%s (后 %s)\n宿债: +%.1f 分 (累计 %.1f 分) | 保留装备: %d/6 件" % [
		state.run_best,
		NumScript.format_num(pending_log),
		NumScript.format_num(after_log),
		debt_add,
		debt_total,
		kept_eq
	]
	_btn_prestige.disabled = not can_prestige

	# 深渊转生状态
	var apv: Dictionary = state.get_abyss_prestige_preview()
	var can_abyss: bool = bool(apv.get("can_prestige", false))
	var p_marks: int = int(apv.get("pending_marks", 0))
	var marks_after: int = int(apv.get("marks_after", state.marks))
	var max_slots_after: int = int(apv.get("max_vault_slots_after", state.get_max_vault_slots()))
	var extractable: Array = apv.get("extractable_affix_ids", []) as Array

	_lbl_abyss_preview.text = "【深渊印记】当前印记: %d | 预计可得: +%d (后 %d)\n永久威能槽位: %d / %d (转生后 %d 槽)\n可萃取词条: %d 个" % [
		state.marks,
		p_marks,
		marks_after,
		state.vault_powers.size(),
		state.get_max_vault_slots(),
		max_slots_after,
		extractable.size()
	]
	_btn_abyss_prestige.disabled = not can_abyss
	if not _selected_extract_power.is_empty():
		_btn_abyss_prestige.text = "深渊印记转生 (萃取: %s)" % _selected_extract_power
	else:
		_btn_abyss_prestige.text = "深渊印记转生 (萃取选中词条)"

	# 刷新可萃取词条选择栏
	if _extract_picker_box != null:
		for ch_ex: Node in _extract_picker_box.get_children():
			ch_ex.queue_free()
		if extractable.is_empty():
			var no_ex_lbl: Label = Label.new()
			no_ex_lbl.text = "当前背包/穿戴暂无新暗金词条可萃取"
			no_ex_lbl.add_theme_font_size_override("font_size", 9)
			no_ex_lbl.add_theme_color_override("font_color", ThemePaletteScript.color_ash_gray())
			_extract_picker_box.add_child(no_ex_lbl)
		else:
			if _selected_extract_power.is_empty() or not extractable.has(_selected_extract_power):
				_selected_extract_power = str(extractable[0])
			var pick_row: HBoxContainer = HBoxContainer.new()
			pick_row.add_theme_constant_override("separation", 4)
			_extract_picker_box.add_child(pick_row)
			for ex_id_var: Variant in extractable:
				var ex_id: String = str(ex_id_var)
				var ex_btn: Button = Button.new()
				ex_btn.text = ("[✓] " if ex_id == _selected_extract_power else "") + "萃取 " + ex_id
				ex_btn.custom_minimum_size = Vector2(0.0, 20.0)
				ex_btn.add_theme_font_size_override("font_size", 9)
				var is_chosen: bool = (ex_id == _selected_extract_power)
				ex_btn.add_theme_color_override(
					"font_color",
					ThemePaletteScript.color_old_gold_bright() if is_chosen else ThemePaletteScript.color_bone_white()
				)
				ex_btn.pressed.connect(_on_select_extract_affix_pressed.bind(ex_id))
				pick_row.add_child(ex_btn)

	# 刷新威能槽
	for ch: Node in _vault_slots_box.get_children():
		ch.queue_free()
	var cur_slots: int = state.get_max_vault_slots()
	for s_idx: int in range(cur_slots):
		var p_btn: Button = Button.new()
		p_btn.custom_minimum_size = Vector2(70.0, 22.0)
		p_btn.add_theme_font_size_override("font_size", 9)
		if s_idx < state.vault_powers.size():
			var aff_id: String = state.vault_powers[s_idx]
			p_btn.text = "槽%d: %s [卸]" % [s_idx + 1, aff_id]
			p_btn.add_theme_color_override("font_color", ThemePaletteScript.color_old_gold_bright())
			p_btn.pressed.connect(_on_unequip_vault_power_pressed.bind(aff_id))
		else:
			p_btn.text = "槽%d: [空]" % (s_idx + 1)
			p_btn.add_theme_color_override("font_color", ThemePaletteScript.color_ash_gray())
			p_btn.disabled = true
		_vault_slots_box.add_child(p_btn)

	# 刷新已解锁但未装配的威能列表
	for ch2: Node in _unlocked_powers_box.get_children():
		ch2.queue_free()
	for un_id: String in state.unlocked_vault_powers:
		if not state.vault_powers.has(un_id):
			var u_row: HBoxContainer = HBoxContainer.new()
			var u_lbl: Label = Label.new()
			u_lbl.text = "已萃取: %s" % un_id
			u_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			u_lbl.add_theme_font_size_override("font_size", 10)
			u_lbl.add_theme_color_override("font_color", ThemePaletteScript.color_bone_white())
			u_row.add_child(u_lbl)
			var eq_btn: Button = Button.new()
			eq_btn.text = "装配"
			eq_btn.custom_minimum_size = Vector2(40.0, 20.0)
			eq_btn.add_theme_font_size_override("font_size", 9)
			eq_btn.disabled = state.vault_powers.size() >= state.get_max_vault_slots()
			eq_btn.pressed.connect(_on_equip_vault_power_pressed.bind(un_id))
			u_row.add_child(eq_btn)
			_unlocked_powers_box.add_child(u_row)

	var off: Dictionary = _game_ref.get_last_offline_summary()
	if not off.is_empty() and bool(off.get("loaded", false)):
		var eff_s: float = float(off.get("effective_seconds", 0.0))
		var g_log: float = float(off.get("gold_gain_log", NumScript.ZERO))
		_lbl_offline_summary.text = "最近离线结算: %.0fs · 金币 +%s" % [eff_s, NumScript.format_num(g_log)]
	else:
		_lbl_offline_summary.text = "自动存档已就绪（退出/每 30 秒原子保存）"

func _on_select_extract_affix_pressed(affix_id: String) -> void:
	_selected_extract_power = affix_id
	refresh_view()

func _on_abyss_prestige_pressed() -> void:
	if _game_ref != null:
		var state: SimStateScript = _game_ref.get_sim_state()
		var p_id: String = _selected_extract_power
		if state != null and p_id.is_empty():
			var ext: Array[String] = state.collect_extractable_affix_ids()
			for cand: String in ext:
				if not state.unlocked_vault_powers.has(cand):
					p_id = cand
					break
			if p_id.is_empty() and not ext.is_empty():
				p_id = ext[0]
		_game_ref.request_abyss_prestige(p_id)

func _on_equip_vault_power_pressed(affix_id: String) -> void:
	if _game_ref != null:
		_game_ref.request_equip_vault_power(affix_id)

func _on_unequip_vault_power_pressed(affix_id: String) -> void:
	if _game_ref != null:
		_game_ref.request_unequip_vault_power(affix_id)

func _on_prestige_pressed() -> void:
	if _game_ref != null:
		_game_ref.request_soul_prestige()

func _on_research_node_pressed(node_id: String) -> void:
	if _game_ref != null:
		_game_ref.request_start_research(node_id)
