class_name EquipSlotView extends Button

## 48×48 六槽装备栏单元视图 (依据《03_美术风格圣经_v1.0.md》§02.1、§02.4 与《00_开发执行总纲.md》E10)
## 槽位固定：weapon / helm / chest / gloves / boots / trinket
## 品质完全由程序表现（边框颜色 + 骨白/铁灰几何木刻占位图标，零 AI 图片）

const ThemePaletteScript = preload("res://ui/ThemePalette.gd")

var slot_key: String = "weapon"
var has_equipped_item: bool = false
var item_rarity: int = -1
var item_ilvl: int = 0

func setup_slot(p_slot_key: String) -> void:
	slot_key = p_slot_key
	custom_minimum_size = Vector2(48.0, 48.0)
	size = Vector2(48.0, 48.0)
	text = ""
	focus_mode = Control.FOCUS_NONE
	_refresh_slot_styles()
	queue_redraw()

func set_item_state(p_equipped: bool, p_rarity: int = -1, p_ilvl: int = 0) -> void:
	if has_equipped_item == p_equipped and item_rarity == p_rarity and item_ilvl == p_ilvl:
		return
	has_equipped_item = p_equipped
	item_rarity = p_rarity
	item_ilvl = p_ilvl
	_refresh_slot_styles()
	queue_redraw()

func _refresh_slot_styles() -> void:
	var border_col: Color = ThemePaletteScript.color_iron_gray()
	if has_equipped_item:
		border_col = ThemePaletteScript.get_rarity_color(item_rarity)

	var normal_style: StyleBoxFlat = ThemePaletteScript.make_card_style(border_col, 4, 1)
	var hover_border: Color = border_col.lerp(ThemePaletteScript.color_old_gold_bright(), 0.5)
	var hover_style: StyleBoxFlat = ThemePaletteScript.make_card_style(hover_border, 4, 1)

	add_theme_stylebox_override("normal", normal_style)
	add_theme_stylebox_override("hover", hover_style)
	add_theme_stylebox_override("pressed", hover_style)
	add_theme_stylebox_override("disabled", normal_style)

func _draw() -> void:
	var icon_col: Color = ThemePaletteScript.color_ash_gray()
	if has_equipped_item:
		icon_col = ThemePaletteScript.color_bone_white()
	else:
		icon_col.a = 0.55

	var c: Vector2 = size * 0.5
	var w: float = 2.0

	match slot_key:
		"weapon":
			# 03 §02.4：左下到右上 45° 斜放武器
			draw_line(c + Vector2(-12.0, 12.0), c + Vector2(12.0, -12.0), icon_col, 2.4)
			draw_line(c + Vector2(-9.0, 3.0), c + Vector2(-3.0, 9.0), icon_col, 2.2)
		"helm":
			draw_arc(c + Vector2(0.0, 2.0), 10.0, PI, TAU, 12, icon_col, w)
			draw_rect(Rect2(c + Vector2(-10.0, 2.0), Vector2(20.0, 8.0)), icon_col, false, w)
			draw_line(c + Vector2(0.0, -4.0), c + Vector2(0.0, 10.0), icon_col, 1.8)
		"chest":
			var pts: PackedVector2Array = PackedVector2Array([
				c + Vector2(-11.0, -10.0),
				c + Vector2(-5.0, -12.0),
				c + Vector2(5.0, -12.0),
				c + Vector2(11.0, -10.0),
				c + Vector2(9.0, 11.0),
				c + Vector2(-9.0, 11.0)
			])
			draw_polyline(pts, icon_col, w)
			draw_line(pts[5], pts[0], icon_col, w)
		"gloves":
			draw_rect(Rect2(c + Vector2(-7.0, -4.0), Vector2(14.0, 14.0)), icon_col, false, w)
			draw_line(c + Vector2(-5.0, -4.0), c + Vector2(-5.0, -11.0), icon_col, 1.8)
			draw_line(c + Vector2(0.0, -4.0), c + Vector2(0.0, -12.0), icon_col, 1.8)
			draw_line(c + Vector2(5.0, -4.0), c + Vector2(5.0, -10.0), icon_col, 1.8)
		"boots":
			draw_rect(Rect2(c + Vector2(-8.0, -11.0), Vector2(9.0, 16.0)), icon_col, false, w)
			draw_rect(Rect2(c + Vector2(-8.0, 5.0), Vector2(16.0, 6.0)), icon_col, false, w)
		"trinket":
			draw_arc(c + Vector2(0.0, 2.0), 9.0, 0.0, TAU, 16, icon_col, w)
			var gem_col: Color = ThemePaletteScript.color_old_gold()
			if has_equipped_item:
				gem_col = ThemePaletteScript.get_rarity_color(item_rarity)
			draw_circle(c + Vector2(0.0, -7.0), 3.2, gem_col)
		_:
			draw_rect(Rect2(c - Vector2(8.0, 8.0), Vector2(16.0, 16.0)), icon_col, false, w)
