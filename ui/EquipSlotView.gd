class_name EquipSlotView extends Button

## 48×48 六槽装备栏单元视图 (依据《03_美术风格圣经_v1.0.md》§02.1、§02.4 与 WP-09)
## 槽位固定：weapon / helm / chest / gloves / boots / trinket
## 接入 96×96 四通道木刻底材图标 + palette_subject.gdshader：
## 空槽显示低亮铁灰木刻剪影；已穿戴按品质色驱动点缀通道与边框，暗金加刻线光环，太古加绯红流动光环

const ThemePaletteScript = preload("res://ui/ThemePalette.gd")
const ArtRegistryScript = preload("res://ui/ArtRegistry.gd")

var slot_key: String = "weapon"
var has_equipped_item: bool = false
var item_rarity: int = -1
var item_ilvl: int = 0
var transmog_id: String = ""

var _icon_rect: TextureRect = null
var _icon_mat: ShaderMaterial = null
var _aura_phase: float = 0.0

func _ready() -> void:
	_ensure_icon_node()
	_refresh_slot_styles()

func _process(delta: float) -> void:
	if has_equipped_item and item_rarity >= 4:
		_aura_phase += delta * 3.2
		queue_redraw()

func _ensure_icon_node() -> void:
	if _icon_rect != null:
		return
	_icon_rect = TextureRect.new()
	_icon_rect.name = "SlotIconRect"
	_icon_rect.position = Vector2(5.0, 5.0)
	_icon_rect.size = Vector2(38.0, 38.0)
	_icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon_mat = ArtRegistryScript.make_palette_material(ThemePaletteScript.color_iron_gray(), false, 1.0)
	_icon_rect.material = _icon_mat
	add_child(_icon_rect)

func setup_slot(p_slot_key: String) -> void:
	slot_key = p_slot_key
	custom_minimum_size = Vector2(48.0, 48.0)
	size = Vector2(48.0, 48.0)
	text = ""
	focus_mode = Control.FOCUS_NONE
	_ensure_icon_node()
	_refresh_slot_styles()
	queue_redraw()

func set_item_state(p_equipped: bool, p_rarity: int = -1, p_ilvl: int = 0) -> void:
	_ensure_icon_node()
	var tex_missing: bool = (_icon_rect.texture == null)
	if not tex_missing and has_equipped_item == p_equipped and item_rarity == p_rarity and item_ilvl == p_ilvl:
		return
	has_equipped_item = p_equipped
	item_rarity = p_rarity
	item_ilvl = p_ilvl
	_refresh_slot_styles()
	queue_redraw()

func set_transmog_id(p_transmog_id: String) -> void:
	_ensure_icon_node()
	if transmog_id == p_transmog_id and _icon_rect.texture != null:
		return
	transmog_id = p_transmog_id
	_refresh_slot_styles()
	queue_redraw()

func has_formal_icon_texture() -> bool:
	return _icon_rect != null and _icon_rect.texture != null

func get_icon_shader_material() -> ShaderMaterial:
	return _icon_mat

func _refresh_slot_styles() -> void:
	_ensure_icon_node()
	var border_col: Color = ThemePaletteScript.color_iron_gray()
	if has_equipped_item:
		border_col = ThemePaletteScript.get_rarity_color(item_rarity)

	var b_width: int = 2 if (has_equipped_item and item_rarity >= 3) else 1
	var normal_style: StyleBoxFlat = ThemePaletteScript.make_card_style(border_col, 4, b_width)
	var hover_border: Color = border_col.lerp(ThemePaletteScript.color_old_gold_bright(), 0.5)
	var hover_style: StyleBoxFlat = ThemePaletteScript.make_card_style(hover_border, 4, b_width)

	add_theme_stylebox_override("normal", normal_style)
	add_theme_stylebox_override("hover", hover_style)
	add_theme_stylebox_override("pressed", hover_style)
	add_theme_stylebox_override("disabled", normal_style)

	var is_uniq_or_primal: bool = (has_equipped_item and item_rarity >= 3) or not transmog_id.is_empty()
	var tex: Texture2D = null
	if not transmog_id.is_empty():
		if transmog_id == "transmog_archon_blade" or transmog_id == "uniq_weapon_thunder":
			tex = ArtRegistryScript.load_texture_safe(ArtRegistryScript.UNIQ_WEAPON_THUNDER)
		elif transmog_id == "unique_trinket" or transmog_id == "uniq_trinket_scales":
			tex = ArtRegistryScript.load_texture_safe(ArtRegistryScript.UNIQ_TRINKET_SCALES)
		else:
			tex = ArtRegistryScript.get_item_icon_texture(slot_key, true)
	if tex == null:
		tex = ArtRegistryScript.get_item_icon_texture(slot_key, is_uniq_or_primal)
	_icon_rect.texture = tex
	_icon_rect.visible = (tex != null)

	if _icon_mat != null:
		if has_equipped_item or not transmog_id.is_empty():
			var r_col: Color = ThemePaletteScript.get_rarity_color(item_rarity if has_equipped_item else 4)
			_icon_mat.set_shader_parameter("color_ink", Color.html("#0B0A0C"))
			_icon_mat.set_shader_parameter("color_bone", Color.html("#E8DCC0"))
			_icon_mat.set_shader_parameter("color_family", r_col)
			_icon_mat.set_shader_parameter("color_gold", Color.html("#C9A04E"))
			_icon_mat.set_shader_parameter("enable_outline", item_rarity >= 3 or not transmog_id.is_empty())
			_icon_mat.set_shader_parameter("outline_width", 1.2)
			_icon_rect.modulate = Color.WHITE
		else:
			var dim_gray: Color = Color.html("#52525C")
			_icon_mat.set_shader_parameter("color_ink", Color.html("#101015"))
			_icon_mat.set_shader_parameter("color_bone", dim_gray)
			_icon_mat.set_shader_parameter("color_family", ThemePaletteScript.color_iron_gray())
			_icon_mat.set_shader_parameter("color_gold", dim_gray)
			_icon_mat.set_shader_parameter("enable_outline", false)
			_icon_rect.modulate = Color(1.0, 1.0, 1.0, 0.56)

func _draw() -> void:
	# 暗金刻线光环 (rarity==3) 与太古绯红流动光环 (rarity>=4)
	if has_equipped_item and item_rarity >= 3:
		var aura_col: Color = ThemePaletteScript.get_rarity_color(item_rarity)
		if item_rarity == 3:
			aura_col.a = 0.52
			draw_rect(Rect2(Vector2(2.5, 2.5), size - Vector2(5.0, 5.0)), aura_col, false, 1.0)
			var c_pts: Array[Vector2] = [
				Vector2(4.0, 4.0),
				Vector2(size.x - 4.0, 4.0),
				size - Vector2(4.0, 4.0),
				Vector2(4.0, size.y - 4.0)
			]
			for pt: Vector2 in c_pts:
				draw_circle(pt, 1.4, aura_col)
		else:
			var pulse: float = 0.45 + 0.35 * (0.5 + 0.5 * sin(_aura_phase))
			aura_col.a = pulse
			draw_rect(Rect2(Vector2(2.0, 2.0), size - Vector2(4.0, 4.0)), aura_col, false, 1.4)
			var gold_inner: Color = ThemePaletteScript.color_coin_gold()
			gold_inner.a = pulse * 0.75
			draw_rect(Rect2(Vector2(4.0, 4.0), size - Vector2(8.0, 8.0)), gold_inner, false, 1.0)

	# 仅当正式图标尚未生成时的极简几何兜底
	if not has_formal_icon_texture():
		var fallback_col: Color = ThemePaletteScript.color_bone_white() if has_equipped_item else ThemePaletteScript.color_ash_gray()
		draw_rect(Rect2(size * 0.5 - Vector2(7.0, 7.0), Vector2(14.0, 14.0)), fallback_col, false, 1.5)
