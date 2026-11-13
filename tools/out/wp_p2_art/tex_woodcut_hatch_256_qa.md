# 美术资产量化质检报告 (PASS)

- **质检工具**: `qa_report.py@1.1.0`
- **生成时间**: `2026-11-13T05:16:04.973176+00:00`
- **待检文件**: `tools\out\wp_p2_art\tex_woodcut_hatch_256_packed.png`
- **文件 SHA-256**: `ba52943d0bbabf0191cd6532cfb5671ad82a6cca931c90677ed6363e9ff542d0`
- **资产类别**: `texture` (`accent=none`)
- **综合结论**: **PASS** (`5 / 5` 项通过)

## 逐项量化指标

| 检查码 | 检查项 | 结果 | 实测值 | 规范阈值 |
|---|---|---|---|---|
| `DIM_SINGLE_CH` | 256x256 单通道 (L/R8) 无损格式 | **PASS** | 256x256 (L) | 256x256 (L) |
| `BINARY_TWO_TONE` | 严格二值化木刻刀痕 (仅 0 与 255) | **PASS** | unique=[0, 255] | unique == [0, 255] |
| `HATCH_DUTY` | 木刻排线刻痕面积占空比 | **PASS** | 36.64% | 18.0% ~ 58.0% |
| `SEAMLESS_TILE` | 四向平铺接缝连续性检测 | **PASS** | seamX=15.2%(+0.0%), seamY=14.5%(+0.0%) | 接缝跳变超额 <= 5.0% |
| `STROKE_COARSENESS` | 排线中位刀宽与零碎杂点检测 | **PASS** | 中位线宽=4.65px, <4px碎点=0 | 中位线宽>=1.50px, <4px碎点=0 |
