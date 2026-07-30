FROM alpine:latest

RUN apk update && apk add --no-cache \
    curl \
    jq \
    bash \
    bc \
    sed \
    inotify-tools \
    wireguard-tools

# Create app directory
WORKDIR /app

# Copy PIA CA certificate
COPY manual-connections/ca.rsa.4096.crt /app/manual-connections/ca.rsa.4096.crt

# Copy scripts
COPY pia_renew.sh /app/pia_renew.sh
COPY start.sh /app/start.sh
COPY list_servers.sh /app/list_servers.sh
COPY entrypoint.sh /app/entrypoint.sh

RUN chmod +x /app/*.sh

# Create config directory for .env persistence
RUN mkdir -p /config

# Default environment variables
# ── PIA Credentials (MUST be set by user) ──
ENV PIA_USER=""
ENV PIA_PASS=""

# ── PIA Server Selection ──
ENV PREFERRED_REGION="none"
ENV MAX_LATENCY="0.1"
ENV PIA_PF="true"
ENV DIP_TOKEN=""

# ── Gluetun Integration ──
ENV GLUETUN_CONTAINER="gluetun"
ENV GLUETUN_ENV_FILE="/config/.env"

# ── qBittorrent Port Injection ──
ENV QBITTORRENT_SERVER="gluetun"
ENV QBITTORRENT_PORT="8080"
ENV QBITTORRENT_USER="admin"
ENV QBITTORRENT_PASS="adminadmin"
ENV PORT_FORWARDED="/tmp/gluetun/forwarded_port"
ENV HTTP_S="http"

# ── Watchdog Tuning ──
ENV HEALTH_CHECK_INTERVAL="120"
ENV HEALTH_CHECK_FAILURES="3"
ENV RENEW_INTERVAL="604800"

ENTRYPOINT ["/app/entrypoint.sh"]
CMD ["watchdog"]
