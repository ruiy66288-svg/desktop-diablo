class_name CollectionRoller extends RefCounted

## 稀有收藏判定与坏运气保护 (依据《02_系统架构与数值_v6.md》§8.1 & §8.3)
## 严格走 SimRng.loot 流或 SimRng.collection 流，零全局随机
## 1-99 层推层期间绝不额外消耗随机数，确保 10,000 ticks 哈希完全一致

const BalanceScript = preload("res://simulation/Balance.gd")
const ItemInstanceScript = preload("res://simulation/loot/ItemInstance.gd")
const CodexScript = preload("res://persistence/Codex.gd")

var mythic_pity_mult: float = 1.0
var primal_pity_mult: float = 1.0
var rune_pity_mult: float = 1.0
var rune_sim_seconds_accumulator: float = 0.0

## 暗金掉落时额外判定神话变体 (1/2000，每次失败 ×1.02)
func check_mythic_roll(item: ItemInstanceScript, rng_stream: RefCounted, bal: BalanceScript) -> bool:
	if int(item.rarity) < int(ItemInstanceScript.Rarity.UNIQUE):
		return false
	var base_chance: float = bal.mythic_base_chance if bal != null else 0.0005
	var bad_luck: float = bal.bad_luck_mult if bal != null else 1.02
	var p: float = minf(1.0, base_chance * mythic_pity_mult)
	var roll: float = rng_stream.call("randf_val")
	if roll < p:
		item.is_mythic = true
		item.name = "神话·" + item.name
		item.unique_mult = maxf(1.0, item.unique_mult * 1.5)
		mythic_pity_mult = 1.0
		return true
	mythic_pity_mult *= bad_luck
	return false

## 太古掉落时判定是否解锁太古独特外观 (1/50，每次失败 ×1.02)
func check_primal_transmog_roll(item: ItemInstanceScript, rng_stream: RefCounted, bal: BalanceScript, codex: CodexScript = null) -> String:
	if int(item.rarity) < int(ItemInstanceScript.Rarity.PRIMAL):
		return ""
	var base_chance: float = bal.primal_transmog_chance if bal != null else 0.02
	var bad_luck: float = bal.bad_luck_mult if bal != null else 1.02
	var p: float = minf(1.0, base_chance * primal_pity_mult)
	var roll: float = rng_stream.call("randf_val")
	if roll < p:
		var slot_key: String = ItemInstanceScript.get_slot_key(item.slot)
		var cos_id: String = "transmog_primal_" + slot_key
		primal_pity_mult = 1.0
		if codex != null:
			codex.unlock_cosmetic(cos_id)
		return cos_id
	primal_pity_mult *= bad_luck
	return ""

## 按模拟时间累计满 60.0 秒判定 1 次召唤符文 (~1-2 天 1 枚)
## 铁律：仅在 run_best >= 100 时判定，确保 1-99 层零随机消耗与 WP-03 哈希不变
func check_summon_rune_tick(
	dt: float,
	run_best: int,
	rng_stream: RefCounted,
	bal: BalanceScript,
	codex: CodexScript = null
) -> bool:
	if run_best < bal.abyss_min_stage:
		return false
	rune_sim_seconds_accumulator += dt
	if rune_sim_seconds_accumulator < 60.0:
		return false
	rune_sim_seconds_accumulator -= 60.0

	var base_chance: float = bal.summon_rune_base_chance if bal != null else 0.00035
	var bad_luck: float = bal.bad_luck_mult if bal != null else 1.02
	var p: float = minf(1.0, base_chance * rune_pity_mult)
	var roll: float = rng_stream.call("randf_val")
	if roll < p:
		rune_pity_mult = 1.0
		if codex != null:
			codex.add_summon_runes(1)
		return true
	rune_pity_mult *= bad_luck
	return false

## 离线时按离线分钟数补判召唤符文（零损失）
func roll_offline_minutes(minutes: int, rng_stream: RefCounted, bal: BalanceScript, codex: CodexScript = null) -> int:
	var runes_gained: int = 0
	var base_chance: float = bal.summon_rune_base_chance if bal != null else 0.00035
	var bad_luck: float = bal.bad_luck_mult if bal != null else 1.02
	for _m: int in range(maxi(0, minutes)):
		var p: float = minf(1.0, base_chance * rune_pity_mult)
		var roll: float = rng_stream.call("randf_val")
		if roll < p:
			runes_gained += 1
			rune_pity_mult = 1.0
			if codex != null:
				codex.add_summon_runes(1)
		else:
			rune_pity_mult *= bad_luck
	return runes_gained

func serialize() -> Dictionary:
	return {
		"mythic_pity_mult": mythic_pity_mult,
		"primal_pity_mult": primal_pity_mult,
		"rune_pity_mult": rune_pity_mult,
		"rune_sim_seconds_accumulator": rune_sim_seconds_accumulator
	}

func deserialize(data: Dictionary) -> void:
	mythic_pity_mult = float(data.get("mythic_pity_mult", 1.0))
	primal_pity_mult = float(data.get("primal_pity_mult", 1.0))
	rune_pity_mult = float(data.get("rune_pity_mult", 1.0))
	rune_sim_seconds_accumulator = float(data.get("rune_sim_seconds_accumulator", 0.0))

func clone() -> CollectionRoller:
	var copy: CollectionRoller = (get_script() as GDScript).new() as CollectionRoller
	copy.mythic_pity_mult = mythic_pity_mult
	copy.primal_pity_mult = primal_pity_mult
	copy.rune_pity_mult = rune_pity_mult
	copy.rune_sim_seconds_accumulator = rune_sim_seconds_accumulator
	return copy
