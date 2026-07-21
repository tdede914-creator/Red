#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────
#  KOBONG VPN BOT — Diagnostic script
#  Prints everything you need to debug a failed service in one shot.
#  Usage: sudo bash /opt/kobong-vpn-bot/diagnose.sh
# ─────────────────────────────────────────────────────────────────────
set -u

readonly INSTALL_DIR="/opt/kobong-vpn-bot"
readonly SERVICE_NAME="kobong-vpn-bot"
readonly ENV_FILE="${INSTALL_DIR}/.env"

C_RESET='\033[0m'
C_GREEN='\033[0;32m'
C_RED='\033[0;31m'
C_YELLOW='\033[0;33m'
C_CYAN='\033[0;36m'
C_BOLD='\033[1m'

section() { printf "\n${C_BOLD}${C_CYAN}▶ %s${C_RESET}\n" "$*"; }
ok()      { printf "  ${C_GREEN}✓${C_RESET} %s\n" "$*"; }
warn()    { printf "  ${C_YELLOW}!${C_RESET} %s\n" "$*"; }
fail()    { printf "  ${C_RED}✗${C_RESET} %s\n" "$*"; }

[[ $EUID -eq 0 ]] || { echo "Run as root: sudo bash $0"; exit 1; }

# ── 1. Filesystem ──────────────────────────────────────────────────
section "File system"
if [[ -d "${INSTALL_DIR}" ]]; then
    ok "Install dir exists: ${INSTALL_DIR}"
    ls -ld "${INSTALL_DIR}" | awk '{printf "    owner: %s:%s  perms: %s\n", $3, $4, $1}'
else
    fail "Install dir missing: ${INSTALL_DIR}"
    exit 1
fi

for f in "${ENV_FILE}" "${INSTALL_DIR}/.venv/bin/python" "${INSTALL_DIR}/bot/__main__.py"; do
    if [[ -e "$f" ]]; then
        ls -ld "$f" | awk -v fn="$f" '{printf "    ✓ %-45s owner: %s:%s  perms: %s\n", fn, $3, $4, $1}'
    else
        fail "MISSING: $f"
    fi
done

# ── 2. Systemd user ────────────────────────────────────────────────
section "Service user"
if id -u kobong >/dev/null 2>&1; then
    ok "User 'kobong' exists (uid $(id -u kobong))"
    # Verify kobong can read .env
    if sudo -u kobong test -r "${ENV_FILE}" 2>/dev/null; then
        ok "'kobong' can read .env"
    else
        fail "'kobong' CANNOT read .env → chown kobong:kobong ${ENV_FILE}"
    fi
else
    fail "User 'kobong' does not exist"
fi

# ── 3. Service state ───────────────────────────────────────────────
section "systemd service"
if [[ -f "/etc/systemd/system/${SERVICE_NAME}.service" ]]; then
    ok "Unit file exists"
else
    fail "Unit file missing"
fi
systemctl is-enabled "${SERVICE_NAME}" >/dev/null 2>&1 \
    && ok "Service is enabled" \
    || warn "Service is not enabled"
if systemctl is-active --quiet "${SERVICE_NAME}"; then
    ok "Service is RUNNING"
else
    fail "Service NOT running"
fi

# ── 4. .env sanity ─────────────────────────────────────────────────
section ".env sanity"
if [[ -r "${ENV_FILE}" ]] || sudo -u kobong test -r "${ENV_FILE}" 2>/dev/null; then
    for key in BOT_TOKEN BOT_USERNAME SUPER_ADMIN_IDS FERNET_KEY; do
        val=$(grep "^${key}=" "${ENV_FILE}" | head -1 | cut -d= -f2-)
        if [[ -n "$val" ]]; then
            ok "${key} is set (len=${#val})"
        else
            fail "${key} is EMPTY or missing"
        fi
    done
    if grep -q "^FERNET_KEY=CHANGE_ME" "${ENV_FILE}"; then
        fail "FERNET_KEY is still the placeholder!"
    fi
fi

# ── 5. Python & dependencies ───────────────────────────────────────
section "Python environment"
if [[ -x "${INSTALL_DIR}/.venv/bin/python" ]]; then
    PY_VER=$("${INSTALL_DIR}/.venv/bin/python" --version 2>&1)
    ok "Venv Python: ${PY_VER}"
    "${INSTALL_DIR}/.venv/bin/python" -c "
import sys
missing = []
for mod in ('telegram', 'sqlalchemy', 'pydantic', 'pydantic_settings', 'asyncssh', 'httpx', 'cryptography'):
    try: __import__(mod)
    except ImportError: missing.append(mod)
if missing:
    print(f'    ✗ Missing modules: {missing}')
    sys.exit(1)
print('    ✓ All required Python modules importable')
"
else
    fail "Venv missing at ${INSTALL_DIR}/.venv/"
fi

# ── 6. Recent errors ───────────────────────────────────────────────
section "Recent errors (last 40 lines from journal)"
journalctl -u "${SERVICE_NAME}" -n 40 --no-pager --no-hostname 2>/dev/null | \
    grep -E "(ERROR|CRITICAL|Traceback|Error|Exception|FAILED)" | tail -15 || \
    warn "No errors in journal"

# ── 7. Full recent journal ─────────────────────────────────────────
section "Full recent journal (last 20 lines)"
journalctl -u "${SERVICE_NAME}" -n 20 --no-pager --no-hostname 2>/dev/null || \
    tail -20 "${INSTALL_DIR}/logs/bot.log" 2>/dev/null

echo
printf "${C_BOLD}Suggested fixes:${C_RESET}\n"
printf "  1. Fix ownership : sudo chown -R kobong:kobong %s\n" "${INSTALL_DIR}"
printf "  2. Restart       : sudo systemctl restart %s\n" "${SERVICE_NAME}"
printf "  3. Watch logs    : sudo journalctl -u %s -f\n" "${SERVICE_NAME}"
echo
