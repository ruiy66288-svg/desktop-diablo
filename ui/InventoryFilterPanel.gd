class_name InventoryFilterPanel extends PanelContainer

## 「行囊 · 过滤 · 属性」抽屉 (阶段 1.5 构筑交互面板)
## Tab 0 行囊: 24 格背包网格 (正式木刻图标/品质框/iLvl), 点选弹出干跑 Δ% + 一键穿戴 + 单件熔炼
## Tab 1 过滤: 保留品质 ≥ 白/蓝/紫/暗金/太古 按钮组 (经 Command 同步 SimState.filter) + 一键熔炼低阶
## Tab 2 属性: StatSheet 完整分解 (金币基础伤/装备平伤/加法区/暗金乘区/灵魂/深渊/暴击/攻速/MF_eff/净财富 W/血量倍率)
## 铁律: 100% 显式静态类型; 严格只读访问 SimState; 一切修改经 Game.submit_command / request_* 走 Command 队列

const GameScript = preload("res://autoload/Game.gd")
const SimStateScript = preload("res://simulation/SimState.gd")
const CommandScript = preload("res://simulation/commands/Command.gd")
const ItemInstanceScript = preload("res://simulation/loot/ItemInstance.gd")
const DryRunScript = preload("res://simulation/commands/DryRun.gd")
const ThemePaletteScript = preload("res://ui/ThemePalette.gd")
const ArtRegistryScript = preload("res://ui/ArtRegistry.gd")
const NumScript = preload("res://core/num/Num.gd")
const StatSheetScript = preload("res://simulation/StatSheet.gd")

enum TabKind {
	BACKPACK = 0,
	FILTER = 1,
	STATS = 2
}

const GRID_COLUMNS: int = 6
const CELL_SIZE: float = 46.0
const BAG_SLOTS: int = 24
const DRY_SEED: int = 987654321
const REFRESH_INTERVAL_SEC: float = 0.5

const RARITY_NAMES: Array[String] = ["白", "蓝", "紫", "暗金", "太古"]
const SLOT_LABELS: Dictionary = {
	"weapon": "武器", "helm": "头盔", "chest": "胸甲",
	"gloves": "手套", "boots": "战靴", "trinket": "饰品"
}

var _game_ref: GameScript = null
var _active_tab: int = TabKind.BACKPACK
var _selected_uid: int = -1
var _delta_cache: Dictionary = {}
var _refresh_accum: float = 0.0

var _btn_tab_bag: Button = null
var _btn_tab_filter: Button = null
var _btn_tab_stats: Button = null
var _view_bag: VBoxContainer = null
var _view_filter: VBoxContainer = null
var _view_stats: VBoxContainer = null

var _lbl_bag_count: Label = null
var _grid: GridContainer = null
var _cells: Array[Button] = []
var _cell_icons: Array[TextureRect] = []
var _cell_ilvl: Array[Label] = []
var _lbl_detail_name: Label = null
var _lbl_detail_info: Label = null
var _lbl_detail_delta: Label = null
var _btn_equip: Button = null
var _btn_smelt: Button = null

var _lbl_filter_current: Label = null
var _filter_buttons: Array[Button] = []
var _lbl_filter_preview: Label = null
var _btn_smelt_low: Button = null

var _stat_value_labels: Dictionary = {}

const STAT_ROWS: Array = [
	["base", "金币基础伤"],
	["gear", "6 槽装备平伤"],
	["additive", "加法区 %"],
	["unique", "暗金独立乘区"],
	["soul", "灵魂加成"],
	["abyss", "深渊印记指数"],
	["crit_rate", "暴击率"],
	["crit_mult", "暴击伤害"],
	["speed", "攻击速度"],
	["mf", "魔法发现 MF → MF_eff"],
	["wealth", "净财富 W"],
	["pressure", "血量倍率 Δh_wealth"]
]

func _init() -> void:
	name = "InventoryFilterPanel"
	position = Vector2(16.0, 56.0)
	size = Vector2(328.0, 336.0)
	visible = false
	z_index = 26

	var sb: StyleBoxFlat = ThemePaletteScript.make_card_style(ThemePaletteScript.color_old_gold(), 4, 1)
	sb.content_margin_left = 10.0
	sb.content_margin_right = 10.0
	sb.content_margin_top = 8.0
	sb.content_margin_bottom = 8.0
	add_theme_stylebox_override("panel", sb)
	_build_ui()

func _process(delta: float) -> void:
	if not visible:
		return
	_refresh_accum += delta
	if _refresh_accum >= REFRESH_INTERVAL_SEC:
		_refresh_accum = 0.0
		refresh_view()

func bind_game(p_game: GameScript) -> void:
	_game_ref = p_game

func open_tab(tab_idx: int = -1) -> void:
	if tab_idx >= 0:
		_active_tab = clampi(tab_idx, TabKind.BACKPACK, TabKind.STATS)
	_sync_tab_visibility()
	visible = true
	refresh_view()

func close_drawer() -> void:
	visible = false

func get_active_tab() -> int:
	return _active_tab

func get_selected_uid() -> int:
	return _selected_uid

func get_cell_count() -> int:
	return _cells.size()

func get_stat_text(key: String) -> String:
	var lbl: Label = _stat_value_labels.get(key, null) as Label
	return lbl.text if lbl != null else ""

func get_filter_button_count() -> int:
	return _filter_buttons.size()

func get_low_smelt_candidates() -> Array[int]:
	var out: Array[int] = []
	if _game_ref == null:
		return out
	var state: SimStateScript = _game_ref.get_sim_state()
	if state == null or state.filter == null:
		return out
	var threshold: int = state.filter.get_threshold()
	for i: int in range(state.inventory.get_count()):
		var it: ItemInstanceScript = state.inventory.get_item_at(i)
		if it != null and int(it.rarity) < threshold:
			out.push_back(it.uid)
	return out

# ------------------------------------------------------------------ 构建 UI

func _build_ui() -> void:
	var root: VBoxContainer = VBoxContainer.new()
	root.add_theme_constant_override("separation", 6)
	add_child(root)

	var header: HBoxContainer = HBoxContainer.new()
	header.add_theme_constant_override("separation", 4)
	root.add_child(header)

	_btn_tab_bag = _make_tab_button("行囊", TabKind.BACKPACK)
	_btn_tab_filter = _make_tab_button("过滤", TabKind.FILTER)
	_btn_tab_stats = _make_tab_button("属性", TabKind.STATS)
	header.add_child(_btn_tab_bag)
	header.add_child(_btn_tab_filter)
	header.add_child(_btn_tab_stats)

	var spacer: Control = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)

	var btn_close: Button = Button.new()
	btn_close.name = "BtnCloseInventory"
	btn_close.text = "关闭"
	btn_close.focus_mode = Control.FOCUS_NONE
	btn_close.custom_minimum_size = Vector2(44.0, 22.0)
	btn_close.add_theme_font_size_override("font_size", 11)
	btn_close.add_theme_color_override("font_color", ThemePaletteScript.color_bone_white())
	btn_close.pressed.connect(close_drawer)
	header.add_child(btn_close)

	_build_bag_view(root)
	_build_filter_view(root)
	_build_stats_view(root)
	_sync_tab_visibility()

func _make_tab_button(text: String, tab_idx: int) -> Button:
	var b: Button = Button.new()
	b.name = "InvTab_%d" % tab_idx
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(48.0, 22.0)
	b.add_theme_font_size_override("font_size", 11)
	b.pressed.connect(open_tab.bind(tab_idx))
	return b

func _build_bag_view(root: VBoxContainer) -> void:
	_view_bag = VBoxContainer.new()
	_view_bag.name = "BagView"
	_view_bag.add_theme_constant_override("separation", 4)
	root.add_child(_view_bag)

	_lbl_bag_count = Label.new()
	_lbl_bag_count.text = "背包 0/24"
	_lbl_bag_count.add_theme_font_size_override("font_size", 11)
	_lbl_bag_count.add_theme_color_override("font_color", ThemePaletteScript.color_bone_shadow())
	_view_bag.add_child(_lbl_bag_count)

	_grid = GridContainer.new()
	_grid.columns = GRID_COLUMNS
	_grid.add_theme_constant_override("h_separation", 4)
	_grid.add_theme_constant_override("v_separation", 4)
	_view_bag.add_child(_grid)

	for i: int in range(BAG_SLOTS):
		var cell: Button = Button.new()
		cell.name = "BagCell_%d" % i
		cell.custom_minimum_size = Vector2(CELL_SIZE, CELL_SIZE)
		cell.focus_mode = Control.FOCUS_NONE
		cell.clip_contents = true
		cell.pressed.connect(_on_cell_pressed.bind(i))
		_grid.add_child(cell)

		var icon: TextureRect = TextureRect.new()
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.position = Vector2(8.0, 4.0)
		icon.size = Vector2(30.0, 30.0)
		icon.material = ArtRegistryScript.make_palette_material(Color.WHITE, false, 1.0)
		icon.visible = false
		cell.add_child(icon)

		var lv: Label = Label.new()
		lv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lv.position = Vector2(2.0, 30.0)
		lv.size = Vector2(CELL_SIZE - 4.0, 14.0)
		lv.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lv.add_theme_font_size_override("font_size", 9)
		lv.add_theme_color_override("font_color", ThemePaletteScript.color_bone_shadow())
		cell.add_child(lv)

		_cells.push_back(cell)
		_cell_icons.push_back(icon)
		_cell_ilvl.push_back(lv)

	var detail: PanelContainer = PanelContainer.new()
	var dsb: StyleBoxFlat = ThemePaletteScript.make_card_style(ThemePaletteScript.color_iron_gray(), 3, 1)
	dsb.content_margin_left = 6.0
	dsb.content_margin_right = 6.0
	dsb.content_margin_top = 4.0
	dsb.content_margin_bottom = 4.0
	detail.add_theme_stylebox_override("panel", dsb)
	_view_bag.add_child(detail)

	var dv: VBoxContainer = VBoxContainer.new()
	dv.add_theme_constant_override("separation", 2)
	detail.add_child(dv)

	_lbl_detail_name = Label.new()
	_lbl_detail_name.text = "点选背包装备查看干跑对比"
	_lbl_detail_name.add_theme_font_size_override("font_size", 11)
	_lbl_detail_name.add_theme_color_override("font_color", ThemePaletteScript.color_bone_white())
	dv.add_child(_lbl_detail_name)

	_lbl_detail_info = Label.new()
	_lbl_detail_info.add_theme_font_size_override("font_size", 10)
	_lbl_detail_info.add_theme_color_override("font_color", ThemePaletteScript.color_bone_shadow())
	_lbl_detail_info.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	_lbl_detail_info.custom_minimum_size = Vector2(290.0, 0.0)
	dv.add_child(_lbl_detail_info)

	var drow: HBoxContainer = HBoxContainer.new()
	drow.add_theme_constant_override("separation", 6)
	dv.add_child(drow)

	_lbl_detail_delta = Label.new()
	_lbl_detail_delta.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lbl_detail_delta.add_theme_font_size_override("font_size", 11)
	drow.add_child(_lbl_detail_delta)

	_btn_equip = Button.new()
	_btn_equip.name = "BtnInvEquip"
	_btn_equip.text = "穿戴"
	_btn_equip.focus_mode = Control.FOCUS_NONE
	_btn_equip.custom_minimum_size = Vector2(44.0, 22.0)
	_btn_equip.add_theme_font_size_override("font_size", 11)
	_btn_equip.pressed.connect(_on_equip_pressed)
	drow.add_child(_btn_equip)

	_btn_smelt = Button.new()
	_btn_smelt.name = "BtnInvSmelt"
	_btn_smelt.text = "熔炼"
	_btn_smelt.focus_mode = Control.FOCUS_NONE
	_btn_smelt.custom_minimum_size = Vector2(44.0, 22.0)
	_btn_smelt.add_theme_font_size_override("font_size", 11)
	_btn_smelt.pressed.connect(_on_smelt_pressed)
	drow.add_child(_btn_smelt)

func _build_filter_view(root: VBoxContainer) -> void:
	_view_filter = VBoxContainer.new()
	_view_filter.name = "FilterView"
	_view_filter.add_theme_constant_override("separation", 8)
	root.add_child(_view_filter)

	var title: Label = Label.new()
	title.text = "保留品质 ≥ (低于阈值的掉落自动熔炼为金币)"
	title.add_theme_font_size_override("font_size", 11)
	title.add_theme_color_override("font_color", ThemePaletteScript.color_old_gold_bright())
	_view_filter.add_child(title)

	_lbl_filter_current = Label.new()
	_lbl_filter_current.add_theme_font_size_override("font_size", 11)
	_lbl_filter_current.add_theme_color_override("font_color", ThemePaletteScript.color_bone_white())
	_view_filter.add_child(_lbl_filter_current)

	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	_view_filter.add_child(row)
	for r: int in range(RARITY_NAMES.size()):
		var fb: Button = Button.new()
		fb.name = "FilterBtn_%d" % r
		fb.text = "≥ " + RARITY_NAMES[r]
		fb.focus_mode = Control.FOCUS_NONE
		fb.custom_minimum_size = Vector2(56.0, 28.0)
		fb.add_theme_font_size_override("font_size", 11)
		fb.pressed.connect(_on_filter_pressed.bind(r))
		row.add_child(fb)
		_filter_buttons.push_back(fb)

	_lbl_filter_preview = Label.new()
	_lbl_filter_preview.add_theme_font_size_override("font_size", 11)
	_lbl_filter_preview.add_theme_color_override("font_color", ThemePaletteScript.color_bone_shadow())
	_lbl_filter_preview.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	_lbl_filter_preview.custom_minimum_size = Vector2(300.0, 0.0)
	_view_filter.add_child(_lbl_filter_preview)

	_btn_smelt_low = Button.new()
	_btn_smelt_low.name = "BtnSmeltLow"
	_btn_smelt_low.text = "一键熔炼低阶背包装备"
	_btn_smelt_low.focus_mode = Control.FOCUS_NONE
	_btn_smelt_low.custom_minimum_size = Vector2(0.0, 28.0)
	_btn_smelt_low.add_theme_font_size_override("font_size", 12)
	_btn_smelt_low.add_theme_color_override("font_color", ThemePaletteScript.color_old_gold_bright())
	_btn_smelt_low.pressed.connect(smelt_low_tier_items)
	_view_filter.add_child(_btn_smelt_low)

func _build_stats_view(root: VBoxContainer) -> void:
	_view_stats = VBoxContainer.new()
	_view_stats.name = "StatsView"
	root.add_child(_view_stats)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(300.0, 270.0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_view_stats.add_child(scroll)

	var gridv: GridContainer = GridContainer.new()
	gridv.columns = 2
	gridv.add_theme_constant_override("h_separation", 10)
	gridv.add_theme_constant_override("v_separation", 5)
	scroll.add_child(gridv)

	for row: Array in STAT_ROWS:
		var key: String = str(row[0])
		var kl: Label = Label.new()
		kl.text = str(row[1])
		kl.custom_minimum_size = Vector2(146.0, 0.0)
		kl.add_theme_font_size_override("font_size", 11)
		kl.add_theme_color_override("font_color", ThemePaletteScript.color_bone_shadow())
		gridv.add_child(kl)
		var vl: Label = Label.new()
		vl.text = "-"
		vl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		vl.add_theme_font_size_override("font_size", 11)
		vl.add_theme_color_override("font_color", ThemePaletteScript.color_bone_white())
		gridv.add_child(vl)
		_stat_value_labels[key] = vl

func _sync_tab_visibility() -> void:
	if _view_bag != null:
		_view_bag.visible = (_active_tab == TabKind.BACKPACK)
	if _view_filter != null:
		_view_filter.visible = (_active_tab == TabKind.FILTER)
	if _view_stats != null:
		_view_stats.visible = (_active_tab == TabKind.STATS)
	var tabs: Array[Button] = [_btn_tab_bag, _btn_tab_filter, _btn_tab_stats]
	for i: int in range(tabs.size()):
		var b: Button = tabs[i]
		if b == null:
			continue
		var on: bool = (i == _active_tab)
		b.add_theme_color_override(
			"font_color",
			ThemePaletteScript.color_old_gold_bright() if on else ThemePaletteScript.color_bone_shadow()
		)
		var border: Color = ThemePaletteScript.color_old_gold() if on else ThemePaletteScript.color_iron_gray()
		b.add_theme_stylebox_override("normal", ThemePaletteScript.make_button_style(ThemePaletteScript.color_card_bg(), border, 3))
		b.add_theme_stylebox_override("hover", ThemePaletteScript.make_button_style(ThemePaletteScript.color_card_bg(), ThemePaletteScript.color_old_gold_bright(), 3))

# ------------------------------------------------------------------ 刷新 (只读 SimState)

func refresh_view() -> void:
	if _game_ref == null:
		return
	var state: SimStateScript = _game_ref.get_sim_state()
	if state == null:
		return
	match _active_tab:
		TabKind.BACKPACK:
			_refresh_bag(state)
		TabKind.FILTER:
			_refresh_filter(state)
		TabKind.STATS:
			_refresh_stats(state)

func _refresh_bag(state: SimStateScript) -> void:
	var count: int = state.inventory.get_count()
	_lbl_bag_count.text = "背包 %d/%d" % [count, state.balance.inventory_max_slots]
	var selected_alive: bool = false
	for i: int in range(BAG_SLOTS):
		var cell: Button = _cells[i]
		var icon: TextureRect = _cell_icons[i]
		var lv: Label = _cell_ilvl[i]
		var item: ItemInstanceScript = state.inventory.get_item_at(i) if i < count else null
		if item == null:
			icon.visible = false
			lv.text = ""
			cell.tooltip_text = ""
			var empty_sb: StyleBoxFlat = ThemePaletteScript.make_card_style(ThemePaletteScript.color_iron_gray(), 3, 1)
			cell.add_theme_stylebox_override("normal", empty_sb)
			cell.add_theme_stylebox_override("hover", empty_sb)
			cell.add_theme_stylebox_override("pressed", empty_sb)
			continue
		var rar: int = int(item.rarity)
		var rc: Color = ThemePaletteScript.get_rarity_color(rar)
		var is_sel: bool = (item.uid == _selected_uid)
		if is_sel:
			selected_alive = true
		var bw: int = 2 if (rar >= 3 or is_sel) else 1
		var border: Color = ThemePaletteScript.color_old_gold_bright() if is_sel else rc
		cell.add_theme_stylebox_override("normal", ThemePaletteScript.make_card_style(border, 3, bw))
		cell.add_theme_stylebox_override("hover", ThemePaletteScript.make_card_style(rc.lerp(ThemePaletteScript.color_old_gold_bright(), 0.5), 3, 2))
		cell.add_theme_stylebox_override("pressed", ThemePaletteScript.make_card_style(ThemePaletteScript.color_old_gold_bright(), 3, 2))
		var slot_key: String = ItemInstanceScript.get_slot_key(item.slot)
		icon.texture = ArtRegistryScript.get_item_icon_texture(slot_key)
		icon.visible = (icon.texture != null)
		var mat: ShaderMaterial = icon.material as ShaderMaterial
		if mat != null:
			mat.set_shader_parameter("color_family", rc)
			mat.set_shader_parameter("enable_outline", rar >= 3)
		lv.text = "Lv.%d" % item.ilvl
		cell.tooltip_text = "%s Lv.%d" % [item.name, item.ilvl]
	if not selected_alive:
		_selected_uid = -1
	_refresh_detail(state)

func _refresh_detail(state: SimStateScript) -> void:
	var sel: ItemInstanceScript = state.inventory.find_item_by_uid(_selected_uid) if _selected_uid >= 0 else null
	if sel == null:
		_lbl_detail_name.text = "点选背包装备查看干跑对比"
		_lbl_detail_name.add_theme_color_override("font_color", ThemePaletteScript.color_bone_shadow())
		_lbl_detail_info.text = ""
		_lbl_detail_delta.text = ""
		_btn_equip.disabled = true
		_btn_smelt.disabled = true
		return
	var slot_key: String = ItemInstanceScript.get_slot_key(sel.slot)
	var rar: int = int(sel.rarity)
	_lbl_detail_name.text = "%s · %s Lv.%d" % [
		RARITY_NAMES[clampi(rar, 0, 4)] + "装", str(SLOT_LABELS.get(slot_key, slot_key)), sel.ilvl
	]
	_lbl_detail_name.add_theme_color_override("font_color", ThemePaletteScript.get_rarity_color(rar))
	_lbl_detail_info.text = _build_affix_summary(sel)
	if not _delta_cache.has(sel.uid):
		var res: Dictionary = DryRunScript.evaluate_candidate(state, sel, DRY_SEED)
		_delta_cache[sel.uid] = float(res.get("delta_pct", 0.0))
	var dp: float = float(_delta_cache[sel.uid])
	if dp > 0.05:
		_lbl_detail_delta.text = "干跑 30s Δ +%.1f%%" % dp
		_lbl_detail_delta.add_theme_color_override("font_color", ThemePaletteScript.color_old_gold_bright())
	elif dp < -0.05:
		_lbl_detail_delta.text = "干跑 30s Δ %.1f%%" % dp
		_lbl_detail_delta.add_theme_color_override("font_color", Color.html("#B84A39"))
	else:
		_lbl_detail_delta.text = "干跑 30s Δ 0.0%"
		_lbl_detail_delta.add_theme_color_override("font_color", ThemePaletteScript.color_ash_gray())
	_btn_equip.disabled = false
	_btn_smelt.disabled = false

static func _affix_label(a: Variant) -> String:
	if a is Dictionary:
		var d: Dictionary = a as Dictionary
		for k: String in ["display_name", "name_zh", "affix_id", "id"]:
			if d.has(k) and not str(d[k]).is_empty():
				return str(d[k])
		return str(d)
	if a is Object:
		var o: Object = a as Object
		for k2: String in ["display_name", "name_zh", "affix_id", "id"]:
			var v: Variant = o.get(k2)
			if v != null and str(v) != "":
				return str(v)
	return str(a)

static func _build_affix_summary(item: ItemInstanceScript) -> String:
	var parts: PackedStringArray = PackedStringArray()
	parts.push_back("评分 %.1f" % item.score)
	if item.additive_pct > 0.0:
		parts.push_back("加法 +%.0f%%" % (item.additive_pct * 100.0))
	if item.unique_mult > 1.0:
		parts.push_back("独立乘区 ×%.2f" % item.unique_mult)
	if item.affixes.size() > 0:
		var names: PackedStringArray = PackedStringArray()
		for a: Variant in item.affixes:
			names.push_back(_affix_label(a))
		parts.push_back("词条: " + " / ".join(names))
	else:
		parts.push_back("无特效词条")
	return " · ".join(parts)

func _refresh_filter(state: SimStateScript) -> void:
	var threshold: int = state.filter.get_threshold()
	_lbl_filter_current.text = "当前: 保留 ≥ %s (白/蓝/紫/暗金/太古)" % RARITY_NAMES[clampi(threshold, 0, 4)]
	for r: int in range(_filter_buttons.size()):
		var b: Button = _filter_buttons[r]
		var on: bool = (r == threshold)
		var rc: Color = ThemePaletteScript.get_rarity_color(r)
		b.add_theme_color_override("font_color", rc)
		b.add_theme_stylebox_override(
			"normal",
			ThemePaletteScript.make_button_style(ThemePaletteScript.color_card_bg(), rc if on else ThemePaletteScript.color_iron_gray(), 3)
		)
		b.add_theme_stylebox_override(
			"hover",
			ThemePaletteScript.make_button_style(ThemePaletteScript.color_card_bg(), ThemePaletteScript.color_old_gold_bright(), 3)
		)
	var cands: Array[int] = get_low_smelt_candidates()
	_lbl_filter_preview.text = "背包内低于阈值的装备 %d 件, 一键熔炼将按原价折算为金币 (走 Command 队列)" % cands.size()
	_btn_smelt_low.disabled = cands.is_empty()

func _refresh_stats(state: SimStateScript) -> void:
	var st: StatSheetScript = state.stats
	if st == null:
		return
	_set_stat("base", NumScript.format_num(st.base_gold_atk_log))
	_set_stat("gear", NumScript.format_num(st.gear_flat_atk_log))
	_set_stat("additive", "+%.1f%%" % (st.additive_percent * 100.0))
	_set_stat("unique", "×" + NumScript.format_num(st.unique_mults_sum_log))
	_set_stat("soul", "×" + NumScript.format_num(st.soul_mult_log))
	_set_stat("abyss", "印记 %d · ×%s" % [state.marks, NumScript.format_num(st.abyss_mult_log)])
	_set_stat("crit_rate", "%.1f%%" % (st.get_effective_crit_rate() * 100.0))
	_set_stat("crit_mult", "×%.2f" % st.crit_mult)
	_set_stat("speed", "%.2f 次/秒" % (1.0 / maxf(0.01, st.atk_interval)))
	_set_stat("mf", "%.0f → %.1f" % [st.magic_find, state.balance.get_effective_mf(st.magic_find)])
	_set_stat("wealth", state.wallet.format_net_wealth())
	_set_stat("pressure", "×%.2f" % state.get_wealth_hp_multiplier())
func _set_stat(key: String, text: String) -> void:
	var lbl: Label = _stat_value_labels.get(key, null) as Label
	if lbl != null:
		lbl.text = text

# ------------------------------------------------------------------ 交互 (全部经 Command 队列)

func select_slot_index(idx: int) -> void:
	_on_cell_pressed(idx)

func _on_cell_pressed(idx: int) -> void:
	if _game_ref == null:
		return
	var state: SimStateScript = _game_ref.get_sim_state()
	if state == null:
		return
	var item: ItemInstanceScript = state.inventory.get_item_at(idx) if idx < state.inventory.get_count() else null
	_selected_uid = item.uid if item != null else -1
	_refresh_bag(state)

func _on_equip_pressed() -> void:
	if _game_ref != null and _selected_uid >= 0:
		_game_ref.request_equip_uid(_selected_uid)
		_delta_cache.clear()
		_selected_uid = -1

func _on_smelt_pressed() -> void:
	if _game_ref != null and _selected_uid >= 0:
		_game_ref.request_smelt_uid(_selected_uid)
		_selected_uid = -1

func _on_filter_pressed(threshold: int) -> void:
	set_filter_threshold(threshold)

## 设置保留阈值 (Command: SET_FILTER_THRESHOLD)
func set_filter_threshold(threshold: int) -> void:
	if _game_ref == null:
		return
	_game_ref.submit_command(CommandScript.make_set_filter(clampi(threshold, 0, 4)))

## 一键熔炼低于阈值的背包装备 (逐件 SMELT_ITEM Command), 返回下发条数
func smelt_low_tier_items() -> int:
	if _game_ref == null:
		return 0
	var uids: Array[int] = get_low_smelt_candidates()
	for u: int in uids:
		_game_ref.request_smelt_uid(u)
	_selected_uid = -1
	return uids.size()
