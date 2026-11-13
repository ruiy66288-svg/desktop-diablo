class_name MechanicDef extends Resource

## 关卡主题机制定义 (依据《02_系统架构与数值_v6.md》§7.1 与《00_开发执行总纲.md》WP-15)
## 数值常数在 Balance（mech_shield_hp_ratio / mech_shield_max_hit_strip / band_lingering_strength）；本资源仅描述身份与提示文案

enum Kind {
	NONE = 0,
	SHIELD = 1,      # 100–199 护盾
	BACKLASH = 2,    # 200–299 反噬（原型不实装）
	CRIT_ONLY = 3,   # 300–399 只吃暴击（原型不实装）
	CLONE = 4,       # 400–499 分身（原型不实装）
	GOLD_EAT = 5     # 500–599 吞金（原型不实装）
}

@export var id: String = ""
@export var display_name: String = ""
@export var kind: Kind = Kind.NONE
@export var wall_hint: String = ""    # 卡墙信号文案 (§7.2)
@export var counter_tags: Array[String] = []   # 克制该机制的词条标签 (每种机制至少 2 种克制词条, §6.2)