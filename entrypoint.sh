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
🛡️  gluetun-pia-watchdog — All-in-one PIA WireGuard manager for Gluetun

COMMANDS:
  watchdog       Start the main watchdog daemon (default)
  list-servers   Browse and filter PIA servers interactively
  renew          Run a one-shot PIA WireGuard key renewal
  help           Show this message

EXAMPLES:
  # Run the watchdog (default when using docker compose)
  docker compose up -d gluetun-pia-watchdog

  # Browse PIA servers with port forwarding
  docker run --rm ghcr.io/yuanweize/gluetun-pia-watchdog list-servers --pf

  # Filter by region
  docker run --rm ghcr.io/yuanweize/gluetun-pia-watchdog list-servers --pf --region germany

  # One-shot renewal
  docker compose run --rm gluetun-pia-watchdog renew
EOF
    ;;
  *)
    echo "Unknown command: $1" >&2
    echo "Run with 'help' for usage information." >&2
    exit 1
    ;;
esac
