class_name ObjectPool extends RefCounted

## 高性能通用对象池 (符合 02号文件 §3.3 规范)
## 杜绝高频掉落与飘字带来的 GC 停顿与节点反复创建开销

var _factory: Callable
var _reset: Callable
var _available: Array = []
var _active_count: int = 0
var max_capacity: int = 120

func _init(factory_func: Callable, reset_func: Callable = Callable(), capacity: int = 120) -> void:
	_factory = factory_func
	_reset = reset_func
	max_capacity = capacity

## 预热对象池
func prewarm(count: int) -> void:
	for _i in range(mini(count, max_capacity)):
		var obj: Variant = _factory.call()
		_available.push_back(obj)

## 从池中获取可用对象
func acquire() -> Variant:
	var obj: Variant = null
	if not _available.is_empty():
		obj = _available.pop_back()
	elif _active_count < max_capacity:
		obj = _factory.call()
	else:
		return null # 池已满且达到最大容量上限

	_active_count += 1
	if _reset.is_valid():
		_reset.call(obj)
	return obj

## 将对象释放归还池中
func release(obj: Variant) -> void:
	if obj == null:
		return
	_active_count = maxi(0, _active_count - 1)
	if _available.size() < max_capacity:
		_available.push_back(obj)

func get_active_count() -> int:
	return _active_count

func get_available_count() -> int:
	return _available.size()

func clear() -> void:
	_available.clear()
	_active_count = 0
