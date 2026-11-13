class_name AffixDef extends Resource

## 统一词条资源定义 (依据《02_系统架构与数值_v6.md》§2.3–§2.4)

const TriggerDefScript = preload("res://simulation/affix/TriggerDef.gd")
const EffectDefScript = preload("res://simulation/affix/EffectDef.gd")

@export var id: String = ""
@export var name: String = ""
@export var desc_template: String = ""

@export var is_passive: bool = false
@export var stat_key: String = ""
@export var stat_val: float = 0.0

@export var trigger: TriggerDefScript = null
@export var effect: EffectDefScript = null
@export var budget_per_tick: int = 10
@export var extra_stats: Dictionary = {}                  # 被动词条的附加属性 {stat_key: val}
@export var counter_tags: Array[String] = []            # 克制的关卡机制标签 (02 §6.2)

func _init(p_id: String = "", p_name: String = "", p_passive: bool = false) -> void:
	id = p_id
	name = p_name
	is_passive = p_passive
