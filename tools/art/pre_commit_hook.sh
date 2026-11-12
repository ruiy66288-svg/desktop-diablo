#!/usr/bin/env sh
# 《桌面破坏神》Git pre-commit 强制合规门禁钩子 (WP-A1)
# 安装位置: .git/hooks/pre-commit
# 作用: 提交前自动执行 tools/art/verify_manifest.py，拦截任何未登记、哈希不匹配、缺少许可或未通过 QA 的美术资产。

set -e

REPO_ROOT="$(git rev-parse --show-toplevel)"

if [ -x "/f/python/python.exe" ]; then
    PYTHON_BIN="/f/python/python.exe"
elif [ -x "F:/python/python.exe" ]; then
    PYTHON_BIN="F:/python/python.exe"
elif command -v python >/dev/null 2>&1; then
    PYTHON_BIN="python"
elif command -v python3 >/dev/null 2>&1; then
    PYTHON_BIN="python3"
else
    echo "[pre-commit] 错误: 找不到 Python 3.11+ 解释器，无法运行 verify_manifest.py！" >&2
    exit 1
fi

"$PYTHON_BIN" "$REPO_ROOT/tools/art/verify_manifest.py"
