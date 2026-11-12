class_name SimRng extends RefCounted

## 《桌面破坏神》确定性伪随机数发生器 (依据《00_开发执行总纲.md》§4.3)
## 严禁使用全局 randf()/randi()；拆分为 combat / loot / collection 三条完全独立的确定性种子流

const DEFAULT_NONZERO_SEED: int = 123456789
const SALT_COMBAT: int = 0x9E3779B9
const SALT_LOOT: int = 0x85EBCA6B
const SALT_COLLECTION: int = 0xC2B2AE35
const U32_MASK: int = 0xFFFFFFFF
const U32_DIVISOR: float = 4294967296.0
const BINOMIAL_EXACT_LIMIT: int = 32
const TWO_PI: float = 6.283185307179586

## 单条独立确定性 Xorshift32 种子流
class RngStream extends RefCounted:
	var state: int = DEFAULT_NONZERO_SEED

	func _init(seed_val: int = DEFAULT_NONZERO_SEED) -> void:
		set_seed(seed_val)

	func set_seed(seed_val: int) -> void:
		var masked: int = seed_val & U32_MASK
		state = masked if masked != 0 else DEFAULT_NONZERO_SEED

	## 生成下一个 32 位无符号伪随机整数 (Xorshift32)
	func next_u32() -> int:
		var x: int = state & U32_MASK
		if x == 0:
			x = DEFAULT_NONZERO_SEED
		x ^= (x << 13) & U32_MASK
		x ^= (x >> 17) & U32_MASK
		x ^= (x << 5) & U32_MASK
		state = x
		return x

	## 生成 [0.0, 1.0) 浮点数
	func randf_val() -> float:
		return float(next_u32()) / U32_DIVISOR

	## 生成 [min_v, max_v] 闭区间整数
	func randi_range_val(min_v: int, max_v: int) -> int:
		if min_v >= max_v:
			return min_v
		var span: int = max_v - min_v + 1
		return min_v + (next_u32() % span)

	## 生成 [min_v, max_v) 半开区间浮点数
	func randf_range_val(min_v: float, max_v: float) -> float:
		return min_v + (max_v - min_v) * randf_val()

	## 按概率 p ∈ [0, 1] 进行伯努利判定
	func roll_chance(p: float) -> bool:
		if p <= 0.0:
			return false
		if p >= 1.0:
			return true
		return randf_val() < p

	## 确定性二项分布采样 Binomial(n, p) (用于 Q6 混合粒度超额攻击暴击聚合)
	func sample_binomial(n: int, p: float) -> int:
		if n <= 0 or p <= 0.0:
			return 0
		if p >= 1.0:
			return n
		if n <= BINOMIAL_EXACT_LIMIT:
			var hits: int = 0
			for _i in range(n):
				if randf_val() < p:
					hits += 1
			return hits
		# 大样本采用确定性 Box-Muller 正态近似并截断到 [0, n]
		var u1: float = maxf(1e-12, randf_val())
		var u2: float = randf_val()
		var z: float = sqrt(-2.0 * log(u1)) * cos(TWO_PI * u2)
		var mean: float = float(n) * p
		var std_dev: float = sqrt(float(n) * p * (1.0 - p))
		var sampled: int = int(round(mean + std_dev * z))
		return clampi(sampled, 0, n)

	func clone() -> RngStream:
		var copy: RngStream = RngStream.new(DEFAULT_NONZERO_SEED)
		copy.state = state
		return copy

var master_seed: int = DEFAULT_NONZERO_SEED
var combat: RngStream
var loot: RngStream
var collection: RngStream

## 兼容属性：读取/设置主战斗流状态
var state: int:
	get:
		return combat.state
	set(value):
		combat.set_seed(value)

func _init(seed_val: int = DEFAULT_NONZERO_SEED) -> void:
	set_seed(seed_val)

## 使用 Murmur3 32 位雪崩混合派生三条互不干扰的种子流
static func _mix_seed(base_seed: int, salt: int) -> int:
	var h: int = (base_seed ^ salt) & U32_MASK
	h ^= (h >> 16) & U32_MASK
	h = (h * 0x7FEB352D) & U32_MASK
	h ^= (h >> 15) & U32_MASK
	h = (h * 0x846CA68B) & U32_MASK
	h ^= (h >> 16) & U32_MASK
	return h if h != 0 else DEFAULT_NONZERO_SEED

func set_seed(seed_val: int) -> void:
	master_seed = seed_val
	combat = RngStream.new(_mix_seed(seed_val, SALT_COMBAT))
	loot = RngStream.new(_mix_seed(seed_val, SALT_LOOT))
	collection = RngStream.new(_mix_seed(seed_val, SALT_COLLECTION))

## 兼容转发至 combat 流（推荐显式访问 rng.combat / rng.loot / rng.collection）
func next_u32() -> int:
	return combat.next_u32()

func randf_val() -> float:
	return combat.randf_val()

func randi_range_val(min_v: int, max_v: int) -> int:
	return combat.randi_range_val(min_v, max_v)

func randf_range_val(min_v: float, max_v: float) -> float:
	return combat.randf_range_val(min_v, max_v)

func roll_chance(p: float) -> bool:
	return combat.roll_chance(p)

func sample_binomial(n: int, p: float) -> int:
	return combat.sample_binomial(n, p)

func get_state_tuple() -> Array[int]:
	return [combat.state, loot.state, collection.state]

func clone() -> RefCounted:
	var script: GDScript = get_script() as GDScript
	var copy: RefCounted = script.new(master_seed)
	copy.combat.state = combat.state
	copy.loot.state = loot.state
	copy.collection.state = collection.state
	return copy
