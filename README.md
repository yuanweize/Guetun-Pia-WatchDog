# 🛡️ Gluetun PIA Watchdog

<p align="center">
  <img src="https://img.shields.io/github/license/yuanweize/gluetun-pia-watchdog?style=for-the-badge&color=blue" alt="License">
  <img src="https://img.shields.io/badge/Docker-GHCR-blue?style=for-the-badge&logo=docker" alt="Docker">
  <img src="https://img.shields.io/badge/Architecture-amd64%20%7C%20arm64-brightgreen?style=for-the-badge" alt="Architecture">
  <img src="https://img.shields.io/badge/Release-v1.0.2-orange?style=for-the-badge" alt="Version">
  <a href="README_CN.md"><img src="https://img.shields.io/badge/文档-简体中文-red?style=for-the-badge" alt="中文文档"></a>
</p>

<p align="center">
  <strong>Automatic PIA WireGuard key registration, health monitoring, self-healing reconnection & qBittorrent port injection — all in one container.</strong>
</p>

<p align="center">
  <a href="#the-problem">The Problem</a> •
  <a href="#key-features">Features</a> •
  <a href="#quick-start">Quick Start</a> •
  <a href="#server-browser">Server Browser</a> •
  <a href="#configuration">Configuration</a> •
  <a href="#architecture">Architecture</a> •
  <a href="#faq">FAQ</a>
</p>

---

## The Problem

[Gluetun](https://github.com/qdm12/gluetun) is the gold standard for routing Docker containers through a VPN. But when used with **Private Internet Access (PIA)** in `custom` WireGuard mode, server IP and key rotations cause:

- ❌ `i/o timeout` error loops in Gluetun logs
- ❌ Manual script runs via [manual-connections](https://github.com/pia-foss/manual-connections)
- ❌ Copy-pasting WireGuard credentials into `docker-compose.yml` or `.env`
- ❌ Constant manual intervention every few days/weeks

## The Solution

**Gluetun PIA Watchdog** is a single Alpine container (~15 MB) that automates the entire lifecycle:

```
Watchdog detects failure → Authenticates with PIA API → Measures server latency
→ Registers fresh WireGuard keys → Updates .env → Restarts Gluetun
→ Injects port into qBittorrent → 🎉 Fully Automated & Hands-Free
```

---

## ✨ Key Features

| Feature | Description |
|:---|:---|
| 🔑 **Auto Key Registration** | Calls PIA's REST API `addKey` to register WireGuard keys automatically |
| 🌍 **Smart Server Selection** | Ping-tests 100+ servers to find the fastest port-forwarding node |
| 🔍 **Interactive Server Browser** | Built-in CLI tool to search & filter servers by region, latency, or port-forwarding |
| 📝 **Atomic `.env` Updates** | Surgically updates only WireGuard variables without wiping user credentials |
| 🔄 **Docker Socket Automation** | Triggers container restart via Docker socket (`:ro`) upon renewal |
| 🏥 **Self-Healing Watchdog** | Checks VPN health every 2 minutes; auto-renews after 3 consecutive failures |
| ⏰ **Proactive Weekly Renewal** | Forces key refresh every 7 days to prevent silent key expiry |
| 🔌 **qBittorrent Port Injection** | Uses `inotifywait` to catch port changes instantly and push to qBittorrent API |
| 🪶 **Ultra-Lightweight** | ~15 MB Alpine image — zero heavy dependencies |
| 🏗️ **Multi-Arch Support** | Pre-built for `linux/amd64` and `linux/arm64` |

---

## 🚀 Quick Start

### 1. Create `.env`

```bash
cp .env.example .env
```

Edit `.env` with your PIA credentials:

```env
# ── PIA Credentials (Required) ──
PIA_USER=p1234567
PIA_PASS=your_pia_password

# ── Server Preferences ──
PREFERRED_REGION=none    # "none" = auto-select lowest latency
MAX_LATENCY=0.1          # seconds
PIA_PF=true              # only port-forwarding servers

# ── Dynamic WireGuard Config (auto-populated by Watchdog) ──
SERVER_NAMES=
WIREGUARD_ENDPOINT_IP=
WIREGUARD_ENDPOINT_PORT=
WIREGUARD_PUBLIC_KEY=
WIREGUARD_PRIVATE_KEY=
WIREGUARD_ADDRESSES=
```

### 2. Configure `docker-compose.yml`

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
      # ⬇️ Auto-populated from .env by gluetun-pia-watchdog
      - SERVER_NAMES=${SERVER_NAMES}
      - WIREGUARD_ENDPOINT_IP=${WIREGUARD_ENDPOINT_IP}
      - WIREGUARD_ENDPOINT_PORT=${WIREGUARD_ENDPOINT_PORT}
      - WIREGUARD_PUBLIC_KEY=${WIREGUARD_PUBLIC_KEY}
      - WIREGUARD_PRIVATE_KEY=${WIREGUARD_PRIVATE_KEY}
      - WIREGUARD_ADDRESSES=${WIREGUARD_ADDRESSES}
      # PIA Port Forwarding
      - VPN_PORT_FORWARDING=on
      - VPN_PORT_FORWARDING_PROVIDER=private internet access
      - VPN_PORT_FORWARDING_USERNAME=${PIA_USER}
      - VPN_PORT_FORWARDING_PASSWORD=${PIA_PASS}
    volumes:
      - ./data/gluetun/temp:/tmp/gluetun
    ports:
      - "8090:8080"
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

### 3. Launch

```bash
docker compose up -d
docker logs -f gluetun-pia-watchdog
```

---

## 🔍 Server Browser

Find the fastest server for your location with the interactive server browser:

```bash
# List all port-forwarding servers sorted by latency
docker compose run --rm gluetun-pia-watchdog list-servers --pf

# Filter by region (e.g. Germany, Netherlands, US)
docker compose run --rm gluetun-pia-watchdog list-servers --pf --region germany

# Latency threshold < 50ms (0.05s)
docker compose run --rm gluetun-pia-watchdog list-servers --pf --latency 0.05

# Output only region IDs (to copy into PREFERRED_REGION)
docker compose run --rm gluetun-pia-watchdog list-servers --pf --ids
```

Sample output:
```
  #     LATENCY     REGION ID                       NAME                                    PF   WIREGUARD IP
  ────  ──────────  ──────────────────────────────  ──────────────────────────────────────  ───  ─────────────────
  1     0.003799s   de_germany-so                   DE Germany Streaming Optimized           ✅   147.90.227.155
  2     0.003858s   de-frankfurt                    DE Frankfurt                             ✅   147.90.209.204
  3     0.007621s   czech                           Czech Republic                           ✅   212.102.39.92
  4     0.010727s   nl_amsterdam                    Netherlands                              ✅   158.173.21.86
```

---

## ⚙️ Configuration

### `.env` User Variables

| Variable | Default | Description |
|:---|:---|:---|
| `PIA_USER` | *(required)* | PIA username (e.g. `p1234567`) |
| `PIA_PASS` | *(required)* | PIA password |
| `PREFERRED_REGION` | `none` | Region ID. `none` = auto-select fastest. Get IDs via `list-servers --ids` |
| `MAX_LATENCY` | `0.1` | Maximum acceptable latency in seconds |
| `PIA_PF` | `true` | Filter for port-forwarding capable servers |

### Watchdog Advanced Options

| Variable | Default | Description |
|:---|:---|:---|
| `GLUETUN_CONTAINER` | `gluetun` | Name of your Gluetun container |
| `GLUETUN_ENV_FILE` | `/config/.env` | Mounted `.env` file path |
| `QBITTORRENT_SERVER` | `gluetun` | qBittorrent hostname |
| `QBITTORRENT_PORT` | `8080` | qBittorrent WebUI port |
| `QBITTORRENT_USER` | `admin` | qBittorrent username |
| `QBITTORRENT_PASS` | `adminadmin` | qBittorrent password |
| `HEALTH_CHECK_INTERVAL` | `120` | Health check interval in seconds |
| `HEALTH_CHECK_FAILURES` | `3` | Consecutive failures before triggering renewal |
| `RENEW_INTERVAL` | `604800` | Proactive renewal interval (default: 7 days) |

---

## 🏗️ Architecture

```
┌──────────────────────────────────────────────────────────────────────┐
│                             Docker Host                              │
│                                                                      │
│  ┌──────────────────────────────┐    ┌────────────────────────────┐  │
│  │  gluetun-pia-watchdog        │    │        gluetun             │  │
│  │                              │    │                            │  │
│  │  ┌────────────────────────┐  │    │  ┌──────────────────────┐  │  │
│  │  │  Health Check (120s)   │──┼────┼─▶│  VPN Connection     │  │  │
│  │  └───────────┬────────────┘  │    │  └──────────────────────┘  │  │
│  │              │ FAIL ×3       │    │                            │  │
│  │  ┌───────────▼────────────┐  │    │  ┌──────────────────────┐  │  │
│  │  │  PIA REST API Client   │  │    │  │  PIA Port Forwarding  │  │  │
│  │  │  → Auth & Token        │  │    │  │  → forwarded_port ──┼──┼──┐
│  │  │  → Latency Test        │  │    │  └──────────────────────┘  │  ││
│  │  │  → Register WG Key     │  │    │                            │  ││
│  │  └───────────┬────────────┘  │    └────────────────────────────┘  ││
│  │              │               │                                    ││
│  │  ┌───────────▼────────────┐  │    ┌────────────────────────────┐  ││
│  │  │  Update .env           │  │    │      qBittorrent           │  ││
│  │  │  Restart Gluetun ──────┼──┼───▶│                            │  ││
│  │  └────────────────────────┘  │    │  ┌──────────────────────┐  │  ││
│  │                              │    │  │  Listen Port ◀──────┼──┼──┘│
│  │  ┌────────────────────────┐  │    │  └──────────────────────┘  │   │
│  │  │  Port Watcher          │  │    │                            │   │
│  │  │  (inotifywait) ────────┼──┼───▶│  API Set Preferences       │   │
│  │  └────────────────────────┘  │    └────────────────────────────┘   │
│  └──────────────────────────────┘                                     │
│                                                                       │
│  .env ◀── Auto-updated by Watchdog ── Read by Docker Compose         │
└───────────────────────────────────────────────────────────────────────┘
```

---

## 📄 License

[MIT License](LICENSE) — free to use and adapt.
