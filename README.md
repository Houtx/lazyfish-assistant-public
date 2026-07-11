# 懒鱼助手

懒鱼助手是面向二手电商卖家的自托管运营管理工具。本仓库提供公开 Docker 镜像的安装、更新和对应源码获取说明。

> 非闲鱼官方产品，与闲鱼及阿里巴巴集团无隶属、合作或授权关系。使用者应遵守适用法律和平台规则。

## 快速安装

要求 Docker Engine 24+ 和 Docker Compose v2。

```bash
git clone https://github.com/Houtx/lazyfish-assistant-public.git
cd lazyfish-assistant-public
cp .env.example .env
docker compose pull
docker compose up -d
docker compose ps
```

默认访问地址：<http://127.0.0.1:9000>。

首次启动后打开页面输入购买时收到的授权码。未设置管理员密码时，可以读取系统生成的一次性密码：

```bash
docker compose exec lazyfish-assistant cat /app/data/.initial_admin_password
```

登录后立即修改密码并删除提示文件：

```bash
docker compose exec lazyfish-assistant rm -f /app/data/.initial_admin_password
```

## 更新

默认使用稳定通道的 `latest` 标签。每次更新前先备份数据，再执行：

```bash
docker compose pull lazyfish-assistant
docker compose up -d --remove-orphans lazyfish-assistant
docker compose ps
curl -fsS http://127.0.0.1:9000/health
```

`latest` 只是指向当前稳定版本的可变标签，更新仍然需要执行 `docker compose pull`。查看当前运行的实际版本：

```bash
docker inspect lazyfish-assistant-lazyfish-assistant-1 \
  --format '{{ index .Config.Labels "org.opencontainers.image.version" }}'
```

遇到兼容问题时，在 `.env` 中把 `IMAGE_TAG` 改成先前的精确版本，例如：

```dotenv
IMAGE_TAG=2.1.0-commercial.1
```

然后重新执行 `docker compose pull` 和 `docker compose up -d`。不要执行 `docker compose down -v`，该命令会删除客户数据卷。

## 镜像

- 稳定最新版：`ghcr.io/houtx/lazyfish-assistant-public:latest`
- 精确版本：`ghcr.io/houtx/lazyfish-assistant-public:<版本号>`
- 支持架构：`linux/amd64`、`linux/arm64`

稳定版本会同时发布精确版本标签和 `latest`。预发布版本只发布精确版本标签，不会移动 `latest`。

## 源码与许可

软件整体按照 [AGPL-3.0-only](LICENSE) 提供。发行镜像内包含该版本的 Python 源码、Dockerfile、依赖锁定文件和构建/安装脚本。获取方法见 [SOURCE.md](SOURCE.md)。品牌名称和 Logo 不因开源代码许可而获得授权。

## 数据安全

数据库、浏览器状态、上传文件和日志保存在 Docker 命名卷中。它们可能包含 Cookie、账号凭据、买家信息和业务数据，应限制主机访问并定期加密备份。
