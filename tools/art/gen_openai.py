#!/usr/bin/env python3
"""
《桌面破坏神》GPT Image 主体资产受控生成器 (gen_openai.py)
版本: 1.2.0
依据:
  - docs/00_开发执行总纲.md (§2 勘误 E5、§3.1 环境变量红线、§5 WP-A2/WP-A3/WP-A4、§6.3 禁止事项、§7 V-02)
  - docs/04_美术资产管线_v1.1.md (§0 价格核实、§4 成本控制与脚本规格、§4.1 固定前缀提示词模板、§8 Agent 规则)
  - docs/verification_log.md ([V-02] / [V-02 补充] / [V-02 补充2] 实测 token 与单价)

安全红线 (硬编码执行):
  1. 默认仅从进程环境变量 os.environ 读取；仅当显式传入 --dotenv (项目负责人 WP-A3/WP-A4 授权模式) 时，
     在内存中解析根目录 .env 的 OPENAI_API_KEY / ART_BUDGET_USD / OPENAI_BASE_URL（若 .env 未设预算则默认 2.00 USD）。
  2. 严禁在任何终端、日志或异常信息中打印密钥明文或前后缀（含异常信息自动脱敏）。
  3. 当未传入 --dotenv 且进程环境变量未设置 OPENAI_API_KEY 或 ART_BUDGET_USD（或显式传入 --dry-run）时，
     100% 自动进入 dry-run 模式：零网络调用、零费用，完整输出模型、尺寸、质量、预估单价、累计账单、SHA-256 缓存键与完整组装 Prompt，退出码 0。
"""

from __future__ import annotations

import argparse
import base64
import csv
import hashlib
import json
import math
import os
import sys
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import yaml

TOOL_NAME: str = "gen_openai.py"
TOOL_VERSION: str = "1.2.0"

ROOT_DIR = Path(__file__).resolve().parent.parent.parent
DEFAULT_DOTENV_PATH = ROOT_DIR / ".env"
DEFAULT_PROMPTS_DIR = ROOT_DIR / "art_source" / "prompts"
DEFAULT_RAW_DIR = ROOT_DIR / "art_source" / "raw"
DEFAULT_LEDGER_CSV = ROOT_DIR / "art_source" / "ledger" / "openai_usage.csv"

# 严格对齐 docs/04_美术资产管线_v1.1.md §4.1 的不可修改固定前缀 (命中 OpenAI Prompt Prefix Cache)
STYLE_FIXED_PREFIX: str = (
    "STYLE (fixed prefix, never edit):\n"
    "A coarse relief woodcut print in strict two-tone: deep ink black and warm bone white, "
    "with limited gold-leaf gilding and one tiny muted accent. Thick confident gouge strokes, "
    "large solid black shadow shapes, coarse parallel hatching only in mid-tones, no gradients, "
    "no soft shading, no glow, no metallic reflections, no photorealism, no 3D render look. "
    "Light from the upper left. The background is a completely flat, uniform medium gray with nothing else. "
    "No frame, border, ground, text, letters, runes or symbols."
)

FINAL_EDIT_SUFFIX: str = (
    "Keep the exact pose, silhouette and composition of the first input image; "
    "match the line weight and carving texture of the second input image."
)

# 官方与 [V-02] 实测单价常数 (USD per 1,000,000 tokens)
RATE_TEXT_INPUT_PER_1M: float = 5.00
RATE_TEXT_CACHED_PER_1M: float = 1.25
RATE_IMAGE_INPUT_PER_1M: float = 8.00
RATE_IMAGE_OUTPUT_PER_1M: float = 30.00

# 基于 docs/verification_log.md [V-02] 实测的单张输出图像 token 基准表
EST_OUTPUT_IMAGE_TOKENS: dict[tuple[str, str], int] = {
    ("low", "1024x1024"): 824,      # [V-02] 两次实测固定为 824 tokens
    ("low", "1024x1536"): 950,
    ("low", "1536x1024"): 950,
    ("medium", "1024x1024"): 1056,
    ("medium", "1024x1536"): 1220,
    ("medium", "1536x1024"): 1220,
    ("high", "1024x1024"): 1120,
    ("high", "1024x1536"): 1353,    # [V-02 补充] 1536x1024 high 实测为 1353 tokens
    ("high", "1536x1024"): 1353,
}

LEDGER_COLUMNS: list[str] = [
    "timestamp",
    "asset_id",
    "model",
    "quality",
    "size",
    "request_hash",
    "input_tokens",
    "output_tokens",
    "est_cost_usd",
    "file",
]


def _file_sha256(path: Path | None) -> str:
    if path is None:
        return ""
    if not path.exists():
        raise FileNotFoundError(f"找不到参考图片文件: {path}")
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def load_prompt_card(card_path: Path) -> dict[str, Any]:
    if not card_path.exists():
        raise FileNotFoundError(f"找不到提示词卡: {card_path}")
    raw_text = card_path.read_text(encoding="utf-8")

    # 支持纯 YAML (.yaml/.yml) 或带 YAML Front-Matter 的 Markdown (.md)
    if card_path.suffix.lower() in {".yaml", ".yml"}:
        data = yaml.safe_load(raw_text)
    else:
        if raw_text.startswith("---"):
            parts = raw_text.split("---", 2)
            if len(parts) >= 3:
                data = yaml.safe_load(parts[1]) or {}
                if "subject_prompt" not in data:
                    data["subject_prompt"] = parts[2].strip()
            else:
                data = {"asset_id": card_path.stem, "subject_prompt": raw_text.strip()}
        else:
            data = {"asset_id": card_path.stem, "subject_prompt": raw_text.strip()}

    if not isinstance(data, dict):
        raise ValueError(f"提示词卡解析格式无效: {card_path}")
    for req_key in ("asset_id", "category", "subject_prompt"):
        if not data.get(req_key):
            raise ValueError(f"提示词卡 {card_path.name} 缺少必需字段: '{req_key}'")
    return data


def assemble_full_prompt(card: dict[str, Any], include_final_edit_clause: bool = False) -> str:
    category = str(card.get("category", "monster")).strip()
    subject_body = str(card["subject_prompt"]).strip()
    constraints = str(card.get("hard_constraints", "")).strip()

    blocks: list[str] = [
        STYLE_FIXED_PREFIX,
        f"SUBJECT ({category}):\n{subject_body}",
    ]
    if constraints:
        blocks.append(f"HARD CONSTRAINTS:\n{constraints}")
    if include_final_edit_clause:
        blocks.append(FINAL_EDIT_SUFFIX)
    return "\n\n".join(blocks)


def compute_request_cache_key(
    model: str,
    quality: str,
    size: str,
    n: int,
    full_prompt: str,
    ref_sha256: str,
    anchor_sha256: str,
) -> str:
    canonical_payload = json.dumps(
        {
            "model": model,
            "quality": quality,
            "size": size,
            "n": n,
            "prompt": full_prompt,
            "ref_sha256": ref_sha256,
            "anchor_sha256": anchor_sha256,
        },
        sort_keys=True,
        ensure_ascii=False,
        separators=(",", ":"),
    )
    return hashlib.sha256(canonical_payload.encode("utf-8")).hexdigest()


def estimate_request_cost_usd(
    full_prompt: str,
    quality: str,
    size: str,
    n: int,
    num_input_images: int = 0,
) -> dict[str, float | int]:
    # 英文平均约 3.8 字符 / token ([V-02]: ~650 chars -> 161~179 tokens)
    est_text_tokens = max(120, int(math.ceil(len(full_prompt) / 3.8)))
    est_img_in_tokens = num_input_images * 560
    per_img_out_tokens = EST_OUTPUT_IMAGE_TOKENS.get((quality, size), 1353)
    est_img_out_tokens = per_img_out_tokens * n

    cost_text = est_text_tokens * RATE_TEXT_INPUT_PER_1M / 1_000_000.0
    cost_img_in = est_img_in_tokens * RATE_IMAGE_INPUT_PER_1M / 1_000_000.0
    cost_img_out = est_img_out_tokens * RATE_IMAGE_OUTPUT_PER_1M / 1_000_000.0
    total_est = cost_text + cost_img_in + cost_img_out

    return {
        "est_input_text_tokens": est_text_tokens,
        "est_input_image_tokens": est_img_in_tokens,
        "est_output_image_tokens": est_img_out_tokens,
        "est_unit_cost_usd": round(total_est / max(1, n), 6),
        "est_total_cost_usd": round(total_est, 6),
    }


def read_ledger_state(ledger_csv: Path) -> tuple[float, dict[str, dict[str, str]], dict[str, int]]:
    """
    读取现有台账，返回:
      - cumulative_spend_usd: 历史累计花费
      - cache_by_hash: request_hash -> 台账记录 (用于本地去重缓存)
      - counts_by_asset: asset_id -> 已调用次数 (用于重试上限检查)
    """
    if not ledger_csv.exists():
        return 0.0, {}, {}

    spent = 0.0
    cache_map: dict[str, dict[str, str]] = {}
    asset_counts: dict[str, int] = {}

    with ledger_csv.open("r", encoding="utf-8", newline="") as f:
        reader = csv.DictReader(f)
        for row in reader:
            try:
                spent += float(row.get("est_cost_usd") or 0.0)
            except ValueError:
                pass
            r_hash = (row.get("request_hash") or "").strip()
            f_path = (row.get("file") or "").strip()
            aid = (row.get("asset_id") or "").strip()
            if aid:
                asset_counts[aid] = asset_counts.get(aid, 0) + 1
            if r_hash and f_path:
                candidate = Path(f_path)
                if not candidate.is_absolute():
                    candidate = ROOT_DIR / candidate
                if candidate.exists():
                    cache_map[r_hash] = row

    return round(spent, 6), cache_map, asset_counts


def append_ledger_row(ledger_csv: Path, row_data: dict[str, Any]) -> None:
    ledger_csv.parent.mkdir(parents=True, exist_ok=True)
    file_exists = ledger_csv.exists() and ledger_csv.stat().st_size > 0
    with ledger_csv.open("a", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=LEDGER_COLUMNS)
        if not file_exists:
            writer.writeheader()
        writer.writerow({col: row_data.get(col, "") for col in LEDGER_COLUMNS})


def resolve_generation_params(
    card: dict[str, Any],
    mode_arg: str | None,
    quality_arg: str | None,
    size_arg: str | None,
    model_arg: str | None,
    n_arg: int | None,
    has_ref_images: bool,
) -> tuple[str, str, str, str, int]:
    mode = mode_arg or str(card.get("default_mode", "draft")).strip().lower()
    category = str(card.get("category", "monster")).strip().lower()

    default_size = str(card.get("size") or ("1024x1024" if category in {"icon", "prop"} else "1024x1536"))
    size = size_arg or default_size

    if mode == "draft":
        model = model_arg or "gpt-image-2.6-flare"
        quality = quality_arg or "low"
        n = n_arg if n_arg is not None else int(card.get("draft_n", 4))
    elif mode == "final":
        model = model_arg or ("gpt-image-2.6-sunburst" if has_ref_images else "gpt-image-2.6-flare")
        quality = quality_arg or "medium"
        n = n_arg if n_arg is not None else 1
    elif mode == "anchor":
        model = model_arg or str(card.get("model", "gpt-image-2.6-flare"))
        quality = quality_arg or str(card.get("quality", "high"))
        n = n_arg if n_arg is not None else 1
    else:
        raise ValueError(f"未知生成模式: {mode} (可选: draft, final, anchor)")

    return mode, model, quality, size, n


def _load_dotenv_in_memory(dotenv_path: Path) -> dict[str, str]:
    """
    仅当显式传入 --dotenv 时在内存中解析 .env 文件；绝不修改系统环境或打印任何密钥值。
    """
    result: dict[str, str] = {}
    if not dotenv_path.exists():
        return result
    for raw_line in dotenv_path.read_text(encoding="utf-8", errors="ignore").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        if line.startswith("export "):
            line = line[len("export ") :].strip()
        key, val = line.split("=", 1)
        key = key.strip()
        val = val.strip()
        if len(val) >= 2 and ((val[0] == '"' and val[-1] == '"') or (val[0] == "'" and val[-1] == "'")):
            val = val[1:-1]
        if key:
            result[key] = val
    return result


def _scrub_secret(msg: str, secret: str) -> str:
    if secret and len(secret) >= 6 and secret in msg:
        return msg.replace(secret, "<REDACTED_API_KEY>")
    return msg


def run_card_generation(
    card: dict[str, Any],
    card_source_label: str,
    mode_arg: str | None = None,
    quality_arg: str | None = None,
    size_arg: str | None = None,
    model_arg: str | None = None,
    n_arg: int | None = None,
    ref_path: Path | None = None,
    anchor_path: Path | None = None,
    out_dir: Path = DEFAULT_RAW_DIR,
    ledger_csv: Path = DEFAULT_LEDGER_CSV,
    explicit_dry_run: bool = False,
    force_retry: bool = False,
    use_dotenv: bool = False,
    dotenv_path: Path = DEFAULT_DOTENV_PATH,
) -> int:
    # 默认仅从进程环境变量读取；仅在显式 --dotenv 时从内存加载 .env，绝不打印密钥本身
    dotenv_map = _load_dotenv_in_memory(dotenv_path) if use_dotenv else {}
    env_api_key = os.environ.get("OPENAI_API_KEY", "").strip() or dotenv_map.get("OPENAI_API_KEY", "").strip()
    env_base_url = os.environ.get("OPENAI_BASE_URL", "").strip() or dotenv_map.get("OPENAI_BASE_URL", "").strip()
    env_budget_raw = os.environ.get("ART_BUDGET_USD", "").strip() or dotenv_map.get("ART_BUDGET_USD", "").strip()
    if use_dotenv and env_api_key and not env_budget_raw:
        env_budget_raw = "2.00"

    has_key = bool(env_api_key)
    has_budget = bool(env_budget_raw)

    auto_dry_run = (not has_key) or (not has_budget) or explicit_dry_run
    has_refs = (ref_path is not None) or (anchor_path is not None)

    mode, model, quality, size, n = resolve_generation_params(
        card=card,
        mode_arg=mode_arg,
        quality_arg=quality_arg,
        size_arg=size_arg,
        model_arg=model_arg,
        n_arg=n_arg,
        has_ref_images=has_refs,
    )

    asset_id = str(card["asset_id"]).strip()
    ref_hash = _file_sha256(ref_path)
    anc_hash = _file_sha256(anchor_path)
    full_prompt = assemble_full_prompt(card, include_final_edit_clause=(mode == "final" and has_refs))

    cache_key = compute_request_cache_key(
        model=model,
        quality=quality,
        size=size,
        n=n,
        full_prompt=full_prompt,
        ref_sha256=ref_hash,
        anchor_sha256=anc_hash,
    )

    num_refs = (1 if ref_path else 0) + (1 if anchor_path else 0)
    est = estimate_request_cost_usd(
        full_prompt=full_prompt,
        quality=quality,
        size=size,
        n=n,
        num_input_images=num_refs,
    )
    spent_usd, cache_map, asset_counts = read_ledger_state(ledger_csv)
    target_dir = out_dir / asset_id
    target_file_preview = target_dir / f"gen_{cache_key[:16]}.png"

    is_cached = (cache_key in cache_map) or (cache_key[:16] in cache_map)
    cached_row = cache_map.get(cache_key) or cache_map.get(cache_key[:16])

    if auto_dry_run:
        reason_parts: list[str] = []
        if explicit_dry_run:
            reason_parts.append("--dry-run flag")
        if not has_key:
            reason_parts.append("OPENAI_API_KEY unset")
        if not has_budget:
            reason_parts.append("ART_BUDGET_USD unset")
        reason_str = ", ".join(reason_parts)

        print("=" * 80)
        print(f"[DRY-RUN] {TOOL_NAME}@{TOOL_VERSION} | 触发原因: {reason_str}")
        print("=" * 80)
        print(f"  Prompt Card       : {card_source_label}")
        print(f"  Asset ID          : {asset_id} (category={card.get('category')})")
        print(f"  Mode / Tier       : {mode}")
        print(f"  Model             : {model}")
        print(f"  Size & Quality    : {size} | quality={quality} | n={n}")
        print(f"  Cache SHA-256     : {cache_key}")
        print(f"  Local Cache Hit   : {'YES ($0.00 skip)' if is_cached else 'NO (new request)'}")
        print(
            f"  Est. Tokens [V-02]: in_text~{est['est_input_text_tokens']}, "
            f"in_img~{est['est_input_image_tokens']}, out_img~{est['est_output_image_tokens']}"
        )
        print(
            f"  Est. Cost (USD)   : ${est['est_unit_cost_usd']:.6f} / image | "
            f"Total batch (n={n}): ${est['est_total_cost_usd']:.6f}"
        )
        print(f"  Ledger Spent SoFar: ${spent_usd:.6f} USD")
        print(f"  Planned Output    : {target_file_preview.relative_to(ROOT_DIR).as_posix() if target_file_preview.is_relative_to(ROOT_DIR) else target_file_preview}")
        print("-" * 80)
        print("  FULL PAYLOAD PROMPT:")
        for line in full_prompt.splitlines():
            print(f"    {line}")
        print("=" * 80)
        print()
        return 0

    # 1. 本地 SHA-256 请求去重缓存命中 -> 零费用直接返回
    if is_cached and cached_row is not None:
        print(f"[CACHE-HIT] 命中本地 SHA-256 缓存 ({cache_key[:16]}): {cached_row.get('file')} (本次费用 $0.00)")
        return 0

    # 2. 单件资产重试上限门禁 (docs/04 §4.4: 最多 1 轮草稿 + 2 次定稿 = 3 次请求记录)
    prior_calls = asset_counts.get(asset_id, 0)
    if prior_calls >= 3 and not force_retry:
        print(
            f"[X] 重试上限拦截: 资产 '{asset_id}' 已有 {prior_calls} 次生成记录（规范上限: 1轮草稿+2次定稿）。"
            "请先调整免费剪影草图，或由项目负责人审批 --force-retry！",
            file=sys.stderr,
        )
        return 3

    # 3. 硬性预算闸校验 (docs/04 §4.5 & docs/00 §6.3: 严禁超预算调用，严禁自行提高 ART_BUDGET_USD)
    try:
        budget_limit = float(env_budget_raw)
    except ValueError:
        print(f"[X] 预算闸错误: ART_BUDGET_USD 不是合法浮点数 ('{env_budget_raw}')", file=sys.stderr)
        return 2

    projected_total = spent_usd + float(est["est_total_cost_usd"])
    if budget_limit <= 0.0 or projected_total > budget_limit:
        print(
            f"[X] 预算闸硬拦截: 历史累计花费 ${spent_usd:.6f} + 本次预估 ${est['est_total_cost_usd']:.6f} "
            f"= ${projected_total:.6f} > 预算上限 ${budget_limit:.6f} USD！已拒绝发出 API 请求。",
            file=sys.stderr,
        )
        return 2

    # 4. 真实 API 调用 (仅在进程环境变量或 --dotenv 已提供密钥与充裕预算时执行)
    from openai import OpenAI

    client_kwargs: dict[str, Any] = {"api_key": env_api_key}
    if env_base_url:
        client_kwargs["base_url"] = env_base_url
    client = OpenAI(**client_kwargs)
    target_dir.mkdir(parents=True, exist_ok=True)

    try:
        if has_refs:
            ref_files = []
            try:
                if ref_path is not None:
                    ref_files.append(ref_path.open("rb"))
                if anchor_path is not None:
                    ref_files.append(anchor_path.open("rb"))
                res = client.images.edit(
                    model=model,
                    image=ref_files if len(ref_files) > 1 else ref_files[0],
                    prompt=full_prompt,
                    n=n,
                    quality=quality,
                    size=size,
                )
            finally:
                for fh in ref_files:
                    fh.close()
        else:
            res = client.images.generate(
                model=model,
                prompt=full_prompt,
                n=n,
                quality=quality,
                size=size,
            )
    except Exception as exc:
        safe_err = _scrub_secret(str(exc), env_api_key)
        print(f"[X] OpenAI API 调用异常 ({type(exc).__name__}): {safe_err}", file=sys.stderr)
        return 4

    usage = getattr(res, "usage", None)
    in_total = int(getattr(usage, "input_tokens", 0) or 0)
    out_total = int(getattr(usage, "output_tokens", 0) or 0)
    in_details = getattr(usage, "input_tokens_details", None)
    in_txt = int(getattr(in_details, "text_tokens", in_total) or 0)
    in_img = int(getattr(in_details, "image_tokens", 0) or 0)
    cached_txt = int(getattr(in_details, "cached_tokens", 0) or 0)
    uncached_txt = max(0, in_txt - cached_txt)

    if in_total == 0 and out_total == 0:
        actual_cost_usd = float(est["est_total_cost_usd"])
    else:
        actual_cost_usd = (
            uncached_txt * RATE_TEXT_INPUT_PER_1M / 1_000_000.0
            + cached_txt * RATE_TEXT_CACHED_PER_1M / 1_000_000.0
            + in_img * RATE_IMAGE_INPUT_PER_1M / 1_000_000.0
            + out_total * RATE_IMAGE_OUTPUT_PER_1M / 1_000_000.0
        )

    saved_files: list[Path] = []
    for idx, item in enumerate(res.data):
        suffix = f"_{idx + 1:02d}" if n > 1 else ""
        out_png = target_dir / f"gen_{cache_key[:16]}{suffix}.png"
        b64_data = getattr(item, "b64_json", None)
        if b64_data:
            out_png.write_bytes(base64.b64decode(b64_data))
        elif getattr(item, "url", None):
            with urllib.request.urlopen(item.url, timeout=60) as resp:
                out_png.write_bytes(resp.read())
        else:
            raise RuntimeError("API 响应既无 b64_json 也无 url 数据")
        saved_files.append(out_png)

    now_iso = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S")
    rel_saved = (
        saved_files[0].resolve().relative_to(ROOT_DIR.resolve()).as_posix()
        if saved_files[0].resolve().is_relative_to(ROOT_DIR.resolve())
        else str(saved_files[0])
    )
    append_ledger_row(
        ledger_csv,
        {
            "timestamp": now_iso,
            "asset_id": asset_id,
            "model": model,
            "quality": quality,
            "size": size,
            "request_hash": cache_key,
            "input_tokens": in_total,
            "output_tokens": out_total,
            "est_cost_usd": f"{actual_cost_usd:.6f}",
            "file": rel_saved,
        },
    )

    print(
        f"[+] 生成完成: {len(saved_files)} 张落盘至 {rel_saved} | "
        f"input_tokens={in_total} (cached={cached_txt}), output_tokens={out_total}, "
        f"实际费用=${actual_cost_usd:.6f} USD (累计=${spent_usd + actual_cost_usd:.6f} / 预算=${budget_limit:.2f})"
    )
    return 0


def build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="gen_openai.py",
        description=(
            "《桌面破坏神》GPT Image 主体生成器（支持 draft/final/anchor 档位、SHA-256 缓存、"
            "V-02 预算闸与台账记录；未配置环境变量且未传 --dotenv 时自动进入零费用 dry-run）"
        ),
    )
    src_group = parser.add_mutually_exclusive_group(required=True)
    src_group.add_argument("--card", type=Path, help="单张 YAML/Markdown 提示词卡路径")
    src_group.add_argument(
        "--all-cards",
        nargs="?",
        const=str(DEFAULT_PROMPTS_DIR),
        type=str,
        help="按文件名顺序批量处理目录下全部提示词卡 (默认目录: art_source/prompts)",
    )
    src_group.add_argument("--prompt", type=str, help="直接传入单次 SUBJECT 提示词文本 (需配合 --asset-id)")

    mode_group = parser.add_mutually_exclusive_group()
    mode_group.add_argument(
        "--mode",
        type=str,
        default=None,
        choices=["draft", "final", "anchor"],
        help="显式指定档位: draft(low) / final(medium+参考图) / anchor(high)",
    )
    mode_group.add_argument("--draft", action="store_true", help="快捷模式: 草稿档位 (Flare, low, n=4)")
    mode_group.add_argument("--final", action="store_true", help="快捷模式: 定稿编辑档位 (Sunburst, medium, n=1)")
    mode_group.add_argument("--anchor-mode", action="store_true", help="快捷模式: 锚点高精档位 (Flare, high, n=1)")

    parser.add_argument("--asset-id", type=str, default="adhoc_subject", help="配合 --prompt 使用的资产 ID")
    parser.add_argument(
        "--category",
        type=str,
        default="monster",
        choices=["monster", "boss", "icon", "prop"],
        help="配合 --prompt 使用的资产类别",
    )
    parser.add_argument("--quality", type=str, default=None, choices=["low", "medium", "high"], help="覆盖图像质量档位")
    parser.add_argument(
        "--size",
        type=str,
        default=None,
        choices=["1024x1024", "1024x1536", "1536x1024"],
        help="覆盖生成画布尺寸",
    )
    parser.add_argument("--model", type=str, default=None, help="覆盖模型名 (默认按档位自动选择 Flare/Sunburst)")
    parser.add_argument("--n", type=int, default=None, help="覆盖单次生成张数")
    parser.add_argument("--ref", type=Path, default=None, help="定稿模式参考图 1: 选中的草稿构图 PNG")
    parser.add_argument("--anchor", type=Path, default=None, help="定稿模式参考图 2: 冻结的风格锚点 PNG")
    parser.add_argument("--out-dir", type=Path, default=DEFAULT_RAW_DIR, help="原始输出根目录 (默认: art_source/raw)")
    parser.add_argument("--ledger", type=Path, default=DEFAULT_LEDGER_CSV, help="花费台账 CSV 路径")
    parser.add_argument("--dotenv", action="store_true", help="在内存中加载根目录 .env 授权配置 (绝不回显密钥)")
    parser.add_argument("--dotenv-path", type=Path, default=DEFAULT_DOTENV_PATH, help="自定义 .env 路径 (默认: 根目录 .env)")
    parser.add_argument("--dry-run", action="store_true", help="强制进入零网络零费用 dry-run 模式")
    parser.add_argument("--force-retry", action="store_true", help="经项目负责人批准后突破单资产 3 次调用上限")
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_arg_parser()
    args = parser.parse_args(argv)

    resolved_mode = args.mode
    if args.draft:
        resolved_mode = "draft"
    elif args.final:
        resolved_mode = "final"
    elif args.anchor_mode:
        resolved_mode = "anchor"

    if args.all_cards is not None:
        cards_dir = Path(args.all_cards)
        card_files = sorted(
            [p for p in cards_dir.iterdir() if p.is_file() and p.suffix.lower() in {".yaml", ".yml", ".md"}]
        )
        if not card_files:
            print(f"[X] 目录 {cards_dir} 下未找到任何提示词卡 (.yaml/.yml/.md)", file=sys.stderr)
            return 1
        for cf in card_files:
            card_obj = load_prompt_card(cf)
            cf_abs = cf.resolve()
            root_abs = ROOT_DIR.resolve()
            rel_label = cf_abs.relative_to(root_abs).as_posix() if cf_abs.is_relative_to(root_abs) else str(cf)
            rc = run_card_generation(
                card=card_obj,
                card_source_label=rel_label,
                mode_arg=resolved_mode,
                quality_arg=args.quality,
                size_arg=args.size,
                model_arg=args.model,
                n_arg=args.n,
                ref_path=args.ref,
                anchor_path=args.anchor,
                out_dir=args.out_dir,
                ledger_csv=args.ledger,
                explicit_dry_run=args.dry_run,
                force_retry=args.force_retry,
                use_dotenv=args.dotenv,
                dotenv_path=args.dotenv_path,
            )
            if rc != 0:
                return rc
        return 0

    if args.card is not None:
        card_obj = load_prompt_card(args.card)
        rel_label = args.card.resolve().relative_to(ROOT_DIR.resolve()).as_posix() if args.card.resolve().is_relative_to(ROOT_DIR.resolve()) else str(args.card)
    else:
        card_obj = {
            "asset_id": args.asset_id,
            "category": args.category,
            "default_mode": resolved_mode or "draft",
            "subject_prompt": args.prompt,
        }
        rel_label = "<cli:--prompt>"

    return run_card_generation(
        card=card_obj,
        card_source_label=rel_label,
        mode_arg=resolved_mode,
        quality_arg=args.quality,
        size_arg=args.size,
        model_arg=args.model,
        n_arg=args.n,
        ref_path=args.ref,
        anchor_path=args.anchor,
        out_dir=args.out_dir,
        ledger_csv=args.ledger,
        explicit_dry_run=args.dry_run,
        force_retry=args.force_retry,
        use_dotenv=args.dotenv,
        dotenv_path=args.dotenv_path,
    )


if __name__ == "__main__":
    sys.exit(main())
