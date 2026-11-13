# 桌面破坏神 (Desktop Diablo)

> **Windows 桌面常驻 360×480 无边框透明置顶 ·「暗黑爆装 × 净财富信贷博弈 × 纯对数无限增量」挂机游戏**  
> 引擎：**Godot 4.7.2-stable (Standard / GL Compatibility / 30 FPS)** ｜ 视觉母题：**「镀金债契 · 骨白版画」(Gilded Debt Woodcut)**

---

## 1. 项目概览与核心循环

《桌面破坏神》是一款驻留在桌面一角的硬核数值增量与暗黑刷宝挂机游戏。游戏将**确定性高频战斗模拟**、**暗黑词条构筑（Build）**与**动态净财富信贷博弈**压缩进 `360×480` 的无边框透明小窗中，并以中世纪铜版画与高利贷羊皮债契为视觉语言，通过四通道数据纹理与自定义 `palette_subject.gdshader` 实现受玩家净财富状态实时驱动的「骨白墨刻 × 债血鎏金」画面表现。

### 实机画面与资产检视

| 360×480 实机主窗口（版画渲染） | 深渊领主 Boss 战 & 净财富色调状态 |
| :---: | :---: |
| ![实机主窗口](tools/out/wp09_v9_live_window.png) | ![Boss战与净财富状态](tools/out/wp09_boss_and_wealth_states.png) |

| 暗金词条标志性 Shader 特效（震地 / 残影 / 光柱） | 全量 10 件正式版画主体资产四联质检板 |
| :---: | :---: |
| ![词条特效预览](tools/out/wp11_affix_vfx_preview.png) | ![资产总览检视板](tools/out/wp_a4_all_assets_contact_sheet.png) |

---

## 2. 核心架构与系统特性

1. **纯对数大数引擎（`core/math/Num.gd`）**
   - 采用 `{sign: int, exp: float}` 对数表示法（`value = sign * 10^exp`），支持覆盖 `10^0` 至 `10^(10^300)` 的加减乘除、幂运算、比较与自适应单位格式化，彻底消除双精度浮点溢出。
2. **模拟层与表现层严格解耦（`simulation/` ↔ `presentation/`）**
   - `simulation/` 纯逻辑层零节点依赖，按 **10Hz（0.1s/tick）** 固定步长确定性推进；
   - `SimRng` 采用 SplitMix64 派生 `combat` / `loot` / `affix` 三路独立随机流，`10,000 ticks` 跨运行状态哈希严格一致；
   - UI 所有交互统一封装为 `Command` 入队，在 tick 边界原子消费，并用零副作用克隆 `DryRun` 计算六槽换装的真实等效 DPS 差值。
3. **暗黑词条引擎与四重防递归保险（`AffixResolver.gd`）**
   - 支持 **6 个装备槽位**（武器、头盔、胸甲、护手、战靴、饰品）、**5 档稀有度**（白/蓝/黄/橙/太古满 Roll）与 **3 大标志性触发词条**（连锁闪电 `chain_lightning`、杀戮狂热 `killing_frenzy`、爆装冲击 `drop_explosion`，驱动震地裂纹 `ground_slam.gdshader`、残影 `afterimage.gdshader` 与折线电弧表现）；
   - 内置因果掩码（Causal Chain Mask）、独立冷却、计数器累加与单步触发上限四重防无限递归保险，支持 100× 极限攻速压测稳定运行。
4. **净财富压力与动态信贷系统（`Wallet.gd` / `CreditService.gd` / `TechTree.gd`）**
   - **净财富压力**：以 `W = gold - debt_total` 驱动承压系数，彻底封死“借钱囤积不花以压低怪物强度”的套利空间；
   - **利用率平方溢价**：贷款溢价率 `premium_rate(u) = 1.1 + 0.5 * u²`（`u = debt_principal / credit_limit`），提前消费需承担真实复利成本，战斗金币掉落最高 **40%** 自动抵扣未清债务；
   - **科技树与过路费闸门**：6 节点科技树搭配 5 格 Unix 时间戳离线研究队列；第 100 层起每 25 层设置 `Toll` 过路费储蓄托管闸门与 Boss 护盾机制（`MechanicDef`）。
5. **灵魂转生、离线结算与原子存档（`PrestigeService.gd` / `OfflineCalc.gd` / `SaveService.gd`）**
   - 灵魂结算公式 `souls_gain = floor((max(0, max_stage - 80) / 20)^2.2)`，未偿清债务折算为 `legacy_debt_minutes` 结转下周目；
   - 存档采用 `.tmp` 写入校验 → 原子重命名 → `.bak` 自动回退机制，支持最高 **8 小时离线收益结算**与系统时钟回拨保护。
6. **桌面常驻小窗工程化体验（`platform/DesktopWindow.gd` / `ui/`）**
   - 360×480 无边框置顶透明窗口、标题栏拖拽、折叠迷你条模式、失焦自动降透明度（`0.45 Alpha`）、老板键一键隐藏/唤醒（`Alt+Q`）与多显示器越界自愈。

---

## 3. 仓库目录与资源治理规范

```text
.
├── project.godot                # Godot 4.7.2 工程配置 (360×480, 无边框置顶透明, gl_compatibility, 30fps)
├── .gitattributes               # Git LFS 追踪规则 (art_source/{raw,anchors,rejected}/**/*.png)
├── .gitignore                   # 严格排除 .env、.godot/、*.tmp 与 art_source/thirdparty_raw/*
├── third_party_notices.txt      # 第三方开源代码与字体完整许可证声明
├── docs/                        # 核心设计基准与工程验证文档
│   ├── 00_开发执行总纲.md        # 开发分包 (WP-00~17, WP-A1~A5)、勘误表与验收门禁总纲
│   ├── 02_系统架构与数值_v6.md   # 核心数学模型、架构分层、信贷/转生/存档规格
│   ├── 03_美术风格圣经_v1.0.md   # 「镀金债契·骨白版画」视觉规范与四通道着色协议
│   ├── 04_美术资产管线_v1.1.md   # AI 母图生成、四通道打包、7 项量化质检与溯源台账规范
│   └── verification_log.md      # 引擎特性、OpenAI 条款与许可证实测核验记录 ([V-01]~[V-04])
├── autoload/                    # 全局入口单例 (Game.gd)
├── core/                        # 纯数学与随机基础设施 (Num.gd, SimRng.gd, Clock.gd)
├── simulation/                  # 零引擎节点依赖的 10Hz 确定性模拟核心 (战斗/掉落/词条/信贷/科技/转生)
├── content/                     # 装备槽位、词条池、怪物种族、Boss 机制与科技节点定义
├── offline/                     # 离线收益折算与时钟回拨防护 (OfflineCalc.gd)
├── persistence/                 # 版本化 JSON 序列化与 .tmp/.bak 原子存档服务 (SaveService.gd)
├── presentation/                # 表现事件总线、对象池、战利品喷泉、飘字层、程序化音效与版画精灵节点
├── platform/                    # 桌面无边框窗口管理、老板键、迷你条与多屏边界保护 (DesktopWindow.gd)
├── ui/                          # 360×480 主界面与抽屉面板 (装备背包/词条过滤/信贷账本/科技树/转生祭坛)
├── assets/                      # 【进包正式资产】仅存放经 verify_manifest.py 校验通过的无损资产
│   ├── art/
│   │   ├── monsters/            # 怪物四通道版画数据纹理 (.png + 防 sRGB 篡改 .import)
│   │   ├── bosses/              # 深渊领主 Boss 四通道版画数据纹理
│   │   ├── items/               # 六大装备槽位四通道版画图标纹理
│   │   ├── vfx/                 # 16 帧灰度爆炸特效图集与元数据
│   │   └── shaders/             # 5 个核心 Shader (palette_subject / loot_beam / sigil_ring / ground_slam / afterimage)
│   └── fonts/                   # Noto Serif SC 开源衬线字体子集配置
├── art_source/                  # 【不进包源资产库】含 .gdignore，绝不进入导出 .pck
│   ├── manifest.csv             # 全库唯一美术资产 SHA-256 与工具链溯源台账 (pre-commit 强制校验)
│   ├── licenses/                # LICENSES.csv 与许可证快照凭证 (proofs/、texts/)
│   ├── prompts/                 # 风格锁与全部正式资产 YAML 生成提示词定义
│   ├── anchors/                 # [Git LFS] 冻结的四大品类视觉锚点母图与打包参考图
│   ├── raw/                     # [Git LFS] OpenAI 生成的原始高分辨率母图归档
│   ├── rejected/                # [Git LFS] 未通过量化质检的退稿样本归档
│   └── thirdparty_raw/          # [.gitignore 排除] 本地第三方原始未加工素材缓存（严禁入库）
├── tools/                       # 数值仿真与美术自动化管线工具
│   ├── curve_sim.gd             # Gate-1 三剧本×30种子数值曲线仿真器
│   ├── art/                     # 美术生成、四通道打包、7项量化QA、联排检视板与 manifest 门禁脚本
│   └── out/                     # Gate-1 数值报告、实机验收截图与资产 QA 检视板 (含 .gdignore)
└── tests/                       # 17 个 Headless 自动化单元与集成测试套件 (run_all.gd)
```

### 美术资产三级隔离与 Pre-commit 强门禁

- **进包层（`assets/art/`）**：仅允许无损 `.png` / `.svg` 及配套 `.gdshader` 进入；所有数据纹理 `.png.import` 强制锁定 `compress/mode=0`、`mipmaps/generate=true`、`detect_3d/compress_to=0`、`compress/channel_pack=1`，防止引擎 sRGB 转换破坏四通道掩码。
- **溯源层（`art_source/`）**：通过 `art_source/.gdignore` 与游戏运行包物理隔离；大尺寸母图统一由 **Git LFS** 追踪；每次 `git commit` 自动触发 `tools/art/verify_manifest.py` 校验全部文件的实时 SHA-256、工具链版本、QA `PASS` 状态与许可证关联。
- **禁入层（`art_source/thirdparty_raw/` & `.env`）**：由 `.gitignore` 严格拦截，确保第三方未加工原始素材与任何 API 密钥零入库。

---

## 4. 环境依赖与常用命令

### 环境要求

- **Godot Engine**：`4.7.2-stable` 标准版（Standard Win64，非 `.NET` 版）
- **Python**：`>= 3.11`（运行美术管线与门禁脚本，依赖：`Pillow`、`numpy`、`scikit-image`、`opencv-python-headless`、`openai`、`pyyaml`）
- **Git & Git LFS**：`git >= 2.40`、`git-lfs >= 3.0`（克隆大尺寸源母图需执行 `git lfs pull`）
- **Node.js**：`>= 20`（仅重新离线渲染 PixelFX 原始帧序列时可选使用）

### 1) 启动桌面实机小窗

```powershell
# 使用 Godot 4.7.2 启动桌面常驻 360×480 透明小窗
& "F:\Godot\4.7.2\Godot_v4.7.2-stable_win64.exe" --path "F:\挂机游戏制作"
```

### 2) 运行全量 17 套件 Headless 自动化测试

```powershell
& "F:\Godot\4.7.2\Godot_v4.7.2-stable_win64_console.exe" --headless --path "F:\挂机游戏制作" --script res://tests/run_all.gd
```

测试覆盖：`Num` 大数运算、`Balance` 数值模型、`CombatSim` 10,000 ticks 确定性哈希、掉落与 24 格背包、净财富钱包、表现层对象池与音效预算、词条解析器与四重防递归保险、信贷溢价与自动抵扣、6 节点科技树、100 层过路费与护盾机制、灵魂转生与原子存档离线结算、`curve_sim` 闸门、桌面窗口交互、词条 Shader VFX、D5/D6 UI 交互及正式版画美术集成（共 `17 / 17` 套件）。

### 3) 运行 Gate-1 数值曲线蒙特卡洛仿真

```powershell
& "F:\Godot\4.7.2\Godot_v4.7.2-stable_win64_console.exe" --headless --path "F:\挂机游戏制作" --script res://tools/curve_sim.gd -- --strict-gate
```

输出报告位于 [`tools/out/gate1_report.md`](tools/out/gate1_report.md) 及同目录 `s1_*.csv` ~ `s3_*.csv`。

### 4) 运行美术资产台账与合规门禁校验

```powershell
python tools/art/verify_manifest.py
```

若新克隆仓库后需在本地启用 Git 提交前自动门禁：

```powershell
Copy-Item tools/art/pre_commit_hook.sh .git/hooks/pre-commit -Force
```

### 5) 美术资产离线生成与四通道打包管线（可选）

> **安全提示**：调用 OpenAI 图像生成脚本前，请仅在本地环境变量或未被 Git 追踪的 `.env` 文件中配置 `OPENAI_API_KEY` 与预算上限 `ART_BUDGET_USD`（如 `ART_BUDGET_USD=15.00`），**严禁在代码、YAML 或提交记录中写入任何明文密钥**。游戏运行时 100% 离线，不包含任何网络或 AI API 调用。

```powershell
# 1. 先执行零扣费 Dry-run 校验提示词与预算护栏
python tools/art/gen_openai.py --prompt art_source/prompts/mon_demon_debtor.yaml --dry-run

# 2. 将原始母图转换为 R/G/B/A 四通道版画数据纹理
python tools/art/process_subject.py --input <raw.png> --category monster --output <packed.png>

# 3. 执行 7 项量化质检 (尺寸/孤立噪点/占比/质心/通道合法性/剪影熵/AI伪影) 并输出四联检视板
python tools/art/qa_report.py --raw <raw.png> --packed <packed.png> --category monster --out-prefix tools/out/qa_check

# 4. 导出至 assets/art/，自动生成防篡改 .import 并登记 art_source/manifest.csv
python tools/art/export.py --asset-id <id> --category monster --version v01 --raw <raw.png> --packed <packed.png> --qa-json tools/out/qa_check.json --prompt-file <prompt.yaml> --source-type openai --license-id LIC-OPENAI-01
```

---

## 5. 第三方开源许可与 AI 生成资产合规声明

本项目严格遵守开源软件许可与数字发行平台（如 Steam）关于预生成 AI 资产的披露规范，完整声明与许可证全文见根目录 [`third_party_notices.txt`](third_party_notices.txt) 与 [`art_source/licenses/LICENSES.csv`](art_source/licenses/LICENSES.csv)：

1. **PixelFX 爆炸特效序列（MIT License）**
   - 来源：[`patch-gg/pixelfx`](https://github.com/patch-gg/pixelfx)（锁定 Commit `5294518ce7c72e48b6100a744596e0acf57f2826`），仅采用 `src/fx/explosions/small-explosion.js`（改编自 Hugo Duprez / Sprite Fusion 开源特效，MIT 许可）经 `fx_normalize.py` 归一化的 16 帧灰度遮罩图集；
   - 上游仓库 `gallery/fonts/` 下的专有字体 `PatchPixel` **已严格排除，未进入本仓库任何目录**。
2. **Noto Serif SC 字体（SIL Open Font License 1.1）**
   - 来源：Google Fonts Noto Serif SC，遵循 SIL OFL 1.1 协议随包分发。
3. **预生成美术底图说明（Pre-Generated AI Content Disclosure）**
   - `assets/art/{monsters,bosses,items}/` 下的 10 件主体资产底图由项目组在研发期通过 `tools/art/gen_openai.py`（OpenAI Images API，商业使用权利归属见 `art_source/licenses/proofs/openai_terms_2026.txt`）基于原创版画提示词离线生成，提示词不含任何在世艺术家姓名或第三方受版权保护 IP；
   - 所有底图均经项目自研确定性算法（`process_subject.py` 形态学去底、墨线/阴影/鎏金分频提取与四通道编码）加工并人工审核冻结，**客户端运行时无任何生成式 AI 调用**。
