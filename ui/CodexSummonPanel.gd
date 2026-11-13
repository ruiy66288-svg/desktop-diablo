class_name CodexSummonPanel extends PanelContainer

## 《桌面破坏神》永久图鉴、稀有 Boss 召唤房与幻化抽屉 (依据《02_系统架构与数值_v6.md》§8.1–§8.4、Q33–Q34 与 WP-P2-UI-2)
## 铁律：
## 1. 100% 显式静态类型，零 :=
## 2. 严格只读访问 SimState；一切操作经 Game.request_* 走 Command 队列
## 3. 严格遵守「镀金债契 · 骨白版画」HEX 色板与 360×480 布局约束

const GameScript = preload("res://autoload/Game.gd")
const SimStateScript = preload("res://simulation/SimState.gd")
const CodexScript = preload("res://persistence/Codex.gd")
const SetDetectorScript = preload("res://simulation/collection/SetDetector.gd")
const SetDefScript = preload("res://simulation/collection/SetDef.gd")
const ThemePaletteScript = preload("res://ui/ThemePalette.gd")
const ArtRegistryScript = preload("res://ui/ArtRegistry.gd")
const NumScript = preload("res://core/num/Num.gd")

enum TabKind {
	CODEX_SETS = 0,
	SUMMON_ARCHON = 1,
	COSMETICS_TRANSMOG = 2
}

var _game_ref: GameScript = null
var _active_tab: int = TabKind.CODEX_SETS

var _btn_tab_codex: Button = null
var _btn_tab_summon: Button = null
var _btn_tab_transmog: Button = null
var _content_box: VBoxContainer = null

# 1. 图鉴 · 套装页
var _codex_view: VBoxContainer = null
var _lbl_codex_summary: Label = null
var _sets_list: VBoxContainer = null

# 2. 召唤 · 执政官页
var _summon_view: VBoxContainer = null
var _lbl_summon_status: Label = null
var _btn_summon_boss: Button = null
var _btn_abort_boss: Button = null

# 3. 外观 · 幻化页
var _transmog_view: VBoxContainer = null
var _lbl_transmog_status: Label = null
var _transmog_options_box: VBoxContainer = null

func _init() -> void:
	name = "CodexSummonPanel"
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
		_active_tab = clampi(tab_idx, TabKind.CODEX_SETS, TabKind.COSMETICS_TRANSMOG)
		_sync_tab_visibility()
	visible = true
	refresh_view()

func close_drawer() -> void:
	visible = false

func get_active_tab() -> int:
	return _active_tab

func _build_ui() -> void:
	var root_vbox: VBoxContainer = VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 6)
	add_child(root_vbox)

	var header: HBoxContainer = HBoxContainer.new()
	header.add_theme_constant_override("separation", 4)
	root_vbox.add_child(header)

	_btn_tab_codex = _make_tab_button("图鉴·套装", TabKind.CODEX_SETS)
	_btn_tab_summon = _make_tab_button("召唤·首领", TabKind.SUMMON_ARCHON)
	_btn_tab_transmog = _make_tab_button("外观·幻化", TabKind.COSMETICS_TRANSMOG)
	header.add_child(_btn_tab_codex)
	header.add_child(_btn_tab_summon)
	header.add_child(_btn_tab_transmog)

	var close_btn: Button = Button.new()
	close_btn.name = "BtnCloseCodex"
	close_btn.text = "关闭"
	close_btn.custom_minimum_size = Vector2(44.0, 22.0)
	close_btn.add_theme_font_size_override("font_size", 11)
	close_btn.add_theme_color_override("font_color", ThemePaletteScript.color_bone_white())
	close_btn.pressed.connect(close_drawer)
	header.add_child(close_btn)

	_content_box = VBoxContainer.new()
	_content_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_vbox.add_child(_content_box)

	_build_codex_tab()
	_build_summon_tab()
	_build_transmog_tab()
	_sync_tab_visibility()

func _make_tab_button(title: String, tab_idx: int) -> Button:
	var btn: Button = Button.new()
	btn.text = title
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.custom_minimum_size = Vector2(0.0, 22.0)
	btn.add_theme_font_size_override("font_size", 10)
	btn.pressed.connect(_on_tab_selected.bind(tab_idx))
	return btn

func _on_tab_selected(tab_idx: int) -> void:
	_active_tab = tab_idx
	_sync_tab_visibility()
	refresh_view()

func _sync_tab_visibility() -> void:
	_codex_view.visible = (_active_tab == TabKind.CODEX_SETS)
	_summon_view.visible = (_active_tab == TabKind.SUMMON_ARCHON)
	_transmog_view.visible = (_active_tab == TabKind.COSMETICS_TRANSMOG)

	_btn_tab_codex.add_theme_color_override(
		"font_color",
		ThemePaletteScript.color_old_gold_bright() if _active_tab == TabKind.CODEX_SETS else ThemePaletteScript.color_bone_shadow()
	)
	_btn_tab_summon.add_theme_color_override(
		"font_color",
		ThemePaletteScript.color_old_gold_bright() if _active_tab == TabKind.SUMMON_ARCHON else ThemePaletteScript.color_bone_shadow()
	)
	_btn_tab_transmog.add_theme_color_override(
		"font_color",
		ThemePaletteScript.color_old_gold_bright() if _active_tab == TabKind.COSMETICS_TRANSMOG else ThemePaletteScript.color_bone_shadow()
	)

func _build_codex_tab() -> void:
	_codex_view = VBoxContainer.new()
	_codex_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_codex_view.add_theme_constant_override("separation", 6)
	_content_box.add_child(_codex_view)

	_lbl_codex_summary = Label.new()
	_lbl_codex_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lbl_codex_summary.add_theme_font_size_override("font_size", 10)
	_lbl_codex_summary.add_theme_color_override("font_color", ThemePaletteScript.color_bone_white())
	_codex_view.add_child(_lbl_codex_summary)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_codex_view.add_child(scroll)

	_sets_list = VBoxContainer.new()
	_sets_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sets_list.add_theme_constant_override("separation", 4)
	scroll.add_child(_sets_list)

func _build_summon_tab() -> void:
	_summon_view = VBoxContainer.new()
	_summon_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_summon_view.add_theme_constant_override("separation", 6)
	_content_box.add_child(_summon_view)

	var top_box: HBoxContainer = HBoxContainer.new()
	top_box.add_theme_constant_override("separation", 8)
	_summon_view.add_child(top_box)

	var rune_tex: Texture2D = ArtRegistryScript.get_summon_rune_texture()
	if rune_tex != null:
		var rune_rect: TextureRect = TextureRect.new()
		rune_rect.custom_minimum_size = Vector2(40.0, 40.0)
		rune_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rune_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		rune_rect.texture = rune_tex
		rune_rect.material = ArtRegistryScript.make_palette_material(ThemePaletteScript.color_old_gold_bright(), false, 1.0)
		top_box.add_child(rune_rect)

	_lbl_summon_status = Label.new()
	_lbl_summon_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lbl_summon_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lbl_summon_status.add_theme_font_size_override("font_size", 10)
	_lbl_summon_status.add_theme_color_override("font_color", ThemePaletteScript.color_bone_white())
	top_box.add_child(_lbl_summon_status)

	var hint_lbl: Label = Label.new()
	hint_lbl.text = "◆ 契约大执政官：专属 30s 极速试炼，击败必掉专属神话/外观；主动撤退或失败 100% 零损失返还符文。"
	hint_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint_lbl.add_theme_font_size_override("font_size", 9)
	hint_lbl.add_theme_color_override("font_color", ThemePaletteScript.color_bone_shadow())
	_summon_view.add_child(hint_lbl)

	var btn_row: HBoxContainer = HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 6)
	_summon_view.add_child(btn_row)

	_btn_summon_boss = Button.new()
	_btn_summon_boss.name = "BtnSummonBoss"
	_btn_summon_boss.text = "消耗 1 符文 · 召唤契约大执政官"
	_btn_summon_boss.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_btn_summon_boss.custom_minimum_size = Vector2(0.0, 26.0)
	_btn_summon_boss.add_theme_font_size_override("font_size", 11)
	_btn_summon_boss.pressed.connect(_on_summon_boss_pressed)
	btn_row.add_child(_btn_summon_boss)

	_btn_abort_boss = Button.new()
	_btn_abort_boss.name = "BtnAbortBoss"
	_btn_abort_boss.text = "主动撤退 (返还符文)"
	_btn_abort_boss.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_btn_abort_boss.custom_minimum_size = Vector2(0.0, 26.0)
	_btn_abort_boss.add_theme_font_size_override("font_size", 11)
	_btn_abort_boss.visible = false
	_btn_abort_boss.pressed.connect(_on_abort_boss_pressed)
	btn_row.add_child(_btn_abort_boss)

func _build_transmog_tab() -> void:
	_transmog_view = VBoxContainer.new()
	_transmog_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_transmog_view.add_theme_constant_override("separation", 6)
	_content_box.add_child(_transmog_view)

	_lbl_transmog_status = Label.new()
	_lbl_transmog_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lbl_transmog_status.add_theme_font_size_override("font_size", 10)
	_lbl_transmog_status.add_theme_color_override("font_color", ThemePaletteScript.color_bone_white())
	_transmog_view.add_child(_lbl_transmog_status)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_transmog_view.add_child(scroll)

	_transmog_options_box = VBoxContainer.new()
	_transmog_options_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_transmog_options_box.add_theme_constant_override("separation", 4)
	scroll.add_child(_transmog_options_box)

func refresh_view() -> void:
	if not visible or _game_ref == null:
		return
	var state: SimStateScript = _game_ref.get_sim_state()
	if state == null:
		return

	match _active_tab:
		TabKind.CODEX_SETS:
			_refresh_codex_tab(state)
		TabKind.SUMMON_ARCHON:
			_refresh_summon_tab(state)
		TabKind.COSMETICS_TRANSMOG:
			_refresh_transmog_tab(state)

func _refresh_codex_tab(state: SimStateScript) -> void:
	var c: CodexScript = state.ensure_codex()
	var bonus_pct: float = c.get_gold_bonus_pct(state.balance) * 100.0
	_lbl_codex_summary.text = "【永久图鉴】族群: %d/7 | 暗金: %d/12 | 套装: %d/3 | 外观: %d/4\n图鉴收益: 全局金币产出 +%.1f%% (转生永久保留)" % [
		c.monsters.size(),
		c.uniques.size(),
		c.sets.size(),
		c.cosmetics.size(),
		bonus_pct
	]

	for ch: Node in _sets_list.get_children():
		ch.queue_free()

	var all_sets: Array[SetDefScript] = SetDetectorScript.get_all_sets()
	var active_sets: Array[SetDefScript] = SetDetectorScript.detect_active_sets(state, c)

	for s_def: SetDefScript in all_sets:
		var is_active: bool = active_sets.has(s_def)
		var is_unlocked: bool = c.sets.has(s_def.id)

		var row: PanelContainer = PanelContainer.new()
		var sb: StyleBoxFlat = ThemePaletteScript.make_card_style(
			ThemePaletteScript.color_old_gold_bright() if is_active else ThemePaletteScript.color_iron_gray(),
			3,
			2 if is_active else 1
		)
		sb.content_margin_left = 6.0
		sb.content_margin_right = 6.0
		sb.content_margin_top = 4.0
		sb.content_margin_bottom = 4.0
		row.add_theme_stylebox_override("panel", sb)

		var vbox: VBoxContainer = VBoxContainer.new()
		row.add_child(vbox)

		var title_lbl: Label = Label.new()
		var status_str: String = "【已激活】" if is_active else ("【已收录】" if is_unlocked else "【未发现】")
		title_lbl.text = "%s %s" % [status_str, s_def.name_zh]
		title_lbl.add_theme_font_size_override("font_size", 10)
		title_lbl.add_theme_color_override(
			"font_color",
			ThemePaletteScript.color_old_gold_bright() if is_active else ThemePaletteScript.color_bone_white()
		)
		vbox.add_child(title_lbl)

		var desc_lbl: Label = Label.new()
		desc_lbl.text = "%s\n套装加成: %s" % [s_def.desc, str(s_def.bonus_stats)]
		desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_lbl.add_theme_font_size_override("font_size", 9)
		desc_lbl.add_theme_color_override("font_color", ThemePaletteScript.color_bone_shadow())
		vbox.add_child(desc_lbl)

		_sets_list.add_child(row)

func _refresh_summon_tab(state: SimStateScript) -> void:
	var c: CodexScript = state.ensure_codex()
	var runes: int = c.summon_runes
	var is_active: bool = state.is_rare_boss_active

	if is_active:
		var rem_s: float = maxf(0.0, 30.0 - state.rare_boss_timer)
		_lbl_summon_status.text = "【试炼进行中】\n目标: 契约大执政官 (30s 倒计时: %.1fs)\n主动撤退返还符文，击败必掉专属神话！" % rem_s
		_btn_summon_boss.visible = false
		_btn_abort_boss.visible = true
	else:
		_lbl_summon_status.text = "【深渊召唤台】\n当前召唤符文库存: %d 枚\n离线与在线均按时间概率获得，永不过期。" % runes
		_btn_summon_boss.visible = true
		_btn_abort_boss.visible = false
		_btn_summon_boss.disabled = (runes <= 0)
		_btn_summon_boss.text = "消耗 1 符文 · 召唤契约大执政官 (%d/1)" % runes

func _refresh_transmog_tab(state: SimStateScript) -> void:
	var c: CodexScript = state.ensure_codex()
	_lbl_transmog_status.text = "【已解锁外观/幻化】共 %d 件\n点击可为武器/饰品槽切换太古/具名木刻幻化外观。" % c.cosmetics.size()

	for ch: Node in _transmog_options_box.get_children():
		ch.queue_free()

	# 1. 武器槽幻化选项
	var w_cur: String = state.get_transmog("weapon")
	var w_row: HBoxContainer = HBoxContainer.new()
	w_row.add_theme_constant_override("separation", 4)
	var w_lbl: Label = Label.new()
	w_lbl.text = "武器幻化:"
	w_lbl.custom_minimum_size = Vector2(60.0, 0.0)
	w_lbl.add_theme_font_size_override("font_size", 9)
	w_lbl.add_theme_color_override("font_color", ThemePaletteScript.color_bone_white())
	w_row.add_child(w_lbl)

	var w_def_btn: Button = Button.new()
	w_def_btn.text = "[原版]" if w_cur.is_empty() else "原版"
	w_def_btn.custom_minimum_size = Vector2(48.0, 20.0)
	w_def_btn.add_theme_font_size_override("font_size", 9)
	w_def_btn.pressed.connect(_on_set_transmog_pressed.bind("weapon", ""))
	w_row.add_child(w_def_btn)

	var w_archon_btn: Button = Button.new()
	var has_archon_blade: bool = c.cosmetics.has("transmog_archon_blade")
	w_archon_btn.text = "[执政官巨刃]" if w_cur == "transmog_archon_blade" else "执政官巨刃"
	w_archon_btn.custom_minimum_size = Vector2(72.0, 20.0)
	w_archon_btn.add_theme_font_size_override("font_size", 9)
	w_archon_btn.disabled = not has_archon_blade
	w_archon_btn.pressed.connect(_on_set_transmog_pressed.bind("weapon", "transmog_archon_blade"))
	w_row.add_child(w_archon_btn)
	_transmog_options_box.add_child(w_row)

	# 2. 饰品槽幻化选项
	var t_cur: String = state.get_transmog("trinket")
	var t_row: HBoxContainer = HBoxContainer.new()
	t_row.add_theme_constant_override("separation", 4)
	var t_lbl: Label = Label.new()
	t_lbl.text = "饰品幻化:"
	t_lbl.custom_minimum_size = Vector2(60.0, 0.0)
	t_lbl.add_theme_font_size_override("font_size", 9)
	t_lbl.add_theme_color_override("font_color", ThemePaletteScript.color_bone_white())
	t_row.add_child(t_lbl)

	var t_def_btn: Button = Button.new()
	t_def_btn.text = "[原版]" if t_cur.is_empty() else "原版"
	t_def_btn.custom_minimum_size = Vector2(48.0, 20.0)
	t_def_btn.add_theme_font_size_override("font_size", 9)
	t_def_btn.pressed.connect(_on_set_transmog_pressed.bind("trinket", ""))
	t_row.add_child(t_def_btn)

	var t_scales_btn: Button = Button.new()
	t_scales_btn.text = "[高利贷天平]" if t_cur == "unique_trinket" else "高利贷天平"
	t_scales_btn.custom_minimum_size = Vector2(72.0, 20.0)
	t_scales_btn.add_theme_font_size_override("font_size", 9)
	t_scales_btn.pressed.connect(_on_set_transmog_pressed.bind("trinket", "unique_trinket"))
	t_row.add_child(t_scales_btn)
	_transmog_options_box.add_child(t_row)

func _on_summon_boss_pressed() -> void:
	if _game_ref != null:
		_game_ref.request_summon_rare_boss()
		refresh_view()

func _on_abort_boss_pressed() -> void:
	if _game_ref != null:
		_game_ref.request_abort_rare_boss()
		refresh_view()

func _on_set_transmog_pressed(slot_key: String, appearance_id: String) -> void:
	if _game_ref != null:
		_game_ref.request_set_transmog(slot_key, appearance_id)
		refresh_view()
