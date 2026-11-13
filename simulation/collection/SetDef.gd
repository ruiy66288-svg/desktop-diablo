class_name SetDef extends Resource

## 隐藏套装定义 (依据《02_系统架构与数值_v6.md》§8.1 & §8.4)
## 同时穿戴特定具名词条暗金时激活隐藏套装，并永久点亮图鉴

@export var id: String = ""
@export var name_zh: String = ""
@export var desc: String = ""
@export var required_affix_ids: Array[String] = []
@export var bonus_stats: Dictionary = {}  # {stat_key: value}
@export var vfx_hint: String = ""
