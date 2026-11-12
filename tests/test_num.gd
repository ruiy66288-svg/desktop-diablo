class_name TestNum extends RefCounted

const Num = preload("res://core/num/Num.gd")

static func run() -> bool:
	print("[TestNum] 开始测试 WP-01 Log10 对数大数库...")

	# 1. 基础转换与乘除幂
	var a: float = Num.from_float(100.0)   # log10(100) = 2.0
	var b: float = Num.from_float(1000.0)  # log10(1000) = 3.0

	var mult: float = Num.mul(a, b)
	if absf(mult - 5.0) > 1e-9:
		printerr("[TestNum] 乘法错误: 预期 5.0, 实际 ", mult)
		return false

	var division: float = Num.div(b, a)
	if absf(division - 1.0) > 1e-9:
		printerr("[TestNum] 除法错误: 预期 1.0, 实际 ", division)
		return false

	var powered: float = Num.pow_num(b, 2.5)
	if absf(powered - 7.5) > 1e-9:
		printerr("[TestNum] 乘幂错误: 预期 7.5, 实际 ", powered)
		return false

	# 2. 对数加减法: 100 + 1000 = 1100; 1100 - 100 = 1000
	var sum_ab: float = Num.add(a, b)
	var expected_sum: float = log(1100.0) / Num.LN10
	if absf(sum_ab - expected_sum) > 1e-9:
		printerr("[TestNum] 加法错误: 预期 ", expected_sum, ", 实际 ", sum_ab)
		return false

	var diff_ba: float = Num.sub(sum_ab, a)
	if absf(diff_ba - b) > 1e-9:
		printerr("[TestNum] 减法逆运算错误: 预期 ", b, ", 实际 ", diff_ba)
		return false

	# 3. 相差超过 17 个数量级时直接返回 max (WP-01 验收红线)
	var hi: float = 100.0
	var lo_over_17: float = 82.9  # 差值 17.1 > 17
	var lo_under_17: float = 90.0 # 差值 10.0 < 17
	if Num.add(hi, lo_over_17) != hi or Num.add(lo_over_17, hi) != hi:
		printerr("[TestNum] 相差超过 17 个数量级时未返回 max!")
		return false
	if Num.sub(hi, lo_over_17) != hi:
		printerr("[TestNum] 减法相差超过 17 个数量级时未返回被减数!")
		return false
	if Num.add(hi, lo_under_17) <= hi:
		printerr("[TestNum] 相差小于 17 个数量级时精度丢失!")
		return false

	# 4. -INF (Num.ZERO) 全算子边界条件 (WP-01 验收红线)
	if not Num.is_zero(Num.ZERO) or not Num.is_zero(Num.from_float(0.0)) or not Num.is_zero(Num.from_float(-5.0)):
		printerr("[TestNum] ZERO 构造与判定失败!")
		return false
	if Num.add(a, Num.ZERO) != a or Num.add(Num.ZERO, a) != a or Num.add(Num.ZERO, Num.ZERO) != Num.ZERO:
		printerr("[TestNum] ZERO 加法边界错误!")
		return false
	if Num.sub(a, Num.ZERO) != a or Num.sub(Num.ZERO, a) != Num.ZERO or Num.sub(a, b) != Num.ZERO:
		printerr("[TestNum] ZERO 减法边界错误!")
		return false
	if Num.mul(a, Num.ZERO) != Num.ZERO or Num.mul(Num.ZERO, b) != Num.ZERO:
		printerr("[TestNum] ZERO 乘法边界错误!")
		return false
	if Num.div(Num.ZERO, a) != Num.ZERO or Num.div(a, Num.ZERO) != INF:
		printerr("[TestNum] ZERO 除法边界错误!")
		return false
	if Num.pow_num(Num.ZERO, 3.0) != Num.ZERO or Num.pow_num(a, 0.0) != 0.0:
		printerr("[TestNum] ZERO 乘幂边界错误!")
		return false

	# 5. 10^1e6 (val_log = 1,000,000) 量级精度测试 (02 §1.1 相对误差约 5e-10，WP-01 验收红线)
	var mega_a: float = 1000000.0
	var mega_b: float = 1000000.0
	var mega_sum: float = Num.add(mega_a, mega_b)
	var log10_two: float = log(2.0) / Num.LN10
	var log_err: float = absf((mega_sum - mega_a) - log10_two)
	var linear_rel_err: float = log_err * Num.LN10
	if linear_rel_err > 1e-9:
		printerr("[TestNum] 10^1e6 加法相对误差超标: ", linear_rel_err)
		return false

	var mega_back: float = Num.sub(mega_sum, mega_a)
	var sub_rel_err: float = absf(mega_back - mega_a) * Num.LN10
	if sub_rel_err > 1e-9:
		printerr("[TestNum] 10^1e6 减法相对误差超标: ", sub_rel_err)
		return false

	# 6. 比较函数测试
	if Num.cmp(a, b) != -1 or Num.cmp(b, a) != 1 or not Num.eq(a, 2.0):
		printerr("[TestNum] cmp/eq 比较函数错误!")
		return false
	if not Num.gt(b, a) or not Num.lt(Num.ZERO, a) or Num.max_num(Num.ZERO, a) != a or Num.min_num(a, b) != a:
		printerr("[TestNum] 大小关系与极值函数错误!")
		return false

	# 7. 全区间格式化测试 (<1e6 千分位 / K / M / B / T / aa..zz / 科学计数 / ee)
	if Num.format_num(Num.ZERO) != "0":
		printerr("[TestNum] 零值格式化错误: ", Num.format_num(Num.ZERO))
		return false
	if Num.format_num(Num.from_float(5.2)) != "5.20":
		printerr("[TestNum] 小数格式化错误: ", Num.format_num(Num.from_float(5.2)))
		return false
	if Num.format_num(Num.from_float(50000.0)) != "50,000":
		printerr("[TestNum] 千分位格式化错误: ", Num.format_num(Num.from_float(50000.0)))
		return false
	if Num.format_num(Num.from_float(50000.0), true) != "50.00K":
		printerr("[TestNum] K 单位格式化错误: ", Num.format_num(Num.from_float(50000.0), true))
		return false
	if Num.format_num(Num.from_float(1.5e6)) != "1.50M":
		printerr("[TestNum] M 格式化错误: ", Num.format_num(Num.from_float(1.5e6)))
		return false
	if Num.format_num(Num.from_float(2.34e9)) != "2.34B":
		printerr("[TestNum] B 格式化错误: ", Num.format_num(Num.from_float(2.34e9)))
		return false
	if Num.format_num(Num.from_float(4.56e12)) != "4.56T":
		printerr("[TestNum] T 格式化错误: ", Num.format_num(Num.from_float(4.56e12)))
		return false
	if Num.format_num(15.0 + Num.from_float(1.23)) != "1.23aa":
		printerr("[TestNum] aa 格式化错误: ", Num.format_num(15.0 + Num.from_float(1.23)))
		return false
	if Num.format_num(2040.0 + Num.from_float(1.23)) != "1.23zz":
		printerr("[TestNum] zz 格式化错误: ", Num.format_num(2040.0 + Num.from_float(1.23)))
		return false
	if Num.format_num(4567.0 + Num.from_float(1.23)) != "1.23e4567":
		printerr("[TestNum] 科学计数格式化错误: ", Num.format_num(4567.0 + Num.from_float(1.23)))
		return false
	if Num.format_num(1000000.0) != "ee6.00":
		printerr("[TestNum] ee 超大数格式化错误: ", Num.format_num(1000000.0))
		return false

	print("[TestNum] WP-01 所有用例测试通过!")
	return true
