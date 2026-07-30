# 🛡️ Gluetun PIA Watchdog

<p align="center">
  <img src="https://img.shields.io/github/license/yuanweize/gluetun-pia-watchdog?style=for-the-badge&color=blue" alt="License">
  <img src="https://img.shields.io/badge/Docker-GHCR-blue?style=for-the-badge&logo=docker" alt="Docker">
  <img src="https://img.shields.io/badge/Architecture-amd64%20%7C%20arm64-brightgreen?style=for-the-badge" alt="Architecture">
  <img src="https://img.shields.io/badge/Release-v1.0.3-orange?style=for-the-badge" alt="Version">
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
3. **无缝更新**：原子化更新 `.env` & `wg0.conf` 文件并自动调用 Docker API 重启 Gluetun
4. **自愈断线看门狗**：定时检测 VPN 连通性，断线自动触发全套重连续期流程
5. **端口全自动注入**：监控 `/tmp/gluetun/forwarded_port` 并自动写入 qBittorrent

---

## ✨ 核心功能

| 功能 | 说明 |
|:---|:---|
| 🔑 **全自动密钥注册** | 自动调用 PIA REST API 完成 `addKey` 注册，无需任何人工干预 |
| 🌍 **智能低延迟选路** | 自动 Ping 测速，从全球 100+ 服务器中选择最快节点，或锁定指定地区 |
| 🔍 **服务器浏览器** | 内置 CLI 交互式工具，支持按端口转发（PF）、地区关键字、延迟过滤 |
| 📝 **安全更新 `.env` 与 `wg0.conf`** | 精确更新 WireGuard 配置，完美兼容 Docker bind-mount 文件挂载 |
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
      - ./data/gluetun/temp/wg0.conf:/gluetun/wireguard/wg0.conf:ro
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

---

## ❤️ 致谢与特别鸣谢

衷心感谢以下优秀的开源项目与团队，正是有了你们的奠基，本项目才得以诞生：

- **[qdm12/gluetun](https://github.com/qdm12/gluetun)** — Docker 生态中最强大的 VPN 客户端容器。
- **[snoringdragon/gluetun-qbittorrent-port-manager](https://github.com/snoringdragon/gluetun-qbittorrent-port-manager)** — 自动向 qBittorrent 注入端口的最初灵感来源。
- **[pia-foss/manual-connections](https://github.com/pia-foss/manual-connections)** — PIA 官方开源的 WireGuard 手动连接脚本。
- **[LinuxServer.io](https://linuxserver.io)** — 为 Home Lab 社区提供高品质 Docker 镜像的团队。
- **Google DeepMind / Antigravity AI 团队** — 强大的 Agentic AI 结对编程与自动化构建支撑。

---

## 📄 开源协议

[MIT License](LICENSE) — 欢迎自由使用、修改及二次分发。
