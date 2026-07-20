#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────
#  KOBONG VPN BOT — Uninstaller
#  Removes only what KOBONG installed. Safe to run on shared VPS.
# ─────────────────────────────────────────────────────────────────────
set -euo pipefail

readonly CONFIG_DIR="/etc/kobong"
readonly BIN_DIR="/usr/local/sbin"

log() { printf "\033[0;33m[uninstall]\033[0m %s\n" "$*"; }
ok()  { printf "\033[0;32m[✓]\033[0m %s\n" "$*"; }

[[ $EUID -eq 0 ]] || { echo "Must run as root"; exit 1; }

log "Stopping and disabling KOBONG services…"
for svc in kobong-zivpn xray dropbear; do
    systemctl stop "$svc" 2>/dev/null || true
    systemctl disable "$svc" 2>/dev/null || true
done

log "Removing KOBONG systemd units…"
rm -f /etc/systemd/system/kobong-*.service
systemctl daemon-reload

log "Removing KOBONG binaries…"
rm -f /usr/local/bin/kobong-*

log "Removing KOBONG config directory…"
rm -rf "$CONFIG_DIR"

log "Removing sysctl override…"
rm -f /etc/sysctl.d/99-kobong-zivpn.conf

# Note: We deliberately do NOT purge xray/dropbear packages themselves,
# since the user might use them for other things. Remove manually if needed:
#   apt purge -y xray dropbear

ok "KOBONG components removed. System packages left intact."
