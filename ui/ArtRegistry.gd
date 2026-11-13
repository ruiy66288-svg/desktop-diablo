class_name ArtRegistry extends RefCounted

## 《桌面破坏神》WP-09 正式木刻版画资产注册表与安全加载器
## 严格绑定 manifest.csv 登记的 10 件四通道 RGBA 主体资产 + 1 件 PixelFX 归一化爆炸图集 + palette_subject.gdshader
## 铁律：100% 显式静态类型，零 :=

const SHADER_PALETTE_SUBJECT: String = "res://assets/art/shaders/palette_subject.gdshader"

# 1. 怪物资产 (352×440, 四通道 RGBA) - 阶段 2 五大族群
const MON_UNDEAD_MISER: String = "res://assets/art/monsters/mon_undead_miser_v01.png"
const MON_DEMON_DEBTOR: String = "res://assets/art/monsters/mon_demon_debtor_v01.png"
const MON_BEAST_GOLDMAW: String = "res://assets/art/monsters/mon_beast_goldmaw_v01.png"
const MON_IDOL_SCALES: String = "res://assets/art/monsters/mon_idol_scales_v01.png"
const MON_CULT_PAWNBROKER: String = "res://assets/art/monsters/mon_cult_pawnbroker_v01.png"

# 2. Boss 资产 (416×520, 四通道 RGBA)
const BOSS_ABYSS_LORD: String = "res://assets/art/bosses/boss_demon_abyss-lord_v01.png"
const BOSS_RARE_ARCHON: String = "res://assets/art/bosses/boss_rare_archon_v01.png"

# 3. 六槽装备底材资产 (96×96, 四通道 RGBA)
const ITEM_WEAPON: String = "res://assets/art/items/eq_weapon_base_greatsword_v01.png"
const ITEM_HELM: String = "res://assets/art/items/eq_helm_base_greathelm_v01.png"
const ITEM_CHEST: String = "res://assets/art/items/eq_chest_base_cuirass_v01.png"
const ITEM_GLOVES: String = "res://assets/art/items/eq_gloves_base_gauntlets_v01.png"
const ITEM_BOOTS: String = "res://assets/art/items/eq_boots_base_greaves_v01.png"
const ITEM_TRINKET: String = "res://assets/art/items/eq_trinket_base_signet_v01.png"

# 3b. 专属暗金、召唤符文与道具插图 (96×96, 四通道 RGBA)
const UNIQ_WEAPON_THUNDER: String = "res://assets/art/items/uniq_weapon_thunder_blade_v01.png"
const UNIQ_TRINKET_SCALES: String = "res://assets/art/items/uniq_trinket_usurer_scales_v01.png"
const COL_RUNE_SUMMON: String = "res://assets/art/items/col_rune_abyss_summon_v01.png"
const PROP_WEALTH_LEDGER: String = "res://assets/art/items/prop_wealth_ledger_v01.png"

# 3c. 木刻排线平铺底纹 (256×256, 单通道二值无缝)
const TEX_WOODCUT_HATCH: String = "res://assets/art/textures/tex_woodcut_hatch_256_v01.png"

# 4. PixelFX 归一化木刻爆炸序列 (512×512, 4×4=16 帧, 128×128/帧)
const VFX_EXPLOSION_SMALL: String = "res://assets/art/vfx/vfx_explosion_small_16f_128x128.png"

# 5. 族群油墨点缀色 (03 §01 & 04 §1.1 冻结 HEX)
const HEX_ACCENT_UNDEAD: String = "#B08D57" # 不死族：旧金
const HEX_ACCENT_DEMON: String = "#7A0F14"  # 恶魔族：血墨
const HEX_ACCENT_BEAST: String = "#4E7A3A"  # 异兽族：苔绿
const HEX_ACCENT_IDOL: String = "#B08D57"   # 堕圣族：镀金圣像旧金
const HEX_ACCENT_CULT: String = "#6A1B3A"   # 深渊族：典当教团酒红
const HEX_ACCENT_SHIELD: String = "#A8C8E8" # 护盾机制区间变体
const HEX_ACCENT_ARCHON: String = "#C9A04E" # 契约大执政官：高阶鎏金

static var _tex_cache: Dictionary = {}
static var _shader_cache: Shader = null

static func get_all_formal_subject_paths() -> Array[String]:
	return [
		MON_UNDEAD_MISER,
		MON_DEMON_DEBTOR,
		MON_BEAST_GOLDMAW,
		MON_IDOL_SCALES,
		MON_CULT_PAWNBROKER,
		BOSS_ABYSS_LORD,
		BOSS_RARE_ARCHON,
		ITEM_WEAPON,
		ITEM_HELM,
		ITEM_CHEST,
		ITEM_GLOVES,
		ITEM_BOOTS,
		ITEM_TRINKET,
		UNIQ_WEAPON_THUNDER,
		UNIQ_TRINKET_SCALES,
		COL_RUNE_SUMMON,
		PROP_WEALTH_LEDGER
	]

static func get_woodcut_hatch_texture() -> Texture2D:
	return load_texture_safe(TEX_WOODCUT_HATCH)

static func get_rare_boss_path() -> String:
	return BOSS_RARE_ARCHON

static func get_summon_rune_texture() -> Texture2D:
	return load_texture_safe(COL_RUNE_SUMMON)

static func get_wealth_ledger_texture() -> Texture2D:
	return load_texture_safe(PROP_WEALTH_LEDGER)

static func get_unique_item_icon_path(slot_key: String) -> String:
	match slot_key:
		"weapon":
			return UNIQ_WEAPON_THUNDER
		"trinket":
			return UNIQ_TRINKET_SCALES
		_:
			return get_item_slot_path(slot_key)

static func get_item_slot_path(slot_key: String) -> String:
	match slot_key:
		"weapon":
			return ITEM_WEAPON
		"helm":
			return ITEM_HELM
		"chest":
			return ITEM_CHEST
		"gloves":
			return ITEM_GLOVES
		"boots":
			return ITEM_BOOTS
		"trinket":
			return ITEM_TRINKET
		_:
			return ITEM_WEAPON

static func clear_cache() -> void:
	_tex_cache.clear()

static func get_palette_shader() -> Shader:
	if _shader_cache == null:
		_shader_cache = ResourceLoader.load(SHADER_PALETTE_SUBJECT) as Shader
	return _shader_cache

static func make_palette_material(
	accent_col: Color,
	enable_outline: bool = true,
	outline_w: float = 1.5
) -> ShaderMaterial:
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = get_palette_shader()
	mat.set_shader_parameter("color_ink", Color.html("#0B0A0C"))
	mat.set_shader_parameter("color_bone", Color.html("#E8DCC0"))
	mat.set_shader_parameter("color_family", accent_col)
	mat.set_shader_parameter("color_gold", Color.html("#C9A04E"))
	mat.set_shader_parameter("color_gold_bright", Color.html("#E9C46A"))
	mat.set_shader_parameter("hit_flash", 0.0)
	mat.set_shader_parameter("dissolve_amount", 0.0)
	mat.set_shader_parameter("wealth_pressure", 0.0)
	mat.set_shader_parameter("enable_outline", enable_outline)
	mat.set_shader_parameter("outline_width", outline_w)
	return mat

static func _has_imported_ctex(res_path: String) -> bool:
	var import_path: String = res_path + ".import"
	if not FileAccess.file_exists(import_path):
		return false
	var f: FileAccess = FileAccess.open(import_path, FileAccess.READ)
	if f == null:
		return false
	while not f.eof_reached():
		var line: String = f.get_line().strip_edges()
		if line.begins_with("path=\""):
			var ctex_path: String = line.trim_prefix("path=\"").trim_suffix("\"")
			f.close()
			return FileAccess.file_exists(ctex_path)
	f.close()
	return false

static func load_texture_safe(res_path: String) -> Texture2D:
	if res_path.is_empty():
		return null
	if _tex_cache.has(res_path):
		var cached: Texture2D = _tex_cache[res_path] as Texture2D
		if cached != null:
			return cached

	if _has_imported_ctex(res_path):
		var loaded: Texture2D = ResourceLoader.load(res_path) as Texture2D
		if loaded != null:
			_tex_cache[res_path] = loaded
			return loaded

	var abs_path: String = ProjectSettings.globalize_path(res_path)
	if FileAccess.file_exists(abs_path):
		var img: Image = Image.load_from_file(abs_path)
		if img != null and not img.is_empty():
			img.generate_mipmaps()
			var img_tex: ImageTexture = ImageTexture.create_from_image(img)
			if img_tex != null:
				_tex_cache[res_path] = img_tex
				return img_tex
	return null

static func get_item_icon_texture(slot_key: String, is_unique_or_primal: bool = false) -> Texture2D:
	if is_unique_or_primal:
		var u_path: String = get_unique_item_icon_path(slot_key)
		var u_tex: Texture2D = load_texture_safe(u_path)
		if u_tex != null:
			return u_tex
	return load_texture_safe(get_item_slot_path(slot_key))

## 根据层数、同层杀怪序号与 Boss/护盾状态返回怪物表现配置（阶段2 五大族群轮换 + 精英变体 + 深渊魔主/稀有大执政官）
static func get_monster_visual_spec(
	stage: int,
	mob_seq: int,
	is_boss: bool,
	has_shield: bool = false,
	is_rare_boss: bool = false
) -> Dictionary:
	if is_rare_boss:
		return {
			"id": "boss_rare_archon",
			"title": "契约大执政官",
			"res_path": BOSS_RARE_ARCHON,
			"accent": Color.html(HEX_ACCENT_ARCHON),
			"is_elite": false
		}

	if is_boss:
		var boss_accent: Color = Color.html(HEX_ACCENT_SHIELD) if has_shield else Color.html(HEX_ACCENT_DEMON)
		var boss_title: String = "护盾魔主" if has_shield else "深渊魔主"
		return {
			"id": "boss_abyss_lord",
			"title": boss_title,
			"res_path": BOSS_ABYSS_LORD,
			"accent": boss_accent,
			"is_elite": false
		}

	var idx: int = posmod(stage * 2 + mob_seq, 5)
	var is_elite: bool = (mob_seq > 0 and posmod(mob_seq, 4) == 3)
	var res_path: String = MON_UNDEAD_MISER
	var base_title: String = "守财亡骸"
	var accent: Color = Color.html(HEX_ACCENT_UNDEAD)

	if idx == 1:
		res_path = MON_DEMON_DEBTOR
		base_title = "契约债魔"
		accent = Color.html(HEX_ACCENT_DEMON)
	elif idx == 2:
		res_path = MON_BEAST_GOLDMAW
		base_title = "吞金腐兽"
		accent = Color.html(HEX_ACCENT_BEAST)
	elif idx == 3:
		res_path = MON_IDOL_SCALES
		base_title = "镀金圣像"
		accent = Color.html(HEX_ACCENT_IDOL)
	elif idx == 4:
		res_path = MON_CULT_PAWNBROKER
		base_title = "典当教徒"
		accent = Color.html(HEX_ACCENT_CULT)

	if has_shield:
		accent = accent.lerp(Color.html(HEX_ACCENT_SHIELD), 0.55)
	if is_elite:
		base_title = "精英·" + base_title

	return {
		"id": "mob_%d" % idx,
		"title": base_title,
		"res_path": res_path,
		"accent": accent,
		"is_elite": is_elite
	}
