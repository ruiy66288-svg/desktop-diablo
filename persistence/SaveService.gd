class_name SaveService extends RefCounted

## 存档服务 (依据《00_开发执行总纲.md》§4.7 与《02_系统架构与数值_v6.md》§3.4、WP-17)
## - 带 version 字段的 JSON；先写 .tmp 再原子替换（rename）
## - 浮点数一律以 IEEE754 双精度 Base64 编码保存：JSON 无法表示 -INF（log 域的零），且文本小数会损失精度，影响确定性
## - 覆盖：四层数变量、钱包/信贷/宿债/托管、灵魂/印记/威能、装备 6 槽与 24 格背包、升级、过滤、保底计数器、
##         科技树与 Unix 时间戳研究队列、怪物战场状态、三条 SimRng 流状态
## - 图鉴/收藏属第二阶段，单独存档，本原型不做

const NumScript = preload("res://core/num/Num.gd")
const BalanceScript = preload("res://simulation/Balance.gd")
const SimStateScript = preload("res://simulation/SimState.gd")
const ItemInstanceScript = preload("res://simulation/loot/ItemInstance.gd")
const AffixDefScript = preload("res://simulation/affix/AffixDef.gd")
const SignatureAffixesScript = preload("res://simulation/affix/SignatureAffixes.gd")

const SAVE_VERSION: int = 1
const DEFAULT_SAVE_PATH: String = "user://save.json"
const TMP_SUFFIX: String = ".tmp"
const BAK_SUFFIX: String = ".bak"

const REQUIRED_KEYS: Array[String] = [
	"version", "stages", "wallet", "progress", "battle", "equipped", "inventory", "rng", "tech"
]

# ---------------------------------------------------------------- 浮点编码
static func enc_f(v: float) -> String:
	return Marshalls.raw_to_base64(PackedFloat64Array([v]).to_byte_array())

static func dec_f(s: Variant, fallback: float = 0.0) -> float:
	if typeof(s) != TYPE_STRING:
		return fallback
	var bytes: PackedByteArray = Marshalls.base64_to_raw(String(s))
	if bytes.size() != 8:
		return fallback
	return bytes.to_float64_array()[0]

# ---------------------------------------------------------------- 物品
static func _item_to_dict(item: ItemInstanceScript) -> Dictionary:
	var affix_ids: Array[String] = []
	for a: Variant in item.affixes:
		if a is AffixDefScript:
			affix_ids.append((a as AffixDefScript).id)
	return {
		"uid": item.uid,
		"name": item.name,
		"slot": int(item.slot),
		"rarity": int(item.rarity),
		"ilvl": item.ilvl,
		"flat_atk_log": enc_f(item.flat_atk_log),
		"additive_pct": enc_f(item.additive_pct),
		"unique_mult": enc_f(item.unique_mult),
		"bonus_affix_slots": item.bonus_affix_slots,
		"affix_ids": affix_ids
	}

static func _resolve_affix(affix_id: String) -> AffixDefScript:
	for def: AffixDefScript in SignatureAffixesScript.create_all():
		if def != null and def.id == affix_id:
			return def
	return null

static func _item_from_dict(d: Dictionary, bal: BalanceScript) -> ItemInstanceScript:
	var item: ItemInstanceScript = ItemInstanceScript.new(
		int(d.get("uid", 0)),
		String(d.get("name", "")),
		clampi(int(d.get("slot", 0)), 0, ItemInstanceScript.SLOT_KEYS.size() - 1) as ItemInstanceScript.Slot,
		clampi(int(d.get("rarity", 0)), 0, int(ItemInstanceScript.Rarity.PRIMAL)) as ItemInstanceScript.Rarity,
		int(d.get("ilvl", 1)),
		dec_f(d.get("flat_atk_log"), NumScript.ZERO),
		dec_f(d.get("additive_pct"), 0.0),
		dec_f(d.get("unique_mult"), 1.0),
		bal
	)
	item.bonus_affix_slots = int(d.get("bonus_affix_slots", 0))
	for id_var: Variant in (d.get("affix_ids", []) as Array):
		var def: AffixDefScript = _resolve_affix(String(id_var))
		if def != null:
			item.affixes.push_back(def)
	return item

# ---------------------------------------------------------------- 序列化
static func serialize(state: SimStateScript) -> Dictionary:
	var equipped_dict: Dictionary = {}
	for slot_key: String in SimStateScript.EQUIP_SLOTS:
		var eq: ItemInstanceScript = state.equipped.get(slot_key, null) as ItemInstanceScript
		equipped_dict[slot_key] = _item_to_dict(eq) if eq != null else null

	var inv_items: Array = []
	for i: int in range(state.inventory.get_count()):
		inv_items.push_back(_item_to_dict(state.inventory.get_item_at(i)))

	return {
		"version": SAVE_VERSION,
		"stages": {
			"all_time_best": state.all_time_best,
			"run_best": state.run_best,
			"current_stage": state.current_stage,
			"farm_stage": state.farm_stage
		},
		"wallet": {
			"gold": enc_f(state.gold),
			"debt_total": enc_f(state.debt_total),
			"legacy_debt_minutes": enc_f(state.legacy_debt_minutes),
			"toll_escrow": enc_f(state.toll_escrow),
			"credit_tier": state.credit.credit_tier,
			"active_loan": state.credit.active_loan,
			"loan_count": state.credit.loan_count,
			"borrowed_principal_log": enc_f(state.credit.borrowed_principal_log)
		},
		"progress": {
			"souls": enc_f(state.souls),
			"marks": state.marks,
			"vault_powers": state.vault_powers.duplicate(),
			"unlocked_vault_powers": state.unlocked_vault_powers.duplicate(),
			"paid_gate_tier": state.paid_gate_tier,
			"gate_boss_cleared": state.gate_boss_cleared,
			"enforce_toll_gates": state.enforce_toll_gates,
			"prestige_count": state.prestige_count,
			"tick_count": state.tick_count,
			"elapsed_seconds": enc_f(state.elapsed_seconds),
			"peak_soul_rate_log": enc_f(state.peak_soul_rate_log),
			"atk_level": state.upgrades.atk_level,
			"speed_level": state.upgrades.speed_level,
			"crit_level": state.upgrades.crit_level,
			"filter_threshold": state.filter.get_threshold(),
			"loot_roller": state.loot_roller.export_state()
		},
		"battle": {
			"mob_max_hp_log": enc_f(state.mob_max_hp_log),
			"mob_current_hp_log": enc_f(state.mob_current_hp_log),
			"is_boss": state.is_boss,
			"boss_timer": enc_f(state.boss_timer),
			"mobs_killed_in_stage": state.mobs_killed_in_stage,
			"mobs_killed_total": state.mobs_killed_total,
			"boss_fail_streak": state.boss_fail_streak,
			"farm_kills_since_retreat": state.farm_kills_since_retreat,
			"last_fail_margin_log": enc_f(state.last_fail_margin_log),
			"atk_progress": enc_f(state.atk_progress),
			"backlash_stacks": enc_f(state.backlash_stacks),
			"stun_remaining_sec": enc_f(state.stun_remaining_sec),
			"boss_clone_triggered": state.boss_clone_triggered,
			"boss_clones_remaining": state.boss_clones_remaining,
			"recent_income_per_sec_log": enc_f(state.recent_income_per_sec_log),
			"mob_shield_max_log": enc_f(state.mob_shield_max_log),
			"mob_shield_cur_log": enc_f(state.mob_shield_cur_log),
			"mob_shield_strip_cap_log": enc_f(state.mob_shield_strip_cap_log)
		},
		"equipped": equipped_dict,
		"inventory": inv_items,
		"rng": {
			"master_seed": state.rng.master_seed,
			"combat": state.rng.combat.state,
			"loot": state.rng.loot.state,
			"collection": state.rng.collection.state
		},
		"buffs": state.buffs.to_array(),
		"tech": {
			"researched": state.tech.researched.duplicate(),
			"debug_seconds_mode": state.tech.debug_seconds_mode,
			"queue": state.research_queue.to_array()
		}
	}

## 校验存档字典：版本与核心字段齐全；返回错误文本，空串表示通过
static func validate(data: Dictionary) -> String:
	for key: String in REQUIRED_KEYS:
		if not data.has(key):
			return "缺少核心字段: " + key
	if int(data.get("version", 0)) != SAVE_VERSION:
		return "不支持的存档版本: " + str(data.get("version"))
	var stages: Dictionary = data["stages"] as Dictionary
	for sk: String in ["all_time_best", "run_best", "current_stage", "farm_stage"]:
		if not stages.has(sk):
			return "缺少层数字段: " + sk
	return ""

## 反序列化：校验失败返回 null
static func deserialize(data: Dictionary, bal: BalanceScript = null) -> SimStateScript:
	if not validate(data).is_empty():
		return null
	var balance: BalanceScript = bal if bal != null else (BalanceScript.load_default() as BalanceScript)
	var rng_d: Dictionary = data["rng"] as Dictionary
	var state: SimStateScript = SimStateScript.new(int(rng_d.get("master_seed", 0)), balance)

	var stages: Dictionary = data["stages"] as Dictionary
	state.all_time_best = int(stages["all_time_best"])
	state.run_best = int(stages["run_best"])
	state.current_stage = int(stages["current_stage"])
	state.farm_stage = int(stages["farm_stage"])

	var w: Dictionary = data["wallet"] as Dictionary
	state.gold = dec_f(w.get("gold"), NumScript.ZERO)
	state.debt_total = dec_f(w.get("debt_total"), NumScript.ZERO)
	state.legacy_debt_minutes = dec_f(w.get("legacy_debt_minutes"), 0.0)
	state.toll_escrow = dec_f(w.get("toll_escrow"), NumScript.ZERO)
	state.credit.credit_tier = int(w.get("credit_tier", 0))
	state.credit.active_loan = bool(w.get("active_loan", false))
	state.credit.loan_count = int(w.get("loan_count", 1 if state.credit.active_loan else 0))
	state.credit.borrowed_principal_log = dec_f(w.get("borrowed_principal_log"), NumScript.ZERO)

	var p: Dictionary = data["progress"] as Dictionary
	state.souls = dec_f(p.get("souls"), NumScript.ZERO)
	state.marks = int(p.get("marks", 0))
	state.vault_powers.clear()
	for v: Variant in (p.get("vault_powers", []) as Array):
		state.vault_powers.push_back(String(v))
	state.unlocked_vault_powers.clear()
	for uv: Variant in (p.get("unlocked_vault_powers", []) as Array):
		state.unlocked_vault_powers.push_back(String(uv))
	state.paid_gate_tier = int(p.get("paid_gate_tier", 0))
	state.gate_boss_cleared = bool(p.get("gate_boss_cleared", false))
	state.enforce_toll_gates = bool(p.get("enforce_toll_gates", true))
	state.prestige_count = int(p.get("prestige_count", 0))
	state.tick_count = int(p.get("tick_count", 0))
	state.elapsed_seconds = dec_f(p.get("elapsed_seconds"), 0.0)
	state.peak_soul_rate_log = dec_f(p.get("peak_soul_rate_log"), NumScript.ZERO)
	state.upgrades.atk_level = int(p.get("atk_level", 0))
	state.upgrades.speed_level = int(p.get("speed_level", 0))
	state.upgrades.crit_level = int(p.get("crit_level", 0))
	state.filter.set_threshold(int(p.get("filter_threshold", int(ItemInstanceScript.Rarity.UNIQUE))))
	state.loot_roller.import_state(p.get("loot_roller", {}) as Dictionary)

	var b: Dictionary = data["battle"] as Dictionary
	state.mob_max_hp_log = dec_f(b.get("mob_max_hp_log"), 0.0)
	state.mob_current_hp_log = dec_f(b.get("mob_current_hp_log"), NumScript.ZERO)
	state.is_boss = bool(b.get("is_boss", false))
	state.boss_timer = dec_f(b.get("boss_timer"), 0.0)
	state.mobs_killed_in_stage = int(b.get("mobs_killed_in_stage", 0))
	state.mobs_killed_total = int(b.get("mobs_killed_total", 0))
	state.boss_fail_streak = int(b.get("boss_fail_streak", 0))
	state.farm_kills_since_retreat = int(b.get("farm_kills_since_retreat", 0))
	state.last_fail_margin_log = dec_f(b.get("last_fail_margin_log"), NumScript.ZERO)
	state.atk_progress = dec_f(b.get("atk_progress"), 0.0)
	state.backlash_stacks = dec_f(b.get("backlash_stacks"), 0.0)
	state.stun_remaining_sec = dec_f(b.get("stun_remaining_sec"), 0.0)
	state.boss_clone_triggered = bool(b.get("boss_clone_triggered", false))
	state.boss_clones_remaining = int(b.get("boss_clones_remaining", 0))
	state.recent_income_per_sec_log = dec_f(b.get("recent_income_per_sec_log"), NumScript.ZERO)
	state.mob_shield_max_log = dec_f(b.get("mob_shield_max_log"), NumScript.ZERO)
	state.mob_shield_cur_log = dec_f(b.get("mob_shield_cur_log"), NumScript.ZERO)
	state.mob_shield_strip_cap_log = dec_f(b.get("mob_shield_strip_cap_log"), NumScript.ZERO)

	state.inventory.clear()
	for it_var: Variant in (data["inventory"] as Array):
		state.inventory.items.push_back(_item_from_dict(it_var as Dictionary, balance))

	var tech_d: Dictionary = data["tech"] as Dictionary
	state.tech.researched.clear()
	for id_var: Variant in (tech_d.get("researched", []) as Array):
		state.tech.researched.push_back(String(id_var))
	state.tech.debug_seconds_mode = bool(tech_d.get("debug_seconds_mode", false))
	state.research_queue.load_from_array(tech_d.get("queue", []) as Array)

	state.buffs.load_from_array(data.get("buffs", []) as Array)
	state.rng.combat.state = int(rng_d.get("combat", state.rng.combat.state))
	state.rng.loot.state = int(rng_d.get("loot", state.rng.loot.state))
	state.rng.collection.state = int(rng_d.get("collection", state.rng.collection.state))

	# 6 槽装备：逐件穿戴（含词条监听器重建），最后统一重算面板
	var eq_d: Dictionary = data["equipped"] as Dictionary
	for slot_key: String in SimStateScript.EQUIP_SLOTS:
		var raw: Variant = eq_d.get(slot_key, null)
		if raw is Dictionary:
			state.equip_item(_item_from_dict(raw as Dictionary, balance))
	state.equip_slots.recalculate_and_apply(state)   # 重建 6 槽 + 威能槽监听器、被动汇总并重算面板
	return state

# ---------------------------------------------------------------- 文件读写
static func to_json_text(state: SimStateScript) -> String:
	return JSON.stringify(serialize(state), "\t")

static func from_json_text(text: String, bal: BalanceScript = null) -> SimStateScript:
	var parser: JSON = JSON.new()
	if parser.parse(text) != OK or typeof(parser.data) != TYPE_DICTIONARY:
		return null
	return deserialize(parser.data as Dictionary, bal)

## 原子保存：先写 .tmp，再替换目标（Windows 无法直接覆盖，先把旧档改名为 .bak，成功后删除）
static func save_to_file(state: SimStateScript, path: String = DEFAULT_SAVE_PATH) -> Error:
	var tmp_path: String = path + TMP_SUFFIX
	var bak_path: String = path + BAK_SUFFIX
	var f: FileAccess = FileAccess.open(tmp_path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(to_json_text(state))
	f.flush()
	f.close()

	var had_old: bool = FileAccess.file_exists(path)
	if had_old:
		if FileAccess.file_exists(bak_path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(bak_path))
		var err_bak: Error = DirAccess.rename_absolute(ProjectSettings.globalize_path(path), ProjectSettings.globalize_path(bak_path))
		if err_bak != OK:
			return err_bak
	var err_rename: Error = DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp_path), ProjectSettings.globalize_path(path))
	if err_rename != OK:
		if had_old:
			DirAccess.rename_absolute(ProjectSettings.globalize_path(bak_path), ProjectSettings.globalize_path(path))
		return err_rename
	if had_old:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(bak_path))
	return OK

## 读取存档；主档损坏时回退 .bak；均失败返回 null
static func load_from_file(path: String = DEFAULT_SAVE_PATH, bal: BalanceScript = null) -> SimStateScript:
	for candidate: String in [path, path + BAK_SUFFIX]:
		if not FileAccess.file_exists(candidate):
			continue
		var f: FileAccess = FileAccess.open(candidate, FileAccess.READ)
		if f == null:
			continue
		var state: SimStateScript = from_json_text(f.get_as_text(), bal)
		f.close()
		if state != null:
			return state
	return null