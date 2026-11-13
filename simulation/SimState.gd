class_name SimState extends RefCounted

## 《桌面破坏神》核心确定性模拟状态快照 (纯 RefCounted, 零 Node 依赖, 可克隆可哈希)
## 依据《02_系统架构与数值_v6.md》§1.2–§1.7、§2.1、§5、§7、§9.1 与《00_开发执行总纲.md》WP-03/05/06、§2 E1/E3/E4/E9/E10

const NumScript = preload("res://core/num/Num.gd")
const SimRngScript = preload("res://core/rng/SimRng.gd")
const StatSheetScript = preload("res://simulation/StatSheet.gd")
const BalanceScript = preload("res://simulation/Balance.gd")
const InventoryScript = preload("res://simulation/loot/Inventory.gd")
const FilterScript = preload("res://simulation/loot/Filter.gd")
const LootRollerScript = preload("res://simulation/loot/LootRoller.gd")
const UpgradesScript = preload("res://simulation/progression/Upgrades.gd")
const CreditScript = preload("res://simulation/economy/Credit.gd")
const WalletScript = preload("res://simulation/economy/Wallet.gd")
const CommandScript = preload("res://simulation/commands/Command.gd")
const CommandQueueScript = preload("res://simulation/commands/CommandQueue.gd")
const ItemInstanceScript = preload("res://simulation/loot/ItemInstance.gd")
const SimEventScript = preload("res://simulation/events/SimEvent.gd")
const EventQueueScript = preload("res://simulation/events/EventQueue.gd")
const BuffsScript = preload("res://simulation/events/Buffs.gd")
const AffixResolverScript = preload("res://simulation/events/AffixResolver.gd")
const EquipSlotsScript = preload("res://simulation/progression/EquipSlots.gd")
const TechTreeScript = preload("res://simulation/tech/TechTree.gd")
const ResearchQueueScript = preload("res://simulation/tech/ResearchQueue.gd")
const TechNodeDefScript = preload("res://simulation/tech/TechNodeDef.gd")
const SmelterScript = preload("res://simulation/loot/Smelter.gd")
const SignalsScript = preload("res://simulation/attention/Signals.gd")
const SignatureAffixesScript = preload("res://simulation/affix/SignatureAffixes.gd")
const AffixDefScript = preload("res://simulation/affix/AffixDef.gd")
const BandRulesScript = preload("res://simulation/mechanics/BandRules.gd")
const MechanicDefScript = preload("res://simulation/mechanics/MechanicDef.gd")
const CodexScript = preload("res://persistence/Codex.gd")
const CollectionRollerScript = preload("res://simulation/collection/CollectionRoller.gd")
const SpawnerScript = preload("res://simulation/combat/Spawner.gd")

const EQUIP_SLOTS: Array[String] = [
	"weapon",
	"helm",
	"chest",
	"gloves",
	"boots",
	"trinket"
]
const RETRY_MARGIN_EPS: float = 1e-4
const VAULT_AVG_WEIGHT: float = 0.5

# 1. 四个层数变量 (§9.1 & 勘误 E3 铁律)
var all_time_best: int = 1       # 跨所有转生的历史最高层 (永不下降)
var run_best: int = 1            # 本周目最高层 (本周目永不下降，灵魂结算与离线不倒退基准)
var current_stage: int = 1       # 当前正在挑战层 (>= farm_stage，退回时绝不下降)
var farm_stage: int = 1          # 自动刷怪层 (<= run_best，Boss 超时退回只改此变量)

# 2. 统一钱包权威源与跨周目成长 (§5.1–§5.2、§9.1 & 勘误 E1/E4：严禁第二货币，唯一货币 gold)
var wallet: WalletScript = WalletScript.new()

var gold: float:
	get:
		return wallet.gold
	set(value):
		wallet.gold = value

var debt_total: float:
	get:
		return wallet.debt_total
	set(value):
		wallet.debt_total = value

var legacy_debt_minutes: float:
	get:
		return wallet.legacy_debt_minutes
	set(value):
		wallet.legacy_debt_minutes = value

var toll_escrow: float:
	get:
		return wallet.toll_escrow
	set(value):
		wallet.toll_escrow = value

var credit: CreditScript:
	get:
		return wallet.credit
	set(value):
		wallet.credit = value

var souls: float = NumScript.ZERO               # 灵魂储备 (log10)
var marks: int = 0                              # 累计深渊印记数
var vault_powers: Array[String] = []            # 已装配进永久威能槽的词条 ID 列表 (槽位数 = 1 + floor(marks/5), Q20)
var unlocked_vault_powers: Array[String] = []   # 已萃取解锁的永久威能池（永久保留）

# 3. 关卡门票、周目计数与时钟统计
var paid_gate_tier: int = 0                     # 本周目已缴纳门票的百层门阶次
var gate_boss_cleared: bool = false             # 当前百层分界 Boss 是否已击杀（等待门票缴清过门）
var enforce_toll_gates: bool = true             # 是否启用每 100 层关卡门票与托管规则 (§7.3)
var prestige_count: int = 0                     # 累计转生次数（用于首周目 140 击杀保底判定）
var tick_count: int = 0                         # 累计已执行模拟 tick 数
var elapsed_seconds: float = 0.0                # 本周目已运行模拟秒数
var peak_soul_rate_log: float = NumScript.ZERO  # 本周目历史最高灵魂获取速率 (§1.6)

# 4. 战场实时怪物与退回重试状态
var mob_max_hp_log: float = 0.0
var mob_current_hp_log: float = NumScript.ZERO
var is_boss: bool = false
var boss_timer: float = 0.0
var mobs_killed_in_stage: int = 0
var mobs_killed_total: int = 0
var boss_fail_streak: int = 0
var farm_kills_since_retreat: int = 0
var last_fail_margin_log: float = NumScript.ZERO
var atk_progress: float = 0.0
var mob_shield_max_log: float = NumScript.ZERO        # 当前怪物护盾上限 (§7.1，无护盾为 -INF)
var mob_shield_cur_log: float = NumScript.ZERO
var mob_shield_strip_cap_log: float = NumScript.ZERO
var backlash_stacks: float = 0.0                  # 200–299 反噬累积 (§7.1)
var stun_remaining_sec: float = 0.0              # 反噬眩晕剩余秒数
var boss_clone_triggered: bool = false          # 400–499 分身是否已触发
var boss_clones_remaining: int = 0
var recent_income_per_sec_log: float = NumScript.ZERO   # 近期每秒收入 (吞金上限基准)
var mech_absorbed_log: Array[float] = [NumScript.ZERO, NumScript.ZERO, NumScript.ZERO, NumScript.ZERO, NumScript.ZERO, NumScript.ZERO]   # 按机制 Kind 统计被吸收/削减伤害 (卡墙归因 §7.2)
var mech_dealt_log: float = NumScript.ZERO     # 同期实际打进怪物生命的伤害
var passive_totals: Dictionary = {}              # 被动词条汇总 {stat_key: value}
var signals: SignalsScript                       # 边缘光带信号 (§5.4)

# 5. 6 槽装备栏、外部指令队列与子系统实例
var equipped: Dictionary = {}
var stats: StatSheetScript
var rng: SimRngScript
var balance: BalanceScript
var inventory: InventoryScript
var filter: FilterScript
var loot_roller: LootRollerScript
var upgrades: UpgradesScript
var command_queue: CommandQueueScript
var buffs: BuffsScript
var resolver: AffixResolverScript
var equip_slots: EquipSlotsScript
var tech: TechTreeScript                 # 科技树（永不随转生重置, Q28）
var research_queue: ResearchQueueScript   # 研究队列（Unix 时间戳, Q27）

# 6. 图鉴、稀有收藏、幻化与稀有 Boss 状态 (§8.1–§8.3)
var codex: CodexScript = null
var collection_roller: CollectionRollerScript
var transmog_slots: Dictionary = {}
var is_rare_boss_active: bool = false
var saved_regular_stage: int = 1
var rare_boss_timer: float = 0.0

func _init(seed_val: int = 123456789, p_balance: BalanceScript = null) -> void:
	balance = p_balance if p_balance != null else (BalanceScript.load_default() as BalanceScript)
	wallet = WalletScript.new()
	command_queue = CommandQueueScript.new()
	rng = SimRngScript.new(seed_val)
	stats = StatSheetScript.new(balance)
	inventory = InventoryScript.new()
	filter = FilterScript.new()
	loot_roller = LootRollerScript.new()
	upgrades = UpgradesScript.new()
	buffs = BuffsScript.new()
	resolver = AffixResolverScript.new()
	equip_slots = EquipSlotsScript.new()
	tech = TechTreeScript.new()
	research_queue = ResearchQueueScript.new()
	signals = SignalsScript.new()
	collection_roller = CollectionRollerScript.new()
	_init_empty_equip_slots()
	recalculate_stats()

func ensure_codex() -> CodexScript:
	if codex == null:
		codex = CodexScript.new()
	return codex

## 消耗 1 枚符文开启稀有 Boss「契约大执政官」独立挑战房 (§8.2)
func summon_rare_boss() -> bool:
	if is_rare_boss_active:
		return false
	if codex == null or not codex.consume_summon_rune():
		return false
	is_rare_boss_active = true
	saved_regular_stage = current_stage
	rare_boss_timer = 0.0
	SpawnerScript.spawn_rare_boss(self)
	return true

## 主动撤退稀有 Boss 挑战（零损失返还符文） (Q25 & §8.2)
func abort_rare_boss() -> bool:
	if not is_rare_boss_active:
		return false
	if codex != null:
		codex.add_summon_runes(1)
	is_rare_boss_active = false
	rare_boss_timer = 0.0
	current_stage = saved_regular_stage
	farm_stage = saved_regular_stage
	mobs_killed_in_stage = 0
	SpawnerScript.spawn_next(self)
	return true

## 设置 6 槽装备幻化外观 (§8.3)
func set_transmog(slot_key: String, appearance_id: String) -> bool:
	if not EQUIP_SLOTS.has(slot_key):
		return false
	if appearance_id.is_empty():
		transmog_slots.erase(slot_key)
		return true
	if codex != null and not codex.cosmetics.has(appearance_id):
		return false
	transmog_slots[slot_key] = appearance_id
	return true

## 获取槽位当前幻化外观 id (无则返回空字符串)
func get_transmog(slot_key: String) -> String:
	return String(transmog_slots.get(slot_key, ""))

func _init_empty_equip_slots() -> void:
	equipped.clear()
	for slot_key: String in EQUIP_SLOTS:
		equipped[slot_key] = null
	equip_slots.equipped.clear()
	resolver.clear_listeners()

## 将外部只写指令压入权威队列，等待下一 tick 起始处确定性结算
func push_command(cmd: CommandScript) -> void:
	command_queue.push(cmd)

func enqueue_command(cmd: CommandScript) -> void:
	command_queue.push(cmd)

## 获取当前实际刷怪/战斗所在层（退回刷怪时为 farm_stage，正常推进时等于 current_stage）
func get_active_stage() -> int:
	return farm_stage if farm_stage < current_stage else current_stage

## 获取当前净财富 W = gold - debt_total 信息（勘误 E4：统一委托 Wallet，严格不含 toll_escrow）
func get_net_wealth_info(stage_override: int = -1) -> Dictionary:
	var target_stage: int = stage_override if stage_override > 0 else get_active_stage()
	return wallet.get_net_wealth_info(target_stage, balance)

## 计算指定层在当前净财富下的怪物血量压力修正 Δh_wealth (Log10 域)
func get_wealth_pressure_hp_delta(stage_override: int = -1) -> float:
	var target_stage: int = stage_override if stage_override > 0 else get_active_stage()
	return wallet.get_wealth_pressure_hp_delta(target_stage, balance)

## 获取指定层在当前净财富下的怪物血量倍率（普通 float，范围 [0.40, 3.00]，供 HUD 展示）
func get_wealth_hp_multiplier(stage_override: int = -1) -> float:
	var target_stage: int = stage_override if stage_override > 0 else get_active_stage()
	return wallet.get_wealth_hp_multiplier(target_stage, balance)

## 花费金币（勘误 E9：统一委托 Wallet.spend，仅扣减余额使压力回落，无额外消费 buff）
func spend_gold(cost_log: float) -> bool:
	return wallet.spend(cost_log)

## 主动使用金币余额提前偿还活跃债务
func repay_debt_with_gold(amount_log: float) -> float:
	return wallet.repay_with_gold(amount_log)

## 计算指定层含财富压力的 Boss 血量与当前期望 DPS 差值（用于变强后自动重试判定, Q3）
func get_boss_power_margin_log(stage_val: int) -> float:
	var boss_hp: float = balance.get_boss_hp_log(stage_val) + get_wealth_pressure_hp_delta(stage_val)
	var dps: float = stats.get_expected_dps_log(balance.min_atk_interval)
	return dps - boss_hp

## 判定退回刷怪期间是否满足自动重试当前挑战层条件 (Q3)
func should_retry_current_stage() -> bool:
	if farm_stage >= current_stage:
		return false
	if farm_kills_since_retreat >= balance.farm_retry_kills:
		return true
	var cur_margin: float = get_boss_power_margin_log(current_stage)
	return cur_margin > last_fail_margin_log + RETRY_MARGIN_EPS

## 判定当前是否处于门前储蓄托管模式 (§7.3 & Q36)
func is_saving_for_toll() -> bool:
	if not enforce_toll_gates:
		return false
	var upcoming_tier: int = balance.get_upcoming_gate_tier(current_stage, paid_gate_tier)
	if upcoming_tier <= 0:
		return false
	return not can_pay_toll_tier(upcoming_tier)

## 判定「托管余额 + 金币 - 应还总额 >= 门票」是否满足 (§7.3)
func can_pay_toll_tier(gate_tier: int) -> bool:
	var toll_log: float = balance.get_toll_cost_log(gate_tier)
	var liquid_plus_escrow: float = NumScript.add(gold, toll_escrow)
	if liquid_plus_escrow < debt_total:
		return false
	var payable_net: float = NumScript.sub(liquid_plus_escrow, debt_total)
	return payable_net != NumScript.ZERO and payable_net >= toll_log

## 自动尝试缴纳当前面临的下一道百层门票；成功返回 true (§7.3)
func try_pay_next_toll() -> bool:
	if not enforce_toll_gates:
		return false
	var upcoming_tier: int = balance.get_upcoming_gate_tier(current_stage, paid_gate_tier)
	if upcoming_tier <= 0:
		return false
	if not can_pay_toll_tier(upcoming_tier):
		return false

	var toll_log: float = balance.get_toll_cost_log(upcoming_tier)
	if toll_escrow >= toll_log:
		toll_escrow = NumScript.sub(toll_escrow, toll_log)
	else:
		var remain_toll: float = NumScript.sub(toll_log, toll_escrow)
		toll_escrow = NumScript.ZERO
		gold = NumScript.sub(gold, remain_toll)

	if toll_escrow != NumScript.ZERO:
		gold = NumScript.add(gold, toll_escrow)
		toll_escrow = NumScript.ZERO

	paid_gate_tier = upcoming_tier
	return true

## 推进至下一层（维护 §9.1 四个层数变量不变量）
func advance_to_next_stage(queue: EventQueueScript = null) -> void:
	gate_boss_cleared = false
	current_stage += 1
	farm_stage = current_stage
	run_best = maxi(run_best, current_stage)
	all_time_best = maxi(all_time_best, current_stage)
	mobs_killed_in_stage = 0
	farm_kills_since_retreat = 0
	_reset_mech_attempt_stats()
	if queue != null:
		queue.push_back(SimEventScript.new(SimEventScript.T.STAGE_UP, float(current_stage)))

## 获得金币收入：先扣 40% 偿还活跃债务/宿债，余下根据储蓄模式入账 toll_escrow 或 gold (§5.2 & §7.3)
func add_income(amount_log: float, queue: EventQueueScript = null) -> void:
	if amount_log == NumScript.ZERO:
		return

	var income_bonus_pct: float = tech.get_effect_total("income_mult_pct")
	if codex != null:
		income_bonus_pct += codex.get_gold_bonus_pct(balance)
	var boosted_log: float = amount_log + NumScript.from_float(1.0 + income_bonus_pct) if income_bonus_pct > 0.0 else amount_log
	var saving_mode: bool = is_saving_for_toll()
	var tier_before: int = wallet.credit.credit_tier
	wallet.add_income(boosted_log, balance, get_active_stage(), saving_mode)
	if wallet.credit.credit_tier > tier_before:
		raise_signal(SignalsScript.Kind.CREDIT_TIER_UP, {"tier": wallet.credit.credit_tier}, queue)

	if enforce_toll_gates and try_pay_next_toll() and gate_boss_cleared:
		advance_to_next_stage(queue)

## 申请信贷借款 (§5.2 & Q26)
func borrow_credit(borrow_amount_log: float) -> bool:
	return wallet.borrow(borrow_amount_log, get_active_stage(), balance)

## 判定某项科技效果是否已生效（如 auto_buy_atk）
func has_tech_effect(effect_key: String) -> bool:
	return tech.get_effect_total(effect_key) > 0.0

## 开始研究：校验前置/队列容量/金币，扣费后入队（时间戳由调用方传入，Sim 不读系统时钟，§4.6）
func start_research(node_id: String, now_unix: int) -> bool:
	var def: TechNodeDefScript = tech.get_def(node_id)
	if def == null or tech.has_researched(node_id) or research_queue.contains(node_id):
		return false
	if not def.prereq_id.is_empty() and not tech.has_researched(def.prereq_id) and not research_queue.contains(def.prereq_id):
		return false
	if marks < def.requires_marks:
		return false   # 深层节点需深渊印记解锁 (§5.3)
	if research_queue.is_full(balance.tech_queue_max_slots):
		return false
	if not spend_gold(def.cost_gold_log):
		return false
	return research_queue.push(node_id, now_unix, tech.get_research_duration_seconds(def, balance), balance.tech_queue_max_slots)

## 按时间戳结算到期研究（离线重开同样走此入口），完成后重算属性并发出 ATTENTION 事件，返回完成的节点 id
func settle_research(now_unix: int, queue: EventQueueScript = null) -> Array[String]:
	var done: Array[String] = research_queue.settle(now_unix)
	for node_id: String in done:
		tech.mark_researched(node_id)
		raise_signal(SignalsScript.Kind.RESEARCH_DONE, {"node_id": node_id}, queue)
	if not done.is_empty():
		recalculate_stats()
	return done

## 装备 6 槽穿戴，返回被替换下来的旧装备（无则为 null）并重算 StatSheet (E10)
func equip_item(item: ItemInstanceScript) -> ItemInstanceScript:
	var slot_key: String = ItemInstanceScript.get_slot_key(item.slot)
	var prev: ItemInstanceScript = equipped.get(slot_key, null) as ItemInstanceScript
	equipped[slot_key] = item
	equip_slots.equipped[int(item.slot)] = item
	if not item.affixes.is_empty() or (prev != null and not prev.affixes.is_empty()):
		# 含词条装备：重建反应型词条监听器并结算被动词条 (WP-10/12)
		equip_slots.recalculate_and_apply(self)
	recalculate_stats()
	return prev

## 卸下指定槽位装备并重算，返回被卸下的装备（无则 null）
func unequip_slot(slot_key: String) -> ItemInstanceScript:
	var prev: ItemInstanceScript = equipped.get(slot_key, null) as ItemInstanceScript
	if prev == null:
		return null
	equipped[slot_key] = null
	equip_slots.equipped.erase(int(prev.slot))
	equip_slots.recalculate_and_apply(self)
	recalculate_stats()
	return prev

## 根据升级等级、6 槽装备、灵魂与永久威能重算 StatSheet (§1.2)
func recalculate_stats() -> void:
	stats.base_gold_atk_log = balance.get_upgrade_gold_atk_log(upgrades.atk_level)

	var total_gear_flat_log: float = NumScript.ZERO
	var total_add_pct: float = 0.0
	var total_unique_log: float = 0.0

	for slot_key: String in EQUIP_SLOTS:
		var item: ItemInstanceScript = equipped.get(slot_key, null) as ItemInstanceScript
		if item != null:
			total_gear_flat_log = NumScript.add(total_gear_flat_log, item.flat_atk_log)
			total_add_pct += item.additive_pct
			if item.unique_mult > 1.0:
				total_unique_log += NumScript.from_float(item.unique_mult)

	var active_vault_count: int = mini(vault_powers.size(), balance.get_vault_slot_count(marks))
	if active_vault_count > 0:
		var avg_vault_mult: float = VAULT_AVG_WEIGHT * (balance.unique_mult_min + balance.unique_mult_max)
		total_unique_log += float(active_vault_count) * NumScript.from_float(avg_vault_mult)

	total_add_pct += tech.get_effect_total("additive_pct") + float(passive_totals.get("additive_percent", 0.0))
	stats.crit_rate_bonus = tech.get_effect_total("crit_rate") + float(passive_totals.get("crit_rate", 0.0))
	stats.crit_mult = balance.base_crit_mult + float(passive_totals.get("crit_mult", 0.0))
	stats.drop_qty_bonus = tech.get_effect_total("drop_qty_bonus")
	wallet.credit.tier_bonus = int(tech.get_effect_total("credit_tier_bonus"))
	wallet.credit.extra_loans = int(tech.get_effect_total("credit_extra_loans"))
	wallet.credit.repay_discount = tech.get_effect_total("credit_repay_discount")
	stats.gear_flat_atk_log = total_gear_flat_log
	stats.additive_percent = total_add_pct
	stats.unique_mults_sum_log = total_unique_log
	stats.soul_mult_log = balance.get_soul_mult_log(souls)

# ---------------------------------------------------------------- 阶段 2：机制统计、卡墙归因、信号、威能

func record_mech_absorbed(kind: int, dmg_log: float) -> void:
	if kind >= 0 and kind < mech_absorbed_log.size():
		mech_absorbed_log[kind] = NumScript.add(mech_absorbed_log[kind], dmg_log)

func record_mech_dealt(dmg_log: float) -> void:
	mech_dealt_log = NumScript.add(mech_dealt_log, dmg_log)

func _reset_mech_attempt_stats() -> void:
	for i: int in range(mech_absorbed_log.size()):
		mech_absorbed_log[i] = NumScript.ZERO
	mech_dealt_log = NumScript.ZERO

func is_in_net_debt() -> bool:
	return debt_total != NumScript.ZERO and debt_total > gold

## 债契护印：净负债时的额外伤害加成 (log10)，无则 0
func get_conditional_damage_bonus_log() -> float:
	var bonus: float = float(passive_totals.get("debt_damage_bonus", 0.0))
	if bonus > 0.0 and is_in_net_debt():
		return NumScript.from_float(1.0 + bonus)
	return 0.0

## 债契护印：净负债时吞金吞噬量系数 (1.0 = 无减免)
func get_gold_eat_factor() -> float:
	var cut: float = float(passive_totals.get("eat_reduction", 0.0))
	if cut > 0.0 and is_in_net_debt():
		return maxf(0.0, 1.0 - cut)
	return 1.0

## 机制 kind 本次 Boss 尝试期间吸收/削减伤害占比 = absorbed / (absorbed + dealt)
func get_mech_absorbed_ratio(kind: int) -> float:
	if kind < 0 or kind >= mech_absorbed_log.size():
		return 0.0
	var absorbed: float = mech_absorbed_log[kind]
	if absorbed == NumScript.ZERO:
		return 0.0
	var total: float = NumScript.add(absorbed, mech_dealt_log)
	return clampf(pow(10.0, absorbed - total), 0.0, 1.0)

## 卡墙归因 (§7.2)：连续 N 次 Boss 失败后，归因到吸收伤害占比最高的机制并给出克制提示
func get_wall_hint() -> Dictionary:
	if boss_fail_streak < balance.wall_signal_fail_streak:
		var no_hint: Array[String] = []
		return {"active": false, "mechanic_id": "", "absorbed_ratio": 0.0, "hint_zh": "", "counter_tags": no_hint}
	var strengths: Dictionary = BandRulesScript.get_strengths(current_stage, balance)
	var best_kind: int = 0
	var best_ratio: float = -1.0
	var best_strength: float = 0.0
	for kind_var: Variant in strengths.keys():
		var kind: int = int(kind_var)
		var ratio: float = get_mech_absorbed_ratio(kind)
		var strength: float = float(strengths[kind_var])
		if ratio > best_ratio or (is_equal_approx(ratio, best_ratio) and strength > best_strength):
			best_kind = kind
			best_ratio = ratio
			best_strength = strength
	if best_kind == 0:
		var power_tags: Array[String] = ["power"]
		return {"active": true, "mechanic_id": "power", "absorbed_ratio": 0.0, "hint_zh": "数值墙 → 换 Build 或借钱", "counter_tags": power_tags}
	var def: MechanicDefScript = BandRulesScript.get_mechanic_def(best_kind)
	var hint: String = def.wall_hint
	if best_ratio > 0.0:
		hint += "（吸收 %d%%）" % int(round(best_ratio * 100.0))
	return {
		"active": true,
		"mechanic_id": def.id,
		"absorbed_ratio": maxf(0.0, best_ratio),
		"hint_zh": hint,
		"counter_tags": def.counter_tags.duplicate()
	}

## 触发边缘光带信号：首次触发时发出 ATTENTION 事件（同类去重，§5.4）
func raise_signal(kind: int, payload: Dictionary = {}, queue: EventQueueScript = null) -> void:
	var is_new: bool = signals.raise_signal(kind, payload)
	if is_new and queue != null:
		var ev: SimEventScript = SimEventScript.new(SimEventScript.T.ATTENTION, float(kind))
		var pl: Dictionary = payload.duplicate()
		pl["signal"] = SignalsScript.get_name_of(kind)
		ev.payload = pl
		queue.push_back(ev)

func ack_signal(kind: int) -> void:
	signals.clear_signal(kind)

## §1.6 最优停止判据：灵魂获取速率越过峰值后回落到 drop_ratio 以下即可转生
func is_prestige_ready() -> bool:
	if elapsed_seconds < balance.auto_prestige_min_run_seconds:
		return false
	var pending: float = balance.get_pending_souls_log(run_best, marks)
	if pending == NumScript.ZERO or peak_soul_rate_log == NumScript.ZERO:
		return false
	var rate_log: float = pending - NumScript.from_float(elapsed_seconds)
	return rate_log < peak_soul_rate_log + NumScript.from_float(balance.auto_prestige_rate_drop_ratio)

## 每 tick 刷新由状态推导的信号（卡墙 / 可转生）
func update_attention_signals(queue: EventQueueScript = null) -> void:
	var wall: Dictionary = get_wall_hint()
	if bool(wall["active"]):
		raise_signal(SignalsScript.Kind.WALL_HINT, {"mechanic_id": wall["mechanic_id"], "hint_zh": wall["hint_zh"]}, queue)
	else:
		signals.clear_signal(SignalsScript.Kind.WALL_HINT)
	if is_prestige_ready():
		raise_signal(SignalsScript.Kind.PRESTIGE_READY, {}, queue)
	else:
		signals.clear_signal(SignalsScript.Kind.PRESTIGE_READY)

## 估算穿戴候选装备后期望 DPS 的 log10 增量（通过纯净克隆 StatSheet 计算，绝不修改当前真实状态与面板）
func estimate_equip_delta_log(item: ItemInstanceScript) -> float:
	var slot_key: String = ItemInstanceScript.get_slot_key(item.slot)
	var prev: ItemInstanceScript = equipped.get(slot_key, null) as ItemInstanceScript
	var prev_flat: float = prev.flat_atk_log if prev != null else NumScript.ZERO
	var prev_add: float = prev.additive_pct if prev != null else 0.0
	var prev_uniq: float = (NumScript.from_float(prev.unique_mult) if prev.unique_mult > 1.0 else 0.0) if prev != null else 0.0

	var item_flat: float = item.flat_atk_log
	var item_add: float = item.additive_pct
	var item_uniq: float = NumScript.from_float(item.unique_mult) if item.unique_mult > 1.0 else 0.0

	var test_stats: StatSheetScript = stats.clone()
	var base_dps: float = test_stats.get_expected_dps_log(balance.min_atk_interval)

	if prev_flat != NumScript.ZERO:
		test_stats.gear_flat_atk_log = NumScript.sub(test_stats.gear_flat_atk_log, prev_flat)
	test_stats.gear_flat_atk_log = NumScript.add(test_stats.gear_flat_atk_log, item_flat)
	test_stats.additive_percent = maxf(0.0, test_stats.additive_percent - prev_add + item_add)
	test_stats.unique_mults_sum_log = maxf(0.0, test_stats.unique_mults_sum_log - prev_uniq + item_uniq)

	var cand_dps: float = test_stats.get_expected_dps_log(balance.min_atk_interval)
	return cand_dps - base_dps

## 新暗金/太古装备入包且估算 DPS 增量 > 0 时触发「强力新装备」信号 (§5.4 & §8.1 & §8.3)
func note_item_kept(item: ItemInstanceScript, queue: EventQueueScript = null) -> void:
	if int(item.rarity) < int(ItemInstanceScript.Rarity.UNIQUE):
		return
	if run_best >= balance.abyss_min_stage and collection_roller != null:
		collection_roller.check_mythic_roll(item, rng.loot, balance)
		collection_roller.check_primal_transmog_roll(item, rng.loot, balance, codex)
	if codex != null:
		for a: Variant in item.affixes:
			if a is AffixDefScript:
				codex.unlock_unique((a as AffixDefScript).id, item.is_mythic)
	if estimate_equip_delta_log(item) > 0.0:
		raise_signal(SignalsScript.Kind.BETTER_UNIQUE, {
			"uid": item.uid, "rarity": int(item.rarity), "slot": ItemInstanceScript.get_slot_key(item.slot)
		}, queue)

## 额外整套掉落判定（终焉喷泉）：走过滤/背包/熔炼，返回对应 DROP 事件供词条链继续触发
func grant_bonus_drops(rolls: int, is_boss: bool) -> Array:
	var events: Array = []
	for _r: int in range(maxi(0, rolls)):
		var items: Array[ItemInstanceScript] = loot_roller.roll_loot_for_kill(get_active_stage(), is_boss, self, null)
		for item: ItemInstanceScript in items:
			if filter.should_keep(item):
				inventory.add_item(item, self, null)
				note_item_kept(item, null)
			else:
				SmelterScript.smelt_item(item, self, null)
			var ev: SimEventScript = SimEventScript.new(SimEventScript.T.DROP, item.flat_atk_log)
			ev.payload = {"item_uid": item.uid, "rarity": int(item.rarity), "slot": ItemInstanceScript.get_slot_key(item.slot)}
			events.push_back(ev)
	return events

# ---------------------------------------------------------------- 深渊转生与永久威能 (Q20)

func get_max_vault_slots() -> int:
	return balance.get_vault_slot_count(marks)

## 当前持有的暗金/太古装备（6 槽 + 背包）上可萃取的词条 id（去重）
func collect_extractable_affix_ids() -> Array[String]:
	var ids: Array[String] = []
	var pool: Array[ItemInstanceScript] = []
	for slot_key: String in EQUIP_SLOTS:
		var eq: ItemInstanceScript = equipped.get(slot_key, null) as ItemInstanceScript
		if eq != null:
			pool.push_back(eq)
	for i: int in range(inventory.get_count()):
		pool.push_back(inventory.get_item_at(i))
	for it: ItemInstanceScript in pool:
		if int(it.rarity) < int(ItemInstanceScript.Rarity.UNIQUE):
			continue
		for a: Variant in it.affixes:
			if a is AffixDefScript and not ids.has((a as AffixDefScript).id):
				ids.push_back((a as AffixDefScript).id)
	return ids

func equip_vault_power(affix_id: String) -> bool:
	if not unlocked_vault_powers.has(affix_id) or vault_powers.has(affix_id):
		return false
	if vault_powers.size() >= get_max_vault_slots():
		return false
	vault_powers.push_back(affix_id)
	equip_slots.recalculate_and_apply(self)
	return true

func unequip_vault_power(affix_id: String) -> bool:
	if not vault_powers.has(affix_id):
		return false
	vault_powers.erase(affix_id)
	equip_slots.recalculate_and_apply(self)
	return true

## 深渊转生预览（只读）：run_best >= abyss_min_stage 才可触发 (§1.5)
func get_abyss_prestige_preview() -> Dictionary:
	var pending: int = balance.get_pending_marks(all_time_best)
	return {
		"can_prestige": run_best >= balance.abyss_min_stage and pending > 0,
		"run_best": run_best,
		"pending_marks": pending,
		"marks_after": marks + pending,
		"max_vault_slots_after": balance.get_vault_slot_count(marks + pending),
		"extractable_affix_ids": collect_extractable_affix_ids(),
		"legacy_debt_added_minutes": wallet.get_prestige_legacy_minutes(maxi(1, current_stage), balance)
	}
## 灵魂转生预览（只读）：可获灵魂、转生后灵魂储备、未还债务将折算的宿债时长、保留装备数 (§1.4、Q19、Q35)
func get_soul_prestige_preview() -> Dictionary:
	var gain_log: float = balance.get_pending_souls_log(run_best, marks)
	var added_minutes: float = wallet.get_prestige_legacy_minutes(maxi(1, current_stage), balance)
	var kept: int = 0
	for slot_key: String in EQUIP_SLOTS:
		if equipped.get(slot_key, null) != null:
			kept += 1
	return {
		"can_prestige": gain_log != NumScript.ZERO,
		"run_best": run_best,
		"pending_souls_log": gain_log,
		"souls_after_log": NumScript.add(souls, gain_log) if gain_log != NumScript.ZERO else souls,
		"legacy_debt_added_minutes": added_minutes,
		"legacy_debt_total_minutes": legacy_debt_minutes + added_minutes,
		"kept_equipped_count": kept
	}

## 执行第一层灵魂转生：结算宿债时长、累加灵魂、保留身上 6 件装备、重置层数与金币 (§1.4 & Q19 & Q35)
func perform_soul_prestige() -> float:
	var earned_souls_log: float = balance.get_pending_souls_log(run_best, marks)
	_settle_unpaid_debt_to_legacy()

	if earned_souls_log != NumScript.ZERO:
		souls = NumScript.add(souls, earned_souls_log)

	prestige_count += 1
	_reset_run_progress(true)
	recalculate_stats()
	return earned_souls_log

## 执行第二层深渊印记转生：结算宿债、累加印记、萃取威能、清空装备/灵魂/金币 (§1.5 & Q20 & Q35)
func perform_abyss_prestige(extract_power_id: String = "") -> int:
	var earned_marks: int = balance.get_pending_marks(all_time_best)
	var extractable: Array[String] = collect_extractable_affix_ids()   # 必须在清空装备前收集
	_settle_unpaid_debt_to_legacy()

	marks += earned_marks
	# 卡奈式萃取：只能萃取当前持有的暗金/太古装备上的专属词条，永久进入解锁池并自动装配到空闲威能槽
	if not extract_power_id.is_empty() and extractable.has(extract_power_id) and not unlocked_vault_powers.has(extract_power_id):
		unlocked_vault_powers.push_back(extract_power_id)
		if not vault_powers.has(extract_power_id) and vault_powers.size() < get_max_vault_slots():
			vault_powers.push_back(extract_power_id)

	souls = NumScript.ZERO
	_init_empty_equip_slots()
	inventory.clear()
	prestige_count += 1
	_reset_run_progress(false)
	equip_slots.recalculate_and_apply(self)   # 重建威能槽监听器并重算面板
	return earned_marks

func _settle_unpaid_debt_to_legacy() -> void:
	wallet.settle_prestige_debt_to_legacy(maxi(1, current_stage), balance)

func _reset_run_progress(_keep_equipped: bool) -> void:
	run_best = 1
	current_stage = 1
	farm_stage = 1
	gold = NumScript.ZERO
	toll_escrow = NumScript.ZERO
	paid_gate_tier = 0
	gate_boss_cleared = false
	elapsed_seconds = 0.0
	peak_soul_rate_log = NumScript.ZERO
	mob_max_hp_log = 0.0
	mob_current_hp_log = NumScript.ZERO
	is_boss = false
	boss_timer = 0.0
	mobs_killed_in_stage = 0
	boss_fail_streak = 0
	farm_kills_since_retreat = 0
	last_fail_margin_log = NumScript.ZERO
	atk_progress = 0.0
	mob_shield_max_log = NumScript.ZERO
	mob_shield_cur_log = NumScript.ZERO
	mob_shield_strip_cap_log = NumScript.ZERO
	backlash_stacks = 0.0
	stun_remaining_sec = 0.0
	boss_clone_triggered = false
	boss_clones_remaining = 0
	recent_income_per_sec_log = NumScript.ZERO
	_reset_mech_attempt_stats()
	signals.clear_signal(SignalsScript.Kind.WALL_HINT)
	signals.clear_signal(SignalsScript.Kind.PRESTIGE_READY)
	buffs.clear()
	upgrades.reset_levels()

## 派生事件超出最大深度时的溢出保底奖励 (§2.3)
func overflow_reward(_ev: Variant) -> void:
	var bonus_gold: float = NumScript.mul(balance.get_mob_gold_log(get_active_stage()), balance.overflow_reward_offset_log)
	add_income(bonus_gold)

## 生成包含全部核心字段与三条独立 RNG 种子流的确定性 SHA-256 状态哈希 (WP-03 验收基准)
func compute_state_hash() -> String:
	return "|".join(get_hash_parts()).sha256_text()

## 状态哈希的规范化分段（供测试定位分叉字段）
func get_hash_parts() -> PackedStringArray:
	var parts: PackedStringArray = PackedStringArray()
	parts.append("stages:%d,%d,%d,%d" % [all_time_best, run_best, current_stage, farm_stage])
	parts.append("econ:%.12f,%.12f,%.8f,%.12f,%.12f,%d" % [
		gold, debt_total, legacy_debt_minutes, toll_escrow, souls, marks
	])
	parts.append("vault:%s" % ",".join(vault_powers))
	if not unlocked_vault_powers.is_empty():
		parts.append("vault_pool:%s" % ",".join(unlocked_vault_powers))
	parts.append("gate:%d,%s,%s,%d,%d,%.6f" % [
		paid_gate_tier, str(gate_boss_cleared), str(enforce_toll_gates),
		prestige_count, tick_count, elapsed_seconds
	])
	parts.append("mob:%.12f,%.12f,%s,%.6f,%d,%d,%d,%d,%.12f,%.8f" % [
		mob_max_hp_log, mob_current_hp_log, str(is_boss), boss_timer,
		mobs_killed_in_stage, mobs_killed_total, boss_fail_streak,
		farm_kills_since_retreat, last_fail_margin_log, atk_progress
	])
	parts.append("stats:%.12f,%.12f,%.8f,%.12f,%.12f,%.12f,%.6f,%.6f,%.6f" % [
		stats.base_gold_atk_log, stats.gear_flat_atk_log, stats.additive_percent,
		stats.unique_mults_sum_log, stats.soul_mult_log, stats.abyss_mult_log,
		stats.atk_interval, stats.crit_rate, stats.crit_mult
	])
	parts.append("upg:%d,%d,%d|cred:%d,%s,%.12f" % [
		upgrades.atk_level, upgrades.speed_level, upgrades.crit_level,
		credit.credit_tier, str(credit.active_loan), credit.borrowed_principal_log
	])
	var rng_tuple: Array[int] = rng.get_state_tuple()
	parts.append("rng:%d,%d,%d|pity:%d,%s" % [
		rng_tuple[0], rng_tuple[1], rng_tuple[2],
		loot_roller.get_pity_counter(), str(loot_roller.is_first_run_pity_triggered())
	])
	for slot_key: String in EQUIP_SLOTS:
		var eq_item: ItemInstanceScript = equipped.get(slot_key, null) as ItemInstanceScript
		if eq_item == null:
			parts.append("eq_%s:null" % slot_key)
		else:
			parts.append("eq_%s:%d,%.8f" % [slot_key, eq_item.uid, eq_item.score])
	if backlash_stacks != 0.0 or stun_remaining_sec != 0.0 or boss_clone_triggered or boss_clones_remaining != 0 or recent_income_per_sec_log != NumScript.ZERO:
		parts.append("mech:%.8f,%.8f,%s,%d,%.12f" % [backlash_stacks, stun_remaining_sec, str(boss_clone_triggered), boss_clones_remaining, recent_income_per_sec_log])
	if credit.loan_count > 1 or stats.crit_rate_bonus != 0.0:
		parts.append("extra:%d,%.8f" % [credit.loan_count, stats.crit_rate_bonus])
	if mob_shield_max_log != NumScript.ZERO:
		parts.append("shield:%.12f,%.12f" % [mob_shield_max_log, mob_shield_cur_log])
	if not tech.researched.is_empty() or research_queue.size() > 0 or credit.tier_bonus > 0:
		parts.append("tech:%s|%s" % [tech.get_signature(), research_queue.get_signature()])
	if not buffs.is_empty():
		parts.append("buffs:%s" % buffs.get_signature())
	if is_rare_boss_active or rare_boss_timer > 0.0:
		parts.append("rare_boss:%s,%.6f,%d" % [str(is_rare_boss_active), rare_boss_timer, saved_regular_stage])
	parts.append("inv:%d" % inventory.get_count())
	for idx: int in range(inventory.get_count()):
		var inv_item: ItemInstanceScript = inventory.get_item_at(idx)
		parts.append("i%d:%d,%.8f" % [idx, inv_item.uid, inv_item.score])

	return parts

## 深拷贝完整模拟状态（供 DryRun 30s 干跑与 OfflineCalc 60s 采样校准使用）
func clone() -> SimState:
	var copy: SimState = (get_script() as GDScript).new(rng.master_seed, balance) as SimState
	copy.all_time_best = all_time_best
	copy.run_best = run_best
	copy.current_stage = current_stage
	copy.farm_stage = farm_stage
	copy.wallet = wallet.clone()
	copy.command_queue = command_queue.clone()
	copy.souls = souls
	copy.marks = marks
	copy.vault_powers = vault_powers.duplicate()
	copy.paid_gate_tier = paid_gate_tier
	copy.gate_boss_cleared = gate_boss_cleared
	copy.enforce_toll_gates = enforce_toll_gates
	copy.prestige_count = prestige_count
	copy.tick_count = tick_count
	copy.elapsed_seconds = elapsed_seconds
	copy.peak_soul_rate_log = peak_soul_rate_log
	copy.mob_max_hp_log = mob_max_hp_log
	copy.mob_current_hp_log = mob_current_hp_log
	copy.is_boss = is_boss
	copy.boss_timer = boss_timer
	copy.mobs_killed_in_stage = mobs_killed_in_stage
	copy.mobs_killed_total = mobs_killed_total
	copy.boss_fail_streak = boss_fail_streak
	copy.farm_kills_since_retreat = farm_kills_since_retreat
	copy.last_fail_margin_log = last_fail_margin_log
	copy.atk_progress = atk_progress
	copy.rng = rng.clone()
	copy.stats = stats.clone()
	copy.inventory = inventory.clone()
	copy.filter = filter.clone()
	copy.loot_roller = loot_roller.clone()
	copy.upgrades = upgrades.clone()
	copy.buffs = buffs.clone()
	copy.tech = tech.clone()
	copy.unlocked_vault_powers = unlocked_vault_powers.duplicate()
	copy.backlash_stacks = backlash_stacks
	copy.stun_remaining_sec = stun_remaining_sec
	copy.boss_clone_triggered = boss_clone_triggered
	copy.boss_clones_remaining = boss_clones_remaining
	copy.recent_income_per_sec_log = recent_income_per_sec_log
	copy.mech_absorbed_log = mech_absorbed_log.duplicate()
	copy.mech_dealt_log = mech_dealt_log
	copy.passive_totals = passive_totals.duplicate()
	copy.signals = signals.clone()
	copy.research_queue = research_queue.clone()
	copy.mob_shield_max_log = mob_shield_max_log
	copy.mob_shield_cur_log = mob_shield_cur_log
	copy.mob_shield_strip_cap_log = mob_shield_strip_cap_log
	if codex != null:
		copy.codex = codex.clone()
	if collection_roller != null:
		copy.collection_roller = collection_roller.clone()
	copy.transmog_slots = transmog_slots.duplicate()
	copy.is_rare_boss_active = is_rare_boss_active
	copy.saved_regular_stage = saved_regular_stage
	copy.rare_boss_timer = rare_boss_timer
	for slot_key: String in EQUIP_SLOTS:
		var eq_item: ItemInstanceScript = equipped.get(slot_key, null) as ItemInstanceScript
		if eq_item != null:
			var cloned_it: ItemInstanceScript = eq_item.clone()
			copy.equipped[slot_key] = cloned_it
			copy.equip_slots.equipped[int(cloned_it.slot)] = cloned_it
		else:
			copy.equipped[slot_key] = null
	copy.equip_slots.recalculate_and_apply(copy)
	copy.recalculate_stats()
	return copy
