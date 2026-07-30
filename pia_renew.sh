#!/usr/bin/env bash
# ============================================================================
# pia_renew.sh — Headless PIA WireGuard Key Registration & .env Writer
# Part of gluetun-pia-watchdog
# ============================================================================
# This script:
#   1. Authenticates with PIA to get a 24h token.
#   2. Queries PIA server list and picks the best (lowest latency) region.
#   3. Generates a fresh WireGuard keypair.
#   4. Registers the public key with PIA's WireGuard API.
#   5. Writes the resulting config to GLUETUN_ENV_FILE (default: /config/.env).
#   6. Restarts the gluetun container via Docker socket.
# ============================================================================
set -euo pipefail

# ── Helpers ──────────────────────────────────────────────────────────────────
log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO]  $*"; }
warn() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN]  $*" >&2; }
die()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [FATAL] $*" >&2; exit 1; }

# ── Configuration (from environment) ─────────────────────────────────────────
: "${PIA_USER:?PIA_USER must be set}"
: "${PIA_PASS:?PIA_PASS must be set}"
: "${PREFERRED_REGION:=none}"          # "none" = auto-select lowest latency
: "${MAX_LATENCY:=0.1}"               # seconds; servers slower than this are skipped
: "${PIA_PF:=true}"                   # enable port-forwarding filter
: "${GLUETUN_ENV_FILE:=/config/.env}" # where to write the .env
: "${GLUETUN_CONTAINER:=gluetun}"     # container name to restart
: "${CA_CERT:=/app/manual-connections/ca.rsa.4096.crt}"
: "${DIP_TOKEN:=}"                    # dedicated IP token (usually empty)

SERVERLIST_URL="https://serverlist.piaservers.net/vpninfo/servers/v6"

# ── Step 1: Get authentication token ────────────────────────────────────────
log "Authenticating with PIA as $PIA_USER …"
tokenResponse=$(curl -s --max-time 15 --location --request POST \
  'https://www.privateinternetaccess.com/api/client/v2/token' \
  --form "username=$PIA_USER" \
  --form "password=$PIA_PASS")

PIA_TOKEN=$(echo "$tokenResponse" | jq -r '.token // empty')
[[ -z "$PIA_TOKEN" ]] && die "Authentication failed! Check PIA_USER / PIA_PASS."
log "Token acquired (expires in 24 h)."

# ── Step 2: Get server list & pick best region ──────────────────────────────
log "Fetching PIA server list …"
all_region_data=$(curl -s --max-time 15 "$SERVERLIST_URL" | head -1)
[[ ${#all_region_data} -lt 1000 ]] && die "Server list too short — network error?"

if [[ "$PREFERRED_REGION" == "none" ]]; then
  log "Auto-selecting region (MAX_LATENCY=${MAX_LATENCY}s, PIA_PF=$PIA_PF) …"

  # Build candidate list (filter by port-forwarding if needed)
  if [[ "$PIA_PF" == "true" ]]; then
    candidates=$(echo "$all_region_data" | jq -r \
      '.regions[] | select(.port_forward==true) |
       .servers.meta[0].ip+" "+.id+" "+.name+" "+(.geo|tostring)')
  else
    candidates=$(echo "$all_region_data" | jq -r \
      '.regions[] |
       .servers.meta[0].ip+" "+.id+" "+.name+" "+(.geo|tostring)')
  fi

  # Measure latency to each candidate (parallel, capped)
  best=""
  best_latency="999"
  while IFS= read -r line; do
    ip=$(echo "$line" | awk '{print $1}')
    region_id=$(echo "$line" | awk '{print $2}')
    t=$(LC_NUMERIC=en_US.utf8 curl -o /dev/null -s \
        --connect-timeout "$MAX_LATENCY" \
        --write-out "%{time_connect}" \
        "http://${ip}:443" 2>/dev/null) || continue
    if (( $(echo "$t < $best_latency" | bc -l) )); then
      best_latency="$t"
      best="$region_id"
    fi
  done <<< "$candidates"

  [[ -z "$best" ]] && die "No region responded within ${MAX_LATENCY}s. Try increasing MAX_LATENCY."
  PREFERRED_REGION="$best"
  log "Selected region: $PREFERRED_REGION (latency: ${best_latency}s)"
else
  log "Using specified region: $PREFERRED_REGION"
fi

# Extract WireGuard server details for the chosen region
regionData=$(echo "$all_region_data" | jq --arg R "$PREFERRED_REGION" -r \
  '.regions[] | select(.id==$R)')
[[ -z "$regionData" ]] && die "Region '$PREFERRED_REGION' not found in server list."

WG_SERVER_IP=$(echo "$regionData"  | jq -r '.servers.wg[0].ip')
WG_HOSTNAME=$(echo "$regionData"   | jq -r '.servers.wg[0].cn')
META_IP=$(echo "$regionData"       | jq -r '.servers.meta[0].ip')
REGION_NAME=$(echo "$regionData"   | jq -r '.name')

log "Best WireGuard server: $WG_HOSTNAME ($WG_SERVER_IP) in $REGION_NAME"

# ── Step 3: Generate WireGuard keypair ──────────────────────────────────────
privKey=$(wg genkey)
pubKey=$(echo "$privKey" | wg pubkey)
log "Generated fresh WireGuard keypair."

# ── Step 4: Register public key with PIA API ────────────────────────────────
log "Registering public key with PIA WireGuard API on $WG_SERVER_IP …"
if [[ -z "$DIP_TOKEN" ]]; then
  wg_json=$(curl -s --max-time 15 -G \
    --connect-to "$WG_HOSTNAME::$WG_SERVER_IP:" \
    --cacert "$CA_CERT" \
    --data-urlencode "pt=${PIA_TOKEN}" \
    --data-urlencode "pubkey=$pubKey" \
    "https://${WG_HOSTNAME}:1337/addKey")
else
  wg_json=$(curl -s --max-time 15 -G \
    --connect-to "$WG_HOSTNAME::$WG_SERVER_IP:" \
    --cacert "$CA_CERT" \
    --user "dedicated_ip_${DIP_TOKEN}:${WG_SERVER_IP}" \
    --data-urlencode "pubkey=$pubKey" \
    "https://${WG_HOSTNAME}:1337/addKey")
fi

status=$(echo "$wg_json" | jq -r '.status // empty')
[[ "$status" != "OK" ]] && die "PIA addKey API returned: $(echo "$wg_json" | jq -c .)"

peer_ip=$(echo "$wg_json"     | jq -r '.peer_ip')
server_key=$(echo "$wg_json"  | jq -r '.server_key')
server_port=$(echo "$wg_json" | jq -r '.server_port')

log "✅ Key registered! peer_ip=$peer_ip server_port=$server_port"

# ── Step 5: Update .env file for Gluetun ────────────────────────────────────
log "Updating WireGuard variables in $GLUETUN_ENV_FILE …"

# Helper: update or append a key=value in the .env file (safe for Docker bind-mounts)
update_env_var() {
  local key="$1" val="$2" file="$3"
  if grep -q "^${key}=" "$file" 2>/dev/null; then
    local tmp; tmp=$(mktemp)
    sed "s|^${key}=.*|${key}=${val}|" "$file" > "$tmp"
    cat "$tmp" > "$file"
    rm -f "$tmp"
  else
    echo "${key}=${val}" >> "$file"
  fi
}

# Create file if it doesn't exist
touch "$GLUETUN_ENV_FILE"

# Update the auto-renewal timestamp comment
if grep -q "^# WATCHDOG_LAST_RENEWAL=" "$GLUETUN_ENV_FILE" 2>/dev/null; then
  tmp_ts=$(mktemp)
  sed "s|^# WATCHDOG_LAST_RENEWAL=.*|# WATCHDOG_LAST_RENEWAL=$(date -Iseconds)|" "$GLUETUN_ENV_FILE" > "$tmp_ts"
  cat "$tmp_ts" > "$GLUETUN_ENV_FILE"
  rm -f "$tmp_ts"
else
  echo "# WATCHDOG_LAST_RENEWAL=$(date -Iseconds)" >> "$GLUETUN_ENV_FILE"
fi

# Update only the 6 dynamic WireGuard variables (preserves all other entries)
update_env_var "SERVER_NAMES"              "$WG_HOSTNAME"  "$GLUETUN_ENV_FILE"
update_env_var "WIREGUARD_ENDPOINT_IP"     "$WG_SERVER_IP" "$GLUETUN_ENV_FILE"
update_env_var "WIREGUARD_ENDPOINT_PORT"   "$server_port"  "$GLUETUN_ENV_FILE"
update_env_var "WIREGUARD_PUBLIC_KEY"      "$server_key"   "$GLUETUN_ENV_FILE"
update_env_var "WIREGUARD_PRIVATE_KEY"     "$privKey"      "$GLUETUN_ENV_FILE"
update_env_var "WIREGUARD_ADDRESSES"       "${peer_ip}/32" "$GLUETUN_ENV_FILE"

log "✅ .env updated (other variables preserved)."

# ── Step 6: Restart Gluetun container ───────────────────────────────────────
if [[ -S /var/run/docker.sock ]]; then
  log "Restarting container '$GLUETUN_CONTAINER' …"
  # Use the Docker Engine API directly via the socket
  restart_status=$(curl -s -o /dev/null -w "%{http_code}" --max-time 30 \
    --unix-socket /var/run/docker.sock \
    -X POST "http://localhost/containers/${GLUETUN_CONTAINER}/restart?t=5")
  if [[ "$restart_status" == "204" ]]; then
    log "✅ Container '$GLUETUN_CONTAINER' restarted successfully."
  else
    warn "Container restart returned HTTP $restart_status (expected 204)."
  fi
else
  warn "Docker socket not available at /var/run/docker.sock — skipping restart."
  warn "You may need to manually run: docker restart $GLUETUN_CONTAINER"
fi

log "🎉 PIA WireGuard renewal complete."
