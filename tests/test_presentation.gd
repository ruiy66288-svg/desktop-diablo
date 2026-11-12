class_name TestPresentation extends RefCounted

## WP-08 爆装表现层、双段对象池 (100+20)、单节点飘字、VfxBudget 合并降级与最小化 10 分钟恢复测试
## 100% 显式静态类型，零 := 隐式推导

const ObjectPoolScript = preload("res://core/pool/ObjectPool.gd")
const PresentationBusScript = preload("res://presentation/PresentationBus.gd")
const VfxBudgetScript = preload("res://presentation/VfxBudget.gd")
const SfxMixerScript = preload("res://presentation/audio/SfxMixer.gd")
const LootFountainScript = preload("res://presentation/loot/LootFountain.gd")
const FloatingTextLayerScript = preload("res://presentation/battle/FloatingTextLayer.gd")
const VfxManagerScript = preload("res://presentation/vfx/VfxManager.gd")
const GameScript = preload("res://autoload/Game.gd")
const MainWindowScript = preload("res://ui/MainWindow.gd")
const SimEventScript = preload("res://simulation/events/SimEvent.gd")

static func run() -> bool:
	print("[TestPresentation] 开始测试 WP-08 爆装表现层、对象池、预算降级与最小化 10 分钟恢复...")

	if not _test_object_pool():
		return false
	if not _test_loot_fountain_120_and_20_reserved():
		return false
	if not _test_floating_text_single_node_and_merge():
		return false
	if not _test_vfx_budget_and_sfx_mixer():
		return false
	if not _test_minimized_10min_restore_no_burst():
		return false

	print("[TestPresentation] WP-08 全部表现层与对象池测试 100% 通过!")
	return true

static func _test_object_pool() -> bool:
	var pool: ObjectPoolScript = ObjectPoolScript.new(func() -> Dictionary: return {"id": 1}, Callable(), 120)
	pool.prewarm(50)
	if pool.get_available_count() != 50:
		printerr("[TestPresentation] 对象池预热数量错误: ", pool.get_available_count())
		return false

	var o1: Variant = pool.acquire()
	if pool.get_available_count() != 49 or pool.get_active_count() != 1:
		printerr("[TestPresentation] 对象池获取状态异常!")
		return false
	pool.release(o1)
	if pool.get_available_count() != 50 or pool.get_active_count() != 0:
		printerr("[TestPresentation] 对象池归还状态异常!")
		return false
	return true

static func _test_loot_fountain_120_and_20_reserved() -> bool:
	var fountain: LootFountainScript = LootFountainScript.new()
	fountain._ready()

	# 1. 连续喷出 120 件白/蓝普通掉落 -> 普通池上限 100，最老白/蓝被回收，绝不侵占 20 个暗金专属位
	for i: int in range(120):
		fountain.spawn_drop(Vector2(112.0, 194.0), i % 2, 1.0, 1)

	if fountain.get_active_normal_count() != 100:
		printerr("[TestPresentation] 普通掉落池未封顶在 100: ", fountain.get_active_normal_count())
		fountain.free()
		return false

	# 2. 在普通池已满 100 时，继续喷出 20 件暗金/太古 -> 20 个专属位必须全部成功生成，总活跃 = 120
	for j: int in range(20):
		var rarity_val: int = 3 if j < 15 else 4
		var ok: bool = fountain.spawn_drop(Vector2(112.0, 194.0), rarity_val, 1.2, 50)
		if not ok:
			printerr("[TestPresentation] 暗金/太古专属 20 槽位分配失败于 index=", j)
			fountain.free()
			return false

	if fountain.get_active_rare_count() != 20 or fountain.get_active_total_count() != 120:
		printerr("[TestPresentation] 100+20 双池容量校验失败: rare=%d total=%d" % [
			fountain.get_active_rare_count(),
			fountain.get_active_total_count()
		])
		fountain.free()
		return false

	# 3. 步进物理弹道并验证鼠标靠近 48px 触发手动拾取信号
	var pickup_hits: Array[int] = [0]
	fountain.manual_pickup_triggered.connect(func(_ilvl: int, _rarity: int) -> void:
		pickup_hits[0] += 1
	)
	fountain.step_simulation(0.033, Vector2(112.0, 190.0))
	if pickup_hits[0] <= 0:
		printerr("[TestPresentation] 鼠标靠近 48px 未触发磁吸拾取信号!")
		fountain.free()
		return false

	fountain.clear_all()
	fountain.free()
	return true

static func _test_floating_text_single_node_and_merge() -> bool:
	var layer: FloatingTextLayerScript = FloatingTextLayerScript.new()
	for i: int in range(100):
		layer.add_floating_text("1.23K", Vector2(180.0, 300.0), Color.TRANSPARENT, i % 5 == 0, true)

	if layer.get_child_count() != 0:
		printerr("[TestPresentation] FloatingTextLayer 严禁创建 Label 子节点! child_count=", layer.get_child_count())
		layer.free()
		return false
	if layer.get_active_count() != FloatingTextLayerScript.MAX_TEXTS:
		printerr("[TestPresentation] 飘字上限应为 60, 实际=", layer.get_active_count())
		layer.free()
		return false
	if layer.get_merged_overflow_total() != 40:
		printerr("[TestPresentation] 超额 40 条飘字未正确合并为 ×N! merged=", layer.get_merged_overflow_total())
		layer.free()
		return false

	layer.free()
	return true

static func _test_vfx_budget_and_sfx_mixer() -> bool:
	var budget: VfxBudgetScript = VfxBudgetScript.new()
	budget.begin_frame(16.6)

	var passed: int = 0
	for _i: int in range(30):
		if budget.request_vfx("explosion", 0):
			passed += 1
	# 单类每帧合并阈值 4，普通预算上限 24；使用不同类型测试 24 总上限
	var budget2: VfxBudgetScript = VfxBudgetScript.new()
	budget2.begin_frame(16.6)
	var total_passed: int = 0
	for j: int in range(30):
		if budget2.request_vfx("type_%d" % (j / 3), 0):
			total_passed += 1
	if total_passed != 24:
		printerr("[TestPresentation] 普通特效未在 24 个时触发全局限额: ", total_passed)
		return false

	# 验证同帧 >= 4 同类合并与高优先级放行
	if passed != VfxBudgetScript.MERGE_THRESHOLD:
		printerr("[TestPresentation] 同类特效未在 4 个时触发合并: ", passed)
		return false
	if int(budget.get_compacted_overflows().get("explosion", 0)) != 26:
		printerr("[TestPresentation] 超额同类合并计数错误!")
		return false
	if not budget2.request_vfx("unique_beam", 3):
		printerr("[TestPresentation] 高优先级暗金特效被错误拦截!")
		return false

	# 验证 > 30ms 自动降级
	budget2.begin_frame(35.0)
	if not budget2.is_trails_disabled() or not budget2.is_shake_disabled() or budget2.get_particle_density_scale() >= 1.0:
		printerr("[TestPresentation] 帧时间 > 30ms 未触发 VfxBudget 降级!")
		return false

	# 验证 SfxMixer 同类并发 4 上限 + 全局 6 上限 + ±5% 音高
	var sfx_budget: VfxBudgetScript = VfxBudgetScript.new()
	sfx_budget.begin_frame(16.6)
	var mixer: SfxMixerScript = SfxMixerScript.new()
	mixer.begin_frame()
	var sfx_played: int = 0
	for _k: int in range(10):
		var req: Dictionary = mixer.request_play_sound("hit_sfx", sfx_budget)
		if bool(req["play"]):
			sfx_played += 1
			var pitch: float = float(req["pitch_scale"])
			if pitch < 0.949 or pitch > 1.051:
				printerr("[TestPresentation] 音高微抖动超出 ±5% 范围: ", pitch)
				return false
	if sfx_played != 4:
		printerr("[TestPresentation] 音效同类并发上限不为 4: ", sfx_played)
		return false

	var vfx_mgr: VfxManagerScript = VfxManagerScript.new()
	vfx_mgr.spawn_crit_ring(Vector2(112.0, 194.0))
	vfx_mgr.spawn_edge_alert(3)
	vfx_mgr.free()
	return true

static func _test_minimized_10min_restore_no_burst() -> bool:
	var game: GameScript = GameScript.new()
	game.initialize_session(20261112)
	game.set_auto_tick_enabled(false)

	var win: MainWindowScript = MainWindowScript.new()
	win.bind_game(game)
	win._ready()
	win.bind_game(game)

	# 模拟窗口最小化持续 10 分钟（600 秒 = 6,000 个 10Hz Sim tick）
	game.set_simulated_minimized(true)
	for _step_i: int in range(6000):
		game.advance_frame(0.1)

	if game.get_presentation_bus().get_pending_count() != 0:
		printerr("[TestPresentation] 最小化 10 分钟期间 PresentationBus 存在未排空积压!")
		win.free()
		game.free()
		return false

	# 恢复窗口：只应播一次受控回归汇总喷泉（<= 10 个实例），严禁一次性涌出数千掉落
	game.set_simulated_minimized(false)
	game.advance_frame(0.1)

	var summary: Dictionary = game.get_last_minimized_summary()
	if int(summary.get("drops_count", 0)) < 50:
		printerr("[TestPresentation] 10 分钟最小化期间掉落汇总统计异常偏低: ", summary.get("drops_count", 0))
		win.free()
		game.free()
		return false

	var spawned_after_restore: int = win.loot_fountain.get_active_total_count()
	if spawned_after_restore <= 0 or spawned_after_restore > 10:
		printerr("[TestPresentation] 最小化 10 分钟恢复后喷泉实例失控暴冲或未播汇总: ", spawned_after_restore)
		win.free()
		game.free()
		return false

	win.free()
	game.free()
	return true
