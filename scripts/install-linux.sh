#!/usr/bin/env bash
set -Eeuo pipefail

readonly PRODUCT_NAME="懒鱼助手"
readonly INSTALL_DIR="${LAZYFISH_INSTALL_DIR:-/opt/lazyfish-assistant}"
readonly COMPOSE_FILE="$INSTALL_DIR/docker-compose.yml"
readonly VNC_COMPOSE_FILE="$INSTALL_DIR/docker-compose.vnc.yml"
readonly ENV_FILE="$INSTALL_DIR/.env"
readonly COMMAND_PATH="${LAZYFISH_COMMAND_PATH:-/usr/local/bin/lazyfish-assistant}"
readonly REPOSITORY="Houtx/lazyfish-assistant-public"
readonly BRANCH="main"
readonly ACTION="${1:-deploy}"

APP_PORT=""
APP_URL=""
NOVNC_URL=""
NOVNC_PORT_VALUE=""
VNC_PASSWORD_PATH=""
PUBLIC_IP=""
OS_FAMILY=""

info() {
  printf '\n[%s] %s\n' "$PRODUCT_NAME" "$1"
}

warn() {
  printf '\n[提醒] %s\n' "$1" >&2
}

fail() {
  printf '\n[错误] %s\n' "$1" >&2
  exit 1
}

require_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    fail "请使用官网命令运行安装器，命令中需要包含 sudo bash。"
  fi
}

detect_platform() {
  local architecture os_id os_like
  architecture="$(uname -m)"
  case "$architecture" in
    x86_64|amd64|aarch64|arm64) ;;
    *) fail "暂不支持当前 CPU 架构：$architecture（仅支持 amd64 和 arm64）。" ;;
  esac

  [[ -r /etc/os-release ]] || fail "无法识别 Linux 发行版：缺少 /etc/os-release。"
  # shellcheck disable=SC1091
  source /etc/os-release
  os_id="${ID:-}"
  os_like="${ID_LIKE:-}"
  case " $os_id $os_like " in
    *debian*|*ubuntu*) OS_FAMILY="debian" ;;
    *rhel*|*fedora*|*centos*|*rocky*|*almalinux*) OS_FAMILY="rhel" ;;
    *) fail "暂不支持当前 Linux 发行版：${PRETTY_NAME:-$os_id}。支持 Ubuntu、Debian、CentOS、RHEL、Rocky Linux 和 AlmaLinux。" ;;
  esac
}

install_base_tools() {
  local missing=false
  command -v curl >/dev/null 2>&1 || missing=true
  command -v awk >/dev/null 2>&1 || missing=true
  command -v sed >/dev/null 2>&1 || missing=true
  [[ "$missing" == "false" ]] && return

  info "正在安装基础工具..."
  if [[ "$OS_FAMILY" == "debian" ]]; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get install -y ca-certificates curl gawk sed
  else
    local package_manager="dnf"
    command -v dnf >/dev/null 2>&1 || package_manager="yum"
    "$package_manager" install -y ca-certificates curl gawk sed
  fi
}

download_url() {
  local url="$1" destination="$2" temporary
  temporary="$(mktemp "${destination}.tmp.XXXXXX")"
  if ! curl --fail --silent --show-error --location \
      --retry 3 --retry-delay 2 --connect-timeout 15 --max-time 180 \
      "$url" -o "$temporary"; then
    rm -f "$temporary"
    return 1
  fi
  chmod 0644 "$temporary"
  mv -f "$temporary" "$destination"
}

download_repository_file() {
  local path="$1" destination="$2"
  local raw_url="https://raw.githubusercontent.com/$REPOSITORY/$BRANCH/$path"
  local cdn_url="https://cdn.jsdelivr.net/gh/$REPOSITORY@$BRANCH/$path"

  if download_url "$raw_url" "$destination"; then
    return
  fi
  warn "GitHub 直连下载失败，正在尝试备用节点..."
  download_url "$cdn_url" "$destination" || fail "下载 $path 失败，请检查服务器网络后重试。"
}

install_docker() {
  if command -v docker >/dev/null 2>&1; then
    return
  fi

  info "未检测到 Docker，正在安装 Docker Engine 官方稳定版..."
  local installer
  installer="$(mktemp)"
  download_url "https://get.docker.com" "$installer" || fail "Docker 官方安装器下载失败。"
  sh "$installer"
  rm -f "$installer"
  command -v docker >/dev/null 2>&1 || fail "Docker 安装失败，请检查上方日志。"
}

start_docker() {
  if command -v systemctl >/dev/null 2>&1; then
    systemctl enable --now docker
  elif command -v service >/dev/null 2>&1; then
    service docker start
  fi

  local attempt
  for attempt in $(seq 1 30); do
    docker info >/dev/null 2>&1 && return
    sleep 2
  done
  fail "Docker 服务未能正常启动，请检查 systemctl status docker。"
}

install_compose_plugin() {
  docker compose version >/dev/null 2>&1 && return

  info "正在安装 Docker Compose v2..."
  if [[ "$OS_FAMILY" == "debian" ]]; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get install -y docker-compose-plugin
  else
    local package_manager="dnf"
    command -v dnf >/dev/null 2>&1 || package_manager="yum"
    "$package_manager" install -y docker-compose-plugin
  fi
  docker compose version >/dev/null 2>&1 || fail "Docker Compose v2 安装失败，请检查 Docker 软件源。"
}

install_command() {
  local source_path="${BASH_SOURCE[0]:-}" source_real target_real
  [[ -n "$source_path" && -f "$source_path" ]] || return

  source_real="$(readlink -f "$source_path")"
  target_real="$(readlink -f "$COMMAND_PATH" 2>/dev/null || true)"
  [[ -n "$target_real" && "$source_real" == "$target_real" ]] && return

  install -m 0755 "$source_path" "$COMMAND_PATH"
}

download_runtime_files() {
  mkdir -p "$INSTALL_DIR"
  info "正在同步部署配置..."
  download_repository_file ".env.example" "$INSTALL_DIR/.env.example"
  download_repository_file "docker-compose.yml" "$COMPOSE_FILE"
  download_repository_file "docker-compose.vnc.yml" "$VNC_COMPOSE_FILE"
  download_repository_file "global_config.yml" "$INSTALL_DIR/global_config.yml"
}

port_is_available() {
  local port="$1"
  if command -v ss >/dev/null 2>&1; then
    ! ss -ltnH 2>/dev/null | awk '{print $4}' | grep -Eq "(^|:)$port$"
  elif command -v netstat >/dev/null 2>&1; then
    ! netstat -ltn 2>/dev/null | awk 'NR > 2 {print $4}' | grep -Eq "(^|:)$port$"
  else
    ! timeout 1 bash -c "</dev/tcp/127.0.0.1/$port" >/dev/null 2>&1
  fi
}

replace_env_value() {
  local key="$1" value="$2" temporary
  temporary="$(mktemp "${ENV_FILE}.tmp.XXXXXX")"
  awk -v key="$key" -v value="$value" '
    BEGIN { found = 0 }
    index($0, key "=") == 1 { print key "=" value; found = 1; next }
    { print }
    END { if (!found) print key "=" value }
  ' "$ENV_FILE" > "$temporary"
  chmod 0600 "$temporary"
  mv -f "$temporary" "$ENV_FILE"
}

ensure_env() {
  if [[ -f "$ENV_FILE" ]]; then
    info "检测到已有配置，将保留授权、端口和自定义设置。"
    return
  fi

  cp "$INSTALL_DIR/.env.example" "$ENV_FILE"
  chmod 0600 "$ENV_FILE"
  local port selected_port=""
  for port in $(seq 9000 9099); do
    if port_is_available "$port"; then
      selected_port="$port"
      break
    fi
  done
  [[ -n "$selected_port" ]] || fail "9000-9099 端口均被占用，请先释放一个端口。"

  replace_env_value "APP_BIND_HOST" "0.0.0.0"
  replace_env_value "APP_PORT" "$selected_port"
  info "已生成配置，服务端口为 $selected_port。"
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
    ./*) VNC_PASSWORD_PATH="$INSTALL_DIR/${configured_path#./}" ;;
    *) VNC_PASSWORD_PATH="$INSTALL_DIR/$configured_path" ;;
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
  APP_PORT="$(read_env_value APP_PORT)"
  [[ "$APP_PORT" =~ ^[0-9]+$ ]] || fail ".env 中的 APP_PORT 配置无效。"
  (( APP_PORT >= 1 && APP_PORT <= 65535 )) || fail ".env 中的 APP_PORT 超出有效范围。"
  APP_URL="http://127.0.0.1:$APP_PORT"
}

configure_vnc_access() {
  NOVNC_PORT_VALUE="$(read_env_value NOVNC_PORT)"
  [[ "$NOVNC_PORT_VALUE" =~ ^[0-9]+$ ]] || fail ".env 中的 NOVNC_PORT 配置无效。"
  (( NOVNC_PORT_VALUE >= 1 && NOVNC_PORT_VALUE <= 65535 )) || fail ".env 中的 NOVNC_PORT 超出有效范围。"
  NOVNC_URL="http://127.0.0.1:$NOVNC_PORT_VALUE/vnc.html?autoconnect=1&resize=scale"
}

compose() {
  docker compose \
    --project-directory "$INSTALL_DIR" \
    --env-file "$ENV_FILE" \
    -f "$COMPOSE_FILE" \
    -f "$VNC_COMPOSE_FILE" \
    "$@"
}

wait_for_app() {
  local attempt
  for attempt in $(seq 1 90); do
    if curl --fail --silent --max-time 3 "$APP_URL/health" >/dev/null 2>&1; then
      return
    fi
    sleep 2
  done
  compose ps || true
  compose logs --tail 80 lazyfish-assistant || true
  fail "服务启动超时，请查看上方日志。"
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

detect_public_ip() {
  PUBLIC_IP="$(curl --fail --silent --max-time 8 https://api.ipify.org 2>/dev/null || true)"
  if [[ -z "$PUBLIC_IP" ]]; then
    PUBLIC_IP="$(curl --fail --silent --max-time 8 https://ifconfig.me/ip 2>/dev/null || true)"
  fi
}

show_access_info() {
  detect_public_ip
  if [[ -n "$PUBLIC_IP" ]]; then
    info "部署完成，访问地址：http://$PUBLIC_IP:$APP_PORT"
  else
    info "部署完成，请使用服务器公网 IP 和端口 $APP_PORT 访问。"
  fi
  warn "请仅对可信 IP 放行 TCP 端口 $APP_PORT，并同步检查云安全组与系统防火墙；生产使用建议配置 HTTPS 反向代理。"
  printf '\n常用命令：\n'
  printf '  sudo lazyfish-assistant          安装或更新\n'
  printf '  sudo lazyfish-assistant start    启动\n'
  printf '  sudo lazyfish-assistant stop     停止\n'
  printf '  sudo lazyfish-assistant status   查看状态\n'
  printf '  sudo lazyfish-assistant logs     查看日志\n'
}

show_vnc_access() {
  local password
  password="$(tr -d '\r\n' < "$VNC_PASSWORD_PATH")"
  printf '\n============================================================\n'
  printf '需要人工处理滑块时，请使用 noVNC 容器浏览器\n'
  printf 'noVNC 入口：%s\n' "$NOVNC_URL"
  printf 'noVNC 密码：%s\n' "$password"
  printf '先在您自己的电脑执行 SSH 隧道命令：\n'
  printf '  ssh -L %s:127.0.0.1:%s <SSH用户>@<服务器公网IP>\n' "$NOVNC_PORT_VALUE" "$NOVNC_PORT_VALUE"
  printf '保持 SSH 窗口打开，再访问上面的 noVNC 入口。\n'
  printf '底层 VNC 5900 不发布，noVNC 6080 只绑定服务器本机；请勿在安全组中对公网放行。\n'
  printf '============================================================\n'
}

deploy() {
  download_runtime_files
  ensure_env
  migrate_vnc_env_defaults
  ensure_vnc_password
  configure_app_url
  configure_vnc_access
  info "正在拉取最新稳定版本，首次下载可能需要几分钟..."
  compose pull lazyfish-assistant
  info "正在启动服务..."
  compose up -d --remove-orphans lazyfish-assistant
  wait_for_app
  compose ps
  show_initial_password
  show_access_info
  show_vnc_access
}

require_existing_install() {
  [[ -f "$ENV_FILE" && -f "$COMPOSE_FILE" && -f "$VNC_COMPOSE_FILE" ]] || fail "尚未安装或部署配置不完整，请先执行官网的一句话安装命令。"
  migrate_vnc_env_defaults
  ensure_vnc_password
  configure_app_url
  configure_vnc_access
}

main() {
  require_root
  detect_platform
  install_base_tools
  install_docker
  start_docker
  install_compose_plugin
  install_command

  case "$ACTION" in
    deploy|install|update) deploy ;;
    start)
      require_existing_install
      compose up -d lazyfish-assistant
      wait_for_app
      compose ps
      show_initial_password
      show_access_info
      show_vnc_access
      ;;
    stop)
      require_existing_install
      info "正在停止服务，客户数据不会被删除..."
      compose stop lazyfish-assistant
      compose ps
      ;;
    status)
      require_existing_install
      compose ps
      ;;
    logs)
      require_existing_install
      compose logs --tail 200 -f lazyfish-assistant
      ;;
    *) fail "未知操作：$ACTION。可用操作：update、start、stop、status、logs。" ;;
  esac
}

if [[ "${LAZYFISH_INSTALLER_LIBRARY_MODE:-0}" != "1" ]]; then
  main "$@"
fi
