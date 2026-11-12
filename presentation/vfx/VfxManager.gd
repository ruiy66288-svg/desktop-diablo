class_name VfxManager extends Node2D

## 战斗特效渲染管理器 (依据《02_系统架构与数值_v6.md》§6.2 & §6.3 与《03_美术风格圣经_v1.0.md》§02.5–§02.6, §03)
## 暴击刻线环与预算合并由单节点 `_draw()` 批量渲染；连锁闪电使用 Line2D 池（ADD 混合）；
## 落地即爆使用 ground_slam.gdshader 池；杀戮狂热使用 afterimage.gdshader 叠层。

const VfxBudgetScript = preload("res://presentation/VfxBudget.gd")
const ThemePaletteScript = preload("res://ui/ThemePalette.gd")
const GroundSlamShader = preload("res://assets/art/shaders/ground_slam.gdshader")
const AfterimageShader = preload("res://assets/art/shaders/afterimage.gdshader")

const MAX_CONCURRENT_CRIT_RINGS: int = 3
const MAX_CONCURRENT_LIGHTNING: int = 2
const MAX_CONCURRENT_SLAMS: int = 4
const LIGHTNING_SEGMENTS: int = 4
const LIGHTNING_JUMP_DURATION: float = 0.09
const SLAM_DURATION: float = 0.25
const SLAM_SIZE: float = 80.0

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

class LightningSlot extends RefCounted:
	var outer_line: Line2D = null
	var inner_line: Line2D = null
	var active: bool = false
	var current_time: float = 0.0
	var max_time: float = 0.09

class SlamSlot extends RefCounted:
	var rect: ColorRect = null
	var material: ShaderMaterial = null
	var active: bool = false
	var current_time: float = 0.0
	var max_time: float = 0.25

var budget: VfxBudgetScript = null
var _active_list: Array[ActiveVfx] = []
var _lightning_pool: Array[LightningSlot] = []
var _slam_pool: Array[SlamSlot] = []
var _frenzy_rect: ColorRect = null
var _frenzy_material: ShaderMaterial = null
var _frenzy_time: float = 0.0
var _frenzy_ratio: float = 0.0
var _edge_alert_time: float = 0.0
var _edge_alert_max_time: float = 0.6
var _edge_alert_color: Color = Color.TRANSPARENT
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

func _init() -> void:
	budget = VfxBudgetScript.new()
	_rng.seed = 20261113
	_init_pools()

func _init_pools() -> void:
	var add_mat: CanvasItemMaterial = CanvasItemMaterial.new()
	add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD

	for i: int in range(MAX_CONCURRENT_LIGHTNING):
		var slot: LightningSlot = LightningSlot.new()
		var outer: Line2D = Line2D.new()
		outer.name = "ChainLightningOuter_%d" % i
		outer.width = 3.0
		outer.default_color = Color.html("#9FE8FF")
		outer.material = add_mat
		outer.visible = false
		outer.z_index = 10
		add_child(outer)

		var inner: Line2D = Line2D.new()
		inner.name = "ChainLightningInner_%d" % i
		inner.width = 1.2
		inner.default_color = Color.WHITE
		inner.material = add_mat
		inner.visible = false
		inner.z_index = 11
		add_child(inner)

		slot.outer_line = outer
		slot.inner_line = inner
		_lightning_pool.push_back(slot)

	for j: int in range(MAX_CONCURRENT_SLAMS):
		var slam: SlamSlot = SlamSlot.new()
		var rect: ColorRect = ColorRect.new()
		rect.name = "GroundSlamRect_%d" % j
		rect.size = Vector2(SLAM_SIZE, SLAM_SIZE)
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rect.color = Color.WHITE
		rect.visible = false
		rect.z_index = 8

		var mat: ShaderMaterial = ShaderMaterial.new()
		mat.shader = GroundSlamShader
		mat.set_shader_parameter("progress", 0.0)
		mat.set_shader_parameter("slam_color", ThemePaletteScript.color_old_gold_bright())
		rect.material = mat
		add_child(rect)

		slam.rect = rect
		slam.material = mat
		_slam_pool.push_back(slam)

	_frenzy_rect = ColorRect.new()
	_frenzy_rect.name = "KillingFrenzyAfterimage"
	_frenzy_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frenzy_rect.color = Color.WHITE
	_frenzy_rect.visible = false
	_frenzy_rect.z_index = 5

	_frenzy_material = ShaderMaterial.new()
	_frenzy_material.shader = AfterimageShader
	_frenzy_material.set_shader_parameter("frenzy_ratio", 0.0)
	_frenzy_material.set_shader_parameter("time_phase", 0.0)
	_frenzy_material.set_shader_parameter("afterimage_color", Color.html("#FF5A1F"))
	_frenzy_rect.material = _frenzy_material
	add_child(_frenzy_rect)

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

	for slot: LightningSlot in _lightning_pool:
		if not slot.active:
			continue
		slot.current_time += delta
		if slot.current_time >= slot.max_time:
			slot.active = false
			slot.outer_line.visible = false
			slot.inner_line.visible = false
		else:
			var alpha: float = 1.0 - clampf(slot.current_time / slot.max_time, 0.0, 1.0)
			var outer_c: Color = Color.html("#9FE8FF")
			outer_c.a = alpha
			var inner_c: Color = Color.WHITE
			inner_c.a = alpha
			slot.outer_line.default_color = outer_c
			slot.inner_line.default_color = inner_c

	for slam: SlamSlot in _slam_pool:
		if not slam.active:
			continue
		slam.current_time += delta
		if slam.current_time >= slam.max_time:
			slam.active = false
			slam.rect.visible = false
		else:
			var progress: float = clampf(slam.current_time / slam.max_time, 0.0, 1.0)
			slam.material.set_shader_parameter("progress", progress)

	if _frenzy_ratio > 0.0 and _frenzy_rect != null and _frenzy_rect.visible:
		_frenzy_time += delta
		_frenzy_material.set_shader_parameter("time_phase", _frenzy_time)

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

## 产生连锁闪电 Line2D 折线 (03 §02.5: #9FE8FF 外层 3px + #FFFFFF 核心, ADD 混合, 90ms/跳, 同屏上限 2)
func spawn_chain_lightning(from_pos: Vector2, to_pos: Vector2, jump_idx: int = 1) -> void:
	if get_active_lightning_lines_count() >= MAX_CONCURRENT_LIGHTNING:
		return
	if not budget.request_vfx("chain_lightning", 1):
		return

	var target_slot: LightningSlot = null
	for slot: LightningSlot in _lightning_pool:
		if not slot.active:
			target_slot = slot
			break
	if target_slot == null:
		return

	var pts: PackedVector2Array = _build_jagged_points(from_pos, to_pos, LIGHTNING_SEGMENTS)
	target_slot.outer_line.points = pts
	target_slot.inner_line.points = pts
	target_slot.outer_line.default_color = Color.html("#9FE8FF")
	target_slot.inner_line.default_color = Color.WHITE
	target_slot.outer_line.visible = true
	target_slot.inner_line.visible = true
	target_slot.current_time = 0.0
	target_slot.max_time = LIGHTNING_JUMP_DURATION * float(maxi(1, jump_idx))
	target_slot.active = true

func _build_jagged_points(from_pos: Vector2, to_pos: Vector2, segments: int) -> PackedVector2Array:
	var pts: PackedVector2Array = PackedVector2Array()
	var dir: Vector2 = to_pos - from_pos
	var perp: Vector2 = Vector2(-dir.y, dir.x).normalized()
	if perp == Vector2.ZERO:
		perp = Vector2(0.0, -1.0)
	pts.push_back(from_pos)
	for s: int in range(1, segments):
		var t: float = float(s) / float(segments)
		var base_pt: Vector2 = from_pos.lerp(to_pos, t)
		var jitter: float = _rng.randf_range(-12.0, 12.0)
		pts.push_back(base_pt + perp * jitter)
	pts.push_back(to_pos)
	return pts

## 产生掉落落地冲击波 (03 §02.5: ground_slam.gdshader, 半径 <= 40px, 250ms)
func spawn_drop_explosion(pos: Vector2, rarity: int = 0) -> void:
	var prio: int = 3 if rarity >= 3 else 1
	if not budget.request_vfx("drop_explosion", prio):
		return

	var target_slam: SlamSlot = null
	for slam: SlamSlot in _slam_pool:
		if not slam.active:
			target_slam = slam
			break
	if target_slam == null:
		target_slam = _slam_pool[0]

	var half_size: float = SLAM_SIZE * 0.5
	target_slam.rect.position = pos - Vector2(half_size, half_size)
	target_slam.material.set_shader_parameter("progress", 0.0)
	target_slam.material.set_shader_parameter("slam_color", ThemePaletteScript.get_rarity_color(rarity))
	target_slam.rect.visible = true
	target_slam.current_time = 0.0
	target_slam.max_time = SLAM_DURATION
	target_slam.active = true

## 产生杀戮狂热刻线环脉冲
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

## 同步杀戮狂热残影 Shader 层强度 (1..10 层)
func update_killing_frenzy_afterimage(stacks: int, card_rect: Rect2) -> void:
	if _frenzy_rect == null or _frenzy_material == null:
		return
	var clamped_stacks: int = clampi(stacks, 0, 10)
	_frenzy_ratio = float(clamped_stacks) / 10.0
	if clamped_stacks <= 0:
		_frenzy_rect.visible = false
		_frenzy_material.set_shader_parameter("frenzy_ratio", 0.0)
		return
	_frenzy_rect.position = card_rect.position - Vector2(8.0, 6.0)
	_frenzy_rect.size = card_rect.size + Vector2(16.0, 12.0)
	_frenzy_material.set_shader_parameter("frenzy_ratio", _frenzy_ratio)
	_frenzy_rect.visible = true

## 触发窗口边缘暗金/太古提醒光带 (03 §02.6)
func spawn_edge_alert(rarity: int) -> void:
	if rarity < 3:
		return
	_edge_alert_color = ThemePaletteScript.get_rarity_color(rarity)
	_edge_alert_max_time = 0.85 if rarity >= 4 else 0.60
	_edge_alert_time = _edge_alert_max_time
	queue_redraw()

func get_active_lightning_lines_count() -> int:
	var cnt: int = 0
	for slot: LightningSlot in _lightning_pool:
		if slot.active:
			cnt += 1
	return cnt

func get_active_slam_rects_count() -> int:
	var cnt: int = 0
	for slam: SlamSlot in _slam_pool:
		if slam.active:
			cnt += 1
	return cnt

func get_frenzy_afterimage_ratio() -> float:
	return _frenzy_ratio

func is_frenzy_afterimage_visible() -> bool:
	return _frenzy_rect != null and _frenzy_rect.visible

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
