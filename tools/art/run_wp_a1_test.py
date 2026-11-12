#!/usr/bin/env python3
"""
《桌面破坏神》WP-A1 程序化测试主体全链路端到端验证脚本 (run_wp_a1_test.py)
依据:
  - 任务简报 #37 WP-A1 第 3 条:
    用 Python 程序化绘制一张含中灰底、墨黑木刻粗刀线、骨白块面、族群色标记、镀金挂锁/钱币几何元素的测试主体图，
    完整跑通 process_subject.py -> qa_report.py -> contact_sheet.py -> export.py -> verify_manifest.py，
    并实测放入无 manifest 记录的临时文件被 verify_manifest.py 非 0 退出码拦截后清理，
    全套流水线中间图、预览图与验证证据落盘 tools/out/wp_a1_test/，正式目录不残留未审批测试图。
"""

from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path

import cv2
import numpy as np
from PIL import Image

THIS_DIR = Path(__file__).resolve().parent
ROOT_DIR = THIS_DIR.parent.parent
OUT_DIR = ROOT_DIR / "tools" / "out" / "wp_a1_test"


def draw_procedural_woodcut_subject(out_raw_path: Path) -> Path:
    """
    在 1024x1280 纯平中灰底 (#808080) 画布上程序化绘制粗刀木刻怪物测试图：
      - 闭合墨黑外轮廓 (#0B0A0C, 线宽 >= 20px) + 右下阴影大块黑面 + 平行木刻粗刀痕
      - 左上 45° 受光骨白块面 (#E8DCC0)
      - 单一主导剪影特征: 锯齿骨冠
      - 族群油墨色点缀 (#7A0F14 血墨腰封标记, G 通道 <= 6%)
      - 财富腐化母题 (#C9A04E 嵌眼金币 + 胸前重型金挂锁与债链环, B 通道 <= 12%)
      - 双腿与双臂同躯干分离，验证外部与腿间中灰底被边缘连通 FloodFill 干净剥离且不伤内部结构
    """
    w, h = 1024, 1280
    bg_gray = (128, 128, 128)
    ink = (11, 10, 12)       # #0B0A0C
    bone = (232, 220, 192)   # #E8DCC0
    blood = (122, 15, 20)    # #7A0F14 (G 通道族群点缀)
    gold = (201, 160, 78)    # #C9A04E (B 通道镀金财富母题)

    img = np.full((h, w, 3), bg_gray, dtype=np.uint8)

    # 1. 先绘制闭合的墨黑大剪影底层 (y: 88..1178, 高度约 85.2%, 水平严格对称居中 cx=512)
    # 锯齿王冠 (单一主导剪影特征)
    crown_pts = np.array(
        [[372, 220], [352, 92], [438, 168], [512, 84], [586, 168], [672, 92], [652, 220]],
        dtype=np.int32,
    )
    cv2.fillPoly(img, [crown_pts], ink)

    # 颅骨与下颌
    cv2.ellipse(img, (512, 286), (138, 112), 0, 0, 360, ink, -1)
    cv2.rectangle(img, (430, 350), (594, 426), ink, -1)

    # 肩甲与胸腔躯干
    torso_pts = np.array(
        [[256, 440], [392, 404], [632, 404], [768, 440], [726, 560], [648, 566], [624, 796], [400, 796], [376, 566], [298, 560]],
        dtype=np.int32,
    )
    cv2.fillPoly(img, [torso_pts], ink)

    # 左右手臂 (与躯干留出明显镂空灰底间隙，符合 03 §02.2 四肢不得紧贴躯干)
    left_arm = np.array([[268, 540], [344, 548], [322, 856], [236, 844]], dtype=np.int32)
    right_arm = np.array([[680, 548], [756, 540], [788, 844], [702, 856]], dtype=np.int32)
    cv2.fillPoly(img, [left_arm, right_arm], ink)
    cv2.circle(img, (274, 876), 48, ink, -1)
    cv2.circle(img, (750, 876), 48, ink, -1)

    # 骨盆与分立双腿 (中间留出 76px 宽的灰底通道直通底部，验证边缘 FloodFill 穿透镂空区)
    cv2.rectangle(img, (376, 786), (648, 882), ink, -1)
    left_leg = np.array([[378, 876], [474, 876], [466, 1176], [352, 1176]], dtype=np.int32)
    right_leg = np.array([[550, 876], [646, 876], [672, 1176], [558, 1176]], dtype=np.int32)
    cv2.fillPoly(img, [left_leg, right_leg], ink)

    # 2. 左上 45° 主光受光面填充骨白块面 (#E8DCC0)，保留粗壮 >=22px 墨黑外轮廓与右侧大块重阴影
    crown_bone = np.array(
        [[396, 206], [382, 130], [444, 184], [510, 120], [568, 184], [626, 136], [616, 206]],
        dtype=np.int32,
    )
    cv2.fillPoly(img, [crown_bone], bone)

    # 颅骨受光左大半侧
    cv2.ellipse(img, (496, 284), (104, 84), 0, 0, 360, bone, -1)
    # 眼窝与鼻腔重黑块
    cv2.circle(img, (458, 282), 34, ink, -1)
    cv2.circle(img, (558, 282), 34, ink, -1)
    nose_pts = np.array([[510, 306], [492, 348], [530, 348]], dtype=np.int32)
    cv2.fillPoly(img, [nose_pts], ink)
    # 牙齿粗刀竖刻
    cv2.rectangle(img, (454, 364), (566, 404), bone, -1)
    for tx in (482, 510, 538):
        cv2.line(img, (tx, 360), (tx, 408), ink, 14)

    # 肩甲骨白块面 + 平行横刀痕表现金属肩甲 (严禁金属渐变，严格落实纠偏 #3)
    left_pauldron = np.array([[284, 454], [392, 426], [412, 538], [314, 538]], dtype=np.int32)
    right_pauldron = np.array([[612, 426], [724, 454], [696, 538], [604, 538]], dtype=np.int32)
    cv2.fillPoly(img, [left_pauldron, right_pauldron], bone)
    for py in (458, 488, 518):
        cv2.line(img, (286, py), (412, py), ink, 14)
        cv2.line(img, (604, py), (722, py), ink, 14)

    # 胸腔肋骨与腹甲粗刀木刻受光块面 (左上亮、右下留重黑，使主体墨黑比严格落在 35%~55% 中心区间)
    for idx, ry in enumerate((448, 506, 564, 622, 680, 736)):
        rib_w = 216 - idx * 6
        cv2.rectangle(img, (512 - rib_w // 2 - 8, ry), (512 + rib_w // 2 + 4, ry + 40), bone, -1)
    # 胸骨中轴暗槽刻线
    cv2.line(img, (512, 444), (512, 718), ink, 16)

    # 骨盆受光骨白块面
    cv2.rectangle(img, (398, 796), (622, 868), bone, -1)

    # 手臂受光骨白条块 + 粗平行刀痕
    cv2.fillPoly(img, [np.array([[280, 560], [330, 564], [310, 842], [252, 834]], dtype=np.int32)], bone)
    cv2.fillPoly(img, [np.array([[694, 564], [742, 560], [768, 834], [712, 842]], dtype=np.int32)], bone)
    cv2.circle(img, (270, 874), 32, bone, -1)
    cv2.circle(img, (746, 874), 32, bone, -1)

    # 腿部受光骨白长块 + 膝盖横刀刻痕
    cv2.fillPoly(img, [np.array([[392, 892], [458, 892], [450, 1156], [368, 1156]], dtype=np.int32)], bone)
    cv2.fillPoly(img, [np.array([[566, 892], [632, 892], [654, 1156], [572, 1156]], dtype=np.int32)], bone)
    cv2.line(img, (374, 1018), (468, 1018), ink, 16)
    cv2.line(img, (556, 1018), (656, 1018), ink, 16)

    # 3. 族群油墨点缀色 (G 通道: 血墨 #7A0F14 腰封契印布条，控制在 ~3.2% <= 6% 上限)
    sash_pts = np.array([[412, 804], [612, 804], [598, 858], [426, 858]], dtype=np.int32)
    cv2.fillPoly(img, [sash_pts], blood)
    cv2.line(img, (412, 831), (612, 831), ink, 12)

    # 4. 镀金财富腐化母题 (B 通道: #C9A04E 左眼嵌金币 + 胸前重型金挂锁与债链，控制在 ~6.5% <= 12% 上限)
    # 左眼窝嵌金币
    cv2.circle(img, (458, 282), 22, gold, -1)
    cv2.rectangle(img, (450, 274), (466, 290), ink, -1)

    # 斜跨胸前的粗金债链节
    chain_centers = [(404, 520), (452, 566), (566, 566), (614, 520)]
    for cx, cy in chain_centers:
        cv2.circle(img, (cx, cy), 24, ink, -1)
        cv2.circle(img, (cx, cy), 16, gold, -1)

    # 胸口中央重型镀金挂锁 (无文字纯几何钥匙孔)
    cv2.circle(img, (512, 592), 42, ink, -1)
    cv2.circle(img, (512, 592), 30, gold, -1)
    cv2.circle(img, (512, 592), 14, ink, -1)
    cv2.rectangle(img, (454, 608), (570, 718), ink, -1)
    cv2.rectangle(img, (468, 622), (556, 704), gold, -1)
    # 锁孔几何黑块
    cv2.circle(img, (512, 652), 14, ink, -1)
    cv2.rectangle(img, (504, 656), (520, 688), ink, -1)

    out_raw_path.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(img, mode="RGB").save(out_raw_path, format="PNG", compress_level=9)
    return out_raw_path


def run_cmd(cmd: list[str], expect_code: int = 0) -> subprocess.CompletedProcess[str]:
    proc = subprocess.run(
        cmd,
        cwd=str(ROOT_DIR),
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    if proc.returncode != expect_code:
        raise RuntimeError(
            f"命令退出码不符 (期望 {expect_code}, 实际 {proc.returncode}): {' '.join(cmd)}\n"
            f"STDOUT:\n{proc.stdout}\nSTDERR:\n{proc.stderr}"
        )
    return proc


def main() -> int:
    if OUT_DIR.exists():
        shutil.rmtree(OUT_DIR)
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    py = sys.executable
    log_lines: list[str] = ["=== WP-A1 程序化测试主体全流程实测日志 ==="]

    # 1. 生成程序化灰底粗刀木刻原图
    raw_png = OUT_DIR / "01_procedural_raw_gray.png"
    draw_procedural_woodcut_subject(raw_png)
    log_lines.append(f"[STEP 1] 程序化原图已生成: {raw_png.relative_to(ROOT_DIR).as_posix()}")

    # 2. 运行 process_subject.py
    packed_png = OUT_DIR / "02_packed_rgba_352x440.png"
    preview_png = OUT_DIR / "02_shader_preview_card.png"
    proc_json = OUT_DIR / "02_process_summary.json"
    res_proc = run_cmd(
        [
            py,
            "tools/art/process_subject.py",
            "--src",
            str(raw_png),
            "--out",
            str(packed_png),
            "--category",
            "monster",
            "--accent-family",
            "demon",
            "--preview",
            str(preview_png),
            "--json-summary",
            str(proc_json),
        ],
        expect_code=0,
    )
    log_lines.append(f"[STEP 2] process_subject.py -> exit=0\n{res_proc.stdout.strip()}")

    # 3. 运行 qa_report.py
    qa_json = OUT_DIR / "03_qa_report.json"
    qa_md = OUT_DIR / "03_qa_report.md"
    res_qa = run_cmd(
        [
            py,
            "tools/art/qa_report.py",
            "--packed",
            str(packed_png),
            "--category",
            "monster",
            "--accent-family",
            "demon",
            "--raw",
            str(raw_png),
            "--json-out",
            str(qa_json),
            "--md-out",
            str(qa_md),
        ],
        expect_code=0,
    )
    log_lines.append(f"[STEP 3] qa_report.py -> exit=0\n{res_qa.stdout.strip()}")

    # 4. 运行 contact_sheet.py
    contact_png = OUT_DIR / "04_contact_sheet.png"
    res_cs = run_cmd(
        [
            py,
            "tools/art/contact_sheet.py",
            "--packed",
            str(packed_png),
            "--raw",
            str(raw_png),
            "--category",
            "monster",
            "--accent-family",
            "demon",
            "--out",
            str(contact_png),
        ],
        expect_code=0,
    )
    log_lines.append(f"[STEP 4] contact_sheet.py -> exit=0\n{res_cs.stdout.strip()}")

    # 5. 受控导出至沙盒项目目录 (保留完整导出 PNG + V-01 .import + manifest.csv 证据供 @verifier 核查)
    sandbox_root = OUT_DIR / "05_exported_sandbox"
    sandbox_assets = sandbox_root / "assets" / "art" / "monsters"
    sandbox_manifest = sandbox_root / "art_source" / "manifest.csv"
    sandbox_licenses = ROOT_DIR / "art_source" / "licenses" / "LICENSES.csv"
    exported_png = sandbox_assets / "mon_demon_proc_test_v01.png"

    res_exp = run_cmd(
        [
            py,
            "tools/art/export.py",
            "--packed",
            str(packed_png),
            "--dest",
            str(exported_png),
            "--asset-id",
            "mon_demon_proc_test",
            "--category",
            "monster",
            "--version",
            "v01",
            "--prompt-file",
            "procedural:tools/art/run_wp_a1_test.py",
            "--source-type",
            "procedural",
            "--license-id",
            "LIC-PROC-01",
            "--raw",
            str(raw_png),
            "--qa-json",
            str(qa_json),
            "--accent-family",
            "demon",
            "--reviewer",
            "art-tools",
            "--notes",
            "WP-A1 程序化木刻测试主体全链路实测样本",
            "--manifest",
            str(sandbox_manifest),
            "--licenses",
            str(sandbox_licenses),
            "--project-root",
            str(sandbox_root),
        ],
        expect_code=0,
    )
    log_lines.append(f"[STEP 5A] export.py -> exit=0\n{res_exp.stdout.strip()}")

    # 5B. 对沙盒导出结果执行 verify_manifest.py 正向校验 (期望退出码 0)
    res_ver_ok = run_cmd(
        [
            py,
            "tools/art/verify_manifest.py",
            "--project-root",
            str(sandbox_root),
            "--assets-dir",
            str(sandbox_root / "assets" / "art"),
            "--manifest",
            str(sandbox_manifest),
            "--licenses",
            str(sandbox_licenses),
        ],
        expect_code=0,
    )
    log_lines.append(f"[STEP 5B] verify_manifest.py (沙盒已登记资产正向通过) -> exit=0\n{res_ver_ok.stdout.strip()}")

    # 6A. 在正式目录 assets/art/monsters/ 放入一个无 manifest 记录的临时文件，实测 verify_manifest.py (零参数 pre-commit 调用) 非 0 拦截！
    rogue_real_file = ROOT_DIR / "assets" / "art" / "monsters" / "_tmp_unregistered_rogue_test.png"
    try:
        shutil.copy2(packed_png, rogue_real_file)
        res_intercept = run_cmd([py, "tools/art/verify_manifest.py"], expect_code=1)
        log_lines.append(
            f"[STEP 6A] verify_manifest.py 拦截正式目录未登记临时文件 -> exit={res_intercept.returncode} (成功拦截!)\n"
            f"{res_intercept.stderr.strip()}"
        )
    finally:
        if rogue_real_file.exists():
            rogue_real_file.unlink()

    # 6B. 清理临时文件后再次运行零参数 verify_manifest.py，确认正式目录 100% 干净通过 (退出码 0)
    res_clean = run_cmd([py, "tools/art/verify_manifest.py"], expect_code=0)
    log_lines.append(f"[STEP 6B] 清理未登记临时文件后复跑 verify_manifest.py -> exit=0\n{res_clean.stdout.strip()}")

    log_file = OUT_DIR / "06_pipeline_and_hook_verification.txt"
    log_text = "\n\n".join(log_lines) + "\n"
    log_file.write_text(log_text, encoding="utf-8")
    print(log_text)
    return 0


if __name__ == "__main__":
    sys.exit(main())
