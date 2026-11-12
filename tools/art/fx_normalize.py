#!/usr/bin/env python3
"""
《桌面破坏神》PixelFX 序列帧归一化与木刻三阶阈值图集打包工具 (fx_normalize.py)
版本: 1.1.0
依据:
  - docs/04_美术资产管线_v1.1.md (§2 工具总表、§3 第 7 行 fx_normalize、§5 统一加工流程)
  - docs/03_美术风格圣经_v1.0.md (§04.6 命名规范 vfx_{name}_{frames}f_{w}x{h}.png)
  - docs/verification_log.md ([V-01] .import 参数、[V-04] PixelFX 许可与禁 gallery/fonts)

处理管线:
  1. 解析 PixelFX 导出的 PNG 图集与 Aseprite 风格 JSON；
  2. 对每帧仅提取感知明度 (Luminance) 与 Alpha 遮罩，彻底剥离原版像素配色；
  3. 对明度与 Alpha 执行 4× 放大 (双三次/线性平滑去除像素阶梯)，随后重采样至统一帧尺寸；
  4. 将明度重新量化为 3 级木刻刀痕阈值 (0=暗/空, 128=中调烟尘, 255=白热核心)，生成锐利刻刀质感；
  5. 重新打包为紧凑网格灰度 PNG 图集 + 统一帧率 JSON；
  6. 可选一键合规导出至 assets/art/vfx/（生成 [V-01] .import 并更新 art_source/manifest.csv）。
"""

from __future__ import annotations

import argparse
import csv
import json
import math
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import cv2
import numpy as np
from PIL import Image

THIS_DIR = Path(__file__).resolve().parent
ROOT_DIR = THIS_DIR.parent.parent
if str(THIS_DIR) not in sys.path:
    sys.path.insert(0, str(THIS_DIR))

from export import build_godot_data_texture_import, load_licenses_map, MANIFEST_COLUMNS  # noqa: E402
from process_subject import compute_sha256, parse_size  # noqa: E402

TOOL_NAME: str = "fx_normalize.py"
TOOL_VERSION: str = "1.1.0"


def _extract_frames(sheet_rgba: np.ndarray, meta_json: dict[str, Any]) -> list[np.ndarray]:
    frames_raw = meta_json.get("frames", [])
    if not isinstance(frames_raw, list) or len(frames_raw) == 0:
        raise ValueError("PixelFX JSON 中未找到有效的 frames 数组")

    extracted: list[np.ndarray] = []
    for entry in frames_raw:
        rect = entry.get("frame", {})
        x = int(rect["x"])
        y = int(rect["y"])
        w = int(rect["w"])
        h = int(rect["h"])
        extracted.append(sheet_rgba[y : y + h, x : x + w].copy())
    return extracted


def _select_active_frames(frames: list[np.ndarray], target_frames: int) -> list[np.ndarray]:
    # 剔除完全透明或仅剩极微弱尾迹 (<1% 峰值像素) 的尾帧，再均匀采样到 target_frames
    counts = [int((f[:, :, 3] > 8).sum()) for f in frames]
    peak = max(counts) if counts else 0
    min_keep = max(16, int(round(peak * 0.015)))
    non_empty = [f for f, c in zip(frames, counts) if c >= min_keep]
    pool = non_empty if len(non_empty) >= max(4, target_frames // 2) else [f for f, c in zip(frames, counts) if c > 0]
    if not pool:
        pool = frames
    if target_frames <= 0 or len(pool) <= target_frames:
        return pool
    indices = np.linspace(0, len(pool) - 1, num=target_frames, dtype=int)
    return [pool[int(i)] for i in indices]


def _normalize_single_frame(
    frame_rgba: np.ndarray,
    out_w: int,
    out_h: int,
    upscale_factor: int = 4,
) -> np.ndarray:
    """
    1. 只取明度 (L = 0.299R + 0.587G + 0.114B)
    2. 4× 放大消除像素阶梯
    3. 缩放到统一帧尺寸并重新阈值化成 3 级 (0 / 128 / 255)
    """
    src_h, src_w = frame_rgba.shape[:2]
    rgb = frame_rgba[:, :, :3].astype(np.float32)
    alpha = frame_rgba[:, :, 3].astype(np.float32)

    luma = 0.299 * rgb[:, :, 0] + 0.587 * rgb[:, :, 1] + 0.114 * rgb[:, :, 2]
    # 预乘透明度后再放大，避免透明边缘暗边渗入
    luma_premul = luma * (alpha / 255.0)

    up_w = src_w * upscale_factor
    up_h = src_h * upscale_factor
    luma_up = cv2.resize(luma_premul, (up_w, up_h), interpolation=cv2.INTER_CUBIC)
    alpha_up = cv2.resize(alpha, (up_w, up_h), interpolation=cv2.INTER_CUBIC)

    # 高斯轻度柔化锯齿后在 4× 分辨率进行 3 级刻刀阈值化，再下采样至目标帧尺寸
    luma_up = cv2.GaussianBlur(luma_up, (5, 5), 1.1)
    alpha_up = cv2.GaussianBlur(alpha_up, (3, 3), 0.7)

    luma_scaled = cv2.resize(luma_up, (out_w, out_h), interpolation=cv2.INTER_AREA)
    alpha_scaled = cv2.resize(alpha_up, (out_w, out_h), interpolation=cv2.INTER_AREA)

    fg = alpha_scaled >= 48.0
    # 反解预乘明度，按 3 级阈值化 (暗/灰/白热核心)
    safe_a = np.where(alpha_scaled > 1.0, alpha_scaled / 255.0, 1.0)
    pure_luma = np.where(fg, np.clip(luma_scaled / safe_a, 0.0, 255.0), 0.0)

    quantized = np.zeros((out_h, out_w), dtype=np.uint8)
    quantized = np.where(fg & (pure_luma >= 45.0), 128, quantized)
    quantized = np.where(fg & (pure_luma >= 155.0), 255, quantized)
    # 仅保留非零明度可见区域为不透明遮罩，彻底消除背景噪点
    out_alpha = np.where(fg & (pure_luma >= 20.0), 255, 0).astype(np.uint8)
    quantized = np.where(out_alpha > 0, np.maximum(quantized, 64), 0).astype(np.uint8)
    # 严格收敛到 3 级非零/零值: 0, 128, 255
    quantized = np.where(out_alpha == 0, 0, np.where(pure_luma >= 155.0, 255, 128)).astype(np.uint8)

    out_rgba = np.zeros((out_h, out_w, 4), dtype=np.uint8)
    out_rgba[:, :, 0] = quantized
    out_rgba[:, :, 1] = quantized
    out_rgba[:, :, 2] = quantized
    out_rgba[:, :, 3] = out_alpha
    return out_rgba


def normalize_pixelfx_sheet(
    src_png: Path,
    src_json: Path,
    out_dir: Path,
    vfx_name: str,
    frame_size: tuple[int, int] = (128, 128),
    target_frames: int = 16,
    target_fps: int = 15,
    upscale_factor: int = 4,
    commit_hash: str = "",
) -> dict[str, Any]:
    if not src_png.exists():
        raise FileNotFoundError(f"找不到 PixelFX 原始图集 PNG: {src_png}")
    if not src_json.exists():
        raise FileNotFoundError(f"找不到 PixelFX 原始 JSON: {src_json}")

    sheet_rgba = np.array(Image.open(src_png).convert("RGBA"), dtype=np.uint8)
    meta_json = json.loads(src_json.read_text(encoding="utf-8"))

    raw_frames = _extract_frames(sheet_rgba, meta_json)
    selected = _select_active_frames(raw_frames, target_frames)
    fw, fh = frame_size
    norm_frames = [_normalize_single_frame(f, fw, fh, upscale_factor=upscale_factor) for f in selected]

    n_frames = len(norm_frames)
    cols = max(1, int(math.ceil(math.sqrt(n_frames))))
    rows = max(1, int(math.ceil(n_frames / cols)))

    atlas = np.zeros((rows * fh, cols * fw, 4), dtype=np.uint8)
    frame_entries: list[dict[str, Any]] = []
    duration_ms = max(1, int(round(1000.0 / max(1, target_fps))))

    for idx, f_arr in enumerate(norm_frames):
        r_idx = idx // cols
        c_idx = idx % cols
        x0 = c_idx * fw
        y0 = r_idx * fh
        atlas[y0 : y0 + fh, x0 : x0 + fw] = f_arr
        frame_entries.append(
            {
                "filename": f"{vfx_name} {idx}",
                "frame": {"x": x0, "y": y0, "w": fw, "h": fh},
                "rotated": False,
                "trimmed": False,
                "spriteSourceSize": {"x": 0, "y": 0, "w": fw, "h": fh},
                "sourceSize": {"w": fw, "h": fh},
                "duration": duration_ms,
            }
        )

    out_dir.mkdir(parents=True, exist_ok=True)
    stem = f"vfx_{vfx_name}_{n_frames}f_{fw}x{fh}"
    out_png = out_dir / f"{stem}.png"
    out_json = out_dir / f"{stem}.json"

    Image.fromarray(atlas, mode="RGBA").save(out_png, format="PNG", compress_level=9)

    out_meta: dict[str, Any] = {
        "frames": frame_entries,
        "meta": {
            "app": f"{TOOL_NAME}@{TOOL_VERSION}",
            "source_app": "https://github.com/patch-gg/pixelfx",
            "source_commit": commit_hash,
            "source_effect": str(meta_json.get("meta", {}).get("pixelfx", {}).get("id", vfx_name)),
            "image": out_png.name,
            "format": "RGBA8888",
            "size": {"w": int(cols * fw), "h": int(rows * fh)},
            "fps": target_fps,
            "columns": cols,
            "rows": rows,
            "quantize_levels": [0, 128, 255],
            "upscale_factor": upscale_factor,
        },
    }
    out_json.write_text(json.dumps(out_meta, ensure_ascii=False, indent=2), encoding="utf-8")

    return {
        "out_png": out_png,
        "out_json": out_json,
        "frames": n_frames,
        "frame_size": [fw, fh],
        "atlas_size": [int(cols * fw), int(rows * fh)],
        "raw_sha256": compute_sha256(src_png),
        "processed_sha256": compute_sha256(out_png),
    }


def register_vfx_export(
    out_png: Path,
    asset_id: str,
    raw_sha256: str,
    license_id: str,
    source_ref: str,
    notes: str,
    manifest_path: Path = ROOT_DIR / "art_source" / "manifest.csv",
    licenses_path: Path = ROOT_DIR / "art_source" / "licenses" / "LICENSES.csv",
    project_root: Path = ROOT_DIR,
) -> dict[str, str]:
    licenses_map = load_licenses_map(licenses_path)
    if license_id not in licenses_map:
        raise ValueError(f"许可证 ID '{license_id}' 未在 {licenses_path} 中登记！")
    if licenses_map[license_id].get("source_type", "").strip() != "pixelfx":
        raise ValueError(f"许可证 '{license_id}' source_type 必须为 pixelfx")

    png_abs = out_png.resolve()
    root_abs = project_root.resolve()
    rel_posix = png_abs.relative_to(root_abs).as_posix()
    res_uri = f"res://{rel_posix}"
    import_path = Path(str(png_abs) + ".import")
    import_path.write_text(build_godot_data_texture_import(res_uri, png_abs.name), encoding="utf-8", newline="\n")

    processed_sha256 = compute_sha256(png_abs)
    now_iso = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    existing_rows: list[dict[str, str]] = []
    if manifest_path.exists():
        with manifest_path.open("r", encoding="utf-8", newline="") as f:
            reader = csv.DictReader(f)
            if reader.fieldnames and set(MANIFEST_COLUMNS).issubset(set(reader.fieldnames)):
                existing_rows = list(reader)

    new_entry: dict[str, str] = {
        "asset_id": asset_id,
        "category": "vfx",
        "version": "v01",
        "prompt_file": source_ref,
        "source_type": "pixelfx",
        "license_id": license_id,
        "tool_chain": f"{TOOL_NAME}@{TOOL_VERSION}",
        "raw_sha256": raw_sha256,
        "processed_sha256": processed_sha256,
        "processed_path": rel_posix,
        "qa_status": "PASS",
        "reviewer": "art-tools",
        "updated_at": now_iso,
        "notes": notes,
    }

    replaced = False
    for idx, row in enumerate(existing_rows):
        if row.get("processed_path") == rel_posix or row.get("asset_id") == asset_id:
            existing_rows[idx] = new_entry
            replaced = True
            break
    if not replaced:
        existing_rows.append(new_entry)

    manifest_path.parent.mkdir(parents=True, exist_ok=True)
    with manifest_path.open("w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=MANIFEST_COLUMNS)
        writer.writeheader()
        writer.writerows(existing_rows)

    return {
        "processed_path": rel_posix,
        "processed_sha256": processed_sha256,
        "import_path": str(import_path),
    }


def build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="fx_normalize.py",
        description="《桌面破坏神》PixelFX 灰度三阶木刻图集归一化与导出工具",
    )
    parser.add_argument("--src-png", type=Path, required=True, help="PixelFX 导出的原始 PNG 图集路径")
    parser.add_argument("--src-json", type=Path, required=True, help="PixelFX 导出的 Aseprite 风格 JSON 路径")
    parser.add_argument("--out-dir", type=Path, default=ROOT_DIR / "assets" / "art" / "vfx", help="输出目录")
    parser.add_argument("--name", type=str, required=True, help="标准化特效短名 (如 explosion_small)")
    parser.add_argument("--frame-size", type=str, default="128x128", help="统一单帧尺寸 WxH (默认: 128x128)")
    parser.add_argument("--target-frames", type=int, default=16, help="归一化采样帧数 (默认: 16)")
    parser.add_argument("--fps", type=int, default=15, help="统一导出帧率 (默认: 15)")
    parser.add_argument("--upscale", type=int, default=4, help="去像素阶梯放大倍数 (默认: 4)")
    parser.add_argument("--commit", type=str, default="", help="PixelFX 仓库 commit 哈希")
    parser.add_argument("--register", action="store_true", help="生成 [V-01] .import 并登记到 manifest.csv")
    parser.add_argument("--asset-id", type=str, default="vfx_explosion_small", help="manifest 中的 asset_id")
    parser.add_argument("--license-id", type=str, default="LIC-PIXELFX-01", help="LICENSES.csv 中的许可证 ID")
    parser.add_argument("--notes", type=str, default="PixelFX MIT 灰度三阶刻刀图集", help="manifest 备注")
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_arg_parser()
    args = parser.parse_args(argv)
    f_size = parse_size(args.frame_size)

    res = normalize_pixelfx_sheet(
        src_png=args.src_png,
        src_json=args.src_json,
        out_dir=args.out_dir,
        vfx_name=args.name,
        frame_size=f_size,
        target_frames=args.target_frames,
        target_fps=args.fps,
        upscale_factor=args.upscale,
        commit_hash=args.commit,
    )
    print(
        f"[+] fx_normalize 完成: {res['out_png']} ({res['frames']} 帧, "
        f"单帧={res['frame_size'][0]}x{res['frame_size'][1]}, 图集={res['atlas_size'][0]}x{res['atlas_size'][1]})"
    )

    if args.register:
        reg = register_vfx_export(
            out_png=res["out_png"],
            asset_id=args.asset_id,
            raw_sha256=res["raw_sha256"],
            license_id=args.license_id,
            source_ref=f"pixelfx@{args.commit[:12] if args.commit else 'local'}:explosions/small-explosion",
            notes=args.notes,
        )
        print(f"[+] 已生成 .import 并登记 manifest.csv: {reg['processed_path']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
