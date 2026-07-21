#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────
#  KOBONG VPN BOT — One-shot installer (systemd, pure Python, no Docker)
#
#  Usage:
#      bash install-bot.sh                # interactive prompts
#      bash install-bot.sh --unattended   # requires env vars pre-set
#
#  What it does:
#      1. Detects Ubuntu/Debian
#      2. Installs Python 3.12 + venv + git
#      3. Creates /opt/kobong-vpn-bot venv + installs requirements
#      4. Generates FERNET_KEY
#      5. Prompts for BOT_TOKEN, ADMIN_ID, PAKASIR_SLUG, PAKASIR_API_KEY
#      6. Writes /opt/kobong-vpn-bot/.env
#      7. Creates + enables + starts systemd service
#      8. Tails log for 30s to verify boot
# ─────────────────────────────────────────────────────────────────────
set -euo pipefail

readonly INSTALL_DIR="/opt/kobong-vpn-bot"
readonly SERVICE_NAME="kobong-vpn-bot"
readonly SYSTEMD_UNIT="/etc/systemd/system/${SERVICE_NAME}.service"
readonly VENV_DIR="${INSTALL_DIR}/.venv"
readonly ENV_FILE="${INSTALL_DIR}/.env"
readonly REPO_URL="${REPO_URL:-https://github.com/tdede914-creator/Red.git}"
readonly REPO_BRANCH="${REPO_BRANCH:-feat/kobong-vpn-bot-m1}"
readonly SUBDIR="kobong-vpn-bot"

# ── Colors ──────────────────────────────────────────────────────────
C_RESET='\033[0m'
C_GREEN='\033[0;32m'
C_RED='\033[0;31m'
C_YELLOW='\033[0;33m'
C_CYAN='\033[0;36m'
C_BOLD='\033[1m'

log()   { printf "${C_CYAN}[install]${C_RESET} %s\n" "$*"; }
ok()    { printf "${C_GREEN}[✓]${C_RESET} %s\n" "$*"; }
warn()  { printf "${C_YELLOW}[!]${C_RESET} %s\n" "$*" >&2; }
die()   { printf "${C_RED}[✗]${C_RESET} %s\n" "$*" >&2; exit 1; }

# ── Pre-flight ──────────────────────────────────────────────────────
[[ $EUID -eq 0 ]] || die "Must run as root (try: sudo bash install-bot.sh)"

detect_os() {
    [[ -f /etc/os-release ]] || die "/etc/os-release not found"
    # shellcheck disable=SC1091
    . /etc/os-release
    log "Detected OS: $PRETTY_NAME"
    case "${ID:-}" in
        ubuntu|debian) ;;
        *) die "Only Ubuntu/Debian are supported (got: ${ID:-unknown})" ;;
    esac
}

install_system_deps() {
    log "Installing system dependencies (python3.12, venv, git)…"
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq

    # Try python3.12 first, fall back to python3 default
    if ! apt-get install -y -qq python3.12 python3.12-venv python3.12-dev 2>/dev/null; then
        warn "python3.12 not in default repo — using system python3"
        apt-get install -y -qq python3 python3-venv python3-dev
        PY_BIN="$(command -v python3)"
    else
        PY_BIN="$(command -v python3.12)"
    fi

    apt-get install -y -qq git curl build-essential libssl-dev libffi-dev
    ok "System deps installed. Python: $PY_BIN ($($PY_BIN --version))"
    export PY_BIN
}

# ── Fetch source ────────────────────────────────────────────────────
fetch_source() {
    # Case A: Manual upload — files already present, no .git needed
    if [[ -f "${INSTALL_DIR}/install-bot.sh" && -d "${INSTALL_DIR}/bot" ]]; then
        log "Existing installation detected at ${INSTALL_DIR}"
        log "Using pre-uploaded files (skipping git clone)"
        ok "Source ready at ${INSTALL_DIR}"
        return
    fi

    # Case B: Previous install with git history — pull latest
    if [[ -d "${INSTALL_DIR}/.git" ]]; then
        log "Existing git install detected → git pull"
        cd "${INSTALL_DIR}"
        git config --global --add safe.directory "${INSTALL_DIR}" 2>/dev/null || true
        git fetch --all --prune
        git checkout "${REPO_BRANCH}"
        git pull --ff-only origin "${REPO_BRANCH}"
        ok "Source updated to latest ${REPO_BRANCH}"
        return
    fi

    # Case C: Fresh install — need internet + GitHub access
    log "Cloning ${REPO_URL} (branch: ${REPO_BRANCH})…"
    if ! command -v git >/dev/null 2>&1; then
        die "git is not installed and no local files found at ${INSTALL_DIR}"
    fi

    rm -rf "${INSTALL_DIR}"
    local tmp
    tmp="$(mktemp -d)"
    if ! git clone --depth 1 -b "${REPO_BRANCH}" "${REPO_URL}" "${tmp}/repo" 2>&1 | tail -20; then
        rm -rf "${tmp}"
        die "git clone failed. If your VPS can't reach GitHub, upload the ZIP manually first"
    fi
    mv "${tmp}/repo/${SUBDIR}" "${INSTALL_DIR}"
    mv "${tmp}/repo/.git" "${INSTALL_DIR}/.git" 2>/dev/null || true
    rm -rf "${tmp}"
    ok "Source cloned to ${INSTALL_DIR}"
}

# ── Python virtualenv ───────────────────────────────────────────────
setup_venv() {
    log "Creating virtualenv…"
    "${PY_BIN}" -m venv "${VENV_DIR}"
    "${VENV_DIR}/bin/pip" install --quiet --upgrade pip wheel setuptools
    log "Installing Python requirements (may take 1-2 min)…"
    "${VENV_DIR}/bin/pip" install --quiet -r "${INSTALL_DIR}/requirements.txt"
    ok "Virtualenv ready at ${VENV_DIR}"
}

# ── Interactive env setup ───────────────────────────────────────────
prompt_env() {
    if [[ -f "${ENV_FILE}" ]]; then
        warn "${ENV_FILE} already exists"
        read -rp "Overwrite existing .env? [y/N]: " reply
        [[ "$reply" =~ ^[Yy]$ ]] || { log "Keeping existing .env"; return; }
    fi

    log "Setting up .env — jawab pertanyaan berikut:"
    echo

    # Bot token
    while true; do
        read -rp "$(printf "${C_BOLD}1/5${C_RESET} Bot token dari @BotFather: ")" BOT_TOKEN
        [[ "${BOT_TOKEN}" =~ ^[0-9]+:[A-Za-z0-9_-]{20,}$ ]] && break
        warn "Format token tidak valid. Contoh: 1234567890:AAH...  (dari @BotFather)"
    done

    read -rp "$(printf "${C_BOLD}2/5${C_RESET} Bot username tanpa @ [KobongVpnBot]: ")" BOT_USERNAME
    BOT_USERNAME="${BOT_USERNAME:-KobongVpnBot}"

    while true; do
        read -rp "$(printf "${C_BOLD}3/5${C_RESET} Telegram User ID admin (dari @userinfobot): ")" SUPER_ADMIN_IDS
        [[ "${SUPER_ADMIN_IDS}" =~ ^[0-9]+(,[0-9]+)*$ ]] && break
        warn "Harus berupa angka (bisa comma-separated untuk multi-admin)"
    done

    read -rp "$(printf "${C_BOLD}4/5${C_RESET} Pakasir slug [kosong=skip payment]: ")" PAKASIR_SLUG
    if [[ -n "${PAKASIR_SLUG}" ]]; then
        read -rp "$(printf "${C_BOLD}5/5${C_RESET} Pakasir API key: ")" PAKASIR_API_KEY
    else
        PAKASIR_API_KEY=""
        warn "Payment via Pakasir dinonaktifkan (bisa diaktifkan nanti dengan edit .env)"
    fi

    # Auto-generate Fernet key
    log "Generating FERNET_KEY…"
    FERNET_KEY="$(${VENV_DIR}/bin/python -c 'from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())')"
    [[ -n "${FERNET_KEY}" ]] || die "Failed to generate FERNET_KEY"

    log "Writing ${ENV_FILE}…"
    umask 077
    cat > "${ENV_FILE}" <<EOF
# Generated by install-bot.sh at $(date -Iseconds)
BOT_TOKEN=${BOT_TOKEN}
BOT_USERNAME=${BOT_USERNAME}
SUPER_ADMIN_IDS=${SUPER_ADMIN_IDS}

FERNET_KEY=${FERNET_KEY}

DATABASE_URL=sqlite+aiosqlite:///data/kobong.db

PAKASIR_SLUG=${PAKASIR_SLUG}
PAKASIR_API_KEY=${PAKASIR_API_KEY}
PAKASIR_METHOD=qris
PAKASIR_BASE_URL=https://app.pakasir.com

CURRENCY=Rp
# One-time install fee per VPS. After paying, create accounts UNLIMITED FREE.
# Super admin (you) is exempt.
DEFAULT_PRICE_INSTALL=50000
# Marketplace prices (v2, unused for now)
DEFAULT_PRICE_SSH=5000
DEFAULT_PRICE_XRAY=8000
DEFAULT_PRICE_ZIVPN=10000
DEFAULT_DURATION_DAYS=30

SSH_POOL_SIZE=10
LOG_LEVEL=INFO
EOF
    chmod 600 "${ENV_FILE}"
    # CRITICAL: .env is created by root, but the bot runs as 'kobong' user.
    # Without this chown the bot fails with PermissionError reading .env.
    if id -u kobong >/dev/null 2>&1; then
        chown kobong:kobong "${ENV_FILE}"
    fi
    ok ".env written (permissions: 600, owner: kobong)"
}

# ── Create dedicated system user ────────────────────────────────────
create_user() {
    if ! id -u kobong >/dev/null 2>&1; then
        log "Creating system user 'kobong'…"
        useradd --system --home "${INSTALL_DIR}" --shell /bin/bash --no-create-home kobong
    fi
    mkdir -p "${INSTALL_DIR}/data" "${INSTALL_DIR}/logs"
    chown -R kobong:kobong "${INSTALL_DIR}"
    chmod 700 "${INSTALL_DIR}/data"
    ok "User + data directories ready"
}

# ── Final ownership sweep ───────────────────────────────────────────
# Called right before starting the service. Catches anything created
# after create_user() ran (e.g. .env, git-pull artifacts).
final_chown() {
    log "Final ownership sweep on ${INSTALL_DIR}…"
    chown -R kobong:kobong "${INSTALL_DIR}"
    chmod 600 "${ENV_FILE}" 2>/dev/null || true
    chmod 700 "${INSTALL_DIR}/data" 2>/dev/null || true
    ok "Ownership fixed"
}

# ── systemd unit ────────────────────────────────────────────────────
install_systemd_unit() {
    log "Installing systemd unit ${SYSTEMD_UNIT}…"
    cat > "${SYSTEMD_UNIT}" <<EOF
[Unit]
Description=KOBONG VPN BOT
Documentation=https://github.com/tdede914-creator/Red/tree/${REPO_BRANCH}/${SUBDIR}
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=kobong
Group=kobong
WorkingDirectory=${INSTALL_DIR}
Environment=PYTHONUNBUFFERED=1
EnvironmentFile=${ENV_FILE}
ExecStart=${VENV_DIR}/bin/python -m bot
Restart=always
RestartSec=5
# Log to BOTH journal (for journalctl) AND file (for tail -f).
# journal-first so debugging is trivial: journalctl -u kobong-vpn-bot -f
StandardOutput=journal
StandardError=journal
SyslogIdentifier=kobong-vpn-bot

# Security hardening
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true
ReadWritePaths=${INSTALL_DIR}/data ${INSTALL_DIR}/logs
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF
    chmod 644 "${SYSTEMD_UNIT}"
    systemctl daemon-reload
    ok "systemd unit installed"
}

# ── Start service + verify ──────────────────────────────────────────
start_service() {
    log "Enabling + starting ${SERVICE_NAME}…"
    systemctl enable "${SERVICE_NAME}" >/dev/null 2>&1
    systemctl restart "${SERVICE_NAME}"
    sleep 4

    if systemctl is-active --quiet "${SERVICE_NAME}"; then
        ok "Service is running"
    else
        warn "Service failed to start. Recent log (last 40 lines):"
        echo "─────────────────────────────────────────────────────────"
        journalctl -u "${SERVICE_NAME}" -n 40 --no-pager --no-hostname 2>/dev/null || \
            tail -n 40 "${INSTALL_DIR}/logs/bot.log" 2>/dev/null || \
            echo "(no logs available)"
        echo "─────────────────────────────────────────────────────────"
        die "Please fix the error above and run: systemctl restart ${SERVICE_NAME}"
    fi
}

# ── Summary ─────────────────────────────────────────────────────────
print_summary() {
    printf "\n${C_GREEN}${C_BOLD}✅ KOBONG VPN BOT terinstall!${C_RESET}\n\n"
    printf "  Install dir : %s\n" "${INSTALL_DIR}"
    printf "  Service     : %s\n" "${SERVICE_NAME}"
    printf "  Env file    : %s\n" "${ENV_FILE}"
    printf "  Log file    : %s\n" "${INSTALL_DIR}/logs/bot.log"
    printf "\n${C_BOLD}Perintah berguna:${C_RESET}\n"
    printf "  Cek status  : systemctl status %s\n" "${SERVICE_NAME}"
    printf "  Lihat log   : journalctl -u %s -f\n" "${SERVICE_NAME}"
    printf "  Restart     : systemctl restart %s\n" "${SERVICE_NAME}"
    printf "  Update SC   : cd %s && git pull && systemctl restart %s\n" "${INSTALL_DIR}" "${SERVICE_NAME}"
    printf "  Uninstall   : bash %s/uninstall-bot.sh\n" "${INSTALL_DIR}"
    printf "\n${C_BOLD}Selanjutnya:${C_RESET}\n"
    printf "  1. Chat bot kamu di Telegram → /start\n"
    printf "  2. Harusnya muncul banner KOBONG + menu inline\n"
    printf "  3. Klik ➕ Tambah VPS untuk daftarin VPS target pertama\n\n"
}

# ── Main ────────────────────────────────────────────────────────────
main() {
    printf "${C_BOLD}${C_GREEN}"
    cat <<'EOF'
  ██╗  ██╗ ██████╗ ██████╗  ██████╗ ███╗   ██╗ ██████╗
  ██║ ██╔╝██╔═══██╗██╔══██╗██╔═══██╗████╗  ██║██╔════╝
  █████╔╝ ██║   ██║██████╔╝██║   ██║██╔██╗ ██║██║  ███╗
  ██╔═██╗ ██║   ██║██╔══██╗██║   ██║██║╚██╗██║██║   ██║
  ██║  ██╗╚██████╔╝██████╔╝╚██████╔╝██║ ╚████║╚██████╔╝
  ╚═╝  ╚═╝ ╚═════╝ ╚═════╝  ╚═════╝ ╚═╝  ╚═══╝ ╚═════╝
             V P N   B O T   -   I N S T A L L E R
EOF
    printf "${C_RESET}\n"

    detect_os
    install_system_deps
    fetch_source
    setup_venv
    create_user
    prompt_env
    install_systemd_unit
    final_chown
    start_service
    print_summary
}

main "$@"
