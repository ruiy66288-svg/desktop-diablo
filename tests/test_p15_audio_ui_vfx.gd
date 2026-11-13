extends RefCounted

## [WP-P15-FEEL] 阶段 1.5 体感补完测试
## 覆盖: 程序化 PCM 合成(13 音效 确定性/非静音/16-bit) + 6 声道混音池(保留 request_play_sound 签名) +
##       行囊/过滤/属性抽屉(24 格/穿戴/熔炼/阈值 Command 闭环) + L5 边缘光带(去重/优先级/过期/太古脉冲) +
##       新特效(护盾碎裂/熔炼溶解/金币吸附 64 上限/陨石/巨锤/金币风暴/终焉喷泉)预算合规 + V10 中心 40% 遮挡 <= 30%

const SfxBankScript = preload("res://presentation/audio/SfxBank.gd")
const SfxMixerScript = preload("res://presentation/audio/SfxMixer.gd")
const VfxBudgetScript = preload("res://presentation/VfxBudget.gd")
const VfxManagerScript = preload("res://presentation/vfx/VfxManager.gd")
const AttentionGlowScript = preload("res://ui/AttentionGlow.gd")
const InventoryFilterPanelScript = preload("res://ui/InventoryFilterPanel.gd")
const MainWindowScript = preload("res://ui/MainWindow.gd")
const GameScript = preload("res://autoload/Game.gd")
const SimStateScript = preload("res://simulation/SimState.gd")
const ItemInstanceScript = preload("res://simulation/loot/ItemInstance.gd")
const ThemePaletteScript = preload("res://ui/ThemePalette.gd")

static func run() -> bool:
	var ok: bool = true
	ok = _test_sfx_bank_synthesis() and ok
	ok = _test_sfx_mixer_pool_and_budget() and ok
	ok = _test_attention_glow_priority_dedup() and ok
	ok = _test_inventory_filter_stats_panel() and ok
	ok = _test_new_vfx_and_v10_budget() and ok
	ok = _test_serif_font_fallback() and ok
	return ok

static func _fail(msg: String) -> bool:
	push_error("[test_p15] " + msg)
	return false

static func _test_sfx_bank_synthesis() -> bool:
	SfxBankScript.clear_cache()
	var ids: Array[String] = SfxBankScript.get_all_sound_ids()
	if ids.size() != 13:
		return _fail("expected 13 sound ids, got %d" % ids.size())
	for sid: String in ids:
		var samples: PackedFloat32Array = SfxBankScript.render_samples(sid)
		if samples.size() < 1000:
			return _fail("sound %s too short: %d samples" % [sid, samples.size()])
		var peak: float = 0.0
		var sum_sq: float = 0.0
		for v: float in samples:
			peak = maxf(peak, absf(v))
			sum_sq += v * v
		var rms: float = sqrt(sum_sq / float(samples.size()))
		if peak > 1.0001 or peak < 0.5:
			return _fail("sound %s bad peak %.3f" % [sid, peak])
		if rms < 0.02:
			return _fail("sound %s is near-silent (rms %.4f)" % [sid, rms])
		var dur: float = SfxBankScript.get_duration_sec(sid)
		if dur > SfxBankScript.MAX_DURATION_SEC + 0.01:
			return _fail("sound %s too long %.2fs" % [sid, dur])
		var stream: AudioStreamWAV = SfxBankScript.get_stream(sid)
		if stream == null or stream.format != AudioStreamWAV.FORMAT_16_BITS or stream.stereo:
			return _fail("sound %s is not mono 16-bit AudioStreamWAV" % sid)
		if stream.data.size() != samples.size() * 2:
			return _fail("sound %s PCM byte size mismatch" % sid)
	# 确定性: 清缓存后重新渲染, 字节逐位一致
	var first_hash: PackedStringArray = PackedStringArray()
	for sid2: String in ids:
		first_hash.push_back(str(SfxBankScript.get_stream(sid2).data.hex_encode().hash()))
	SfxBankScript.clear_cache()
	for k: int in range(ids.size()):
		var again: String = str(SfxBankScript.get_stream(ids[k]).data.hex_encode().hash())
		if again != first_hash[k]:
			return _fail("sound %s not deterministic" % ids[k])
	for alias: String in ["hit", "crit", "drop_normal", "drop_rare"]:
		if not SfxBankScript.has_sound(alias):
			return _fail("alias %s unresolved" % alias)
	if SfxBankScript.has_sound("no_such_sound"):
		return _fail("unknown sound should not resolve")
	print("[test_p15] SfxBank 13 procedural PCM sounds deterministic & audible PASS")
	return true

static func _test_sfx_mixer_pool_and_budget() -> bool:
	var mixer: SfxMixerScript = SfxMixerScript.new()
	# 旧接口兼容 (未挂载宿主也可调用): 单类并发上限 4
	var budget: VfxBudgetScript = VfxBudgetScript.new()
	mixer.begin_frame()
	budget.begin_frame(16.0)
	var played: int = 0
	var merged: int = 0
	for i: int in range(6):
		var res: Dictionary = mixer.request_play_sound("hit", budget)
		if bool(res.get("play", false)):
			played += 1
			var pitch: float = float(res.get("pitch_scale", 1.0))
			if pitch < 0.95 or pitch > 1.05:
				return _fail("pitch out of +-5%% range: %.3f" % pitch)
		if bool(res.get("merged", false)):
			merged += 1
	if played != 4 or merged != 2:
		return _fail("legacy mixer concurrency expected 4 played / 2 merged, got %d / %d" % [played, merged])

	var host: Node = Node.new()
	mixer.attach_host(host)
	mixer.attach_host(host)
	if mixer.get_channel_count() != 6 or host.get_child_count() != 6:
		return _fail("expected exactly 6 AudioStreamPlayer channels (idempotent attach)")

	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree != null and tree.root != null:
		tree.root.add_child(host)
		mixer.begin_frame()
		var before: int = mixer.get_started_total()
		mixer.request_play_sound("crit_slash", null)
		mixer.request_play_sound("drop_unique", null)
		if mixer.get_started_total() != before + 2:
			tree.root.remove_child(host)
			host.free()
			return _fail("mixer did not start voices on pooled channels")
		mixer.set_muted(true)
		mixer.begin_frame()
		var muted_before: int = mixer.get_started_total()
		mixer.request_play_sound("hit", null)
		if mixer.get_started_total() != muted_before:
			tree.root.remove_child(host)
			host.free()
			return _fail("muted mixer must not start voices")
		tree.root.remove_child(host)
	host.free()
	print("[test_p15] SfxMixer 6-channel pool + legacy request_play_sound signature + mute PASS")
	return true

static func _test_attention_glow_priority_dedup() -> bool:
	var glow: AttentionGlowScript = AttentionGlowScript.new()
	if glow.mouse_filter != Control.MOUSE_FILTER_IGNORE:
		glow.free()
		return _fail("AttentionGlow must ignore mouse")
	if not glow.push_signal(AttentionGlowScript.KIND_WALL_HINT):
		glow.free()
		return _fail("first wall_hint should be new")
	if glow.push_signal(AttentionGlowScript.KIND_WALL_HINT):
		glow.free()
		return _fail("duplicate wall_hint should be deduped")
	glow.push_signal(AttentionGlowScript.KIND_RESEARCH_DONE)
	if glow.get_top_kind() != AttentionGlowScript.KIND_RESEARCH_DONE:
		glow.free()
		return _fail("research_done should outrank wall_hint")
	glow.push_signal(AttentionGlowScript.KIND_BETTER_UNIQUE, 4)
	if glow.get_top_kind() != AttentionGlowScript.KIND_BETTER_UNIQUE or not glow.is_pulse_active():
		glow.free()
		return _fail("primal better_unique should be top with 120ms pulse")
	if not glow.get_kind_color(AttentionGlowScript.KIND_BETTER_UNIQUE).is_equal_approx(ThemePaletteScript.get_rarity_color(4)):
		glow.free()
		return _fail("primal band must be crimson")
	if glow.push_signal("bogus_kind"):
		glow.free()
		return _fail("unknown kind must be ignored")
	if glow.get_dedup_count() != 1:
		glow.free()
		return _fail("dedup counter mismatch")
	glow.advance(0.2)
	if glow.is_pulse_active():
		glow.free()
		return _fail("pulse must end after 120ms")
	glow.advance(30.0)
	if glow.get_top_kind() != "":
		glow.free()
		return _fail("all signals must expire")
	glow.free()
	print("[test_p15] AttentionGlow 5-kind priority / dedup / expiry / 120ms primal pulse PASS")
	return true

static func _make_item(uid: int, slot: int, rarity: int, ilvl: int, state: SimStateScript) -> ItemInstanceScript:
	return ItemInstanceScript.new(uid, "测试装备%d" % uid, slot, rarity, ilvl, 2.0 + float(ilvl) * 0.1, 0.1, 1.1, state.balance)

static func _test_inventory_filter_stats_panel() -> bool:
	var game: GameScript = GameScript.new()
	game.initialize_session(20261113, null, true)
	var state: SimStateScript = game.get_sim_state()
	state.inventory.items.push_back(_make_item(9101, ItemInstanceScript.Slot.WEAPON, ItemInstanceScript.Rarity.PURPLE, 12, state))
	state.inventory.items.push_back(_make_item(9102, ItemInstanceScript.Slot.HELM, ItemInstanceScript.Rarity.WHITE, 3, state))
	state.inventory.items.push_back(_make_item(9103, ItemInstanceScript.Slot.CHEST, ItemInstanceScript.Rarity.BLUE, 5, state))

	var win: MainWindowScript = MainWindowScript.new()
	win.bind_game(game)
	win._ready()
	var panel: InventoryFilterPanelScript = win.inventory_panel
	if panel == null or win.btn_inventory == null or win.btn_mute == null or win.attention_glow == null:
		win.free()
		game.free()
		return _fail("MainWindow missing inventory panel / buttons / attention glow")

	win.open_inventory_panel(InventoryFilterPanelScript.TabKind.BACKPACK)
	if not panel.visible or panel.get_cell_count() != 24:
		win.free()
		game.free()
		return _fail("backpack grid must expose 24 cells")

	panel.select_slot_index(0)
	if panel.get_selected_uid() != 9101:
		win.free()
		game.free()
		return _fail("selecting cell 0 should select uid 9101")

	# 穿戴 -> Command 队列 -> 下一 tick 生效
	panel._on_equip_pressed()
	game.advance_frame(0.2)
	var eq_w: ItemInstanceScript = state.equipped.get("weapon", null) as ItemInstanceScript
	if eq_w == null or eq_w.uid != 9101:
		win.free()
		game.free()
		return _fail("equip via Command queue failed")

	# 过滤阈值 Command
	panel.open_tab(InventoryFilterPanelScript.TabKind.FILTER)
	if panel.get_filter_button_count() != 5:
		win.free()
		game.free()
		return _fail("filter tab needs 5 threshold buttons")
	panel.set_filter_threshold(2)
	game.advance_frame(0.2)
	if state.filter.get_threshold() != 2:
		win.free()
		game.free()
		return _fail("SET_FILTER_THRESHOLD command did not apply (got %d)" % state.filter.get_threshold())

	# 一键熔炼低阶: 白(9102) + 蓝(9103) 均 < 紫阈值
	var cands: Array[int] = panel.get_low_smelt_candidates()
	if cands.size() != 2:
		win.free()
		game.free()
		return _fail("expected 2 low-tier smelt candidates, got %d" % cands.size())
	var gold_before: float = state.gold
	var issued: int = panel.smelt_low_tier_items()
	game.advance_frame(0.3)
	if issued != 2 or state.inventory.find_item_by_uid(9102) != null or state.inventory.find_item_by_uid(9103) != null:
		win.free()
		game.free()
		return _fail("one-click smelt did not remove low-tier items")
	if state.gold <= gold_before:
		win.free()
		game.free()
		return _fail("smelting must credit gold")

	# 属性明细
	panel.open_tab(InventoryFilterPanelScript.TabKind.STATS)
	for key: String in ["base", "gear", "additive", "unique", "soul", "abyss", "crit_rate", "crit_mult", "speed", "mf", "wealth", "pressure"]:
		if panel.get_stat_text(key) == "" or panel.get_stat_text(key) == "-":
			win.free()
			game.free()
			return _fail("stat row %s not populated" % key)
	if not panel.get_stat_text("crit_rate").ends_with("%") or not panel.get_stat_text("pressure").begins_with("×"):
		win.free()
		game.free()
		return _fail("stat row formats wrong")

	# 面板互斥: 打开系统抽屉必须关闭行囊
	win.open_systems_drawer(0)
	if panel.visible:
		win.free()
		game.free()
		return _fail("opening systems drawer must close inventory panel")

	# 静音按钮
	win._on_btn_mute_pressed()
	if not win.sfx_mixer.is_muted() or win.btn_mute.text != "静":
		win.free()
		game.free()
		return _fail("mute button toggle failed")

	win.free()
	game.free()
	print("[test_p15] Inventory panel 24 cells / equip / filter / smelt-low / stats / mutex / mute PASS")
	return true

static func _test_new_vfx_and_v10_budget() -> bool:
	var vfx: VfxManagerScript = VfxManagerScript.new()
	var card: Rect2 = Rect2(Vector2(24.0, 84.0), Vector2(176.0, 220.0))

	vfx.spawn_shield_shatter(card)
	if not vfx.is_shield_shatter_active():
		vfx.free()
		return _fail("shield shatter should start")
	vfx._process(0.2)
	if not vfx.is_shield_shatter_active():
		vfx.free()
		return _fail("shield shatter should still run at 200ms")
	vfx._process(0.2)
	if vfx.is_shield_shatter_active():
		vfx.free()
		return _fail("shield shatter must end by 350ms")

	if not vfx.spawn_smelt_ember(Vector2(112.0, 240.0), "helm", 1):
		vfx.free()
		return _fail("smelt ember should start")
	if vfx.get_active_smelt_count() != 1:
		vfx.free()
		return _fail("smelt slot count mismatch")
	vfx._process(0.5)
	if vfx.get_active_smelt_count() != 0:
		vfx.free()
		return _fail("smelt dissolve must end by 400ms")

	var spawned: int = 0
	for i: int in range(20):
		spawned += vfx.spawn_gold_magnet(Vector2(112.0, 240.0), 8)
	if spawned != VfxManagerScript.MAX_GOLD_MOTES or vfx.get_active_gold_motes_count() != 64:
		vfx.free()
		return _fail("gold mote must cap at 64, got %d" % vfx.get_active_gold_motes_count())
	vfx._process(0.7)
	if vfx.get_active_gold_motes_count() != 0:
		vfx.free()
		return _fail("gold mote must expire within 500ms")

	for key: String in ["meteor", "hammer", "gold_storm", "fountain_burst", "shield_shatter"]:
		if not vfx.spawn_by_vfx_key(key, Vector2(112.0, 194.0), card):
			vfx.free()
			return _fail("vfx_key %s unmapped" % key)
	if vfx.spawn_by_vfx_key("nope", Vector2.ZERO, card):
		vfx.free()
		return _fail("unknown vfx_key must return false")
	vfx.free()

	# V10: 10 秒爆发含全部新特效, 中心 40% 任意 200ms 遮挡 <= 30%
	var burst: VfxManagerScript = VfxManagerScript.new()
	burst.reset_occlusion_stats()
	var center: Vector2 = Vector2(112.0, 194.0)
	var dt: float = 1.0 / 30.0
	for frame: int in range(300):
		if frame % 3 == 0:
			burst.spawn_crit_ring(center)
		if frame % 4 == 0:
			burst.spawn_shield_shatter(card)
		if frame % 5 == 0:
			burst.spawn_chain_lightning(center, Vector2(288.0, 139.0), 1)
		if frame % 7 == 0:
			burst.spawn_meteor(center)
		if frame % 6 == 0:
			burst.spawn_hammer(center)
		if frame % 8 == 0:
			burst.spawn_gold_storm(center)
		if frame % 9 == 0:
			burst.spawn_drop_explosion(center + Vector2(10.0, 20.0), 4)
			burst.spawn_fountain_burst(center)
		if frame % 2 == 0:
			burst.spawn_smelt_ember(center + Vector2(0.0, 40.0), "boots", 0)
			burst.spawn_gold_magnet(center + Vector2(0.0, 30.0), 6)
		burst.update_killing_frenzy_afterimage(10, card)
		burst._process(dt)
	var max_occ: float = burst.get_max_rolling_200ms_occlusion()
	burst.free()
	if max_occ > 0.30:
		return _fail("V10 violated with new VFX: %.3f > 0.30" % max_occ)
	print("[test_p15] New VFX (shield/smelt/gold-magnet<=64/meteor/hammer/storm/fountain) + V10 burst occlusion = %.1f%% (<= 30%%) PASS" % (max_occ * 100.0))
	return true

static func _test_serif_font_fallback() -> bool:
	ThemePaletteScript.reset_font_probe()
	var has_font: bool = ThemePaletteScript.has_serif_font()
	var th: Theme = ThemePaletteScript.make_serif_theme()
	if has_font and th == null:
		return _fail("font file present but serif theme failed to load")
	if not has_font and th != null:
		return _fail("no font file but theme returned")
	print("[test_p15] Serif font adaptive binding (present=%s) PASS" % str(has_font))
	return true
