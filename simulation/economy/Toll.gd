class_name Toll extends RefCounted

## 关卡门票只读状态与卡墙提示 (依据《02_系统架构与数值_v6.md》§7.1–§7.3、Q32、Q36 与《00_开发执行总纲.md》WP-15)
## 结算逻辑本体在 SimState（can_pay_toll_tier / try_pay_next_toll / add_income 托管分流），本类提供 UI 与测试用的只读快照

const NumScript = preload("res://core/num/Num.gd")
const BalanceScript = preload("res://simulation/Balance.gd")
const BandRulesScript = preload("res://simulation/mechanics/BandRules.gd")
const MechanicDefScript = preload("res://simulation/mechanics/MechanicDef.gd")

const PHASE_NONE: String = "none"
const PHASE_SAVING: String = "saving"        # 门前储蓄托管中
const PHASE_WAITING: String = "waiting"      # 分界 Boss 已击杀，等待门票缴清
const PHASE_WALL_SHIELD: String = "wall_shield"
const PHASE_WALL_POWER: String = "wall_power"

## 返回当前门票快照：tier / gate_stage / toll_log / net_assets_log / progress(0..1) / saving / waiting / paid_tier
static func get_status(state: RefCounted) -> Dictionary:
	var bal: BalanceScript = state.get("balance") as BalanceScript
	var current_stage: int = int(state.get("current_stage"))
	var paid_tier: int = int(state.get("paid_gate_tier"))
	var upcoming: int = bal.get_upcoming_gate_tier(current_stage, paid_tier)
	var waiting: bool = bool(state.get("gate_boss_cleared"))
	var tier: int = upcoming
	if tier <= 0 and waiting:
		tier = paid_tier + 1
	var toll_log: float = bal.get_toll_cost_log(tier) if tier > 0 else NumScript.ZERO
	var gold: float = float(state.get("gold"))
	var escrow: float = float(state.get("toll_escrow"))
	var debt: float = float(state.get("debt_total"))
	var liquid: float = NumScript.add(gold, escrow)
	var net_assets_log: float = NumScript.sub(liquid, debt) if liquid >= debt else NumScript.ZERO
	var progress: float = 0.0
	if tier > 0 and toll_log != NumScript.ZERO and net_assets_log != NumScript.ZERO:
		progress = clampf(pow(10.0, net_assets_log - toll_log), 0.0, 1.0)
	return {
		"tier": tier,
		"gate_stage": tier * bal.band_stage_interval,
		"toll_log": toll_log,
		"net_assets_log": net_assets_log,
		"progress": progress,
		"saving": bool(state.call("is_saving_for_toll")),
		"waiting": waiting,
		"paid_tier": paid_tier
	}

## 当前玩家所处阶段：储蓄 / 等待缴费 / 护盾墙 / 数值墙 / 无
static func get_phase(state: RefCounted) -> String:
	var bal: BalanceScript = state.get("balance") as BalanceScript
	if bool(state.get("gate_boss_cleared")):
		return PHASE_WAITING
	if bool(state.call("is_saving_for_toll")):
		return PHASE_SAVING
	if int(state.get("boss_fail_streak")) >= bal.wall_signal_fail_streak:
		if BandRulesScript.get_shield_strength(int(state.get("current_stage")), bal) > 0.0:
			return PHASE_WALL_SHIELD
		return PHASE_WALL_POWER
	return PHASE_NONE

## 卡墙 / 储蓄提示文案（§7.2、§7.3）
static func get_hint_text(state: RefCounted) -> String:
	var status: Dictionary = get_status(state)
	match get_phase(state):
		PHASE_WAITING:
			return "第 %d 层门票未缴清，已储蓄 %s%%（托管金币不增加怪物血量）" % [
				int(status["gate_stage"]), str(snappedf(float(status["progress"]) * 100.0, 0.1))
			]
		PHASE_SAVING:
			return "门前储蓄中：门票 %s，净资产进度 %s%%（托管金币不增加怪物血量）" % [
				NumScript.format_num(float(status["toll_log"])), str(snappedf(float(status["progress"]) * 100.0, 0.1))
			]
		PHASE_WALL_SHIELD:
			var def: MechanicDefScript = BandRulesScript.get_shield_def()
			return def.wall_hint if def != null else "护盾卡墙"
		PHASE_WALL_POWER:
			return "数值墙 → 换 Build 或借钱"
	return ""