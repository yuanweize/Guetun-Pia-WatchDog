# 🛡️ Gluetun PIA Watchdog

<p align="center">
  <img src="https://img.shields.io/github/license/yuanweize/gluetun-pia-watchdog?style=for-the-badge&color=blue" alt="License">
  <img src="https://img.shields.io/badge/Docker-GHCR-blue?style=for-the-badge&logo=docker" alt="Docker">
  <img src="https://img.shields.io/badge/Architecture-amd64%20%7C%20arm64-brightgreen?style=for-the-badge" alt="Architecture">
  <img src="https://img.shields.io/badge/Release-v1.0.5-orange?style=for-the-badge" alt="Version">
</p>

<p align="center">
  <strong>专为 Gluetun + Private Internet Access (PIA) 设计的全自动 WireGuard 密钥续期、网络健康看门狗 & qBittorrent 动态端口注入管家。</strong>
</p>

<p align="center">
  <a href="#-痛点与背景">痛点与背景</a> •
  <a href="#-核心功能">核心功能</a> •
  <a href="#-快速开始">快速开始</a> •
  <a href="#-命令行用法全指南">命令行指南</a> •
  <a href="#-运行日志示例">日志示例</a> •
  <a href="#-服务器交互式浏览器">服务器浏览器</a> •
  <a href="#-环境变量配置详解">环境变量</a> •
  <a href="#-工作原理架构">工作原理</a> •
  <a href="#-致谢与特别鸣谢">致谢与鸣谢</a> •
  <a href="#-常见问题与故障排查">常见问题</a>
</p>

---

## 痛点与背景

在使用 [Gluetun](https://github.com/qdm12/gluetun) 配合 PIA VPN 时，由于 PIA 定期轮换服务器 IP、域名和 WireGuard 密钥，原生 Gluetun 经常出现：

- ❌ `i/o timeout` 循环报错，VPN 连接彻底中断
- ❌ 需要手动运行 [manual-connections](https://github.com/pia-foss/manual-connections) 脚本重新注册
- ❌ 手动复制 6 个 WireGuard 变量（`SERVER_NAMES` / `ENDPOINT_IP` 等）粘贴到 `docker-compose.yml` 或 `.env`
- ❌ 手动重启容器，隔几天/几周就要重复一遍痛苦操作

**Gluetun PIA Watchdog 彻底解决这一痛点！** 作为一个轻量级 Alpine 容器（仅 ~15MB）：

1. **自动注册**：通过 PIA 官方 REST API 自动生成并注册 WireGuard 密钥对
2. **智能选路**：自动测速并选择延迟最低且支持端口转发（PF）的 PIA 服务器
3. **无缝更新**：原子化更新 `.env` 文件并自动调用 Docker API 重启 Gluetun
4. **自愈断线看门狗**：定时检测 VPN 连通性，断线自动触发全套重连续期流程
5. **端口全自动注入**：监控 `/tmp/gluetun/forwarded_port` 并自动写入 qBittorrent

---

## ✨ 核心功能

| 功能 | 说明 |
|:---|:---|
| 🔑 **全自动密钥注册** | 自动调用 PIA REST API 完成 `addKey` 注册，无需任何人工干预 |
| 🌍 **智能低延迟选路** | 自动 Ping 测速，从全球 100+ 服务器中选择最快节点，或锁定指定地区 |
| 🔍 **服务器浏览器** | 内置 CLI 交互式工具，支持按端口转发（PF）、地区关键字、延迟过滤 |
| 📝 **安全更新 `.env`** | 精确更新 WireGuard 配置，完美兼容 Docker bind-mount 文件挂载 |
| 🔄 **Docker Socket 联动** | 连接宿主机 Docker Socket (`:ro`)，续期完成后自动重启 Gluetun |
| 🏥 **连通性看门狗** | 每 2 分钟执行一次健康检查，连续 3 次失败自动触发自愈续期 |
| ⏰ **预防性定期续期** | 即使网络正常，每 7 天也会自动预防性刷一次密钥，防止静默过期 |
| 🔌 **qBittorrent 端口注入** | 使用 `inotifywait` 毫秒级监听端口文件变化并 API 注入 qBittorrent |
| 🪶 **极致轻量** | ~15 MB Alpine 镜像，无 Python / Node.js 冗余依赖 |
| 🏗️ **多架构支持** | 同时支持 `linux/amd64` 和 `linux/arm64` (如树莓派/ARM 云服务器) |

---

## 🚀 快速开始

### 1. 创建 `.env` 配置文件

```bash
# 复制示例文件
cp .env.example .env
```

编辑 `.env` 填入你的 PIA 账号密码：

```env
# ── PIA 账号设置（必填）──
PIA_USER=p1234567
PIA_PASS=your_pia_password

# ── 服务器偏好 ──
PREFERRED_REGION=none    # "none" 表示自动选择延迟最低节点
MAX_LATENCY=0.1          # 允许的最大延迟（秒）
PIA_PF=true              # 过滤必须支持端口转发

# ── 动态 WireGuard 配置（Watchdog 自动更新，请勿手动编辑）──
SERVER_NAMES=
WIREGUARD_ENDPOINT_IP=
WIREGUARD_ENDPOINT_PORT=
WIREGUARD_PUBLIC_KEY=
WIREGUARD_PRIVATE_KEY=
WIREGUARD_ADDRESSES=
```

### 2. 编排 `docker-compose.yml`

```yaml
services:
  gluetun:
    image: qmcgaw/gluetun:latest
    container_name: gluetun
    cap_add:
      - NET_ADMIN
    devices:
      - /dev/net/tun:/dev/net/tun
    environment:
      - VPN_SERVICE_PROVIDER=custom
      - VPN_TYPE=wireguard
      # ⬇️ 以下 6 个变量由 gluetun-pia-watchdog 自动填入 .env
      - SERVER_NAMES=${SERVER_NAMES}
      - WIREGUARD_ENDPOINT_IP=${WIREGUARD_ENDPOINT_IP}
      - WIREGUARD_ENDPOINT_PORT=${WIREGUARD_ENDPOINT_PORT}
      - WIREGUARD_PUBLIC_KEY=${WIREGUARD_PUBLIC_KEY}
      - WIREGUARD_PRIVATE_KEY=${WIREGUARD_PRIVATE_KEY}
      - WIREGUARD_ADDRESSES=${WIREGUARD_ADDRESSES}
      # PIA 端口转发
      - VPN_PORT_FORWARDING=on
      - VPN_PORT_FORWARDING_PROVIDER=private internet access
      - VPN_PORT_FORWARDING_USERNAME=${PIA_USER}
      - VPN_PORT_FORWARDING_PASSWORD=${PIA_PASS}
    volumes:
      - ./data/gluetun/temp:/tmp/gluetun
    ports:
      - "8090:8080"   # qBittorrent WebUI
    restart: unless-stopped

  gluetun-pia-watchdog:
    image: ghcr.io/yuanweize/gluetun-pia-watchdog:latest
    container_name: gluetun-pia-watchdog
    restart: unless-stopped
    environment:
      - PIA_USER=${PIA_USER}
      - PIA_PASS=${PIA_PASS}
      - PREFERRED_REGION=${PREFERRED_REGION}
      - MAX_LATENCY=${MAX_LATENCY}
      - PIA_PF=${PIA_PF}
      - GLUETUN_CONTAINER=gluetun
      - QBITTORRENT_SERVER=gluetun
      - QBITTORRENT_PORT=8080
      - QBITTORRENT_USER=admin
      - QBITTORRENT_PASS=adminadmin
    volumes:
      - ./data/gluetun/temp:/tmp/gluetun
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./.env:/config/.env
    depends_on:
      - gluetun
      - qbittorrent

  qbittorrent:
    image: lscr.io/linuxserver/qbittorrent:latest
    container_name: qbittorrent
    network_mode: "service:gluetun"
    environment:
      - PUID=1000
      - PGID=1000
      - WEBUI_PORT=8080
    volumes:
      - ./qbittorrent:/config
      - /data/downloads:/data/downloads
    restart: unless-stopped
    depends_on:
      - gluetun
```

---

## 🛠️ 命令行用法全指南

Watchdog 镜像内置了丰富的子命令，支持后台守护、节点测速浏览、手动单次续期等操作：

### 1. 启动守护进程 (默认模式)
```bash
docker compose up -d gluetun-pia-watchdog
```

### 2. 浏览 PIA 服务器 (`list-servers`)
```bash
# 查所有支持端口转发的服务器（按延迟升序排列）
docker compose run --rm gluetun-pia-watchdog list-servers --pf

# 按地区筛选 (例如德国 / 荷兰 / 瑞士)
docker compose run --rm gluetun-pia-watchdog list-servers --pf --region germany

# 限制最大延迟低于 50ms (0.05秒)
docker compose run --rm gluetun-pia-watchdog list-servers --pf --latency 0.05

# 仅输出 Region ID（便于复制填入 .env 的 PREFERRED_REGION 变量）
docker compose run --rm gluetun-pia-watchdog list-servers --pf --ids

# 输出原始 JSON 格式
docker compose run --rm gluetun-pia-watchdog list-servers --pf --json
```

### 3. 手动强行触发单次密钥续期 (`renew`)
当你怀疑 PIA 节点过期或者想要手动切换节点时，可以立刻运行：
```bash
docker compose exec gluetun-pia-watchdog /app/entrypoint.sh renew
```

### 4. 查看交互式帮助菜单 (`help`)
```bash
docker run --rm ghcr.io/yuanweize/gluetun-pia-watchdog help
```

---

## 📜 运行日志示例

以下是 `gluetun-pia-watchdog` 启动、自动向 PIA 注册 WireGuard 密钥、重启 Gluetun 并将端口注入 qBittorrent 的真实控制台日志：

```text
   ______   __                  __                ____  _____  ___       _       ______     __       __                    __
  / ____/  / /  __  __  ___    / /_  __  ______  / __ \/  _/  /   |     | |     / / __ \   / /______/ /_  ____  ____  ____/ /
 / / __   / /  / / / / / _ \  / __/ / / / / __ \/ /_/ // /   / /| |     | | /| / / /_/ /  / __/ ___/ __ \/ __ \/ __ \/ __  / 
/ /_/ /  / /__/ /_/ / /  __/ / /_  / /_/ / / / / ____// /   / ___ |     | |/ |/ / ____/  / /_/ /__/ / / / /_/ / /_/ / /_/ /  
\____/  /____/\__,_/  \___/  \__/  \__,_/_/ /_/_/   /___/  /_/  |_|     |__/|__/_/       \__/\___/_/ /_/\____/\____/\__,_/   
                                                                                                                   v1.0.5
[2026-07-30 18:36:12] [INFO]  ════════════════════════════════════════════════════════════════════════════
[2026-07-30 18:36:12] [INFO]    GLUETUN_CONTAINER    = gluetun
[2026-07-30 18:36:12] [INFO]    HEALTH_CHECK_INTERVAL= 120s
[2026-07-30 18:36:12] [INFO]    HEALTH_CHECK_FAILURES= 3
[2026-07-30 18:36:12] [INFO]    RENEW_INTERVAL       = 604800s
[2026-07-30 18:36:12] [INFO]    QBITTORRENT_SERVER   = gluetun
[2026-07-30 18:36:12] [INFO]    PREFERRED_REGION     = swiss
[2026-07-30 18:36:12] [INFO]  ════════════════════════════════════════════════════════════════════════════
[2026-07-30 18:36:12] [INFO]  Starting port file watcher on /tmp/gluetun/forwarded_port …
[2026-07-30 18:36:12] [INFO]  Port watcher started (PID 19).
[2026-07-30 18:36:23] [INFO]  Injecting port 35563 into qBittorrent at gluetun:8080 …
[2026-07-30 18:36:23] [INFO]  ✅ qBittorrent listening port set to 35563
```

---

## 🔍 服务器交互式浏览器

不确定用哪个 PIA 节点？使用内置服务器浏览器查找最快节点：

```bash
# 查看所有支持端口转发的节点（按延迟升序排列）
docker compose run --rm gluetun-pia-watchdog list-servers --pf

# 搜索特定地区（如德国 / 荷兰）
docker compose run --rm gluetun-pia-watchdog list-servers --pf --region germany

# 限制延迟低于 50ms (0.05秒)
docker compose run --rm gluetun-pia-watchdog list-servers --pf --latency 0.05

# 仅输出 Region ID（便于复制到 .env 的 PREFERRED_REGION 变量）
docker compose run --rm gluetun-pia-watchdog list-servers --pf --ids
```

---

## ⚙️ 环境变量配置详解

所有的关键配置只需要在 `.env` 中维护一份：

### 用户核心配置 (`.env`)

| 变量名 | 默认值 | 说明 |
|:---|:---|:---|
| `PIA_USER` | *(必填)* | PIA 账号 (例如 `p1234567`) |
| `PIA_PASS` | *(必填)* | PIA 密码 |
| `PREFERRED_REGION` | `none` | 目标地区 ID。`none` 表示自动选择最快节点。可通过 `list-servers --ids` 查询 |
| `MAX_LATENCY` | `0.1` | 自动选择节点时的最大可容忍延迟（秒） |
| `PIA_PF` | `true` | 是否仅筛选支持端口转发的节点 |

### Watchdog 高级调优 (环境参数)

| 变量名 | 默认值 | 说明 |
|:---|:---|:---|
| `GLUETUN_CONTAINER` | `gluetun` | 需要监控和重启的 Gluetun 容器名称 |
| `GLUETUN_ENV_FILE` | `/config/.env` | 容器内挂载的 `.env` 路径 |
| `QBITTORRENT_SERVER` | `gluetun` | qBittorrent 访问地址 |
| `QBITTORRENT_PORT` | `8080` | qBittorrent WebUI 端口 |
| `QBITTORRENT_USER` | `admin` | qBittorrent 用户名 |
| `QBITTORRENT_PASS` | `adminadmin` | qBittorrent 密码 |
| `HEALTH_CHECK_INTERVAL` | `120` | 健康检查间隔（秒） |
| `HEALTH_CHECK_FAILURES` | `3` | 连续失败多少次触发自动重连续期 |
| `RENEW_INTERVAL` | `604800` | 预防性定期续期周期（秒，默认 7 天） |

---

## 🏗️ 工作原理架构

```
┌──────────────────────────────────────────────────────────────────────┐
│                             Docker 宿主机                            │
│                                                                      │
│  ┌──────────────────────────────┐    ┌────────────────────────────┐  │
│  │  gluetun-pia-watchdog        │    │        gluetun             │  │
│  │                              │    │                            │  │
│  │  ┌────────────────────────┐  │    │  ┌──────────────────────┐  │  │
│  │  │  健康检查轮询 (120s)     │──┼────┼─▶│  VPN 连接 (WireGuard)│  │  │
│  │  └───────────┬────────────┘  │    │  └──────────────────────┘  │  │
│  │              │ 失败 ×3       │    │                            │  │
│  │  ┌───────────▼────────────┐  │    │  ┌──────────────────────┐  │  │
│  │  │  PIA REST API 客户端   │  │    │  │  PIA 端口转发 API    │  │  │
│  │  │  → 身份认证获取 Token   │  │    │  │  → forwarded_port ──┼──┼──┐
│  │  │  → 全球节点 Ping 测速   │  │    │  └──────────────────────┘  │  ││
│  │  │  → 生成 & 注册 WG Key   │  │    │                            │  ││
│  │  └───────────┬────────────┘  │    └────────────────────────────┘  ││
│  │              │               │                                    ││
│  │  ┌───────────▼────────────┐  │    ┌────────────────────────────┐  ││
│  │  │  更新 .env 文件        │  │    │      qBittorrent           │  ││
│  │  │  Docker API 重启 Gluetun ┼──┼───▶│                            │  ││
│  │  └────────────────────────┘  │    │  ┌──────────────────────┐  │  ││
│  │                              │    │  │  监听端口 ◀──────────┼──┼──┘│
│  │  ┌────────────────────────┐  │    │  └──────────────────────┘  │   │
│  │  │  端口监听器             │  │    │                            │   │
│  │  │  (inotifywait 实时同步) ┼──┼───▶│  API 设置监听端口          │   │
│  │  └────────────────────────┘  │    └────────────────────────────┘   │
│  └──────────────────────────────┘                                     │
│                                                                       │
│  .env ◀── 自动更新 ── Read by Docker Compose                          │
└───────────────────────────────────────────────────────────────────────┘
```

---

## ❤️ 致谢与特别鸣谢

衷心感谢以下优秀的开源项目与团队，正是有了你们的奠基，本项目才得以诞生：

- **[qdm12/gluetun](https://github.com/qdm12/gluetun)** — Docker 生态中最强大的 VPN 客户端容器。
- **[snoringdragon/gluetun-qbittorrent-port-manager](https://github.com/snoringdragon/gluetun-qbittorrent-port-manager)** — 自动向 qBittorrent 注入端口的最初灵感来源。
- **[pia-foss/manual-connections](https://github.com/pia-foss/manual-connections)** — PIA 官方开源的 WireGuard 手动连接脚本。
- **[LinuxServer.io](https://linuxserver.io)** — 为 Home Lab 社区提供高品质 Docker 镜像的团队。

---

## 📄 开源协议

[MIT License](LICENSE) — 欢迎自由使用、修改及二次分发。
