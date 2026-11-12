class_name FloatingTextLayer extends Control

## 批量伤害飘字层 (依据《02_系统架构与数值_v6.md》§3.3 & 《03_美术风格圣经_v1.0.md》§02.5, §03)
## 铁律：单节点 `_draw()` 统一绘制，零 Label 子节点；上限 60 条，超限自动合并为 "×N" 累计数字；伤害数字仅出现于战场上部 1/3

const ThemePaletteScript = preload("res://ui/ThemePalette.gd")

const MAX_TEXTS: int = 60
const UPPER_THIRD_MIN_Y: float = 68.0
const UPPER_THIRD_MAX_Y: float = 152.0

class FloatingText extends RefCounted:
	var base_text: String = ""
	var merge_count: int = 1
	var pos: Vector2 = Vector2.ZERO
	var vel: Vector2 = Vector2.ZERO
	var color: Color = Color.WHITE
	var outline_color: Color = Color.TRANSPARENT
	var life: float = 0.5
	var max_life: float = 0.5
	var size: int = 12
	var is_crit: bool = false

	func get_display_text() -> String:
		if merge_count > 1:
			return "%s ×%d" % [base_text, merge_count]
		return base_text

var _items: Array[FloatingText] = []
var _merged_overflow_total: int = 0

func add_floating_text(
	text_str: String,
	start_pos: Vector2,
	text_color: Color = Color.TRANSPARENT,
	is_crit: bool = false,
	clamp_upper_third: bool = true
) -> void:
	var resolved_color: Color = text_color
	if resolved_color.a <= 0.0:
		resolved_color = ThemePaletteScript.color_crit_core() if is_crit else ThemePaletteScript.color_bone_white()

	var resolved_outline: Color = Color.TRANSPARENT
	if is_crit:
		resolved_outline = Color.html(ThemePaletteScript.HEX_CRIT_EDGE)

	var clamped_pos: Vector2 = start_pos
	if clamp_upper_third:
		clamped_pos.y = clampf(clamped_pos.y, UPPER_THIRD_MIN_Y, UPPER_THIRD_MAX_Y)

	# 容量防线: 上限 60 条，超限优先合并到同类飘字为 "×N" 累计数字，绝不创建 Label 节点
	if _items.size() >= MAX_TEXTS:
		_merged_overflow_total += 1
		for idx: int in range(_items.size() - 1, -1, -1):
			var existing: FloatingText = _items[idx]
			if existing.is_crit == is_crit:
				existing.merge_count += 1
				existing.base_text = text_str
				existing.life = existing.max_life
				queue_redraw()
				return

		var fallback: FloatingText = _items[0]
		fallback.merge_count += 1
		fallback.base_text = text_str
		fallback.life = fallback.max_life
		queue_redraw()
		return

	var item: FloatingText = FloatingText.new()
	item.base_text = text_str
	item.merge_count = 1
	item.pos = clamped_pos
	item.color = resolved_color
	item.outline_color = resolved_outline
	item.is_crit = is_crit
	item.max_life = 0.75 if is_crit else 0.50
	item.life = item.max_life
	item.size = 16 if is_crit else 12

	var vx: float = randf_range(-14.0, 14.0)
	var vy: float = randf_range(-56.0, -82.0) if is_crit else randf_range(-36.0, -52.0)
	item.vel = Vector2(vx, vy)

	_items.push_back(item)
	queue_redraw()

func get_active_count() -> int:
	return _items.size()

func get_merged_overflow_total() -> int:
	return _merged_overflow_total

func clear_all() -> void:
	_items.clear()
	_merged_overflow_total = 0
	queue_redraw()

func _process(delta: float) -> void:
	if _items.is_empty():
		return

	var i: int = 0
	while i < _items.size():
		var it: FloatingText = _items[i]
		it.life -= delta
		if it.life <= 0.0:
			_items.remove_at(i)
		else:
			it.pos += it.vel * delta
			it.vel.y += 20.0 * delta
			i += 1

	queue_redraw()

func _draw() -> void:
	if _items.is_empty():
		return

	var font: Font = get_theme_default_font()
	if font == null:
		return

	for it: FloatingText in _items:
		var alpha: float = clampf(it.life / it.max_life, 0.0, 1.0)
		var display_str: String = it.get_display_text()

		if it.is_crit and it.outline_color.a > 0.0:
			var edge_col: Color = it.outline_color
			edge_col.a = alpha * 0.9
			draw_string(font, it.pos + Vector2(-1.0, 0.0), display_str, HORIZONTAL_ALIGNMENT_CENTER, -1.0, it.size, edge_col)
			draw_string(font, it.pos + Vector2(1.0, 0.0), display_str, HORIZONTAL_ALIGNMENT_CENTER, -1.0, it.size, edge_col)
			draw_string(font, it.pos + Vector2(0.0, 1.0), display_str, HORIZONTAL_ALIGNMENT_CENTER, -1.0, it.size, edge_col)

		var c: Color = it.color
		c.a = alpha
		draw_string(font, it.pos, display_str, HORIZONTAL_ALIGNMENT_CENTER, -1.0, it.size, c)
