class_name LootFountain extends Node2D

## 纯物理轻量喷泉掉落系统 (依据《02_系统架构与数值_v6.md》Q11, §3.3 & 《03_美术风格圣经_v1.0.md》§02.5–§02.6, §03)
## 拒绝重量级 RigidBody2D 物理引擎，自写弹道 + 双段 ObjectPool：
## 总上限 120 个（普通池 100 给白/蓝/紫 + 专属池 20 专留暗金及以上）；池满优先回收最老白/蓝装；
## 集成光柱 Shader (loot_beam.gdshader) 与地面符印环 Shader (sigil_ring.gdshader)

const ObjectPoolScript = preload("res://core/pool/ObjectPool.gd")
const ThemePaletteScript = preload("res://ui/ThemePalette.gd")
const LootBeamShader = preload("res://assets/art/shaders/loot_beam.gdshader")
const SigilRingShader = preload("res://assets/art/shaders/sigil_ring.gdshader")

const TOTAL_CAPACITY: int = 120
const RARE_RESERVED_CAPACITY: int = 20
const NORMAL_CAPACITY: int = 100

const GRAVITY: float = 980.0
const FLOOR_Y: float = 356.0
const BOUNCE_DAMPING: float = 0.45
const FRICTION: float = 0.70
const STOP_BOUNCE_VY: float = 30.0
const STAY_DURATION: float = 2.5
const MAGNET_DIST: float = 48.0
const MAGNET_SPEED: float = 650.0
const MIN_X: float = 22.0
const MAX_X: float = 338.0

const MAX_POOLED_BEAMS: int = 16
const MAX_POOLED_SIGILS: int = 8

signal manual_pickup_triggered(ilvl: int, rarity: int)

class LootParticle extends RefCounted:
	var pos: Vector2 = Vector2.ZERO
	var vel: Vector2 = Vector2.ZERO
	var rarity: int = 0
	var ilvl: int = 1
	var age: float = 0.0
	var landed: bool = false
	var landed_time: float = 0.0
	var is_active: bool = false
	var is_magnetized: bool = false
	var manual_notified: bool = false
	var target_dest: Vector2 = Vector2(180.0, 444.0)
	var is_rare_slot: bool = false

var normal_pool: ObjectPoolScript = null
var rare_pool: ObjectPoolScript = null
var _active_particles: Array[LootParticle] = []
var _overflow_compacted_drops: int = 0
var _beam_rects: Array[ColorRect] = []
var _sigil_rects: Array[ColorRect] = []

func _ready() -> void:
	_ensure_pools_initialized()
	_init_shader_node_pools()

func _ensure_pools_initialized() -> void:
	if normal_pool != null and rare_pool != null:
		return

	normal_pool = ObjectPoolScript.new(
		func() -> LootParticle:
			var p: LootParticle = LootParticle.new()
			p.is_rare_slot = false
			return p,
		func(p: LootParticle) -> void:
			p.age = 0.0
			p.landed = false
			p.landed_time = 0.0
			p.is_active = true
			p.is_magnetized = false
			p.manual_notified = false
			p.is_rare_slot = false,
		NORMAL_CAPACITY
	)
	normal_pool.prewarm(40)

	rare_pool = ObjectPoolScript.new(
		func() -> LootParticle:
			var p: LootParticle = LootParticle.new()
			p.is_rare_slot = true
			return p,
		func(p: LootParticle) -> void:
			p.age = 0.0
			p.landed = false
			p.landed_time = 0.0
			p.is_active = true
			p.is_magnetized = false
			p.manual_notified = false
			p.is_rare_slot = true,
		RARE_RESERVED_CAPACITY
	)
	rare_pool.prewarm(RARE_RESERVED_CAPACITY)

func _init_shader_node_pools() -> void:
	if not _beam_rects.is_empty():
		return

	for i: int in range(MAX_POOLED_BEAMS):
		var beam_rect: ColorRect = ColorRect.new()
		beam_rect.name = "PooledBeam_%d" % i
		beam_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		beam_rect.color = Color.WHITE
		beam_rect.visible = false
		var mat: ShaderMaterial = ShaderMaterial.new()
		mat.shader = LootBeamShader
		beam_rect.material = mat
		add_child(beam_rect)
		_beam_rects.push_back(beam_rect)

	for j: int in range(MAX_POOLED_SIGILS):
		var sigil_rect: ColorRect = ColorRect.new()
		sigil_rect.name = "PooledSigil_%d" % j
		sigil_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sigil_rect.color = Color.WHITE
		sigil_rect.visible = false
		var sig_mat: ShaderMaterial = ShaderMaterial.new()
		sig_mat.shader = SigilRingShader
		sigil_rect.material = sig_mat
		add_child(sigil_rect)
		_sigil_rects.push_back(sigil_rect)

## 产生单件掉落物喷泉弹射；暗金及以上 (>=3) 走 20 格专属池，普通走 100 格池（满时回收最老白/蓝装）
func spawn_drop(origin: Vector2, rarity: int, launch_mul: float = 1.0, ilvl: int = 1) -> bool:
	_ensure_pools_initialized()
	var is_rare: bool = rarity >= 3
	var p: LootParticle = null

	if is_rare:
		p = rare_pool.acquire() as LootParticle
		if p == null:
			# 20 个暗金专属池已满时，优先回收最老的暗金，保留太古
			p = _evict_oldest_matching(func(cand: LootParticle) -> bool: return cand.is_rare_slot and cand.rarity == 3)
			if p == null:
				_overflow_compacted_drops += 1
				return false
	else:
		p = normal_pool.acquire() as LootParticle
		if p == null:
			# 普通池满时优先回收最老的白装 (0) / 蓝装 (1)
			p = _evict_oldest_matching(func(cand: LootParticle) -> bool: return not cand.is_rare_slot and cand.rarity <= 1)
			if p == null:
				_overflow_compacted_drops += 1
				return false

	p.pos = origin
	p.rarity = clampi(rarity, 0, 4)
	p.ilvl = maxi(1, ilvl)
	p.age = 0.0
	p.landed = false
	p.landed_time = 0.0
	p.is_active = true
	p.is_magnetized = false
	p.manual_notified = false

	var vx: float = randf_range(-120.0, 120.0)
	var vy: float = -randf_range(380.0, 520.0) * maxf(0.5, launch_mul)
	p.vel = Vector2(vx, vy)

	_active_particles.push_back(p)
	queue_redraw()
	return true

func _evict_oldest_matching(pred: Callable) -> LootParticle:
	for idx: int in range(_active_particles.size()):
		var cand: LootParticle = _active_particles[idx]
		if bool(pred.call(cand)):
			_active_particles.remove_at(idx)
			cand.age = 0.0
			cand.landed = false
			cand.landed_time = 0.0
			cand.is_active = true
			cand.is_magnetized = false
			cand.manual_notified = false
			return cand
	return null

func get_active_total_count() -> int:
	return _active_particles.size()

func get_active_normal_count() -> int:
	return normal_pool.get_active_count() if normal_pool != null else 0

func get_active_rare_count() -> int:
	return rare_pool.get_active_count() if rare_pool != null else 0

func get_overflow_compacted_drops() -> int:
	return _overflow_compacted_drops

func clear_all() -> void:
	for p: LootParticle in _active_particles:
		if p.is_rare_slot and rare_pool != null:
			rare_pool.release(p)
		elif not p.is_rare_slot and normal_pool != null:
			normal_pool.release(p)
	_active_particles.clear()
	_overflow_compacted_drops = 0
	_hide_all_shader_nodes()
	queue_redraw()

func _hide_all_shader_nodes() -> void:
	for b: ColorRect in _beam_rects:
		b.visible = false
	for s: ColorRect in _sigil_rects:
		s.visible = false

func _process(delta: float) -> void:
	step_simulation(delta, get_global_mouse_position())

## 独立步进函数（支持 Headless 单元测试与实时渲染共用）
func step_simulation(delta: float, mouse_pos: Vector2) -> void:
	if _active_particles.is_empty():
		_hide_all_shader_nodes()
		return

	var i: int = 0
	while i < _active_particles.size():
		var p: LootParticle = _active_particles[i]
		p.age += delta

		if not p.is_magnetized and p.pos.distance_to(mouse_pos) < MAGNET_DIST:
			p.is_magnetized = true
			if not p.manual_notified:
				p.manual_notified = true
				manual_pickup_triggered.emit(p.ilvl, p.rarity)

		if p.is_magnetized:
			var dir: Vector2 = (p.target_dest - p.pos).normalized()
			p.pos += dir * MAGNET_SPEED * delta
			if p.pos.distance_to(p.target_dest) < 20.0 or p.age > 5.0:
				_release_particle(p)
				_active_particles.remove_at(i)
				continue
		else:
			p.vel.y += GRAVITY * delta
			p.pos += p.vel * delta
			p.pos.x = clampf(p.pos.x, MIN_X, MAX_X)

			if p.pos.y >= FLOOR_Y:
				p.pos.y = FLOOR_Y
				if not p.landed:
					p.landed = true
				p.vel.y = -p.vel.y * BOUNCE_DAMPING
				p.vel.x *= FRICTION
				if absf(p.vel.y) < STOP_BOUNCE_VY:
					p.vel.y = 0.0
				if absf(p.vel.x) < 10.0:
					p.vel.x = 0.0

			if p.landed:
				p.landed_time += delta
				if p.landed_time >= STAY_DURATION:
					p.is_magnetized = true

		i += 1

	_sync_shader_nodes()
	queue_redraw()

func _release_particle(p: LootParticle) -> void:
	p.is_active = false
	if p.is_rare_slot and rare_pool != null:
		rare_pool.release(p)
	elif not p.is_rare_slot and normal_pool != null:
		normal_pool.release(p)

func _sync_shader_nodes() -> void:
	_hide_all_shader_nodes()
	if _beam_rects.is_empty():
		return

	var beam_idx: int = 0
	var sigil_idx: int = 0

	# 优先为暗金/太古分配光柱与地面符印环，其次分配紫/蓝光柱
	for pass_rare: int in [1, 0]:
		for p: LootParticle in _active_particles:
			var is_high: bool = p.rarity >= 3
			if (pass_rare == 1) != is_high:
				continue
			if p.rarity == 0 or not p.landed or p.is_magnetized:
				continue

			var col: Color = ThemePaletteScript.get_rarity_color(p.rarity)
			var beam_h: float = 42.0
			var beam_w: float = 12.0
			var max_life: float = 0.6

			if p.rarity == 2:
				beam_h = 74.0
				beam_w = 16.0
				max_life = 1.0
			elif p.rarity == 3:
				beam_h = 160.0
				beam_w = 24.0
				max_life = STAY_DURATION
			elif p.rarity == 4:
				beam_h = 180.0
				beam_w = 28.0
				max_life = STAY_DURATION

			var life_alpha: float = clampf(1.0 - (p.landed_time / max_life) * 0.65, 0.0, 1.0)
			if p.landed_time <= max_life and beam_idx < _beam_rects.size():
				var rect_node: ColorRect = _beam_rects[beam_idx]
				rect_node.position = Vector2(p.pos.x - beam_w * 0.5, p.pos.y - beam_h)
				rect_node.size = Vector2(beam_w, beam_h)
				var mat: ShaderMaterial = rect_node.material as ShaderMaterial
				if mat != null:
					mat.set_shader_parameter("beam_color", col)
					mat.set_shader_parameter("life_alpha", life_alpha)
					mat.set_shader_parameter("intensity", 1.45 if is_high else 1.0)
				rect_node.visible = true
				beam_idx += 1

			if is_high and sigil_idx < _sigil_rects.size():
				var sig_node: ColorRect = _sigil_rects[sigil_idx]
				var sig_size: Vector2 = Vector2(36.0, 20.0)
				sig_node.position = Vector2(p.pos.x - sig_size.x * 0.5, p.pos.y - sig_size.y * 0.5)
				sig_node.size = sig_size
				var sig_mat: ShaderMaterial = sig_node.material as ShaderMaterial
				if sig_mat != null:
					sig_mat.set_shader_parameter("ring_color", col)
					sig_mat.set_shader_parameter("life_alpha", life_alpha)
				sig_node.visible = true
				sigil_idx += 1

func _draw() -> void:
	var ink_col: Color = ThemePaletteScript.color_ink_black()
	for p: LootParticle in _active_particles:
		var c: Color = ThemePaletteScript.get_rarity_color(p.rarity)
		var r: float = 4.2 if p.rarity >= 3 else 3.2
		draw_circle(p.pos, r + 1.0, ink_col)
		draw_circle(p.pos, r, c)
