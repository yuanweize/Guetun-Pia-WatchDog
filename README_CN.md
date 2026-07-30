# 🛡️ Gluetun PIA Watchdog

<p align="center">
  <img src="https://img.shields.io/github/license/yuanweize/gluetun-pia-watchdog?style=for-the-badge&color=blue" alt="License">
  <img src="https://img.shields.io/badge/Docker-GHCR-blue?style=for-the-badge&logo=docker" alt="Docker">
  <img src="https://img.shields.io/badge/Architecture-amd64%20%7C%20arm64-brightgreen?style=for-the-badge" alt="Architecture">
  <img src="https://img.shields.io/badge/Release-v1.0.2-orange?style=for-the-badge" alt="Version">
</p>

<p align="center">
  <strong>专为 Gluetun + Private Internet Access (PIA) 设计的全自动 WireGuard 密钥续期、网络健康看门狗 & qBittorrent 动态端口注入管家。</strong>
</p>

<p align="center">
  <a href="#-痛点与背景">痛点与背景</a> •
  <a href="#-核心功能">核心功能</a> •
  <a href="#-快速开始">快速开始</a> •
  <a href="#-服务器交互式浏览器">服务器浏览器</a> •
  <a href="#-环境变量配置">环境变量配置</a> •
  <a href="#-工作原理架构">工作原理</a> •
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
| 📝 **安全更新 `.env`** | 仅精确更新 WireGuard 6 个动态变量，完美保留你的账户密码和其他配置 |
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

### 3. 一键启动

```bash
docker compose up -d
docker logs -f gluetun-pia-watchdog  # 查看全自动流转日志
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

示例输出：

```
  #     LATENCY     REGION ID                       NAME                                    PF   WIREGUARD IP
  ────  ──────────  ──────────────────────────────  ──────────────────────────────────────  ───  ─────────────────
  1     0.003799s   de_germany-so                   DE Germany Streaming Optimized           ✅   147.90.227.155
  2     0.003858s   de-frankfurt                    DE Frankfurt                             ✅   147.90.209.204
  3     0.007621s   czech                           Czech Republic                           ✅   212.102.39.92
  4     0.010727s   nl_amsterdam                    Netherlands                              ✅   158.173.21.86
```

---

## ⚙️ 环境变量配置

所有的关键配置只需要在 `.env` 中维护一份：

### 用户核心配置 (`.env`)

| 变量名 | 默认值 | 说明 |
|:---|:---|:---|
| `PIA_USER` | *(必填)* | PIA 账号 (例如 `p1234567`) |
| `PIA_PASS` | *(必填)* | PIA 密码 |
| `PREFERRED_REGION` | `none` | 目标地区 ID。`none` 表示自动选最快节点。可通过 `list-servers --ids` 查询 |
| `MAX_LATENCY` | `0.1` | 自动选择节点时的最大可容忍延迟（秒） |
| `PIA_PF` | `true` | 是否仅筛选支持端口转发的节点 |

### Watchdog 高级调优（可选）

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

## ❓ 常见问题与故障排查

<details>
<summary><strong>为什么不直接用 Gluetun 内置的 PIA 支持？</strong></summary>

Gluetun 内置的 PIA 实现经常因 PIA 官方节点轮换或 API 变更而失效报 `i/o timeout`。使用 `custom` WireGuard 模式配合本地注册的密钥是最稳定的方式，而 Watchdog 正是把这个繁琐的注册过程彻底自动化。
</details>

<details>
<summary><strong>挂载 Docker Socket (`docker.sock`) 安全吗？</strong></summary>

容器挂载 Socket 时使用了 **只读权限** (`:ro`)。Watchdog 仅使用 API 执行：
1. 容器内连通性测试 (`exec`)
2. 重启 Gluetun 容器 (`restart`)

无法进行拉取镜像、删除容器或破坏宿主机的敏感操作。
</details>

<details>
<summary><strong>密钥更新重连时会有多久中断？</strong></summary>

整个过程通常在 **15-30 秒** 内完成（包含下载节点列表、生成密钥、API 注册、重启 Gluetun 和恢复端口绑定）。qBittorrent 会在端口恢复后自动恢复做种和下载。
</details>

---

## 📄 开源协议

[MIT License](LICENSE) — 欢迎自由使用、修改及二次分发。
