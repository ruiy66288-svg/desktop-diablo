#!/usr/bin/env python3
"""
《桌面破坏神》美术资产受控导出、Godot 数据纹理 .import 生成与 Manifest 登记工具 (export.py)
版本: 1.1.0
依据:
  - docs/00_开发执行总纲.md (WP-A1, V-01)
  - docs/verification_log.md ([V-01] ResourceImporterTexture 四通道非 sRGB 数据纹理导入参数)
  - docs/04_美术资产管线_v1.1.md (§5 统一加工流程与 manifest/LICENSES 强制关联)

职责:
  1. 强制核验资产已通过 qa_report (可读取已有 QA JSON 或现场执行 evaluate_packed_asset)，未 PASS 严禁导出；
  2. 校验 license_id 已在 art_source/licenses/LICENSES.csv 合法登记且 source_type 匹配；
  3. 拷贝无损四通道 PNG 至目标路径，并自动生成符合 [V-01] 实测规范的配套 .import 文件：
       compress/mode=0, mipmaps/generate=true, detect_3d/compress_to=0,
       compress/channel_pack=1, process/hdr_as_srgb=false, process/fix_alpha_border=false
  4. 计算原始图与导出图的完整 64 位 SHA-256，幂等写入/更新 art_source/manifest.csv。
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import shutil
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

THIS_DIR = Path(__file__).resolve().parent
ROOT_DIR = THIS_DIR.parent.parent
if str(THIS_DIR) not in sys.path:
    sys.path.insert(0, str(THIS_DIR))

from process_subject import AccentFamilyType, CategoryType, TOOL_NAME as PROC_NAME, TOOL_VERSION as PROC_VER, compute_sha256  # noqa: E402
from qa_report import TOOL_NAME as QA_NAME, TOOL_VERSION as QA_VER, evaluate_packed_asset  # noqa: E402

TOOL_NAME: str = "export.py"
TOOL_VERSION: str = "1.1.0"

MANIFEST_COLUMNS: list[str] = [
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
]

# Godot 4 ResourceUID Base-34 字符表 (0-9 + a-z 排除 'l' 与 'o')
_GODOT_UID_CHARS: str = "0123456789abcdefghijkmnpqrstuvwxyz"


def _deterministic_godot_uid(seed_text: str) -> str:
    digest = hashlib.sha256(seed_text.encode("utf-8")).digest()
    # 取 62-bit 正整数 (< 2^63 - 1)，确保 Godot ResourceUID.text_to_id() 合法无溢出
    val = int.from_bytes(digest[:8], "big") & ((1 << 62) - 1)
    if val == 0:
        val = 1
    chars: list[str] = []
    base = len(_GODOT_UID_CHARS)
    while val > 0:
        val, rem = divmod(val, base)
        chars.append(_GODOT_UID_CHARS[rem])
    return "uid://" + "".join(reversed(chars))


def build_godot_data_texture_import(res_path: str, filename: str) -> str:
    """
    严格按 docs/verification_log.md [V-01] 生成 Godot 4.7.2 四通道数据纹理 .import 内容。
    """
    md5_hex = hashlib.md5(res_path.encode("utf-8")).hexdigest()
    ctex_path = f"res://.godot/imported/{filename}-{md5_hex}.ctex"
    uid_str = _deterministic_godot_uid(res_path)

    return (
        "[remap]\n\n"
        'importer="texture"\n'
        'type="CompressedTexture2D"\n'
        f'uid="{uid_str}"\n'
        f'path="{ctex_path}"\n'
        "metadata={\n"
        '"vram_texture": false\n'
        "}\n\n"
        "[deps]\n\n"
        f'source_file="{res_path}"\n'
        f'dest_files=["{ctex_path}"]\n\n'
        "[params]\n\n"
        "compress/mode=0\n"
        "compress/high_quality=false\n"
        "compress/lossy_quality=0.7\n"
        "compress/hdr_compression=1\n"
        "compress/normal_map=0\n"
        "compress/channel_pack=1\n"
        "mipmaps/generate=true\n"
        "mipmaps/limit=-1\n"
        "roughness/mode=0\n"
        'roughness/src_normal=""\n'
        "process/fix_alpha_border=false\n"
        "process/premult_alpha=false\n"
        "process/normal_map_invert_y=false\n"
        "process/hdr_as_srgb=false\n"
        "process/hdr_clamp_exposure=false\n"
        "process/size_limit=0\n"
        "detect_3d/compress_to=0\n"
    )


def load_licenses_map(licenses_csv: Path) -> dict[str, dict[str, str]]:
    if not licenses_csv.exists():
        raise FileNotFoundError(f"找不到许可证台账: {licenses_csv}")
    with licenses_csv.open("r", encoding="utf-8", newline="") as f:
        reader = csv.DictReader(f)
        return {row["license_id"].strip(): row for row in reader if row.get("license_id")}


def export_packed_asset(
    packed_path: Path,
    dest_path: Path,
    asset_id: str,
    category: CategoryType,
    version: str,
    prompt_file: str,
    source_type: str,
    license_id: str,
    raw_path: Path | None = None,
    raw_sha256: str | None = None,
    qa_json_path: Path | None = None,
    accent_family: AccentFamilyType = "auto",
    reviewer: str = "auto_qa",
    notes: str = "",
    manifest_path: Path = ROOT_DIR / "art_source" / "manifest.csv",
    licenses_path: Path = ROOT_DIR / "art_source" / "licenses" / "LICENSES.csv",
    project_root: Path = ROOT_DIR,
) -> dict[str, Any]:
    if not packed_path.exists():
        raise FileNotFoundError(f"找不到待导出的四通道 PNG: {packed_path}")
    if dest_path.suffix.lower() != ".png":
        raise ValueError(f"导出目标必须是无损 .png 文件: {dest_path}")

    # 1. 校验许可证台账
    licenses_map = load_licenses_map(licenses_path)
    if license_id not in licenses_map:
        raise ValueError(f"许可证 ID '{license_id}' 未在 {licenses_path} 中登记！")
    lic_row = licenses_map[license_id]
    if lic_row.get("source_type", "").strip() != source_type:
        raise ValueError(
            f"source_type '{source_type}' 与许可证 '{license_id}' 的类型 '{lic_row.get('source_type')}' 不一致！"
        )

    # 2. 强制核验 QA 状态必须为 PASS
    if qa_json_path is not None and qa_json_path.exists():
        qa_data = json.loads(qa_json_path.read_text(encoding="utf-8"))
        current_packed_hash = compute_sha256(packed_path)
        if qa_data.get("packed_sha256") != current_packed_hash:
            raise ValueError("QA 报告对应的文件 SHA-256 与当前待导出 PNG 不一致，请重新运行 qa_report.py！")
    else:
        qa_data = evaluate_packed_asset(
            packed_path=packed_path,
            category=category,
            accent_family=accent_family,
            raw_path=raw_path,
        )

    if qa_data.get("qa_status") != "PASS":
        raise RuntimeError(f"资产 [{asset_id}] 未通过量化质检 (qa_status={qa_data.get('qa_status')})，拒绝导出！")

    # 3. 解析输入原图哈希
    resolved_raw_hash = raw_sha256
    if not resolved_raw_hash:
        if raw_path is not None and raw_path.exists():
            resolved_raw_hash = compute_sha256(raw_path)
        elif isinstance(qa_data.get("raw_sha256"), str) and len(qa_data["raw_sha256"]) == 64:
            resolved_raw_hash = qa_data["raw_sha256"]
        else:
            raise ValueError("必须提供 --raw 原图文件或 64 位 --raw-sha256 以保证溯源哈希完整！")

    if len(resolved_raw_hash) != 64:
        raise ValueError(f"raw_sha256 必须是 64 位十六进制 SHA-256，当前为: {resolved_raw_hash}")

    # 4. 复制四通道 PNG 并生成配套 .import
    dest_abs = dest_path.resolve()
    root_abs = project_root.resolve()
    try:
        rel_posix = dest_abs.relative_to(root_abs).as_posix()
    except ValueError as exc:
        raise ValueError(f"目标路径 {dest_abs} 必须位于项目根目录 {root_abs} 之内") from exc

    dest_abs.parent.mkdir(parents=True, exist_ok=True)
    if packed_path.resolve() != dest_abs:
        shutil.copy2(packed_path, dest_abs)

    processed_hash = compute_sha256(dest_abs)
    res_uri = f"res://{rel_posix}"
    import_path = Path(str(dest_abs) + ".import")
    import_content = build_godot_data_texture_import(res_uri, dest_abs.name)
    import_path.write_text(import_content, encoding="utf-8", newline="\n")

    # 5. 幂等更新 manifest.csv
    tool_chain = f"{PROC_NAME}@{PROC_VER}+{QA_NAME}@{QA_VER}+{TOOL_NAME}@{TOOL_VERSION}"
    now_iso = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    existing_rows: list[dict[str, str]] = []
    if manifest_path.exists():
        with manifest_path.open("r", encoding="utf-8", newline="") as f:
            reader = csv.DictReader(f)
            if reader.fieldnames and set(MANIFEST_COLUMNS).issubset(set(reader.fieldnames)):
                existing_rows = list(reader)

    new_entry: dict[str, str] = {
        "asset_id": asset_id,
        "category": category,
        "version": version,
        "prompt_file": prompt_file,
        "source_type": source_type,
        "license_id": license_id,
        "tool_chain": tool_chain,
        "raw_sha256": resolved_raw_hash,
        "processed_sha256": processed_hash,
        "processed_path": rel_posix,
        "qa_status": "PASS",
        "reviewer": reviewer,
        "updated_at": now_iso,
        "notes": notes,
    }

    replaced = False
    for idx, row in enumerate(existing_rows):
        if row.get("processed_path") == rel_posix or (
            row.get("asset_id") == asset_id and row.get("version") == version
        ):
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
        "asset_id": asset_id,
        "dest_path": str(dest_abs),
        "import_path": str(import_path),
        "processed_path": rel_posix,
        "processed_sha256": processed_hash,
        "raw_sha256": resolved_raw_hash,
        "manifest_path": str(manifest_path),
    }


def build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="export.py",
        description="《桌面破坏神》将质检通过的四通道 PNG 导出为 Godot 数据纹理（含 V-01 .import）并登记 manifest.csv",
    )
    parser.add_argument("--packed", type=Path, required=True, help="通过 QA 的四通道 PNG 路径")
    parser.add_argument("--dest", type=Path, required=True, help="导出目标 PNG 路径 (如 assets/art/monsters/xxx.png)")
    parser.add_argument("--asset-id", type=str, required=True, help="唯一资产 ID (如 mon_undead_miser)")
    parser.add_argument(
        "--category",
        type=str,
        default="monster",
        choices=["monster", "boss", "icon", "prop"],
        help="资产类别 (默认: monster)",
    )
    parser.add_argument("--version", type=str, default="v01", help="版本号 (如 v01)")
    parser.add_argument("--prompt-file", type=str, required=True, help="提示词卡相对路径或 procedural 标识")
    parser.add_argument(
        "--source-type",
        type=str,
        required=True,
        choices=["openai", "procedural", "pixelfx", "megascans"],
        help="资产来源类型",
    )
    parser.add_argument("--license-id", type=str, required=True, help="LICENSES.csv 中登记的许可证 ID")
    parser.add_argument("--raw", type=Path, default=None, help="原始输入图路径 (用于自动计算 64 位 SHA-256)")
    parser.add_argument("--raw-sha256", type=str, default=None, help="可选：显式传入 64 位原始图 SHA-256")
    parser.add_argument("--qa-json", type=Path, default=None, help="可选：qa_report.py 输出的 JSON 报告路径")
    parser.add_argument(
        "--accent-family",
        type=str,
        default="auto",
        choices=["auto", "undead", "demon", "beast", "fallen_saint", "abyss", "none"],
        help="现场复核 QA 时使用的点缀色族 (默认: auto)",
    )
    parser.add_argument("--reviewer", type=str, default="auto_qa", help="质检审核人标记")
    parser.add_argument("--notes", type=str, default="", help="备注说明")
    parser.add_argument(
        "--manifest",
        type=Path,
        default=ROOT_DIR / "art_source" / "manifest.csv",
        help="manifest.csv 路径 (默认: art_source/manifest.csv)",
    )
    parser.add_argument(
        "--licenses",
        type=Path,
        default=ROOT_DIR / "art_source" / "licenses" / "LICENSES.csv",
        help="LICENSES.csv 路径 (默认: art_source/licenses/LICENSES.csv)",
    )
    parser.add_argument(
        "--project-root",
        type=Path,
        default=ROOT_DIR,
        help="计算 processed_path 与 res:// URI 的项目根目录 (默认: 仓库根目录)",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_arg_parser()
    args = parser.parse_args(argv)

    try:
        result = export_packed_asset(
            packed_path=args.packed,
            dest_path=args.dest,
            asset_id=args.asset_id,
            category=args.category,
            version=args.version,
            prompt_file=args.prompt_file,
            source_type=args.source_type,
            license_id=args.license_id,
            raw_path=args.raw,
            raw_sha256=args.raw_sha256,
            qa_json_path=args.qa_json,
            accent_family=args.accent_family,
            reviewer=args.reviewer,
            notes=args.notes,
            manifest_path=args.manifest,
            licenses_path=args.licenses,
            project_root=args.project_root,
        )
    except Exception as exc:
        print(f"[X] 导出失败: {exc}", file=sys.stderr)
        return 1

    print(f"[+] 资产已合规导出: {result['processed_path']}")
    print(f"    SHA-256 : {result['processed_sha256']}")
    print(f"    .import : {result['import_path']}")
    print(f"    Manifest: {result['manifest_path']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
