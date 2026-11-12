class_name VfxManager extends Node2D

## 战斗特效渲染管理器 (依据《02_系统架构与数值_v6.md》§6.2 & §6.3 与《03_美术风格圣经_v1.0.md》§02.5–§02.6, §03)
## 单节点 `_draw()` 批量渲染，严格遵守 VfxBudget（24 实例 / 帧上限，超额自动合并为 "×N"）与荧光刻线视觉语言

const VfxBudgetScript = preload("res://presentation/VfxBudget.gd")
const ThemePaletteScript = preload("res://ui/ThemePalette.gd")

const MAX_CONCURRENT_CRIT_RINGS: int = 3
const MAX_CONCURRENT_LIGHTNING: int = 2

class ActiveVfx extends RefCounted:
	var type: String = ""
	var start_pos: Vector2 = Vector2.ZERO
	var end_pos: Vector2 = Vector2.ZERO
	var current_time: float = 0.0
	var max_time: float = 0.25
	var color: Color = Color.WHITE
	var max_radius: float = 40.0
	var merge_count: int = 1
	var extra_data: Dictionary = {}

var budget: VfxBudgetScript = null
var _active_list: Array[ActiveVfx] = []
var _edge_alert_time: float = 0.0
var _edge_alert_max_time: float = 0.6
var _edge_alert_color: Color = Color.TRANSPARENT

func _init() -> void:
	budget = VfxBudgetScript.new()

func _process(delta: float) -> void:
	var frame_ms: float = delta * 1000.0
	_flush_compacted_overflows()
	budget.begin_frame(frame_ms)

	var remaining: Array[ActiveVfx] = []
	for vfx: ActiveVfx in _active_list:
		vfx.current_time += delta
		if vfx.current_time < vfx.max_time:
			remaining.push_back(vfx)
	_active_list = remaining

	if _edge_alert_time > 0.0:
		_edge_alert_time = maxf(0.0, _edge_alert_time - delta)

	queue_redraw()

func _flush_compacted_overflows() -> void:
	var overflows: Dictionary = budget.get_compacted_overflows()
	if overflows.is_empty():
		return

	for key_raw: Variant in overflows.keys():
		var vtype: String = str(key_raw)
		var count: int = int(overflows[key_raw])
		if count <= 0:
			continue
		var merged: ActiveVfx = ActiveVfx.new()
		merged.type = "merged_burst"
		merged.start_pos = Vector2(112.0, 194.0)
		merged.max_time = 0.35
		merged.max_radius = 48.0
		merged.merge_count = count
		merged.color = Color.html(ThemePaletteScript.HEX_CRIT_CORE) if vtype == "crit_ring" else ThemePaletteScript.color_old_gold_bright()
		_active_list.push_back(merged)

## 产生暴击同心刻线环 + 8 道放射刀痕 (03 §02.5: 时长 200ms，同屏上限 3)
func spawn_crit_ring(pos: Vector2) -> void:
	if _count_active_type("crit_ring") >= MAX_CONCURRENT_CRIT_RINGS:
		return
	if not budget.request_vfx("crit_ring", 1):
		return

	var v: ActiveVfx = ActiveVfx.new()
	v.type = "crit_ring"
	v.start_pos = pos
	v.max_time = 0.20
	v.max_radius = 34.0
	v.color = Color.html(ThemePaletteScript.HEX_CRIT_CORE)
	_active_list.push_back(v)

## 产生连锁闪电折线 (03 §02.5: #9FE8FF + 核心 #FFFFFF, 同屏上限 2 条链)
func spawn_chain_lightning(from_pos: Vector2, to_pos: Vector2, jump_idx: int = 1) -> void:
	if _count_active_type("chain_lightning") >= MAX_CONCURRENT_LIGHTNING:
		return
	if not budget.request_vfx("chain_lightning", 1):
		return

	var v: ActiveVfx = ActiveVfx.new()
	v.type = "chain_lightning"
	v.start_pos = from_pos
	v.end_pos = to_pos
	v.max_time = 0.18
	v.color = Color.html("#9FE8FF")
	v.extra_data["jump_idx"] = jump_idx
	_active_list.push_back(v)

## 产生掉落落地冲击波 (03 §02.5: 半径 <= 40px, 250ms)
func spawn_drop_explosion(pos: Vector2, rarity: int = 0) -> void:
	var prio: int = 3 if rarity >= 3 else 1
	if not budget.request_vfx("drop_explosion", prio):
		return

	var v: ActiveVfx = ActiveVfx.new()
	v.type = "drop_explosion"
	v.start_pos = pos
	v.max_time = 0.25
	v.max_radius = 38.0
	v.color = ThemePaletteScript.get_rarity_color(rarity)
	_active_list.push_back(v)

## 产生杀戮狂热刻线环
func spawn_killing_frenzy(pos: Vector2, stacks: int) -> void:
	if not budget.request_vfx("killing_frenzy", 1):
		return

	var v: ActiveVfx = ActiveVfx.new()
	v.type = "killing_frenzy"
	v.start_pos = pos
	v.max_time = 0.25
	v.max_radius = 46.0 + float(stacks) * 2.5
	v.color = Color.html(ThemePaletteScript.HEX_CRIT_EDGE)
	v.extra_data["stacks"] = stacks
	_active_list.push_back(v)

## 触发窗口边缘暗金/太古提醒光带 (03 §02.6)
func spawn_edge_alert(rarity: int) -> void:
	if rarity < 3:
		return
	_edge_alert_color = ThemePaletteScript.get_rarity_color(rarity)
	_edge_alert_max_time = 0.85 if rarity >= 4 else 0.60
	_edge_alert_time = _edge_alert_max_time
	queue_redraw()

func _count_active_type(vtype: String) -> int:
	var cnt: int = 0
	for v: ActiveVfx in _active_list:
		if v.type == vtype:
			cnt += 1
	return cnt

func _draw() -> void:
	var font: Font = ThemeDB.fallback_font

	if _edge_alert_time > 0.0:
		var edge_a: float = clampf(_edge_alert_time / _edge_alert_max_time, 0.0, 1.0) * 0.75
		var ec: Color = _edge_alert_color
		ec.a = edge_a
		draw_rect(Rect2(Vector2(2.0, 2.0), Vector2(356.0, 476.0)), ec, false, 2.5)

	for vfx: ActiveVfx in _active_list:
		var progress: float = clampf(vfx.current_time / vfx.max_time, 0.0, 1.0)
		var alpha: float = 1.0 - progress

		match vfx.type:
			"crit_ring":
				var r_outer: float = vfx.max_radius * progress
				var r_inner: float = r_outer * 0.55
				var core_c: Color = vfx.color
				core_c.a = alpha
				var edge_c: Color = Color.html(ThemePaletteScript.HEX_CRIT_EDGE)
				edge_c.a = alpha * 0.85
				draw_arc(vfx.start_pos, r_outer, 0.0, TAU, 24, edge_c, 2.2)
				draw_arc(vfx.start_pos, r_inner, 0.0, TAU, 20, core_c, 1.5)
				for k: int in range(8):
					var ang: float = float(k) * (TAU / 8.0)
					var dir_v: Vector2 = Vector2(cos(ang), sin(ang))
					draw_line(vfx.start_pos + dir_v * (r_inner + 2.0), vfx.start_pos + dir_v * (r_outer + 5.0), core_c, 1.5)

			"chain_lightning":
				var pts: PackedVector2Array = PackedVector2Array()
				var segments: int = 4
				var dir: Vector2 = vfx.end_pos - vfx.start_pos
				var perp: Vector2 = Vector2(-dir.y, dir.x).normalized()
				pts.push_back(vfx.start_pos)
				for s: int in range(1, segments):
					var t: float = float(s) / float(segments)
					var base_pt: Vector2 = vfx.start_pos.lerp(vfx.end_pos, t)
					var jitter: float = sin(float(s) * 3.14 + vfx.current_time * 24.0) * 10.0
					pts.push_back(base_pt + perp * jitter)
				pts.push_back(vfx.end_pos)

				var col: Color = vfx.color
				col.a = alpha
				draw_polyline(pts, col, 3.0)
				var core_col: Color = Color.WHITE
				core_col.a = alpha
				draw_polyline(pts, core_col, 1.2)

			"drop_explosion":
				var r: float = vfx.max_radius * progress
				var col: Color = vfx.color
				col.a = alpha * 0.85
				draw_arc(vfx.start_pos, r, 0.0, TAU, 24, col, maxf(1.2, 3.0 * alpha))

			"killing_frenzy":
				var col: Color = vfx.color
				col.a = alpha * 0.55
				var r: float = vfx.max_radius * (0.8 + 0.2 * progress)
				draw_arc(vfx.start_pos, r, 0.0, TAU, 24, col, 2.0)

			"merged_burst":
				var r: float = vfx.max_radius * progress
				var col: Color = vfx.color
				col.a = alpha
				draw_arc(vfx.start_pos, r, 0.0, TAU, 28, col, 3.0)
				if font != null and vfx.merge_count > 1:
					draw_string(font, vfx.start_pos + Vector2(-12.0, -r - 4.0), "×%d" % vfx.merge_count, HORIZONTAL_ALIGNMENT_CENTER, -1.0, 13, col)
