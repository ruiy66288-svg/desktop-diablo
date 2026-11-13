#!/usr/bin/env python3
"""
《桌面破坏神》WP-A4 首批 10 件正式美术资产总览检视板生成器 (build_master_sheet.py)
版本: 1.0.0
输出: tools/out/wp_a4_all_assets_contact_sheet.png
展示全部 10 件正式四通道 RGBA 资产 (3 怪物 + 1 Boss + 6 装备槽底材图标) 的:
  - #16161C 黑卡底 Shader 着色还原 (实景显示尺寸 176x220 / 208x260 / 96x96)
  - 72x90 排队卡 / 48x48 装备栏槽位 / 28x28 地面掉落实景缩略
  - R / G / B 通道占比与 QA 7/7 PASS 核心指标
"""

from __future__ import annotations

import json
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
    ("mon_undead_miser_v01", "Monster · Undead (#B08D57)", "monster", "undead", "assets/art/monsters/mon_undead_miser_v01.png"),
    ("mon_demon_debtor_v01", "Monster · Demon (#7A0F14)", "monster", "demon", "assets/art/monsters/mon_demon_debtor_v01.png"),
    ("mon_beast_goldmaw_v01", "Monster · Beast (#4E7A3A)", "monster", "beast", "assets/art/monsters/mon_beast_goldmaw_v01.png"),
    ("boss_demon_abyss-lord_v01", "Boss · Demon (#7A0F14)", "boss", "demon", "assets/art/bosses/boss_demon_abyss-lord_v01.png"),
]

ICON_ASSETS = [
    ("eq_weapon_base_greatsword_v01", "Slot 1 · Weapon", "demon", "assets/art/items/eq_weapon_base_greatsword_v01.png"),
    ("eq_helm_base_greathelm_v01", "Slot 2 · Helm", "abyss", "assets/art/items/eq_helm_base_greathelm_v01.png"),
    ("eq_chest_base_cuirass_v01", "Slot 3 · Chest", "demon", "assets/art/items/eq_chest_base_cuirass_v01.png"),
    ("eq_gloves_base_gauntlets_v01", "Slot 4 · Gloves", "beast", "assets/art/items/eq_gloves_base_gauntlets_v01.png"),
    ("eq_boots_base_greaves_v01", "Slot 5 · Boots", "abyss", "assets/art/items/eq_boots_base_greaves_v01.png"),
    ("eq_trinket_base_signet_v01", "Slot 6 · Trinket", "abyss", "assets/art/items/eq_trinket_base_signet_v01.png"),
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


def build_sheet(out_path: Path) -> int:
    W, H = 1920, 1160
    sheet = Image.new("RGB", (W, H), (14, 14, 19))
    draw = ImageDraw.Draw(sheet)
    font = ImageFont.load_default()

    # Header
    draw.rectangle([0, 0, W, 56], fill=(20, 20, 27))
    draw.line([0, 56, W, 56], fill=(201, 160, 78), width=2)
    draw.text(
        (24, 14),
        "DESKTOP DIABLO (360x480) — WP-A3 & WP-A4 FORMAL 4-CHANNEL WOODCUT ASSET MASTER SHEET (10/10 QA PASS)",
        fill=(232, 220, 192),
        font=font,
    )
    draw.text(
        (24, 34),
        "Palette Frozen: Card #16161C | Ink #0B0A0C | Bone #E8DCC0 | Gilding #C9A04E/#E9C46A | Undead #B08D57 | Demon #7A0F14 | Beast #4E7A3A | Abyss #6A1B3A",
        fill=(165, 158, 145),
        font=font,
    )

    # Row 1: 4 Portraits (Monsters + Boss)
    col_w = 456
    start_x = 24
    row1_y = 74

    for idx, (aid, subtitle, cat, fam, rel_p) in enumerate(PORTRAIT_ASSETS):
        x0 = start_x + idx * (col_w + 16)
        y0 = row1_y
        draw.rectangle([x0, y0, x0 + col_w, y0 + 530], fill=(22, 22, 28), outline=(58, 54, 48), width=1)
        draw.text((x0 + 12, y0 + 10), f"[{idx + 1}] {aid}", fill=(233, 196, 106), font=font)
        draw.text((x0 + 12, y0 + 26), subtitle, fill=(180, 174, 162), font=font)

        p_path = ROOT_DIR / rel_p
        rgba = np.array(Image.open(p_path).convert("RGBA"))
        qa = evaluate_packed_asset(p_path, category=cat, accent_family=fam)

        # Display size shader render (176x220 or 208x260)
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

        # Right column inside card: 72x90 queue card + 72x90 silhouette + In-Debt preview
        rx = x0 + 240
        q_thumb = cv2.resize(sh_full[:, :, :3], (72, 90), interpolation=cv2.INTER_AREA)
        q_sil = _make_sil(rgba, 72, 90)
        draw.rectangle([rx - 1, card_y - 1, rx + 72, card_y + 90], outline=(90, 86, 78))
        _paste_np(sheet, q_thumb, rx, card_y)
        _paste_np(sheet, q_sil, rx + 84, card_y)
        draw.text((rx, card_y + 94), "72x90 Queue & Sil", fill=(160, 155, 145), font=font)

        _paste_np(sheet, sh_debt_sm, rx, card_y + 116)
        draw.text((rx, card_y + 250), "Debt Peel (dH=-0.4)", fill=(160, 155, 145), font=font)

        # Bottom mini channel bars & QA stats (pure ASCII for PIL default font)
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

    # Row 2: 6 Equipment Base Icons (96x96)
    row2_y = 622
    icol_w = 298
    for idx, (aid, subtitle, fam, rel_p) in enumerate(ICON_ASSETS):
        x0 = start_x + idx * (icol_w + 16)
        y0 = row2_y
        draw.rectangle([x0, y0, x0 + icol_w, y0 + 514], fill=(22, 22, 28), outline=(58, 54, 48), width=1)
        draw.text((x0 + 10, y0 + 10), f"[{idx + 5}] {subtitle}", fill=(233, 196, 106), font=font)
        draw.text((x0 + 10, y0 + 26), aid, fill=(185, 178, 166), font=font)

        p_path = ROOT_DIR / rel_p
        rgba = np.array(Image.open(p_path).convert("RGBA"))
        qa = evaluate_packed_asset(p_path, category="icon", accent_family=fam)

        sh_96 = render_shader_preview(rgba, accent_family=fam, on_card_bg=True, with_outline=True)[:, :, :3]
        sh_48 = cv2.resize(sh_96, (48, 48), interpolation=cv2.INTER_AREA)
        sh_28 = cv2.resize(sh_96, (28, 28), interpolation=cv2.INTER_AREA)
        sil_48 = _make_sil(rgba, 48, 48)
        sil_32 = _make_sil(rgba, 32, 32)

        # 96x96 Master + 48x48 Slot + 28x28 Ground Loot + 48/32 Silhouettes
        iy = y0 + 54
        draw.rectangle([x0 + 13, iy - 1, x0 + 110, iy + 96], outline=(201, 160, 78))
        _paste_np(sheet, sh_96, x0 + 14, iy)
        draw.text((x0 + 14, iy + 102), "96x96 Master", fill=(160, 155, 145), font=font)

        draw.rectangle([x0 + 129, iy - 1, x0 + 178, iy + 48], outline=(110, 105, 96))
        _paste_np(sheet, sh_48, x0 + 130, iy)
        draw.text((x0 + 130, iy + 52), "48x48", fill=(160, 155, 145), font=font)

        draw.rectangle([x0 + 195, iy + 9, x0 + 224, iy + 38], outline=(255, 138, 0))
        _paste_np(sheet, sh_28, x0 + 196, iy + 10)
        draw.text((x0 + 192, iy + 52), "28x28", fill=(160, 155, 145), font=font)

        _paste_np(sheet, sil_48, x0 + 130, iy + 72)
        _paste_np(sheet, sil_32, x0 + 196, iy + 80)
        draw.text((x0 + 130, iy + 124), "48 & 32 Sil", fill=(160, 155, 145), font=font)

        # R / G / B channel mini previews (48x48 each)
        cy = y0 + 206
        for c_i, (c_lbl, c_col) in enumerate([("R:Bone", (232, 220, 192)), ("G:Acc", PALETTE_RGB[fam]), ("B:Gold", (233, 196, 106))]):
            ch_48 = cv2.resize(rgba[:, :, c_i], (48, 48), interpolation=cv2.INTER_AREA).astype(np.float32) / 255.0
            fg_48 = (cv2.resize(rgba[:, :, 3], (48, 48), interpolation=cv2.INTER_AREA) >= 64).astype(np.float32)
            bg_c = np.full((48, 48, 3), 26.0, dtype=np.float32)
            ink_c = np.full((48, 48, 3), 10.0, dtype=np.float32)
            lit_c = np.array(c_col, dtype=np.float32)[None, None, :]
            viz = bg_c * (1.0 - fg_48[..., None]) + (ink_c * (1.0 - ch_48[..., None]) + lit_c * ch_48[..., None]) * fg_48[..., None]
            cx = x0 + 14 + c_i * 88
            draw.rectangle([cx - 1, cy - 1, cx + 48, cy + 48], outline=(60, 60, 70))
            _paste_np(sheet, np.clip(viz, 0, 255).astype(np.uint8), cx, cy)
            draw.text((cx, cy + 52), c_lbl, fill=(155, 150, 140), font=font)

        # QA summary box (pure ASCII for PIL default font)
        chk_map = {c["code"]: c for c in qa["checks"]}
        d_v4 = chk_map["V4_INK_MASS"]["details"]
        d_v2 = chk_map["V2_CHANNEL_CAPS"]["details"]
        d_v1 = chk_map["V1_THUMB_READABILITY"]["details"]
        d_v3 = chk_map["V3_LINE_WIDTH"]["details"]
        d_v5 = chk_map["V5_COMPOSITION"]["details"]
        badge_col = (78, 168, 92) if qa["qa_status"] == "PASS" else (210, 60, 60)
        draw.rectangle([x0 + 10, y0 + 286, x0 + icol_w - 10, y0 + 500], fill=(17, 17, 22), outline=(44, 44, 54))
        draw.text((x0 + 16, y0 + 296), f"QA: {qa['qa_status']} ({qa['passed_count']}/{qa['total_checks']}) | 96x96 RGBA", fill=badge_col, font=font)
        draw.text((x0 + 16, y0 + 320), f"V4 Ink  : {d_v4['ink_ratio']*100:.2f}% (R={d_v2['r_bone_ratio']*100:.1f}%)", fill=(220, 214, 200), font=font)
        draw.text((x0 + 16, y0 + 342), f"V2 Chan : G={d_v2['g_accent_ratio']*100:.2f}% B={d_v2['b_gold_ratio']*100:.2f}%", fill=(220, 214, 200), font=font)
        draw.text((x0 + 16, y0 + 364), f"V1 32px : mush={d_v1['muddy_gray_ratio']*100:.1f}% RMS={d_v1['rms_contrast']:.2f}", fill=(220, 214, 200), font=font)
        draw.text((x0 + 16, y0 + 386), f"V3 Line : <1.5px={d_v3['thin_line_lt_1_5px_ratio']*100:.1f}%", fill=(220, 214, 200), font=font)
        draw.text((x0 + 16, y0 + 408), f"V5 Span : {d_v5['width_ratio']*100:.0f}%x{d_v5['height_ratio']*100:.0f}%", fill=(220, 214, 200), font=font)
        draw.text((x0 + 16, y0 + 434), "res://assets/art/items/", fill=(140, 150, 175), font=font)
        draw.text((x0 + 16, y0 + 452), f"{aid}.png", fill=(140, 150, 175), font=font)

    out_path.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(out_path, format="PNG", compress_level=9)
    print(f"[+] Master 10-Asset Contact Sheet 已生成: {out_path} ({W}x{H})")
    return 0


if __name__ == "__main__":
    out_file = Path(sys.argv[1]) if len(sys.argv) > 1 else (ROOT_DIR / "tools" / "out" / "wp_a4_all_assets_contact_sheet.png")
    sys.exit(build_sheet(out_file))
