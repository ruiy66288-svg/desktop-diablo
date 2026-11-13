class_name CosmeticDef extends Resource

## 外观与幻化定义 (依据《02_系统架构与数值_v6.md》§8.3 & §8.4)
## 仅改变表现层的外观、配色与特效，不影响战斗模拟

@export var id: String = ""
@export var name_zh: String = ""
@export var desc: String = ""
@export var slot_target: String = ""  # theme / beam / skin_kill / transmog_weapon / transmog_trinket
@export var icon_path: String = ""
@export var vfx_key: String = ""
