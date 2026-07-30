<p align="center">
  <img src="https://img.shields.io/github/license/yuanweize/gluetun-pia-watchdog?style=flat-square" alt="License">
  <img src="https://img.shields.io/github/actions/workflow/status/yuanweize/gluetun-pia-watchdog/docker-publish.yml?style=flat-square&label=build" alt="Build Status">
  <img src="https://img.shields.io/badge/docker-ghcr.io-blue?style=flat-square&logo=docker" alt="Docker">
  <img src="https://img.shields.io/badge/platform-amd64%20%7C%20arm64-lightgrey?style=flat-square" alt="Platform">
</p>

<h1 align="center">🛡️ Gluetun PIA Watchdog</h1>

<p align="center">
  <strong>Automatic PIA WireGuard key registration, health monitoring, self-healing reconnection & qBittorrent port injection — all in one lightweight container.</strong>
</p>

<p align="center">
  <a href="#the-problem">The Problem</a> •
  <a href="#the-solution">The Solution</a> •
  <a href="#quick-start">Quick Start</a> •
  <a href="#server-browser">Server Browser</a> •
  <a href="#configuration">Configuration</a> •
  <a href="#architecture">Architecture</a> •
  <a href="#faq">FAQ</a>
</p>

---

## The Problem

[Gluetun](https://github.com/qdm12/gluetun) is the gold standard for routing Docker containers through a VPN. But when used with **Private Internet Access (PIA)** in `custom` WireGuard mode, you face a painful cycle:

```
PIA rotates servers → Your WireGuard keys expire → Gluetun can't connect
→ i/o timeout loops → You manually run scripts → Copy-paste 6 variables
→ Restart everything → Repeat in a few days/weeks 😩
```

The official [manual-connections](https://github.com/pia-foss/manual-connections) scripts require interactive input. The built-in PIA provider in Gluetun frequently breaks. And [gluetun-qbittorrent-port-manager](https://github.com/snoringdragon/gluetun-qbittorrent-port-manager) only handles port injection — it can't fix a dead VPN connection.

## The Solution

**Gluetun PIA Watchdog** is a single, lightweight Alpine container (~15 MB) that **eliminates all manual intervention**:

```
Watchdog detects failure → Authenticates with PIA API → Selects fastest server
→ Generates fresh WireGuard keys → Registers with PIA → Updates .env
→ Restarts Gluetun → Injects forwarded port into qBittorrent → 🎉 All automatic
```

---

## ✨ Features

| Feature | Description |
|:--------|:------------|
| 🔑 **Auto Key Registration** | Generates WireGuard keypairs and registers them with PIA's `addKey` API — zero manual steps |
| 🌍 **Smart Server Selection** | Auto-selects the lowest latency server with port-forwarding support, or lock to a preferred region |
| 🔍 **Server Browser** | Built-in CLI tool to browse, filter, and search PIA's 100+ servers |
| 📝 **Atomic `.env` Updates** | Surgically updates only WireGuard variables — preserves your credentials and other config |
| 🔄 **Auto Container Restart** | Restarts Gluetun via Docker socket after each renewal — fully hands-off |
| 🏥 **Health Monitoring** | Checks Gluetun connectivity every N seconds; self-heals after configurable failures |
| ⏰ **Proactive Renewal** | Forces key refresh every 7 days (configurable) — prevents silent expiry surprises |
| 🔌 **Port Injection** | Watches `forwarded_port` via `inotifywait` and pushes it to qBittorrent's API |
| 🪶 **Lightweight** | ~15 MB Alpine image. No Python, no Node.js — just bash, curl, jq, and wireguard-tools |
| 🏗️ **Multi-Arch** | Built for `linux/amd64` and `linux/arm64` |

---

## Quick Start

### 1. Create your `.env` file

```bash
cp .env.example .env
nano .env
```

```env
# ── PIA Credentials (REQUIRED) ──
PIA_USER=p1234567
PIA_PASS=your_pia_password

# ── Server Selection ──
PREFERRED_REGION=none    # "none" = auto-select fastest
MAX_LATENCY=0.1          # seconds
PIA_PF=true              # only port-forwarding servers

# ── Dynamic WireGuard Config (auto-generated — DO NOT EDIT) ──
SERVER_NAMES=
WIREGUARD_ENDPOINT_IP=
WIREGUARD_ENDPOINT_PORT=
WIREGUARD_PUBLIC_KEY=
WIREGUARD_PRIVATE_KEY=
WIREGUARD_ADDRESSES=
```

### 2. Add to your `docker-compose.yml`

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
      # ⬇️ Auto-populated from .env by the watchdog
      - SERVER_NAMES=${SERVER_NAMES}
      - WIREGUARD_ENDPOINT_IP=${WIREGUARD_ENDPOINT_IP}
      - WIREGUARD_ENDPOINT_PORT=${WIREGUARD_ENDPOINT_PORT}
      - WIREGUARD_PUBLIC_KEY=${WIREGUARD_PUBLIC_KEY}
      - WIREGUARD_PRIVATE_KEY=${WIREGUARD_PRIVATE_KEY}
      - WIREGUARD_ADDRESSES=${WIREGUARD_ADDRESSES}
      # PIA port forwarding
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
docker logs -f gluetun-pia-watchdog  # Watch the magic
```

On first start, the watchdog will automatically:
1. ✅ Authenticate with PIA
2. ✅ Find the fastest server
3. ✅ Generate & register WireGuard keys
4. ✅ Write your `.env` file
5. ✅ Restart Gluetun with fresh config
6. ✅ Inject the forwarded port into qBittorrent

---

## 🔍 Server Browser

Don't know which PIA region to use? The built-in server browser helps you explore:

```bash
# List all port-forwarding servers, sorted by latency
docker run --rm ghcr.io/yuanweize/gluetun-pia-watchdog list-servers --pf

# Filter by region keyword
docker run --rm ghcr.io/yuanweize/gluetun-pia-watchdog list-servers --pf --region germany

# Custom latency threshold
docker run --rm ghcr.io/yuanweize/gluetun-pia-watchdog list-servers --pf --latency 0.05

# Get just region IDs (for your PREFERRED_REGION config)
docker run --rm ghcr.io/yuanweize/gluetun-pia-watchdog list-servers --pf --ids

# Raw JSON output
docker run --rm ghcr.io/yuanweize/gluetun-pia-watchdog list-servers --pf --json
```

Example output:
```
🌍 Fetching PIA server list …
⏱️  Testing latency (max 0.1s) …

  #     LATENCY     REGION ID                       NAME                                    PF   WIREGUARD IP
  ────  ──────────  ──────────────────────────────  ──────────────────────────────────────  ───  ─────────────────
  1     0.003799s   de_germany-so                   DE Germany Streaming Optimized           ✅   147.90.227.155
  2     0.003858s   de-frankfurt                    DE Frankfurt                             ✅   147.90.209.204
  3     0.007621s   czech                           Czech Republic                           ✅   212.102.39.92
  4     0.009498s   ad                              Andorra (geo)                            ✅   173.239.217.186
  ...

📊 Found 67 servers responding within 0.1s

💡 To use a specific region, set PREFERRED_REGION in your .env file.
   Example: PREFERRED_REGION=de_germany-so
```

---

## ⚙️ Configuration

All configuration lives in a **single `.env` file** — no duplicate credentials, no extra config files.

### `.env` — User Settings

| Variable | Default | Description |
|:---------|:--------|:------------|
| `PIA_USER` | *(required)* | PIA username (e.g. `p1234567`) |
| `PIA_PASS` | *(required)* | PIA password |
| `PREFERRED_REGION` | `none` | Region ID. `none` = auto-select lowest latency. Find IDs with `list-servers --ids` |
| `MAX_LATENCY` | `0.1` | Maximum acceptable latency in seconds |
| `PIA_PF` | `true` | Only consider port-forwarding servers |

### Container Environment — Behavior Tuning

| Variable | Default | Description |
|:---------|:--------|:------------|
| `GLUETUN_CONTAINER` | `gluetun` | Name of your Gluetun container |
| `GLUETUN_ENV_FILE` | `/config/.env` | Path where `.env` is mounted inside the container |
| `QBITTORRENT_SERVER` | `gluetun` | Hostname/IP of qBittorrent |
| `QBITTORRENT_PORT` | `8080` | qBittorrent WebUI port |
| `QBITTORRENT_USER` | `admin` | qBittorrent username |
| `QBITTORRENT_PASS` | `adminadmin` | qBittorrent password |
| `PORT_FORWARDED` | `/tmp/gluetun/forwarded_port` | Gluetun's forwarded port file path |
| `HTTP_S` | `http` | Protocol for qBittorrent API |
| `HEALTH_CHECK_INTERVAL` | `120` | Seconds between health checks |
| `HEALTH_CHECK_FAILURES` | `3` | Consecutive failures before renewal |
| `RENEW_INTERVAL` | `604800` | Seconds between proactive renewals (default: 7 days) |

---

## 🏗️ Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│                        Docker Host                               │
│                                                                  │
│  ┌──────────────────────────┐    ┌───────────────────────────┐  │
│  │  gluetun-pia-watchdog    │    │        gluetun             │  │
│  │                          │    │                           │  │
│  │  ┌────────────────────┐  │    │  ┌─────────────────────┐  │  │
│  │  │  Health Check Loop │──┼────┼─▶│  VPN Connection     │  │  │
│  │  └────────┬───────────┘  │    │  └─────────────────────┘  │  │
│  │           │ FAIL ×3      │    │                           │  │
│  │  ┌────────▼───────────┐  │    │  ┌─────────────────────┐  │  │
│  │  │  PIA API Client    │  │    │  │  Port Forwarding    │  │  │
│  │  │  → Authenticate    │  │    │  │  → forwarded_port ──┼──┼──┐
│  │  │  → Select Server   │  │    │  └─────────────────────┘  │  │
│  │  │  → Register WG Key │  │    │                           │  │
│  │  └────────┬───────────┘  │    └───────────────────────────┘  │
│  │           │              │                                    │
│  │  ┌────────▼───────────┐  │    ┌───────────────────────────┐  │
│  │  │  Update .env       │  │    │      qBittorrent          │  │
│  │  │  Restart Gluetun ──┼──┼───▶│                           │  │
│  │  └────────────────────┘  │    │  ┌─────────────────────┐  │  │
│  │                          │    │  │  Listen Port ◀──────┼──┼──┘
│  │  ┌────────────────────┐  │    │  └─────────────────────┘  │
│  │  │  Port Watcher      │  │    │                           │
│  │  │  (inotifywait) ────┼──┼───▶│  API: setPreferences     │
│  │  └────────────────────┘  │    └───────────────────────────┘
│  └──────────────────────────┘                                    │
│                                                                  │
│  .env ◀── auto-updated by watchdog ──▶ read by docker compose   │
└──────────────────────────────────────────────────────────────────┘
```

### Lifecycle

1. **Startup** — Checks if `.env` has valid WireGuard config. If not → full PIA registration
2. **Registration** — Auth → server list → latency test → keygen → API call → write `.env`
3. **Restart** — Sends restart command to Gluetun via Docker socket API
4. **Port Watch** — `inotifywait` on `/tmp/gluetun/forwarded_port` → push to qBittorrent
5. **Monitoring** — Health check every 2 min → 3 failures → auto-renewal
6. **Proactive** — Forced renewal every 7 days even if healthy

---

## 📦 Docker Commands

```bash
# Run the watchdog (default)
docker compose up -d gluetun-pia-watchdog

# Browse servers
docker run --rm ghcr.io/yuanweize/gluetun-pia-watchdog list-servers --pf

# Force a one-shot renewal
docker compose exec gluetun-pia-watchdog /app/entrypoint.sh renew

# View help
docker run --rm ghcr.io/yuanweize/gluetun-pia-watchdog help
```

---

## Required Volumes

| Mount | Purpose |
|:------|:--------|
| `./data/gluetun/temp:/tmp/gluetun` | Shared directory for Gluetun's `forwarded_port` file |
| `/var/run/docker.sock:/var/run/docker.sock:ro` | Docker socket (**read-only**) for health checks and container restart |
| `./.env:/config/.env` | Persistent `.env` file shared between watchdog and Docker Compose |

---

## FAQ

<details>
<summary><strong>Why not use Gluetun's built-in PIA support?</strong></summary>

Gluetun's native PIA integration frequently breaks when PIA rotates server infrastructure. Using the `custom` provider with manually-registered WireGuard keys is more reliable — this container automates the manual part.
</details>

<details>
<summary><strong>Is mounting the Docker socket safe?</strong></summary>

The socket is mounted **read-only** (`:ro`). The watchdog only uses it for:
1. Running health checks inside the Gluetun container (`exec`)
2. Restarting the Gluetun container (`restart`)

It cannot pull images, create new containers, or perform destructive operations.
</details>

<details>
<summary><strong>Can I use this without qBittorrent?</strong></summary>

Yes! The port injection is optional. If qBittorrent isn't reachable, the watchdog logs a warning and continues with VPN health monitoring.
</details>

<details>
<summary><strong>What happens during a renewal?</strong></summary>

1. Gluetun restarts (~5-10 seconds of downtime)
2. All containers using `network_mode: "service:gluetun"` briefly lose network
3. Gluetun reconnects with fresh WireGuard keys
4. Port forwarding re-establishes automatically
5. Watchdog injects the new port into qBittorrent

Total downtime: typically under 30 seconds.
</details>

<details>
<summary><strong>Where do I find PIA region IDs?</strong></summary>

Use the built-in server browser:
```bash
docker run --rm ghcr.io/yuanweize/gluetun-pia-watchdog list-servers --pf --ids
```

Or check the raw API: https://serverlist.piaservers.net/vpninfo/servers/v6
</details>

---

## Credits & Inspiration

- [qdm12/gluetun](https://github.com/qdm12/gluetun) — The VPN container that makes this all possible
- [snoringdragon/gluetun-qbittorrent-port-manager](https://github.com/snoringdragon/gluetun-qbittorrent-port-manager) — Original port injection concept
- [pia-foss/manual-connections](https://github.com/pia-foss/manual-connections) — Official PIA scripts that we automated

---

## License

[MIT License](LICENSE) — free to use, modify, and distribute.
