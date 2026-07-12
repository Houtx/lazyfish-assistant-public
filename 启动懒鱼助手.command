#!/bin/bash
ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
"$ROOT_DIR/scripts/lazyfish-macos.sh" start
STATUS=$?
printf '\n'
read -r -p '按回车键关闭窗口...'
exit "$STATUS"
