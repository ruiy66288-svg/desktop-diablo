extends SceneTree

# 单跑 [WP-P15-FEEL] 测试: godot --headless --script res://tests/run_p15_only.gd
# (Wave 1 期间不修改 run_all.gd, 由 @verifier/@env-d0 集成阶段统一挂载)

const TestP15 = preload("res://tests/test_p15_audio_ui_vfx.gd")

func _init() -> void:
	var ok: bool = TestP15.run()
	if ok:
		print("[run_p15_only] ALL PASSED")
		quit(0)
	else:
		printerr("[run_p15_only] FAILED")
		quit(1)
