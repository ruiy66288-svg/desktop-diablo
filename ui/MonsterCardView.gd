class_name MonsterCardView extends Control

## 程序化塔罗怪物卡与排队卡视图 (依据《03_美术风格圣经_v1.0.md》§02.1–§02.3 与《04_美术资产管线_v1.1.md》§1.1–§1.3)
## 在 D3 WP-09 正式美术资产经 Gate-U1 审批接入前，使用 100% 纯代码木刻版画剪影与塔罗拱门卡框绘制
## 严禁引用任何未登记于 manifest.csv 的 AI 测试图，零文字伪符文

const ThemePaletteScript = preload("res://ui/ThemePalette.gd")

enum CardRole {
	MAIN_MOB,
	BOSS_MOB,
	QUEUE_MOB
}

var role: CardRole = CardRole.MAIN_MOB
var hp_ratio: float = 1.0
var wealth_pressure_log: float = 0.0
var hit_flash: float = 0.0
var mob_title: String = ""

func setup_role(p_role: CardRole, p_title: String = "") -> void:
	role = p_role
	mob_title = p_title
	queue_redraw()

func update_combat_visuals(p_hp_ratio: float, p_wealth_pressure_log: float, p_hit_flash: float = 0.0) -> void:
	var clamped_hp: float = clampf(p_hp_ratio, 0.0, 1.0)
	var clamped_flash: float = clampf(p_hit_flash, 0.0, 1.0)
	if (
		not is_equal_approx(hp_ratio, clamped_hp)
		or not is_equal_approx(wealth_pressure_log, p_wealth_pressure_log)
		or not is_equal_approx(hit_flash, clamped_flash)
	):
		hp_ratio = clamped_hp
		wealth_pressure_log = p_wealth_pressure_log
		hit_flash = clamped_flash
		queue_redraw()

func trigger_hit_flash() -> void:
	hit_flash = 1.0
	queue_redraw()

func _process(delta: float) -> void:
	if hit_flash > 0.0:
		hit_flash = maxf(0.0, hit_flash - delta * 14.0)
		queue_redraw()

func _draw() -> void:
	var rect: Rect2 = Rect2(Vector2.ZERO, size)
	if rect.size.x < 8.0 or rect.size.y < 8.0:
		return

	var card_bg: Color = ThemePaletteScript.color_card_bg()
	var ink_col: Color = ThemePaletteScript.color_ink_black()
	var bone_col: Color = ThemePaletteScript.color_bone_white()
	var bone_dim: Color = ThemePaletteScript.color_bone_shadow()
	var frame_col: Color = ThemePaletteScript.color_old_gold()
	if role == CardRole.BOSS_MOB:
		frame_col = ThemePaletteScript.color_old_gold_bright()
	elif role == CardRole.QUEUE_MOB:
		frame_col = ThemePaletteScript.color_iron_gray()
		bone_col = Color(bone_dim.r, bone_dim.g, bone_dim.b, 0.58)

	# 1. 绘制 #16161C 实体卡底与外层 1px 塔罗卡框
	draw_rect(rect, card_bg, true)
	draw_rect(Rect2(Vector2(0.5, 0.5), rect.size - Vector2(1.0, 1.0)), frame_col, false, 1.0)

	# 2. 内衬版画边饰框（纯几何直线与塔罗拱门，零伪文字）
	var inset: float = 4.0 if role == CardRole.QUEUE_MOB else 6.0
	var inner_rect: Rect2 = Rect2(
		Vector2(inset, inset),
		Vector2(maxf(2.0, rect.size.x - inset * 2.0), maxf(2.0, rect.size.y - inset * 2.0))
	)
	var inner_stroke: Color = Color(frame_col.r, frame_col.g, frame_col.b, 0.45)
	draw_rect(inner_rect, inner_stroke, false, 1.0)

	if role == CardRole.BOSS_MOB:
		var arch_center: Vector2 = Vector2(rect.size.x * 0.5, inner_rect.position.y + inner_rect.size.x * 0.42)
		var arch_radius: float = inner_rect.size.x * 0.44
		draw_arc(arch_center, arch_radius, PI, TAU, 24, frame_col, 1.5)

	# 3. 计算镀金层随净财富压力 Δh_wealth 的视觉表现 (04 §1.3)
	var gilded_col: Color = ThemePaletteScript.color_gilded_gold()
	var show_gilded: bool = true
	if wealth_pressure_log > 0.02:
		var boost: float = clampf(wealth_pressure_log / 0.47712125, 0.0, 1.0)
		gilded_col = gilded_col.lerp(ThemePaletteScript.color_coin_gold(), 0.65 * boost)
	elif wealth_pressure_log < -0.05:
		var strip_ratio: float = clampf(-wealth_pressure_log / 0.39794001, 0.0, 1.0)
		gilded_col = gilded_col.lerp(bone_dim, 0.75 * strip_ratio)
		if strip_ratio > 0.85:
			show_gilded = false

	# 受击闪白混色
	var lit_bone: Color = bone_col.lerp(Color.WHITE, hit_flash * 0.85)
	var lit_gilded: Color = gilded_col.lerp(Color.WHITE, hit_flash * 0.70)

	# 4. 绘制粗刀木刻主体剪影占位（正面塔罗对称站姿 + 财富债契母题）
	var cx: float = rect.size.x * 0.5
	var cy: float = rect.size.y * 0.50
	var scale_u: float = minf(rect.size.x / 176.0, rect.size.y / 220.0)

	if role == CardRole.BOSS_MOB:
		_draw_boss_woodcut_emblem(Vector2(cx, cy), scale_u, ink_col, lit_bone, lit_gilded, show_gilded)
	else:
		_draw_mob_woodcut_emblem(Vector2(cx, cy), scale_u, ink_col, lit_bone, lit_gilded, show_gilded)

	# 5. 四角几何铆钉刀痕
	var tick_len: float = 5.0 * scale_u
	var corners: Array[Vector2] = [
		inner_rect.position,
		Vector2(inner_rect.end.x, inner_rect.position.y),
		inner_rect.end,
		Vector2(inner_rect.position.x, inner_rect.end.y)
	]
	for c_pt: Vector2 in corners:
		draw_circle(c_pt, maxf(1.2, 1.8 * scale_u), frame_col)
	if tick_len >= 2.5 and role != CardRole.QUEUE_MOB:
		var foot_y: float = rect.size.y * 0.90
		draw_line(
			Vector2(inner_rect.position.x + 8.0, foot_y),
			Vector2(inner_rect.end.x - 8.0, foot_y),
			inner_stroke,
			1.5
		)

func _draw_mob_woodcut_emblem(
	center: Vector2,
	s: float,
	ink_col: Color,
	bone_col: Color,
	gilded_col: Color,
	show_gilded: bool
) -> void:
	# 守财亡骸粗刀木刻几何主体：对称肩甲剪影 + 颅骨受光块 + 肋骨横刀排线 + 金币眼窝与钱袋债链
	var torso_pts: PackedVector2Array = PackedVector2Array([
		center + Vector2(-34.0, -24.0) * s,
		center + Vector2(34.0, -24.0) * s,
		center + Vector2(24.0, 48.0) * s,
		center + Vector2(30.0, 74.0) * s,
		center + Vector2(-30.0, 74.0) * s,
		center + Vector2(-24.0, 48.0) * s
	])
	draw_colored_polygon(torso_pts, bone_col)
	# 右下阴影墨黑块（左上 45° 主光，右侧大块墨黑）
	var shadow_pts: PackedVector2Array = PackedVector2Array([
		center + Vector2(2.0, -24.0) * s,
		center + Vector2(34.0, -24.0) * s,
		center + Vector2(24.0, 48.0) * s,
		center + Vector2(30.0, 74.0) * s,
		center + Vector2(0.0, 74.0) * s
	])
	draw_colored_polygon(shadow_pts, ink_col)

	# 颅骨主剪影
	var head_center: Vector2 = center + Vector2(0.0, -48.0) * s
	draw_circle(head_center, 22.0 * s, bone_col)
	draw_rect(
		Rect2(head_center + Vector2(-13.0, 10.0) * s, Vector2(26.0, 14.0) * s),
		bone_col,
		true
	)

	# 粗刀木刻肋骨横排线（线宽 >= 2px）
	var stroke_w: float = maxf(2.0, 3.0 * s)
	for rib_idx: int in range(4):
		var ry: float = (-12.0 + float(rib_idx) * 13.0) * s
		draw_line(
			center + Vector2(-22.0 * s, ry),
			center + Vector2(20.0 * s, ry),
			ink_col,
			stroke_w
		)

	# 眼窝墨黑与镀金金币母题 (04 §1.1 守财亡骸：眼窝嵌金币、肋骨缠钱袋)
	var left_eye: Vector2 = head_center + Vector2(-8.0, -2.0) * s
	var right_eye: Vector2 = head_center + Vector2(8.0, -2.0) * s
	draw_circle(left_eye, 5.5 * s, ink_col)
	draw_circle(right_eye, 5.5 * s, ink_col)

	if show_gilded:
		draw_circle(left_eye, 3.6 * s, gilded_col)
		draw_arc(right_eye, 3.6 * s, 0.0, TAU, 12, gilded_col, maxf(1.5, 2.0 * s))
		# 胸前债契挂锁/钱袋镀金块
		var lock_rect: Rect2 = Rect2(center + Vector2(-9.0, 18.0) * s, Vector2(18.0, 20.0) * s)
		draw_rect(lock_rect, gilded_col, true)
		draw_rect(lock_rect, ink_col, false, maxf(1.5, 2.0 * s))
		draw_arc(center + Vector2(0.0, 18.0) * s, 6.5 * s, PI, TAU, 12, gilded_col, maxf(1.5, 2.2 * s))

func _draw_boss_woodcut_emblem(
	center: Vector2,
	s: float,
	ink_col: Color,
	bone_col: Color,
	gilded_col: Color,
	show_gilded: bool
) -> void:
	# 深渊魔主粗刀木刻几何主体（03 §02.3：宽肩 >= 70%，双主导特征：巨角 + 镀金王冠）
	var mantle_pts: PackedVector2Array = PackedVector2Array([
		center + Vector2(-58.0, -28.0) * s,
		center + Vector2(58.0, -28.0) * s,
		center + Vector2(44.0, 82.0) * s,
		center + Vector2(-44.0, 82.0) * s
	])
	draw_colored_polygon(mantle_pts, bone_col)

	var dark_mass: PackedVector2Array = PackedVector2Array([
		center + Vector2(-6.0, -28.0) * s,
		center + Vector2(58.0, -28.0) * s,
		center + Vector2(44.0, 82.0) * s,
		center + Vector2(-14.0, 82.0) * s
	])
	draw_colored_polygon(dark_mass, ink_col)

	# 双巨角剪影
	var left_horn: PackedVector2Array = PackedVector2Array([
		center + Vector2(-18.0, -52.0) * s,
		center + Vector2(-54.0, -84.0) * s,
		center + Vector2(-32.0, -38.0) * s
	])
	var right_horn: PackedVector2Array = PackedVector2Array([
		center + Vector2(18.0, -52.0) * s,
		center + Vector2(54.0, -84.0) * s,
		center + Vector2(32.0, -38.0) * s
	])
	draw_colored_polygon(left_horn, bone_col)
	draw_colored_polygon(right_horn, bone_col)

	# 头部与平行金属横刀痕
	var head_pos: Vector2 = center + Vector2(0.0, -48.0) * s
	draw_circle(head_pos, 24.0 * s, bone_col)
	var hatch_w: float = maxf(2.0, 3.2 * s)
	for band_idx: int in range(5):
		var by: float = (-14.0 + float(band_idx) * 16.0) * s
		draw_line(
			center + Vector2(-42.0 * s, by),
			center + Vector2(38.0 * s, by),
			ink_col,
			hatch_w
		)

	# 镀金王冠与债链天平母题
	if show_gilded:
		var crown_pts: PackedVector2Array = PackedVector2Array([
			head_pos + Vector2(-20.0, -18.0) * s,
			head_pos + Vector2(-14.0, -36.0) * s,
			head_pos + Vector2(-5.0, -23.0) * s,
			head_pos + Vector2(0.0, -40.0) * s,
			head_pos + Vector2(5.0, -23.0) * s,
			head_pos + Vector2(14.0, -36.0) * s,
			head_pos + Vector2(20.0, -18.0) * s
		])
		draw_colored_polygon(crown_pts, gilded_col)
		draw_line(
			center + Vector2(-38.0, 8.0) * s,
			center + Vector2(38.0, 36.0) * s,
			gilded_col,
			maxf(2.0, 3.2 * s)
		)
		draw_circle(center + Vector2(0.0, 22.0) * s, 11.0 * s, gilded_col)
		draw_circle(center + Vector2(0.0, 22.0) * s, 5.0 * s, ink_col)
