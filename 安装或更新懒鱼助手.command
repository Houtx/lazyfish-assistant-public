#!/bin/bash
ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
"$ROOT_DIR/scripts/lazyfish-macos.sh" deploy
STATUS=$?
printf '\n'
if [[ $STATUS -ne 0 ]]; then
  printf '执行失败，请保留本窗口中的错误信息并联系卖家。\n'
fi
read -r -p '按回车键关闭窗口...'
exit "$STATUS"
