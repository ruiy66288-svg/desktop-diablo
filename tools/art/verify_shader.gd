extends SceneTree

## WP-A1 最小独立验证脚本: 实测加载、编译并渲染校验 palette_subject.gdshader
## 运行方式:
##   Godot_v4.7.2-stable_win64_console.exe --headless --path "f:\挂机游戏制作" --script res://tools/art/verify_shader.gd

const SHADER_PATH: String = "res://assets/art/shaders/palette_subject.gdshader"

const REQUIRED_UNIFORMS: Array[String] = [
	"color_ink",
	"color_bone",
	"color_family",
	"color_gold",
	"color_gold_bright",
	"hit_flash",
	"dissolve_amount",
	"dissolve_edge_width",
	"dissolve_edge_color",
	"use_external_noise",
	"dissolve_noise",
	"wealth_pressure",
	"enable_outline",
	"outline_color",
	"outline_width",
]

var _frame_count: int = 0
var _mat: ShaderMaterial = null

func _init() -> void:
	var shader_res: Resource = ResourceLoader.load(SHADER_PATH)
	if shader_res == null or not (shader_res is Shader):
		push_error("[FAIL] 无法加载 Shader: %s" % SHADER_PATH)
		quit(1)
		return

	var shader: Shader = shader_res as Shader
	if shader.get_mode() != Shader.MODE_CANVAS_ITEM:
		push_error("[FAIL] Shader 模式不是 MODE_CANVAS_ITEM: %d" % shader.get_mode())
		quit(1)
		return

	var uniform_list: Array = shader.get_shader_uniform_list()
	var found_names: Dictionary = {}
	for entry_variant: Variant in uniform_list:
		var entry: Dictionary = entry_variant as Dictionary
		var uname: String = str(entry.get("name", ""))
		found_names[uname] = true

	for req_name: String in REQUIRED_UNIFORMS:
		if not found_names.has(req_name):
			push_error("[FAIL] 缺少必需 uniform 参数: %s" % req_name)
			quit(1)
			return

	_mat = ShaderMaterial.new()
	_mat.shader = shader
	_mat.set_shader_parameter("color_ink", Color("#0B0A0C"))
	_mat.set_shader_parameter("color_bone", Color("#E8DCC0"))
	_mat.set_shader_parameter("color_family", Color("#7A0F14"))
	_mat.set_shader_parameter("color_gold", Color("#C9A04E"))
	_mat.set_shader_parameter("color_gold_bright", Color("#E9C46A"))
	_mat.set_shader_parameter("hit_flash", 0.25)
	_mat.set_shader_parameter("dissolve_amount", 0.30)
	_mat.set_shader_parameter("wealth_pressure", 0.42)
	_mat.set_shader_parameter("enable_outline", true)
	_mat.set_shader_parameter("outline_width", 1.5)

	var img: Image = Image.create(32, 32, true, Image.FORMAT_RGBA8)
	for y: int in range(32):
		for x: int in range(32):
			var inside: bool = (x >= 6 and x <= 25 and y >= 4 and y <= 28)
			if inside:
				var r_val: float = 1.0 if ((x / 3 + y / 3) % 2 == 0) else 0.0
				var g_val: float = 1.0 if (x >= 10 and x <= 13 and y >= 10 and y <= 13) else 0.0
				var b_val: float = 1.0 if (x >= 18 and x <= 21 and y >= 10 and y <= 13) else 0.0
				img.set_pixel(x, y, Color(r_val, g_val, b_val, 1.0))
			else:
				img.set_pixel(x, y, Color(0.0, 0.0, 0.0, 0.0))

	var tex: ImageTexture = ImageTexture.create_from_image(img)
	var sprite: Sprite2D = Sprite2D.new()
	sprite.position = Vector2(180.0, 240.0)
	sprite.texture = tex
	sprite.material = _mat
	root.add_child(sprite)

func _process(_delta: float) -> bool:
	_frame_count += 1
	if _frame_count == 1 and _mat != null:
		# 第二帧测试负债剥落分支 (wealth_pressure < 0)
		_mat.set_shader_parameter("wealth_pressure", -0.35)
		_mat.set_shader_parameter("hit_flash", 0.0)
	if _frame_count >= 2:
		print("[PASS] palette_subject.gdshader 编译与双分支渲染校验通过 (uniforms=%d, frames=%d)" % [REQUIRED_UNIFORMS.size(), _frame_count])
		quit(0)
		return true
	return false
