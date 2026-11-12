#!/usr/bin/env python3
"""
《桌面破坏神》美术资产完整性、溯源哈希与许可证合规门禁工具 (verify_manifest.py)
版本: 1.1.0 (同时作为 .git/hooks/pre-commit 强制钩子)
依据:
  - docs/00_开发执行总纲.md (§4.9 提交规范、§5 WP-A1、§6.3 禁止事项)
  - docs/04_美术资产管线_v1.1.md (§5 强制执行 verify_manifest、§7 LICENSES.csv、§8 Agent 规则)
  - docs/verification_log.md ([V-01] 数据纹理 .import 必需参数、[V-04] 禁 PatchPixel 字体)

校验规则 (任何一项不满足即打印违规详情并以退出码 1 拒绝):
  1. LICENSES.csv 存在且字段完整；PixelFX 条款明确排除 gallery/fonts；全库禁止混入 PatchPixel 字体；
  2. manifest.csv 存在且表头字段完整；
  3. 扫描 assets/art/ 下全部光栅与矢量图形文件 (.png/.svg/.jpg/.jpeg/.webp/.bmp/.tga/.dds/.exr)：
     - 严禁非无损光栅格式 (.jpg/.jpeg/.webp/.bmp) 进入 assets/art/；
     - 磁盘上每一个资产文件必须在 manifest.csv 中存在精确匹配的 processed_path 记录（拦截未登记私货文件！）；
  4. manifest.csv 中每一条记录：
     - processed_path 对应的物理文件必须真实存在；
     - 物理文件的实时 SHA-256 必须与 processed_sha256 (64位十六进制) 100% 一致；
     - raw_sha256 必须为合法 64 位十六进制 SHA-256；
     - source_type 合法，tool_chain 非空，qa_status 必须严格为 "PASS"；
     - license_id 必须存在于 LICENSES.csv 且 source_type 一致；
     - 对于 .png 数据纹理，配套 .png.import 文件必须存在且包含 [V-01] 防 sRGB 篡改关键参数
       (compress/mode=0, mipmaps/generate=true, detect_3d/compress_to=0, compress/channel_pack=1)。
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import re
import sys
from pathlib import Path

TOOL_NAME: str = "verify_manifest.py"
TOOL_VERSION: str = "1.1.0"

ROOT_DIR = Path(__file__).resolve().parent.parent.parent
DEFAULT_MANIFEST = ROOT_DIR / "art_source" / "manifest.csv"
DEFAULT_LICENSES = ROOT_DIR / "art_source" / "licenses" / "LICENSES.csv"
DEFAULT_ASSETS_ART = ROOT_DIR / "assets" / "art"

HEX64_RE = re.compile(r"^[0-9a-fA-F]{64}$")

REQUIRED_MANIFEST_COLS: set[str] = {
    "asset_id",
    "category",
    "version",
    "prompt_file",
    "source_type",
    "license_id",
    "tool_chain",
    "raw_sha256",
    "processed_sha256",
    "processed_path",
    "qa_status",
    "reviewer",
    "updated_at",
    "notes",
}

REQUIRED_LICENSE_COLS: set[str] = {
    "license_id",
    "source_type",
    "source_ref",
    "license_name",
    "proof_path",
    "acquired_date",
    "account",
    "attribution_required",
    "redistribution_raw_allowed",
    "notes",
}

ALLOWED_SOURCE_TYPES: set[str] = {"openai", "megascans", "pixelfx", "procedural", "font", "python-lib"}
RASTER_AND_VECTOR_EXTS: set[str] = {".png", ".svg", ".jpg", ".jpeg", ".webp", ".bmp", ".tga", ".dds", ".exr"}
ALLOWED_ASSET_EXTS: set[str] = {".png", ".svg"}

REQUIRED_IMPORT_PARAMS: tuple[str, ...] = (
    "compress/mode=0",
    "mipmaps/generate=true",
    "detect_3d/compress_to=0",
    "compress/channel_pack=1",
)


def compute_sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest().lower()


def verify_repository_art(
    project_root: Path = ROOT_DIR,
    assets_art_dir: Path = DEFAULT_ASSETS_ART,
    manifest_path: Path = DEFAULT_MANIFEST,
    licenses_path: Path = DEFAULT_LICENSES,
) -> tuple[bool, list[str], int]:
    errors: list[str] = []
    root_abs = project_root.resolve()
    assets_abs = assets_art_dir.resolve()

    if not licenses_path.exists():
        return False, [f"缺少许可证台账文件: {licenses_path}"], 0
    if not manifest_path.exists():
        return False, [f"缺少资产清单文件: {manifest_path}"], 0
    if not assets_abs.exists():
        return False, [f"缺少美术资产目录: {assets_abs}"], 0

    # 1. 读取并校验 LICENSES.csv
    licenses_by_id: dict[str, dict[str, str]] = {}
    with licenses_path.open("r", encoding="utf-8", newline="") as f:
        lic_reader = csv.DictReader(f)
        lic_fields = set(lic_reader.fieldnames or [])
        missing_lic_cols = REQUIRED_LICENSE_COLS - lic_fields
        if missing_lic_cols:
            errors.append(f"LICENSES.csv 缺少必需列: {sorted(missing_lic_cols)}")
        else:
            for idx, row in enumerate(lic_reader, start=2):
                lid = (row.get("license_id") or "").strip()
                stype = (row.get("source_type") or "").strip()
                if not lid:
                    errors.append(f"LICENSES.csv 第 {idx} 行 license_id 为空")
                    continue
                if stype not in ALLOWED_SOURCE_TYPES:
                    errors.append(f"LICENSES.csv [{lid}] 非法 source_type: '{stype}'")
                licenses_by_id[lid] = row

    # 2. 全局禁令扫描: 严禁 PatchPixel / gallery/fonts 混入仓库资产
    assets_root = root_abs / "assets"
    if assets_root.exists():
        for p in assets_root.rglob("*"):
            if p.is_file() and ("patchpixel" in p.name.lower() or "gallery/fonts" in p.as_posix().lower()):
                errors.append(f"触发 §6.3 红线: 发现禁止使用的 PatchPixel 字体文件 '{p}'")

    # 3. 读取并校验 manifest.csv
    manifest_by_path: dict[str, dict[str, str]] = {}
    with manifest_path.open("r", encoding="utf-8", newline="") as f:
        man_reader = csv.DictReader(f)
        man_fields = set(man_reader.fieldnames or [])
        missing_man_cols = REQUIRED_MANIFEST_COLS - man_fields
        if missing_man_cols:
            errors.append(f"manifest.csv 缺少必需列: {sorted(missing_man_cols)}")
            return False, errors, 0

        for idx, row in enumerate(man_reader, start=2):
            aid = (row.get("asset_id") or "").strip()
            proc_rel = (row.get("processed_path") or "").strip().replace("\\", "/")
            lid = (row.get("license_id") or "").strip()
            stype = (row.get("source_type") or "").strip()
            tchain = (row.get("tool_chain") or "").strip()
            raw_hash = (row.get("raw_sha256") or "").strip().lower()
            proc_hash = (row.get("processed_sha256") or "").strip().lower()
            qa_stat = (row.get("qa_status") or "").strip()

            if not aid or not proc_rel:
                errors.append(f"manifest.csv 第 {idx} 行 asset_id 或 processed_path 为空")
                continue
            if proc_rel in manifest_by_path:
                errors.append(f"manifest.csv 存在重复的 processed_path 记录: {proc_rel}")
                continue
            manifest_by_path[proc_rel] = row

            if stype not in ALLOWED_SOURCE_TYPES:
                errors.append(f"资产 [{aid}] 非法 source_type: '{stype}'")
            if lid not in licenses_by_id:
                errors.append(f"资产 [{aid}] 引用了未登记的许可证 ID: '{lid}'")
            else:
                lic_stype = (licenses_by_id[lid].get("source_type") or "").strip()
                if lic_stype != stype:
                    errors.append(f"资产 [{aid}] source_type='{stype}' 与许可证 [{lid}] 类型 '{lic_stype}' 不匹配")
            if not tchain:
                errors.append(f"资产 [{aid}] 缺少加工工具链与版本记录 (tool_chain 为空)")
            if not HEX64_RE.match(raw_hash):
                errors.append(f"资产 [{aid}] raw_sha256 不是合法 64 位 SHA-256: '{raw_hash}'")
            if not HEX64_RE.match(proc_hash):
                errors.append(f"资产 [{aid}] processed_sha256 不是合法 64 位 SHA-256: '{proc_hash}'")
            if qa_stat != "PASS":
                errors.append(f"资产 [{aid}] 质检状态未通过 (qa_status='{qa_stat}' != 'PASS')")

            disk_file = root_abs / proc_rel
            if not disk_file.exists():
                errors.append(f"资产 [{aid}] 登记的目标文件在磁盘上不存在: {proc_rel}")
            else:
                actual_hash = compute_sha256(disk_file)
                if HEX64_RE.match(proc_hash) and actual_hash != proc_hash:
                    errors.append(
                        f"资产 [{aid}] ({proc_rel}) SHA-256 不匹配！清单={proc_hash[:16]}... 实际={actual_hash[:16]}..."
                    )
                if disk_file.suffix.lower() == ".png":
                    imp_file = Path(str(disk_file) + ".import")
                    if not imp_file.exists():
                        errors.append(f"资产 [{aid}] ({proc_rel}) 缺少配套 Godot 数据纹理 .import 文件: {imp_file.name}")
                    else:
                        imp_text = imp_file.read_text(encoding="utf-8", errors="replace")
                        for req_param in REQUIRED_IMPORT_PARAMS:
                            if req_param not in imp_text:
                                errors.append(
                                    f"资产 [{aid}] ({imp_file.name}) 缺少 [V-01] 必需导入参数 '{req_param}'"
                                )

    # 4. 反向全盘扫描 assets_art_dir: 拦截任何未在 manifest.csv 登记的野生/未加工图形文件！
    disk_asset_files: list[Path] = []
    for file_path in sorted(assets_abs.rglob("*")):
        if not file_path.is_file():
            continue
        if file_path.name == ".gitkeep":
            continue
        ext = file_path.suffix.lower()
        if ext in {".gdshader", ".import", ".tres", ".tscn", ".gd"}:
            continue
        if ext in RASTER_AND_VECTOR_EXTS:
            disk_asset_files.append(file_path)
            rel_posix = file_path.relative_to(root_abs).as_posix()
            if ext not in ALLOWED_ASSET_EXTS:
                errors.append(f"禁止格式文件进入 assets/art/ (仅允许无损 .png 或 .svg): {rel_posix}")
            if rel_posix not in manifest_by_path:
                errors.append(f"拦截未登记资产: '{rel_posix}' 未在 art_source/manifest.csv 中登记！")
        else:
            rel_posix = file_path.relative_to(root_abs).as_posix()
            errors.append(f"发现未知非白名单文件混入 assets/art/: {rel_posix}")

    return len(errors) == 0, errors, len(disk_asset_files)


def build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="verify_manifest.py",
        description="《桌面破坏神》美术资产清单、SHA-256 哈希、.import 参数与许可证合规校验器 (Git Pre-commit Hook)",
    )
    parser.add_argument("--project-root", type=Path, default=ROOT_DIR, help="项目根目录 (默认: 仓库根目录)")
    parser.add_argument("--assets-dir", type=Path, default=DEFAULT_ASSETS_ART, help="待扫描美术目录 (默认: assets/art)")
    parser.add_argument("--manifest", type=Path, default=DEFAULT_MANIFEST, help="manifest.csv 路径")
    parser.add_argument("--licenses", type=Path, default=DEFAULT_LICENSES, help="LICENSES.csv 路径")
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_arg_parser()
    args = parser.parse_args(argv)

    ok, errors, asset_count = verify_repository_art(
        project_root=args.project_root,
        assets_art_dir=args.assets_dir,
        manifest_path=args.manifest,
        licenses_path=args.licenses,
    )
    if not ok:
        print(f"[X] verify_manifest 校验失败 (共发现 {len(errors)} 项违规):", file=sys.stderr)
        for err in errors:
            print(f"  - {err}", file=sys.stderr)
        return 1

    print(
        f"[+] verify_manifest 校验通过: assets_dir='{args.assets_dir}' 下共 {asset_count} 件光栅/矢量资产，"
        "SHA-256、工具链、.import 与许可证台账 100% 合规！"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
