#!/usr/bin/env bash
set -Eeuo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
temporary_directory="$(mktemp -d)"
trap 'rm -rf "$temporary_directory"' EXIT HUP INT TERM

source_script="$repository_root/scripts/install-linux.sh"
installed_script="$temporary_directory/lazyfish-assistant"

LAZYFISH_INSTALLER_LIBRARY_MODE=1 \
LAZYFISH_COMMAND_PATH="$installed_script" \
bash -c 'source "$1"; install_command' _ "$source_script"

cmp "$source_script" "$installed_script"
test -x "$installed_script"

LAZYFISH_INSTALLER_LIBRARY_MODE=1 \
LAZYFISH_COMMAND_PATH="$installed_script" \
bash -c 'source "$1"; install_command' _ "$installed_script"

printf 'Linux installer command installation tests passed.\n'
