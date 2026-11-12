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
