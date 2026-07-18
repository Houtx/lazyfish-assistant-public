# 懒鱼助手

懒鱼助手是面向二手电商卖家的自托管运营管理工具，支持 Windows、macOS 和 Linux 云服务器。本仓库提供公开 Docker 镜像、一键部署工具、版本更新和对应源码获取说明。当前稳定版本为 `2.1.6`。

[产品官网](https://lazyfish.haoyunqiankun.com/) · [Linux 一句话安装](#linux-云服务器一句话安装) · [Windows 一键部署包](https://github.com/Houtx/lazyfish-assistant-public/releases/download/installer-latest/lazyfish-assistant-windows.zip) · [macOS 一键部署包](https://github.com/Houtx/lazyfish-assistant-public/releases/download/installer-latest/lazyfish-assistant-macos.zip) · [获取对应源码](SOURCE.md)

> 非闲鱼官方产品，与闲鱼及阿里巴巴集团无隶属、合作或授权关系。使用者应遵守适用法律和平台规则。

## 官网与仓库

- [懒鱼助手官网](https://lazyfish.haoyunqiankun.com/)提供产品功能、数据与授权说明、安装流程及官方下载入口；授权购买入口开放后也将以官网展示的信息为准。
- 本仓库用于发布一键部署文件、公开 Docker 镜像、版本更新说明和 AGPL 对应源码，不是闲鱼官方仓库或在线 SaaS 服务。
- 授权码应通过官网后续公布的购买入口或卖家正式上架渠道获取。不要向第三方提供授权码、Cookie、管理员密码或业务数据。

## 三平台一键部署（推荐）

| 使用环境 | 客户需要做什么 | 安装入口 |
| --- | --- | --- |
| Linux 云服务器 | SSH 登录后复制一行命令 | [查看 Linux 命令](#linux-云服务器一句话安装) |
| Windows 电脑 | 下载 ZIP、完整解压、双击安装 | [下载 Windows 部署包](https://github.com/Houtx/lazyfish-assistant-public/releases/download/installer-latest/lazyfish-assistant-windows.zip) |
| macOS 电脑 | 下载 ZIP、完整解压、右键打开安装 | [下载 macOS 部署包](https://github.com/Houtx/lazyfish-assistant-public/releases/download/installer-latest/lazyfish-assistant-macos.zip) |

### Linux 云服务器：一句话安装

以 `root` 用户登录服务器，或使用有 `sudo` 权限的用户，复制下面一整行执行，无需下载或解压安装包：

```bash
curl -fsSL https://lazyfish.haoyunqiankun.com/install.sh | sudo bash
```

脚本支持 Ubuntu、Debian、CentOS、RHEL、Rocky Linux 和 AlmaLinux，以及 `amd64`、`arm64` 架构。它会自动安装并启动 Docker Engine 与 Compose v2，把服务安装到 `/opt/lazyfish-assistant`，从 `9000-9099` 选择空闲端口，并显示公网访问地址。

安装器同时启用仅监听服务器本机的 noVNC 人工验证入口，并生成独立随机密码。需要处理滑块时，后台会显示入口和密码；先按安装器提示建立 SSH 隧道，再在自己电脑的浏览器打开 noVNC。不要在云安全组中开放 `5900` 或 `6080`。

以后再次执行同一句命令就是更新。已有 `.env`、授权设置、端口和 Docker 数据卷都会保留。脚本不会自动修改云厂商安全组，请按执行结果放行对应的 TCP 端口。

> **公网安全提醒：**仅向可信 IP 放行安装器显示的 TCP 端口，并同时检查云厂商安全组与服务器系统防火墙。准备长期对公网提供服务时，建议使用 Nginx 等反向代理配置 HTTPS，不要把管理端口无条件开放给所有来源。

安装后可以使用以下管理命令：

```bash
sudo lazyfish-assistant update
sudo lazyfish-assistant start
sudo lazyfish-assistant stop
sudo lazyfish-assistant status
sudo lazyfish-assistant logs
```

### Windows 与 macOS：部署包安装

Windows 和 macOS 客户不需要安装 Git，也不需要输入 Docker 命令。下载对应系统的部署包并完整解压：

- [Windows 一键部署包](https://github.com/Houtx/lazyfish-assistant-public/releases/download/installer-latest/lazyfish-assistant-windows.zip)
- [macOS 一键部署包](https://github.com/Houtx/lazyfish-assistant-public/releases/download/installer-latest/lazyfish-assistant-macos.zip)

Windows 双击 `安装或更新懒鱼助手.bat`；macOS 首次运行时右键点击 `安装或更新懒鱼助手.command` 并选择“打开”。脚本会自动生成配置和 noVNC 随机密码、拉取稳定版 `latest`、启动服务并打开浏览器。以后再次运行同一个脚本就是更新。安装窗口会显著显示 noVNC 入口和密码，端口只监听本机。

电脑必须先安装并启动 [Docker Desktop](https://www.docker.com/products/docker-desktop/)。Docker Desktop 的首次安装需要客户确认系统权限，无法由普通脚本完全静默代办；脚本检测到未安装时会自动打开官方下载页。

部署包同时提供“启动懒鱼助手”和“停止懒鱼助手”入口。停止操作不会删除客户数据。

## 命令行安装（技术人员）

要求 Docker Engine 24+ 和 Docker Compose v2。

```bash
git clone https://github.com/Houtx/lazyfish-assistant-public.git
cd lazyfish-assistant-public
cp .env.example .env
mkdir -p secrets && chmod 700 secrets
openssl rand -base64 18 > secrets/vnc_password.txt
chmod 600 secrets/vnc_password.txt
docker compose -f docker-compose.yml -f docker-compose.vnc.yml pull
docker compose -f docker-compose.yml -f docker-compose.vnc.yml up -d
docker compose -f docker-compose.yml -f docker-compose.vnc.yml ps
```

Windows 与 macOS 默认访问地址：<http://127.0.0.1:9000>。Linux 安装器默认监听公网地址，并在完成时显示实际访问地址。

首次启动后打开页面输入购买时收到的授权码。激活成功后，登录页会直接显示 `admin` 和随机生成的初始密码；首次登录必须设置新密码。忘记密码时，可在登录页使用当前安装绑定的有效授权码生成临时密码。

## 更新

默认使用稳定通道的 `latest` 标签。每次更新前先备份数据，再执行：

```bash
docker compose -f docker-compose.yml -f docker-compose.vnc.yml pull lazyfish-assistant
docker compose -f docker-compose.yml -f docker-compose.vnc.yml up -d --remove-orphans lazyfish-assistant
docker compose -f docker-compose.yml -f docker-compose.vnc.yml ps
curl -fsS http://127.0.0.1:9000/health
```

`latest` 只是指向当前稳定版本的可变标签，更新仍然需要执行 `docker compose pull`。查看当前运行的实际版本：

```bash
docker inspect lazyfish-assistant-lazyfish-assistant-1 \
  --format '{{ index .Config.Labels "org.opencontainers.image.version" }}'
```

遇到兼容问题时，在 `.env` 中把 `IMAGE_TAG` 改成先前的精确版本，例如：

```dotenv
IMAGE_TAG=2.1.3
```

然后使用基础 Compose 和 VNC overlay 重新执行 `pull` 与 `up -d`。不要执行 `docker compose down -v`，该命令会删除客户数据卷。

## noVNC 人工验证

自动处理滑块失败时，系统会保留当前容器浏览器会话，并在后台提示进入 noVNC。必须在这个容器浏览器中完成滑块，不能把处罚链接复制到普通浏览器，否则新 Cookie 不会回到正在运行的会话。

- Windows/macOS：直接打开安装窗口或后台显示的 `http://127.0.0.1:6080/vnc.html?autoconnect=1&resize=scale`，使用安装器显示的密码。
- Linux 云服务器：先在自己的电脑执行 `ssh -L 6080:127.0.0.1:6080 <SSH用户>@<服务器公网IP>`，保持终端连接，再打开上述本机地址。
- 密码保存在部署目录的 `secrets/vnc_password.txt`，安装器只在首次缺失时生成，升级不会改掉现有密码。
- 底层 VNC `5900` 不发布到宿主机，noVNC `6080` 仅绑定 `127.0.0.1`。不要改成 `0.0.0.0`，也不要在云安全组或路由器中公开这些端口。

## 镜像

- 稳定最新版：`ghcr.io/houtx/lazyfish-assistant-public:latest`
- 精确版本：`ghcr.io/houtx/lazyfish-assistant-public:<版本号>`
- 支持架构：`linux/amd64`、`linux/arm64`

稳定版本会同时发布精确版本标签和 `latest`。预发布版本只发布精确版本标签，不会移动 `latest`。

## 源码与许可

软件整体按照 [AGPL-3.0-only](LICENSE) 提供。发行镜像内包含该版本的 Python 源码、Dockerfile、依赖锁定文件和构建/安装脚本。获取方法见 [SOURCE.md](SOURCE.md)。品牌名称和 Logo 不因开源代码许可而获得授权。

## 数据安全

数据库、浏览器状态、上传文件和日志保存在 Docker 命名卷中。它们可能包含 Cookie、账号凭据、买家信息和业务数据，应限制主机访问并定期加密备份。
