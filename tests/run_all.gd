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

	# 4. WP-05: 掉落、过滤、熔炼与 24 格背包测试
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

	# 7. WP-04 (可选自动接入): 若 res://tests/test_curve_sim.gd 已创建则一并执行
	if ResourceLoader.exists("res://tests/test_curve_sim.gd"):
		var curve_test_script: GDScript = ResourceLoader.load("res://tests/test_curve_sim.gd") as GDScript
		if curve_test_script != null:
			total_count += 1
			var ok: bool = bool(curve_test_script.call("run"))
			if ok:
				passed_count += 1

	print("--------------------------------------------------")
	if passed_count == total_count:
		print("[TestRunner] 全部测试通过! 通过数 / 总数: %d / %d" % [passed_count, total_count])
		quit(0)
	else:
		printerr("[TestRunner] 存在未通过的测试用例! 通过数 / 总数: %d / %d" % [passed_count, total_count])
		quit(1)
