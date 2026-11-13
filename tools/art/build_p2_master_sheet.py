#!/usr/bin/env python3
"""
《桌面破坏神》WP-P2-ART 阶段 2 扩充美术资产总览检视板生成器 (build_p2_master_sheet.py)
版本: 1.0.0
输出: tools/out/wp_p2_art_contact_sheet.png
覆盖全部 8 件阶段 2 新增正式美术资产:
  - 族群 4 普通怪物: mon_idol_scales_v01.png (352x440, 镀金圣像 · 堕圣族)
  - 族群 5 普通怪物: mon_cult_pawnbroker_v01.png (352x440, 典当教团 · 深渊族)
  - 稀有召唤 Boss : boss_rare_archon_v01.png (416x520, 契约大执政官)
  - 无缝木刻排线底纹: tex_woodcut_hatch_256_v01.png (256x256 单通道 R8, 含原图高度 + 二值母版 + 2x2 平铺 ≤15% 着色实景)
  - 专属暗金图标 #1 : uniq_weapon_thunder_blade_v01.png (96x96, 雷霆断债巨剑)
  - 专属暗金图标 #2 : uniq_trinket_usurer_scales_v01.png (96x96, 高利贷天平圣契)
  - 收藏召唤符文图标: col_rune_abyss_summon_v01.png (96x96, 深渊召唤石刻符文 · 纯几何刻痕)
  - 财富契约道具插图: prop_wealth_ledger_v01.png (96x96, 金币堆与债契账簿)
"""

from __future__ import annotations

import sys
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageFont

THIS_DIR = Path(__file__).resolve().parent
ROOT_DIR = THIS_DIR.parent.parent
if str(THIS_DIR) not in sys.path:
    sys.path.insert(0, str(THIS_DIR))

from process_subject import PALETTE_RGB, render_shader_preview  # noqa: E402
from qa_report import evaluate_packed_asset  # noqa: E402

PORTRAIT_ASSETS = [
    ("mon_idol_scales_v01", "Family 4 · Fallen Saint (#B08D57)", "monster", "fallen_saint", "assets/art/monsters/mon_idol_scales_v01.png"),
    ("mon_cult_pawnbroker_v01", "Family 5 · Abyss Pawn-Cult (#6A1B3A)", "monster", "abyss", "assets/art/monsters/mon_cult_pawnbroker_v01.png"),
    ("boss_rare_archon_v01", "Rare Boss · Covenant Archon (#6A1B3A)", "boss", "abyss", "assets/art/bosses/boss_rare_archon_v01.png"),
]

ICON_ASSETS = [
    ("uniq_weapon_thunder_blade_v01", "Unique 1 · Thunder Debt-Blade", "demon", "assets/art/items/uniq_weapon_thunder_blade_v01.png"),
    ("uniq_trinket_usurer_scales_v01", "Unique 2 · Usurer's Scales", "fallen_saint", "assets/art/items/uniq_trinket_usurer_scales_v01.png"),
    ("col_rune_abyss_summon_v01", "Collectible · Abyss Geometric Rune", "abyss", "assets/art/items/col_rune_abyss_summon_v01.png"),
    ("prop_wealth_ledger_v01", "Wealth Prop · Coins & Debt Ledger", "demon", "assets/art/items/prop_wealth_ledger_v01.png"),
]


def _paste_np(canvas: Image.Image, arr: np.ndarray, x: int, y: int) -> None:
    pil = Image.fromarray(arr, mode="RGBA" if arr.shape[2] == 4 else "RGB")
    if pil.mode == "RGBA":
        canvas.paste(pil, (x, y), pil)
    else:
        canvas.paste(pil, (x, y))


def _make_sil(rgba: np.ndarray, tw: int, th: int) -> np.ndarray:
    a = cv2.resize(rgba[:, :, 3], (tw, th), interpolation=cv2.INTER_AREA).astype(np.float32) / 255.0
    bg = np.array(PALETTE_RGB["bone"], dtype=np.float32)
    fg = np.array(PALETTE_RGB["ink"], dtype=np.float32)
    rgb = bg[None, None, :] * (1.0 - a[..., None]) + fg[None, None, :] * a[..., None]
    return np.clip(np.round(rgb), 0, 255).astype(np.uint8)


def build_p2_sheet(out_path: Path) -> int:
    W, H = 1920, 1160
    sheet = Image.new("RGB", (W, H), (14, 14, 19))
    draw = ImageDraw.Draw(sheet)
    font = ImageFont.load_default()

    # Header
    draw.rectangle([0, 0, W, 56], fill=(20, 20, 27))
    draw.line([0, 56, W, 56], fill=(201, 160, 78), width=2)
    draw.text(
        (24, 14),
        "DESKTOP DIABLO (360x480) - WP-P2-ART PHASE 2 WOODCUT ASSET & SEAMLESS HATCH MASTER SHEET (8/8 QA PASS)",
        fill=(232, 220, 192),
        font=font,
    )
    draw.text(
        (24, 34),
        "2 New Monster Families (Fallen Saint / Abyss Cult) + 1 Rare Summon Boss + 2 Unique Icons + 1 Geometric Rune + 1 Wealth Prop + 256x256 Seamless Hatch",
        fill=(165, 158, 145),
        font=font,
    )

    col_w = 456
    start_x = 24
    row1_y = 74

    # Row 1 Cols 1-3: Portraits
    for idx, (aid, subtitle, cat, fam, rel_p) in enumerate(PORTRAIT_ASSETS):
        x0 = start_x + idx * (col_w + 16)
        y0 = row1_y
        draw.rectangle([x0, y0, x0 + col_w, y0 + 530], fill=(22, 22, 28), outline=(58, 54, 48), width=1)
        draw.text((x0 + 12, y0 + 10), f"[{idx + 1}] {aid}", fill=(233, 196, 106), font=font)
        draw.text((x0 + 12, y0 + 26), subtitle, fill=(180, 174, 162), font=font)

        p_path = ROOT_DIR / rel_p
        rgba = np.array(Image.open(p_path).convert("RGBA"))
        qa = evaluate_packed_asset(p_path, category=cat, accent_family=fam)

        disp_w, disp_h = (208, 260) if cat == "boss" else (176, 220)
        sh_full = render_shader_preview(rgba, accent_family=fam, on_card_bg=True, with_outline=True)
        sh_disp = cv2.resize(sh_full[:, :, :3], (disp_w, disp_h), interpolation=cv2.INTER_AREA)
        sh_debt = render_shader_preview(rgba, accent_family=fam, wealth_pressure=-0.40, on_card_bg=True, with_outline=True)
        sh_debt_sm = cv2.resize(sh_debt[:, :, :3], (104, 130), interpolation=cv2.INTER_AREA)

        card_x = x0 + 14
        card_y = y0 + 52
        border_col = (201, 160, 78) if cat == "boss" else (72, 68, 60)
        draw.rectangle([card_x - 2, card_y - 2, card_x + disp_w + 2, card_y + disp_h + 2], outline=border_col, width=1)
        _paste_np(sheet, sh_disp, card_x, card_y)
        draw.text((card_x, card_y + disp_h + 6), f"1:1 Card ({disp_w}x{disp_h})", fill=(160, 155, 145), font=font)

        rx = x0 + 240
        q_thumb = cv2.resize(sh_full[:, :, :3], (72, 90), interpolation=cv2.INTER_AREA)
        q_sil = _make_sil(rgba, 72, 90)
        draw.rectangle([rx - 1, card_y - 1, rx + 72, card_y + 90], outline=(90, 86, 78))
        _paste_np(sheet, q_thumb, rx, card_y)
        _paste_np(sheet, q_sil, rx + 84, card_y)
        draw.text((rx, card_y + 94), "72x90 Queue & Sil", fill=(160, 155, 145), font=font)

        _paste_np(sheet, sh_debt_sm, rx, card_y + 116)
        draw.text((rx, card_y + 250), "Debt Peel (dH=-0.4)", fill=(160, 155, 145), font=font)

        chk_map = {c["code"]: c for c in qa["checks"]}
        d_v4 = chk_map["V4_INK_MASS"]["details"]
        d_v2 = chk_map["V2_CHANNEL_CAPS"]["details"]
        d_v1 = chk_map["V1_THUMB_READABILITY"]["details"]
        d_v3 = chk_map["V3_LINE_WIDTH"]["details"]
        d_v5 = chk_map["V5_COMPOSITION"]["details"]
        ink_str = f"ink={d_v4['ink_ratio']*100:.2f}% (bone={d_v2['r_bone_ratio']*100:.1f}%)"
        chan_str = f"G={d_v2['g_accent_ratio']*100:.2f}%, B={d_v2['b_gold_ratio']*100:.2f}%, ovlp={d_v2['channel_overlap_ratio']*100:.2f}%"
        v1_str = f"mush={d_v1['muddy_gray_ratio']*100:.1f}%, RMS={d_v1['rms_contrast']:.3f}, occ={d_v1['silhouette_occupancy']*100:.1f}%"
        v3_str = f"<1.5px={d_v3['thin_line_lt_1_5px_ratio']*100:.1f}%, medW={d_v3['median_stroke_width_px']:.2f}px"
        v5_str = f"H={d_v5['height_ratio']*100:.1f}%, dx={d_v5['center_x_offset']*100:.1f}%, foot={d_v5['foot_line_ratio']*100:.1f}%"
        badge_col = (78, 168, 92) if qa["qa_status"] == "PASS" else (210, 60, 60)
        draw.rectangle([x0 + 12, y0 + 356, x0 + col_w - 12, y0 + 516], fill=(17, 17, 22), outline=(44, 44, 54))
        draw.text((x0 + 20, y0 + 366), f"QA: {qa['qa_status']} ({qa['passed_count']}/{qa['total_checks']}) | Master {rgba.shape[1]}x{rgba.shape[0]}", fill=badge_col, font=font)
        draw.text((x0 + 20, y0 + 388), f"V4 Ink Mass : {ink_str}", fill=(220, 214, 200), font=font)
        draw.text((x0 + 20, y0 + 408), f"V2 Channels : {chan_str}", fill=(220, 214, 200), font=font)
        draw.text((x0 + 20, y0 + 428), f"V1 72px Rd  : {v1_str}", fill=(220, 214, 200), font=font)
        draw.text((x0 + 20, y0 + 448), f"V3 LineW    : {v3_str}", fill=(220, 214, 200), font=font)
        draw.text((x0 + 20, y0 + 468), f"V5 Framing  : {v5_str}", fill=(220, 214, 200), font=font)
        draw.text((x0 + 20, y0 + 490), f"res://{rel_p}", fill=(140, 150, 175), font=font)

    # Row 1 Col 4: Seamless Woodcut Hatch Texture (tex_woodcut_hatch_256_v01.png)
    tx0 = start_x + 3 * (col_w + 16)
    ty0 = row1_y
    draw.rectangle([tx0, ty0, tx0 + col_w, ty0 + 530], fill=(22, 22, 28), outline=(201, 160, 78), width=1)
    draw.text((tx0 + 12, ty0 + 10), "[4] tex_woodcut_hatch_256_v01", fill=(233, 196, 106), font=font)
    draw.text((tx0 + 12, ty0 + 26), "Seamless 256x256 Single-Ch R8 Binary Hatch (LIC-PROC-0001)", fill=(180, 174, 162), font=font)

    hatch_path = ROOT_DIR / "assets" / "art" / "textures" / "tex_woodcut_hatch_256_v01.png"
    raw_h_path = ROOT_DIR / "art_source" / "raw" / "tex_woodcut_hatch_256" / "height_stone_parchment_256.png"
    hatch_gray = np.array(Image.open(hatch_path).convert("L"), dtype=np.uint8)
    raw_h_gray = np.array(Image.open(raw_h_path).convert("L"), dtype=np.uint8)
    tqa = evaluate_packed_asset(hatch_path, category="texture")

    # 128x128 Height + 128x128 Binary Master + 160x260 2x2 Tiled Card Tint (12% opacity per 04 §3 #6)
    h_128 = np.repeat(cv2.resize(raw_h_gray, (124, 124), interpolation=cv2.INTER_AREA)[:, :, None], 3, axis=2)
    b_128 = np.repeat(cv2.resize(hatch_gray, (124, 124), interpolation=cv2.INTER_NEAREST)[:, :, None], 3, axis=2)
    _paste_np(sheet, h_128, tx0 + 14, ty0 + 52)
    draw.rectangle([tx0 + 13, ty0 + 51, tx0 + 138, ty0 + 176], outline=(90, 86, 78))
    draw.text((tx0 + 14, ty0 + 180), "Seamless HeightMap", fill=(160, 155, 145), font=font)

    _paste_np(sheet, b_128, tx0 + 14, ty0 + 202)
    draw.rectangle([tx0 + 13, ty0 + 201, tx0 + 138, ty0 + 326], outline=(90, 86, 78))
    draw.text((tx0 + 14, ty0 + 330), "256x256 R8 Binary", fill=(160, 155, 145), font=font)

    tiled_512 = np.tile(hatch_gray, (2, 2))[:260, :260].astype(np.float32) / 255.0
    card_base = np.array(PALETTE_RGB["card_bg"], dtype=np.float32)[None, None, :]
    bone_tint = np.array(PALETTE_RGB["bone"], dtype=np.float32)[None, None, :]
    in_game_tint = np.clip(np.round(card_base + (bone_tint - card_base) * (0.12 * tiled_512[..., None])), 0, 255).astype(np.uint8)
    _paste_np(sheet, in_game_tint, tx0 + 170, ty0 + 52)
    draw.rectangle([tx0 + 169, ty0 + 51, tx0 + 430, ty0 + 312], outline=(201, 160, 78))
    draw.text((tx0 + 170, ty0 + 318), "2x2 Seamless Tile @ 12% Card Tint", fill=(160, 155, 145), font=font)

    tchk = {c["code"]: c for c in tqa["checks"]}
    tbadge = (78, 168, 92) if tqa["qa_status"] == "PASS" else (210, 60, 60)
    draw.rectangle([tx0 + 12, ty0 + 356, tx0 + col_w - 12, ty0 + 516], fill=(17, 17, 22), outline=(44, 44, 54))
    draw.text((tx0 + 20, ty0 + 366), f"QA: {tqa['qa_status']} ({tqa['passed_count']}/{tqa['total_checks']}) | 256x256 Mode=L (R8)", fill=tbadge, font=font)
    draw.text((tx0 + 20, ty0 + 388), f"Binary Vals : {tchk['BINARY_TWO_TONE']['measured']}", fill=(220, 214, 200), font=font)
    draw.text((tx0 + 20, ty0 + 408), f"Hatch Duty  : {tchk['HATCH_DUTY']['measured']} (target 18%-58%)", fill=(220, 214, 200), font=font)
    draw.text((tx0 + 20, ty0 + 428), f"Seamless    : {tchk['SEAMLESS_TILE']['measured']}", fill=(220, 214, 200), font=font)
    draw.text((tx0 + 20, ty0 + 448), f"Stroke W    : medW={tchk['STROKE_COARSENESS']['details']['median_stroke_width_px']:.2f}px, specks=0", fill=(220, 214, 200), font=font)
    draw.text((tx0 + 20, ty0 + 490), "res://assets/art/textures/tex_woodcut_hatch_256_v01.png", fill=(140, 150, 175), font=font)

    # Row 2: 4 Phase-2 96x96 Icons / Unique / Rune / Prop
    row2_y = 622
    icol_w = 456
    for idx, (aid, subtitle, fam, rel_p) in enumerate(ICON_ASSETS):
        x0 = start_x + idx * (icol_w + 16)
        y0 = row2_y
        draw.rectangle([x0, y0, x0 + icol_w, y0 + 514], fill=(22, 22, 28), outline=(58, 54, 48), width=1)
        draw.text((x0 + 14, y0 + 10), f"[{idx + 5}] {subtitle}", fill=(233, 196, 106), font=font)
        draw.text((x0 + 14, y0 + 26), aid, fill=(185, 178, 166), font=font)

        p_path = ROOT_DIR / rel_p
        rgba = np.array(Image.open(p_path).convert("RGBA"))
        qa = evaluate_packed_asset(p_path, category="icon", accent_family=fam)

        sh_96 = render_shader_preview(rgba, accent_family=fam, on_card_bg=True, with_outline=True)[:, :, :3]
        sh_48 = cv2.resize(sh_96, (48, 48), interpolation=cv2.INTER_AREA)
        sh_28 = cv2.resize(sh_96, (28, 28), interpolation=cv2.INTER_AREA)
        sil_48 = _make_sil(rgba, 48, 48)
        sil_32 = _make_sil(rgba, 32, 32)

        iy = y0 + 54
        draw.rectangle([x0 + 15, iy - 1, x0 + 112, iy + 96], outline=(255, 159, 26))
        _paste_np(sheet, sh_96, x0 + 16, iy)
        draw.text((x0 + 16, iy + 102), "96x96 Master", fill=(160, 155, 145), font=font)

        draw.rectangle([x0 + 145, iy - 1, x0 + 194, iy + 48], outline=(110, 105, 96))
        _paste_np(sheet, sh_48, x0 + 146, iy)
        draw.text((x0 + 146, iy + 52), "48x48 Slot", fill=(160, 155, 145), font=font)

        draw.rectangle([x0 + 225, iy + 9, x0 + 254, iy + 38], outline=(255, 159, 26))
        _paste_np(sheet, sh_28, x0 + 226, iy + 10)
        draw.text((x0 + 220, iy + 52), "28x28 Drop", fill=(160, 155, 145), font=font)

        _paste_np(sheet, sil_48, x0 + 310, iy)
        _paste_np(sheet, sil_32, x0 + 372, iy + 8)
        draw.text((x0 + 310, iy + 52), "48 & 32 Sil", fill=(160, 155, 145), font=font)

        # R / G / B channel previews
        cy = y0 + 186
        for c_i, (c_lbl, c_col) in enumerate([("R: Bone", (232, 220, 192)), ("G: Accent", PALETTE_RGB[fam]), ("B: Gilding", (233, 196, 106))]):
            ch_64 = cv2.resize(rgba[:, :, c_i], (64, 64), interpolation=cv2.INTER_AREA).astype(np.float32) / 255.0
            fg_64 = (cv2.resize(rgba[:, :, 3], (64, 64), interpolation=cv2.INTER_AREA) >= 64).astype(np.float32)
            bg_c = np.full((64, 64, 3), 26.0, dtype=np.float32)
            ink_c = np.full((64, 64, 3), 10.0, dtype=np.float32)
            lit_c = np.array(c_col, dtype=np.float32)[None, None, :]
            viz = bg_c * (1.0 - fg_64[..., None]) + (ink_c * (1.0 - ch_64[..., None]) + lit_c * ch_64[..., None]) * fg_64[..., None]
            cx = x0 + 16 + c_i * 116
            draw.rectangle([cx - 1, cy - 1, cx + 64, cy + 64], outline=(60, 60, 70))
            _paste_np(sheet, np.clip(viz, 0, 255).astype(np.uint8), cx, cy)
            draw.text((cx, cy + 68), c_lbl, fill=(155, 150, 140), font=font)

        chk_map = {c["code"]: c for c in qa["checks"]}
        d_v4 = chk_map["V4_INK_MASS"]["details"]
        d_v2 = chk_map["V2_CHANNEL_CAPS"]["details"]
        d_v1 = chk_map["V1_THUMB_READABILITY"]["details"]
        d_v3 = chk_map["V3_LINE_WIDTH"]["details"]
        d_v5 = chk_map["V5_COMPOSITION"]["details"]
        badge_col = (78, 168, 92) if qa["qa_status"] == "PASS" else (210, 60, 60)
        draw.rectangle([x0 + 12, y0 + 282, x0 + icol_w - 12, y0 + 498], fill=(17, 17, 22), outline=(44, 44, 54))
        draw.text((x0 + 20, y0 + 294), f"QA: {qa['qa_status']} ({qa['passed_count']}/{qa['total_checks']}) | 96x96 RGBA", fill=badge_col, font=font)
        draw.text((x0 + 20, y0 + 318), f"V4 Ink Mass : {d_v4['ink_ratio']*100:.2f}% (bone={d_v2['r_bone_ratio']*100:.1f}%)", fill=(220, 214, 200), font=font)
        draw.text((x0 + 20, y0 + 340), f"V2 Channels : G={d_v2['g_accent_ratio']*100:.2f}%, B={d_v2['b_gold_ratio']*100:.2f}%, ovlp={d_v2['channel_overlap_ratio']*100:.2f}%", fill=(220, 214, 200), font=font)
        draw.text((x0 + 20, y0 + 362), f"V1 32px Rd  : mush={d_v1['muddy_gray_ratio']*100:.1f}%, RMS={d_v1['rms_contrast']:.3f}, occ={d_v1['silhouette_occupancy']*100:.1f}%", fill=(220, 214, 200), font=font)
        draw.text((x0 + 20, y0 + 384), f"V3 LineW    : <1.5px={d_v3['thin_line_lt_1_5px_ratio']*100:.1f}%, medW={d_v3['median_stroke_width_px']:.2f}px", fill=(220, 214, 200), font=font)
        draw.text((x0 + 20, y0 + 406), f"V5 Framing  : span={d_v5['width_ratio']*100:.0f}%x{d_v5['height_ratio']*100:.0f}%, dx={d_v5['center_x_offset']*100:.1f}%", fill=(220, 214, 200), font=font)
        draw.text((x0 + 20, y0 + 432), f"res://{rel_p}", fill=(140, 150, 175), font=font)

    out_path.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(out_path, format="PNG", compress_level=9)
    print(f"[+] Phase-2 Master Contact Sheet 已生成: {out_path} ({W}x{H})")
    return 0


if __name__ == "__main__":
    out_file = Path(sys.argv[1]) if len(sys.argv) > 1 else (ROOT_DIR / "tools" / "out" / "wp_p2_art_contact_sheet.png")
    sys.exit(build_p2_sheet(out_file))
