#!/usr/bin/env bash
# ============================================================================
# start.sh — Main entrypoint for gluetun-pia-watchdog container
# ============================================================================
# Lifecycle:
#   1. Initial setup: run pia_renew.sh if .env is missing or empty.
#   2. Watchdog loop: every HEALTH_CHECK_INTERVAL seconds, check if Gluetun
#      can reach the internet. If it fails HEALTH_CHECK_FAILURES consecutive
#      times, trigger a full PIA renewal cycle.
#   3. Port forwarding: watch /tmp/gluetun/forwarded_port and inject into
#      qBittorrent whenever it changes.
#   4. Proactive renewal: every RENEW_INTERVAL seconds, force a renewal even
#      if healthy (PIA keys/servers can silently expire).
# ============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ── Configuration ────────────────────────────────────────────────────────────
: "${HEALTH_CHECK_INTERVAL:=120}"      # seconds between health checks
: "${HEALTH_CHECK_FAILURES:=3}"        # consecutive failures before renew
: "${RENEW_INTERVAL:=604800}"          # seconds between proactive renewals (default 7 days)
: "${GLUETUN_ENV_FILE:=/config/.env}"
: "${GLUETUN_CONTAINER:=gluetun}"

# Port manager settings
: "${QBITTORRENT_SERVER:=gluetun}"
: "${QBITTORRENT_PORT:=8080}"
: "${QBITTORRENT_USER:=admin}"
: "${QBITTORRENT_PASS:=adminadmin}"
: "${PORT_FORWARDED:=/tmp/gluetun/forwarded_port}"
: "${HTTP_S:=http}"

# ── Logging ──────────────────────────────────────────────────────────────────
log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO]  $*"; }
warn() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN]  $*" >&2; }

# ── Port injection (qBittorrent) ─────────────────────────────────────────────
COOKIES="/tmp/qb_cookies.txt"

update_qb_port() {
  if [[ ! -f "$PORT_FORWARDED" ]]; then
    return 1
  fi
  local port
  port=$(cat "$PORT_FORWARDED" 2>/dev/null | tr -d '[:space:]')
  if [[ -z "$port" || "$port" == "0" ]]; then
    warn "Port file exists but is empty or zero — skipping."
    return 1
  fi

  log "Injecting port $port into qBittorrent at ${QBITTORRENT_SERVER}:${QBITTORRENT_PORT} …"
  rm -f "$COOKIES"

  # Login
  local login_resp
  login_resp=$(curl -s -c "$COOKIES" --max-time 10 \
    --data "username=${QBITTORRENT_USER}&password=${QBITTORRENT_PASS}" \
    "${HTTP_S}://${QBITTORRENT_SERVER}:${QBITTORRENT_PORT}/api/v2/auth/login" 2>&1) || true

  # Set port
  curl -s -b "$COOKIES" --max-time 10 \
    --data "json={\"listen_port\": \"${port}\"}" \
    "${HTTP_S}://${QBITTORRENT_SERVER}:${QBITTORRENT_PORT}/api/v2/app/setPreferences" > /dev/null 2>&1 || true

  rm -f "$COOKIES"
  log "✅ qBittorrent listening port set to $port"
}

# ── Health check ─────────────────────────────────────────────────────────────
check_gluetun_health() {
  # Try to reach the internet THROUGH the gluetun container.
  # We use the Docker socket to exec a curl inside gluetun.
  if [[ -S /var/run/docker.sock ]]; then
    # Create exec instance
    local exec_create exec_id exec_start
    exec_create=$(curl -s --max-time 10 \
      --unix-socket /var/run/docker.sock \
      -H "Content-Type: application/json" \
      -d '{"AttachStdout":true,"AttachStderr":true,"Cmd":["wget","--spider","-q","--timeout=5","https://cloudflare.com"]}' \
      "http://localhost/containers/${GLUETUN_CONTAINER}/exec" 2>/dev/null)

    exec_id=$(echo "$exec_create" | jq -r '.Id // empty' 2>/dev/null)
    if [[ -z "$exec_id" ]]; then
      warn "Failed to create exec in $GLUETUN_CONTAINER (container may be down)."
      return 1
    fi

    exec_start=$(curl -s -o /dev/null -w "%{http_code}" --max-time 15 \
      --unix-socket /var/run/docker.sock \
      -H "Content-Type: application/json" \
      -d '{"Detach":false,"Tty":false}' \
      "http://localhost/exec/${exec_id}/start" 2>/dev/null)

    # Check exec exit code
    local inspect_resp exit_code
    inspect_resp=$(curl -s --max-time 5 \
      --unix-socket /var/run/docker.sock \
      "http://localhost/exec/${exec_id}/json" 2>/dev/null)
    exit_code=$(echo "$inspect_resp" | jq -r '.ExitCode // 1' 2>/dev/null)

    if [[ "$exit_code" == "0" ]]; then
      return 0
    else
      return 1
    fi
  else
    # Fallback: try to reach gluetun's control API
    local status
    status=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 \
      "http://${GLUETUN_CONTAINER}:8000/v1/openvpn/status" 2>/dev/null) || true
    [[ "$status" == "200" ]] && return 0
    return 1
  fi
}

# ── Run PIA renewal ─────────────────────────────────────────────────────────
run_renewal() {
  log "🔄 Running PIA WireGuard renewal …"
  bash "${SCRIPT_DIR}/pia_renew.sh"
  local rc=$?
  if [[ $rc -ne 0 ]]; then
    warn "Renewal script exited with code $rc"
  fi
  return $rc
}

# ── Port watcher (background) ───────────────────────────────────────────────
port_watcher() {
  log "Starting port file watcher on $PORT_FORWARDED …"
  while true; do
    if [[ -f "$PORT_FORWARDED" ]]; then
      update_qb_port
      # Watch for changes
      inotifywait -qq -e close_write -e moved_to "$(dirname "$PORT_FORWARDED")" 2>/dev/null || sleep 10
      # Small delay to let the file be fully written
      sleep 2
      update_qb_port
    else
      sleep 10
    fi
  done
}

# ══════════════════════════════════════════════════════════════════════════════
# MAIN
# ══════════════════════════════════════════════════════════════════════════════
cat <<'LOGO'
   ______   __                  __                ____  _____  ___       _       ______     __       __                    __
  / ____/  / /  __  __  ___    / /_  __  ______  / __ \/  _/  /   |     | |     / / __ \   / /______/ /_  ____  ____  ____/ /
 / / __   / /  / / / / / _ \  / __/ / / / / __ \/ /_/ // /   / /| |     | | /| / / /_/ /  / __/ ___/ __ \/ __ \/ __ \/ __  / 
/ /_/ /  / /__/ /_/ / /  __/ / /_  / /_/ / / / / ____// /   / ___ |     | |/ |/ / ____/  / /_/ /__/ / / / /_/ / /_/ / /_/ /  
\____/  /____/\__,_/  \___/  \__/  \__,_/_/ /_/_/   /___/  /_/  |_|     |__/|__/_/       \__/\___/_/ /_/\____/\____/\__,_/   
                                                                                                                   v1.0.2
LOGO
log "════════════════════════════════════════════════════════════════════════════"
log "  GLUETUN_CONTAINER    = $GLUETUN_CONTAINER"
log "  HEALTH_CHECK_INTERVAL= ${HEALTH_CHECK_INTERVAL}s"
log "  HEALTH_CHECK_FAILURES= $HEALTH_CHECK_FAILURES"
log "  RENEW_INTERVAL       = ${RENEW_INTERVAL}s"
log "  QBITTORRENT_SERVER   = $QBITTORRENT_SERVER"
log "  PREFERRED_REGION     = ${PREFERRED_REGION:-none}"
log "════════════════════════════════════════════════════════════════════════════"

# ── Initial setup: if WireGuard IP missing or unpopulated in .env, run renew ─
if ! grep -E -q '^WIREGUARD_ENDPOINT_IP=[0-9]+' "$GLUETUN_ENV_FILE" 2>/dev/null; then
  log "WireGuard configuration in $GLUETUN_ENV_FILE missing or empty — running initial PIA setup …"
  run_renewal || warn "Initial renewal failed; will retry in watchdog loop."
  log "Waiting 15s for Gluetun to initialize …"
  sleep 15
fi

# ── Start port watcher in background ────────────────────────────────────────
port_watcher &
PORT_WATCHER_PID=$!
log "Port watcher started (PID $PORT_WATCHER_PID)."

# ── Watchdog loop ────────────────────────────────────────────────────────────
fail_count=0
last_renew=$(date +%s)

while true; do
  sleep "$HEALTH_CHECK_INTERVAL"

  now=$(date +%s)
  elapsed=$(( now - last_renew ))

  # ── Proactive renewal ────────────────────────────────────────────────────
  if (( elapsed >= RENEW_INTERVAL )); then
    log "⏰ Proactive renewal triggered (${elapsed}s since last renewal, threshold ${RENEW_INTERVAL}s)."
    if run_renewal; then
      fail_count=0
      last_renew=$(date +%s)
      log "Waiting 30s for Gluetun to restart …"
      sleep 30
      continue
    else
      warn "Proactive renewal failed — will keep retrying."
    fi
  fi

  # ── Health check ─────────────────────────────────────────────────────────
  if check_gluetun_health; then
    if (( fail_count > 0 )); then
      log "✅ Gluetun is healthy again after $fail_count failure(s)."
    fi
    fail_count=0
  else
    fail_count=$(( fail_count + 1 ))
    warn "Health check FAILED ($fail_count/$HEALTH_CHECK_FAILURES)"

    if (( fail_count >= HEALTH_CHECK_FAILURES )); then
      log "💀 $HEALTH_CHECK_FAILURES consecutive failures — triggering renewal."
      if run_renewal; then
        fail_count=0
        last_renew=$(date +%s)
        log "Waiting 30s for Gluetun to restart …"
        sleep 30
      else
        warn "Renewal failed — will retry next cycle."
      fi
    fi
  fi
done
