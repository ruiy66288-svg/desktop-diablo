class_name Buffs extends RefCounted

## 统一临时增益/减益管理器 (依据《02_系统架构与数值_v6.md》§2.3)

class BuffInstance extends RefCounted:
	var key: String = ""
	var remaining_ticks: int = 0
	var current_stacks: int = 1
	var max_stacks: int = 1
	var stat: String = ""
	var val_per_stack: float = 0.0
	var charges: int = 0
	var hint: Dictionary = {}

var _active_buffs: Dictionary = {}

func add_buff(
	key: String,
	duration_ticks: int,
	max_stacks: int,
	stat: String,
	val_per_stack: float,
	hint: Dictionary = {}
) -> void:
	if _active_buffs.has(key):
		var buff: BuffInstance = _active_buffs[key] as BuffInstance
		buff.remaining_ticks = maxi(buff.remaining_ticks, duration_ticks)
		buff.current_stacks = mini(buff.current_stacks + 1, max_stacks)
		buff.hint = hint
	else:
		var new_buff: BuffInstance = BuffInstance.new()
		new_buff.key = key
		new_buff.remaining_ticks = duration_ticks
		new_buff.current_stacks = 1
		new_buff.max_stacks = max_stacks
		new_buff.stat = stat
		new_buff.val_per_stack = val_per_stack
		new_buff.hint = hint
		_active_buffs[key] = new_buff

func has_buff(key: String) -> bool:
	return _active_buffs.has(key)

func get_stacks(key: String) -> int:
	if _active_buffs.has(key):
		return (_active_buffs[key] as BuffInstance).current_stacks
	return 0

func get_stat_bonus(stat_name: String) -> float:
	var total: float = 0.0
	for buff_var: Variant in _active_buffs.values():
		var b: BuffInstance = buff_var as BuffInstance
		if b.stat == stat_name:
			total += b.val_per_stack * float(b.current_stacks)
	return total

func tick() -> void:
	var expired_keys: Array[String] = []
	for key_var: Variant in _active_buffs.keys():
		var key: String = str(key_var)
		var buff: BuffInstance = _active_buffs[key] as BuffInstance
		buff.remaining_ticks -= 1
		if buff.remaining_ticks <= 0:
			expired_keys.push_back(key)

	for exp_key: String in expired_keys:
		_active_buffs.erase(exp_key)

func clear() -> void:
	_active_buffs.clear()

func is_empty() -> bool:
	return _active_buffs.is_empty()

## 确定性签名（按 key 排序），供 SimState 状态哈希使用
func get_signature() -> String:
	var keys: Array = _active_buffs.keys()
	keys.sort()
	var parts: PackedStringArray = PackedStringArray()
	for key_var: Variant in keys:
		var b: BuffInstance = _active_buffs[key_var] as BuffInstance
		parts.append("%s:%d:%d" % [b.key, b.current_stacks, b.remaining_ticks])
	return ",".join(parts)

## 存档导出：每个 buff 一条 Dictionary（val_per_stack 以普通 float 存储，JSON 可表示）
func to_array() -> Array:
	var keys: Array = _active_buffs.keys()
	keys.sort()
	var out: Array = []
	for key_var: Variant in keys:
		var b: BuffInstance = _active_buffs[key_var] as BuffInstance
		out.push_back({
			"key": b.key, "remaining_ticks": b.remaining_ticks, "stacks": b.current_stacks,
			"max_stacks": b.max_stacks, "stat": b.stat, "val_per_stack": b.val_per_stack,
			"charges": b.charges, "hint": b.hint.duplicate()
		})
	return out

func load_from_array(data: Array) -> void:
	_active_buffs.clear()
	for item_var: Variant in data:
		var d: Dictionary = item_var as Dictionary
		var b: BuffInstance = BuffInstance.new()
		b.key = String(d.get("key", ""))
		b.remaining_ticks = int(d.get("remaining_ticks", 0))
		b.current_stacks = int(d.get("stacks", 1))
		b.max_stacks = int(d.get("max_stacks", 1))
		b.stat = String(d.get("stat", ""))
		b.val_per_stack = float(d.get("val_per_stack", 0.0))
		b.charges = int(d.get("charges", 0))
		b.hint = (d.get("hint", {}) as Dictionary).duplicate()
		_active_buffs[b.key] = b

func clone() -> Buffs:
	var copy: Buffs = (get_script() as GDScript).new() as Buffs
	for key_var: Variant in _active_buffs.keys():
		var src: BuffInstance = _active_buffs[key_var] as BuffInstance
		var dst: BuffInstance = BuffInstance.new()
		dst.key = src.key
		dst.remaining_ticks = src.remaining_ticks
		dst.current_stacks = src.current_stacks
		dst.max_stacks = src.max_stacks
		dst.stat = src.stat
		dst.val_per_stack = src.val_per_stack
		dst.charges = src.charges
		dst.hint = src.hint.duplicate()
		copy._active_buffs[key_var] = dst
	return copy