#!/bin/bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="${1:-$ROOT_DIR/dist}"
STAGE_DIR="$(mktemp -d)"
trap 'rm -rf "$STAGE_DIR"' EXIT

WINDOWS_DIR="$STAGE_DIR/windows/lazyfish-assistant"
MACOS_DIR="$STAGE_DIR/macos/lazyfish-assistant"
mkdir -p "$WINDOWS_DIR/scripts" "$MACOS_DIR/scripts" "$OUTPUT_DIR"
OUTPUT_DIR="$(cd "$OUTPUT_DIR" && pwd)"

for target in "$WINDOWS_DIR" "$MACOS_DIR"; do
  cp \
    "$ROOT_DIR/.env.example" \
    "$ROOT_DIR/docker-compose.yml" \
    "$ROOT_DIR/docker-compose.vnc.yml" \
    "$ROOT_DIR/global_config.yml" \
    "$ROOT_DIR/客户使用说明.txt" \
    "$target/"
done

cp "$ROOT_DIR"/*.bat "$WINDOWS_DIR/"
cp "$ROOT_DIR/scripts/lazyfish-windows.ps1" "$WINDOWS_DIR/scripts/"
cp "$ROOT_DIR"/*.command "$MACOS_DIR/"
cp "$ROOT_DIR/scripts/lazyfish-macos.sh" "$MACOS_DIR/scripts/"
chmod +x "$MACOS_DIR"/*.command "$MACOS_DIR/scripts/lazyfish-macos.sh"

rm -f \
  "$OUTPUT_DIR/lazyfish-assistant-windows.zip" \
  "$OUTPUT_DIR/lazyfish-assistant-macos.zip" \
  "$OUTPUT_DIR/SHA256SUMS"

python3 "$ROOT_DIR/scripts/create-deployment-zip.py" \
  "$WINDOWS_DIR" \
  "$OUTPUT_DIR/lazyfish-assistant-windows.zip"
python3 "$ROOT_DIR/scripts/create-deployment-zip.py" \
  "$MACOS_DIR" \
  "$OUTPUT_DIR/lazyfish-assistant-macos.zip"

if command -v sha256sum >/dev/null 2>&1; then
  (cd "$OUTPUT_DIR" && sha256sum lazyfish-assistant-*.zip > SHA256SUMS)
else
  (cd "$OUTPUT_DIR" && shasum -a 256 lazyfish-assistant-*.zip > SHA256SUMS)
fi

printf 'Created deployment kits in %s\n' "$OUTPUT_DIR"
