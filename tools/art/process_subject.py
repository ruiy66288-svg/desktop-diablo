#!/usr/bin/env python3
"""
《桌面破坏神》木刻主体后处理与四通道打包工具 (process_subject.py)
版本: 1.1.0
依据:
  - docs/00_开发执行总纲.md (勘误 E6、WP-A1)
  - docs/04_美术资产管线_v1.1.md (§1.2 四通道打包、§3 资产规格、§5 统一加工流程)
  - docs/03_美术风格圣经_v1.0.md (§02.2–02.4 尺寸与构图、§04.5 后处理步骤)

四通道数据纹理定义 (RGBA8 无损 PNG):
  - R 通道: 骨白受光掩码 (0 = 墨黑 #0B0A0C, 255 = 骨白 #E8DCC0)
  - G 通道: 族群油墨点缀色 / 装备镶嵌点缀色掩码 (面积上限: 怪物 <= 6%, 图标 <= 8%, Boss <= 15%)
  - B 通道: 镀金财富母题掩码 (#C9A04E / #E9C46A, 面积上限 <= 12%)
  - A 通道: 不透明度 (纯平中灰底经边缘连通 FloodFill 剥离 + 1px 抗锯齿边缘)
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Literal

import cv2
import numpy as np
from PIL import Image

TOOL_NAME: str = "process_subject.py"
TOOL_VERSION: str = "1.1.0"

CategoryType = Literal["monster", "boss", "icon", "prop"]
AccentFamilyType = Literal["auto", "undead", "demon", "beast", "fallen_saint", "abyss", "none"]

# 冻结 HEX 调色板 (docs/03 §03 & docs/04 §1.2)
PALETTE_RGB: dict[str, tuple[int, int, int]] = {
    "card_bg": (22, 22, 28),        # #16161C
    "ink": (11, 10, 12),            # #0B0A0C
    "bone": (232, 220, 192),        # #E8DCC0
    "gold": (201, 160, 78),         # #C9A04E
    "gold_bright": (233, 196, 106), # #E9C46A
    "undead": (176, 141, 87),       # #B08D57 旧金
    "fallen_saint": (176, 141, 87), # #B08D57 旧金
    "demon": (122, 15, 20),         # #7A0F14 血墨
    "beast": (78, 122, 58),         # #4E7A3A 苔绿
    "abyss": (106, 27, 58),         # #6A1B3A 酒红
    "auto": (122, 15, 20),          # 默认预览点缀色(血墨，与镀金高对比便于人工核验通道分离)
    "none": (176, 141, 87),
}


@dataclass(frozen=True)
class CategorySpec:
    width: int
    height: int
    target_height_ratio: float
    foot_line_ratio: float
    center_vertical: bool


CATEGORY_SPECS: dict[str, CategorySpec] = {
    "monster": CategorySpec(
        width=352,
        height=440,
        target_height_ratio=0.86,
        foot_line_ratio=0.92,
        center_vertical=False,
    ),
    "boss": CategorySpec(
        width=416,
        height=520,
        target_height_ratio=0.92,
        foot_line_ratio=0.95,
        center_vertical=False,
    ),
    "icon": CategorySpec(
        width=96,
        height=96,
        target_height_ratio=0.82,
        foot_line_ratio=0.91,
        center_vertical=True,
    ),
    "prop": CategorySpec(
        width=256,
        height=256,
        target_height_ratio=0.82,
        foot_line_ratio=0.91,
        center_vertical=True,
    ),
}


def compute_sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def parse_size(size_str: str) -> tuple[int, int]:
    parts = size_str.lower().split("x")
    if len(parts) != 2:
        raise ValueError(f"无效尺寸格式 '{size_str}'，应为 WxH（如 352x440）")
    w, h = int(parts[0]), int(parts[1])
    if w <= 0 or h <= 0:
        raise ValueError(f"尺寸必须为正整数: {size_str}")
    return w, h


def extract_foreground_alpha(
    img_rgb: np.ndarray,
    bg_tolerance: float = 28.0,
    min_speck_ratio: float = 0.0005,
) -> tuple[np.ndarray, np.ndarray]:
    """
    四角取样纯平中灰背景色，从画布四条边界全像素种子执行连通 FloodFill 剥离外部灰底，
    保留闭合黑轮廓内部的全部骨白/阴影细节，并剔除面积 < 0.05% 的孤立杂点。
    返回: (alpha_uint8, bg_ref_rgb)
    """
    h, w = img_rgb.shape[:2]
    patch = max(2, min(8, h // 16, w // 16))
    corners = np.concatenate(
        [
            img_rgb[:patch, :patch].reshape(-1, 3),
            img_rgb[:patch, w - patch :].reshape(-1, 3),
            img_rgb[h - patch :, :patch].reshape(-1, 3),
            img_rgb[h - patch :, w - patch :].reshape(-1, 3),
        ],
        axis=0,
    )
    bg_ref = np.median(corners, axis=0).astype(np.float32)

    diff = np.linalg.norm(img_rgb.astype(np.float32) - bg_ref, axis=-1)
    cand_bg = (diff <= bg_tolerance).astype(np.uint8)

    # 从画布四边所有满足灰底容差的边界像素启动 FloodFill (标记为 2)
    flood_work = cand_bg.copy()
    ff_mask = np.zeros((h + 2, w + 2), dtype=np.uint8)

    for x in range(w):
        if flood_work[0, x] == 1:
            cv2.floodFill(flood_work, ff_mask, (x, 0), 2)
        if flood_work[h - 1, x] == 1:
            cv2.floodFill(flood_work, ff_mask, (x, h - 1), 2)
    for y in range(h):
        if flood_work[y, 0] == 1:
            cv2.floodFill(flood_work, ff_mask, (0, y), 2)
        if flood_work[y, w - 1] == 1:
            cv2.floodFill(flood_work, ff_mask, (w - 1, y), 2)

    fg_binary = (flood_work != 2).astype(np.uint8)

    # 删除面积 < 0.05% 画布的连通前景杂点 (docs/03 §04.5 第 3 步)
    min_area = max(4, int(round(h * w * min_speck_ratio)))
    num_labels, labels, stats, _ = cv2.connectedComponentsWithStats(fg_binary, connectivity=8)
    clean_fg = np.zeros_like(fg_binary)
    for lbl in range(1, num_labels):
        if int(stats[lbl, cv2.CC_STAT_AREA]) >= min_area:
            clean_fg[labels == lbl] = 1

    # 1px 边缘柔化抗锯齿 (保持内部完全 255 不透明，仅外边界 1px 平滑过渡)
    eroded = cv2.erode(clean_fg, np.ones((3, 3), dtype=np.uint8), iterations=1)
    blurred = cv2.GaussianBlur(clean_fg.astype(np.float32) * 255.0, (3, 3), 0.65)
    alpha = np.where(eroded == 1, 255.0, np.where(clean_fg == 1, blurred, 0.0))
    return np.clip(np.round(alpha), 0, 255).astype(np.uint8), bg_ref


def separate_four_channels(
    img_rgb: np.ndarray,
    alpha: np.ndarray,
    accent_family: AccentFamilyType = "auto",
) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """
    在前景区域内分离 R(骨白)、G(族群/镶嵌油墨点缀色)、B(镀金遮罩) 三个正交掩码通道。
    墨黑 (#0B0A0C) 对应 R=0, G=0, B=0, A>0。
    """
    img_bgr = cv2.cvtColor(img_rgb, cv2.COLOR_RGB2BGR)
    hsv = cv2.cvtColor(img_bgr, cv2.COLOR_BGR2HSV)
    h_ch = hsv[:, :, 0].astype(np.int32)  # 0..179
    s_ch = hsv[:, :, 1].astype(np.int32)  # 0..255
    v_ch = hsv[:, :, 2].astype(np.int32)  # 0..255

    fg = alpha > 8
    warm_gold_hue = (h_ch >= 11) & (h_ch <= 31)
    undead_warm_hue = (h_ch >= 11) & (h_ch <= 36)

    # 自适应估算当前图像高亮骨白受光面的基础饱和度中位数 (兼容纯白 S~40 与暖羊皮骨白 S~75)
    bright_fg = fg & (v_ch >= 175)
    bone_s_med = float(np.median(s_ch[bright_fg])) if int(bright_fg.sum()) >= 32 else 50.0
    gold_s_floor = int(round(min(115.0, max(82.0, bone_s_med + 30.0))))

    if accent_family == "none":
        g_mask = np.zeros_like(fg)
        b_mask = fg & warm_gold_hue & (s_ch >= gold_s_floor) & (v_ch >= 85)
    elif accent_family in ("undead", "fallen_saint"):
        # 不死/堕圣: 高明度金属金箔 (V>=182) 归入 B 镀金; 中低明度旧金/橄榄褐油墨 (V<182) 归入 G 点缀
        b_mask = fg & undead_warm_hue & (v_ch >= 182) & (s_ch >= gold_s_floor)
        warm_ochre_ink = fg & undead_warm_hue & (~b_mask) & (s_ch >= max(105, gold_s_floor)) & (v_ch >= 60)
        other_ink = fg & (~undead_warm_hue) & (s_ch >= 80) & (v_ch >= 38)
        g_mask = warm_ochre_ink | other_ink
    else:
        # 镀金 (B): 暖金黄 H in [11, 31] (H>=32 的苔绿/橄榄绿宝石与衣领直接归入 G 通道!)
        b_mask = fg & warm_gold_hue & (s_ch >= gold_s_floor) & (v_ch >= 85)
        g_mask = fg & (~warm_gold_hue) & (s_ch >= 80) & (v_ch >= 38)

    # 骨白 (R): 非镀金、非油墨点缀色的高明度低饱和受光面
    luma = (
        0.299 * img_rgb[:, :, 0].astype(np.float32)
        + 0.587 * img_rgb[:, :, 1].astype(np.float32)
        + 0.114 * img_rgb[:, :, 2].astype(np.float32)
    )
    r_mask = fg & (~b_mask) & (~g_mask) & (luma >= 122.0)

    r_u8 = (r_mask.astype(np.uint8)) * 255
    g_u8 = (g_mask.astype(np.uint8)) * 255
    b_u8 = (b_mask.astype(np.uint8)) * 255
    return r_u8, g_u8, b_u8


def standardize_and_downsample(
    rgba_src: np.ndarray,
    spec: CategorySpec,
    target_size: tuple[int, int] | None = None,
    no_reframe: bool = False,
) -> np.ndarray:
    """
    按 docs/03 §02.2–02.4 与 §04.5 第 4–5 步执行主体包围盒构图标准化，
    并用 INTER_AREA 面积滤波缩放到母版尺寸，同时保持通道正交无杂色。
    """
    out_w, out_h = target_size if target_size is not None else (spec.width, spec.height)
    alpha = rgba_src[:, :, 3]
    ys, xs = np.where(alpha >= 32)

    if no_reframe or len(xs) == 0 or len(ys) == 0:
        resized = cv2.resize(rgba_src, (out_w, out_h), interpolation=cv2.INTER_AREA)
    else:
        x0, x1 = int(xs.min()), int(xs.max()) + 1
        y0, y1 = int(ys.min()), int(ys.max()) + 1
        crop = rgba_src[y0:y1, x0:x1]
        crop_h, crop_w = crop.shape[:2]

        # 在高分辨率工作画布上完成标准化排布，再一次性 INTER_AREA 下采样
        scale_up = max(1, int(np.ceil(max(crop_h / (out_h * spec.target_height_ratio), 1.0))))
        work_w = out_w * scale_up
        work_h = out_h * scale_up

        if spec.center_vertical:
            # 方形图标/道具: 最大边占画布 target_height_ratio，水平垂直双居中
            desired_span = spec.target_height_ratio * float(min(work_w, work_h))
            fit_scale = desired_span / float(max(crop_w, crop_h))
            new_w = max(1, int(round(crop_w * fit_scale)))
            new_h = max(1, int(round(crop_h * fit_scale)))
            scaled_crop = (
                cv2.resize(crop, (new_w, new_h), interpolation=cv2.INTER_AREA if fit_scale < 1.0 else cv2.INTER_LINEAR)
                if (new_w, new_h) != (crop_w, crop_h)
                else crop
            )
            dst_x = (work_w - new_w) // 2
            dst_y = (work_h - new_h) // 2
        else:
            # 怪物/Boss 竖版: 高度占 target_height_ratio，脚底对齐 foot_line_ratio，水平居中
            desired_h = spec.target_height_ratio * float(work_h)
            max_allowed_w = 0.96 * float(work_w)
            fit_scale = min(desired_h / float(crop_h), max_allowed_w / float(crop_w))
            new_w = max(1, int(round(crop_w * fit_scale)))
            new_h = max(1, int(round(crop_h * fit_scale)))
            scaled_crop = (
                cv2.resize(crop, (new_w, new_h), interpolation=cv2.INTER_AREA if fit_scale < 1.0 else cv2.INTER_LINEAR)
                if (new_w, new_h) != (crop_w, crop_h)
                else crop
            )
            dst_x = (work_w - new_w) // 2
            foot_y = int(round(spec.foot_line_ratio * float(work_h)))
            dst_y = max(2, min(work_h - new_h - 2, foot_y - new_h))

        canvas = np.zeros((work_h, work_w, 4), dtype=np.uint8)
        canvas[dst_y : dst_y + new_h, dst_x : dst_x + new_w] = scaled_crop
        resized = (
            cv2.resize(canvas, (out_w, out_h), interpolation=cv2.INTER_AREA)
            if (work_w, work_h) != (out_w, out_h)
            else canvas
        )

    # 下采样后做通道正交化二值收口 (严格保证 4 色，消除下采样半灰杂边)，保留 A 通道 1px 抗锯齿
    r_ch = resized[:, :, 0]
    g_ch = resized[:, :, 1]
    b_ch = resized[:, :, 2]
    a_ch = resized[:, :, 3]

    # 清除极弱透明残影，并剔除下采样可能产生的 <0.05% 孤立碎点
    a_clean = np.where(a_ch < 20, 0, np.where(a_ch > 242, 255, a_ch)).astype(np.uint8)
    fg_mask = (a_clean >= 20).astype(np.uint8)
    min_out_speck = max(2, int(round(out_w * out_h * 0.0005)))
    n_lbl, lbls, st, _ = cv2.connectedComponentsWithStats(fg_mask, connectivity=8)
    valid_fg = np.zeros_like(fg_mask, dtype=bool)
    for idx in range(1, n_lbl):
        if int(st[idx, cv2.CC_STAT_AREA]) >= min_out_speck:
            valid_fg[lbls == idx] = True

    a_final = np.where(valid_fg, a_clean, 0).astype(np.uint8)

    # 优先级 B(镀金) > G(油墨点缀) > R(骨白) > 墨黑(0,0,0)；72 阈值确保 96x96 图标上的微小锁扣/宝石不被下采样吞没
    is_b = valid_fg & (b_ch >= 72) & (b_ch >= g_ch)
    is_g = valid_fg & (~is_b) & (g_ch >= 72)
    is_r = valid_fg & (~is_b) & (~is_g) & (r_ch >= 120)

    out_rgba = np.zeros((out_h, out_w, 4), dtype=np.uint8)
    out_rgba[:, :, 0] = np.where(is_r, 255, 0).astype(np.uint8)
    out_rgba[:, :, 1] = np.where(is_g, 255, 0).astype(np.uint8)
    out_rgba[:, :, 2] = np.where(is_b, 255, 0).astype(np.uint8)
    out_rgba[:, :, 3] = a_final
    return out_rgba


def render_shader_preview(
    packed_rgba: np.ndarray,
    accent_family: AccentFamilyType = "auto",
    wealth_pressure: float = 0.0,
    on_card_bg: bool = True,
    with_outline: bool = True,
) -> np.ndarray:
    """
    在 Python 端精确复现 palette_subject.gdshader 着色结果，用于预览图与质检缩略图。
    """
    h, w = packed_rgba.shape[:2]
    r = packed_rgba[:, :, 0].astype(np.float32) / 255.0
    g = packed_rgba[:, :, 1].astype(np.float32) / 255.0
    b = packed_rgba[:, :, 2].astype(np.float32) / 255.0
    a = packed_rgba[:, :, 3].astype(np.float32) / 255.0

    c_ink = np.array(PALETTE_RGB["ink"], dtype=np.float32)
    c_bone = np.array(PALETTE_RGB["bone"], dtype=np.float32)
    c_family = np.array(PALETTE_RGB.get(accent_family, PALETTE_RGB["auto"]), dtype=np.float32)
    c_gold = np.array(PALETTE_RGB["gold"], dtype=np.float32)
    c_gold_bright = np.array(PALETTE_RGB["gold_bright"], dtype=np.float32)

    base = c_ink[None, None, :] * (1.0 - r[..., None]) + c_bone[None, None, :] * r[..., None]
    base = base * (1.0 - g[..., None]) + c_family[None, None, :] * g[..., None]

    eff_b = b.copy()
    gold_rgb = np.broadcast_to(c_gold, (h, w, 3)).copy()

    if wealth_pressure > 0.0005:
        wp = min(1.0, max(0.0, wealth_pressure / 0.477121))
        gold_rgb = c_gold[None, None, :] * (1.0 - wp) + c_gold_bright[None, None, :] * wp
    elif wealth_pressure < -0.0005:
        debt_ratio = min(1.0, max(0.0, -wealth_pressure / 0.397940))
        yy, xx = np.mgrid[0:h, 0:w]
        u = xx.astype(np.float32) / max(1.0, float(w))
        v = yy.astype(np.float32) / max(1.0, float(h))
        cell_hash = np.mod(np.sin(np.floor((u + v) * 36.0) * 127.1 + np.floor((v - u) * 14.0) * 311.7) * 43758.5453, 1.0)
        peeled = (cell_hash < debt_ratio * 0.85).astype(np.float32)
        eff_b = b * (1.0 - peeled)
        base = base * (1.0 - (b * peeled)[..., None]) + c_bone[None, None, :] * (b * peeled)[..., None]

    subj_rgb = base * (1.0 - eff_b[..., None]) + gold_rgb * eff_b[..., None]
    out_rgb = subj_rgb.copy()
    out_a = a.copy()

    if with_outline:
        dilated_a = cv2.dilate(packed_rgba[:, :, 3], np.ones((3, 3), dtype=np.uint8), iterations=1).astype(np.float32) / 255.0
        rim_mask = np.clip((dilated_a - 0.15) / 0.50, 0.0, 1.0) * (1.0 - a)
        rim_a = 0.40 * rim_mask
        comp_a = a + rim_a * (1.0 - a)
        safe_a = np.where(comp_a > 1e-4, comp_a, 1.0)
        out_rgb = (subj_rgb * a[..., None] + c_bone[None, None, :] * (rim_a * (1.0 - a))[..., None]) / safe_a[..., None]
        out_a = comp_a

    if on_card_bg:
        bg = np.array(PALETTE_RGB["card_bg"], dtype=np.float32)
        final_rgb = bg[None, None, :] * (1.0 - out_a[..., None]) + out_rgb * out_a[..., None]
        final_rgba = np.dstack([np.clip(np.round(final_rgb), 0, 255).astype(np.uint8), np.full((h, w), 255, dtype=np.uint8)])
        return final_rgba

    return np.dstack([
        np.clip(np.round(out_rgb), 0, 255).astype(np.uint8),
        np.clip(np.round(out_a * 255.0), 0, 255).astype(np.uint8),
    ])


def process_subject_file(
    src_path: Path,
    out_packed_path: Path,
    category: CategoryType = "monster",
    accent_family: AccentFamilyType = "auto",
    out_preview_path: Path | None = None,
    target_size: tuple[int, int] | None = None,
    bg_tolerance: float = 28.0,
    no_reframe: bool = False,
) -> dict[str, object]:
    if not src_path.exists():
        raise FileNotFoundError(f"找不到源图片: {src_path}")
    if category not in CATEGORY_SPECS:
        raise ValueError(f"不支持的资产类别: {category}")

    pil_img = Image.open(src_path).convert("RGB")
    img_rgb = np.array(pil_img, dtype=np.uint8)

    alpha, bg_ref = extract_foreground_alpha(img_rgb, bg_tolerance=bg_tolerance)
    r_ch, g_ch, b_ch = separate_four_channels(img_rgb, alpha, accent_family=accent_family)
    raw_packed = np.dstack([r_ch, g_ch, b_ch, alpha])

    spec = CATEGORY_SPECS[category]
    final_rgba = standardize_and_downsample(
        raw_packed,
        spec=spec,
        target_size=target_size,
        no_reframe=no_reframe,
    )

    out_packed_path.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(final_rgba, mode="RGBA").save(out_packed_path, format="PNG", compress_level=9)

    if out_preview_path is not None:
        preview_rgba = render_shader_preview(final_rgba, accent_family=accent_family, on_card_bg=True, with_outline=True)
        out_preview_path.parent.mkdir(parents=True, exist_ok=True)
        Image.fromarray(preview_rgba, mode="RGBA").save(out_preview_path, format="PNG", compress_level=9)

    fg = final_rgba[:, :, 3] >= 128
    fg_total = max(1, int(fg.sum()))
    r_ratio = float(((final_rgba[:, :, 0] >= 128) & fg).sum()) / fg_total
    g_ratio = float(((final_rgba[:, :, 1] >= 128) & fg).sum()) / fg_total
    b_ratio = float(((final_rgba[:, :, 2] >= 128) & fg).sum()) / fg_total
    ink_ratio = float(((final_rgba[:, :, 0] < 128) & (final_rgba[:, :, 1] < 128) & (final_rgba[:, :, 2] < 128) & fg).sum()) / fg_total

    summary: dict[str, object] = {
        "tool": f"{TOOL_NAME}@{TOOL_VERSION}",
        "src_path": str(src_path),
        "src_sha256": compute_sha256(src_path),
        "packed_path": str(out_packed_path),
        "packed_sha256": compute_sha256(out_packed_path),
        "category": category,
        "accent_family": accent_family,
        "output_size": [int(final_rgba.shape[1]), int(final_rgba.shape[0])],
        "bg_sampled_rgb": [round(float(x), 1) for x in bg_ref.tolist()],
        "foreground_pixels": fg_total,
        "channel_ratios": {
            "ink_black": round(ink_ratio, 4),
            "r_bone": round(r_ratio, 4),
            "g_accent": round(g_ratio, 4),
            "b_gold": round(b_ratio, 4),
        },
    }
    return summary


def build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="process_subject.py",
        description="《桌面破坏神》木刻主体后处理：纯平中灰底边缘 FloodFill 抠图 + R/G/B/A 四通道打包 + 构图标准化",
    )
    parser.add_argument("--src", type=Path, required=True, help="输入原始图片路径 (PNG)")
    parser.add_argument("--out", type=Path, required=True, help="输出四通道 RGBA 数据纹理路径 (PNG)")
    parser.add_argument(
        "--category",
        type=str,
        default="monster",
        choices=["monster", "boss", "icon", "prop"],
        help="资产类别：决定母版分辨率与构图规范 (monster=352x440, boss=416x520, icon=96x96)",
    )
    parser.add_argument(
        "--accent-family",
        type=str,
        default="auto",
        choices=["auto", "undead", "demon", "beast", "fallen_saint", "abyss", "none"],
        help="族群油墨色分类辅助，用于区分旧金油墨与高亮镀金 (默认: auto)",
    )
    parser.add_argument("--preview", type=Path, default=None, help="可选：输出 #16161C 卡底 Shader 着色还原预览图路径")
    parser.add_argument("--size", type=str, default=None, help="可选：显式覆盖输出尺寸 WxH (如 352x440)")
    parser.add_argument("--bg-tolerance", type=float, default=28.0, help="四角中灰底采样欧氏容差 (默认: 28.0)")
    parser.add_argument("--no-reframe", action="store_true", help="跳过包围盒重排构图，仅原位缩放")
    parser.add_argument("--json-summary", type=Path, default=None, help="可选：将处理统计摘要写入 JSON 文件")
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_arg_parser()
    args = parser.parse_args(argv)
    target_size = parse_size(args.size) if args.size else None

    summary = process_subject_file(
        src_path=args.src,
        out_packed_path=args.out,
        category=args.category,
        accent_family=args.accent_family,
        out_preview_path=args.preview,
        target_size=target_size,
        bg_tolerance=args.bg_tolerance,
        no_reframe=args.no_reframe,
    )
    if args.json_summary is not None:
        args.json_summary.parent.mkdir(parents=True, exist_ok=True)
        args.json_summary.write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")

    ratios = summary["channel_ratios"]
    assert isinstance(ratios, dict)
    print(
        f"[+] 四通道打包完成: {summary['packed_path']} ({summary['output_size'][0]}x{summary['output_size'][1]}) | "
        f"墨黑={ratios['ink_black']*100:.1f}% R骨白={ratios['r_bone']*100:.1f}% "
        f"G点缀={ratios['g_accent']*100:.1f}% B镀金={ratios['b_gold']*100:.1f}%"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
