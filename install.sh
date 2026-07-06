#!/usr/bin/env bash
# =============================================================================
# Techma Gateway — installer / migrator for Armbian / Debian (systemd).
#
# Fresh install or MIGRATE an old box to the new gateway (no manual steps, and
# NO Node.js needed — the release is a single self-contained binary):
#   curl -fsSL https://raw.githubusercontent.com/techma-technology/counting-gateway/main/install.sh | sudo bash
#
# Re-running upgrades to the latest release.
# =============================================================================
set -euo pipefail

INSTALL_ROOT="${INSTALL_ROOT:-/opt/techma-gateway}"
MANIFEST_URL="${MANIFEST_URL:-https://raw.githubusercontent.com/techma-technology/counting-gateway/main/latest.json}"
LOCAL_PORT="${LOCAL_PORT:-80}"          # dedicated appliance → serve the panel on :80
ARCH="$(uname -m)"                       # x86_64 | aarch64

echo "== Techma Gateway installer (arch: $ARCH) =="
[ "$(id -u)" -eq 0 ] || { echo "Jalankan sebagai root (sudo)."; exit 1; }
command -v curl >/dev/null || { apt-get update && apt-get install -y curl; }

# 1. Read the manifest, then pick the tarball whose filename matches THIS arch.
TMP="$(mktemp)"
curl -fsSL "$MANIFEST_URL" -o "$TMP"
VERSION="$(grep -oE '"version"[^,]*' "$TMP" | head -1 | grep -oE '[0-9][^"]*')"
URL="$(grep -oE "https://[^\"]+${ARCH}[^\"]*\.tar\.gz" "$TMP" | head -1)"
# fallback to the top-level url only if no arch-specific asset is listed
[ -n "$URL" ] || URL="$(grep -oE '"url"[[:space:]]*:[[:space:]]*"[^"]+"' "$TMP" | head -1 | sed -E 's/.*"([^"]+)".*/\1/')"
if [ -z "$URL" ]; then
  echo "❌ Tidak ada paket untuk arsitektur '$ARCH' di manifest ($MANIFEST_URL)."; exit 1
fi
echo "Versi terbaru: v$VERSION"

# 2. Download + extract the self-contained binary release.
mkdir -p "$INSTALL_ROOT/releases/$VERSION" "$INSTALL_ROOT/data"
echo "Mengunduh $URL"
curl -fsSL "$URL" | tar -xz --strip-components=1 -C "$INSTALL_ROOT/releases/$VERSION"
chmod +x "$INSTALL_ROOT/releases/$VERSION/techma-gateway"
echo "$VERSION" > "$INSTALL_ROOT/current"

# 3. Launcher that always runs the version named in `current`.
cat > "$INSTALL_ROOT/run.sh" <<RUN
#!/usr/bin/env bash
ROOT="$INSTALL_ROOT"
DIR="\$ROOT/releases/\$(cat "\$ROOT/current")"
cd "\$DIR"
exec "\$DIR/techma-gateway"
RUN
chmod +x "$INSTALL_ROOT/run.sh"

# 4. Best-effort config carry-over (device key / cloud URL) from an older install.
if [ ! -f "$INSTALL_ROOT/data/config.json" ]; then
  for old in /opt/techma-counting/config.json /opt/techma/config.json /root/config.json; do
    [ -f "$old" ] && cp "$old" "$INSTALL_ROOT/data/config.json" && echo "Config lama diimpor dari $old" && break
  done
fi

# 5. systemd service (no Node dependency — the binary is self-contained).
#    Panel password uses the shared default ('techma'); the user changes it from
#    the panel (stored on the device) and can reset it via the Scanner app.
cat > /etc/systemd/system/techma-gateway.service <<UNIT
[Unit]
Description=Techma Counting Gateway
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
Environment=STATE_DIR=$INSTALL_ROOT/data
Environment=INSTALL_ROOT=$INSTALL_ROOT
Environment=UPDATE_MANIFEST_URL=$MANIFEST_URL
Environment=UPDATE_ALLOW_REAL=true
Environment=LOCAL_PORT=$LOCAL_PORT
ExecStart=$INSTALL_ROOT/run.sh
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
UNIT

# 6. Disable any legacy Techma service.
for legacy in techma-counting techma techma-client counting techma-cloud; do
  systemctl stop "$legacy" 2>/dev/null || true
  systemctl disable "$legacy" 2>/dev/null || true
done

systemctl daemon-reload
systemctl enable --now techma-gateway

IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
PORT_SUFFIX=""; [ "$LOCAL_PORT" != "80" ] && PORT_SUFFIX=":$LOCAL_PORT"
echo
echo "======================================================================"
echo " Terpasang: Techma Gateway v$VERSION ($ARCH, binary mandiri)"
echo " Panel admin : http://${IP:-<ip-box>}${PORT_SUFFIX}"
echo " Password default: techma  (ubah dari panel; reset via aplikasi Scanner)"
echo "======================================================================"
