#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────
#  KOBONG VPN BOT — Main installer (M1 skeleton)
#  Installs a fresh multi-protocol VPN stack on Ubuntu 20/22/24 or
#  Debian 10/11/12. Called by the Telegram bot via SSH.
#
#  Idempotent: safe to re-run.
#  Non-interactive: reads config from CLI flags or /etc/kobong/install.env
#
#  Author  : KOBONG
#  License : MIT
# ─────────────────────────────────────────────────────────────────────
set -euo pipefail

readonly VERSION="0.1.0"
readonly BRAND="KOBONG VPN BOT"
readonly LOG_FILE="/var/log/kobong-install.log"
readonly CONFIG_DIR="/etc/kobong"
readonly BIN_DIR="/usr/local/sbin"

# ── Colors ──────────────────────────────────────────────────────────
readonly C_RESET='\033[0m'
readonly C_GREEN='\033[0;32m'
readonly C_RED='\033[0;31m'
readonly C_YELLOW='\033[0;33m'
readonly C_BLUE='\033[0;36m'
readonly C_BOLD='\033[1m'

# ── Defaults (overridable via env) ──────────────────────────────────
DOMAIN="${DOMAIN:-}"
INSTALL_MODE="${INSTALL_MODE:-full}"   # full | xray | ssh | custom
INSTALL_ZIVPN="${INSTALL_ZIVPN:-yes}"
ZIVPN_PASSWORDS="${ZIVPN_PASSWORDS:-zi}"   # comma-separated
ZIVPN_PORT="${ZIVPN_PORT:-5667}"
BOT_CALLBACK_URL="${BOT_CALLBACK_URL:-}"   # optional: POST progress here
BOT_CALLBACK_TOKEN="${BOT_CALLBACK_TOKEN:-}"

# ── Logging helpers ─────────────────────────────────────────────────
mkdir -p "$(dirname "$LOG_FILE")"
exec > >(tee -a "$LOG_FILE") 2>&1

log()  { printf "${C_BLUE}[%s]${C_RESET} %s\n" "$(date +%H:%M:%S)" "$*"; }
ok()   { printf "${C_GREEN}[✓]${C_RESET} %s\n" "$*"; }
warn() { printf "${C_YELLOW}[!]${C_RESET} %s\n" "$*" >&2; }
err()  { printf "${C_RED}[✗]${C_RESET} %s\n" "$*" >&2; }
die()  { err "$*"; exit 1; }

# ── Callback to bot (best-effort, never fatal) ──────────────────────
callback() {
    local stage="$1" status="$2" pct="${3:-0}"
    [[ -z "$BOT_CALLBACK_URL" ]] && return 0
    curl -sf --max-time 5 -X POST "$BOT_CALLBACK_URL" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer ${BOT_CALLBACK_TOKEN}" \
        -d "{\"stage\":\"$stage\",\"status\":\"$status\",\"pct\":$pct}" \
        >/dev/null 2>&1 || true
}

# ── Pre-flight ──────────────────────────────────────────────────────
require_root() {
    [[ $EUID -eq 0 ]] || die "Must run as root"
}

detect_os() {
    [[ -f /etc/os-release ]] || die "/etc/os-release not found"
    # shellcheck disable=SC1091
    . /etc/os-release
    local id="${ID:-unknown}"
    local ver="${VERSION_ID:-0}"
    log "OS: $PRETTY_NAME"
    case "$id" in
        ubuntu)
            [[ ${ver%%.*} -ge 20 ]] || die "Ubuntu 20.04+ required (found $ver)"
            ;;
        debian)
            [[ ${ver%%.*} -ge 10 ]] || die "Debian 10+ required (found $ver)"
            ;;
        *)
            die "Unsupported OS: $id"
            ;;
    esac
    export OS_ID="$id"
    export OS_VER="$ver"
}

check_arch() {
    local arch
    arch="$(uname -m)"
    [[ "$arch" == "x86_64" ]] || die "Unsupported architecture: $arch (need x86_64)"
    log "Architecture: $arch"
}

check_virt() {
    local virt
    virt="$(systemd-detect-virt 2>/dev/null || echo unknown)"
    [[ "$virt" == "openvz" ]] && die "OpenVZ is not supported"
    log "Virtualization: $virt"
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
    log "Installing base packages…"
    callback "base_packages" "running" 10
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y -qq --no-install-recommends \
        curl wget git jq unzip zip \
        ca-certificates gnupg lsb-release \
        openssl socat cron \
        net-tools iproute2 iptables iptables-persistent \
        dnsutils vnstat chrony \
        build-essential \
        python3 python3-pip
    ok "Base packages installed"
    callback "base_packages" "done" 20
}

setup_dirs() {
    log "Setting up config directories…"
    mkdir -p "$CONFIG_DIR" "$BIN_DIR"
    mkdir -p /etc/kobong/{xray,ssh,zivpn,ssl}
    mkdir -p /var/log/kobong
    ok "Directories ready"
}

# ── Timezone ────────────────────────────────────────────────────────
setup_timezone() {
    timedatectl set-timezone Asia/Jakarta 2>/dev/null || warn "Failed to set timezone"
    log "Timezone: $(date +'%Z %z')"
}

# ── Domain (custom or random) ───────────────────────────────────────
setup_domain() {
    if [[ -z "$DOMAIN" ]]; then
        # Random subdomain — placeholder, real impl fetched from bot in M2
        DOMAIN="kobong-$(openssl rand -hex 3).sslip.io"
        log "No domain provided — using sslip.io fallback: $DOMAIN"
    fi
    echo "$DOMAIN" > "$CONFIG_DIR/domain"
    ok "Domain: $DOMAIN"
}

# ── SSL via acme.sh ─────────────────────────────────────────────────
install_ssl() {
    log "Installing SSL certificate for $DOMAIN…"
    callback "ssl" "running" 30
    if ! command -v ~/.acme.sh/acme.sh >/dev/null 2>&1; then
        curl -fsSL https://get.acme.sh | sh -s email="admin@$DOMAIN"
    fi
    # shellcheck disable=SC1090
    export PATH="$HOME/.acme.sh:$PATH"

    # Stop anything on port 80
    systemctl stop nginx 2>/dev/null || true

    if ~/.acme.sh/acme.sh --issue -d "$DOMAIN" --standalone -k ec-256 \
        --server letsencrypt --force; then
        ~/.acme.sh/acme.sh --installcert -d "$DOMAIN" \
            --fullchainpath "$CONFIG_DIR/ssl/fullchain.pem" \
            --keypath "$CONFIG_DIR/ssl/privkey.pem" \
            --ecc
        chmod 644 "$CONFIG_DIR/ssl/"*.pem
        ok "SSL certificate issued"
    else
        warn "SSL issuance failed — continuing with self-signed"
        openssl req -x509 -newkey rsa:4096 -sha256 -days 365 -nodes \
            -keyout "$CONFIG_DIR/ssl/privkey.pem" \
            -out "$CONFIG_DIR/ssl/fullchain.pem" \
            -subj "/CN=$DOMAIN"
    fi
    callback "ssl" "done" 40
}

# ── Xray (VMess / VLESS / Trojan / Shadowsocks) ─────────────────────
install_xray() {
    log "Installing Xray core…"
    callback "xray" "running" 50
    bash -c "$(curl -fsSL https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" \
        @ install --without-geodata >/dev/null
    systemctl enable --now xray >/dev/null 2>&1 || warn "Xray systemd enable failed"
    ok "Xray installed ($(xray version 2>/dev/null | head -1 || echo 'version unknown'))"
    callback "xray" "done" 60
}

# ── SSH hardening + Dropbear ────────────────────────────────────────
install_ssh_stack() {
    log "Installing SSH + Dropbear…"
    callback "ssh" "running" 70
    apt-get install -y -qq dropbear
    # Enable dropbear on port 143 and 109 (common bypass ports)
    if [[ -f /etc/default/dropbear ]]; then
        sed -i 's/^NO_START=.*/NO_START=0/' /etc/default/dropbear
        sed -i 's/^DROPBEAR_PORT=.*/DROPBEAR_PORT=143/' /etc/default/dropbear
        sed -i 's/^DROPBEAR_EXTRA_ARGS=.*/DROPBEAR_EXTRA_ARGS="-p 109"/' /etc/default/dropbear
    fi
    systemctl restart dropbear
    ok "SSH + Dropbear ready"
    callback "ssh" "done" 80
}

# ── ZIVPN (UDP tunnel) ──────────────────────────────────────────────
install_zivpn_stack() {
    [[ "$INSTALL_ZIVPN" == "yes" ]] || return 0
    log "Installing ZIVPN UDP…"
    callback "zivpn" "running" 85
    bash "$(dirname "$0")/install_zivpn.sh" || die "ZIVPN installation failed"
    ok "ZIVPN installed on UDP port $ZIVPN_PORT"
    callback "zivpn" "done" 95
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
    "xray": true,
    "ssh": true,
    "dropbear": true,
    "zivpn": $( [[ "$INSTALL_ZIVPN" == "yes" ]] && echo true || echo false )
  }
}
EOF
    ok "Install manifest saved to $CONFIG_DIR/install.json"
    callback "install" "completed" 100
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
    check_virt
    check_ip

    setup_dirs
    setup_timezone
    setup_domain
    install_base

    case "$INSTALL_MODE" in
        full)
            install_ssh_stack
            install_ssl
            install_xray
            install_zivpn_stack
            ;;
        xray)
            install_ssl
            install_xray
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
