class_name Signals extends RefCounted

## 「想瞥一眼」信号系统 (依据《02_系统架构与数值_v6.md》§5.4：拉力，不是压力)
## 五种边缘光带信号：研究完成(青) / 强力新装备(暗金或绯红) / 卡墙(灰白) / 信用升级(绿) / 可转生(紫)
## 同一种信号重复触发只更新载荷、不重复提醒（去重）；多种信号同时存在时按优先级取最高者显示
## 纯 RefCounted，零 Node 依赖；不进入状态哈希（瞬时提示，由 UI 通过 Command.ACK_SIGNAL 确认消除）

enum Kind {
	RESEARCH_DONE = 0,
	BETTER_UNIQUE = 1,
	WALL_HINT = 2,
	CREDIT_TIER_UP = 3,
	PRESTIGE_READY = 4
}

## 优先级（数值越大越优先）：可转生 > 强力新装备 > 研究完成 > 信用升级 > 卡墙提示
const PRIORITY: Dictionary = {
	Kind.PRESTIGE_READY: 50,
	Kind.BETTER_UNIQUE: 40,
	Kind.RESEARCH_DONE: 30,
	Kind.CREDIT_TIER_UP: 20,
	Kind.WALL_HINT: 10
}
const NAMES: Dictionary = {
	Kind.RESEARCH_DONE: "research_done",
	Kind.BETTER_UNIQUE: "better_unique",
	Kind.WALL_HINT: "wall_hint",
	Kind.CREDIT_TIER_UP: "credit_tier_up",
	Kind.PRESTIGE_READY: "prestige_ready"
}
## 光带颜色键（具体 HEX 由 ThemePalette 决定）
const COLOR_KEYS: Dictionary = {
	Kind.RESEARCH_DONE: "cyan",
	Kind.BETTER_UNIQUE: "gold",
	Kind.WALL_HINT: "gray",
	Kind.CREDIT_TIER_UP: "green",
	Kind.PRESTIGE_READY: "purple"
}

var _active: Dictionary = {}

static func get_name_of(kind: int) -> String:
	return String(NAMES.get(kind, ""))

## 触发信号；返回 true 表示首次触发（需要提醒），false 表示已存在仅更新载荷（去重）
func raise_signal(kind: int, payload: Dictionary = {}) -> bool:
	var is_new: bool = not _active.has(kind)
	_active[kind] = payload.duplicate()
	return is_new

func clear_signal(kind: int) -> void:
	_active.erase(kind)

func is_active(kind: int) -> bool:
	return _active.has(kind)

func get_payload(kind: int) -> Dictionary:
	return (_active.get(kind, {}) as Dictionary).duplicate()

## 当前生效信号，按优先级从高到低
func get_active_kinds() -> Array[int]:
	var kinds: Array[int] = []
	for k: Variant in _active.keys():
		kinds.push_back(int(k))
	kinds.sort_custom(func(a: int, b: int) -> bool: return int(PRIORITY[a]) > int(PRIORITY[b]))
	return kinds

## 最高优先级信号快照：{kind, name, priority, color_key, payload}，无信号返回空字典
func get_top() -> Dictionary:
	var kinds: Array[int] = get_active_kinds()
	if kinds.is_empty():
		return {}
	var k: int = kinds[0]
	return {
		"kind": k,
		"name": NAMES[k],
		"priority": PRIORITY[k],
		"color_key": COLOR_KEYS[k],
		"payload": get_payload(k)
	}

func clear_all() -> void:
	_active.clear()

func clone() -> Signals:
	var copy: Signals = (get_script() as GDScript).new() as Signals
	for k: Variant in _active.keys():
		copy._active[k] = (_active[k] as Dictionary).duplicate()
	return copy