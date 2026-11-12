class_name TriggerDef extends Resource

## 词条触发器定义 (依据《02_系统架构与数值_v6.md》§2.3–§2.4 与《00_开发执行总纲.md》§4.3)
## 严禁使用全局 randf()/randi()；概率触发强制走 SimRng.combat 独立确定性流

const SimEventScript = preload("res://simulation/events/SimEvent.gd")
const SimRngScript = preload("res://core/rng/SimRng.gd")

enum Mode {
	ALWAYS,
	COUNTER,
	CHANCE,
	TIMER
}

@export var event_type: SimEventScript.T = SimEventScript.T.HIT
@export var mode: Mode = Mode.ALWAYS
@export var threshold: int = 1
@export var chance: float = 1.0
@export var icd_ticks: int = 0

## 消耗事件并计算触发次数，保证计数器余数保留不丢数 (§2.3)
func consume(ev: SimEventScript, runtime: Dictionary, current_tick: int, rng: RefCounted = null) -> int:
	if ev.type != event_type:
		return 0

	var last_tick: int = int(runtime.get("last_fired_tick", -999999))
	if icd_ticks > 0 and (current_tick - last_tick) < icd_ticks:
		return 0

	var fires: int = 0
	var ev_count: int = maxi(1, ev.count)

	match mode:
		Mode.ALWAYS:
			fires = ev_count
		Mode.COUNTER:
			var acc: int = int(runtime.get("acc", 0)) + ev_count
			var thresh: int = maxi(1, threshold)
			fires = int(acc / thresh)
			runtime["acc"] = acc % thresh
		Mode.CHANCE:
			if rng is SimRngScript:
				var combat_rng: SimRngScript.RngStream = (rng as SimRngScript).combat
				fires = combat_rng.sample_binomial(ev_count, chance)
			elif rng is SimRngScript.RngStream:
				fires = (rng as SimRngScript.RngStream).sample_binomial(ev_count, chance)
			else:
				fires = ev_count if chance >= 1.0 else 0
		Mode.TIMER:
			fires = 1

	if fires > 0 and icd_ticks > 0:
		runtime["last_fired_tick"] = current_tick

	return fires
