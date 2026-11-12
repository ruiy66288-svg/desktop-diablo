extends RefCounted

## WP-11 & WP-12 专项单元测试：
## 1. VfxManager 连锁闪电 Line2D 池（ADD 混合 + 90ms/跳 + 上限 2）
## 2. VfxManager 落地即爆 ground_slam.gdshader 池（<= 40px + 250ms）
## 3. VfxManager 杀戮狂热 afterimage.gdshader 叠层随 stacks (0..10) 线性变化
## 4. MainWindow 6 槽换装对比浮层 + DryRun 30s Δ% 确定性与 Command.EQUIP_ITEM 隔离闭环

const GameScript = preload("res://autoload/Game.gd")
const MainWindowScript = preload("res://ui/MainWindow.gd")
const VfxManagerScript = preload("res://presentation/vfx/VfxManager.gd")
const ItemInstanceScript = preload("res://simulation/loot/ItemInstance.gd")
const SimStateScript = preload("res://simulation/SimState.gd")

static func run() -> bool:
	var ok: bool = true
	ok = _test_vfx_affix_pools() and ok
	ok = _test_wp12_dryrun_compare_and_equip_command() and ok
	return ok

static func _test_vfx_affix_pools() -> bool:
	var vfx: VfxManagerScript = VfxManagerScript.new()

	# 1. Chain Lightning Line2D pool
	vfx.spawn_chain_lightning(Vector2(100.0, 180.0), Vector2(260.0, 150.0), 1)
	if vfx.get_active_lightning_lines_count() != 1:
		push_error("[test_vfx_affixes] Expected 1 active lightning Line2D slot, got %d" % vfx.get_active_lightning_lines_count())
		vfx.free()
		return false

	vfx.spawn_chain_lightning(Vector2(260.0, 150.0), Vector2(290.0, 220.0), 2)
	vfx.spawn_chain_lightning(Vector2(100.0, 180.0), Vector2(300.0, 220.0), 1)
	if vfx.get_active_lightning_lines_count() != 2:
		push_error("[test_vfx_affixes] Expected max 2 concurrent lightning slots, got %d" % vfx.get_active_lightning_lines_count())
		vfx.free()
		return false

	# Step 0.10s -> jump 1 (0.09s) expires, jump 2 (0.18s) stays active
	vfx._process(0.10)
	if vfx.get_active_lightning_lines_count() != 1:
		push_error("[test_vfx_affixes] Expected jump 1 to expire after 0.10s, remaining=%d" % vfx.get_active_lightning_lines_count())
		vfx.free()
		return false

	# 2. Ground Slam shader pool
	vfx.spawn_drop_explosion(Vector2(112.0, 210.0), 4)
	if vfx.get_active_slam_rects_count() != 1:
		push_error("[test_vfx_affixes] Expected 1 active ground_slam rect, got %d" % vfx.get_active_slam_rects_count())
		vfx.free()
		return false
	vfx._process(0.26)
	if vfx.get_active_slam_rects_count() != 0:
		push_error("[test_vfx_affixes] Expected ground_slam rect to expire after 0.26s")
		vfx.free()
		return false

	# 3. Killing Frenzy afterimage shader scaling (0..10)
	var card_rect: Rect2 = Rect2(Vector2(24.0, 84.0), Vector2(176.0, 220.0))
	vfx.update_killing_frenzy_afterimage(0, card_rect)
	if vfx.is_frenzy_afterimage_visible() or vfx.get_frenzy_afterimage_ratio() != 0.0:
		push_error("[test_vfx_affixes] Expected frenzy afterimage hidden at 0 stacks")
		vfx.free()
		return false

	vfx.update_killing_frenzy_afterimage(10, card_rect)
	if not vfx.is_frenzy_afterimage_visible() or not is_equal_approx(vfx.get_frenzy_afterimage_ratio(), 1.0):
		push_error("[test_vfx_affixes] Expected frenzy afterimage visible and ratio=1.0 at 10 stacks")
		vfx.free()
		return false

	vfx.free()
	print("[test_vfx_affixes] _test_vfx_affix_pools PASS")
	return true

static func _test_wp12_dryrun_compare_and_equip_command() -> bool:
	var game: GameScript = GameScript.new()
	game._ready()

	var win: MainWindowScript = MainWindowScript.new()
	win.bind_game(game)
	win._ready()

	var state: SimStateScript = game.get_sim_state()
	var strong_weapon: ItemInstanceScript = ItemInstanceScript.new(
		99001,
		"镀金断罪剑",
		ItemInstanceScript.Slot.WEAPON,
		ItemInstanceScript.Rarity.UNIQUE,
		25,
		4.2,
		0.5,
		1.5,
		state.balance
	)
	state.inventory.add_item(strong_weapon, state)

	# 1. DryRun 确定性与 Δ% > 0
	var list_a: Array[Dictionary] = win.get_compare_entries_data("weapon", 987654321)
	var list_b: Array[Dictionary] = win.get_compare_entries_data("weapon", 987654321)
	if list_a.is_empty() or list_b.is_empty():
		push_error("[test_vfx_affixes] Expected weapon candidate in compare entries")
		win.free()
		game.free()
		return false

	var delta_a: float = float(list_a[0].get("delta_pct", 0.0))
	var delta_b: float = float(list_b[0].get("delta_pct", 0.0))
	if not is_equal_approx(delta_a, delta_b) or delta_a <= 0.0:
		push_error("[test_vfx_affixes] Expected deterministic positive delta_pct, got %.4f vs %.4f" % [delta_a, delta_b])
		win.free()
		game.free()
		return false

	# 2. 打开对比浮层并经 Command 队列换装
	win.open_equip_compare_panel("weapon")
	if not win.equip_compare_panel.visible:
		push_error("[test_vfx_affixes] Expected equip_compare_panel to be visible")
		win.free()
		game.free()
		return false

	win._on_compare_equip_pressed(99001)
	if win.equip_compare_panel.visible:
		push_error("[test_vfx_affixes] Expected equip_compare_panel to close after equip")
		win.free()
		game.free()
		return false

	game.advance_frame(0.2)
	var equipped_wpn: ItemInstanceScript = state.equipped.get("weapon", null) as ItemInstanceScript
	if equipped_wpn == null or equipped_wpn.uid != 99001:
		push_error("[test_vfx_affixes] Expected weapon uid=99001 equipped via Command.EQUIP_ITEM")
		win.free()
		game.free()
		return false

	win.free()
	game.free()
	print("[test_vfx_affixes] _test_wp12_dryrun_compare_and_equip_command PASS (delta_pct=+%.2f%%)" % delta_a)
	return true
