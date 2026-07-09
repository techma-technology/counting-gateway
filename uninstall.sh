#!/usr/bin/env bash
# =============================================================================
# Techma Gateway — uninstaller (Armbian / Debian, systemd).
#
#   curl -fsSL https://raw.githubusercontent.com/techma-technology/counting-gateway/main/uninstall.sh | sudo bash
#
# Removes the systemd service + the install directory. Add --keep-data to keep
# the device config/state (device key, cameras) for a later reinstall:
#   ... | sudo bash -s -- --keep-data
# =============================================================================
set -euo pipefail

INSTALL_ROOT="${INSTALL_ROOT:-/opt/techma-gateway}"
SERVICE="techma-gateway"

echo "== Techma Gateway uninstaller =="
[ "$(id -u)" -eq 0 ] || { echo "Jalankan sebagai root (sudo)."; exit 1; }

KEEP_DATA=0
[ "${1:-}" = "--keep-data" ] && KEEP_DATA=1

# 1. Stop + disable + remove the systemd unit.
systemctl stop "$SERVICE" 2>/dev/null || true
systemctl disable "$SERVICE" 2>/dev/null || true
rm -f "/etc/systemd/system/${SERVICE}.service"
systemctl daemon-reload
systemctl reset-failed "$SERVICE" 2>/dev/null || true

# 2. Remove files.
if [ "$KEEP_DATA" = "1" ]; then
  rm -rf "$INSTALL_ROOT/releases" "$INSTALL_ROOT/current" "$INSTALL_ROOT/run.sh" "$INSTALL_ROOT/updates"
  echo "Aplikasi dihapus. Data (config/state) DIPERTAHANKAN di $INSTALL_ROOT/data"
else
  rm -rf "$INSTALL_ROOT"
  echo "Aplikasi + data dihapus dari $INSTALL_ROOT"
fi

echo "✅ Techma Gateway telah dihapus (service '$SERVICE' dihentikan & dinonaktifkan)."
echo "   Untuk memasang lagi: jalankan install.sh."
