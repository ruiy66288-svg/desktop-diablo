class_name Upgrades extends RefCounted

## 金币基础属性升级管理器 (依据《02_系统架构与数值_v6.md》§1.2 与《00_开发执行总纲.md》§2 E9、WP-05)
## 纯 RefCounted，零 Node 依赖，零硬编码常数

const NumScript = preload("res://core/num/Num.gd")
const BalanceScript = preload("res://simulation/Balance.gd")
const StatSheetScript = preload("res://simulation/StatSheet.gd")

var atk_level: int = 0
var speed_level: int = 0
var crit_level: int = 0

## 计算下一级基础攻击升级所需金币 (Log10 域)
func get_next_atk_cost_log(state: RefCounted) -> float:
	var bal: BalanceScript = state.get("balance") as BalanceScript
	return bal.get_upgrade_atk_cost_log(atk_level)

## 判定当前金币余额是否足以购买下一级基础攻击力
func can_buy_atk_upgrade(state: RefCounted) -> bool:
	var cur_gold: float = float(state.get("gold"))
	var cost_log: float = get_next_atk_cost_log(state)
	return cur_gold != NumScript.ZERO and cur_gold >= cost_log

## 尝试购买 1 级基础攻击力；购买成功返回 true 并同步重算角色面板
func buy_atk_upgrade(state: RefCounted) -> bool:
	var bal: BalanceScript = state.get("balance") as BalanceScript
	var cost_log: float = bal.get_upgrade_atk_cost_log(atk_level)

	var paid: bool = false
	if state.has_method("spend_gold"):
		paid = bool(state.call("spend_gold", cost_log))
	else:
		var cur_gold: float = float(state.get("gold"))
		if cur_gold != NumScript.ZERO and cur_gold >= cost_log:
			state.set("gold", NumScript.sub(cur_gold, cost_log))
			paid = true

	if paid:
		atk_level += 1
		if state.has_method("recalculate_stats"):
			state.call("recalculate_stats")
		else:
			var st: StatSheetScript = state.get("stats") as StatSheetScript
			st.base_gold_atk_log = bal.get_upgrade_gold_atk_log(atk_level)
		return true
	return false

## 连续购买最多 max_count 级基础攻击力，返回实际购买成功的级数
func buy_atk_upgrades_bulk(state: RefCounted, max_count: int) -> int:
	var bought: int = 0
	var target: int = maxi(0, max_count)
	for _i: int in range(target):
		if not buy_atk_upgrade(state):
			break
		bought += 1
	return bought

func reset_levels() -> void:
	atk_level = 0
	speed_level = 0
	crit_level = 0

func clone() -> Upgrades:
	var copy: Upgrades = (get_script() as GDScript).new() as Upgrades
	copy.atk_level = atk_level
	copy.speed_level = speed_level
	copy.crit_level = crit_level
	return copy
