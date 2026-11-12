class_name Command extends RefCounted

## UI 到 Simulation 权威层的只写指令载荷 (依据《02_系统架构与数值_v6.md》§2.1 & Q12)
## 纯 RefCounted，零 Node 依赖

enum Type {
	BUY_ATK_UPGRADE,   # 购买金币基础攻击升级
	MANUAL_PICKUP,     # 鼠标划过拾取 (+10% 金币奖励)
	EQUIP_ITEM,        # 6 槽换装
	SMELT_ITEM,        # 手动熔炼背包单件
	BORROW_CREDIT,     # 申请信贷
	REPAY_CREDIT,      # 手动还款
	SOUL_PRESTIGE,     # 灵魂转生
	ABYSS_PRESTIGE     # 深渊印记转生
}

var type: Type = Type.BUY_ATK_UPGRADE
var payload: Dictionary = {}

func _init(p_type: Type, p_payload: Dictionary = {}) -> void:
	type = p_type
	payload = p_payload
