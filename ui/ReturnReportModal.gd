class_name ReturnReportModal extends PanelContainer

## 《桌面破坏神》离线回归账本报告卡 (依据《02_系统架构与数值_v6.md》§3.4、§5.4、Q5 与 WP-P2-UI-2)
## 铁律：
## 1. 100% 显式静态类型，零 :=
## 2. 纯展示与交互回传，严禁写 SimState；点击收下战利品通知主窗口播放圣钟与战利品喷泉
## 3. 严格遵守「镀金债契 · 骨白版画」HEX 色板与 360×480 紧凑布局

const ThemePaletteScript = preload("res://ui/ThemePalette.gd")
const ArtRegistryScript = preload("res://ui/ArtRegistry.gd")
const NumScript = preload("res://core/num/Num.gd")

signal closed()
signal claimed(summary: Dictionary)

var _last_summary: Dictionary = {}

var _lbl_title: Label = null
var _btn_close: Button = null
var _tex_ledger: TextureRect = null
var _lbl_overview: Label = null
var _lbl_details: Label = null
var _lbl_drops: Label = null
var _btn_claim: Button = null

func _init() -> void:
	name = "ReturnReportModal"
	position = Vector2(24.0, 72.0)
	size = Vector2(312.0, 336.0)
	visible = false
	z_index = 32

	var panel_sb: StyleBoxFlat = ThemePaletteScript.make_card_style(
		ThemePaletteScript.color_old_gold_bright(),
		6,
		2
	)
	panel_sb.content_margin_left = 12.0
	panel_sb.content_margin_right = 12.0
	panel_sb.content_margin_top = 10.0
	panel_sb.content_margin_bottom = 10.0
	add_theme_stylebox_override("panel", panel_sb)

	_build_ui()

func _build_ui() -> void:
	var root_vbox: VBoxContainer = VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 8)
	add_child(root_vbox)

	# 1. 顶栏：标题 + 关闭按钮
	var header_hbox: HBoxContainer = HBoxContainer.new()
	header_hbox.add_theme_constant_override("separation", 6)
	root_vbox.add_child(header_hbox)

	_lbl_title = Label.new()
	_lbl_title.text = "◆ 离线回归清算账本"
	_lbl_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lbl_title.add_theme_font_size_override("font_size", 12)
	_lbl_title.add_theme_color_override("font_color", ThemePaletteScript.color_old_gold_bright())
	header_hbox.add_child(_lbl_title)

	_btn_close = Button.new()
	_btn_close.text = "×"
	_btn_close.custom_minimum_size = Vector2(22.0, 20.0)
	_btn_close.focus_mode = Control.FOCUS_NONE
	_btn_close.add_theme_font_size_override("font_size", 12)
	_btn_close.add_theme_color_override("font_color", ThemePaletteScript.color_bone_shadow())
	_btn_close.add_theme_stylebox_override(
		"normal",
		ThemePaletteScript.make_button_style(ThemePaletteScript.color_card_bg(), ThemePaletteScript.color_iron_gray(), 3)
	)
	_btn_close.pressed.connect(_on_close_pressed)
	header_hbox.add_child(_btn_close)

	# 2. 插画与宏观推进摘要
	var illu_hbox: HBoxContainer = HBoxContainer.new()
	illu_hbox.add_theme_constant_override("separation", 10)
	root_vbox.add_child(illu_hbox)

	_tex_ledger = TextureRect.new()
	_tex_ledger.custom_minimum_size = Vector2(56.0, 56.0)
	_tex_ledger.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_tex_ledger.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var ledger_img: Texture2D = _load_ledger_texture()
	if ledger_img != null:
		_tex_ledger.texture = ledger_img
	_tex_ledger.material = ArtRegistryScript.make_palette_material(ThemePaletteScript.color_old_gold_bright(), false, 1.0)
	illu_hbox.add_child(_tex_ledger)

	_lbl_overview = Label.new()
	_lbl_overview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lbl_overview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lbl_overview.add_theme_font_size_override("font_size", 11)
	_lbl_overview.add_theme_color_override("font_color", ThemePaletteScript.color_bone_white())
	illu_hbox.add_child(_lbl_overview)

	# 3. 详细收支账目面板
	var details_panel: PanelContainer = PanelContainer.new()
	var d_sb: StyleBoxFlat = ThemePaletteScript.make_card_style(
		ThemePaletteScript.color_iron_gray(),
		4,
		1
	)
	d_sb.content_margin_left = 8.0
	d_sb.content_margin_right = 8.0
	d_sb.content_margin_top = 6.0
	d_sb.content_margin_bottom = 6.0
	details_panel.add_theme_stylebox_override("panel", d_sb)
	root_vbox.add_child(details_panel)

	var details_vbox: VBoxContainer = VBoxContainer.new()
	details_vbox.add_theme_constant_override("separation", 4)
	details_panel.add_child(details_vbox)

	_lbl_details = Label.new()
	_lbl_details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lbl_details.add_theme_font_size_override("font_size", 10)
	_lbl_details.add_theme_color_override("font_color", ThemePaletteScript.color_bone_white())
	details_vbox.add_child(_lbl_details)

	# 4. 稀有掉落与符文收获
	_lbl_drops = Label.new()
	_lbl_drops.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lbl_drops.add_theme_font_size_override("font_size", 10)
	_lbl_drops.add_theme_color_override("font_color", ThemePaletteScript.color_coin_gold())
	root_vbox.add_child(_lbl_drops)

	# 5. 底部领取按钮
	_btn_claim = Button.new()
	_btn_claim.name = "BtnClaimReturnLoot"
	_btn_claim.text = "【收下战利品 · 鸣圣钟】"
	_btn_claim.custom_minimum_size = Vector2(0.0, 32.0)
	_btn_claim.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_btn_claim.add_theme_font_size_override("font_size", 11)
	_btn_claim.add_theme_color_override("font_color", ThemePaletteScript.color_card_bg())
	_btn_claim.add_theme_stylebox_override(
		"normal",
		ThemePaletteScript.make_button_style(
			ThemePaletteScript.color_old_gold_bright(),
			ThemePaletteScript.color_coin_gold(),
			4
		)
	)
	_btn_claim.pressed.connect(_on_claim_pressed)
	root_vbox.add_child(_btn_claim)

func show_report(summary: Dictionary) -> void:
	_last_summary = summary
	var elapsed_sec: float = float(summary.get("elapsed_seconds", 0.0))
	var effective_sec: float = float(summary.get("effective_seconds", elapsed_sec))
	var is_capped: bool = bool(summary.get("capped", false))
	var gain_log: float = float(summary.get("gold_gain_log", -INF))
	var stages_adv: int = int(summary.get("stages_advanced", 0))
	var debt_paid_log: float = float(summary.get("debt_repaid_log", -INF))
	var research_done: Array = summary.get("research_done", []) as Array
	var new_uniques: Array = summary.get("new_uniques", []) as Array
	var summon_runes: int = int(summary.get("new_summon_runes", 0))
	var r_after: int = int(summary.get("run_best_after", 0))

	# 格式化时间
	var time_str: String = _format_duration(elapsed_sec)
	var cap_notice: String = " (已达收益上限)" if is_capped else ""
	_lbl_overview.text = "离线经营清算契约\n离线时长: %s%s\n契约推进: +%d 层 (最高层: %d)" % [
		time_str,
		cap_notice,
		stages_adv,
		r_after
	]

	var gold_str: String = "0" if is_nan(gain_log) or is_inf(gain_log) else NumScript.format_num(gain_log)
	var debt_str: String = "0" if is_nan(debt_paid_log) or is_inf(debt_paid_log) else NumScript.format_num(debt_paid_log)
	_lbl_details.text = "◆ 经营账目结项：\n  • 金币毛收入: +%s\n  • 自动冲还债务: -%s\n  • 科技自动完工: %d 项" % [
		gold_str,
		debt_str,
		research_done.size()
	]

	var drop_lines: Array[String] = []
	if new_uniques.size() > 0:
		drop_lines.push_back("★ 斩获暗金装备: %d 件 (%s)" % [
			new_uniques.size(),
			", ".join(new_uniques.slice(0, mini(3, new_uniques.size())))
		])
	else:
		drop_lines.push_back("★ 斩获暗金装备: 0 件 (普通掉落已自动熔炼)")

	if summon_runes > 0:
		drop_lines.push_back("✦ 深渊召唤符文: +%d 枚 (已入库图鉴)" % summon_runes)
	else:
		drop_lines.push_back("✦ 深渊召唤符文: 0 枚")

	_lbl_drops.text = "\n".join(drop_lines)
	visible = true

func _on_claim_pressed() -> void:
	claimed.emit(_last_summary)
	visible = false
	closed.emit()

func _on_close_pressed() -> void:
	visible = false
	closed.emit()

func _format_duration(seconds: float) -> String:
	if seconds < 60.0:
		return "%.0f 秒" % maxf(1.0, seconds)
	var mins: int = int(floor(seconds / 60.0))
	if mins < 60:
		return "%d 分钟" % mins
	var hours: int = mins / 60
	var rem_mins: int = mins % 60
	return "%d 小时 %d 分" % [hours, rem_mins]

func _load_ledger_texture() -> Texture2D:
	return ArtRegistryScript.get_wealth_ledger_texture()
