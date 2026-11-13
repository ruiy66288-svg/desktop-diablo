class_name ThemePalette extends RefCounted

## 《桌面破坏神》「镀金债契 · 骨白版画」冻结 HEX 色彩规范与纯代码样式工厂
## 依据《03_美术风格圣经_v1.0.md》§01、§02.6、§03 与《04_美术资产管线_v1.1.md》§1.2
## 铁律：严禁用 AI 生成任何 UI/文字/边框；窗口 UI 只使用灰阶、骨白、旧金与镀金

# 1. 背景色系 (§03 冻结 HEX)
const HEX_WINDOW_BG: String = "#0E0F14"
const HEX_CARD_BG: String = "#16161C"
const HEX_INK_BLACK: String = "#0B0A0C"
const HEX_WINDOW_STROKE: String = "#FFFFFF14"

# 2. 灰阶色系 (§03 冻结 HEX)
const HEX_IRON_GRAY: String = "#3A3A42"
const HEX_ASH_GRAY: String = "#6E6A66"

# 3. 骨白与旧金/镀金色系 (§03 & 04 §1.2 冻结 HEX)
const HEX_BONE_WHITE: String = "#E8DCC0"
const HEX_BONE_SHADOW: String = "#B8A888"
const HEX_OLD_GOLD: String = "#B08D57"
const HEX_OLD_GOLD_BRIGHT: String = "#D9B26F"
const HEX_GILDED_GOLD: String = "#C9A04E"
const HEX_COIN_GOLD: String = "#E9C46A"

# 4. 血墨与护盾/伤害飘字 (§03 冻结 HEX，血墨禁止发光)
const HEX_BLOOD_INK: String = "#7A0F14"
const HEX_WINE_RED: String = "#6A1B3A"
const HEX_SHIELD_BLUE: String = "#A8C8E8"
const HEX_CRIT_CORE: String = "#FFF4D6"
const HEX_CRIT_EDGE: String = "#FF5A1F"

# 5. 五档装备品质色 (§03 冻结 HEX：仅用于特效、槽位边框与点缀通道)
const HEX_RARITY_WHITE: String = "#E6E6E6"
const HEX_RARITY_BLUE: String = "#4C8DFF"
const HEX_RARITY_PURPLE: String = "#B45CFF"
const HEX_RARITY_UNIQUE: String = "#FF9F1A"
const HEX_RARITY_PRIMAL: String = "#FF2E4D"

# 6. 窗口背景视觉参数 (§02.6 & 02号文件 §3.3)
const WINDOW_BG_ALPHA: float = 0.85
const WINDOW_CORNER_RADIUS: int = 12
const PAPER_NOISE_ALPHA: float = 0.03
const PAPER_NOISE_SIZE: int = 64

static var _cached_paper_noise: ImageTexture = null

static func color_window_bg(alpha: float = WINDOW_BG_ALPHA) -> Color:
	var c: Color = Color.html(HEX_WINDOW_BG)
	c.a = alpha
	return c

static func color_card_bg() -> Color:
	return Color.html(HEX_CARD_BG)

static func color_ink_black() -> Color:
	return Color.html(HEX_INK_BLACK)

static func color_window_stroke() -> Color:
	return Color.html(HEX_WINDOW_STROKE)

static func color_iron_gray() -> Color:
	return Color.html(HEX_IRON_GRAY)

static func color_ash_gray() -> Color:
	return Color.html(HEX_ASH_GRAY)

static func color_bone_white() -> Color:
	return Color.html(HEX_BONE_WHITE)

static func color_bone_shadow() -> Color:
	return Color.html(HEX_BONE_SHADOW)

static func color_old_gold() -> Color:
	return Color.html(HEX_OLD_GOLD)

static func color_old_gold_bright() -> Color:
	return Color.html(HEX_OLD_GOLD_BRIGHT)

static func color_gilded_gold() -> Color:
	return Color.html(HEX_GILDED_GOLD)

static func color_coin_gold() -> Color:
	return Color.html(HEX_COIN_GOLD)

static func color_blood_ink() -> Color:
	return Color.html(HEX_BLOOD_INK)

static func color_shield() -> Color:
	return Color.html(HEX_SHIELD_BLUE)

static func color_crit_core() -> Color:
	return Color.html(HEX_CRIT_CORE)

static func get_rarity_color(rarity: int) -> Color:
	match rarity:
		0:
			return Color.html(HEX_RARITY_WHITE)
		1:
			return Color.html(HEX_RARITY_BLUE)
		2:
			return Color.html(HEX_RARITY_PURPLE)
		3:
			return Color.html(HEX_RARITY_UNIQUE)
		4:
			return Color.html(HEX_RARITY_PRIMAL)
		_:
			return Color.html(HEX_IRON_GRAY)

## 构建桌面小窗伪磨砂主底板样式 (#0E0F14, alpha=0.85, 圆角 12, 1px #FFFFFF14 描边)
static func make_window_panel_style() -> StyleBoxFlat:
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = color_window_bg(WINDOW_BG_ALPHA)
	box.set_corner_radius_all(WINDOW_CORNER_RADIUS)
	box.set_border_width_all(1)
	box.border_color = color_window_stroke()
	return box

## 构建通用黑底骨白卡框样式 (#16161C 卡底 + 指定 1px 描边色)
static func make_card_style(border_col: Color, corner_radius: int = 4, border_px: int = 1) -> StyleBoxFlat:
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = color_card_bg()
	box.set_corner_radius_all(corner_radius)
	box.set_border_width_all(border_px)
	box.border_color = border_col
	return box

## 构建极简按钮样式（纯代码 StyleBoxFlat）
static func make_button_style(bg_col: Color, border_col: Color, corner_radius: int = 3) -> StyleBoxFlat:
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = bg_col
	box.set_corner_radius_all(corner_radius)
	box.set_border_width_all(1)
	box.border_color = border_col
	box.content_margin_left = 6.0
	box.content_margin_right = 6.0
	box.content_margin_top = 2.0
	box.content_margin_bottom = 2.0
	return box

## 构建怪物血条底槽与血墨填充样式
static func make_hp_track_style() -> StyleBoxFlat:
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = color_card_bg()
	box.set_corner_radius_all(2)
	box.set_border_width_all(1)
	box.border_color = color_old_gold()
	return box

static func make_hp_fill_style() -> StyleBoxFlat:
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = color_blood_ink()
	box.set_corner_radius_all(1)
	return box

## 生成确定性 3% 纸纹噪点平铺纹理 (§01 & §02.6：只有窗口背景允许 3% 程序化纸纹噪点)
static func get_paper_noise_texture() -> ImageTexture:
	if _cached_paper_noise != null:
		return _cached_paper_noise

	var img: Image = Image.create(PAPER_NOISE_SIZE, PAPER_NOISE_SIZE, false, Image.FORMAT_RGBA8)
	var bone_col: Color = color_bone_white()
	var hash_state: int = 0x5A17C3E9

	for y: int in range(PAPER_NOISE_SIZE):
		for x: int in range(PAPER_NOISE_SIZE):
			hash_state = int((hash_state * 1103515245 + 12345 + x * 31 + y * 97) & 0x7FFFFFFF)
			var norm: float = float(hash_state % 256) / 255.0
			# 刻刀纸纹：稀疏粗颗粒木浆肌理，均值控制在 3% 不透明度
			var grain_alpha: float = PAPER_NOISE_ALPHA * (0.4 + 0.8 * step_quantize(norm))
			img.set_pixel(x, y, Color(bone_col.r, bone_col.g, bone_col.b, grain_alpha))

	_cached_paper_noise = ImageTexture.create_from_image(img)
	return _cached_paper_noise

static func step_quantize(v: float) -> float:
	if v > 0.72:
		return 1.0
	if v > 0.38:
		return 0.45
	return 0.0

# ---- 思源宋体 (Noto Serif SC, SIL OFL 1.1) 自适应绑定: 文件存在则全局挂载, 不存在平滑回退默认字体 ----
const SERIF_FONT_CANDIDATES: Array[String] = [
	"res://assets/fonts/NotoSerifSC-Subset.ttf",
	"res://assets/fonts/NotoSerifSC-Subset.otf"
]

static var _cached_serif_font: Font = null
static var _serif_font_probed: bool = false

static func get_serif_font_path() -> String:
	for p: String in SERIF_FONT_CANDIDATES:
		if FileAccess.file_exists(p) or ResourceLoader.exists(p):
			return p
	return ""

static func has_serif_font() -> bool:
	return not get_serif_font_path().is_empty()

static func get_serif_font() -> Font:
	if _serif_font_probed:
		return _cached_serif_font
	_serif_font_probed = true
	var path: String = get_serif_font_path()
	if path.is_empty():
		return null
	var loaded: Font = null
	if ResourceLoader.exists(path):
		loaded = ResourceLoader.load(path) as Font
	if loaded == null:
		var ff: FontFile = FontFile.new()
		var abs_path: String = ProjectSettings.globalize_path(path)
		var err: Error = ff.load_dynamic_font(abs_path)
		if err == OK:
			loaded = ff
	_cached_serif_font = loaded
	return _cached_serif_font

static func reset_font_probe() -> void:
	_cached_serif_font = null
	_serif_font_probed = false

## 构造带衬线主字体的 Theme (字体缺失时返回 null, 调用方保持默认字体)
static func make_serif_theme() -> Theme:
	var f: Font = get_serif_font()
	if f == null:
		return null
	var th: Theme = Theme.new()
	th.default_font = f
	return th
