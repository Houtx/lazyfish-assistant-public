#!/usr/bin/env bash
set -Eeuo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
temporary_directory="$(mktemp -d)"
trap 'rm -rf "$temporary_directory"' EXIT HUP INT TERM

source_script="$repository_root/scripts/install-linux.sh"
installed_script="$temporary_directory/lazyfish-assistant"
if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
  use_real_chown="true"
else
  use_real_chown="false"
fi

LAZYFISH_INSTALLER_LIBRARY_MODE=1 \
LAZYFISH_COMMAND_PATH="$installed_script" \
bash -c 'source "$1"; install_command' _ "$source_script"

cmp "$source_script" "$installed_script"
test -x "$installed_script"

LAZYFISH_INSTALLER_LIBRARY_MODE=1 \
LAZYFISH_COMMAND_PATH="$installed_script" \
bash -c 'source "$1"; install_command' _ "$installed_script"

printf 'Linux installer command installation tests passed.\n'

install_root="$temporary_directory/install"
compose_capture="$temporary_directory/compose-arguments.txt"
chown_capture="$temporary_directory/chown-arguments.txt"
mkdir -p "$install_root"
cp "$repository_root/.env.example" "$install_root/.env"

LAZYFISH_INSTALLER_LIBRARY_MODE=1 \
LAZYFISH_INSTALL_DIR="$install_root" \
COMPOSE_CAPTURE="$compose_capture" \
CHOWN_CAPTURE="$chown_capture" \
USE_REAL_CHOWN="$use_real_chown" \
bash -c '
  set -Eeuo pipefail
  source "$1"
  if [[ "$USE_REAL_CHOWN" != "true" ]]; then
    chown() {
      printf "%s\n" "$*" >> "$CHOWN_CAPTURE"
    }
  fi

  file_owner() {
    stat -c "%u:%g" "$1" 2>/dev/null || stat -f "%u:%g" "$1"
  }
  file_mode() {
    stat -c "%a" "$1" 2>/dev/null || stat -f "%Lp" "$1"
  }

  ensure_vnc_password
  password_before="$(cat "$VNC_PASSWORD_PATH")"
  if [[ "$USE_REAL_CHOWN" == "true" ]]; then
    test "$(file_owner "$VNC_PASSWORD_PATH")" = "10001:10001"
    chown 0:0 "$VNC_PASSWORD_PATH"
  fi
  ensure_vnc_password
  test "$(cat "$VNC_PASSWORD_PATH")" = "$password_before"
  test ${#password_before} -ge 8
  if [[ "$USE_REAL_CHOWN" == "true" ]]; then
    test "$(file_owner "$VNC_PASSWORD_PATH")" = "10001:10001"
  fi
  test "$(file_mode "$(dirname "$VNC_PASSWORD_PATH")")" = "700"
  test "$(file_mode "$VNC_PASSWORD_PATH")" = "600"

  docker() {
    printf "%s\n" "$@" > "$COMPOSE_CAPTURE"
  }
  compose ps
' _ "$source_script"

grep -Fx -- "$install_root/docker-compose.yml" "$compose_capture" >/dev/null
grep -Fx -- "$install_root/docker-compose.vnc.yml" "$compose_capture" >/dev/null
if [[ "$use_real_chown" != "true" ]]; then
  test "$(grep -Fc -- "10001:10001 $install_root/secrets/.vnc_password.tmp." "$chown_capture")" = "1"
  test "$(grep -Fxc -- "10001:10001 $install_root/secrets/vnc_password.txt" "$chown_capture")" = "1"
fi
grep -Fq 'user: "10001:10001"' "$repository_root/docker-compose.yml"

grep -Fq '127.0.0.1:${NOVNC_PORT:-6080}:6080' "$repository_root/docker-compose.vnc.yml"
if grep -Fq ':5900' "$repository_root/docker-compose.vnc.yml"; then
  printf 'Raw VNC port 5900 must not be published.\n' >&2
  exit 1
fi

printf 'Linux noVNC deployment tests passed.\n'

legacy_root="$temporary_directory/legacy-install"
legacy_snapshot="$temporary_directory/legacy-env.snapshot"
mkdir -p "$legacy_root"
printf 'APP_PORT=9001\nLICENSE_KEY=legacy-license\n' > "$legacy_root/.env"

LAZYFISH_INSTALLER_LIBRARY_MODE=1 \
LAZYFISH_INSTALL_DIR="$legacy_root" \
bash -c '
  set -Eeuo pipefail
  source "$1"
  migrate_vnc_env_defaults
  cp "$ENV_FILE" "$2"
  migrate_vnc_env_defaults
  cmp "$ENV_FILE" "$2"

  grep -Fx "LICENSE_KEY=legacy-license" "$ENV_FILE" >/dev/null
  grep -Fx "VNC_PASSWORD_FILE=./secrets/vnc_password.txt" "$ENV_FILE" >/dev/null
  grep -Fx "NOVNC_PORT=6080" "$ENV_FILE" >/dev/null
  grep -Fx "MANUAL_VERIFICATION_URL=http://127.0.0.1:6080/vnc.html?autoconnect=1&resize=scale" "$ENV_FILE" >/dev/null
  grep -Fx "XY_MANUAL_SLIDER_TAKEOVER_TIMEOUT=450" "$ENV_FILE" >/dev/null
  test "$(grep -c "^VNC_PASSWORD_FILE=" "$ENV_FILE")" = "1"
  test "$(grep -c "^NOVNC_PORT=" "$ENV_FILE")" = "1"
  test "$(grep -c "^MANUAL_VERIFICATION_URL=" "$ENV_FILE")" = "1"
  test "$(grep -c "^XY_MANUAL_SLIDER_TAKEOVER_TIMEOUT=" "$ENV_FILE")" = "1"
' _ "$source_script" "$legacy_snapshot"

custom_root="$temporary_directory/custom-install"
custom_snapshot="$temporary_directory/custom-env.snapshot"
custom_chown_capture="$temporary_directory/custom-chown-arguments.txt"
mkdir -p "$custom_root"
printf '%s\n' \
  'APP_PORT=9002' \
  'VNC_PASSWORD_FILE=./private/vnc.txt' \
  'NOVNC_PORT=6099' \
  'XY_MANUAL_SLIDER_TAKEOVER_TIMEOUT=900' > "$custom_root/.env"

LAZYFISH_INSTALLER_LIBRARY_MODE=1 \
LAZYFISH_INSTALL_DIR="$custom_root" \
CUSTOM_CHOWN_CAPTURE="$custom_chown_capture" \
USE_REAL_CHOWN="$use_real_chown" \
bash -c '
  set -Eeuo pipefail
  source "$1"
  if [[ "$USE_REAL_CHOWN" != "true" ]]; then
    chown() {
      printf "%s\n" "$*" >> "$CUSTOM_CHOWN_CAPTURE"
    }
  fi
  migrate_vnc_env_defaults
  cp "$ENV_FILE" "$2"
  migrate_vnc_env_defaults
  cmp "$ENV_FILE" "$2"

  grep -Fx "VNC_PASSWORD_FILE=./private/vnc.txt" "$ENV_FILE" >/dev/null
  grep -Fx "NOVNC_PORT=6099" "$ENV_FILE" >/dev/null
  grep -Fx "MANUAL_VERIFICATION_URL=http://127.0.0.1:6099/vnc.html?autoconnect=1&resize=scale" "$ENV_FILE" >/dev/null
  grep -Fx "XY_MANUAL_SLIDER_TAKEOVER_TIMEOUT=900" "$ENV_FILE" >/dev/null
  ensure_vnc_password
  test "$VNC_PASSWORD_PATH" = "$LAZYFISH_INSTALL_DIR/private/vnc.txt"
  test -s "$VNC_PASSWORD_PATH"
' _ "$source_script" "$custom_snapshot"

if [[ "$use_real_chown" == "true" ]]; then
  test "$(stat -c '%u:%g' "$custom_root/private/vnc.txt")" = "10001:10001"
else
  grep -Fq -- "10001:10001 $custom_root/private/.vnc_password.tmp." "$custom_chown_capture"
fi

printf 'Legacy .env noVNC migration tests passed.\n'
