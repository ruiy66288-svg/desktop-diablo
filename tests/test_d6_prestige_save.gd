class_name TestD6PrestigeSave extends RefCounted

## D6 验收：WP-16 最简灵魂转生（宿债按时长扣款、保留 6 件装备）+ WP-17 存档读档与离线结算最小版本
## 依据《02_系统架构与数值_v6.md》§1.4、§3.4 第 7 条、Q19、Q35 与《00_开发执行总纲.md》§4.7、WP-16、WP-17

const SimStateScript = preload("res://simulation/SimState.gd")
const SimRunnerScript = preload("res://simulation/SimRunner.gd")
const CommandScript = preload("res://simulation/commands/Command.gd")
const BalanceScript = preload("res://simulation/Balance.gd")
const ItemInstanceScript = preload("res://simulation/loot/ItemInstance.gd")
const SignatureAffixesScript = preload("res://simulation/affix/SignatureAffixes.gd")
const SaveServiceScript = preload("res://persistence/SaveService.gd")
const OfflineCalcScript = preload("res://offline/OfflineCalc.gd")
const NumScript = preload("res://core/num/Num.gd")

const T0: int = 1_800_000_000
const SAVE_TEST_PATH: String = "user://__test_save_d6.json"

static func run() -> bool:
	print("[TestD6] 开始测试 WP-16 灵魂转生与 WP-17 存档/离线...")
	if not _test_soul_prestige_with_debt_and_tech():
		return false
	if not _test_save_roundtrip_and_continuation():
		return false
	if not _test_save_file_atomic_and_validation():
		return false
	if not _test_offline_settle():
		return false
	print("[TestD6] WP-16 / WP-17 全部验收项 100% 通过!")
	return true

static func _equip_full_set(state: SimStateScript, bal: BalanceScript, with_affix: bool) -> void:
	var slots: Array = [
		ItemInstanceScript.Slot.WEAPON, ItemInstanceScript.Slot.HELM, ItemInstanceScript.Slot.CHEST,
		ItemInstanceScript.Slot.GLOVES, ItemInstanceScript.Slot.BOOTS, ItemInstanceScript.Slot.TRINKET
	]
	for i: int in range(slots.size()):
		var it: ItemInstanceScript = ItemInstanceScript.new(
			900 + i, "套装件_" + str(i), slots[i] as ItemInstanceScript.Slot, ItemInstanceScript.Rarity.UNIQUE,
			30 + i, bal.get_equip_flat_atk_log(30 + i, 0.9), 0.4, 1.8, bal
		)
		if with_affix and i == 5:
			it.affixes.push_back(SignatureAffixesScript.create_killing_frenzy())
		state.equip_item(it)

## WP-16：转生前借满额度并买科技 → 转生后保留 6 件装备/科技/信用，宿债按时长在新周目逐笔收入 40% 扣款
static func _test_soul_prestige_with_debt_and_tech() -> bool:
	var bal: BalanceScript = BalanceScript.load_default() as BalanceScript
	var state: SimStateScript = SimStateScript.new(1616, bal)
	state.tech.debug_seconds_mode = true
	_equip_full_set(state, bal, false)
	state.current_stage = 80
	state.farm_stage = 80
	state.run_best = 80
	state.all_time_best = 80
	state.stats.atk_interval = 100.0

	# 借满额度 → 买科技（花光借来的钱）
	var limit_log: float = state.credit.get_credit_limit_log(80, bal)
	if not state.borrow_credit(limit_log):
		printerr("[TestD6] 借满失败")
		return false
	if not state.start_research("eco_scavenger", T0):
		printerr("[TestD6] 买科技失败")
		return false
	state.settle_research(T0 + 1000)
	state.spend_gold(state.gold)

	var preview: Dictionary = state.get_soul_prestige_preview()
	if not bool(preview["can_prestige"]) or int(preview["kept_equipped_count"]) != 6:
		printerr("[TestD6] 转生预览异常: ", preview)
		return false
	# 借满 10 分钟额度 × 1.6 溢价 = 16 分钟宿债
	if absf(float(preview["legacy_debt_added_minutes"]) - 16.0) > 1e-2:
		printerr("[TestD6] 预览宿债时长应为 16.0 分钟, 实际: ", preview["legacy_debt_added_minutes"])
		return false

	var souls_before: float = state.souls
	var runner: SimRunnerScript = SimRunnerScript.new(state)
	runner.enqueue_command(CommandScript.make_soul_prestige())
	runner.step()

	if state.prestige_count != 1 or state.run_best != 1 or state.current_stage != 1 or state.farm_stage != 1:
		printerr("[TestD6] 转生后层数未重置")
		return false
	if state.all_time_best != 80:
		printerr("[TestD6] all_time_best 不应下降")
		return false
	if state.souls <= souls_before or absf(state.souls - float(preview["souls_after_log"])) > 1e-9:
		printerr("[TestD6] 灵魂结算不符预览")
		return false
	for slot_key: String in SimStateScript.EQUIP_SLOTS:
		if state.equipped.get(slot_key, null) == null:
			printerr("[TestD6] 转生后装备槽被清空: ", slot_key)
			return false
	if not state.tech.has_researched("eco_scavenger") or state.credit.credit_tier != 0:
		printerr("[TestD6] 科技应保留、未还清借款不升阶")
		return false
	if state.debt_total != NumScript.ZERO or state.credit.active_loan:
		printerr("[TestD6] 转生后活跃债务应清零")
		return false
	if absf(state.legacy_debt_minutes - 16.0) > 1e-2:
		printerr("[TestD6] 宿债时长应为 16.0 分钟, 实际: ", state.legacy_debt_minutes)
		return false

	# 新周目：第 1 层赚 10 分钟期望收入(含科技+30%) → 抵扣 40% = 4 分钟，剩 12 分钟；其余 60% 入账金币
	var base_income_log: float = NumScript.mul(bal.get_expected_income_per_min_log(1), NumScript.from_float(10.0))
	state.stats.atk_interval = 100.0
	state.gold = NumScript.ZERO
	state.add_income(base_income_log)
	var boosted: float = base_income_log + NumScript.from_float(1.3)
	var paid_minutes: float = pow(10.0, boosted + NumScript.from_float(0.4) - bal.get_expected_income_per_min_log(1))
	var expected_left: float = maxf(0.0, 16.0 - paid_minutes)
	if absf(state.legacy_debt_minutes - expected_left) > 1e-2:
		printerr("[TestD6] 宿债按时长 40% 扣款不符: ", state.legacy_debt_minutes, " vs ", expected_left)
		return false
	if state.gold == NumScript.ZERO:
		printerr("[TestD6] 扣款后剩余 60% 收入应入账")
		return false

	# 无灵魂可得时拒绝转生（防止白白清空）
	var fresh: SimStateScript = SimStateScript.new(1617, bal)
	var r2: SimRunnerScript = SimRunnerScript.new(fresh)
	r2.enqueue_command(CommandScript.make_soul_prestige())
	r2.step()
	if fresh.prestige_count != 0:
		printerr("[TestD6] 记录层不足时不应允许转生")
		return false

	print("[TestD6] 灵魂转生: 保留 6 装备/科技, 宿债 16.0 分钟按 40% 扣款验证通过")
	return true

static func _build_rich_state(seed_val: int) -> SimStateScript:
	var bal: BalanceScript = BalanceScript.load_default() as BalanceScript
	var state: SimStateScript = SimStateScript.new(seed_val, bal)
	state.tech.debug_seconds_mode = true
	state.stats.base_gold_atk_log = 5.0
	_equip_full_set(state, bal, true)
	state.filter.set_threshold(ItemInstanceScript.Rarity.PURPLE)
	for i: int in range(4):
		state.inventory.add_item(ItemInstanceScript.new(
			700 + i, "背包件_" + str(i), ItemInstanceScript.Slot.HELM, ItemInstanceScript.Rarity.PURPLE,
			20 + i, bal.get_equip_flat_atk_log(20 + i, 0.5), 0.2, 1.0, bal
		), state)
	var runner: SimRunnerScript = SimRunnerScript.new(state)
	runner.enqueue_command(CommandScript.make_buy_atk(2))
	state.gold = 12.0
	state.borrow_credit(state.credit.get_credit_limit_log(state.get_active_stage(), bal) - 0.1)
	state.start_research("combat_edge", T0)
	state.start_research("credit_line", T0)
	for _t: int in range(300):
		runner.step()
		runner.queue.clear()
	return state

## WP-17：存档往返后状态哈希完全一致；读档后继续推演与原状态逐 tick 同步（含 RNG/保底/怪物/装备词条）
static func _test_save_roundtrip_and_continuation() -> bool:
	var original: SimStateScript = _build_rich_state(20261113)
	var data: Dictionary = SaveServiceScript.serialize(original)
	if int(data["version"]) != SaveServiceScript.SAVE_VERSION:
		printerr("[TestD6] 存档缺少 version 字段")
		return false

	# JSON 文本往返（含 -INF 与双精度精度）
	var text: String = SaveServiceScript.to_json_text(original)
	var loaded: SimStateScript = SaveServiceScript.from_json_text(text)
	if loaded == null:
		printerr("[TestD6] 存档 JSON 反序列化失败")
		return false
	if loaded.compute_state_hash() != original.compute_state_hash():
		printerr("[TestD6] 存档往返后状态哈希不一致")
		return false

	var ra: SimRunnerScript = SimRunnerScript.new(original)
	var rb: SimRunnerScript = SimRunnerScript.new(loaded)
	for t: int in range(500):
		ra.step()
		rb.step()
		ra.queue.clear()
		rb.queue.clear()
		if t % 100 == 99 and original.compute_state_hash() != loaded.compute_state_hash():
			printerr("[TestD6] 读档后第 ", t + 1, " tick 与原状态发生分叉")
			return false
	if original.compute_state_hash() != loaded.compute_state_hash():
		printerr("[TestD6] 读档后继续推演哈希不一致")
		return false

	# 装备词条经存档恢复后，监听器与杀戮狂热仍可生效
	if not loaded.resolver.has_listeners():
		printerr("[TestD6] 读档后装备词条监听器未重建")
		return false
	print("[TestD6] 存档 JSON 往返 + 继续推演 500 tick 哈希一致: ", loaded.compute_state_hash().substr(0, 12))
	return true

static func _test_save_file_atomic_and_validation() -> bool:
	var state: SimStateScript = _build_rich_state(77)
	var err1: Error = SaveServiceScript.save_to_file(state, SAVE_TEST_PATH)
	var err2: Error = SaveServiceScript.save_to_file(state, SAVE_TEST_PATH)   # 覆盖保存（Windows rename 不能直接覆盖）
	if err1 != OK or err2 != OK:
		printerr("[TestD6] 保存失败: ", err1, " / ", err2)
		return false
	if FileAccess.file_exists(SAVE_TEST_PATH + SaveServiceScript.TMP_SUFFIX):
		printerr("[TestD6] 保存后 .tmp 文件应已被 rename 掉")
		return false
	var back: SimStateScript = SaveServiceScript.load_from_file(SAVE_TEST_PATH)
	if back == null or back.compute_state_hash() != state.compute_state_hash():
		printerr("[TestD6] 文件存读哈希不一致")
		return false

	# 主档损坏 → 回退 .bak
	var bak_f: FileAccess = FileAccess.open(SAVE_TEST_PATH + SaveServiceScript.BAK_SUFFIX, FileAccess.WRITE)
	bak_f.store_string(SaveServiceScript.to_json_text(state))
	bak_f.close()
	var corrupt_f: FileAccess = FileAccess.open(SAVE_TEST_PATH, FileAccess.WRITE)
	corrupt_f.store_string("{ not json")
	corrupt_f.close()
	var recovered: SimStateScript = SaveServiceScript.load_from_file(SAVE_TEST_PATH)
	if recovered == null or recovered.compute_state_hash() != state.compute_state_hash():
		printerr("[TestD6] 主档损坏时未回退到 .bak")
		return false

	# 版本与核心字段校验
	var data: Dictionary = SaveServiceScript.serialize(state)
	var bad_version: Dictionary = data.duplicate(true)
	bad_version["version"] = SaveServiceScript.SAVE_VERSION + 99
	if SaveServiceScript.deserialize(bad_version) != null:
		printerr("[TestD6] 不支持的版本应被拒绝")
		return false
	var missing: Dictionary = data.duplicate(true)
	missing.erase("wallet")
	if SaveServiceScript.deserialize(missing) != null or SaveServiceScript.validate(missing).is_empty():
		printerr("[TestD6] 缺少核心字段应被拒绝")
		return false

	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_TEST_PATH))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_TEST_PATH + SaveServiceScript.BAK_SUFFIX))
	print("[TestD6] 原子保存(.tmp→rename)、.bak 回退、版本/字段校验验证通过")
	return true

static func _test_offline_settle() -> bool:
	var bal: BalanceScript = BalanceScript.load_default() as BalanceScript
	var base: SimStateScript = SimStateScript.new(3030, bal)
	base.tech.debug_seconds_mode = true
	base.upgrades.atk_level = 60   # 面板由升级等级重算（base_gold_atk_log 直接赋值会在 clone/重算时丢失）
	base.recalculate_stats()
	base.gold = 8.0
	base.start_research("combat_edge", T0)
	base.start_research("eco_scavenger", T0)
	base.current_stage = 12
	base.farm_stage = 12
	base.run_best = 12
	base.all_time_best = 15

	# 3 小时离线：研究按时间戳全部完成；金币增长；run_best / all_time_best 不倒退
	var s3: SimStateScript = base.clone()
	var gold_before: float = s3.gold
	var rep3: Dictionary = OfflineCalcScript.settle(s3, 3.0 * 3600.0, T0 + 3 * 3600)
	var done: Array = rep3["research_done"] as Array
	if done.size() != 2 or not s3.tech.has_researched("combat_edge") or not s3.tech.has_researched("eco_scavenger"):
		printerr("[TestD6] 离线研究未按时间戳完成: ", done)
		return false
	if s3.gold <= gold_before or float(rep3["gold_gain_log"]) == NumScript.ZERO:
		printerr("[TestD6] 离线金币未增长")
		return false
	if s3.run_best < 12 or s3.all_time_best < 15 or s3.current_stage < 12:
		printerr("[TestD6] 离线结算导致层数倒退!")
		return false
	if bool(rep3["capped"]):
		printerr("[TestD6] 3 小时不应触顶")
		return false

	# 超过上限（8h）：100 小时与 8 小时收益一致且标记 capped
	var s8: SimStateScript = base.clone()
	var s100: SimStateScript = base.clone()
	var rep8: Dictionary = OfflineCalcScript.settle(s8, bal.offline_cap_base_hours * 3600.0, T0)
	var rep100: Dictionary = OfflineCalcScript.settle(s100, 100.0 * 3600.0, T0)
	if not bool(rep100["capped"]) or absf(float(rep8["gold_gain_log"]) - float(rep100["gold_gain_log"])) > 1e-9:
		printerr("[TestD6] 离线上限封顶不正确")
		return false

	# 零离线：金币不变
	var s0: SimStateScript = base.clone()
	var g0: float = s0.gold
	OfflineCalcScript.settle(s0, 0.0, T0)
	if s0.gold != g0:
		printerr("[TestD6] 零离线不应获得金币")
		return false

	# 带活跃债务：离线收入经 40% 抵扣（债务减少，而非全额入账）
	var sd: SimStateScript = base.clone()
	sd.borrow_credit(sd.credit.get_credit_limit_log(12, bal))
	var debt_before: float = sd.debt_total
	OfflineCalcScript.settle(sd, 3600.0, T0)
	if sd.debt_total >= debt_before:
		printerr("[TestD6] 离线收入未抵扣债务")
		return false

	# 通过 SimRunner 长间隔回调（睡眠/卡顿超过追赶上限）
	var s_cb: SimStateScript = base.clone()
	var runner: SimRunnerScript = SimRunnerScript.new(s_cb, func(st: SimStateScript, elapsed: float) -> void:
		OfflineCalcScript.settle(st, elapsed, T0 + 4000))
	var gold_cb_before: float = s_cb.gold
	var ticks: int = runner.advance(3600.0)
	if ticks != 0 or s_cb.gold <= gold_cb_before:
		printerr("[TestD6] SimRunner 长间隔未触发离线结算")
		return false

	print("[TestD6] 离线结算: 研究按时间戳完成、金币外推、8h 封顶、不倒退验证通过")
	return true