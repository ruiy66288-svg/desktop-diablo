class_name AttentionGlow extends Control

## L5 窗口边缘提醒光带 (02 号文件 §5.4 + 03 号文件 §02.6)
## 拉力而非压力: 仅在窗口边缘亮起一道细微呼吸光带 + 角标, 默认不弹系统通知
## 五种信号 (优先级由高到低): 暗金/太古新装 > 可转生 > 研究完成 > 信用升级 > 卡墙
## 去重: 同类信号重复触发只刷新时长, 不叠加; 同时仅渲染最高优先级一条
## 太古掉落附带 120ms 视觉脉冲 (绯红, 一次性)

const ThemePaletteScript = preload("res://ui/ThemePalette.gd")

const KIND_RESEARCH_DONE: String = "research_done"
const KIND_BETTER_UNIQUE: String = "better_unique"
const KIND_WALL_HINT: String = "wall_hint"
const KIND_CREDIT_TIER_UP: String = "credit_tier_up"
const KIND_PRESTIGE_READY: String = "prestige_ready"

const KIND_ORDER: Array[String] = [
	KIND_BETTER_UNIQUE,
	KIND_PRESTIGE_READY,
	KIND_RESEARCH_DONE,
	KIND_CREDIT_TIER_UP,
	KIND_WALL_HINT
]

const KIND_DURATION_SEC: Dictionary = {
	"research_done": 8.0,
	"better_unique": 10.0,
	"wall_hint": 12.0,
	"credit_tier_up": 8.0,
	"prestige_ready": 14.0
}

const KIND_ICON: Dictionary = {
	"research_done": "研",
	"better_unique": "器",
	"wall_hint": "墙",
	"credit_tier_up": "债",
	"prestige_ready": "魂"
}

const WALL_HINT_TEXT: String = "换 Build 或借钱"
const PULSE_DURATION_SEC: float = 0.12
const BREATH_PERIOD_SEC: float = 1.6
const GLOW_RECT: Rect2 = Rect2(Vector2(2.0, 2.0), Vector2(356.0, 476.0))

var _remaining: Dictionary = {}
var _rarity_of_unique: int = 3
var _pulse_left: float = 0.0
var _breath_time: float = 0.0
var _push_count: int = 0
var _dedup_count: int = 0

func _init() -> void:
	name = "AttentionGlow"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 30
	position = Vector2.ZERO
	size = Vector2(360.0, 480.0)

func _process(delta: float) -> void:
	advance(delta)

## 推进计时 (测试与实时共用)
func advance(delta: float) -> void:
	_breath_time += delta
	if _pulse_left > 0.0:
		_pulse_left = maxf(0.0, _pulse_left - delta)
	var expired: Array[String] = []
	for k: Variant in _remaining.keys():
		var left: float = float(_remaining[k]) - delta
		if left <= 0.0:
			expired.push_back(str(k))
		else:
			_remaining[k] = left
	for e: String in expired:
		_remaining.erase(e)
	queue_redraw()

## 推送一个信号; rarity 仅对 better_unique 有效 (3 暗金 / 4 太古)
## 返回 true 表示新建, false 表示去重刷新
func push_signal(kind: String, rarity: int = 3) -> bool:
	if not KIND_DURATION_SEC.has(kind):
		return false
	_push_count += 1
	var is_new: bool = not _remaining.has(kind)
	_remaining[kind] = float(KIND_DURATION_SEC[kind])
	if not is_new:
		_dedup_count += 1
	if kind == KIND_BETTER_UNIQUE:
		_rarity_of_unique = clampi(rarity, 3, 4)
		if rarity >= 4:
			_pulse_left = PULSE_DURATION_SEC
	queue_redraw()
	return is_new

func clear_signal(kind: String) -> void:
	_remaining.erase(kind)
	queue_redraw()

func clear_all() -> void:
	_remaining.clear()
	_pulse_left = 0.0
	queue_redraw()

func get_active_kinds() -> Array[String]:
	var out: Array[String] = []
	for k: String in KIND_ORDER:
		if _remaining.has(k):
			out.push_back(k)
	return out

## 当前显示的最高优先级信号, 无则返回 ""
func get_top_kind() -> String:
	for k: String in KIND_ORDER:
		if _remaining.has(k):
			return k
	return ""

func get_push_count() -> int:
	return _push_count

func get_dedup_count() -> int:
	return _dedup_count

func is_pulse_active() -> bool:
	return _pulse_left > 0.0

func get_kind_color(kind: String) -> Color:
	match kind:
		KIND_RESEARCH_DONE:
			return Color.html("#5FD0D8")
		KIND_BETTER_UNIQUE:
			return ThemePaletteScript.get_rarity_color(_rarity_of_unique)
		KIND_WALL_HINT:
			return Color.html("#CFCBC0")
		KIND_CREDIT_TIER_UP:
			return Color.html("#5FA85A")
		KIND_PRESTIGE_READY:
			return Color.html("#B45CFF")
		_:
			return Color.TRANSPARENT

## 当前呼吸强度 0..1 (正弦呼吸)
func get_breath_alpha() -> float:
	return 0.5 + 0.5 * sin(TAU * _breath_time / BREATH_PERIOD_SEC)

func _draw() -> void:
	var top: String = get_top_kind()
	var font: Font = get_theme_default_font()

	if _pulse_left > 0.0:
		var pa: float = clampf(_pulse_left / PULSE_DURATION_SEC, 0.0, 1.0)
		var pc: Color = ThemePaletteScript.get_rarity_color(4)
		pc.a = 0.55 * pa
		draw_rect(GLOW_RECT, pc, false, 6.0)

	if top.is_empty():
		return
	var base: Color = get_kind_color(top)
	var breath: float = 0.35 + 0.65 * get_breath_alpha()
	for i: int in range(3):
		var c: Color = base
		c.a = (0.62 - float(i) * 0.2) * breath
		draw_rect(GLOW_RECT.grow(-float(i) * 1.5), c, false, 1.5)

	if font != null:
		var icon: String = str(KIND_ICON.get(top, ""))
		var ic: Color = base
		ic.a = 0.5 + 0.5 * breath
		draw_string(font, Vector2(8.0, 78.0), icon, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 12, ic)
		if top == KIND_WALL_HINT:
			var tc: Color = base
			tc.a = 0.9 * breath
			draw_string(font, Vector2(0.0, 384.0), WALL_HINT_TEXT, HORIZONTAL_ALIGNMENT_CENTER, 360.0, 10, tc)
