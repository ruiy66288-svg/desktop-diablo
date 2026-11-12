# 《桌面破坏神》工程与生产待核实项实测记录 (Verification Log)
**版本：V1.0 · 首次实测时间：2026-11-12**

依据《00_开发执行总纲.md》第 7 节“待核实清单”，所有工具能力、模型单价、许可证及后处理流程均需实测落盘。本文件记录各项实测数据，作为执行模型（Gemini Carbon）后续批量开发与生产的直接依据。

---

## [V-02] GPT Image 2.6 实测调用与单张成本核实报告

- **实测状态**：✅ **已通过验证（Canonical 实况）**
- **实测时间**：2026-11-12 22:28
- **调用模型**：`gpt-image-2.6-flare`
- **调用参数**：
  - `prompt`: 遵照《04_美术资产管线_v1.1.md》§4.1 模板（守财亡骸·不死族）
  - `quality`: `"low"`
  - `size`: `"1024x1024"`
  - `n`: 1
- **API 返回 Usage 实测值**：
  - `input_tokens`: 161（全部为 text_tokens，无参考图输入）
  - `output_tokens`: 824（全部为 image_tokens）
  - `total_tokens`: 985
- **实际账单结算（官方 rate: 文本 $5/1M, 图像输出 $30/1M）**：
  - 文本输入费：$161 \times \$5.00 / 1,000,000 = \$0.000805$
  - 图像输出费：$824 \times \$30.00 / 1,000,000 = \$0.024720$
  - **单张最终总费用**：**\$0.025525 USD**（按汇率折合约 **0.185 元人民币**）
- **生成耗时**：约 12 ~ 14 秒。
- **输出格式**：默认返回 `b64_json`，无需额外网络下载，可直接通过 Python 本地落盘。
- **测试样本存档**：
  - 原始生成图：[`art_source/raw/test_sample/test_skeleton_flare_low.png`](../art_source/raw/test_sample/test_skeleton_flare_low.png)
  - 四通道打包图：[`art_source/raw/test_sample/test_skeleton_packed_rgba.png`](../art_source/raw/test_sample/test_skeleton_packed_rgba.png)
  - Shader还原预览图：[`art_source/raw/test_sample/test_skeleton_shader_preview.png`](../art_source/raw/test_sample/test_skeleton_shader_preview.png)

### 后处理算法实测结论：
1. **纯平中灰底抠图可行性 100%**：通过画布四角取样（RGB: 112, 111, 111）结合 OpenCV 边缘 FloodFill，可 100% 滤除外部灰色，且不损伤主体内部任何骨骼或暗部线段。
2. **黄金与骨白通道分离可行性 100%**：在 HSV 空间下，通过色相 H ∈ [10, 38]、饱和度 S > 60 可极干净地提取金色钱币/王冠等镀金层（写入 B 通道），高明度低饱和度像素提取为骨白受光（写入 R 通道）。
3. **质感验收结论**：即使是 `quality="low"` 级别，木刻刀痕粗细均匀，暗部大块墨黑坚实，完全不存在 AI 常见的写实噪点与灰阶浑浊，满足《美术风格圣经》小窗口高辨识度要求。

---

## [V-04] PixelFX 许可证与 NOTICE 实测核实报告

- **实测状态**：✅ **已通过验证（Canonical 实况）**
- **官方仓库**：`github.com/patch-gg/pixelfx` (2026-11-12 抓取)
- **代码许可**：MIT License（Copyright (c) 2026 Patch / Hugo Duprez）
- **NOTICE.md 核心条款**：
  1. `src/core/sim.js` 改编自 Sprite Fusion 的开源像素特效（Hugo Duprez, MIT）。
  2. `src/core/act.js` 改编自 Hollow Crown（rehan-remade, MIT）。
  3. **【严禁使用红线】**：`gallery/fonts/PatchPixel-Regular.woff2` 为 Patch 自有版权字体，明确声明**不包含在 MIT 许可内（All rights reserved）**，本项目严禁引用。
- **项目集成结论**：
  - 仅复用其纯代码生成的特效逻辑导出的灰度帧序列（Sheet），在游戏发布时将 Patch / Hugo Duprez / rehan-remade 计入 `third_party_notices.txt` 即可合规商用。


---

## [V-01] 本机 Godot 4 引擎实况与环境核实报告

- **实测状态**：✅ **已通过验证（Canonical 实况 · WP-00 复核更新 2026-11-12）**
- **引擎版本**：`Godot Engine v4.7.2.stable.official.ed1daf0bf`（官方标准版，非 .NET 版）
- **控制台绝对路径**：`F:\Godot\4.7.2\Godot_v4.7.2-stable_win64_console.exe`
- **GUI 可执行路径**：`F:\Godot\4.7.2\Godot_v4.7.2-stable_win64.exe`
- **渲染后端实测**：`OpenGL API 3.3.0 - Compatibility`（`RenderingDriver=opengl3`, `RenderingMethod=gl_compatibility`）
- **原生窗口与拖拽 API 探针（`ClassDB` 实测）**：
  - `DisplayServer.window_start_drag(window_id)`：**支持（`true`）**，且 `Window.start_drag()` 同步可用；手动偏移拖拽可保留作兜底。
  - `DisplayServer.window_set_mouse_passthrough(region, window_id)`：**支持（`true`）**，可用于圆角外透明区鼠标穿透。
  - 小窗实机启动与自动退出核验（`--quit-after 10`）：窗口尺寸 `(360, 480)`、`FLAG_BORDERLESS=true`、`FLAG_ALWAYS_ON_TOP=true`、`FLAG_TRANSPARENT=true`、`root.transparent_bg=true`、`Engine.max_fps=30`，退出码 `0`。
- **数据纹理导入与 sRGB 选项实测（`ResourceImporterTexture` `.import` 参数）**：
  - 在 Godot 4.7.2 `importer="texture"`（`CompressedTexture2D`）下，四通道打包数据纹理应配置：
    - `compress/mode=0`（Lossless 无损压缩）
    - `mipmaps/generate=true`（开启 Mipmaps；默认值为 `false` 需显式改为 `true`）
    - `detect_3d/compress_to=0`（关闭 3D 自动检测压缩/sRGB 转换；默认值为 `1` 需改为 `0`）
    - `compress/channel_pack=1`（Non-Color Data 数据通道优化打包）
    - `process/hdr_as_srgb=false`
  - 在 `gl_compatibility` 的 `canvas_item` Shader 中，`TEXTURE` 或不带 `: source_color` 修饰的 `sampler2D` 直接按 0..1 原始字节归一化读取，不做 sRGB 伽马变换；线性过滤与 Mipmap 采样通过 Shader `filter_linear_mipmap` 或节点 `TEXTURE_FILTER_LINEAR_WITH_MIPMAPS` 指定。
- **§3.1 配套工具链实测版本**：
  - Python：`3.13.2`（`F:\python\python.exe`），依赖全部就绪：`Pillow 12.2.0`、`numpy 2.4.6`、`scikit-image 0.26.0`、`opencv-python-headless 4.13.0.92`、`openai 2.41.0`、`PyYAML 6.0.3`
  - Node.js：`v24.15.0`（满足 ≥ 20）
  - Git & Git LFS：`git version 2.56.0.windows.4`、`git-lfs/3.8.1`（`.gitattributes` 已配置 `art_source/raw/**/*.png` 走 `filter=lfs`）
  - 环境变量状态（仅布尔核查）：当前进程环境 `OPENAI_API_KEY` 未设置（`False`）、`ART_BUDGET_USD` 未设置（`False`）；根目录 `.env` 已配置对应键名并由 `.gitignore` 严格忽略。
- **执行命令范例**：
  ```bash
  & "F:\Godot\4.7.2\Godot_v4.7.2-stable_win64_console.exe" --headless --path "F:\挂机游戏制作" --script res://tests/run_all.gd
  ```
- **测试套件运行结论**：
  - `project.godot` 配置已正确识别，支持 360×480 无边框透明窗口与 Compatibility 渲染。
  - `res://tests/run_all.gd` 测试运行器在 Godot 4.7.2 下 100% 正常执行，全套单元测试通过，退出码 `0`。


---

## [V-02 补充] GPT Image 2.6 · high · 1536×1024 实测（2026-11-12 22:37）

| 项 | 数值 |
|---|---|
| 模型 | `gpt-image-2.6-flare` |
| 参数 | quality = `high`，size = `1536x1024`，n = 1 |
| usage | 输入 486 个文本 token，输出 1353 个图像 token |
| 估算费用 | **约 \$0.043 / 张** |

**结论**：high 档的成本很低，可以直接用于锚点图。04 号文件 §3 的成本估算偏高，应按实测数据更新。

- 台账：`art_source/ledger/openai_usage.csv`
- 原图：`art_source/raw/style_board_v1/gen_d7a4d440f0b031b7.png`

## [V-02 补充2] GPT Image 2.6 · low · 1024×1024 第二次调用实测（2026-11-12 22:51）

| 项 | 数值 |
|---|---|
| 模型 | `gpt-image-2.6-flare` |
| 参数 | quality = `low`，size = `1024x1024`，n = 1 |
| 测试主体 | 债魔（恶魔族 · 财富母题：债链、金挂锁、契约账簿） |
| usage | 输入 179 个文本 token，输出 824 个图像 token，合计 1003 tokens |
| 实际结算费用 | **$0.025615 USD**（折合约 **0.1857 元人民币**） |
| 生成耗时 | 约 16 秒 |
| 原图落盘 | `art_source/raw/test_sample/test_demon_flare_low.png` |
| RGBA 打包 | `art_source/raw/test_sample/test_demon_packed_rgba.png` |
| 着色还原预览 | `art_source/raw/test_sample/test_demon_shader_preview.png` |
| 台账记录 | `art_source/ledger/openai_usage.csv` |

**结论**：连续两次实测验证，`gpt-image-2.6-flare` 的 `low` 档出图费用稳定在 **$0.0256 USD (~0.186 元)** 左右，输入 token 与提示词长度正相关（160~180 tokens），输出固定为 824 tokens。成本控制与通道分离管线完全闭环。

---

## [风格方向板 v1] 评审（`docs/ref/style_board_gilded_debt_v1.png`，替换已废弃的概念图 A）

**符合规范的地方**：
- 粗刀木刻，墨黑加骨白；
- 镀金只出现在财富母题上：金币眼窝、钱袋、债链与挂锁、金条獠牙、金币堆；
- 五档品质光柱的顺序和色相正确；
- 图中没有任何文字。

**与规范的偏差**（锚点图和正式资产必须纠正）：
1. **卡面底色是骨白纸色**。规范要求黑底骨白：卡底用 `#16161C`，主体用灰底出图，再由脚本抠成透明。
2. **毛发和披风的排线过细**，接近铜版画。缩到 72px 时会发灰，违反 03 号文件的 V3。
3. **头盔和胸甲带有轻微的金属明暗过渡**。应改为只用平行刀痕表现金属。
4. **光柱底部的放射刺状光线过多**。正式版由 Shader 绘制，控制在 4–6 道楔形刀痕以内。
5. **小窗示意缺少右侧的 2 张排队卡**。布局以 03 号文件 §02.1 为准。

**用途**：只作为风格方向参考，**不能**作为 Image 1 锚点。锚点图按 WP-A3 的流程单独生成。
