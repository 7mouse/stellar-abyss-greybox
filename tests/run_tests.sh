#!/usr/bin/env bash
# 无头运行全部验收；任何引擎/脚本报错也算失败
cd "$(dirname "$0")/.."
godot --headless --import --quit >/dev/null 2>&1
out=$(mktemp)
godot --headless res://tests/test_main.tscn 2>&1 | tee "$out" | grep -av '^\[战斗\]'
code=${PIPESTATUS[0]}
if grep -aqE "SCRIPT ERROR|^ERROR:" "$out"; then echo "检测到引擎报错 → 失败"; exit 1; fi
exit $code
