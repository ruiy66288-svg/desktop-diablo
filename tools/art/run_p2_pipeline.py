#!/usr/bin/env python3
"""
《桌面破坏神》WP-P2-ART 7 件阶段 2 原创木刻资产一键后处理、质检、联系表与受控导出脚本
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

ROOT_DIR = Path(__file__).resolve().parent.parent.parent
OUT_DIR = ROOT_DIR / "tools" / "out" / "wp_p2_art"

P2_SUBJECTS = [
    {
        "asset_id": "mon_idol_scales",
        "category": "monster",
        "accent_family": "fallen_saint",
        "anchor": "art_source/anchors/anchor_monster_v1.png",
        "prompt": "art_source/prompts/mon_idol_scales.yaml",
        "dest": "assets/art/monsters/mon_idol_scales_v01.png",
        "notes": "WP-P2-ART Monster Family 4 Fallen Saint Gilded Idol (7/7 QA PASS)",
    },
    {
        "asset_id": "mon_cult_pawnbroker",
        "category": "monster",
        "accent_family": "abyss",
        "anchor": "art_source/anchors/anchor_monster_v1.png",
        "prompt": "art_source/prompts/mon_cult_pawnbroker.yaml",
        "dest": "assets/art/monsters/mon_cult_pawnbroker_v01.png",
        "notes": "WP-P2-ART Monster Family 5 Abyss Pawn-Cult (7/7 QA PASS)",
    },
    {
        "asset_id": "boss_rare_archon",
        "category": "boss",
        "accent_family": "abyss",
        "anchor": "art_source/anchors/anchor_boss_v1.png",
        "prompt": "art_source/prompts/boss_rare_archon.yaml",
        "dest": "assets/art/bosses/boss_rare_archon_v01.png",
        "notes": "WP-P2-ART Rare Summon Boss Covenant High Archon (7/7 QA PASS)",
    },
    {
        "asset_id": "uniq_weapon_thunder_blade",
        "category": "icon",
        "accent_family": "demon",
        "anchor": "art_source/anchors/anchor_icon_weapon_v1.png",
        "prompt": "art_source/prompts/uniq_weapon_thunder_blade.yaml",
        "dest": "assets/art/items/uniq_weapon_thunder_blade_v01.png",
        "notes": "WP-P2-ART Unique Weapon Thunder Debt-Blade (7/7 QA PASS)",
    },
    {
        "asset_id": "uniq_trinket_usurer_scales",
        "category": "icon",
        "accent_family": "fallen_saint",
        "anchor": "art_source/anchors/anchor_icon_helm_v1.png",
        "prompt": "art_source/prompts/uniq_trinket_usurer_scales.yaml",
        "dest": "assets/art/items/uniq_trinket_usurer_scales_v01.png",
        "notes": "WP-P2-ART Unique Trinket Usurer Scales (7/7 QA PASS)",
    },
    {
        "asset_id": "col_rune_abyss_summon",
        "category": "icon",
        "accent_family": "abyss",
        "anchor": "art_source/anchors/anchor_icon_helm_v1.png",
        "prompt": "art_source/prompts/col_rune_abyss_summon.yaml",
        "dest": "assets/art/items/col_rune_abyss_summon_v01.png",
        "notes": "WP-P2-ART Collectible Geometric Summon Rune (7/7 QA PASS)",
    },
    {
        "asset_id": "prop_wealth_ledger",
        "category": "icon",
        "accent_family": "demon",
        "anchor": "art_source/anchors/anchor_icon_helm_v1.png",
        "prompt": "art_source/prompts/prop_wealth_ledger.yaml",
        "dest": "assets/art/items/prop_wealth_ledger_v01.png",
        "notes": "WP-P2-ART Wealth Prop Coins & Debt Ledger (7/7 QA PASS)",
    },
]


def _run(cmd: list[str], allow_fail: bool = False) -> subprocess.CompletedProcess[str]:
    proc = subprocess.run(cmd, cwd=str(ROOT_DIR), text=True, capture_output=True, encoding="utf-8", errors="replace")
    if proc.stdout:
        print(proc.stdout.rstrip())
    if proc.stderr:
        print(proc.stderr.rstrip(), file=sys.stderr)
    if proc.returncode != 0 and not allow_fail:
        raise RuntimeError(f"Command failed ({proc.returncode}): {' '.join(cmd)}")
    return proc


def main() -> int:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    py = sys.executable
    failed: list[str] = []

    for item in P2_SUBJECTS:
        aid = item["asset_id"]
        raw_dir = ROOT_DIR / "art_source" / "raw" / aid
        pngs = sorted(raw_dir.glob("gen_*.png"), key=lambda p: p.stat().st_mtime)
        if not pngs:
            print(f"[X] {aid}: 找不到生成原图 ({raw_dir})")
            failed.append(aid)
            continue
        raw_png = pngs[-1]
        packed_png = OUT_DIR / f"{aid}_packed.png"
        qa_json = OUT_DIR / f"{aid}_qa.json"
        qa_md = OUT_DIR / f"{aid}_qa.md"
        sheet_png = OUT_DIR / f"{aid}_contact_sheet.png"

        print(f"\n=== Processing {aid} ({raw_png.name}) ===")
        _run([
            py, "tools/art/process_subject.py",
            "--src", str(raw_png),
            "--out", str(packed_png),
            "--category", item["category"],
            "--accent-family", item["accent_family"],
        ])
        qa_res = _run([
            py, "tools/art/qa_report.py",
            "--packed", str(packed_png),
            "--category", item["category"],
            "--accent-family", item["accent_family"],
            "--raw", str(raw_png),
            "--json-out", str(qa_json),
            "--md-out", str(qa_md),
        ], allow_fail=True)
        _run([
            py, "tools/art/contact_sheet.py",
            "--raw", str(raw_png),
            "--packed", str(packed_png),
            "--anchor", str(ROOT_DIR / item["anchor"]),
            "--category", item["category"],
            "--accent-family", item["accent_family"],
            "--out", str(sheet_png),
        ])

        if qa_res.returncode != 0:
            failed.append(aid)
            continue

        _run([
            py, "tools/art/export.py",
            "--packed", str(packed_png),
            "--dest", str(ROOT_DIR / item["dest"]),
            "--asset-id", aid,
            "--category", item["category"],
            "--version", "v01",
            "--prompt-file", item["prompt"],
            "--source-type", "openai",
            "--license-id", "LIC-OPENAI-01",
            "--raw", str(raw_png),
            "--qa-json", str(qa_json),
            "--accent-family", item["accent_family"],
            "--reviewer", "art-tools",
            "--notes", item["notes"],
        ])

    if failed:
        print(f"\n[!] 共 {len(failed)} 件资产需退回迭代: {failed}")
        return 1
    print("\n[+] 全部 7 件阶段 2 原创木刻资产 100% 通过 QA 并导出完成！")
    return 0


if __name__ == "__main__":
    sys.exit(main())
