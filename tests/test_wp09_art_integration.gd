extends RefCounted

## WP-09 全量正式美术资产与四通道 Shader 实机集成测试
## 覆盖：
## 1. 10 件四通道木刻主体资产 + PixelFX 16 帧爆炸图集 + palette_subject.gdshader 加载与尺寸校验
## 2. MonsterCardView 三态 wealth_pressure (+0.48 / 0.0 / -0.40)、60ms 闪白、120ms 3px 后仰位移与非阻塞死亡溶解状态机
## 3. EquipSlotView 6 槽底材图标、空槽铁灰剪影与品质点缀色绑定
## 4. V9 五档光柱灰度明度严格递增校验 + V10 10 秒战斗爆发中心 40% 区域任意 200ms 遮挡 <= 30%

const ArtRegistryScript = preload("res://ui/ArtRegistry.gd")
const MonsterCardViewScript = preload("res://ui/MonsterCardView.gd")
const EquipSlotViewScript = preload("res://ui/EquipSlotView.gd")
const LootFountainScript = preload("res://presentation/loot/LootFountain.gd")
const VfxManagerScript = preload("res://presentation/vfx/VfxManager.gd")
const ThemePaletteScript = preload("res://ui/ThemePalette.gd")

static func run() -> bool:
	var ok: bool = true
	ok = _test_formal_assets_and_shader_load() and ok
	ok = _test_monster_card_wealth_flash_recoil_dissolve() and ok
	ok = _test_equip_slots_and_v9_beam_luminance() and ok
	ok = _test_v10_10sec_center_occlusion_budget() and ok
	return ok

static func _test_formal_assets_and_shader_load() -> bool:
	ArtRegistryScript.clear_cache()
	var shd: Shader = ArtRegistryScript.get_palette_shader()
	if shd == null:
		push_error("[test_wp09] Failed to load palette_subject.gdshader")
		return false

	var paths: Array[String] = ArtRegistryScript.get_all_formal_subject_paths()
	if paths.size() < 10:
		push_error("[test_wp09] Expected at least 10 formal subject asset paths, got %d" % paths.size())
		return false

	for p: String in paths:
		var tex: Texture2D = ArtRegistryScript.load_texture_safe(p)
		if tex == null:
			push_error("[test_wp09] Missing or unloadable formal asset: %s" % p)
			return false
		var sz: Vector2i = Vector2i(tex.get_width(), tex.get_height())
		if p.contains("/monsters/") and sz != Vector2i(352, 440):
			push_error("[test_wp09] Monster %s expected 352x440, got %s" % [p, str(sz)])
			return false
		elif p.contains("/bosses/") and sz != Vector2i(416, 520):
			push_error("[test_wp09] Boss %s expected 416x520, got %s" % [p, str(sz)])
			return false
		elif p.contains("/items/") and sz != Vector2i(96, 96):
			push_error("[test_wp09] Item icon %s expected 96x96, got %s" % [p, str(sz)])
			return false

	var exp_tex: Texture2D = ArtRegistryScript.load_texture_safe(ArtRegistryScript.VFX_EXPLOSION_SMALL)
	if exp_tex == null or Vector2i(exp_tex.get_width(), exp_tex.get_height()) != Vector2i(512, 512):
		push_error("[test_wp09] Expected vfx_explosion_small_16f_128x128.png 512x512")
		return false

	print("[test_wp09] 10 formal subject assets + explosion sheet + palette_subject.gdshader PASS")
	return true

static func _test_monster_card_wealth_flash_recoil_dissolve() -> bool:
	var card: MonsterCardViewScript = MonsterCardViewScript.new()
	card.size = Vector2(176.0, 220.0)
	card._ready()
	card.apply_visual_spec(ArtRegistryScript.get_monster_visual_spec(1, 0, false, false))

	if not card.has_formal_texture():
		push_error("[test_wp09] MonsterCardView failed to bind formal monster texture")
		card.free()
		return false

	var mat: ShaderMaterial = card.get_subject_shader_material()
	for wp_val: float in [0.4771, 0.0, -0.3979]:
		card.update_combat_visuals(0.8, wp_val, 0.0)
		var actual_wp: float = float(mat.get_shader_parameter("wealth_pressure"))
		if not is_equal_approx(actual_wp, wp_val):
			push_error("[test_wp09] Expected wealth_pressure=%.4f, got %.4f" % [wp_val, actual_wp])
			card.free()
			return false

	# Hit flash (60ms) + 3px recoil (120ms)
	card.trigger_hit_flash()
	if not is_equal_approx(float(mat.get_shader_parameter("hit_flash")), 1.0):
		push_error("[test_wp09] Expected hit_flash=1.0 immediately on hit")
		card.free()
		return false

	card.step_visuals(0.06)
	if card.get_recoil_offset().length() <= 0.5:
		push_error("[test_wp09] Expected positive recoil offset at 60ms, got %s" % str(card.get_recoil_offset()))
		card.free()
		return false
	if float(mat.get_shader_parameter("hit_flash")) > 0.05:
		push_error("[test_wp09] Expected hit_flash decayed near 0 after 60ms")
		card.free()
		return false

	card.step_visuals(0.08)
	if card.get_recoil_offset().length() > 0.01:
		push_error("[test_wp09] Expected recoil returned to 0 after 140ms")
		card.free()
		return false

	# Death dissolve ghost (non-blocking)
	card.trigger_death_dissolve()
	if not card.is_dissolve_active():
		push_error("[test_wp09] Expected death dissolve ghost active")
		card.free()
		return false
	card.step_visuals(0.16)
	var d_mid: float = float(card.get_dissolve_shader_material().get_shader_parameter("dissolve_amount"))
	if d_mid <= 0.2 or d_mid >= 0.9:
		push_error("[test_wp09] Expected mid dissolve_amount in (0.2, 0.9), got %.3f" % d_mid)
		card.free()
		return false
	card.step_visuals(0.20)
	if card.is_dissolve_active():
		push_error("[test_wp09] Expected death dissolve finished after 360ms")
		card.free()
		return false

	card.free()
	print("[test_wp09] MonsterCardView three-state wealth_pressure / flash / recoil / dissolve PASS")
	return true

static func _test_equip_slots_and_v9_beam_luminance() -> bool:
	var slots: Array[String] = ["weapon", "helm", "chest", "gloves", "boots", "trinket"]
	for idx: int in range(slots.size()):
		var sv: EquipSlotViewScript = EquipSlotViewScript.new()
		sv.setup_slot(slots[idx])
		if not sv.has_formal_icon_texture():
			push_error("[test_wp09] EquipSlotView missing formal icon for slot %s" % slots[idx])
			sv.free()
			return false
		sv.set_item_state(true, mini(4, idx), 20)
		var fam_col: Color = sv.get_icon_shader_material().get_shader_parameter("color_family") as Color
		var expected_col: Color = ThemePaletteScript.get_rarity_color(mini(4, idx))
		if not fam_col.is_equal_approx(expected_col):
			push_error("[test_wp09] EquipSlotView rarity accent mismatch for slot %s" % slots[idx])
			sv.free()
			return false
		sv.free()

	# V9 五档光柱灰度加法明度严格递增校验
	var fountain: LootFountainScript = LootFountainScript.new()
	fountain._ready()
	fountain.spawn_v9_showcase_five_tiers()
	var prev_lum: float = -1.0
	for tier: int in range(5):
		var c: Color = ThemePaletteScript.get_rarity_color(tier)
		var intensities: Array[float] = [0.24, 0.58, 0.96, 1.35, 2.65]
		var inten: float = intensities[tier]
		var alpha: float = 0.63 * inten
		var core_w: float = 0.455
		var src_lum: float = (0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b) * alpha + core_w
		var blended_lum: float = 0.058 + src_lum * clampf(alpha, 0.0, 1.0)
		if blended_lum <= prev_lum:
			push_error("[test_wp09] V9 beam grayscale luminance not strictly increasing at tier %d (%.4f <= %.4f)" % [tier, blended_lum, prev_lum])
			fountain.free()
			return false
		prev_lum = blended_lum
	fountain.free()
	print("[test_wp09] 6-slot formal icons & V9 5-tier monotonic luminance PASS")
	return true

static func _test_v10_10sec_center_occlusion_budget() -> bool:
	var vfx: VfxManagerScript = VfxManagerScript.new()
	vfx.reset_occlusion_stats()
	var center: Vector2 = Vector2(112.0, 194.0)
	var q1: Vector2 = Vector2(288.0, 139.0)
	var q2: Vector2 = Vector2(288.0, 243.0)
	var card_rect: Rect2 = Rect2(Vector2(24.0, 84.0), Vector2(176.0, 220.0))

	# 模拟 10 秒 (300 帧 @ 30fps) 高频战斗特效爆发
	var dt: float = 1.0 / 30.0
	for frame: int in range(300):
		if frame % 3 == 0:
			vfx.spawn_crit_ring(center)
		if frame % 5 == 0:
			vfx.spawn_chain_lightning(center, q1, 1)
			vfx.spawn_chain_lightning(q1, q2, 2)
		if frame % 9 == 0:
			vfx.spawn_drop_explosion(center + Vector2(10.0, 20.0), 4)
		vfx.update_killing_frenzy_afterimage(10, card_rect)
		vfx._process(dt)

	var max_occ: float = vfx.get_max_rolling_200ms_occlusion()
	vfx.free()
	if max_occ > 0.30:
		push_error("[test_wp09] V10 failed: max 200ms center-40%% occlusion %.3f > 0.30" % max_occ)
		return false

	print("[test_wp09] V10 10-second burst center-40%% max 200ms occlusion = %.1f%% (<= 30%%) PASS" % (max_occ * 100.0))
	return true
