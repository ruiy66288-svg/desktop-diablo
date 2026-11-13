#!/usr/bin/env python3
"""
《桌面破坏神》高度图转无缝二值木刻排线平铺纹理工具 (hatch_from_height.py)
版本: 1.0.0
依据:
  - docs/04_美术资产管线_v1.1.md (§3 #6 逐项规格、§5 统一加工流程、§8 第 3 条许可红线)
  - docs/03_美术风格圣经_v1.0.md (§01 左上角固定光源、§03 地面条/卡底暗纹 ≤15% 不透明度单通道着色)

管线步骤:
  1. 输入外部高度图 (--height-map) 或确定性生成无缝石板/羊皮纸程序化高度图 (--procedural，登记 LIC-PROC-0001)；
  2. 周期域双线性缩放至目标尺寸 (默认 256×256) 并归一化高度 H ∈ [0, 1]；
  3. 计算左上角光源 (-1/√2, -1/√2) 下的浮雕受光斜率与凹陷阴影权重；
  4. 沿垂直于左上光源的木刻刀痕方向生成严格周期等距排线 (线宽 w = f(height, slope))；
  5. 二值化为 {0, 255}，经周期包裹形态学去毛刺后输出 256×256 单通道 (8-bit L / R8) 无缝 PNG。
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import cv2
import numpy as np
from PIL import Image

TOOL_NAME: str = "hatch_from_height.py"
TOOL_VERSION: str = "1.0.0"

ROOT_DIR = Path(__file__).resolve().parent.parent.parent
DEFAULT_RAW_HEIGHT = ROOT_DIR / "art_source" / "raw" / "tex_woodcut_hatch_256" / "height_stone_parchment_256.png"
DEFAULT_OUT_HATCH = ROOT_DIR / "tools" / "out" / "wp_p2_art" / "tex_woodcut_hatch_256_packed.png"


def generate_seamless_stone_parchment_height(size: int = 256, seed: int = 20261113) -> np.ndarray:
    """
    在二维周期傅里叶频域合成 100% 四边无缝平铺的石板起伏 + 羊皮纸纤维高度图 (uint8 0..255)。
    零外部版权依赖，同一种子跨平台完全确定性复现。
    """
    rng = np.random.default_rng(seed)
    fy = np.fft.fftfreq(size)[:, None] * float(size)
    fx = np.fft.fftfreq(size)[None, :] * float(size)
    freq_r = np.sqrt(fx * fx + fy * fy)

    # 层 1: 低频粗凿石板块面起伏 (波数 2..7)
    phase1 = rng.uniform(0.0, 2.0 * np.pi, size=(size, size))
    amp1 = np.where((freq_r >= 2.0) & (freq_r <= 7.5), 1.0 / np.maximum(1.0, freq_r ** 1.35), 0.0)
    slab = np.real(np.fft.ifft2(amp1 * (np.cos(phase1) + 1j * np.sin(phase1))))

    # 层 2: 中频石材风化凹坑与纤维肌理 (波数 8..22)
    phase2 = rng.uniform(0.0, 2.0 * np.pi, size=(size, size))
    amp2 = np.where((freq_r >= 8.0) & (freq_r <= 22.0), 1.0 / np.maximum(1.0, freq_r ** 1.55), 0.0)
    grain = np.real(np.fft.ifft2(amp2 * (np.cos(phase2) + 1j * np.sin(phase2))))

    # 层 3: 轻微斜向羊皮纸织纹调制 (严格整数周期保无缝)
    yy, xx = np.meshgrid(np.arange(size, dtype=np.float64), np.arange(size, dtype=np.float64), indexing="ij")
    weave = 0.12 * np.sin(2.0 * np.pi * (3.0 * xx - 2.0 * yy) / float(size))

    def _norm01(arr: np.ndarray) -> np.ndarray:
        lo, hi = float(arr.min()), float(arr.max())
        return (arr - lo) / max(1e-8, hi - lo)

    combined = 0.62 * _norm01(slab) + 0.28 * _norm01(grain) + 0.10 * _norm01(weave)
    combined = _norm01(combined)
    return np.clip(np.round(combined * 255.0), 0, 255).astype(np.uint8)


def _periodic_morph(binary_u8: np.ndarray, ksize: int = 3) -> np.ndarray:
    """使用 wrap 周期边界做开闭运算消除 1px 孤立毛刺，同时严格保持四向平铺无缝。"""
    pad = ksize // 2 + 1
    wrapped = np.pad(binary_u8, ((pad, pad), (pad, pad)), mode="wrap")
    kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (ksize, ksize))
    opened = cv2.morphologyEx(wrapped, cv2.MORPH_OPEN, kernel)
    closed = cv2.morphologyEx(opened, cv2.MORPH_CLOSE, kernel)
    return closed[pad:-pad, pad:-pad]


def convert_height_to_woodcut_hatch(
    height_u8: np.ndarray,
    size: int = 256,
    periods: int = 20,
    min_duty: float = 0.22,
    max_duty: float = 0.54,
) -> np.ndarray:
    """
    将高度图转换为左上角受光、线宽随高度与斜率变化的无缝二值木刻排线单通道图 (uint8 {0, 255})。
    """
    if height_u8.shape != (size, size):
        height_u8 = cv2.resize(height_u8, (size, size), interpolation=cv2.INTER_AREA)

    # 1. 归一化高度 H ∈ [0, 1] 并做周期高斯平滑避免高频碎裂
    pad = 6
    h_wrap = np.pad(height_u8.astype(np.float32) / 255.0, ((pad, pad), (pad, pad)), mode="wrap")
    h_smooth = cv2.GaussianBlur(h_wrap, (5, 5), 1.1)[pad:-pad, pad:-pad]
    h_min, h_max = float(h_smooth.min()), float(h_smooth.max())
    h_norm = (h_smooth - h_min) / max(1e-6, h_max - h_min)

    # 2. 左上角固定光源 (-1/√2, -1/√2) 浮雕阴影量计算 (周期差分 np.roll 保证零接缝)
    dh_dx = 0.5 * (np.roll(h_norm, -1, axis=1) - np.roll(h_norm, 1, axis=1)) * float(size) / 32.0
    dh_dy = 0.5 * (np.roll(h_norm, -1, axis=0) - np.roll(h_norm, 1, axis=0)) * float(size) / 32.0
    # 背向左上光 (即朝向右下 dh_dx < 0, dh_dy < 0 或凹坑低处) 排线加粗
    shadow_slope = np.clip(0.5 - 0.35 * (dh_dx + dh_dy), 0.0, 1.0)
    shade = np.clip(0.60 * (1.0 - h_norm) + 0.40 * shadow_slope, 0.0, 1.0)

    # 3. 沿木刻斜向排线方向生成严格整数周期相位 + 手工刻刀微弯曲调制
    yy, xx = np.meshgrid(np.arange(size, dtype=np.float32), np.arange(size, dtype=np.float32), indexing="ij")
    # 手工刻刀微颤 (严格整数波数 2 与 3，幅度平缓确保不产生断线)
    gouge_wobble = (
        0.07 * np.sin(2.0 * np.pi * (2.0 * xx - 2.0 * yy) / float(size))
        + 0.05 * (h_norm - 0.5)
    )
    phase = np.mod((float(periods) * (xx + yy) / float(size)) + gouge_wobble, 1.0)

    # 4. 线宽 w = f(height, slope) 并二值化为 {0, 255}
    duty = min_duty + (max_duty - min_duty) * shade
    hatch_bool = np.abs(phase - 0.5) < (0.5 * duty)
    hatch_u8 = (hatch_bool.astype(np.uint8)) * 255

    # 5. 周期形态学整理并移除任何 <4px 孤立微粒
    cleaned = _periodic_morph(hatch_u8, ksize=3)
    cleaned = np.where(cleaned >= 128, 255, 0).astype(np.uint8)

    n_lbl, lbls, stats, _ = cv2.connectedComponentsWithStats((cleaned > 0).astype(np.uint8), connectivity=8)
    for idx in range(1, n_lbl):
        if int(stats[idx, cv2.CC_STAT_AREA]) < 4:
            cleaned[lbls == idx] = 0
    return cleaned


def build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="hatch_from_height.py",
        description="《桌面破坏神》将无缝高度图转换为 256×256 单通道 (R/L) 二值木刻排线平铺纹理",
    )
    parser.add_argument(
        "--height-map",
        type=Path,
        default=None,
        help="输入高度图路径；若未提供或配合 --procedural，则生成确定性无缝石板/羊皮纸高度图",
    )
    parser.add_argument(
        "--procedural",
        action="store_true",
        help="使用确定性程序化无缝石板/羊皮纸高度图并保存原图至 --save-height",
    )
    parser.add_argument(
        "--save-height",
        type=Path,
        default=DEFAULT_RAW_HEIGHT,
        help="程序化高度图原图保存路径 (默认: art_source/raw/tex_woodcut_hatch_256/height_stone_parchment_256.png)",
    )
    parser.add_argument("--out", type=Path, required=True, help="输出 256×256 单通道木刻排线 PNG 路径")
    parser.add_argument("--size", type=int, default=256, help="输出平铺尺寸 (默认: 256)")
    parser.add_argument("--periods", type=int, default=20, help="256px 跨度内的斜向木刻排线整数周期数 (默认: 20)")
    parser.add_argument("--seed", type=int, default=20261113, help="程序化高度图确定性随机种子")
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_arg_parser()
    args = parser.parse_args(argv)

    if args.procedural or args.height_map is None:
        height_u8 = generate_seamless_stone_parchment_height(size=args.size, seed=args.seed)
        args.save_height.parent.mkdir(parents=True, exist_ok=True)
        Image.fromarray(height_u8, mode="L").save(args.save_height, format="PNG", compress_level=9)
        src_desc = f"procedural(seed={args.seed}) -> {args.save_height}"
    else:
        if not args.height_map.exists():
            print(f"[X] 找不到输入高度图: {args.height_map}", file=sys.stderr)
            return 1
        height_u8 = np.array(Image.open(args.height_map).convert("L"), dtype=np.uint8)
        src_desc = str(args.height_map)

    hatch_u8 = convert_height_to_woodcut_hatch(
        height_u8=height_u8,
        size=args.size,
        periods=args.periods,
    )
    args.out.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(hatch_u8, mode="L").save(args.out, format="PNG", compress_level=9)

    duty_pct = float((hatch_u8 > 127).sum()) / float(args.size * args.size) * 100.0
    print(
        f"[+] 木刻排线平铺纹理已生成: {args.out} ({args.size}x{args.size}, mode=L, 排线占空比={duty_pct:.2f}%) | 来源: {src_desc}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
