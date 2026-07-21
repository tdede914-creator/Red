#!/usr/bin/env bash
# Uninstall KOBONG VPN BOT (bot side — not target VPS)
set -euo pipefail

readonly INSTALL_DIR="/opt/kobong-vpn-bot"
readonly SERVICE_NAME="kobong-vpn-bot"

[[ $EUID -eq 0 ]] || { echo "Must run as root"; exit 1; }

echo "This will stop and remove KOBONG VPN BOT."
read -rp "Keep data (accounts, orders)? [Y/n]: " keep
KEEP_DATA="${keep:-Y}"

systemctl stop "${SERVICE_NAME}" 2>/dev/null || true
systemctl disable "${SERVICE_NAME}" 2>/dev/null || true
rm -f "/etc/systemd/system/${SERVICE_NAME}.service"
systemctl daemon-reload

if [[ "${KEEP_DATA}" =~ ^[Yy]$ ]]; then
    if [[ -d "${INSTALL_DIR}/data" ]]; then
        BACKUP="${INSTALL_DIR}-data-backup-$(date +%Y%m%d-%H%M%S).tar.gz"
        tar czf "${BACKUP}" -C "${INSTALL_DIR}" data .env 2>/dev/null || true
        echo "Data backed up to: ${BACKUP}"
    fi
fi

rm -rf "${INSTALL_DIR}"
userdel kobong 2>/dev/null || true

echo "✅ KOBONG VPN BOT removed."
