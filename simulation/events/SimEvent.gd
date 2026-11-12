class_name SimEvent extends RefCounted

## 《桌面破坏神》统一战斗与经济事件结构 (依据《02_系统架构与数值_v6.md》§2.2 & §5.4)
## 纯 RefCounted，零 Node 依赖

enum T {
	HIT,        # 攻击命中 (value: 造成的伤害, log10)
	CRIT,       # 暴击命中
	KILL,       # 击杀普通怪
	BOSS_KILL,  # 击杀 Boss
	DROP,       # 产生掉落
	SMELT,      # 熔炼装备
	METEOR,     # 陨石秒杀等特殊触发
	TIMER,      # 挂机周期计时触发
	STAGE_UP,   # 成功突破至下一层
	ATTENTION   # 桌面边缘呼吸灯提醒 (§5.4)
}

var type: T = T.HIT
var count: int = 1
var value: float = 0.0
var payload: Dictionary = {}
var depth: int = 0
var chain_mask: int = 0
var hint: Dictionary = {}

func _init(p_type: T = T.HIT, p_val: float = 0.0, p_count: int = 1) -> void:
	type = p_type
	value = p_val
	count = p_count
