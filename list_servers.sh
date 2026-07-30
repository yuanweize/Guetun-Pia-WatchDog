#!/usr/bin/env bash
# ============================================================================
# list_servers.sh — Human-friendly PIA server browser
# Part of gluetun-pia-watchdog
# ============================================================================
# Usage:
#   list_servers.sh                    # List all servers, sorted by latency
#   list_servers.sh --pf               # Only port-forwarding servers
#   list_servers.sh --region europe    # Filter by keyword (case-insensitive)
#   list_servers.sh --pf --region de   # Combine filters
#   list_servers.sh --latency 0.05     # Custom latency threshold (seconds)
#   list_servers.sh --ids              # Show region IDs only (for PREFERRED_REGION)
#   list_servers.sh --json             # Raw JSON output
# ============================================================================
set -uo pipefail

SERVERLIST_URL="https://serverlist.piaservers.net/vpninfo/servers/v6"

# ── Defaults ─────────────────────────────────────────────────────────────────
FILTER_PF="false"
FILTER_REGION=""
MAX_LATENCY="${MAX_LATENCY:-0.15}"
OUTPUT_IDS="false"
OUTPUT_JSON="false"
SHOW_HELP="false"

# ── Parse arguments ──────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --pf|--port-forwarding)
      FILTER_PF="true"; shift ;;
    --region|-r)
      FILTER_REGION="$2"; shift 2 ;;
    --latency|-l)
      MAX_LATENCY="$2"; shift 2 ;;
    --ids)
      OUTPUT_IDS="true"; shift ;;
    --json)
      OUTPUT_JSON="true"; shift ;;
    --help|-h)
      SHOW_HELP="true"; shift ;;
    *)
      echo "Unknown option: $1" >&2
      SHOW_HELP="true"; shift ;;
  esac
done

if [[ "$SHOW_HELP" == "true" ]]; then
  cat <<'HELP'
🛡️  gluetun-pia-watchdog — PIA Server Browser

USAGE:
  list-servers [OPTIONS]

OPTIONS:
  --pf, --port-forwarding   Only show servers that support port forwarding
  --region, -r KEYWORD      Filter by region name or ID (case-insensitive)
                            Examples: --region germany, --region de, --region asia
  --latency, -l SECONDS     Max latency threshold (default: 0.15s)
                            Servers slower than this are skipped
  --ids                     Output region IDs only (useful for PREFERRED_REGION)
  --json                    Output raw JSON from PIA API
  --help, -h                Show this help

EXAMPLES:
  # Show all port-forwarding servers in Germany
  docker run --rm ghcr.io/yuanweize/gluetun-pia-watchdog list-servers --pf --region germany

  # Find fastest servers with latency under 50ms
  docker run --rm ghcr.io/yuanweize/gluetun-pia-watchdog list-servers --pf --latency 0.05

  # Get just the region IDs for your config
  docker run --rm ghcr.io/yuanweize/gluetun-pia-watchdog list-servers --pf --ids

HELP
  exit 0
fi

# ── Fetch server list ────────────────────────────────────────────────────────
echo "🌍 Fetching PIA server list …" >&2
all_data=$(curl -s --max-time 15 "$SERVERLIST_URL" | head -1)

if [[ ${#all_data} -lt 1000 ]]; then
  echo "❌ Failed to fetch server list. Check your internet connection." >&2
  exit 1
fi

# ── Raw JSON mode ────────────────────────────────────────────────────────────
if [[ "$OUTPUT_JSON" == "true" ]]; then
  if [[ "$FILTER_PF" == "true" ]]; then
    echo "$all_data" | jq '.regions[] | select(.port_forward==true)'
  else
    echo "$all_data" | jq '.regions[]'
  fi
  exit 0
fi

# ── Build JQ filter ──────────────────────────────────────────────────────────
jq_filter='.regions[]'
if [[ "$FILTER_PF" == "true" ]]; then
  jq_filter="$jq_filter | select(.port_forward==true)"
fi

# Extract candidates
candidates=$(echo "$all_data" | jq -r "$jq_filter |
  .servers.meta[0].ip+\"\t\"+.id+\"\t\"+.name+\"\t\"+(.port_forward|tostring)+\"\t\"+(.geo|tostring)+\"\t\"+(.servers.wg[0].ip // \"N/A\")")

# ── Apply region keyword filter ──────────────────────────────────────────────
if [[ -n "$FILTER_REGION" ]]; then
  candidates=$(echo "$candidates" | grep -i "$FILTER_REGION" || true)
fi

if [[ -z "$candidates" ]]; then
  echo "❌ No servers match your filters." >&2
  exit 1
fi

# ── IDs-only mode ────────────────────────────────────────────────────────────
if [[ "$OUTPUT_IDS" == "true" ]]; then
  echo "$candidates" | awk -F'\t' '{print $2}' | sort
  exit 0
fi

# ── Measure latency ──────────────────────────────────────────────────────────
echo "⏱️  Testing latency (max ${MAX_LATENCY}s) …" >&2
echo "" >&2

results=""
count=0
while IFS=$'\t' read -r meta_ip region_id region_name pf geo wg_ip; do
  t=$(LC_NUMERIC=en_US.utf8 curl -o /dev/null -s \
      --connect-timeout "$MAX_LATENCY" \
      --write-out "%{time_connect}" \
      "http://${meta_ip}:443" 2>/dev/null) || continue
  count=$((count + 1))

  pf_icon="❌"
  [[ "$pf" == "true" ]] && pf_icon="✅"

  geo_tag=""
  [[ "$geo" == "true" ]] && geo_tag=" (geo)"

  results+=$(printf "%s\t%s\t%s%s\t%s\t%s\t%s\n" "$t" "$region_id" "$region_name" "$geo_tag" "$pf_icon" "$wg_ip" "$meta_ip")
done <<< "$candidates"

if [[ -z "$results" ]]; then
  echo "❌ No servers responded within ${MAX_LATENCY}s. Try --latency 0.3" >&2
  exit 1
fi

# ── Sort & display ───────────────────────────────────────────────────────────
sorted=$(echo "$results" | sort -t$'\t' -k1 -n)

# Header
printf "\n"
printf "  %-4s  %-10s  %-30s  %-38s  %-3s  %-17s\n" "#" "LATENCY" "REGION ID" "NAME" "PF" "WIREGUARD IP"
printf "  %-4s  %-10s  %-30s  %-38s  %-3s  %-17s\n" "────" "──────────" "──────────────────────────────" "──────────────────────────────────────" "───" "─────────────────"

i=0
while IFS=$'\t' read -r latency region_id region_name pf_icon wg_ip meta_ip; do
  i=$((i + 1))
  printf "  %-4s  %-10s  %-30s  %-38s  %-3s  %-17s\n" "$i" "${latency}s" "$region_id" "$region_name" "$pf_icon" "$wg_ip"
done <<< "$sorted"

printf "\n"
echo "📊 Found $count servers responding within ${MAX_LATENCY}s" >&2
echo "" >&2
echo "💡 To use a specific region, set PREFERRED_REGION in your .env file." >&2
echo "   Example: PREFERRED_REGION=$(echo "$sorted" | head -1 | awk -F'\t' '{print $2}')" >&2
echo "" >&2
