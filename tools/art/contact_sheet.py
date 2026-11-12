#!/usr/bin/env python3
"""
《桌面破坏神》美术资产多维检视联系表生成工具 (contact_sheet.py)
版本: 1.1.0
依据:
  - docs/00_开发执行总纲.md (WP-A1)
  - docs/03_美术风格圣经_v1.0.md (§02.1 360x480 小窗布局、§05 六、64px/72px 联系表、§07 V1 小尺寸轮廓)
  - docs/04_美术资产管线_v1.1.md (§1.2 四通道拆解、§1.3 财富压力可视化状态)

生成内容:
  - 原图 vs R(骨白) / G(族群点缀) / B(镀金遮罩) / A(闭合剪影) 四通道独立拆解
  - 1:1 母版着色还原 vs 囤钱增亮 (Δh=+0.48) vs 负债剥落 (Δh=-0.40) 三态对比
  - 360x480 桌面小窗实景比例面板 (176x220 主怪卡 + 右侧 2 张 72x90 排队卡 + 64px/48px/32px 小尺寸剪影对比)
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageFont

THIS_DIR = Path(__file__).resolve().parent
if str(THIS_DIR) not in sys.path:
    sys.path.insert(0, str(THIS_DIR))

from process_subject import AccentFamilyType, CategoryType, PALETTE_RGB, render_shader_preview  # noqa: E402

TOOL_NAME: str = "contact_sheet.py"
TOOL_VERSION: str = "1.1.0"


def _make_checkerboard(w: int, h: int, tile: int = 12) -> np.ndarray:
    yy, xx = np.mgrid[0:h, 0:w]
    parity = ((xx // tile) + (yy // tile)) % 2
    c1 = np.array([34, 34, 42], dtype=np.uint8)
    c2 = np.array([50, 50, 60], dtype=np.uint8)
    return np.where(parity[..., None] == 0, c1, c2)


def _fit_into_box(img_rgb_or_rgba: np.ndarray, box_w: int, box_h: int, bg_rgb: tuple[int, int, int]) -> Image.Image:
    ih, iw = img_rgb_or_rgba.shape[:2]
    scale = min(float(box_w - 16) / max(1.0, float(iw)), float(box_h - 16) / max(1.0, float(ih)))
    nw = max(1, int(round(iw * scale)))
    nh = max(1, int(round(ih * scale)))
    interp = cv2.INTER_AREA if scale < 1.0 else cv2.INTER_NEAREST
    resized = cv2.resize(img_rgb_or_rgba, (nw, nh), interpolation=interp)

    canvas = Image.new("RGBA", (box_w, box_h), (*bg_rgb, 255))
    ox = (box_w - nw) // 2
    oy = (box_h - nh) // 2
    if resized.shape[2] == 4:
        fg_pil = Image.fromarray(resized, mode="RGBA")
        canvas.alpha_composite(fg_pil, (ox, oy))
    else:
        fg_pil = Image.fromarray(resized, mode="RGB").convert("RGBA")
        canvas.alpha_composite(fg_pil, (ox, oy))
    return canvas


def _render_channel_tile(mask_u8: np.ndarray, alpha_u8: np.ndarray, fg_color: tuple[int, int, int]) -> np.ndarray:
    h, w = mask_u8.shape[:2]
    bg = _make_checkerboard(w, h, tile=10).astype(np.float32)
    ink = np.array(PALETTE_RGB["ink"], dtype=np.float32)
    col = np.array(fg_color, dtype=np.float32)

    a = alpha_u8.astype(np.float32) / 255.0
    m = mask_u8.astype(np.float32) / 255.0
    inside = ink[None, None, :] * (1.0 - m[..., None]) + col[None, None, :] * m[..., None]
    comp = bg * (1.0 - a[..., None]) + inside * a[..., None]
    return np.clip(np.round(comp), 0, 255).astype(np.uint8)


def _build_small_window_mockup(
    packed_rgba: np.ndarray,
    category: CategoryType,
    accent_family: AccentFamilyType,
) -> Image.Image:
    """
    严格按 docs/03 §02.1 还原 360x480 桌面小窗比例：
      - 窗底 #0E0F14, 卡底 #16161C, 旧金框 #B08D57
      - 主怪卡 176x220 (左中) + 右侧 2 张排队卡 72x90 (上下排列)
      - 底部 6 个 48x48 装备槽 + 掉落地面 28x28 图标预览
    """
    win = Image.new("RGBA", (360, 480), (14, 15, 20, 255))  # #0E0F14
    draw = ImageDraw.Draw(win)
    # 外框 1px 描边
    draw.rounded_rectangle([0, 0, 359, 479], radius=12, outline=(176, 141, 87, 110), width=1)
    # 标题栏 0..24 与 层数/血条区 24..64
    draw.line([(0, 24), (359, 24)], fill=(58, 58, 66, 180), width=1)
    draw.rectangle([16, 36, 344, 46], fill=(22, 22, 28, 255), outline=(176, 141, 87, 160), width=1)
    draw.rectangle([17, 37, 260, 45], fill=(122, 15, 20, 255))

    preview_transparent = render_shader_preview(
        packed_rgba,
        accent_family=accent_family,
        wealth_pressure=0.0,
        on_card_bg=False,
        with_outline=True,
    )

    if category == "boss":
        # Boss 卡 208x260 居中 (docs/03 §02.1)
        bx, by, bw, bh = 76, 64, 208, 260
        draw.rounded_rectangle([bx, by, bx + bw, by + bh], radius=4, fill=(22, 22, 28, 255), outline=(217, 178, 111, 220), width=2)
        boss_disp = cv2.resize(preview_transparent, (bw, bh), interpolation=cv2.INTER_AREA)
        win.alpha_composite(Image.fromarray(boss_disp, mode="RGBA"), (bx, by))
    else:
        # 主怪卡 176x220 + 右侧 2 张排队卡 72x90
        mx, my, mw, mh = 24, 78, 176, 220
        draw.rounded_rectangle([mx, my, mx + mw, my + mh], radius=4, fill=(22, 22, 28, 255), outline=(176, 141, 87, 200), width=1)
        q1x, q1y, qw, qh = 240, 88, 72, 90
        q2x, q2y = 240, 196
        draw.rounded_rectangle([q1x, q1y, q1x + qw, q1y + qh], radius=3, fill=(22, 22, 28, 255), outline=(58, 58, 66, 220), width=1)
        draw.rounded_rectangle([q2x, q2y, q2x + qw, q2y + qh], radius=3, fill=(22, 22, 28, 255), outline=(58, 58, 66, 220), width=1)

        if category == "monster":
            main_disp = cv2.resize(preview_transparent, (mw, mh), interpolation=cv2.INTER_AREA)
            queue_disp = cv2.resize(preview_transparent, (qw, qh), interpolation=cv2.INTER_AREA)
            win.alpha_composite(Image.fromarray(main_disp, mode="RGBA"), (mx, my))
            win.alpha_composite(Image.fromarray(queue_disp, mode="RGBA"), (q1x, q1y))
            win.alpha_composite(Image.fromarray(queue_disp, mode="RGBA"), (q2x, q2y))

    # 掉落地面带 324..392 & HUD 带 392..420
    draw.line([(12, 324), (348, 324)], fill=(58, 58, 66, 120), width=1)
    draw.rectangle([12, 392, 348, 416], fill=(22, 22, 28, 220), outline=(58, 58, 66, 160), width=1)

    if category in ("icon", "prop"):
        # 在掉落地面画 28x28 图标 + 暗金光柱示意
        drop_28 = cv2.resize(preview_transparent, (28, 28), interpolation=cv2.INTER_AREA)
        draw.line([(180, 230), (180, 356)], fill=(255, 159, 26, 220), width=2)
        win.alpha_composite(Image.fromarray(drop_28, mode="RGBA"), (166, 348))

    # 底部 6 个 48x48 装备槽 (420..468)
    slot_x0 = 16
    for i in range(6):
        sx = slot_x0 + i * (48 + 8)
        sy = 424
        border_col = (255, 159, 26, 220) if (category == "icon" and i == 0) else (58, 58, 66, 220)
        draw.rounded_rectangle([sx, sy, sx + 48, sy + 48], radius=3, fill=(22, 22, 28, 255), outline=border_col, width=1)
        if category in ("icon", "prop") and i < 3:
            slot_48 = cv2.resize(preview_transparent, (44, 44), interpolation=cv2.INTER_AREA)
            win.alpha_composite(Image.fromarray(slot_48, mode="RGBA"), (sx + 2, sy + 2))

    return win


def generate_contact_sheet(
    packed_path: Path,
    out_path: Path,
    category: CategoryType = "monster",
    accent_family: AccentFamilyType = "auto",
    raw_path: Path | None = None,
    anchor_path: Path | None = None,
) -> Path:
    if not packed_path.exists():
        raise FileNotFoundError(f"找不到四通道 PNG: {packed_path}")

    packed_rgba = np.array(Image.open(packed_path).convert("RGBA"), dtype=np.uint8)
    r_ch, g_ch, b_ch, a_ch = (
        packed_rgba[:, :, 0],
        packed_rgba[:, :, 1],
        packed_rgba[:, :, 2],
        packed_rgba[:, :, 3],
    )

    if raw_path is not None and raw_path.exists():
        raw_arr = np.array(Image.open(raw_path).convert("RGB"), dtype=np.uint8)
    else:
        raw_arr = render_shader_preview(packed_rgba, accent_family=accent_family, on_card_bg=True)[:, :, :3]

    # 联系表总画布: 1560 x 980
    sheet_w, sheet_h = 1560, 980
    sheet = Image.new("RGBA", (sheet_w, sheet_h), (14, 15, 20, 255))
    draw = ImageDraw.Draw(sheet)
    font = ImageFont.load_default()

    cell_w, cell_h = 260, 340
    top_y = 48
    gap_x = 24

    # 第一排: 原图 + R / G / B / A 四通道拆解
    r_tile = _render_channel_tile(r_ch, a_ch, PALETTE_RGB["bone"])
    g_tile = _render_channel_tile(g_ch, a_ch, PALETTE_RGB.get(accent_family, PALETTE_RGB["auto"]))
    b_tile = _render_channel_tile(b_ch, a_ch, PALETTE_RGB["gold"])
    a_sil = _render_channel_tile(np.full_like(a_ch, 255), a_ch, (232, 220, 192))

    row1_items: list[tuple[str, np.ndarray]] = [
        ("1. RAW INPUT (Gray BG)", raw_arr),
        ("2. R-CHAN (Bone White)", r_tile),
        ("3. G-CHAN (Family Accent)", g_tile),
        ("4. B-CHAN (Gold Motif)", b_tile),
        ("5. A-CHAN (Silhouette)", a_sil),
    ]

    for idx, (label, arr) in enumerate(row1_items):
        cx = 28 + idx * (cell_w + gap_x)
        draw.text((cx, top_y - 20), label, fill=(232, 220, 192, 255), font=font)
        tile_img = _fit_into_box(arr, cell_w, cell_h, (22, 22, 28))
        sheet.alpha_composite(tile_img, (cx, top_y))
        draw.rectangle([cx, top_y, cx + cell_w, top_y + cell_h], outline=(58, 58, 66, 255), width=1)

    # 第二排左半: 常态 / 囤钱(+0.48) / 负债(-0.40) 三态 1:1 还原 + 小尺寸剪影 (72x90 / 64x64 / 48x48 / 32x32)
    row2_y = 440
    prev_norm = render_shader_preview(packed_rgba, accent_family=accent_family, wealth_pressure=0.0, on_card_bg=True)
    prev_rich = render_shader_preview(packed_rgba, accent_family=accent_family, wealth_pressure=0.477, on_card_bg=True)
    prev_debt = render_shader_preview(packed_rgba, accent_family=accent_family, wealth_pressure=-0.398, on_card_bg=True)

    row2_states: list[tuple[str, np.ndarray]] = [
        ("6. SHADER 1:1 (Normal dH=0)", prev_norm),
        ("7. HOARDING (Rich dH=+0.48)", prev_rich),
        ("8. IN DEBT (Peeled dH=-0.40)", prev_debt),
    ]

    for idx, (label, arr) in enumerate(row2_states):
        cx = 28 + idx * (cell_w + gap_x)
        draw.text((cx, row2_y - 20), label, fill=(217, 178, 111, 255), font=font)
        tile_img = _fit_into_box(arr, cell_w, 480, (22, 22, 28))
        sheet.alpha_composite(tile_img, (cx, row2_y))
        draw.rectangle([cx, row2_y, cx + cell_w, row2_y + 480], outline=(176, 141, 87, 180), width=1)

    # 第四栏: V1 多级小尺寸缩略与纯黑剪影测试 (72x90, 64x64, 48x48, 32x32) + 可选锚点对比
    col4_x = 28 + 3 * (cell_w + gap_x)
    draw.text((col4_x, row2_y - 20), "9. V1 THUMB & SILHOUETTE", fill=(232, 220, 192, 255), font=font)
    draw.rectangle([col4_x, row2_y, col4_x + cell_w, row2_y + 480], fill=(22, 22, 28, 255), outline=(58, 58, 66, 255), width=1)

    scales: list[tuple[str, int, int]] = [
        ("72x90 Queue", 72, 90),
        ("64x64 Thumb", 64, 64),
        ("48x48 Sil", 48, 48),
        ("32x32 Sil", 32, 32),
    ]
    cur_y = row2_y + 18
    pure_black_sil = np.zeros_like(packed_rgba)
    pure_black_sil[:, :, :3] = np.where((a_ch >= 128)[..., None], np.array([11, 10, 12], dtype=np.uint8), np.array([232, 220, 192], dtype=np.uint8))
    pure_black_sil[:, :, 3] = 255

    for s_label, sw, sh in scales:
        draw.text((col4_x + 14, cur_y), s_label, fill=(184, 168, 136, 255), font=font)
        col_thumb = cv2.resize(prev_norm, (sw, sh), interpolation=cv2.INTER_AREA)
        sil_thumb = cv2.resize(pure_black_sil, (sw, sh), interpolation=cv2.INTER_AREA)
        sheet.alpha_composite(Image.fromarray(col_thumb, mode="RGBA"), (col4_x + 98, cur_y))
        draw.rectangle([col4_x + 98, cur_y, col4_x + 98 + sw, cur_y + sh], outline=(110, 106, 102, 180), width=1)
        sheet.alpha_composite(Image.fromarray(sil_thumb, mode="RGBA"), (col4_x + 182, cur_y))
        draw.rectangle([col4_x + 182, cur_y, col4_x + 182 + sw, cur_y + sh], outline=(110, 106, 102, 180), width=1)
        cur_y += max(sh, 36) + 18

    if anchor_path is not None and anchor_path.exists():
        anc_rgba = np.array(Image.open(anchor_path).convert("RGBA"), dtype=np.uint8)
        anc_prev = render_shader_preview(anc_rgba, accent_family=accent_family, on_card_bg=True)
        anc_thumb = cv2.resize(anc_prev, (72, 90), interpolation=cv2.INTER_AREA)
        draw.text((col4_x + 14, cur_y), "Anchor 72x90", fill=(217, 178, 111, 255), font=font)
        sheet.alpha_composite(Image.fromarray(anc_thumb, mode="RGBA"), (col4_x + 120, cur_y))

    # 第五栏: 360x480 实景小窗 1:1 镶嵌
    win_x = 28 + 4 * (cell_w + gap_x)
    draw.text((win_x, row2_y - 20), "10. 360x480 WINDOW MOCKUP (1:1)", fill=(217, 178, 111, 255), font=font)
    win_mockup = _build_small_window_mockup(packed_rgba, category=category, accent_family=accent_family)
    sheet.alpha_composite(win_mockup, (win_x, row2_y))

    out_path.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(out_path, format="PNG", compress_level=9)
    return out_path


def build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="contact_sheet.py",
        description="《桌面破坏神》生成原图 / 四通道拆解 / 1:1 三态着色 / 360x480 小窗实景对比联系表 (PNG)",
    )
    parser.add_argument("--packed", type=Path, required=True, help="四通道打包后的 PNG 路径")
    parser.add_argument("--out", type=Path, required=True, help="输出联系表 PNG 路径")
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
        help="族群油墨点缀色 (默认: auto)",
    )
    parser.add_argument("--raw", type=Path, default=None, help="可选：原始灰底生成图路径")
    parser.add_argument("--anchor", type=Path, default=None, help="可选：冻结锚点四通道 PNG 路径，用于并排对比")
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_arg_parser()
    args = parser.parse_args(argv)

    saved = generate_contact_sheet(
        packed_path=args.packed,
        out_path=args.out,
        category=args.category,
        accent_family=args.accent_family,
        raw_path=args.raw,
        anchor_path=args.anchor,
    )
    print(f"[+] 检视联系表已生成: {saved}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
