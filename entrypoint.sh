#!/usr/bin/env bash
# ============================================================================
# entrypoint.sh — Multi-command entrypoint for gluetun-pia-watchdog
# ============================================================================
set -uo pipefail

case "${1:-watchdog}" in
  watchdog|start)
    exec /app/start.sh
    ;;
  list-servers|list|servers)
    shift
    exec /app/list_servers.sh "$@"
    ;;
  renew|refresh)
    exec /app/pia_renew.sh
    ;;
  help|--help|-h)
    cat <<'EOF'
   ______   __                  __                ____  _____  ___       _       ______     __       __                    __
  / ____/  / /  __  __  ___    / /_  __  ______  / __ \/  _/  /   |     | |     / / __ \   / /______/ /_  ____  ____  ____/ /
 / / __   / /  / / / / / _ \  / __/ / / / / __ \/ /_/ // /   / /| |     | | /| / / /_/ /  / __/ ___/ __ \/ __ \/ __ \/ __  / 
/ /_/ /  / /__/ /_/ / /  __/ / /_  / /_/ / / / / ____// /   / ___ |     | |/ |/ / ____/  / /_/ /__/ / / / /_/ / /_/ / /_/ /  
\____/  /____/\__,_/  \___/  \__/  \__,_/_/ /_/_/   /___/  /_/  |_|     |__/|__/_/       \__/\___/_/ /_/\____/\____/\__,_/   
                                                                                                                   v1.0.2

🛡️  Gluetun PIA Watchdog — All-in-one PIA WireGuard Manager for Gluetun

COMMANDS:
  watchdog                 Start the main watchdog daemon (default)
  list-servers [OPTIONS]   Browse, filter, and latency-test PIA servers
  renew                    Run a one-shot PIA WireGuard key renewal & restart Gluetun
  help, --help, -h         Display this interactive help menu

SERVER BROWSER OPTIONS (for list-servers):
  --pf, --port-forwarding  Filter only servers that support port forwarding
  --region, -r KEYWORD     Filter servers by name/ID (e.g. --region germany, --region nl)
  --latency, -l SECONDS    Max allowed latency threshold (default: 0.15s)
  --ids                    Output only region IDs (useful for PREFERRED_REGION config)
  --json                   Output raw JSON response from PIA API

EXAMPLES:
  # 🚀 Start the daemon (used in docker-compose.yml)
  docker compose up -d gluetun-pia-watchdog

  # 🔍 Browse port-forwarding servers with lowest latency
  docker compose run --rm gluetun-pia-watchdog list-servers --pf

  # 🇩🇪 Filter servers in Germany
  docker compose run --rm gluetun-pia-watchdog list-servers --pf --region germany

  # ⏱️ Find ultra-low latency servers (< 50ms)
  docker compose run --rm gluetun-pia-watchdog list-servers --pf --latency 0.05

  # 🔑 Force immediate key renewal
  docker compose run --rm gluetun-pia-watchdog renew

DOCUMENTATION:
  GitHub: https://github.com/yuanweize/gluetun-pia-watchdog
  Docker: ghcr.io/yuanweize/gluetun-pia-watchdog:latest
EOF
    ;;
  *)
    echo "Unknown command: $1" >&2
    echo "Run with 'help' for usage information." >&2
    exit 1
    ;;
esac
