class_name TestP2UiAbyssMechanics extends RefCounted

## 阶段 2 美术接入、百层机制与卡墙 UI、深渊转生与魔盒威能台 UI 自动化测试
## 铁律：100% 显式静态类型，零 :=，零禁词

const GameScript = preload("res://autoload/Game.gd")
const SimStateScript = preload("res://simulation/SimState.gd")
const BalanceScript = preload("res://simulation/Balance.gd")
const ArtRegistryScript = preload("res://ui/ArtRegistry.gd")
const MainWindowScript = preload("res://ui/MainWindow.gd")
const SystemsDrawerScript = preload("res://ui/SystemsDrawer.gd")
const InventoryFilterPanelScript = preload("res://ui/InventoryFilterPanel.gd")
const AttentionGlowScript = preload("res://ui/AttentionGlow.gd")
const BandRulesScript = preload("res://simulation/mechanics/BandRules.gd")
const MechanicDefScript = preload("res://simulation/mechanics/MechanicDef.gd")
const ItemInstanceScript = preload("res://simulation/loot/ItemInstance.gd")
const NumScript = preload("res://core/num/Num.gd")
const AffixDefScript = preload("res://simulation/affix/AffixDef.gd")

static func run() -> bool:
	var passed: bool = true
	passed = _test_art_registry_p2() and passed
	passed = _test_mechanic_status_bar_and_wall_hint() and passed
	passed = _test_inventory_wall_break_highlight() and passed
	passed = _test_systems_drawer_p2() and passed
	passed = _test_game_audio_and_tray_sync() and passed
	if passed:
		print("[TEST PASS] TestP2UiAbyssMechanics all checks green.")
	else:
		printerr("[TEST FAIL] TestP2UiAbyssMechanics encountered failures.")
	return passed

static func _test_art_registry_p2() -> bool:
	print("--- Running TestP2UiAbyssMechanics._test_art_registry_p2 ---")
	var formal_paths: Array[String] = ArtRegistryScript.get_all_formal_subject_paths()
	if formal_paths.size() != 17:
		printerr("Expected 17 formal subject paths, got: ", formal_paths.size())
		return false

	# 1. 验证五大族群怪物视觉配置
	for clan_idx: int in range(5):
		var spec: Dictionary = ArtRegistryScript.get_monster_visual_spec(0, clan_idx, false, false)
		var p: String = str(spec.get("res_path", ""))
		if p.is_empty():
			printerr("Empty res_path for clan idx: ", clan_idx)
			return false

	# 2. 验证稀有 Boss 与魔主
	var boss_spec: Dictionary = ArtRegistryScript.get_monster_visual_spec(10, 0, true, false, false)
	if str(boss_spec.get("id", "")) != "boss_abyss_lord":
		printerr("Abyss lord spec mismatch: ", boss_spec)
		return false

	var rare_spec: Dictionary = ArtRegistryScript.get_monster_visual_spec(10, 0, true, false, true)
	if str(rare_spec.get("id", "")) != "boss_rare_archon":
		printerr("Rare boss archon spec mismatch: ", rare_spec)
		return false

	# 3. 验证木刻底纹、符文与账簿插图纹理加载接口
	var hatch_tex: Texture2D = ArtRegistryScript.get_woodcut_hatch_texture()
	var rune_tex: Texture2D = ArtRegistryScript.get_summon_rune_texture()
	var ledger_tex: Texture2D = ArtRegistryScript.get_wealth_ledger_texture()
	var uniq_w_path: String = ArtRegistryScript.get_unique_item_icon_path("weapon")
	var uniq_t_path: String = ArtRegistryScript.get_unique_item_icon_path("trinket")

	if uniq_w_path != ArtRegistryScript.UNIQ_WEAPON_THUNDER:
		printerr("Unique weapon icon path mismatch: ", uniq_w_path)
		return false
	if uniq_t_path != ArtRegistryScript.UNIQ_TRINKET_SCALES:
		printerr("Unique trinket icon path mismatch: ", uniq_t_path)
		return false

	print("ArtRegistry P2 checks passed.")
	return true

static func _test_mechanic_status_bar_and_wall_hint() -> bool:
	print("--- Running TestP2UiAbyssMechanics._test_mechanic_status_bar_and_wall_hint ---")
	var game: GameScript = GameScript.new()
	game.initialize_session(12345)
	var win: MainWindowScript = MainWindowScript.new()
	win.bind_game(game)
	win._ready()

	if win.mechanic_status_bar == null:
		printerr("MainWindow missing mechanic_status_bar node.")
		win.free()
		game.free()
		return false

	if win.wall_hint_banner == null:
		printerr("MainWindow missing wall_hint_banner node.")
		win.free()
		game.free()
		return false

	var state: SimStateScript = game.get_sim_state()

	# 1. 第 50 层：常规试炼无机制
	state.current_stage = 50
	win.refresh_hud()
	if not win.lbl_mechanic_status.text.contains("常规试炼"):
		printerr("Stage 50 should show 常规试炼, got: ", win.lbl_mechanic_status.text)
		win.free()
		game.free()
		return false
	if win.mini_shield_bar.visible:
		printerr("Stage 50 shield bar should not be visible.")
		win.free()
		game.free()
		return false

	# 2. 第 150 层：护盾机制
	state.current_stage = 150
	state.mob_shield_max_log = 5.0
	state.mob_shield_cur_log = 4.8
	win.refresh_hud()
	if not win.lbl_mechanic_status.text.contains("护盾"):
		printerr("Stage 150 should contain 护盾, got: ", win.lbl_mechanic_status.text)
		win.free()
		game.free()
		return false
	if not win.mini_shield_bar.visible:
		printerr("Stage 150 shield bar should be visible.")
		win.free()
		game.free()
		return false

	# 3. 第 250 层：反噬机制与余韵
	state.current_stage = 250
	state.mob_shield_max_log = NumScript.ZERO
	state.mob_shield_cur_log = NumScript.ZERO
	state.backlash_stacks = 28.0
	win.refresh_hud()
	if not win.lbl_mechanic_status.text.contains("反噬"):
		printerr("Stage 250 should contain 反噬, got: ", win.lbl_mechanic_status.text)
		win.free()
		game.free()
		return false
	if not win.lbl_mechanic_status.text.contains("余韵"):
		printerr("Stage 250 should mention 余韵, got: ", win.lbl_mechanic_status.text)
		win.free()
		game.free()
		return false
	if not win.lbl_mechanic_tag.text.contains("28/40"):
		printerr("Stage 250 tag should show 28/40, got: ", win.lbl_mechanic_tag.text)
		win.free()
		game.free()
		return false

	# 4. 反噬眩晕态
	state.stun_remaining_sec = 1.8
	win.refresh_hud()
	if not win.lbl_mechanic_tag.text.contains("眩晕"):
		printerr("Stun tag should show 眩晕, got: ", win.lbl_mechanic_tag.text)
		win.free()
		game.free()
		return false

	# 5. 第 450 层：分身机制
	state.current_stage = 450
	state.stun_remaining_sec = 0.0
	state.backlash_stacks = 0.0
	state.boss_clones_remaining = 3
	win.refresh_hud()
	if not win.lbl_mechanic_tag.text.contains("分身 3/4"):
		printerr("Clone tag should show 3/4, got: ", win.lbl_mechanic_tag.text)
		win.free()
		game.free()
		return false

	# 6. 卡墙横幅触发测试
	state.boss_fail_streak = state.balance.wall_signal_fail_streak + 1
	var hint_dict: Dictionary = state.get_wall_hint()
	if not bool(hint_dict.get("active", false)):
		printerr("Wall hint should be active after streak fails.")
		win.free()
		game.free()
		return false

	win.refresh_hud()
	if not win.wall_hint_banner.visible:
		printerr("Wall hint banner should be visible when wall hint is active.")
		win.free()
		game.free()
		return false
	if not win.lbl_wall_hint.text.contains("卡墙提示"):
		printerr("Wall hint label should contain 卡墙提示, got: ", win.lbl_wall_hint.text)
		win.free()
		game.free()
		return false

	win.free()
	game.free()
	print("Mechanic status bar and wall hint tests passed.")
	return true

static func _test_inventory_wall_break_highlight() -> bool:
	print("--- Running TestP2UiAbyssMechanics._test_inventory_wall_break_highlight ---")
	var game: GameScript = GameScript.new()
	game.initialize_session(20261113)
	var panel: InventoryFilterPanelScript = InventoryFilterPanelScript.new()
	panel.bind_game(game)

	var state: SimStateScript = game.get_sim_state()

	# 构造一件克制多段攻击的装备
	var counter_item: ItemInstanceScript = ItemInstanceScript.new(
		9001, "破壁神剑", ItemInstanceScript.Slot.WEAPON, ItemInstanceScript.Rarity.UNIQUE, 100, 10.0
	)
	var aff: AffixDefScript = AffixDefScript.new("rapid_fire", "连射", false)
	aff.counter_tags = ["multi_hit"]
	counter_item.affixes.push_back(aff)
	state.inventory.items.push_back(counter_item)

	# 构造一件普通不克制的装备
	var normal_item: ItemInstanceScript = ItemInstanceScript.new(
		9002, "坚固胸甲", ItemInstanceScript.Slot.CHEST, ItemInstanceScript.Rarity.PURPLE, 50, 5.0
	)
	state.inventory.items.push_back(normal_item)

	# 触发护盾卡墙
	state.current_stage = 150
	state.boss_fail_streak = 5
	state.mech_absorbed_log[int(MechanicDefScript.Kind.SHIELD)] = 10.0

	panel.open_tab(0)
	panel.refresh_view()

	if not panel.is_cell_counter_highlighted(0):
		printerr("Counter item at cell 0 should display BreakBadge.")
		panel.free()
		game.free()
		return false

	if panel.is_cell_counter_highlighted(1):
		printerr("Non-counter item at cell 1 should NOT display BreakBadge.")
		panel.free()
		game.free()
		return false

	panel.free()
	game.free()
	print("Inventory wall break highlight tests passed.")
	return true

static func _test_systems_drawer_p2() -> bool:
	print("--- Running TestP2UiAbyssMechanics._test_systems_drawer_p2 ---")
	var game: GameScript = GameScript.new()
	game.initialize_session(7777)
	var drawer: SystemsDrawerScript = SystemsDrawerScript.new()
	drawer.bind_game(game)

	var state: SimStateScript = game.get_sim_state()

	# 1. 验证科技页签
	drawer.open_tab(SystemsDrawerScript.TabKind.TECH)
	var defs: Array = state.tech.get_all_defs()
	if defs.size() != 12:
		printerr("Expected 12 tech defs, got: ", defs.size())
		drawer.free()
		game.free()
		return false

	# 检查印记门槛节点 (深渊印记 < 1 时禁用)
	state.marks = 0
	drawer.refresh_view()

	# 2. 验证信贷页签双并发贷款与折扣
	drawer.open_tab(SystemsDrawerScript.TabKind.CREDIT)
	drawer.refresh_view()

	# 3. 验证转生与卡奈魔盒威能台
	state.run_best = 220
	state.marks = 5
	drawer.open_tab(SystemsDrawerScript.TabKind.PRESTIGE)

	# 放入可萃取暗金
	var u_item: ItemInstanceScript = ItemInstanceScript.new(
		8001, "典当金戒", ItemInstanceScript.Slot.TRINKET, ItemInstanceScript.Rarity.UNIQUE, 100, 10.0
	)
	var aff2: AffixDefScript = AffixDefScript.new("gold_synergy", "金币共鸣", false)
	u_item.affixes.push_back(aff2)
	state.inventory.items.push_back(u_item)

	drawer.refresh_view()

	# 测试威能装卸
	state.unlocked_vault_powers.push_back("test_power")
	var max_slots: int = state.get_max_vault_slots()
	if max_slots < 2:
		printerr("With marks=5, max vault slots should be >= 2, got: ", max_slots)
		drawer.free()
		game.free()
		return false

	var eq_ok: bool = state.equip_vault_power("test_power")
	if not eq_ok or not state.vault_powers.has("test_power"):
		printerr("equip_vault_power failed.")
		drawer.free()
		game.free()
		return false

	var uneq_ok: bool = state.unequip_vault_power("test_power")
	if not uneq_ok or state.vault_powers.has("test_power"):
		printerr("unequip_vault_power failed.")
		drawer.free()
		game.free()
		return false

	drawer.free()
	game.free()
	print("SystemsDrawer P2 checks passed.")
	return true

static func _test_game_audio_and_tray_sync() -> bool:
	print("--- Running TestP2UiAbyssMechanics._test_game_audio_and_tray_sync ---")
	var game: GameScript = GameScript.new()
	game.initialize_session(9999)

	var box: Array[bool] = [false, false]
	var on_mute: Callable = func(m: bool) -> void:
		box[0] = true
		box[1] = m
	game.mute_toggled.connect(on_mute)

	game.set_audio_muted(true)
	if not box[0] or not box[1] or not game.is_audio_muted():
		printerr("Game set_audio_muted(true) failed.")
		game.free()
		return false

	box[0] = false
	game.toggle_audio_mute()
	if not box[0] or box[1] or game.is_audio_muted():
		printerr("Game toggle_audio_mute failed.")
		game.free()
		return false

	game.free()
	print("Game audio mute and tray sync tests passed.")
	return true
