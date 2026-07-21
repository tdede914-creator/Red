#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────
#  KOBONG VPN BOT — ZIVPN UDP installer
#  Based on: https://github.com/zahidbd2/udp-zivpn (official ZIVPN UDP)
#
#  Env overrides:
#    ZIVPN_PORT       — UDP listen port (default: 5667)
#    ZIVPN_PASSWORDS  — comma-separated auth passwords (default: "zi")
#    ZIVPN_OBFS       — obfuscation string (default: "zivpn")
#    ZIVPN_RANGE      — DNAT source port range (default: 6000:19999)
#
#  Uses config paths under /etc/kobong/zivpn so it doesn't clash with
#  the upstream /etc/zivpn convention if user runs both.
# ─────────────────────────────────────────────────────────────────────
set -euo pipefail

readonly ZIVPN_VERSION="1.4.9"
readonly ZIVPN_BINARY_URL="https://github.com/zahidbd2/udp-zivpn/releases/download/udp-zivpn_${ZIVPN_VERSION}/udp-zivpn-linux-amd64"

ZIVPN_PORT="${ZIVPN_PORT:-5667}"
ZIVPN_PASSWORDS="${ZIVPN_PASSWORDS:-zi}"
ZIVPN_OBFS="${ZIVPN_OBFS:-zivpn}"
ZIVPN_RANGE="${ZIVPN_RANGE:-6000:19999}"

readonly CONFIG_DIR="/etc/kobong/zivpn"
readonly BINARY="/usr/local/bin/kobong-zivpn"
readonly SERVICE_NAME="kobong-zivpn"

log()  { printf "\033[0;36m[ZIVPN]\033[0m %s\n" "$*"; }
ok()   { printf "\033[0;32m[✓]\033[0m %s\n" "$*"; }
die()  { printf "\033[0;31m[✗]\033[0m %s\n" "$*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "Must run as root"

# ── Download binary ─────────────────────────────────────────────────
log "Downloading ZIVPN UDP binary v${ZIVPN_VERSION}…"
mkdir -p "$CONFIG_DIR"
if ! curl -fsSL "$ZIVPN_BINARY_URL" -o "$BINARY"; then
    die "Failed to download ZIVPN binary"
fi
chmod +x "$BINARY"
ok "Binary installed at $BINARY"

# ── Generate self-signed cert (ZIVPN uses TLS-like handshake) ───────
if [[ ! -f "$CONFIG_DIR/zivpn.crt" ]] || [[ ! -f "$CONFIG_DIR/zivpn.key" ]]; then
    log "Generating self-signed certificate…"
    openssl req -new -newkey rsa:4096 -days 3650 -nodes -x509 \
        -subj "/CN=zivpn" \
        -keyout "$CONFIG_DIR/zivpn.key" \
        -out "$CONFIG_DIR/zivpn.crt" 2>/dev/null
    chmod 600 "$CONFIG_DIR/zivpn.key"
    ok "Certificate generated"
fi

# ── Build config.json ───────────────────────────────────────────────
log "Writing config…"
IFS=',' read -r -a _pw_array <<< "$ZIVPN_PASSWORDS"
if [[ ${#_pw_array[@]} -eq 1 ]]; then
    _pw_array+=("${_pw_array[0]}")
fi
_pw_json="["
for i in "${!_pw_array[@]}"; do
    [[ $i -gt 0 ]] && _pw_json+=","
    _pw_json+="\"${_pw_array[$i]}\""
done
_pw_json+="]"

cat > "$CONFIG_DIR/config.json" <<EOF
{
  "listen": ":${ZIVPN_PORT}",
  "cert": "${CONFIG_DIR}/zivpn.crt",
  "key": "${CONFIG_DIR}/zivpn.key",
  "obfs": "${ZIVPN_OBFS}",
  "auth": {
    "mode": "passwords",
    "config": ${_pw_json}
  }
}
EOF
chmod 600 "$CONFIG_DIR/config.json"
ok "Config written to $CONFIG_DIR/config.json"

# ── Kernel network tuning ───────────────────────────────────────────
log "Tuning kernel network buffers…"
sysctl -w net.core.rmem_max=16777216 >/dev/null
sysctl -w net.core.wmem_max=16777216 >/dev/null
cat > /etc/sysctl.d/99-kobong-zivpn.conf <<EOF
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
EOF
ok "Network buffers tuned"

# ── systemd unit ────────────────────────────────────────────────────
log "Installing systemd service…"
cat > "/etc/systemd/system/${SERVICE_NAME}.service" <<EOF
[Unit]
Description=KOBONG ZIVPN UDP Server
Documentation=https://github.com/zahidbd2/udp-zivpn
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=${CONFIG_DIR}
ExecStart=${BINARY} server -c ${CONFIG_DIR}/config.json
Restart=always
RestartSec=3
Environment=ZIVPN_LOG_LEVEL=info
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable "$SERVICE_NAME" >/dev/null 2>&1
systemctl restart "$SERVICE_NAME"

# ── Firewall: allow ZIVPN port + DNAT range ─────────────────────────
log "Configuring iptables DNAT (${ZIVPN_RANGE}/udp → ${ZIVPN_PORT})…"
IFACE="$(ip -4 route ls | awk '/^default/ {print $5; exit}')"
[[ -n "$IFACE" ]] || die "Failed to detect default network interface"

# Remove any prior rule with the same target then add
iptables -t nat -D PREROUTING -i "$IFACE" -p udp --dport "$ZIVPN_RANGE" \
    -j DNAT --to-destination ":$ZIVPN_PORT" 2>/dev/null || true
iptables -t nat -A PREROUTING -i "$IFACE" -p udp --dport "$ZIVPN_RANGE" \
    -j DNAT --to-destination ":$ZIVPN_PORT"

# Persist iptables (requires iptables-persistent)
if command -v netfilter-persistent >/dev/null 2>&1; then
    netfilter-persistent save >/dev/null 2>&1 || true
fi

# UFW rules (best-effort)
if command -v ufw >/dev/null 2>&1; then
    ufw allow "${ZIVPN_PORT}/udp" >/dev/null 2>&1 || true
    ufw allow "${ZIVPN_RANGE}/udp" >/dev/null 2>&1 || true
fi
ok "Firewall rules applied"

# ── Verify ──────────────────────────────────────────────────────────
sleep 2
if systemctl is-active --quiet "$SERVICE_NAME"; then
    ok "ZIVPN service is running on UDP :${ZIVPN_PORT}"
else
    die "ZIVPN service failed to start. Check: journalctl -u $SERVICE_NAME -n 50"
fi

printf "\n\033[0;32m✅ ZIVPN UDP installed successfully!\033[0m\n\n"
printf "  Port      : %s/udp (+ DNAT range %s)\n" "$ZIVPN_PORT" "$ZIVPN_RANGE"
printf "  Passwords : %s\n" "$ZIVPN_PASSWORDS"
printf "  Config    : %s/config.json\n" "$CONFIG_DIR"
printf "  Service   : systemctl status %s\n" "$SERVICE_NAME"
