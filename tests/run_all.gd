extends SceneTree

# 《桌面破坏神》Headless 自动化测试总运行器 (符合 00_开发执行总纲.md §4.1 & §4.8)
# 运行命令: godot --headless --script res://tests/run_all.gd

const TestNum = preload("res://tests/test_num.gd")
const TestBalance = preload("res://tests/test_balance.gd")
const TestCombatSim = preload("res://tests/test_combat_sim.gd")
const TestLootInventory = preload("res://tests/test_loot_inventory.gd")
const TestWallet = preload("res://tests/test_wallet.gd")
const TestPresentation = preload("res://tests/test_presentation.gd")
const TestAffixResolver = preload("res://tests/test_affix_resolver.gd")
const TestCredit = preload("res://tests/test_credit.gd")
const TestTechTree = preload("res://tests/test_tech_tree.gd")
const TestTollMechanics = preload("res://tests/test_toll_mechanics.gd")
const TestD6PrestigeSave = preload("res://tests/test_d6_prestige_save.gd")

func _init() -> void:
	print("==================================================")
	print("[TestRunner] 正在启动《桌面破坏神》测试套件...")
	print("==================================================")

	var passed_count: int = 0
	var total_count: int = 0

	# 1. WP-01: Num 对数大数库测试
	total_count += 1
	if TestNum.run():
		passed_count += 1

	# 2. WP-02: Balance 全局数值模型与常数注释完整性测试
	total_count += 1
	if TestBalance.run():
		passed_count += 1

	# 3. WP-03: Combat 核心战斗管线与 10,000 ticks 确定性状态哈希测试
	total_count += 1
	if TestCombatSim.run():
		passed_count += 1

	# 4. WP-05: 掉落、过滤、熔炼、24 格背包与 Command 队列测试
	total_count += 1
	if TestLootInventory.run():
		passed_count += 1

	# 5. WP-06: 净财富压力钱包与借贷机制测试
	total_count += 1
	if TestWallet.run():
		passed_count += 1

	# 6. WP-08: 渲染管线、对象池、事件总线与音效预算测试
	total_count += 1
	if TestPresentation.run():
		passed_count += 1

	# 7. WP-10~12: 词条解析器、四重防递归保险、六槽换装与 DryRun 确定性测试
	total_count += 1
	if TestAffixResolver.run_all_tests():
		passed_count += 1

	# 7b. WP-13: 信贷溢价 / 预览一致 / 40% 抵扣 / 信用升阶
	total_count += 1
	if TestCredit.run():
		passed_count += 1

	# 7c. WP-14: 科技树 6 节点 + 5 格研究队列（Unix 时间戳）
	total_count += 1
	if TestTechTree.run():
		passed_count += 1

	# 7d. WP-15: 第 100 层门票 / 储蓄托管 / 护盾机制
	total_count += 1
	if TestTollMechanics.run():
		passed_count += 1

	# 7e. WP-16/17: 灵魂转生、存档读档、离线结算
	total_count += 1
	if TestD6PrestigeSave.run():
		passed_count += 1

	# 8. WP-04 (自动接入): 若 res://tests/test_curve_sim.gd 存在则执行
	if ResourceLoader.exists("res://tests/test_curve_sim.gd"):
		var curve_test_script: GDScript = ResourceLoader.load("res://tests/test_curve_sim.gd") as GDScript
		if curve_test_script != null:
			total_count += 1
			if not curve_test_script.can_instantiate():
				printerr("[TestRunner] 可选测试脚本编译失败，计为未通过: " + curve_test_script.resource_path)
			else:
				if bool(curve_test_script.call("run")):
					passed_count += 1

	# 9. WP-07 (自动接入): 若 res://tests/test_desktop_window.gd 存在则执行
	if ResourceLoader.exists("res://tests/test_desktop_window.gd"):
		var desktop_test_script: GDScript = ResourceLoader.load("res://tests/test_desktop_window.gd") as GDScript
		if desktop_test_script != null:
			total_count += 1
			if not desktop_test_script.can_instantiate():
				printerr("[TestRunner] 可选测试脚本编译失败，计为未通过: " + desktop_test_script.resource_path)
			else:
				if bool(desktop_test_script.call("run")):
					passed_count += 1

	# 10. WP-11 (自动接入): 若 res://tests/test_vfx_affixes.gd 存在则执行
	if ResourceLoader.exists("res://tests/test_vfx_affixes.gd"):
		var vfx_test_script: GDScript = ResourceLoader.load("res://tests/test_vfx_affixes.gd") as GDScript
		if vfx_test_script != null:
			total_count += 1
			if not vfx_test_script.can_instantiate():
				printerr("[TestRunner] 可选测试脚本编译失败，计为未通过: " + vfx_test_script.resource_path)
			else:
				if bool(vfx_test_script.call("run")):
					passed_count += 1

	# 11. D5 UI (自动接入): 若 res://tests/test_d5_ui.gd 存在则执行
	if ResourceLoader.exists("res://tests/test_d5_ui.gd"):
		var d5_ui_test_script: GDScript = ResourceLoader.load("res://tests/test_d5_ui.gd") as GDScript
		if d5_ui_test_script != null:
			total_count += 1
			if not d5_ui_test_script.can_instantiate():
				printerr("[TestRunner] 可选测试脚本编译失败，计为未通过: " + d5_ui_test_script.resource_path)
			else:
				if bool(d5_ui_test_script.call("run")):
					passed_count += 1

	# 12. D6 UI (自动接入): 若 res://tests/test_d6_ui.gd 存在则执行
	if ResourceLoader.exists("res://tests/test_d6_ui.gd"):
		var d6_ui_test_script: GDScript = ResourceLoader.load("res://tests/test_d6_ui.gd") as GDScript
		if d6_ui_test_script != null:
			total_count += 1
			if not d6_ui_test_script.can_instantiate():
				printerr("[TestRunner] 可选测试脚本编译失败，计为未通过: " + d6_ui_test_script.resource_path)
			else:
				if bool(d6_ui_test_script.call("run")):
					passed_count += 1

	# 13. WP-09 正式美术与 Shader 集成 (自动接入): 若 res://tests/test_wp09_art_integration.gd 存在则执行
	if ResourceLoader.exists("res://tests/test_wp09_art_integration.gd"):
		var wp09_test_script: GDScript = ResourceLoader.load("res://tests/test_wp09_art_integration.gd") as GDScript
		if wp09_test_script != null:
			total_count += 1
			if not wp09_test_script.can_instantiate():
				printerr("[TestRunner] 可选测试脚本编译失败，计为未通过: " + wp09_test_script.resource_path)
			else:
				if bool(wp09_test_script.call("run")):
					passed_count += 1

	# 14. WP-P2-SIM-1 阶段 1.5/2 模拟内核、百层机制与深渊转生
	if ResourceLoader.exists("res://tests/test_p2_sim_mechanics_abyss.gd"):
		var p2_sim_script: GDScript = ResourceLoader.load("res://tests/test_p2_sim_mechanics_abyss.gd") as GDScript
		if p2_sim_script != null:
			total_count += 1
			if not p2_sim_script.can_instantiate():
				printerr("[TestRunner] 可选测试脚本编译失败，计为未通过: " + p2_sim_script.resource_path)
			else:
				if bool(p2_sim_script.call("run")):
					passed_count += 1

	# 15. WP-P15-FEEL 阶段 1.5 音频混音池、行囊过滤与微特效
	if ResourceLoader.exists("res://tests/test_p15_audio_ui_vfx.gd"):
		var p15_feel_script: GDScript = ResourceLoader.load("res://tests/test_p15_audio_ui_vfx.gd") as GDScript
		if p15_feel_script != null:
			total_count += 1
			if not p15_feel_script.can_instantiate():
				printerr("[TestRunner] 可选测试脚本编译失败，计为未通过: " + p15_feel_script.resource_path)
			else:
				if bool(p15_feel_script.call("run")):
					passed_count += 1

	# 16. WP-P15-FONT-PLAT 思源宋体子集化、系统托盘与 DWM 防黑底封装
	if ResourceLoader.exists("res://tests/test_p2_platform_tray.gd"):
		var p2_plat_script: GDScript = ResourceLoader.load("res://tests/test_p2_platform_tray.gd") as GDScript
		if p2_plat_script != null:
			total_count += 1
			if not p2_plat_script.can_instantiate():
				printerr("[TestRunner] 可选测试脚本编译失败，计为未通过: " + p2_plat_script.resource_path)
			else:
				if bool(p2_plat_script.call("run")):
					passed_count += 1

	print("--------------------------------------------------")
	if passed_count == total_count:
		print("[TestRunner] 全部测试通过! 通过数 / 总数: %d / %d" % [passed_count, total_count])
		quit(0)
	else:
		printerr("[TestRunner] 存在未通过的测试用例! 通过数 / 总数: %d / %d" % [passed_count, total_count])
		quit(1)
