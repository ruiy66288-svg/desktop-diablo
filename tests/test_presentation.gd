class_name TestPresentation extends RefCounted

const ObjectPoolScript = preload("res://core/pool/ObjectPool.gd")
const PresentationBusScript = preload("res://presentation/PresentationBus.gd")
const VfxBudgetScript = preload("res://presentation/VfxBudget.gd")
const SfxMixerScript = preload("res://presentation/audio/SfxMixer.gd")
const SimEventScript = preload("res://simulation/events/SimEvent.gd")

static func run() -> bool:
	print("[TestPresentation] 开始测试 WP-08 渲染管线、对象池、总线与音效预算...")

	# 1. 对象池测试 (容量 120, 预热与释放)
	var pool = ObjectPoolScript.new(func(): return {"id": 1}, Callable(), 120)
	pool.prewarm(50)
	if pool.get_available_count() != 50:
		printerr("[TestPresentation] 对象池预热数量错误: ", pool.get_available_count())
		return false

	var o1 = pool.acquire()
	if pool.get_available_count() != 49 or pool.get_active_count() != 1:
		printerr("[TestPresentation] 对象池获取状态异常!")
		return false
	pool.release(o1)
	if pool.get_available_count() != 50 or pool.get_active_count() != 0:
		printerr("[TestPresentation] 对象池归还状态异常!")
		return false

	# 2. PresentationBus 离线/最小化防线测试 (Q10: 最小化排空不产生堆积)
	var bus = PresentationBusScript.new()
	# 压入 1000 个击杀和掉落事件
	for i in range(1000):
		var ev = SimEventScript.new(SimEventScript.T.DROP, 1.0)
		ev.payload = {"rarity": 1 if i % 10 != 0 else 3} # 90% 蓝装, 10% 暗金
		bus.push(ev)

	if bus.get_pending_count() != 1000:
		printerr("[TestPresentation] 总线压入事件数错误: ", bus.get_pending_count())
		return false

	# 模拟窗口最小化时排空
	bus.drain_for_minimized()
	if bus.get_pending_count() != 0:
		printerr("[TestPresentation] 最小化排空后总线未清空!")
		return false

	var summary: Dictionary = bus.fetch_and_reset_minimized_summary()
	if summary["drops_count"] != 1000:
		printerr("[TestPresentation] 最小化掉落统计汇总丢失: ", summary["drops_count"])
		return false
	if summary["rare_drops"].size() != 100: # 100 件暗金被正确捕获
		printerr("[TestPresentation] 最小化稀有掉落筛选异常: ", summary["rare_drops"].size())
		return false
	print("[TestPresentation] 窗口最小化事件汇聚与防暴冲机制验证通过!")

	# 3. VfxBudget 特效预算与并发限制测试 (每帧 24 个普通上限, Boss/暗金高优先级放行)
	var vfx = VfxBudgetScript.new()
	vfx.begin_frame()

	var passed := 0
	for i in range(30):
		if vfx.request_vfx("explosion", 0): # 普通优先级
			passed += 1

	if passed != 24:
		printerr("[TestPresentation] 普通特效未在 24 个时触发限额: ", passed)
		return false

	# 验证高优先级 (暗金) 必须放行
	var high_passed: bool = vfx.request_vfx("unique_beam", 3)
	if not high_passed:
		printerr("[TestPresentation] 高优先级暗金特效被错误拦截!")
		return false

	# 4. SfxMixer 同帧音效去重测试 (上限 4)
	var sfx = SfxMixerScript.new()
	sfx.begin_frame()
	var sfx_played := 0
	for i in range(10):
		var req = sfx.request_play_sound("hit_sfx")
		if req["play"]:
			sfx_played += 1
			if req["pitch_scale"] < 0.94 or req["pitch_scale"] > 1.06:
				printerr("[TestPresentation] 音高微抖动超出范围: ", req["pitch_scale"])
				return false

	if sfx_played != 4:
		printerr("[TestPresentation] 音效同帧并发上限不为 4: ", sfx_played)
		return false

	print("[TestPresentation] WP-08 渲染管线、对象池、事件总线与音效预算 100% 验证通过!")
	return true
