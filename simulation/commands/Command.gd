class_name Command extends RefCounted

## UI 到 Simulation 权威层的只写指令载荷 (依据《02_系统架构与数值_v6.md》§2.1 & Q12 与《00_开发执行总纲.md》§4.2、WP-05)
## 纯 RefCounted，零 Node 依赖

const SELF_SCRIPT_PATH: String = "res://simulation/commands/Command.gd"

enum Type {
	BUY_ATK_UPGRADE,      # 购买金币基础攻击升级: payload {"count": int}
	MANUAL_PICKUP,        # 鼠标划过拾取 (+10% 金币奖励): payload {"ilvl": int, "rarity": int, "base_gold_log": float}
	EQUIP_ITEM,           # 6 槽换装: payload {"item_uid": int} 或 {"item": ItemInstance}
	SMELT_ITEM,           # 手动熔炼背包单件: payload {"item_uid": int}
	BORROW_CREDIT,        # 申请信贷: payload {"amount_log": float}
	REPAY_CREDIT,         # 主动使用金币余额还款: payload {"amount_log": float}
	SOUL_PRESTIGE,        # 灵魂转生: payload {}
	ABYSS_PRESTIGE,       # 深渊印记转生: payload {"extract_power_id": String}
	SET_FILTER_THRESHOLD,  # 设置掉落过滤保留品质阈值 (>= threshold): payload {"threshold": int}
	START_RESEARCH,        # 开始研究科技节点 (§5.3): payload {"node_id": String, "now_unix": int}
	SETTLE_RESEARCH,       # 按 Unix 时间戳结算到期研究 (离线重开同样使用): payload {"now_unix": int}
	EQUIP_VAULT_POWER,     # 将已解锁的永久威能装配进威能槽: payload {"affix_id": String}
	UNEQUIP_VAULT_POWER,   # 卸下威能槽中的永久威能: payload {"affix_id": String}
	ACK_SIGNAL,            # 确认并消除边缘光带信号: payload {"kind": int}
	SUMMON_RARE_BOSS,      # 消耗 1 枚符文开启稀有 Boss「契约大执政官」独立挑战房: payload {}
	ABORT_RARE_BOSS,       # 主动撤退稀有 Boss 挑战（零损失返还符文）: payload {}
	SET_TRANSMOG           # 设置 6 槽装备幻化外观: payload {"slot": String, "appearance_id": String}
}

var type: Type = Type.BUY_ATK_UPGRADE
var payload: Dictionary = {}

func _init(p_type: Type, p_payload: Dictionary = {}) -> void:
	type = p_type
	payload = p_payload.duplicate()

static func _create(p_type: Type, p_payload: Dictionary) -> Command:
	var script_ref: GDScript = load(SELF_SCRIPT_PATH) as GDScript
	return script_ref.new(p_type, p_payload) as Command

static func make_buy_atk(count: int = 1) -> Command:
	return _create(Type.BUY_ATK_UPGRADE, {"count": maxi(1, count)})

static func make_manual_pickup(ilvl: int = -1, rarity: int = 0) -> Command:
	return _create(Type.MANUAL_PICKUP, {"ilvl": ilvl, "rarity": rarity})

static func make_equip_uid(item_uid: int) -> Command:
	return _create(Type.EQUIP_ITEM, {"item_uid": item_uid})

static func make_smelt_uid(item_uid: int) -> Command:
	return _create(Type.SMELT_ITEM, {"item_uid": item_uid})

static func make_set_filter(threshold: int) -> Command:
	return _create(Type.SET_FILTER_THRESHOLD, {"threshold": threshold})

static func make_borrow(amount_log: float) -> Command:
	return _create(Type.BORROW_CREDIT, {"amount_log": amount_log})

static func make_repay(amount_log: float) -> Command:
	return _create(Type.REPAY_CREDIT, {"amount_log": amount_log})

static func make_soul_prestige() -> Command:
	return _create(Type.SOUL_PRESTIGE, {})

static func make_abyss_prestige(extract_power_id: String = "") -> Command:
	return _create(Type.ABYSS_PRESTIGE, {"extract_power_id": extract_power_id})

static func make_start_research(node_id: String, now_unix: int) -> Command:
	return _create(Type.START_RESEARCH, {"node_id": node_id, "now_unix": now_unix})

static func make_settle_research(now_unix: int) -> Command:
	return _create(Type.SETTLE_RESEARCH, {"now_unix": now_unix})

static func make_equip_vault_power(affix_id: String) -> Command:
	return _create(Type.EQUIP_VAULT_POWER, {"affix_id": affix_id})

static func make_unequip_vault_power(affix_id: String) -> Command:
	return _create(Type.UNEQUIP_VAULT_POWER, {"affix_id": affix_id})

static func make_ack_signal(kind: int) -> Command:
	return _create(Type.ACK_SIGNAL, {"kind": kind})

static func make_summon_rare_boss() -> Command:
	return _create(Type.SUMMON_RARE_BOSS, {})

static func make_abort_rare_boss() -> Command:
	return _create(Type.ABORT_RARE_BOSS, {})

static func make_set_transmog(slot: String, appearance_id: String) -> Command:
	return _create(Type.SET_TRANSMOG, {"slot": slot, "appearance_id": appearance_id})

func clone() -> Command:
	return (get_script() as GDScript).new(type, payload.duplicate()) as Command
