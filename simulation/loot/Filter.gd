class_name Filter extends RefCounted

## 智能掉落拾取过滤器 (依据《02_系统架构与数值_v6.md》§0 Q13 & WP-05: 保留品质 >= X，默认暗金)
## 纯 RefCounted，零 Node 依赖

const ItemInstanceScript = preload("res://simulation/loot/ItemInstance.gd")

var keep_threshold: int = ItemInstanceScript.Rarity.UNIQUE

func _init(p_threshold: int = ItemInstanceScript.Rarity.UNIQUE) -> void:
	set_threshold(p_threshold)

func set_threshold(p_threshold: int) -> void:
	keep_threshold = clampi(
		p_threshold,
		int(ItemInstanceScript.Rarity.WHITE),
		int(ItemInstanceScript.Rarity.PRIMAL)
	)

func get_threshold() -> int:
	return keep_threshold

## 判定该装备是否保留进包（false 则立即自动熔炼为 gold）
func should_keep(item: ItemInstanceScript) -> bool:
	if item == null:
		return false
	return int(item.rarity) >= keep_threshold

func clone() -> Filter:
	return (get_script() as GDScript).new(keep_threshold) as Filter
