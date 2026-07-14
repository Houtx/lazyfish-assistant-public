#!/bin/bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="$ROOT_DIR/docker-compose.yml"
VNC_COMPOSE_FILE="$ROOT_DIR/docker-compose.vnc.yml"
ENV_FILE="$ROOT_DIR/.env"
ACTION="${1:-deploy}"
APP_URL=""
NOVNC_URL=""
VNC_PASSWORD_PATH=""

info() {
  printf '\n[%s] %s\n' "懒鱼助手" "$1"
}

fail() {
  printf '\n[错误] %s\n' "$1" >&2
  exit 1
}

find_docker() {
  if command -v docker >/dev/null 2>&1; then
    return 0
  fi

  local docker_cli="/Applications/Docker.app/Contents/Resources/bin"
  if [[ -x "$docker_cli/docker" ]]; then
    export PATH="$docker_cli:$PATH"
    return 0
  fi

  info "尚未安装 Docker Desktop，正在打开官方下载页面。"
  open "https://www.docker.com/products/docker-desktop/" >/dev/null 2>&1 || true
  fail "请先安装并启动 Docker Desktop，然后重新双击本脚本。"
}

wait_for_docker() {
  if docker info >/dev/null 2>&1; then
    return 0
  fi

  if [[ -d "/Applications/Docker.app" ]]; then
    info "正在启动 Docker Desktop，请稍候..."
    open -a Docker >/dev/null 2>&1 || true
  else
    fail "找不到 Docker Desktop，请先完成安装。"
  fi

  local attempt
  for attempt in $(seq 1 90); do
    if docker info >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done
  fail "Docker Desktop 启动超时。请确认它已正常运行后重试。"
}

check_compose() {
  if ! docker compose version >/dev/null 2>&1; then
    fail "当前 Docker 不支持 Compose v2，请升级 Docker Desktop。"
  fi
}

ensure_config() {
  if [[ ! -f "$ENV_FILE" ]]; then
    cp "$ROOT_DIR/.env.example" "$ENV_FILE"
    chmod 600 "$ENV_FILE"
    local port selected_port=""
    for port in $(seq 9000 9099); do
      if ! lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1; then
        selected_port="$port"
        awk -v selected_port="$port" '
          /^APP_PORT=/ { print "APP_PORT=" selected_port; next }
          { print }
        ' "$ENV_FILE" > "$ENV_FILE.tmp"
        mv "$ENV_FILE.tmp" "$ENV_FILE"
        chmod 600 "$ENV_FILE"
        break
      fi
    done
    if [[ -z "$selected_port" ]]; then
      fail "9000-9099 端口均被占用，请联系卖家协助处理。"
    fi
    info "已生成本机配置 .env。"
    if [[ "$selected_port" != "9000" ]]; then
      info "端口 9000 已被占用，已自动改用端口 ${selected_port}。"
    fi
  fi
}

read_env_value() {
  local key="$1"
  awk -F= -v key="$key" 'index($0, key "=") == 1 {sub(/^[^=]*=/, ""); gsub(/\r$/, ""); print; exit}' "$ENV_FILE"
}

append_env_default() {
  local key="$1" value="$2"
  if awk -F= -v key="$key" 'index($0, key "=") == 1 {found = 1; exit} END {exit !found}' "$ENV_FILE"; then
    return
  fi
  printf '\n%s=%s\n' "$key" "$value" >> "$ENV_FILE"
  chmod 0600 "$ENV_FILE"
}

migrate_vnc_env_defaults() {
  local novnc_port
  append_env_default "VNC_PASSWORD_FILE" "./secrets/vnc_password.txt"
  append_env_default "NOVNC_PORT" "6080"
  novnc_port="$(read_env_value NOVNC_PORT)"
  append_env_default \
    "MANUAL_VERIFICATION_URL" \
    "http://127.0.0.1:${novnc_port}/vnc.html?autoconnect=1&resize=scale"
  append_env_default "XY_MANUAL_SLIDER_TAKEOVER_TIMEOUT" "450"
}

resolve_vnc_password_path() {
  local configured_path
  configured_path="$(read_env_value VNC_PASSWORD_FILE)"
  if [[ -z "$configured_path" ]]; then
    configured_path="./secrets/vnc_password.txt"
    append_env_default "VNC_PASSWORD_FILE" "$configured_path"
  fi
  case "$configured_path" in
    /*) VNC_PASSWORD_PATH="$configured_path" ;;
    ./*) VNC_PASSWORD_PATH="$ROOT_DIR/${configured_path#./}" ;;
    *) VNC_PASSWORD_PATH="$ROOT_DIR/$configured_path" ;;
  esac
}

ensure_vnc_password() {
  local password_directory temporary password
  resolve_vnc_password_path
  password_directory="$(dirname "$VNC_PASSWORD_PATH")"
  mkdir -p "$password_directory"
  chmod 0700 "$password_directory"

  if [[ -s "$VNC_PASSWORD_PATH" ]]; then
    chmod 0600 "$VNC_PASSWORD_PATH"
    return
  fi

  temporary="$(mktemp "$password_directory/.vnc_password.tmp.XXXXXX")"
  if command -v openssl >/dev/null 2>&1; then
    password="$(openssl rand -base64 18 | tr -d '\r\n')"
  else
    password="$(LC_ALL=C od -An -N18 -tx1 /dev/urandom | tr -d '[:space:]')"
  fi
  [[ ${#password} -ge 8 ]] || fail "noVNC 随机密码生成失败。"
  (umask 077; printf '%s\n' "$password" > "$temporary")
  chmod 0600 "$temporary"
  mv -f "$temporary" "$VNC_PASSWORD_PATH"
}

configure_app_url() {
  local port
  port="$(read_env_value APP_PORT)"
  if [[ ! "$port" =~ ^[0-9]+$ ]]; then
    fail ".env 中的 APP_PORT 配置无效。"
  fi
  APP_URL="http://127.0.0.1:$port"
}

configure_vnc_access() {
  local port
  port="$(read_env_value NOVNC_PORT)"
  [[ "$port" =~ ^[0-9]+$ ]] || fail ".env 中的 NOVNC_PORT 配置无效。"
  NOVNC_URL="http://127.0.0.1:$port/vnc.html?autoconnect=1&resize=scale"
}

open_app() {
  if [[ "${LAZYFISH_NO_OPEN:-false}" != "true" ]]; then
    open "$APP_URL" >/dev/null 2>&1 || true
  fi
}

compose() {
  docker compose \
    --project-directory "$ROOT_DIR" \
    --env-file "$ENV_FILE" \
    -f "$COMPOSE_FILE" \
    -f "$VNC_COMPOSE_FILE" \
    "$@"
}

wait_for_app() {
  local attempt
  for attempt in $(seq 1 60); do
    if curl --fail --silent --max-time 3 "$APP_URL/health" >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done
  compose ps || true
  fail "服务启动超时，请保留窗口中的信息并联系卖家。"
}

show_initial_password() {
  local password
  password="$(compose exec -T lazyfish-assistant sh -c \
    'cat /app/data/.initial_admin_password 2>/dev/null || true' 2>/dev/null || true)"
  if [[ -n "$password" ]]; then
    printf '\n首次登录管理员账号：admin\n首次登录管理员密码：%s\n' "$password"
    printf '登录后请立即修改密码。\n'
  fi
}

show_vnc_access() {
  local password
  password="$(tr -d '\r\n' < "$VNC_PASSWORD_PATH")"
  printf '\n============================================================\n'
  printf '需要人工处理滑块时，请使用 noVNC 容器浏览器\n'
  printf 'noVNC 入口：%s\n' "$NOVNC_URL"
  printf 'noVNC 密码：%s\n' "$password"
  printf '底层 VNC 端口不发布，noVNC 仅绑定本机，不会对局域网或公网开放。\n'
  printf '============================================================\n'
}

deploy() {
  info "正在拉取最新稳定版本，首次下载可能需要几分钟..."
  compose pull lazyfish-assistant
  info "正在启动懒鱼助手..."
  compose up -d --remove-orphans lazyfish-assistant
  wait_for_app
  compose ps
  show_initial_password
  info "部署完成，访问地址：$APP_URL"
  show_vnc_access
  open_app
}

start_app() {
  info "正在启动懒鱼助手..."
  compose up -d lazyfish-assistant
  wait_for_app
  compose ps
  show_initial_password
  show_vnc_access
  open_app
}

stop_app() {
  info "正在停止懒鱼助手，客户数据不会被删除..."
  compose stop lazyfish-assistant
  compose ps
}

find_docker
wait_for_docker
check_compose
ensure_config
migrate_vnc_env_defaults
ensure_vnc_password
configure_app_url
configure_vnc_access

case "$ACTION" in
  deploy) deploy ;;
  start) start_app ;;
  stop) stop_app ;;
  status) compose ps ;;
  *) fail "未知操作：$ACTION" ;;
esac
