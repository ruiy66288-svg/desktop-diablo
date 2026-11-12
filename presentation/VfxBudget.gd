class_name VfxBudget extends RefCounted

## 特效与渲染预算管理器 (依据《02_系统架构与数值_v6.md》§6.3 & 《03_美术风格圣经_v1.0.md》§02.6)
## 杜绝同屏过量粒子/震屏导致的掉帧与雪崩，锁定 30fps；支持优先级抢占、同类合并与超帧时自动降级

const MAX_VFX_PER_FRAME: int = 24
const MAX_SFX_PER_FRAME: int = 6
const MERGE_THRESHOLD: int = 4
const DEGRADE_FRAME_MS: float = 30.0

var _vfx_spawned_this_frame: int = 0
var _sfx_spawned_this_frame: int = 0
var _pending_vfx_by_type: Dictionary = {} # type -> count
var _frame_counts_by_type: Dictionary = {} # type -> count
var _last_frame_ms: float = 16.0
var _trails_disabled: bool = false
var _shake_disabled: bool = false
var _particle_density_scale: float = 1.0

## 新的一帧开始时重置计数并依据上一帧耗时执行自动降级 (§6.3)
func begin_frame(last_frame_ms: float = 16.0) -> void:
	_vfx_spawned_this_frame = 0
	_sfx_spawned_this_frame = 0
	_pending_vfx_by_type.clear()
	_frame_counts_by_type.clear()
	_last_frame_ms = maxf(0.0, last_frame_ms)

	if _last_frame_ms > DEGRADE_FRAME_MS:
		_trails_disabled = true
		_shake_disabled = true
		_particle_density_scale = 0.5
	else:
		_trails_disabled = false
		_shake_disabled = false
		_particle_density_scale = 1.0

## 请求生成特效配额 (带优先级: 0=普通, 1=签名词条, 2=Boss, 3=暗金/太古)
func request_vfx(vfx_type: String, priority: int = 0) -> bool:
	var prev_type_count: int = int(_frame_counts_by_type.get(vfx_type, 0))
	_frame_counts_by_type[vfx_type] = prev_type_count + 1

	# 高优先级 (Boss / 暗金太古) 无条件放行
	if priority >= 2:
		_vfx_spawned_this_frame += 1
		return true

	# 同类单帧 >= 4 个或超出总预算 24 时，转入合并池 (例: 30 个合成 1 个放大版 + "×30")
	if _vfx_spawned_this_frame >= MAX_VFX_PER_FRAME or prev_type_count >= MERGE_THRESHOLD:
		_pending_vfx_by_type[vfx_type] = int(_pending_vfx_by_type.get(vfx_type, 0)) + 1
		return false

	_vfx_spawned_this_frame += 1
	return true

## 请求生成音效配额 (单帧总上限 6)
func request_sfx() -> bool:
	if _sfx_spawned_this_frame >= MAX_SFX_PER_FRAME:
		return false
	_sfx_spawned_this_frame += 1
	return true

func get_vfx_spawned_this_frame() -> int:
	return _vfx_spawned_this_frame

func get_sfx_spawned_this_frame() -> int:
	return _sfx_spawned_this_frame

func is_trails_disabled() -> bool:
	return _trails_disabled

func is_shake_disabled() -> bool:
	return _shake_disabled

func get_particle_density_scale() -> float:
	return _particle_density_scale

## 获取本帧被合并的超额特效信息 (例: 30个爆炸合成一个带 ×30 标记的大冲击)
func get_compacted_overflows() -> Dictionary:
	return _pending_vfx_by_type
