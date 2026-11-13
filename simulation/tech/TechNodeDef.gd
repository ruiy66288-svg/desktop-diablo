class_name TechNodeDef extends Resource

## 科技节点定义 (依据《02_系统架构与数值_v6.md》§5.3 与《00_开发执行总纲.md》WP-14)
## 数据存放于 res://content/tech/*.tres，每个常数旁标注来源

@export var id: String = ""
@export var display_name: String = ""
@export var branch: String = ""          # combat / economy / credit / automation (Q28)
@export var tier: int = 1                # 研究时长 T(tier) = 2 分钟 × 2.2^tier (Balance.get_tech_research_seconds)
@export var cost_gold_log: float = 0.0   # 研究价格 (log10 金币)
@export var prereq_id: String = ""
@export var requires_marks: int = 0       # 深渊印记解锁门槛 (§5.3：深渊印记解锁第 5 层以后的深层节点)
@export var effect_key: String = ""      # additive_pct / crit_rate / income_mult_pct / credit_tier_bonus / drop_qty_bonus / auto_buy_atk
@export var effect_val: float = 0.0
@export var desc: String = ""