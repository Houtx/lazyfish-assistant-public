# 获取对应源码

懒鱼助手整体按照 GNU Affero General Public License v3.0（`AGPL-3.0-only`）提供。每个公开 Docker 镜像都在 `/app` 中包含与该镜像版本对应的源代码和构建材料，包括 Python 源文件、Dockerfile、依赖锁定文件、配置、前端资源及发布脚本。

## 从精确版本镜像提取

将 `VERSION` 替换为正在使用的精确版本：

```bash
VERSION=2.1.0
docker pull "ghcr.io/houtx/lazyfish-assistant-public:${VERSION}"
docker create --name lazyfish-source "ghcr.io/houtx/lazyfish-assistant-public:${VERSION}"
docker cp lazyfish-source:/app "./lazyfish-assistant-${VERSION}-source"
docker rm lazyfish-source
```

提取后的目录是该镜像内用于运行和修改的源代码。镜像标签对应的实际版本可通过以下命令确认：

```bash
docker image inspect ghcr.io/houtx/lazyfish-assistant-public:latest \
  --format '{{ index .Config.Labels "org.opencontainers.image.version" }}'
```

为了复现构建，应使用精确版本标签或镜像 digest，不要把随时间移动的 `latest` 当作历史版本标识。

## 许可边界

接收者可以依照 AGPL 运行、研究、复制、修改和再分发代码。重新分发时必须保留许可证、版权与修改声明，并继续提供对应源码。AGPL 不授予“懒鱼助手”名称、Logo 或第三方商标的品牌使用权。

若镜像无法拉取或源码提取失败，请通过购买订单中的支持渠道索取对应版本；不能用其他版本替代实际运行版本的对应源码。
