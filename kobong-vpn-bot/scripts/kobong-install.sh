#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────
#  KOBONG VPN BOT — Main installer
#
#  Installs a fresh multi-protocol VPN stack on Ubuntu 20/22/24 or
#  Debian 10/11/12. Called by the Telegram bot via SSH.
#
#  Idempotent: safe to re-run.
#  Non-interactive: reads config from env vars.
#
#  Author  : KOBONG
#  License : MIT
# ─────────────────────────────────────────────────────────────────────
set -euo pipefail

readonly VERSION="0.2.0"
readonly BRAND="KOBONG VPN BOT"
readonly LOG_FILE="/var/log/kobong-install.log"
readonly CONFIG_DIR="/etc/kobong"
readonly BIN_DIR="/usr/local/sbin"
readonly XRAY_CONFIG="/etc/xray/config.json"

# ── Colors ──────────────────────────────────────────────────────────
C_RESET='\033[0m'
C_GREEN='\033[0;32m'
C_RED='\033[0;31m'
C_YELLOW='\033[0;33m'
C_BLUE='\033[0;36m'
C_BOLD='\033[1m'

# ── Defaults (overridable via env) ──────────────────────────────────
DOMAIN="${DOMAIN:-}"
INSTALL_MODE="${INSTALL_MODE:-full}"       # full | xray | ssh | zivpn
INSTALL_ZIVPN="${INSTALL_ZIVPN:-yes}"
ZIVPN_PASSWORDS="${ZIVPN_PASSWORDS:-zi}"   # comma-separated
ZIVPN_PORT="${ZIVPN_PORT:-5667}"

# ── Logging ─────────────────────────────────────────────────────────
mkdir -p "$(dirname "$LOG_FILE")"
exec > >(tee -a "$LOG_FILE") 2>&1

log()  { printf "${C_BLUE}[%s]${C_RESET} %s\n" "$(date +%H:%M:%S)" "$*"; }
ok()   { printf "${C_GREEN}[✓]${C_RESET} %s\n" "$*"; }
warn() { printf "${C_YELLOW}[!]${C_RESET} %s\n" "$*" >&2; }
err()  { printf "${C_RED}[✗]${C_RESET} %s\n" "$*" >&2; }
die()  { err "$*"; exit 1; }

# ── Pre-flight ──────────────────────────────────────────────────────
require_root() {
    [[ $EUID -eq 0 ]] || die "Must run as root"
}

detect_os() {
    [[ -f /etc/os-release ]] || die "/etc/os-release not found"
    # shellcheck disable=SC1091
    . /etc/os-release
    log "OS: $PRETTY_NAME"
    case "${ID:-}" in
        ubuntu) [[ ${VERSION_ID%%.*} -ge 20 ]] || die "Ubuntu 20.04+ required" ;;
        debian) [[ ${VERSION_ID%%.*} -ge 10 ]] || die "Debian 10+ required" ;;
        *) die "Unsupported OS: ${ID:-unknown}" ;;
    esac
    export OS_ID="${ID}" OS_VER="${VERSION_ID}"
}

check_arch() {
    local arch
    arch="$(uname -m)"
    [[ "$arch" == "x86_64" ]] || die "Unsupported architecture: $arch"
    log "Architecture: $arch"
}

check_ip() {
    local ip
    ip="$(curl -fsS --max-time 5 https://api.ipify.org || echo '')"
    [[ -n "$ip" ]] || die "Failed to detect public IP"
    export PUBLIC_IP="$ip"
    log "Public IP: $ip"
}

# ── Base packages ───────────────────────────────────────────────────
install_base() {
    log "MENJALANKAN base_packages"
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y -qq --no-install-recommends \
        curl wget git jq unzip zip \
        ca-certificates gnupg lsb-release \
        openssl socat cron \
        net-tools iproute2 iptables iptables-persistent \
        dnsutils \
        build-essential \
        python3 python3-pip \
        uuid-runtime
    ok "base_packages done"
}

setup_dirs() {
    log "Setting up directories…"
    mkdir -p "$CONFIG_DIR" "$BIN_DIR"
    mkdir -p /etc/kobong/{xray,ssh,zivpn,ssl}
    mkdir -p /var/log/kobong
    mkdir -p /etc/xray
    ok "Directories ready"
}

setup_timezone() {
    timedatectl set-timezone Asia/Jakarta 2>/dev/null || warn "Failed to set TZ"
    log "Timezone: $(date +'%Z %z')"
}

setup_domain() {
    if [[ -z "$DOMAIN" ]]; then
        # Use sslip.io fallback: <ip>.sslip.io resolves to your IP automatically
        # Format: 1-2-3-4.sslip.io
        local sanitized_ip="${PUBLIC_IP//./-}"
        DOMAIN="${sanitized_ip}.sslip.io"
        log "No domain provided → using sslip.io fallback: $DOMAIN"
    fi
    echo "$DOMAIN" > "$CONFIG_DIR/domain"
    ok "Domain: $DOMAIN"
}

# ── SSL certificate ─────────────────────────────────────────────────
install_ssl() {
    log "MENJALANKAN ssl for $DOMAIN"

    # Install acme.sh if not present
    if [[ ! -x /root/.acme.sh/acme.sh ]]; then
        curl -fsSL https://get.acme.sh | sh -s email="admin@${DOMAIN}" >/dev/null 2>&1 || \
            warn "acme.sh install failed, will use self-signed"
    fi

    # Free up port 80
    systemctl stop nginx haproxy 2>/dev/null || true

    if [[ -x /root/.acme.sh/acme.sh ]] && \
       /root/.acme.sh/acme.sh --set-default-ca --server letsencrypt >/dev/null 2>&1 && \
       /root/.acme.sh/acme.sh --issue -d "$DOMAIN" --standalone -k ec-256 --force >/dev/null 2>&1
    then
        /root/.acme.sh/acme.sh --installcert -d "$DOMAIN" \
            --fullchainpath "$CONFIG_DIR/ssl/fullchain.pem" \
            --keypath "$CONFIG_DIR/ssl/privkey.pem" \
            --ecc >/dev/null 2>&1
        ok "SSL certificate issued from Let's Encrypt"
    else
        warn "Let's Encrypt failed — using self-signed"
        openssl req -x509 -newkey rsa:4096 -sha256 -days 365 -nodes \
            -keyout "$CONFIG_DIR/ssl/privkey.pem" \
            -out "$CONFIG_DIR/ssl/fullchain.pem" \
            -subj "/CN=${DOMAIN}" 2>/dev/null
    fi
    chmod 644 "$CONFIG_DIR/ssl/"*.pem
    log "ssl done"
}

# ── SSH + Dropbear ──────────────────────────────────────────────────
install_ssh_stack() {
    log "MENJALANKAN ssh"

    # Install dropbear
    apt-get install -y -qq dropbear

    # Configure dropbear on port 143 + 109
    cat > /etc/default/dropbear <<'EOF'
NO_START=0
DROPBEAR_PORT=143
DROPBEAR_EXTRA_ARGS="-p 109"
DROPBEAR_BANNER=""
DROPBEAR_RECEIVE_WINDOW=65536
EOF
    systemctl enable dropbear >/dev/null 2>&1
    systemctl restart dropbear

    # Create kobong-ssh group for tracking accounts we manage
    getent group kobong-ssh >/dev/null 2>&1 || groupadd --system kobong-ssh

    # Add legit user shells so /bin/false gets accepted for tunneling
    grep -qx "/bin/false" /etc/shells || echo "/bin/false" >> /etc/shells
    grep -qx "/usr/sbin/nologin" /etc/shells || echo "/usr/sbin/nologin" >> /etc/shells

    # SSH server allow password auth (needed for tunnel users)
    sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
    sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
    systemctl restart ssh 2>/dev/null || systemctl restart sshd

    ok "ssh done (SSH 22, Dropbear 143 + 109)"
}

# ── Xray core ───────────────────────────────────────────────────────
install_xray_core() {
    log "MENJALANKAN xray"

    # Official Xray install script (installs to /usr/local/bin/xray)
    bash -c "$(curl -fsSL https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" \
        @ install --without-geodata >/dev/null 2>&1 || \
        die "Xray install script failed"

    # Base config — VMess (WS 80), VLESS (WS 8080), Trojan (WS 8443), Shadowsocks (WS 8443)
    # No user inbound initially — bot adds them as needed
    cat > "$XRAY_CONFIG" <<EOF
{
  "log": {
    "loglevel": "warning",
    "access": "/var/log/xray/access.log",
    "error": "/var/log/xray/error.log"
  },
  "inbounds": [
    {
      "tag": "vmess-ws",
      "port": 8080,
      "protocol": "vmess",
      "settings": { "clients": [] },
      "streamSettings": {
        "network": "ws",
        "wsSettings": { "path": "/vmess" }
      }
    },
    {
      "tag": "vless-ws",
      "port": 8880,
      "protocol": "vless",
      "settings": { "clients": [], "decryption": "none" },
      "streamSettings": {
        "network": "ws",
        "wsSettings": { "path": "/vless" }
      }
    },
    {
      "tag": "trojan-ws",
      "port": 2082,
      "protocol": "trojan",
      "settings": { "clients": [] },
      "streamSettings": {
        "network": "ws",
        "wsSettings": { "path": "/trojan" }
      }
    }
  ],
  "outbounds": [
    { "protocol": "freedom", "tag": "direct" },
    { "protocol": "blackhole", "tag": "block" }
  ]
}
EOF
    mkdir -p /var/log/xray
    chown www-data:www-data /var/log/xray 2>/dev/null || true

    systemctl enable xray >/dev/null 2>&1
    systemctl restart xray

    if systemctl is-active --quiet xray; then
        ok "xray done ($(xray version 2>/dev/null | head -1))"
    else
        err "xray service failed to start"
        journalctl -u xray -n 20 --no-pager || true
        die "Xray installation failed"
    fi
}

# ── ZIVPN (calls the separate script) ───────────────────────────────
install_zivpn_stack() {
    [[ "$INSTALL_ZIVPN" == "yes" ]] || return 0
    log "MENJALANKAN zivpn"

    local zivpn_script="$(dirname "$0")/install_zivpn.sh"
    [[ -f "$zivpn_script" ]] || die "install_zivpn.sh not found next to this script"

    ZIVPN_PORT="$ZIVPN_PORT" ZIVPN_PASSWORDS="$ZIVPN_PASSWORDS" \
        bash "$zivpn_script" || die "ZIVPN installation failed"

    ok "zivpn done (UDP :${ZIVPN_PORT})"
}

# ── Finalize ────────────────────────────────────────────────────────
finalize() {
    log "Finalizing…"
    cat > "$CONFIG_DIR/install.json" <<EOF
{
  "version": "$VERSION",
  "brand": "$BRAND",
  "installed_at": "$(date -Iseconds)",
  "domain": "$DOMAIN",
  "public_ip": "$PUBLIC_IP",
  "mode": "$INSTALL_MODE",
  "protocols": {
    "xray": $([[ "$INSTALL_MODE" != "ssh" && "$INSTALL_MODE" != "zivpn" ]] && echo true || echo false),
    "ssh": $([[ "$INSTALL_MODE" != "zivpn" ]] && echo true || echo false),
    "dropbear": $([[ "$INSTALL_MODE" != "zivpn" ]] && echo true || echo false),
    "zivpn": $([[ "$INSTALL_ZIVPN" == "yes" ]] && echo true || echo false)
  }
}
EOF
    ok "Manifest saved to $CONFIG_DIR/install.json"
}

# ── Main ────────────────────────────────────────────────────────────
main() {
    printf "${C_BOLD}${C_GREEN}"
    cat <<'BANNER'
  ██╗  ██╗ ██████╗ ██████╗  ██████╗ ███╗   ██╗ ██████╗
  ██║ ██╔╝██╔═══██╗██╔══██╗██╔═══██╗████╗  ██║██╔════╝
  █████╔╝ ██║   ██║██████╔╝██║   ██║██╔██╗ ██║██║  ███╗
  ██╔═██╗ ██║   ██║██╔══██╗██║   ██║██║╚██╗██║██║   ██║
  ██║  ██╗╚██████╔╝██████╔╝╚██████╔╝██║ ╚████║╚██████╔╝
  ╚═╝  ╚═╝ ╚═════╝ ╚═════╝  ╚═════╝ ╚═╝  ╚═══╝ ╚═════╝
                V P N   B O T   I N S T A L L E R
BANNER
    printf "${C_RESET}"
    printf "  Version: %s  •  Mode: %s\n\n" "$VERSION" "$INSTALL_MODE"

    require_root
    detect_os
    check_arch
    check_ip

    setup_dirs
    setup_timezone
    setup_domain
    install_base

    case "$INSTALL_MODE" in
        full)
            install_ssh_stack
            install_ssl
            install_xray_core
            install_zivpn_stack
            ;;
        xray)
            install_ssl
            install_xray_core
            ;;
        ssh)
            install_ssh_stack
            ;;
        zivpn)
            install_zivpn_stack
            ;;
        *)
            die "Unknown INSTALL_MODE: $INSTALL_MODE"
            ;;
    esac

    finalize

    printf "\n${C_GREEN}${C_BOLD}✅ Installation completed!${C_RESET}\n\n"
    printf "Domain    : %s\n" "$DOMAIN"
    printf "Public IP : %s\n" "$PUBLIC_IP"
    printf "Log file  : %s\n\n" "$LOG_FILE"
}

main "$@"
