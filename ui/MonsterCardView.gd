class_name MonsterCardView extends Control

## 四通道木刻主体塔罗怪物卡与排队卡视图 (依据《03_美术风格圣经_v1.0.md》§02.1–§02.5、《04_美术资产管线_v1.1.md》§1.1–§1.3 与 WP-09)
## 铁律：
## 1. 100% 显式静态类型，零 :=
## 2. 主怪/排队卡/Boss 统一使用真实四通道版画纹理 + palette_subject.gdshader 渲染
## 3. 支持 60ms 受击闪白、120ms 3px 受击后仰位移、非阻塞木刻死亡溶解残影与 Δh_wealth 三态镀金动态

const ThemePaletteScript = preload("res://ui/ThemePalette.gd")
const ArtRegistryScript = preload("res://ui/ArtRegistry.gd")

enum CardRole {
	MAIN_MOB,
	BOSS_MOB,
	QUEUE_MOB
}

const HIT_FLASH_DURATION: float = 0.06
const RECOIL_DURATION: float = 0.12
const RECOIL_PIXELS: float = 3.0
const DISSOLVE_DURATION: float = 0.32

var role: CardRole = CardRole.MAIN_MOB
var hp_ratio: float = 1.0
var wealth_pressure_log: float = 0.0
var hit_flash: float = 0.0
var mob_title: String = ""
var subject_res_path: String = ArtRegistryScript.MON_UNDEAD_MISER
var accent_color: Color = Color.html(ArtRegistryScript.HEX_ACCENT_UNDEAD)
var is_elite: bool = false

var _subject_rect: TextureRect = null
var _subject_mat: ShaderMaterial = null
var _dissolve_ghost_rect: TextureRect = null
var _dissolve_mat: ShaderMaterial = null

var _recoil_timer: float = 0.0
var _dissolve_active: bool = false
var _dissolve_elapsed: float = 0.0

func _ready() -> void:
	_ensure_subject_nodes()
	_sync_subject_layout_and_shader()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_sync_subject_layout_and_shader()

func _ensure_subject_nodes() -> void:
	if _subject_rect != null:
		return

	_dissolve_ghost_rect = TextureRect.new()
	_dissolve_ghost_rect.name = "DissolveGhostRect"
	_dissolve_ghost_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dissolve_ghost_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_dissolve_ghost_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_dissolve_ghost_rect.visible = false
	_dissolve_mat = ArtRegistryScript.make_palette_material(accent_color, false, 1.0)
	_dissolve_ghost_rect.material = _dissolve_mat
	add_child(_dissolve_ghost_rect)

	_subject_rect = TextureRect.new()
	_subject_rect.name = "SubjectTextureRect"
	_subject_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_subject_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_subject_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_subject_mat = ArtRegistryScript.make_palette_material(accent_color, true, 1.5)
	_subject_rect.material = _subject_mat
	add_child(_subject_rect)

func setup_role(p_role: CardRole, p_title: String = "") -> void:
	_ensure_subject_nodes()
	var changed: bool = (role != p_role) or (mob_title != p_title)
	role = p_role
	mob_title = p_title
	if role == CardRole.BOSS_MOB and subject_res_path == ArtRegistryScript.MON_UNDEAD_MISER:
		subject_res_path = ArtRegistryScript.BOSS_ABYSS_LORD
		accent_color = Color.html(ArtRegistryScript.HEX_ACCENT_DEMON)
	if changed or _subject_rect.texture == null:
		_sync_subject_layout_and_shader()
		queue_redraw()

func apply_visual_spec(spec: Dictionary) -> void:
	_ensure_subject_nodes()
	var next_path: String = str(spec.get("res_path", subject_res_path))
	var next_title: String = str(spec.get("title", mob_title))
	var next_accent: Color = spec.get("accent", accent_color) as Color
	var next_elite: bool = bool(spec.get("is_elite", false))

	var changed: bool = (
		next_path != subject_res_path
		or next_title != mob_title
		or not next_accent.is_equal_approx(accent_color)
		or next_elite != is_elite
		or _subject_rect.texture == null
	)
	subject_res_path = next_path
	mob_title = next_title
	accent_color = next_accent
	is_elite = next_elite
	if changed:
		_sync_subject_layout_and_shader()
		queue_redraw()

func update_combat_visuals(p_hp_ratio: float, p_wealth_pressure_log: float, p_hit_flash: float = 0.0) -> void:
	_ensure_subject_nodes()
	var clamped_hp: float = clampf(p_hp_ratio, 0.0, 1.0)
	var clamped_flash: float = clampf(p_hit_flash, 0.0, 1.0)
	var dirty: bool = (
		not is_equal_approx(hp_ratio, clamped_hp)
		or not is_equal_approx(wealth_pressure_log, p_wealth_pressure_log)
		or not is_equal_approx(hit_flash, clamped_flash)
	)
	hp_ratio = clamped_hp
	wealth_pressure_log = p_wealth_pressure_log
	hit_flash = clamped_flash

	if _subject_rect.texture == null:
		var retry_tex: Texture2D = ArtRegistryScript.load_texture_safe(subject_res_path)
		if retry_tex != null:
			_subject_rect.texture = retry_tex
			dirty = true

	if _subject_mat != null:
		_subject_mat.set_shader_parameter("wealth_pressure", clampf(wealth_pressure_log, -1.0, 1.0))
		_subject_mat.set_shader_parameter("hit_flash", hit_flash)
	if dirty:
		queue_redraw()

func trigger_hit_flash() -> void:
	_ensure_subject_nodes()
	hit_flash = 1.0
	_recoil_timer = RECOIL_DURATION
	if _subject_mat != null:
		_subject_mat.set_shader_parameter("hit_flash", 1.0)
	_apply_recoil_offset()
	queue_redraw()

func trigger_death_dissolve() -> void:
	_ensure_subject_nodes()
	if _subject_rect.texture == null or _dissolve_ghost_rect == null or _dissolve_mat == null:
		return
	_dissolve_ghost_rect.texture = _subject_rect.texture
	_dissolve_ghost_rect.position = _get_base_subject_rect().position
	_dissolve_ghost_rect.size = _get_base_subject_rect().size
	_dissolve_mat.set_shader_parameter("color_family", accent_color)
	_dissolve_mat.set_shader_parameter("wealth_pressure", clampf(wealth_pressure_log, -1.0, 1.0))
	_dissolve_mat.set_shader_parameter("hit_flash", 0.0)
	_dissolve_mat.set_shader_parameter("dissolve_amount", 0.04)
	_dissolve_ghost_rect.visible = true
	_dissolve_active = true
	_dissolve_elapsed = 0.0

func _process(delta: float) -> void:
	step_visuals(delta)

func step_visuals(delta: float) -> void:
	_ensure_subject_nodes()
	var need_redraw: bool = false

	if hit_flash > 0.0:
		hit_flash = maxf(0.0, hit_flash - delta / HIT_FLASH_DURATION)
		if _subject_mat != null:
			_subject_mat.set_shader_parameter("hit_flash", hit_flash)
		need_redraw = true

	if _recoil_timer > 0.0:
		_recoil_timer = maxf(0.0, _recoil_timer - delta)
		_apply_recoil_offset()

	if _dissolve_active and _dissolve_ghost_rect != null and _dissolve_mat != null:
		_dissolve_elapsed += delta
		var ratio: float = clampf(_dissolve_elapsed / DISSOLVE_DURATION, 0.0, 1.0)
		_dissolve_mat.set_shader_parameter("dissolve_amount", ratio)
		if ratio >= 1.0:
			_dissolve_active = false
			_dissolve_ghost_rect.visible = false

	if need_redraw:
		queue_redraw()

func _get_base_subject_rect() -> Rect2:
	var pad: float = 4.0 if role == CardRole.QUEUE_MOB else 7.0
	if role == CardRole.BOSS_MOB:
		pad = 6.0
	var base_pos: Vector2 = Vector2(pad, pad)
	var base_sz: Vector2 = Vector2(maxf(8.0, size.x - pad * 2.0), maxf(8.0, size.y - pad * 2.0))
	if is_elite and role == CardRole.MAIN_MOB:
		var grow: Vector2 = base_sz * 0.03
		base_pos -= grow * 0.5
		base_sz += grow
	return Rect2(base_pos, base_sz)

func _apply_recoil_offset() -> void:
	if _subject_rect == null:
		return
	var base_r: Rect2 = _get_base_subject_rect()
	var offset: Vector2 = Vector2.ZERO
	if _recoil_timer > 0.0:
		var phase: float = 1.0 - (_recoil_timer / RECOIL_DURATION)
		var wave: float = sin(phase * PI)
		offset = Vector2(RECOIL_PIXELS * wave, -RECOIL_PIXELS * 0.65 * wave)
	_subject_rect.position = base_r.position + offset
	_subject_rect.size = base_r.size

func _sync_subject_layout_and_shader() -> void:
	if _subject_rect == null or _subject_mat == null:
		return
	var tex: Texture2D = ArtRegistryScript.load_texture_safe(subject_res_path)
	_subject_rect.texture = tex
	_subject_rect.visible = (tex != null)
	_apply_recoil_offset()

	var bone_c: Color = ThemePaletteScript.color_bone_white()
	var enable_rim: bool = true
	var rim_w: float = 1.5
	if role == CardRole.QUEUE_MOB:
		bone_c = ThemePaletteScript.color_bone_shadow()
		enable_rim = false
		_subject_rect.modulate = Color(1.0, 1.0, 1.0, 0.78)
	else:
		_subject_rect.modulate = Color.WHITE
		if role == CardRole.BOSS_MOB or is_elite:
			rim_w = 1.8

	_subject_mat.set_shader_parameter("color_bone", bone_c)
	_subject_mat.set_shader_parameter("color_family", accent_color)
	_subject_mat.set_shader_parameter("wealth_pressure", clampf(wealth_pressure_log, -1.0, 1.0))
	_subject_mat.set_shader_parameter("hit_flash", hit_flash)
	_subject_mat.set_shader_parameter("enable_outline", enable_rim)
	_subject_mat.set_shader_parameter("outline_width", rim_w)

func has_formal_texture() -> bool:
	return _subject_rect != null and _subject_rect.texture != null

func get_subject_shader_material() -> ShaderMaterial:
	return _subject_mat

func get_dissolve_shader_material() -> ShaderMaterial:
	return _dissolve_mat

func is_dissolve_active() -> bool:
	return _dissolve_active

func get_recoil_offset() -> Vector2:
	if _subject_rect == null:
		return Vector2.ZERO
	return _subject_rect.position - _get_base_subject_rect().position

func _draw() -> void:
	var rect: Rect2 = Rect2(Vector2.ZERO, size)
	if rect.size.x < 8.0 or rect.size.y < 8.0:
		return

	var card_bg: Color = ThemePaletteScript.color_card_bg()
	var frame_col: Color = ThemePaletteScript.color_old_gold()
	if role == CardRole.BOSS_MOB or is_elite:
		frame_col = ThemePaletteScript.color_old_gold_bright()
	elif role == CardRole.QUEUE_MOB:
		frame_col = ThemePaletteScript.color_iron_gray()

	# 1. #16161C 实体卡底与 1px 塔罗外框
	draw_rect(rect, card_bg, true)
	draw_rect(Rect2(Vector2(0.5, 0.5), rect.size - Vector2(1.0, 1.0)), frame_col, false, 1.0)

	# 2. 内衬几何边饰框与 Boss 哥特拱门 + 符印底环（纯几何刀痕，零伪文字）
	var inset: float = 4.0 if role == CardRole.QUEUE_MOB else 6.0
	var inner_rect: Rect2 = Rect2(
		Vector2(inset, inset),
		Vector2(maxf(2.0, rect.size.x - inset * 2.0), maxf(2.0, rect.size.y - inset * 2.0))
	)
	var inner_stroke: Color = Color(frame_col.r, frame_col.g, frame_col.b, 0.42)
	draw_rect(inner_rect, inner_stroke, false, 1.0)

	if role == CardRole.BOSS_MOB:
		var arch_center: Vector2 = Vector2(rect.size.x * 0.5, inner_rect.position.y + inner_rect.size.x * 0.42)
		var arch_radius: float = inner_rect.size.x * 0.44
		draw_arc(arch_center, arch_radius, PI, TAU, 28, frame_col, 1.5)
		draw_arc(arch_center, arch_radius - 5.0, PI, TAU, 24, inner_stroke, 1.0)
		var sigil_c: Vector2 = Vector2(rect.size.x * 0.5, rect.size.y * 0.86)
		draw_arc(sigil_c, inner_rect.size.x * 0.28, 0.0, TAU, 28, inner_stroke, 1.2)

	var scale_u: float = minf(rect.size.x / 176.0, rect.size.y / 220.0)
	var corners: Array[Vector2] = [
		inner_rect.position,
		Vector2(inner_rect.end.x, inner_rect.position.y),
		inner_rect.end,
		Vector2(inner_rect.position.x, inner_rect.end.y)
	]
	for c_pt: Vector2 in corners:
		draw_circle(c_pt, maxf(1.2, 1.8 * scale_u), frame_col)

	if role != CardRole.QUEUE_MOB:
		var foot_y: float = rect.size.y * 0.92
		draw_line(
			Vector2(inner_rect.position.x + 8.0, foot_y),
			Vector2(inner_rect.end.x - 8.0, foot_y),
			inner_stroke,
			1.2
		)

	# 仅当正式纹理尚未生成落盘时的极简剪影兜底；正式纹理存在时 100% 由 _subject_rect 渲染
	if not has_formal_texture():
		var fallback_col: Color = ThemePaletteScript.color_iron_gray()
		draw_arc(rect.size * 0.5, minf(rect.size.x, rect.size.y) * 0.22, 0.0, TAU, 20, fallback_col, 2.0)
