class_name Balance extends Resource

## 《桌面破坏神》全局平衡常数与公式库
## 依据《02_系统架构与数值_v6.md》§1.2–§1.7、§2.3、§3.2、§5、§7 与《00_开发执行总纲.md》WP-02、§2 E1–E10、§4.5
## 铁律：所有可调常数统一配置于 res://content/balance.tres，业务代码中禁止硬编码数值常数

const NumScript = preload("res://core/num/Num.gd")
const DEFAULT_RESOURCE_PATH: String = "res://content/balance.tres"

static var _cached_default: Resource = null

static func load_default() -> Resource:
	if _cached_default != null:
		return _cached_default
	if ResourceLoader.exists(DEFAULT_RESOURCE_PATH):
		var loaded: Resource = ResourceLoader.load(DEFAULT_RESOURCE_PATH)
		if loaded != null:
			_cached_default = loaded
			return _cached_default
	_cached_default = load("res://simulation/Balance.gd").new()
	return _cached_default

static func reload_default() -> Resource:
	_cached_default = null
	if ResourceLoader.exists(DEFAULT_RESOURCE_PATH):
		var loaded: Resource = ResourceLoader.load(DEFAULT_RESOURCE_PATH, "", ResourceLoader.CACHE_MODE_REPLACE)
		if loaded != null:
			_cached_default = loaded
			return _cached_default
	_cached_default = load("res://simulation/Balance.gd").new()
	return _cached_default

# ------------------------------------------------------------------------------
# 1. 基础战斗与单次伤害模型 (§1.2)
# ------------------------------------------------------------------------------
@export_group("Combat Base (§1.2)")
@export var base_atk_interval: float = 0.50            # 来源: 02号文件 §1.2 — 默认基础攻击间隔 0.5 秒（攻速 2.0 次/秒）
@export var min_atk_interval: float = 0.01             # 来源: 02号文件 §1.2 & Q6 — 攻击间隔安全下限 0.01 秒
@export var base_crit_rate: float = 0.05               # 来源: 02号文件 §1.2 — 初始暴击率 5%
@export var crit_rate_cap: float = 0.75                # 来源: 02号文件 §1.2 — 暴击率上限 75%
@export var base_crit_mult: float = 1.50               # 来源: 02号文件 §1.2 — 初始暴击伤害倍率 1.50x

@export_group("Gold Upgrades & Gear (§1.2 & E10)")
@export var b0_atk_log: float = 2.0                    # 来源: 02号文件 §1.2 — 初始基础攻击 B0 = 100 (log10 = 2.0)
@export var beta_atk_log: float = 0.05690485           # 来源: 02号文件 §1.2 — 金币攻击每级乘数 β = 1.14 (log10(1.14))
@export var c0_cost_log: float = 1.0                   # 来源: 02号文件 §1.2 — 金币攻击初始升级费用 c0 = 10 (log10 = 1.0)
@export var gamma_cost_log: float = 0.06818586         # 来源: 02号文件 §1.2 — 金币攻击升级费用增长率 γ = 1.17 (log10(1.17))
@export var eq_phi_min: float = 0.30                   # 来源: 02号文件 §1.2 — 装备基础平值随机系数 φ 下限 0.30
@export var eq_phi_max: float = 1.00                   # 来源: 02号文件 §1.2 — 装备基础平值随机系数 φ 上限 1.00
@export var eq_g_log: float = 0.14612803               # 来源: 02号文件 §1.2 — 装备平值随 iLvl 指数增长 g = 1.40 (log10(1.40))
@export var gear_additive_pct_blue: float = 0.15       # 来源: 02号文件 §1.2 — 蓝装附加加法区百分比上限 15%
@export var gear_additive_pct_purple: float = 0.40     # 来源: 02号文件 §1.2 — 紫装附加加法区百分比上限 40%
@export var gear_additive_pct_unique: float = 0.80     # 来源: 02号文件 §1.2 — 暗金附加加法区百分比上限 80%
@export var gear_additive_pct_primal: float = 1.20     # 来源: 02号文件 §1.2 & §1.7 — 太古满 roll 附加加法区百分比 120%
@export var unique_mult_min: float = 1.50              # 来源: 02号文件 §1.2 — 暗金独立乘区单件下限 ×1.50
@export var unique_mult_max: float = 3.00              # 来源: 02号文件 §1.2 — 暗金独立乘区单件上限 ×3.00
@export var equip_slot_count: int = 6                  # 来源: 00号文件 §2 E10 & 02号文件 §1.2 — 6 装备槽位 (weapon/helm/chest/gloves/boots/trinket)
@export var e0_income_log: float = 1.0                 # 来源: 02号文件 §1.2 & §5.1 — 单怪基础金币基数 10 (log10 = 1.0)
@export var income_stage_log: float = 0.17609126       # 来源: 02号文件 §1.2 & §5.1 — 每层单怪金币增长率 1.50 (log10(1.50))
@export var expected_kills_per_min: float = 50.0       # 来源: 02号文件 §1.2 & §5.1 — 设计期望每分钟等效击杀数 50

# ------------------------------------------------------------------------------
# 2. 怪物血量曲线与推层规则 (§1.3 & Q3 & E3)
# ------------------------------------------------------------------------------
@export_group("Monster Curves (§1.3 & Q3)")
@export var h0_hp_log: float = 2.17609126              # 来源: 02号文件 §1.3 — 怪物初始血量基数 150 (log10(150))
@export var hp_linear_coeff: float = 0.20              # 来源: 02号文件 §1.3 — h(s) 线性增长系数 0.20
@export var hp_quad_coeff: float = 0.0005              # 来源: 02号文件 §1.3 — h(s) 二次增长系数 a = 0.0005
@export var boss_hp_mult_log: float = 1.0              # 来源: 02号文件 §1.3 — Boss 血量为同层小怪 10 倍 (+1.0 log10)
@export var boss_time_limit: float = 15.0              # 来源: 02号文件 §0 Q3 & §1.3 — Boss 挑战限时 15 秒
@export var mobs_per_stage: int = 10                   # 来源: 02号文件 §0 Q3 & §1.3 — 每层推进需击杀小怪 10 只
@export var farm_retry_kills: int = 20                 # 来源: 02号文件 §0 Q3 & 00号文件 E3 — 刷怪层周期自动重试图腾击杀数 20

# ------------------------------------------------------------------------------
# 3. 灵魂转生、深渊印记与自动转生 (§1.4 – §1.6)
# ------------------------------------------------------------------------------
@export_group("Prestige: Souls & Marks (§1.4–§1.6)")
@export var soul_start_stage: int = 50                 # 来源: 02号文件 §1.4 — 灵魂产出起始纪录层数 50
@export var soul_k_coeff: float = 0.05                 # 来源: 02号文件 §1.4 — 灵魂产出基础指数系数 k = 0.05
@export var soul_dmg_per_unit: float = 0.10            # 来源: 02号文件 §1.2 & §1.4 — 每点灵魂提供 +0.1 乘区: log10(1 + 0.1 * souls)
@export var mark_k_amp_per_mark: float = 0.20          # 来源: 02号文件 §1.5 — 每枚深渊印记放大 k 系数 20%: k = 0.05 * (1 + 0.2 * M)
@export var mark_stage_divisor: float = 100.0          # 来源: 02号文件 §1.5 — 深渊印记层数分母 100: floor((s_rec / 100)^1.5)
@export var mark_stage_exponent: float = 1.50          # 来源: 02号文件 §1.5 — 深渊印记层数幂指数 1.5
@export var vault_base_slots: int = 1                  # 来源: 02号文件 §1.5 — 卡奈永久威能初始槽位数 1
@export var vault_marks_per_extra_slot: int = 5        # 来源: 02号文件 §1.5 — 每 5 枚印记增加 1 个永久威能槽: 1 + floor(M / 5)
@export var auto_prestige_min_run_seconds: float = 1800.0 # 来源: 02号文件 §1.6 — 自动转生检测最短周目时长 1800 秒（30 分钟）
@export var auto_prestige_rate_drop_ratio: float = 0.95   # 来源: 02号文件 §1.6 — 灵魂速率跌破峰值 95% 时触发最优停止转生

# ------------------------------------------------------------------------------
# 4. 掉落、MF、保底、熔炼与背包 (§1.7 & Q12 & Q13)
# ------------------------------------------------------------------------------
@export_group("Loot, MF & Smelter (§1.7 & Q13)")
@export var drop_base_per_kill: float = 1.20           # 来源: 02号文件 §1.7 — 普通小怪每次击杀期望掉落 1.2 件
@export var boss_drop_base_count: int = 3              # 来源: 02号文件 §1.7 — Boss 击杀基础掉落件数 3 件
@export var drop_max_per_kill: int = 30                # 来源: 02号文件 §1.7 — 单次击杀掉落件数上限 30 件
@export var rarity_weight_white: float = 70.0          # 来源: 02号文件 §1.7 — 白装基础品质权重 70
@export var rarity_weight_blue: float = 22.0           # 来源: 02号文件 §1.7 — 蓝装基础品质权重 22
@export var rarity_weight_purple: float = 7.0          # 来源: 02号文件 §1.7 — 紫装基础品质权重 7
@export var rarity_weight_unique: float = 0.9          # 来源: 02号文件 §1.7 — 暗金基础品质权重 0.9
@export var rarity_weight_primal: float = 0.1          # 来源: 02号文件 §1.7 — 太古绯红基础品质权重 0.1
@export var mf_diminish_k: float = 250.0               # 来源: 02号文件 §1.7 — D2 式 MF 递减常数 250: MF * 250 / (MF + 250)
@export var unique_pity_kills: int = 140               # 来源: 02号文件 §1.7 — 首周目连续 140 次击杀未出暗金触发保底
@export var primal_bonus_ilvl: int = 5                 # 来源: 02号文件 §1.7 — 太古绯红额外 +5 iLvl
@export var primal_extra_affixes: int = 1              # 来源: 02号文件 §1.7 — 太古绯红额外 +1 词条
@export var inventory_max_slots: int = 24              # 来源: 02号文件 §0 Q13 — 背包容量固定 24 格
@export var score_rarity_weight: float = 1000.0        # 来源: 02号文件 §0 Q13 — 背包淘汰评分中品质阶次权重 1000
@export var score_ilvl_weight: float = 10.0            # 来源: 02号文件 §0 Q13 — 背包淘汰评分中 iLvl 权重 10
@export var smelt_mult_white_log: float = 0.0          # 来源: 02号文件 §1.7 — 白装熔炼金币倍率 1.0x (log10 = 0.0)
@export var smelt_mult_blue_log: float = 0.39794001    # 来源: 02号文件 §1.7 — 蓝装熔炼金币倍率 2.5x (log10(2.5))
@export var smelt_mult_purple_log: float = 0.90308999  # 来源: 02号文件 §1.7 — 紫装熔炼金币倍率 8.0x (log10(8.0))
@export var smelt_mult_unique_log: float = 1.47712125  # 来源: 02号文件 §1.7 — 暗金熔炼金币倍率 30.0x (log10(30.0))
@export var smelt_mult_primal_log: float = 2.0         # 来源: 02号文件 §1.7 — 太古熔炼金币倍率 100.0x (log10(100.0))
@export var manual_pickup_bonus_rate: float = 0.10     # 来源: 02号文件 §0 Q12 & §3.3 — 鼠标手动划过拾取额外 +10% 金币

# ------------------------------------------------------------------------------
# 5. 模拟时钟、混合粒度结算与防递归预算 (§0 Q5–Q7, §2.3, §3.2)
# ------------------------------------------------------------------------------
@export_group("Sim Runner & Resolver (§0 Q6, §2.3, §3.2)")
@export var sim_tick_dt: float = 0.10                  # 来源: 02号文件 §0 Q5 & §3.2 — 10Hz 固定模拟步长 0.1 秒
@export var max_catchup_ticks: int = 50                # 来源: 02号文件 §3.2 & 00号文件 WP-03 — 单次最多追赶 50 个 tick（5 秒）
@export var hybrid_individual_attacks: int = 8         # 来源: 02号文件 §0 Q6 & 00号文件 WP-03 — 每 tick 前 8 次攻击逐次结算，超额按二项分布聚合
@export var max_kills_per_tick: int = 20               # 来源: 02号文件 §0 Q6 & 00号文件 WP-03 — 每 tick 溢出穿透最多击杀 20 只怪
@export var resolver_max_depth: int = 4                # 来源: 02号文件 §0 Q7 & §2.3 — 词条派生事件最大递归深度 4
@export var resolver_max_events_per_tick: int = 256    # 来源: 02号文件 §2.3 — 每 tick 事件处理全局上限 256
@export var resolver_max_spill: int = 512              # 来源: 02号文件 §2.3 — 事件队列触发强制合并上限 512
@export var event_compact_threshold: int = 64          # 来源: 02号文件 §2.3 — EventQueue 同类事件轻量压缩阈值 64
@export var overflow_reward_offset_log: float = -1.0   # 来源: 02号文件 §2.3 — 超出最大深度转化的保底金币系数 0.1x (-1.0 log10)

# ------------------------------------------------------------------------------
# 6. 净财富压力与信贷系统 (§5.1 – §5.2 & 勘误 E4, Q23, Q26, Q35)
# ------------------------------------------------------------------------------
@export_group("Wealth Pressure (§5.1 & E4)")
@export var wealth_pressure_slope: float = 0.50        # 来源: 02号文件 §5.1 — 囤钱正净财富斜率 0.5: 0.5 * log10(W/I)
@export var max_wealth_hp_mult_log: float = 0.47712125 # 来源: 02号文件 §5.1 & 00号文件 E4 — 普通财富压力怪物血量上限 ×3 (log10(3))
@export var debt_relief_slope: float = 0.06            # 来源: 02号文件 §5.1 — 净负债减血斜率 0.06: max(0.4, 1 + 0.06 * W/I)
@export var min_debt_hp_factor: float = 0.40           # 来源: 02号文件 §5.1 & 00号文件 E4 — 负债怪物血量最低降至 40%
@export var min_debt_hp_mult_log: float = -0.39794001  # 来源: 02号文件 §5.1 & 00号文件 E4 — 负债怪物血量下限 log10(0.4)

@export_group("Credit & Legacy Debt (§5.2 & Q26 & Q35)")
@export var credit_limit_base_minutes: float = 10.0    # 来源: 02号文件 §5.2 — 0 级信用基础额度为 10 分钟期望收入
@export var credit_limit_tier_growth: float = 1.50     # 来源: 02号文件 §5.2 — 每升 1 级信用额度乘以 1.5: I * 10 * 1.5^tier
@export var credit_base_mult: float = 1.10             # 来源: 02号文件 §5.2 & Q26 — 借款基础还款溢价 1.10x
@export var credit_quad_coeff: float = 0.50            # 来源: 02号文件 §5.2 & Q26 — 借款溢价二次系数 0.50: 1.1 + 0.5 * u^2（借满 1.6x）
@export var repayment_deduction_rate: float = 0.40     # 来源: 02号文件 §5.2 & Q26 & Q35 — 每笔收入自动扣 40% 偿债/抵扣宿债
@export var credit_max_concurrent_loans: int = 1       # 来源: 02号文件 §5.2 — 默认同时允许最多 1 笔活跃借款

# ------------------------------------------------------------------------------
# 7. 科技树研究与离线结算上限 (§3.4 & §5.3 & Q5 & Q27)
# ------------------------------------------------------------------------------
@export_group("Tech Tree & Offline (§3.4 & §5.3)")
@export var tech_base_minutes: float = 2.0             # 来源: 02号文件 §5.3 — 科技节点基础研究时长 2 分钟: 2 * 2.2^tier
@export var tech_tier_time_growth: float = 2.20        # 来源: 02号文件 §5.3 — 科技研究时长层级指数底数 2.2
@export var tech_queue_max_slots: int = 5              # 来源: 02号文件 §0 Q27 & §5.3 — 研究队列容量上限 5 格
@export var auto_buy_max_per_tick: int = 16            # 来源: 02号文件 §5.3 自动化分支 — 自动购买金币升级每 tick 最多购买级数 (防单 tick 爆循环)
@export var tech_deep_unlock_tier: int = 5             # 来源: 02号文件 §5.3 — 深渊印记解锁第 5 层以后深层节点
@export var offline_sample_seconds: float = 60.0       # 来源: 02号文件 §3.4 第 7 条 & §2.1 — 离线结算 60 秒校准采样窗口
@export var offline_cap_base_hours: float = 8.0        # 来源: 02号文件 §0 Q5 & §3.4 — 默认离线收益上限 8 小时
@export var offline_cap_max_hours: float = 24.0        # 来源: 02号文件 §0 Q5 & §3.4 & §5.3 — 升级后离线收益上限 24 小时

# ------------------------------------------------------------------------------
# 8. 每 100 层机制变阵、卡墙信号与关卡门票 (§7.1 – §7.3 & Q30–Q32, Q36)
# ------------------------------------------------------------------------------
@export_group("Band Mechanics & Toll Gates (§7.1–§7.3)")
@export var band_stage_interval: int = 100             # 来源: 02号文件 §7.1 & Q31 — 每 100 层切换主题机制并设关卡门票
@export var band_lingering_strength: float = 0.30      # 来源: 02号文件 §7.1 & Q31 — 上一区间主题机制保留 30% 余韵强度
@export var mech_shield_hp_ratio: float = 0.50         # 来源: 02号文件 §7.1 — 100–199 层护盾：额外 50% 最大生命护盾
@export var mech_shield_max_hit_strip: float = 0.02    # 来源: 02号文件 §7.1 — 100–199 层护盾：每次命中最多削掉 2% 护盾
@export var mech_backlash_max_stacks: int = 40         # 来源: 02号文件 §7.1 & Q30 — 200–299 层反噬：累积满 40 点触发眩晕
@export var mech_backlash_stun_seconds: float = 2.0    # 来源: 02号文件 §7.1 & Q30 — 200–299 层反噬：攒满后眩晕 2 秒
@export var mech_crit_only_non_crit_mult: float = 0.05 # 来源: 02号文件 §7.1 — 300–399 层只吃暴击：非暴击伤害 ×0.05
@export var mech_clone_trigger_hp_ratio: float = 0.50  # 来源: 02号文件 §7.1 — 400–499 层分身：Boss 血量降至 50% 时分裂
@export var mech_clone_split_count: int = 4            # 来源: 02号文件 §7.1 — 400–499 层分身：分裂为 4 个分身
@export var mech_gold_eat_balance_rate: float = 0.01   # 来源: 02号文件 §7.1 — 500–599 层吞金：怪物存活每秒吞掉余额 1%
@export var mech_gold_eat_income_cap: float = 0.50     # 来源: 02号文件 §7.1 — 500–599 层吞金：吞金速率不超过收入的 50%
@export var wall_signal_fail_streak: int = 5           # 来源: 02号文件 §7.2 — 连续 5 次挑战 Boss 失败触发灰白卡墙信号
@export var toll_expected_income_minutes: float = 30.0 # 来源: 02号文件 §7.3 & Q32 — 关卡门票价格 = 分界层 30 分钟设计期望收入
@export var toll_saving_lead_stages: int = 5           # 来源: 02号文件 §7.3 & Q36 — 到达门前 5 层以内且净资产不足时进入储蓄托管模式

# ------------------------------------------------------------------------------
# 9. 换装干跑 DryRun (§0 Q14)
# ------------------------------------------------------------------------------
@export_group("DryRun (§0 Q14)")
@export var dry_run_seconds: float = 30.0                # 来源: 02号文件 §0 Q14 & §2.1 — 克隆 Sim 干跑 30 秒得出换装 Δ%
@export var dry_run_default_seed: int = 987654321        # 来源: 02号文件 §2.1 — 干跑默认确定性种子 (同种子结果可复现)
@export var dry_run_display_cap_log: float = 5.0        # 来源: 02号文件 §0 Q14 — Δ% 展示上限 10^5 倍 (避免溢出显示)

# ------------------------------------------------------------------------------
# 10. 阶段 2：机制池收益统计、暗金雨、深渊转生 (§2.4, §1.5, §7.1)
# ------------------------------------------------------------------------------
@export_group("Phase 2 (§1.5, §2.4, §7.1)")
@export var mech_income_ema_new: float = 0.10          # 来源: 02号文件 §7.1 吞金 & curve_sim 口径 — 近期每秒收入滑动平均新样本权重 (旧值权重 = 1 - 该值)
@export var mech_income_min_interval: float = 0.5      # 来源: 02号文件 §7.1 吞金 & curve_sim 口径 — 单次击杀折算每秒收入的最小攻击间隔(秒)
@export var unique_rain_drop_mult: int = 10             # 来源: 02号文件 §2.4 暗金雨 — 下一次击杀掉落件数 ×10
@export var unique_rain_rarity_floor: int = 2           # 来源: 02号文件 §2.4 暗金雨 — 品质保底 紫装 (Rarity.PURPLE = 2)
@export var abyss_min_stage: int = 100                 # 来源: 02号文件 §1.5 — ΔM = floor((s/100)^1.5) 至少需要 100 层才可深渊转生

# ------------------------------------------------------------------------------
# 11. 阶段 2 收藏、图鉴、隐藏套装与稀有 Boss (§8.1–§8.3 & Q33–Q34)
# ------------------------------------------------------------------------------
@export_group("Collection & Codex (§8.1–§8.3)")
@export var codex_gold_bonus_per_entry: float = 0.005   # 来源: 02号文件 §8.3 & Q34 — 图鉴每点亮 1 项永久提供 +0.5% 金币获取加成
@export var mythic_base_chance: float = 0.0005          # 来源: 02号文件 §8.1 — 暗金变体神话判定基准概率 1/2,000
@export var primal_transmog_chance: float = 0.02        # 来源: 02号文件 §8.1 — 太古独特外观判定基准概率 1/50
@export var summon_rune_base_chance: float = 0.00035    # 来源: 02号文件 §8.1 — 稀有 Boss 召唤符文每模拟分钟判定基准概率 (~1-2天1枚)
@export var bad_luck_mult: float = 1.02                 # 来源: 02号文件 §8.1 — 坏运气保护：失败后单次概率乘 1.02，成功后重置
@export var rare_boss_time_limit: float = 30.0          # 来源: 02号文件 §8.2 — 稀有 Boss 挑战限时 30 秒 (超时无损返还符文)
@export var rare_boss_hp_mult: float = 5.0              # 来源: 02号文件 §8.2 — 稀有 Boss 相对同层 Boss 的血量倍率 (5.0x)

# ------------------------------------------------------------------------------
# 数值公式计算接口（全部读取导出常数，零硬编码）
# ------------------------------------------------------------------------------

## 计算第 stage 层普通小怪基础血量 h(s) (Log10 域, §1.3)
func get_monster_hp_log(stage: int) -> float:
	var s: float = float(stage)
	return h0_hp_log + hp_linear_coeff * s + hp_quad_coeff * (s * s)

## 计算第 stage 层 Boss 基础血量 (Log10 域, §1.3)
func get_boss_hp_log(stage: int) -> float:
	return get_monster_hp_log(stage) + boss_hp_mult_log

## 计算第 stage 层单只怪物击杀金币 (Log10 域, §1.2)
func get_mob_gold_log(stage: int) -> float:
	var s: float = float(stage)
	return e0_income_log + income_stage_log * s

## 计算第 stage 层设计期望每分钟金币收入 I (Log10 域, §1.2 & §5.1)
func get_expected_income_per_min_log(stage: int) -> float:
	return get_mob_gold_log(stage) + NumScript.from_float(expected_kills_per_min)

## 计算金币攻击力等级 atk_level 对应的基础金币攻击力 B_gold (Log10 域, §1.2)
func get_upgrade_gold_atk_log(atk_level: int) -> float:
	return b0_atk_log + float(atk_level) * beta_atk_log

## 计算购买下一级（当前等级 atk_level）金币攻击升级的花费 (Log10 域, §1.2)
func get_upgrade_atk_cost_log(atk_level: int) -> float:
	return c0_cost_log + float(atk_level) * gamma_cost_log

## 计算 iLvl 与随机系数 phi 对应的装备平值攻击力 F(iLvl) (Log10 域, §1.2)
func get_equip_flat_atk_log(ilvl: int, phi: float) -> float:
	var clamped_phi: float = clampf(phi, eq_phi_min, eq_phi_max)
	return b0_atk_log + NumScript.from_float(clamped_phi) + float(ilvl) * eq_g_log

## 计算净财富压力导致的怪物血量修正 Δh_wealth (Log10 域, §5.1 & 勘误 E4)
## is_debt = false 时 ratio = W / I；is_debt = true 时 ratio = |W| / I = (debt_total - gold) / I
func get_wealth_pressure_hp_delta(is_debt: bool, ratio: float) -> float:
	if not is_debt:
		if ratio <= 1.0:
			return 0.0
		var g: float = NumScript.from_float(ratio)
		return minf(wealth_pressure_slope * g, max_wealth_hp_mult_log)
	var factor: float = maxf(min_debt_hp_factor, 1.0 - debt_relief_slope * maxf(0.0, ratio))
	return maxf(min_debt_hp_mult_log, NumScript.from_float(factor))

## 计算信用等级 credit_tier 在第 stage 层的最大借款额度 limit = I * 10 * 1.5^tier (Log10 域, §5.2)
func get_credit_limit_log(stage: int, credit_tier: int) -> float:
	var income_min_log: float = get_expected_income_per_min_log(stage)
	var base_log: float = NumScript.from_float(credit_limit_base_minutes)
	var tier_log: float = float(credit_tier) * NumScript.from_float(credit_limit_tier_growth)
	return income_min_log + base_log + tier_log

## 计算借款浮动还款溢价倍率: 1.1 + 0.5 * u^2 (§5.2 & Q26)
func get_credit_repayment_mult(utilization_rate: float) -> float:
	var u: float = clampf(utilization_rate, 0.0, 1.0)
	return credit_base_mult + credit_quad_coeff * (u * u)

## 计算第 gate_tier 道门（对应 gate_tier * 100 层）的门票价格 (Log10 域, §7.3 & Q32)
func get_toll_cost_log(gate_tier: int) -> float:
	var gate_stage: int = gate_tier * band_stage_interval
	var income_min_log: float = get_expected_income_per_min_log(gate_stage)
	return income_min_log + NumScript.from_float(toll_expected_income_minutes)

## 获取当前推进层即将面临的下一道门票阶次（如 95..100 层对应 gate_tier = 1）
func get_upcoming_gate_tier(stage: int, paid_gate_tier: int) -> int:
	var next_tier: int = paid_gate_tier + 1
	var gate_stage: int = next_tier * band_stage_interval
	if stage >= gate_stage - toll_saving_lead_stages and stage <= gate_stage:
		return next_tier
	return 0

## 判定当前层是否处于门前 5 层储蓄区 (§7.3 & Q36)
func is_in_toll_saving_zone(stage: int, paid_gate_tier: int) -> bool:
	return get_upcoming_gate_tier(stage, paid_gate_tier) > 0

## 计算含深渊印记加成的有效灵魂指数系数 k = 0.05 * (1 + 0.2 * M) (§1.4 & §1.5)
func get_effective_soul_k(marks: int) -> float:
	return soul_k_coeff * (1.0 + mark_k_amp_per_mark * float(maxi(0, marks)))

## 计算纪录层数 run_best_stage 在当前印记数 marks 下转生可获灵魂 (Log10 域, §1.4 & §1.5)
func get_pending_souls_log(run_best_stage: int, marks: int = 0) -> float:
	if run_best_stage <= soul_start_stage:
		return NumScript.ZERO
	var k_eff: float = get_effective_soul_k(marks)
	return k_eff * float(run_best_stage - soul_start_stage)

## 计算当前灵魂储备提供的灵魂独立乘区 s_soul = log10(1 + 0.1 * souls) (§1.2 & §1.4)
func get_soul_mult_log(souls_log: float) -> float:
	if souls_log == NumScript.ZERO:
		return 0.0
	var scaled_souls_log: float = souls_log + NumScript.from_float(soul_dmg_per_unit)
	return NumScript.add(0.0, scaled_souls_log)

## 计算历史最高层 record_stage 进行深渊转生可获印记数 ΔM = floor((s_rec / 100)^1.5) (§1.5)
func get_pending_marks(record_stage: int) -> int:
	if float(record_stage) < mark_stage_divisor:
		return 0
	var ratio: float = float(record_stage) / mark_stage_divisor
	return int(floor(pow(ratio, mark_stage_exponent)))

## 计算当前累计印记数对应的永久威能槽数 1 + floor(M / 5) (§1.5)
func get_vault_slot_count(marks: int) -> int:
	if vault_marks_per_extra_slot <= 0:
		return vault_base_slots
	return vault_base_slots + int(floor(float(maxi(0, marks)) / float(vault_marks_per_extra_slot)))

## 计算 D2 式递减有效 MF: MF_eff = MF * 250 / (MF + 250) (§1.7)
func get_effective_mf(raw_mf: float) -> float:
	if raw_mf <= 0.0:
		return 0.0
	return (raw_mf * mf_diminish_k) / (raw_mf + mf_diminish_k)

## 获取指定品质对应的熔炼金币乘数 (Log10 域, §1.7)
func get_smelt_mult_log(rarity: int) -> float:
	match rarity:
		0:
			return smelt_mult_white_log
		1:
			return smelt_mult_blue_log
		2:
			return smelt_mult_purple_log
		3:
			return smelt_mult_unique_log
		4:
			return smelt_mult_primal_log
		_:
			return smelt_mult_white_log

## 计算第 tier 层科技节点所需研究时长（秒, §5.3: 2 min * 2.2^tier）
func get_tech_research_seconds(tier: int, debug_seconds_mode: bool = false) -> float:
	var seconds_per_min: float = 1.0 if debug_seconds_mode else 60.0
	return tech_base_minutes * seconds_per_min * pow(tech_tier_time_growth, float(maxi(0, tier)))
