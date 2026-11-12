class_name Num extends RefCounted

## 《桌面破坏神》对数大数静态运算库 (Log10 域)
## 依据《02_系统架构与数值_v6.md》§1.1 与《00_开发执行总纲.md》WP-01、§4.4
## 所有会无限膨胀的量统一存储为 log10 浮点数，仅通过本类静态函数运算

const ZERO: float = -INF
const LN10: float = 2.302585092994046
const DIFF_THRESHOLD: float = 17.0
const ZERO_DISPLAY_FLOOR_LOG: float = -300.0
const THOUSAND_LOG: float = 3.0
const MILLION_LOG: float = 6.0
const SCIENTIFIC_MAX_LOG: float = 100000.0
const AA_START_TIER: int = 5
const AA_TIER_COUNT: int = 676 # aa..zz = 26 * 26

const BASE_SUFFIXES: Array[String] = ["", "K", "M", "B", "T"]

## 判定是否为对数域零值 (-INF)
static func is_zero(a: float) -> bool:
	return a == ZERO

## 从普通非负浮点数构造 log10 值 (<= 0 映射为 ZERO = -INF)
static func from_float(val: float) -> float:
	if val <= 0.0:
		return ZERO
	return log(val) / LN10

## 将小范围 log10 值还原为普通浮点数 (超出 float64 范围时返回 INF / 0.0)
static func to_float(val_log: float) -> float:
	if val_log == ZERO or val_log < -308.0:
		return 0.0
	if val_log > 308.0:
		return INF
	return pow(10.0, val_log)

## 对数加法: log10(10^a + 10^b)；相差超过 17 个数量级时直接返回较大者
static func add(a: float, b: float) -> float:
	if a == ZERO:
		return b
	if b == ZERO:
		return a
	var hi: float = a if a >= b else b
	var lo: float = b if a >= b else a
	if hi == INF:
		return INF
	var diff: float = hi - lo
	if diff >= DIFF_THRESHOLD:
		return hi
	return hi + log(1.0 + pow(10.0, -diff)) / LN10

## 对数减法: log10(max(0, 10^a - 10^b))
static func sub(a: float, b: float) -> float:
	if b == ZERO:
		return a
	if a <= b:
		return ZERO
	if a == INF:
		return INF
	var diff: float = a - b
	if diff >= DIFF_THRESHOLD:
		return a
	return a + log(1.0 - pow(10.0, -diff)) / LN10

## 对数乘法: log10(10^a * 10^b) = a + b
static func mul(a: float, b: float) -> float:
	if a == ZERO or b == ZERO:
		return ZERO
	return a + b

## 对数除法: log10(10^a / 10^b) = a - b
static func div(a: float, b: float) -> float:
	if a == ZERO:
		return ZERO
	if b == ZERO:
		return INF
	return a - b

## 标量乘幂: log10((10^a)^k) = a * k
static func pow_num(a: float, k: float) -> float:
	if k == 0.0:
		return 0.0
	if a == ZERO:
		return ZERO if k > 0.0 else INF
	return a * k

## 对数域比较: a < b 返回 -1，|a - b| <= eps 返回 0，a > b 返回 1
static func cmp(a: float, b: float, eps: float = 1e-9) -> int:
	if a == b:
		return 0
	if a == ZERO:
		return -1
	if b == ZERO:
		return 1
	if absf(a - b) <= eps:
		return 0
	return 1 if a > b else -1

static func eq(a: float, b: float, eps: float = 1e-9) -> bool:
	return cmp(a, b, eps) == 0

static func gt(a: float, b: float) -> bool:
	return a > b

static func gte(a: float, b: float) -> bool:
	return a >= b

static func lt(a: float, b: float) -> bool:
	return a < b

static func lte(a: float, b: float) -> bool:
	return a <= b

static func max_num(a: float, b: float) -> float:
	return a if a >= b else b

static func min_num(a: float, b: float) -> float:
	return a if a <= b else b

## 根据千分阶次获取单位后缀: 1->K, 2->M, 3->B, 4->T, 5..680->aa..zz
static func get_tier_suffix(tier: int) -> String:
	if tier < 0:
		return ""
	if tier < BASE_SUFFIXES.size():
		return BASE_SUFFIXES[tier]
	var aa_idx: int = tier - AA_START_TIER
	if aa_idx >= 0 and aa_idx < AA_TIER_COUNT:
		var first_code: int = 97 + int(aa_idx / 26)
		var second_code: int = 97 + (aa_idx % 26)
		return String.chr(first_code) + String.chr(second_code)
	return ""

## 标准数值格式化 (§1.1: <1e6 千分位，之后 K/M/B/T/aa…，再大科学计数法，最后 ee)
static func format_num(val_log: float, use_k_below_million: bool = false) -> String:
	if is_nan(val_log):
		return "NaN"
	if val_log == INF:
		return "INF"
	if val_log == ZERO or val_log < ZERO_DISPLAY_FLOOR_LOG:
		return "0"

	# 1. 小于 1e3 (1000)
	if val_log < THOUSAND_LOG:
		var real_val: float = pow(10.0, val_log)
		if real_val < 10.0:
			return "%.2f" % real_val
		elif real_val < 100.0:
			return "%.1f" % real_val
		var rounded_small: int = int(round(real_val))
		if rounded_small < 1000:
			return "%d" % rounded_small
		val_log = THOUSAND_LOG

	# 2. 1e3 ~ <1e6: 默认千分位 (12,345)；若启用 K 缩写则输出 12.35K
	if val_log < MILLION_LOG and not use_k_below_million:
		var mid_val: int = int(round(pow(10.0, val_log)))
		if mid_val < 1000000:
			var s: String = str(mid_val)
			if s.length() > 3:
				return s.substr(0, s.length() - 3) + "," + s.substr(s.length() - 3)
			return s
		val_log = MILLION_LOG

	# 3. 字母缩写区间: K / M / B / T / aa .. zz (至 10^2043)
	var max_suffix_tier: int = AA_START_TIER + AA_TIER_COUNT - 1
	var tier: int = int(floor(val_log / 3.0))
	if tier <= max_suffix_tier:
		var mantissa: float = pow(10.0, val_log - float(tier * 3))
		if round(mantissa * 100.0) >= 100000.0:
			tier += 1
			mantissa = 1.0
		if tier <= max_suffix_tier:
			var suffix: String = get_tier_suffix(tier)
			return "%.2f%s" % [mantissa, suffix]

	# 4. 科学计数法区间 (例: 1.23e4567)
	if val_log < SCIENTIFIC_MAX_LOG:
		var exponent: int = int(floor(val_log))
		var sci_mantissa: float = pow(10.0, val_log - float(exponent))
		if round(sci_mantissa * 100.0) >= 1000.0:
			exponent += 1
			sci_mantissa = 1.0
		if float(exponent) < SCIENTIFIC_MAX_LOG:
			return "%.2fe%d" % [sci_mantissa, exponent]

	# 5. 超大指数区间: ee 记法 (例: 10^1e6 -> ee6.00)
	return "ee%.2f" % (log(val_log) / LN10)
