#!/usr/bin/env python3
"""
《桌面破坏神》美术资产自动化量化质检工具 (qa_report.py)
版本: 1.1.0
依据:
  - docs/03_美术风格圣经_v1.0.md (§02.2–02.4, §05 四、跑偏判定, §07 V1–V5 可量化验收项)
  - docs/04_美术资产管线_v1.1.md (§1.2 四通道面积上限: G <= 6%, B <= 12%)
  - docs/verification_log.md ([风格方向板 v1] 评审纠偏: 72px 缩略防发灰检测)

输出: JSON 与 Markdown 双格式量化质检报告，全部检查项通过时 qa_status="PASS" (退出码 0)，否则 "FAIL" (退出码 1)。
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import cv2
import numpy as np
from PIL import Image
from skimage.morphology import skeletonize

# 确保可从任意工作目录导入同目录下的 process_subject
THIS_DIR = Path(__file__).resolve().parent
if str(THIS_DIR) not in sys.path:
    sys.path.insert(0, str(THIS_DIR))

from process_subject import AccentFamilyType, CategoryType, compute_sha256, render_shader_preview  # noqa: E402

TOOL_NAME: str = "qa_report.py"
TOOL_VERSION: str = "1.1.0"


@dataclass
class CheckItemResult:
    code: str
    name: str
    passed: bool
    measured: str
    threshold: str
    details: dict[str, Any]


@dataclass(frozen=True)
class QaThresholds:
    expected_w: int
    expected_h: int
    display_w: int
    display_h: int
    thumb_w: int
    thumb_h: int
    ink_min: float
    ink_max: float
    g_cap: float
    b_cap: float
    height_min: float
    height_max: float
    center_tol: float
    foot_min: float
    foot_max: float
    is_square_centered: bool


QA_SPECS: dict[str, QaThresholds] = {
    "monster": QaThresholds(
        expected_w=352,
        expected_h=440,
        display_w=176,
        display_h=220,
        thumb_w=72,
        thumb_h=90,
        ink_min=0.35,
        ink_max=0.55,
        g_cap=0.06,
        b_cap=0.12,
        height_min=0.82,
        height_max=0.90,
        center_tol=0.04,
        foot_min=0.88,
        foot_max=0.96,
        is_square_centered=False,
    ),
    "boss": QaThresholds(
        expected_w=416,
        expected_h=520,
        display_w=208,
        display_h=260,
        thumb_w=72,
        thumb_h=90,
        ink_min=0.50,
        ink_max=0.60,
        g_cap=0.15,
        b_cap=0.12,
        height_min=0.90,
        height_max=0.94,
        center_tol=0.04,
        foot_min=0.90,
        foot_max=0.98,
        is_square_centered=False,
    ),
    "icon": QaThresholds(
        expected_w=96,
        expected_h=96,
        display_w=48,
        display_h=48,
        thumb_w=32,
        thumb_h=32,
        ink_min=0.30,
        ink_max=0.50,
        g_cap=0.08,
        b_cap=0.12,
        height_min=0.72,
        height_max=0.90,
        center_tol=0.06,
        foot_min=0.0,
        foot_max=1.0,
        is_square_centered=True,
    ),
    "prop": QaThresholds(
        expected_w=256,
        expected_h=256,
        display_w=128,
        display_h=128,
        thumb_w=64,
        thumb_h=64,
        ink_min=0.25,
        ink_max=0.60,
        g_cap=0.10,
        b_cap=0.18,
        height_min=0.70,
        height_max=0.92,
        center_tol=0.06,
        foot_min=0.0,
        foot_max=1.0,
        is_square_centered=True,
    ),
}


def evaluate_packed_asset(
    packed_path: Path,
    category: CategoryType = "monster",
    accent_family: AccentFamilyType = "auto",
    raw_path: Path | None = None,
) -> dict[str, Any]:
    if not packed_path.exists():
        raise FileNotFoundError(f"找不到待质检的四通道 PNG 文件: {packed_path}")
    if category not in QA_SPECS:
        raise ValueError(f"不支持的资产类别: {category}")

    spec = QA_SPECS[category]
    pil_img = Image.open(packed_path)
    img_mode = pil_img.mode
    rgba = np.array(pil_img.convert("RGBA"), dtype=np.uint8)
    h, w = rgba.shape[:2]

    checks: list[CheckItemResult] = []

    # 1. 尺寸与格式校验 (DIM)
    dim_ok = (img_mode == "RGBA") and (w == spec.expected_w) and (h == spec.expected_h)
    checks.append(
        CheckItemResult(
            code="DIM",
            name="母版尺寸与 RGBA 四通道无损格式",
            passed=dim_ok,
            measured=f"{w}x{h} ({img_mode})",
            threshold=f"{spec.expected_w}x{spec.expected_h} (RGBA)",
            details={"width": w, "height": h, "mode": img_mode},
        )
    )

    r_ch = rgba[:, :, 0]
    g_ch = rgba[:, :, 1]
    b_ch = rgba[:, :, 2]
    a_ch = rgba[:, :, 3]

    # 2. 透明边缘净度与孤立杂点检测 (ALPHA_CLEAN)
    border_pixels = np.concatenate([a_ch[0, :], a_ch[h - 1, :], a_ch[:, 0], a_ch[:, w - 1]])
    border_opaque_ratio = float((border_pixels >= 32).sum()) / max(1, len(border_pixels))
    nonzero_a = int((a_ch > 0).sum())
    semi_a_ratio = float(((a_ch > 0) & (a_ch < 255)).sum()) / max(1, nonzero_a)

    fg_bin = (a_ch >= 20).astype(np.uint8)
    min_speck_area = max(2, int(round(h * w * 0.0005)))
    n_lbl, _, st, _ = cv2.connectedComponentsWithStats(fg_bin, connectivity=8)
    tiny_specks = sum(1 for idx in range(1, n_lbl) if int(st[idx, cv2.CC_STAT_AREA]) < min_speck_area)

    alpha_ok = (border_opaque_ratio <= 0.02) and (semi_a_ratio <= 0.22) and (tiny_specks == 0) and (nonzero_a > 0)
    checks.append(
        CheckItemResult(
            code="ALPHA_CLEAN",
            name="透明边缘净度与零孤立杂点",
            measured=f"边界残留={border_opaque_ratio*100:.2f}%, 半透明边={semi_a_ratio*100:.1f}%, 杂点={tiny_specks}",
            threshold="边界残留<=2.0%, 半透明边<=22.0%, 杂点=0",
            passed=alpha_ok,
            details={
                "border_opaque_ratio": round(border_opaque_ratio, 5),
                "semi_transparent_edge_ratio": round(semi_a_ratio, 4),
                "tiny_specks_count": tiny_specks,
            },
        )
    )

    # 3. 四通道正交性与占比上限 (V2_CHANNEL_CAPS: docs/04 §1.2 & docs/03 §07 V2)
    fg = a_ch >= 128
    fg_count = max(1, int(fg.sum()))
    is_r = (r_ch >= 128) & fg
    is_g = (g_ch >= 128) & fg
    is_b = (b_ch >= 128) & fg
    is_ink = (~is_r) & (~is_g) & (~is_b) & fg

    overlap_count = int((((r_ch > 0) & (g_ch > 0)) | ((r_ch > 0) & (b_ch > 0)) | ((g_ch > 0) & (b_ch > 0))).sum())
    overlap_ratio = float(overlap_count) / fg_count
    r_ratio = float(is_r.sum()) / fg_count
    g_ratio = float(is_g.sum()) / fg_count
    b_ratio = float(is_b.sum()) / fg_count
    ink_ratio = float(is_ink.sum()) / fg_count

    chan_ok = (overlap_ratio <= 0.01) and (g_ratio <= spec.g_cap) and (b_ratio <= spec.b_cap)
    checks.append(
        CheckItemResult(
            code="V2_CHANNEL_CAPS",
            name="四通道正交分离与点缀/镀金面积上限",
            passed=chan_ok,
            measured=f"G点缀={g_ratio*100:.2f}%, B镀金={b_ratio*100:.2f}%, 通道混叠={overlap_ratio*100:.2f}%",
            threshold=f"G<={spec.g_cap*100:.1f}%, B<={spec.b_cap*100:.1f}%, 混叠<=1.0%",
            details={
                "r_bone_ratio": round(r_ratio, 4),
                "g_accent_ratio": round(g_ratio, 4),
                "b_gold_ratio": round(b_ratio, 4),
                "channel_overlap_ratio": round(overlap_ratio, 5),
            },
        )
    )

    # 4. 墨黑体量占比 (V4_INK_MASS: docs/03 §07 V4)
    ink_ok = spec.ink_min <= ink_ratio <= spec.ink_max
    checks.append(
        CheckItemResult(
            code="V4_INK_MASS",
            name="主体内部墨黑面积占比 (V4)",
            passed=ink_ok,
            measured=f"{ink_ratio*100:.2f}%",
            threshold=f"{spec.ink_min*100:.0f}% ~ {spec.ink_max*100:.0f}%",
            details={"ink_ratio": round(ink_ratio, 4)},
        )
    )

    # 5. 显示尺寸刀痕线宽与防铜版细线检测 (V3_LINE_WIDTH: docs/03 §07 V3)
    disp_rgba = cv2.resize(rgba, (spec.display_w, spec.display_h), interpolation=cv2.INTER_AREA)
    disp_fg = disp_rgba[:, :, 3] >= 128
    disp_ink = (
        disp_fg
        & (disp_rgba[:, :, 0] < 128)
        & (disp_rgba[:, :, 1] < 128)
        & (disp_rgba[:, :, 2] < 128)
    ).astype(np.uint8)

    if int(disp_ink.sum()) > 0:
        dist_map = cv2.distanceTransform(disp_ink, cv2.DIST_L2, 5)
        skel = skeletonize(disp_ink > 0)
        skel_widths = dist_map[skel] * 2.0
        thin_ratio = float((skel_widths < 1.5).sum()) / max(1, len(skel_widths))
        median_width = float(np.median(skel_widths)) if len(skel_widths) > 0 else 0.0
    else:
        thin_ratio = 1.0
        median_width = 0.0

    line_ok = thin_ratio <= 0.15
    checks.append(
        CheckItemResult(
            code="V3_LINE_WIDTH",
            name="显示尺寸墨线宽度与防铜版细线检测 (V3)",
            passed=line_ok,
            measured=f"<1.5px细线占比={thin_ratio*100:.2f}%, 中位线宽={median_width:.2f}px (@{spec.display_w}x{spec.display_h})",
            threshold="<1.5px细线占比 <= 15.0%",
            details={
                "display_size": [spec.display_w, spec.display_h],
                "thin_line_lt_1_5px_ratio": round(thin_ratio, 4),
                "median_stroke_width_px": round(median_width, 2),
            },
        )
    )

    # 6. 构图包围盒、居中度与脚底线 (V5_COMPOSITION: docs/03 §02.2–02.4 & §07 V5)
    ys, xs = np.where(fg)
    if len(xs) > 0 and len(ys) > 0:
        x_min, x_max = int(xs.min()), int(xs.max()) + 1
        y_min, y_max = int(ys.min()), int(ys.max()) + 1
        w_ratio = float(x_max - x_min) / float(w)
        h_ratio = float(y_max - y_min) / float(h)
        cx_offset = abs(((x_min + x_max) * 0.5 / float(w)) - 0.5)
        cy_offset = abs(((y_min + y_max) * 0.5 / float(h)) - 0.5)
        foot_ratio = float(y_max) / float(h)
    else:
        w_ratio = h_ratio = foot_ratio = 0.0
        cx_offset = cy_offset = 1.0

    if spec.is_square_centered:
        span_ratio = max(w_ratio, h_ratio)
        comp_ok = (spec.height_min <= span_ratio <= spec.height_max) and (cx_offset <= spec.center_tol) and (cy_offset <= spec.center_tol)
        comp_measured = f"主跨度={span_ratio*100:.1f}%, 水平偏移={cx_offset*100:.1f}%, 垂直偏移={cy_offset*100:.1f}%"
        comp_thresh = f"主跨度 {spec.height_min*100:.0f}%~{spec.height_max*100:.0f}%, 居中偏移<={spec.center_tol*100:.0f}%"
    else:
        comp_ok = (
            (spec.height_min <= h_ratio <= spec.height_max)
            and (cx_offset <= spec.center_tol)
            and (spec.foot_min <= foot_ratio <= spec.foot_max)
        )
        comp_measured = f"高占比={h_ratio*100:.1f}%, 水平偏移={cx_offset*100:.1f}%, 脚底线={foot_ratio*100:.1f}%"
        comp_thresh = (
            f"高占比 {spec.height_min*100:.0f}%~{spec.height_max*100:.0f}%, "
            f"水平偏移<={spec.center_tol*100:.0f}%, 脚底线 {spec.foot_min*100:.0f}%~{spec.foot_max*100:.0f}%"
        )

    checks.append(
        CheckItemResult(
            code="V5_COMPOSITION",
            name="主体占比、居中公差与脚底基准线 (V5)",
            passed=comp_ok,
            measured=comp_measured,
            threshold=comp_thresh,
            details={
                "width_ratio": round(w_ratio, 4),
                "height_ratio": round(h_ratio, 4),
                "center_x_offset": round(cx_offset, 4),
                "center_y_offset": round(cy_offset, 4),
                "foot_line_ratio": round(foot_ratio, 4),
            },
        )
    )

    # 7. 小尺寸缩略图 (72x90 排队卡 / 32x32 图标) 辨识度与防灰糊检测 (V1_THUMB_READABILITY)
    # 注: 关闭外发光描边 (with_outline=False) 以免 40% 半透明骨白描边在 32x32/72x90 下被误计入内部灰糊;
    # 对角长剑 (03 §02.4 45° 对角) 与四肢分离骷髅 (03 §02.2) 的合法剪影占空比约为 12%~18%，故占空下限设为 10%
    preview_card = render_shader_preview(rgba, accent_family=accent_family, on_card_bg=True, with_outline=False)
    thumb_rgb = cv2.resize(preview_card[:, :, :3], (spec.thumb_w, spec.thumb_h), interpolation=cv2.INTER_AREA)
    thumb_alpha = cv2.resize(a_ch, (spec.thumb_w, spec.thumb_h), interpolation=cv2.INTER_AREA)
    thumb_b = cv2.resize(b_ch, (spec.thumb_w, spec.thumb_h), interpolation=cv2.INTER_AREA)
    thumb_g = cv2.resize(g_ch, (spec.thumb_w, spec.thumb_h), interpolation=cv2.INTER_AREA)

    thumb_fg = thumb_alpha >= 96
    thumb_core = thumb_alpha >= 160
    thumb_occ = float(thumb_fg.sum()) / float(spec.thumb_w * spec.thumb_h)

    thumb_luma = (
        0.299 * thumb_rgb[:, :, 0].astype(np.float32)
        + 0.587 * thumb_rgb[:, :, 1].astype(np.float32)
        + 0.114 * thumb_rgb[:, :, 2].astype(np.float32)
    )
    bw_fg = thumb_core & (thumb_b < 96) & (thumb_g < 96)
    bw_count = max(1, int(bw_fg.sum()))
    # 区分"锐利黑白边界的 1px 抗锯齿过渡" (3x3 局部跨度 >= 90) 与 "铜版细密排线坍缩成的平坦灰糊团" (局部跨度 < 90)
    k3 = np.ones((3, 3), dtype=np.uint8)
    local_luma_span = cv2.dilate(thumb_luma, k3) - cv2.erode(thumb_luma, k3)
    muddy_gray_ratio = float(
        ((thumb_luma >= 75.0) & (thumb_luma <= 165.0) & (local_luma_span < 90.0) & bw_fg).sum()
    ) / bw_count
    fg_rms_contrast = float(np.std(thumb_luma[thumb_fg] / 255.0)) if int(thumb_fg.sum()) > 1 else 0.0

    thumb_ok = (muddy_gray_ratio <= 0.25) and (fg_rms_contrast >= 0.22) and (thumb_occ >= 0.10)
    checks.append(
        CheckItemResult(
            code="V1_THUMB_READABILITY",
            name=f"小尺寸缩略 ({spec.thumb_w}x{spec.thumb_h}) 剪影对比度与防灰糊检测 (V1)",
            passed=thumb_ok,
            measured=f"灰糊团占比={muddy_gray_ratio*100:.1f}%, RMS对比度={fg_rms_contrast:.3f}, 剪影占空={thumb_occ*100:.1f}%",
            threshold="灰糊团占比<=25.0%, RMS对比度>=0.220, 剪影占空>=10.0%",
            details={
                "thumb_size": [spec.thumb_w, spec.thumb_h],
                "muddy_gray_ratio": round(muddy_gray_ratio, 4),
                "rms_contrast": round(fg_rms_contrast, 4),
                "silhouette_occupancy": round(thumb_occ, 4),
            },
        )
    )

    overall_pass = all(c.passed for c in checks)
    report: dict[str, Any] = {
        "tool": f"{TOOL_NAME}@{TOOL_VERSION}",
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "packed_path": str(packed_path),
        "packed_sha256": compute_sha256(packed_path),
        "raw_path": str(raw_path) if raw_path else None,
        "raw_sha256": compute_sha256(raw_path) if (raw_path and raw_path.exists()) else None,
        "category": category,
        "accent_family": accent_family,
        "qa_status": "PASS" if overall_pass else "FAIL",
        "passed_count": sum(1 for c in checks if c.passed),
        "total_checks": len(checks),
        "checks": [asdict(c) for c in checks],
    }
    return report


def format_markdown_report(report: dict[str, Any]) -> str:
    status_badge = "PASS" if report["qa_status"] == "PASS" else "FAIL"
    lines: list[str] = [
        f"# 美术资产量化质检报告 ({status_badge})",
        "",
        f"- **质检工具**: `{report['tool']}`",
        f"- **生成时间**: `{report['generated_at']}`",
        f"- **待检文件**: `{report['packed_path']}`",
        f"- **文件 SHA-256**: `{report['packed_sha256']}`",
        f"- **资产类别**: `{report['category']}` (`accent={report['accent_family']}`)",
        f"- **综合结论**: **{status_badge}** (`{report['passed_count']} / {report['total_checks']}` 项通过)",
        "",
        "## 逐项量化指标",
        "",
        "| 检查码 | 检查项 | 结果 | 实测值 | 规范阈值 |",
        "|---|---|---|---|---|",
    ]
    for chk in report["checks"]:
        mark = "PASS" if chk["passed"] else "FAIL"
        lines.append(f"| `{chk['code']}` | {chk['name']} | **{mark}** | {chk['measured']} | {chk['threshold']} |")
    lines.append("")
    return "\n".join(lines)


def build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="qa_report.py",
        description="《桌面破坏神》四通道木刻资产自动化质检工具（输出 JSON 与 Markdown 报告）",
    )
    parser.add_argument("--packed", type=Path, required=True, help="待质检的四通道打包 PNG 路径")
    parser.add_argument(
        "--category",
        type=str,
        default="monster",
        choices=["monster", "boss", "icon", "prop"],
        help="资产类别 (默认: monster)",
    )
    parser.add_argument(
        "--accent-family",
        type=str,
        default="auto",
        choices=["auto", "undead", "demon", "beast", "fallen_saint", "abyss", "none"],
        help="族群油墨色类别，用于还原小尺寸缩略预览对比度检测 (默认: auto)",
    )
    parser.add_argument("--raw", type=Path, default=None, help="可选：原始生成图路径，用于记录输入 SHA-256")
    parser.add_argument("--json-out", type=Path, default=None, help="输出 JSON 质检报告路径")
    parser.add_argument("--md-out", type=Path, default=None, help="输出 Markdown 质检报告路径")
    parser.add_argument("--report-only", action="store_true", help="即使质检未通过也返回退出码 0（仅生成报告）")
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_arg_parser()
    args = parser.parse_args(argv)

    report = evaluate_packed_asset(
        packed_path=args.packed,
        category=args.category,
        accent_family=args.accent_family,
        raw_path=args.raw,
    )

    if args.json_out is not None:
        args.json_out.parent.mkdir(parents=True, exist_ok=True)
        args.json_out.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")

    md_text = format_markdown_report(report)
    if args.md_out is not None:
        args.md_out.parent.mkdir(parents=True, exist_ok=True)
        args.md_out.write_text(md_text, encoding="utf-8")

    print(
        f"[{'+' if report['qa_status'] == 'PASS' else 'X'}] QA 结论: {report['qa_status']} "
        f"({report['passed_count']}/{report['total_checks']}) — {args.packed}"
    )
    for chk in report["checks"]:
        prefix = "PASS" if chk["passed"] else "FAIL"
        print(f"  [{prefix}] {chk['code']}: {chk['measured']}  (标准: {chk['threshold']})")

    if report["qa_status"] != "PASS" and not args.report_only:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
