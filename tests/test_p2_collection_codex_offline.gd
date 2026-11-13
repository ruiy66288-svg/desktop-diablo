class_name TestP2CollectionCodexOffline extends RefCounted

## [WP-P2-SIM-2] 稀有收藏 + 永久图鉴 Codex + 隐藏套装 + 稀有 Boss 召唤房 + 完整经验校准离线结算验收套件
## 100% 显式静态类型，零 :=，纯 RefCounted，零 Node / SceneTree 依赖

const BalanceScript = preload("res://simulation/Balance.gd")
const SimStateScript = preload("res://simulation/SimState.gd")
const SimRunnerScript = preload("res://simulation/SimRunner.gd")
const CommandScript = preload("res://simulation/commands/Command.gd")
const CommandQueueScript = preload("res://simulation/commands/CommandQueue.gd")
const ItemInstanceScript = preload("res://simulation/loot/ItemInstance.gd")
const SignatureAffixesScript = preload("res://simulation/affix/SignatureAffixes.gd")
const AffixDefScript = preload("res://simulation/affix/AffixDef.gd")
const CodexScript = preload("res://persistence/Codex.gd")
const CollectionRollerScript = preload("res://simulation/collection/CollectionRoller.gd")
const SetDetectorScript = preload("res://simulation/collection/SetDetector.gd")
const SetDefScript = preload("res://simulation/collection/SetDef.gd")
const CosmeticDefScript = preload("res://simulation/collection/CosmeticDef.gd")
const DryRunScript = preload("res://simulation/commands/DryRun.gd")
const OfflineCalcScript = preload("res://offline/OfflineCalc.gd")
const NumScript = preload("res://core/num/Num.gd")
const SpawnerScript = preload("res://simulation/combat/Spawner.gd")

const TEST_CODEX_PATH: String = "user://test_codex_p2.json"
const T0: int = 1_800_000_000

static func run() -> bool:
	print("==================================================")
	print("[TestP2CollectionCodexOffline] 开始验收 [WP-P2-SIM-2]...")
	print("==================================================")

	if not _test_codex_system():
		return false
	if not _test_collection_roller():
		return false
	if not _test_hidden_sets():
		return false
	if not _test_transmog_system():
		return false
	if not _test_rare_boss_chamber():
		return false
	if not _test_offline_segmented_calibration():
		return false

	print("[TestP2CollectionCodexOffline] [WP-P2-SIM-2] 全部验收项 100% 通过!")
	print("==================================================")
	return true

# ---------------------------------------------------------------- 1. Codex 永久图鉴与原子落盘
static func _test_codex_system() -> bool:
	print("  [1/6] 验证 Codex 永久独立图鉴、页面集齐外观与原子读写...")
	var bal: BalanceScript = BalanceScript.load_default() as BalanceScript
	var codex: CodexScript = CodexScript.new(TEST_CODEX_PATH)
	# 清理旧残留
	if FileAccess.file_exists(TEST_CODEX_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_CODEX_PATH))

	# 1.1 初始状态
	if codex.get_unlocked_count() != 0 or codex.get_gold_bonus_pct(bal) != 0.0:
		printerr("  [!] Codex 初始状态非空")
		return false

	# 1.2 解锁怪物、暗金、神话、套装、符文
	if not codex.unlock_monster("mon_beast"):
		printerr("  [!] 无法解锁 mon_beast")
		return false
	if codex.unlock_monster("mon_beast"):
		printerr("  [!] 重复解锁 mon_beast 未去重")
		return false
	if not codex.unlock_unique("chain_lightning", false):
		printerr("  [!] 无法解锁 chain_lightning")
		return false
	if not codex.unlock_unique("chain_lightning", true):
		printerr("  [!] 无法解锁 mythic_chain_lightning")
		return false
	if not codex.unlock_set("set_thunder_debt"):
		printerr("  [!] 无法解锁 set_thunder_debt")
		return false

	codex.add_summon_runes(3)
	if codex.summon_runes != 3:
		printerr("  [!] 符文增加数量异常")
		return false
	if not codex.consume_summon_rune() or codex.summon_runes != 2:
		printerr("  [!] 符文消费异常")
		return false

	# 已点亮 4 项：mon_beast, chain_lightning, mythic_chain_lightning, set_thunder_debt
	# 金币加成 = 4 * 0.005 = 0.02 (2.0%)
	var expected_bonus: float = 4.0 * bal.codex_gold_bonus_per_entry
	if not is_equal_approx(codex.get_gold_bonus_pct(bal), expected_bonus):
		printerr("  [!] Codex 金币加成异常: ", codex.get_gold_bonus_pct(bal), " != ", expected_bonus)
		return false

	# 1.3 集齐一页解锁外观
	for m: String in CodexScript.FULL_MONSTERS:
		codex.unlock_monster(m)
	if not codex.is_page_complete("monsters"):
		printerr("  [!] 怪物页应已集齐")
		return false
	if not codex.cosmetics.has("theme_gilded_archon"):
		printerr("  [!] 集齐怪物页未自动解锁 theme_gilded_archon 外观")
		return false

	for u: String in CodexScript.FULL_UNIQUES:
		codex.unlock_unique(u)
	if not codex.is_page_complete("uniques"):
		printerr("  [!] 暗金页应已集齐")
		return false
	if not codex.cosmetics.has("beam_abyss_crimson"):
		printerr("  [!] 集齐暗金页未自动解锁 beam_abyss_crimson 外观")
		return false

	for s: String in CodexScript.FULL_SETS:
		codex.unlock_set(s)
	if not codex.is_page_complete("sets"):
		printerr("  [!] 套装页应已集齐")
		return false
	if not codex.cosmetics.has("skin_kill_starlight"):
		printerr("  [!] 集齐套装页未自动解锁 skin_kill_starlight 外观")
		return false

	# 1.4 原子写盘与读盘
	var save_err: Error = codex.save_to_file()
	if save_err != OK:
		printerr("  [!] Codex save_to_file 失败: ", save_err)
		return false

	var loaded_codex: CodexScript = CodexScript.new(TEST_CODEX_PATH)
	if not loaded_codex.load_from_file():
		printerr("  [!] Codex load_from_file 失败")
		return false
	if loaded_codex.summon_runes != 2 or loaded_codex.cosmetics.size() != 3:
		printerr("  [!] 读盘后数据与原数据不一致")
		return false

	# 清理测试存档
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_CODEX_PATH))
	var bak_p: String = TEST_CODEX_PATH + ".bak"
	if FileAccess.file_exists(bak_p):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(bak_p))

	print("  [✓] Codex 永久图鉴、加成、奖励外观与原子落盘全部通过")
	return true

# ---------------------------------------------------------------- 2. CollectionRoller 坏运气保护与判定
static func _test_collection_roller() -> bool:
	print("  [2/6] 验证 CollectionRoller 神话变体、太古外观、时间符文与坏运气保护...")
	var bal: BalanceScript = BalanceScript.load_default() as BalanceScript
	var roller: CollectionRollerScript = CollectionRollerScript.new()
	var codex: CodexScript = CodexScript.new()

	var state: SimStateScript = SimStateScript.new(54321, bal)
	state.codex = codex

	# 2.1 神话变体判定 (item.rarity >= UNIQUE)
	var item_rare: ItemInstanceScript = ItemInstanceScript.new(101, "稀有剑", ItemInstanceScript.Slot.WEAPON, ItemInstanceScript.Rarity.PURPLE, 10, 1.0)
	if roller.check_mythic_roll(item_rare, state.rng.loot, bal):
		printerr("  [!] 稀有装备不应触发神话判定")
		return false

	var item_uniq: ItemInstanceScript = ItemInstanceScript.new(102, "雷霆之刃", ItemInstanceScript.Slot.WEAPON, ItemInstanceScript.Rarity.UNIQUE, 100, 5.0, 2.0, 2.0, bal)
	var original_mult: float = item_uniq.unique_mult
	# 模拟连续失败，验证保底倍率乘算
	roller.mythic_pity_mult = 1.0
	var old_pity: float = roller.mythic_pity_mult
	# 人工将 pity 提高至保证命中
	roller.mythic_pity_mult = 10000.0
	var success: bool = roller.check_mythic_roll(item_uniq, state.rng.loot, bal)
	if not success or not item_uniq.is_mythic or not item_uniq.name.begins_with("神话·"):
		printerr("  [!] 神话变体变异失败")
		return false
	if item_uniq.unique_mult <= original_mult:
		printerr("  [!] 神话变体专属倍率未提升")
		return false
	if roller.mythic_pity_mult != 1.0:
		printerr("  [!] 神话保底命中后未重置为 1.0")
		return false

	# 2.2 太古独特外观判定
	var item_primal: ItemInstanceScript = ItemInstanceScript.new(103, "太古手套", ItemInstanceScript.Slot.GLOVES, ItemInstanceScript.Rarity.PRIMAL, 100, 5.0, 2.0, 2.0, bal)
	roller.primal_pity_mult = 1000.0
	var cos_id: String = roller.check_primal_transmog_roll(item_primal, state.rng.loot, bal, codex)
	if cos_id.is_empty() or not codex.cosmetics.has(cos_id):
		printerr("  [!] 太古幻化解锁失败: ", cos_id)
		return false
	if roller.primal_pity_mult != 1.0:
		printerr("  [!] 太古保底命中后未重置")
		return false

	# 2.3 召唤符文模拟时间判定 (必须 run_best >= 100 且满 60 秒)
	state.run_best = 50
	var got_low: bool = roller.check_summon_rune_tick(70.0, state.run_best, state.rng.loot, bal, codex)
	if got_low:
		printerr("  [!] run_best < 100 时绝不可判定召唤符文")
		return false

	state.run_best = 150
	roller.rune_pity_mult = 10000.0
	var got_high: bool = roller.check_summon_rune_tick(65.0, state.run_best, state.rng.loot, bal, codex)
	if not got_high or codex.summon_runes < 1:
		printerr("  [!] 满足 60s 与高保底时召唤符文判定失败")
		return false
	if roller.rune_pity_mult != 1.0:
		printerr("  [!] 符文保底命中后未重置")
		return false

	# 2.4 离线分钟数判定
	var runes_before: int = codex.summon_runes
	roller.rune_pity_mult = 10000.0
	var off_gained: int = roller.roll_offline_minutes(5, state.rng.loot, bal, codex)
	if off_gained <= 0 or codex.summon_runes != runes_before + off_gained:
		printerr("  [!] 离线分钟符文判定失败")
		return false

	# 2.5 克隆与序列化
	var cloned_roller: CollectionRollerScript = roller.clone()
	if cloned_roller.mythic_pity_mult != roller.mythic_pity_mult or cloned_roller.rune_sim_seconds_accumulator != roller.rune_sim_seconds_accumulator:
		printerr("  [!] CollectionRoller clone 失败")
		return false

	print("  [✓] CollectionRoller 神话变体、太古外观、时间符文与保底全部通过")
	return true

# ---------------------------------------------------------------- 3. SetDetector 隐藏套装检测
static func _test_hidden_sets() -> bool:
	print("  [3/6] 验证 SetDetector 隐藏套装扫描、词条激活与 Codex 解锁...")
	var bal: BalanceScript = BalanceScript.load_default() as BalanceScript
	var state: SimStateScript = SimStateScript.new(11111, bal)
	var codex: CodexScript = CodexScript.new()
	state.codex = codex

	# 穿戴雷霆断债套装所需词条：chain_lightning (WEAPON) + multi_strike (CHEST)
	var w: ItemInstanceScript = ItemInstanceScript.new(1, "雷霆之刃", ItemInstanceScript.Slot.WEAPON, ItemInstanceScript.Rarity.UNIQUE, 100, 3.0)
	var aff_w: AffixDefScript = SignatureAffixesScript.get_by_id("chain_lightning")
	w.affixes.push_back(aff_w)
	state.equip_slots.equip(w, state)

	var c: ItemInstanceScript = ItemInstanceScript.new(2, "连击护甲", ItemInstanceScript.Slot.CHEST, ItemInstanceScript.Rarity.UNIQUE, 100, 3.0)
	var aff_c: AffixDefScript = SignatureAffixesScript.get_by_id("multi_strike")
	c.affixes.push_back(aff_c)
	state.equip_slots.equip(c, state)

	# 此时应检测到套装 set_thunder_debt
	var active_sets: Array[SetDefScript] = SetDetectorScript.detect_active_sets(state, codex)
	if active_sets.size() != 1 or active_sets[0].id != "set_thunder_debt":
		printerr("  [!] 未正确检测到隐藏套装 set_thunder_debt: ", active_sets)
		return false

	if not codex.sets.has("set_thunder_debt"):
		printerr("  [!] 穿戴套装后未自动记录进 Codex")
		return false

	# 验证加成是否生效到 StatSheet (set_thunder_debt: bonus_additive_pct=0.5, crit_mult=1.0)
	state.equip_slots.recalculate_and_apply(state)
	if state.stats.crit_mult < bal.base_crit_mult + 1.0 or state.stats.additive_percent < 0.5:
		printerr("  [!] 隐藏套装词条加成未生效到 StatSheet: crit_mult=", state.stats.crit_mult, ", add_pct=", state.stats.additive_percent)
		return false

	# 卸下武器后套装应失效
	state.equip_slots.unequip(ItemInstanceScript.Slot.WEAPON, state)
	var active_after: Array[SetDefScript] = SetDetectorScript.detect_active_sets(state, codex)
	if not active_after.is_empty():
		printerr("  [!] 卸下散件后隐藏套装未正确注销")
		return false

	print("  [✓] SetDetector 隐藏套装检测、面板加成与 Codex 记录全部通过")
	return true

# ---------------------------------------------------------------- 4. 幻化系统
static func _test_transmog_system() -> bool:
	print("  [4/6] 验证装备幻化 (Transmog) 槽位绑定、未解锁拦截与数值零影响...")
	var bal: BalanceScript = BalanceScript.load_default() as BalanceScript
	var state: SimStateScript = SimStateScript.new(22222, bal)
	var codex: CodexScript = CodexScript.new()
	state.codex = codex

	var dps_before: float = state.stats.get_expected_dps_log(bal.min_atk_interval)

	# 未解锁该外观时应拒绝设置
	if state.set_transmog("weapon", "transmog_archon_blade"):
		printerr("  [!] 未解锁外观不应允许设置")
		return false

	# 解锁后设置成功
	codex.unlock_cosmetic("transmog_archon_blade")
	if not state.set_transmog("weapon", "transmog_archon_blade"):
		printerr("  [!] 解锁外观后设置失败")
		return false
	if state.get_transmog("weapon") != "transmog_archon_blade":
		printerr("  [!] get_transmog 返回异常")
		return false

	# 幻化必须零影响核心战斗数值
	var dps_after: float = state.stats.get_expected_dps_log(bal.min_atk_interval)
	if absf(dps_before - dps_after) > 1e-9:
		printerr("  [!] 幻化意外修改了战斗数值!")
		return false

	# 清除幻化
	if not state.set_transmog("weapon", ""):
		printerr("  [!] 清除幻化失败")
		return false
	if not state.get_transmog("weapon").is_empty():
		printerr("  [!] 清除幻化后外观非空")
		return false

	print("  [✓] Transmog 幻化设置、校验与数值零影响全部通过")
	return true

# ---------------------------------------------------------------- 5. 稀有 Boss 独立战斗房
static func _test_rare_boss_chamber() -> bool:
	print("  [5/6] 验证稀有 Boss 独立战斗房、召唤/超时零损失返还/击杀专属掉落/DryRun...")
	var bal: BalanceScript = BalanceScript.load_default() as BalanceScript
	var state: SimStateScript = SimStateScript.new(33333, bal)
	var codex: CodexScript = CodexScript.new()
	state.codex = codex
	var runner: SimRunnerScript = SimRunnerScript.new(state)

	state.current_stage = 150
	state.farm_stage = 150

	# 5.1 无符文无法召唤
	if state.summon_rare_boss():
		printerr("  [!] 无符文时不应允许召唤稀有 Boss")
		return false

	# 5.2 获得 1 枚符文后通过 Command 队列触发召唤
	codex.add_summon_runes(1)
	state.push_command(CommandScript.make_summon_rare_boss())
	runner.step() # 执行队列

	if not state.is_rare_boss_active or state.saved_regular_stage != 150 or codex.summon_runes != 0:
		printerr("  [!] 稀有 Boss 召唤状态异常: active=", state.is_rare_boss_active, ", runes=", codex.summon_runes)
		return false

	# 5.3 超时判定与零损失返还 (Q25)
	# 跑满 30 秒 (300 ticks)
	state.stats.base_gold_atk_log = -10.0 # 伤害极低无法击杀
	for _t: int in range(305):
		runner.step()

	if state.is_rare_boss_active:
		printerr("  [!] 稀有 Boss 超过 30s 未自动超时退出")
		return false
	if codex.summon_runes != 1:
		printerr("  [!] 稀有 Boss 超时后未零损失返还符文: ", codex.summon_runes)
		return false
	if state.current_stage != 150:
		printerr("  [!] 稀有 Boss 超时后未恢复原关卡: ", state.current_stage)
		return false

	# 5.4 主动撤退判定 (ABORT_RARE_BOSS)
	state.push_command(CommandScript.make_summon_rare_boss())
	runner.step()
	if not state.is_rare_boss_active or codex.summon_runes != 0:
		printerr("  [!] 重新召唤稀有 Boss 失败")
		return false

	state.push_command(CommandScript.make_abort_rare_boss())
	runner.step()
	if state.is_rare_boss_active or codex.summon_runes != 1:
		printerr("  [!] 主动撤退稀有 Boss 状态异常或未返还符文")
		return false

	# 5.5 成功击杀稀有 Boss：掉落专属暗金与外观，记录图鉴
	state.push_command(CommandScript.make_summon_rare_boss())
	runner.step()
	state.stats.base_gold_atk_log = 50.0 # 极高攻击力一击必杀
	state.stats.atk_interval = 0.01
	for _k: int in range(10):
		runner.step()
		if not state.is_rare_boss_active:
			break

	if state.is_rare_boss_active:
		printerr("  [!] 稀有 Boss 击杀后未退出战斗房")
		return false
	if not codex.monsters.has("boss_rare_archon"):
		printerr("  [!] 击杀后未点亮稀有 Boss 图鉴")
		return false
	if not codex.uniques.has("thunder_blade"):
		printerr("  [!] 击杀后未点亮 thunder_blade 图鉴")
		return false
	if not codex.cosmetics.has("transmog_archon_blade"):
		printerr("  [!] 击杀后未解锁 transmog_archon_blade 外观")
		return false

	# 5.6 DryRun 对稀有 Boss 评估
	var cand_weapon: ItemInstanceScript = ItemInstanceScript.new(999, "强力测试武器", ItemInstanceScript.Slot.WEAPON, ItemInstanceScript.Rarity.PRIMAL, 150, 10.0)
	var dry_res: Dictionary = DryRunScript.evaluate_candidate(state, cand_weapon, 42, true)
	if not dry_res.has("delta_pct") or float(dry_res["delta_pct"]) <= 0.0:
		printerr("  [!] DryRun against_rare_boss 评估异常: ", dry_res)
		return false

	print("  [✓] 稀有 Boss 召唤、超时返还、主动撤退、击杀掉落与 DryRun 全部通过")
	return true

# ---------------------------------------------------------------- 6. OfflineCalc 完整分段校准
static func _test_offline_segmented_calibration() -> bool:
	print("  [6/6] 验证 OfflineCalc 完整分段校准、自动攻击、门票拦截、离线符文与不倒退铁律...")
	var bal: BalanceScript = BalanceScript.load_default() as BalanceScript
	var state: SimStateScript = SimStateScript.new(44444, bal)
	var codex: CodexScript = CodexScript.new()
	state.codex = codex

	# 6.1 离线自动升级攻击力 (auto_upgrade 节点提供 auto_buy_atk 效果) 与推进层数
	state.tech.mark_researched("auto_upgrade")
	var w_offline: ItemInstanceScript = ItemInstanceScript.new(888, "斩魔利刃", ItemInstanceScript.Slot.WEAPON, ItemInstanceScript.Rarity.UNIQUE, 50, 10.0, 1.0, 1.0, bal)
	state.equip_slots.equip(w_offline, state)
	state.gold = 10.0 # 充裕金币
	state.current_stage = 10
	state.farm_stage = 10
	state.run_best = 10
	state.all_time_best = 10

	var report: Dictionary = OfflineCalcScript.settle(state, 600.0, T0 + 600)
	if not report.has("stages_advanced") or int(report["stages_advanced"]) <= 0:
		printerr("  [!] 离线具备充裕战力时未推进层数: ", report)
		return false
	if state.upgrades.atk_level <= 0:
		printerr("  [!] 拥有 auto_buy_atk 时离线未自动购买攻击力")
		return false
	if state.run_best <= 10:
		printerr("  [!] run_best 未同步推进")
		return false

	# 6.2 百层门票拦截：未达到门票所需净资产时绝不可推进下一区间 (Q32)
	state.current_stage = 100
	state.farm_stage = 100
	state.run_best = 100
	state.paid_gate_tier = 0
	state.enforce_toll_gates = true
	state.gold = NumScript.ZERO
	state.toll_escrow = NumScript.ZERO
	state.debt_total = 20.0 # 净负债巨额，无法支付门票
	state.stats.base_gold_atk_log = 30.0 # 即使秒杀也无法通过门票

	var report_gate: Dictionary = OfflineCalcScript.settle(state, 120.0, T0 + 1200)
	if state.current_stage > 100 or state.paid_gate_tier > 0:
		printerr("  [!] 违反 Q32 铁律: 无法支付门票时离线错误穿越了门票层: stage=", state.current_stage)
		return false

	# 6.3 离线召唤符文判定 (run_best >= 100 阶段)
	state.run_best = 150
	state.collection_roller.rune_pity_mult = 10000.0 # 确保触发
	var report_rune: Dictionary = OfflineCalcScript.settle(state, 300.0, T0 + 1500)
	if int(report_rune.get("new_summon_runes", 0)) <= 0 or codex.summon_runes <= 0:
		printerr("  [!] run_best >= 100 离线结算未判定召唤符文: ", report_rune)
		return false

	# 6.4 离线不倒退铁律校验
	var stage_before: int = state.current_stage
	var run_best_before: int = state.run_best
	var all_time_before: int = state.all_time_best
	var net_wealth_before: float = float(state.get_net_wealth_info().get("net_log", NumScript.ZERO))

	# 模拟离线极短时间（无金币增加或低收益）
	state.gold = NumScript.ZERO
	var report_def: Dictionary = OfflineCalcScript.settle(state, 10.0, T0 + 2000)
	if state.current_stage < stage_before or state.run_best < run_best_before or state.all_time_best < all_time_before:
		printerr("  [!] 违反离线不倒退铁律: 层数倒退")
		return false

	print("  [✓] OfflineCalc 分段校准、自动升级、门票守卫与符文产出全部通过")
	return true
