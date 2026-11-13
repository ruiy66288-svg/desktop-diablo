class_name Codex extends RefCounted

## 永久独立图鉴系统 (依据《02_系统架构与数值_v6.md》§8.3 & Q34)
## 独立存储于 user://codex.json，灵魂转生与深渊转生永不清空
## 维护 monsters, uniques, sets, runes_cosmetics 四大类别与召唤符文持久化

const BalanceScript = preload("res://simulation/Balance.gd")

const DEFAULT_CODEX_PATH: String = "user://codex.json"
const TMP_SUFFIX: String = ".tmp"
const BAK_SUFFIX: String = ".bak"

const FULL_MONSTERS: Array[String] = [
	"mon_beast", "mon_undead", "mon_demon", "mon_idol_scales", "mon_cult_pawnbroker",
	"boss_abyss_lord", "boss_rare_archon"
]
const FULL_UNIQUES: Array[String] = [
	"chain_lightning", "drop_explosion", "killing_frenzy",
	"executioner_hammer", "gold_storm", "meteor_shower",
	"doomsday_fountain", "crit_afterglow", "unique_rain",
	"multi_strike", "deadly_precision", "usurer_ward"
]
const FULL_SETS: Array[String] = [
	"set_thunder_debt", "set_greed_covenant", "set_abyss_execution"
]

var save_path: String = DEFAULT_CODEX_PATH
var monsters: Dictionary = {}
var uniques: Dictionary = {}
var sets: Dictionary = {}
var summon_runes: int = 0
var cosmetics: Array[String] = []

func _init(custom_path: String = DEFAULT_CODEX_PATH) -> void:
	save_path = custom_path

func get_unlocked_count() -> int:
	return monsters.size() + uniques.size() + sets.size() + cosmetics.size()

func get_gold_bonus_pct(bal: BalanceScript = null) -> float:
	var step: float = bal.codex_gold_bonus_per_entry if bal != null else 0.005
	return float(get_unlocked_count()) * step

func unlock_monster(id: String) -> bool:
	if monsters.has(id):
		return false
	monsters[id] = true
	_check_page_rewards()
	return true

func unlock_unique(id: String, is_mythic: bool = false) -> bool:
	var key: String = ("mythic_" + id) if is_mythic else id
	if uniques.has(key):
		return false
	uniques[key] = true
	_check_page_rewards()
	return true

func unlock_set(id: String) -> bool:
	if sets.has(id):
		return false
	sets[id] = true
	_check_page_rewards()
	return true

func add_summon_runes(count: int = 1) -> void:
	summon_runes += maxi(0, count)

func consume_summon_rune() -> bool:
	if summon_runes <= 0:
		return false
	summon_runes -= 1
	return true

func unlock_cosmetic(cosmetic_id: String) -> bool:
	if cosmetics.has(cosmetic_id):
		return false
	cosmetics.push_back(cosmetic_id)
	return true

func is_page_complete(page_name: String) -> bool:
	match page_name:
		"monsters":
			for m: String in FULL_MONSTERS:
				if not monsters.has(m):
					return false
			return true
		"uniques":
			for u: String in FULL_UNIQUES:
				if not uniques.has(u):
					return false
			return true
		"sets":
			for s: String in FULL_SETS:
				if not sets.has(s):
					return false
			return true
		_:
			return false

func _check_page_rewards() -> void:
	if is_page_complete("monsters"):
		unlock_cosmetic("theme_gilded_archon")
	if is_page_complete("uniques"):
		unlock_cosmetic("beam_abyss_crimson")
	if is_page_complete("sets"):
		unlock_cosmetic("skin_kill_starlight")

func serialize() -> Dictionary:
	return {
		"version": 1,
		"monsters": monsters.duplicate(),
		"uniques": uniques.duplicate(),
		"sets": sets.duplicate(),
		"summon_runes": summon_runes,
		"cosmetics": cosmetics.duplicate()
	}

func deserialize(data: Dictionary) -> void:
	monsters = (data.get("monsters", {}) as Dictionary).duplicate()
	uniques = (data.get("uniques", {}) as Dictionary).duplicate()
	sets = (data.get("sets", {}) as Dictionary).duplicate()
	summon_runes = int(data.get("summon_runes", 0))
	cosmetics.clear()
	for c: Variant in (data.get("cosmetics", []) as Array):
		cosmetics.push_back(String(c))

func clone() -> Codex:
	var copy: Codex = (get_script() as GDScript).new(save_path) as Codex
	copy.deserialize(serialize())
	return copy

func save_to_file(path: String = "") -> Error:
	var target_path: String = path if not path.is_empty() else save_path
	var tmp_path: String = target_path + TMP_SUFFIX
	var bak_path: String = target_path + BAK_SUFFIX
	var f: FileAccess = FileAccess.open(tmp_path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(serialize(), "\t"))
	f.flush()
	f.close()

	var had_old: bool = FileAccess.file_exists(target_path)
	if had_old:
		if FileAccess.file_exists(bak_path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(bak_path))
		var err_bak: Error = DirAccess.rename_absolute(ProjectSettings.globalize_path(target_path), ProjectSettings.globalize_path(bak_path))
		if err_bak != OK:
			return err_bak
	var err_rename: Error = DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp_path), ProjectSettings.globalize_path(target_path))
	if err_rename != OK:
		if had_old:
			DirAccess.rename_absolute(ProjectSettings.globalize_path(bak_path), ProjectSettings.globalize_path(target_path))
		return err_rename
	if had_old:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(bak_path))
	return OK

func load_from_file(path: String = "") -> bool:
	var target_path: String = path if not path.is_empty() else save_path
	for candidate: String in [target_path, target_path + BAK_SUFFIX]:
		if not FileAccess.file_exists(candidate):
			continue
		var f: FileAccess = FileAccess.open(candidate, FileAccess.READ)
		if f == null:
			continue
		var text: String = f.get_as_text()
		f.close()
		var parser: JSON = JSON.new()
		if parser.parse(text) == OK and typeof(parser.data) == TYPE_DICTIONARY:
			deserialize(parser.data as Dictionary)
			return true
	return false
