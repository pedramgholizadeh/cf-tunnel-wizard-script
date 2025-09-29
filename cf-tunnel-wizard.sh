#!/usr/bin/env bash
# cf-tunnel-wizard.sh
# Formal and simple Cloudflare Tunnel installer/wizard for Ubuntu
# Usage: sudo bash ./cf-tunnel-wizard.sh
set -euo pipefail

# -------------------------
# Simple color helpers
# -------------------------
CSI="\033["
RESET="${CSI}0m"
BOLD="${CSI}1m"
RED="${CSI}31m"
GREEN="${CSI}32m"
YELLOW="${CSI}33m"
CYAN="${CSI}36m"

info()   { printf "${CYAN}[INFO]${RESET} %s\n" "$*"; }
ok()     { printf "${GREEN}[OK]${RESET} %s\n" "$*"; }
warn()   { printf "${YELLOW}[WARN]${RESET} %s\n" "$*"; }
err()    { printf "${RED}[ERROR]${RESET} %s\n" "$*" >&2; }

prompt() { printf "${BOLD}%s${RESET} " "$*"; }

# -------------------------
# Sanity checks
# -------------------------
if [[ "$(id -u)" -ne 0 ]]; then
  err "This script requires sudo privileges. Please run as root or with sudo."
  exit 1
fi

ARCH=$(uname -m)
if [[ "$ARCH" != "x86_64" && "$ARCH" != "aarch64" && "$ARCH" != "arm64" ]]; then
  err "Unsupported architecture: $ARCH. Supported: x86_64, aarch64/arm64."
  exit 1
fi

# -------------------------
# Check cloudflared presence
# -------------------------
if command -v cloudflared >/dev/null 2>&1; then
  ok "cloudflared is already installed: $(command -v cloudflared)"
  CLOUD_INSTALLED=true
else
  info "cloudflared not found. Will download and install the official Debian package."
  CLOUD_INSTALLED=false
fi

# -------------------------
# Install cloudflared (if needed)
# -------------------------
if ! $CLOUD_INSTALLED; then
  # Choose package name by arch
  if [[ "$ARCH" == "x86_64" ]]; then
    DEB="cloudflared-linux-amd64.deb"
  else
    DEB="cloudflared-linux-arm64.deb"
  fi

  TMPDIR=$(mktemp -d)
  cd "$TMPDIR"

  info "Downloading latest cloudflared .deb..."
  if ! curl -fsSL -o "$DEB" "https://github.com/cloudflare/cloudflared/releases/latest/download/${DEB}"; then
    err "Download failed. Check network connectivity and try again."
    rm -rf "$TMPDIR"
    exit 1
  fi

  info "Installing package..."
  if ! dpkg -i "$DEB" >/dev/null 2>&1; then
    warn "dpkg returned errors. Attempting to fix dependencies..."
    apt-get update -y
    apt-get install -f -y
  fi

  cd - >/dev/null
  rm -rf "$TMPDIR"

  if command -v cloudflared >/dev/null 2>&1; then
    ok "cloudflared installed successfully."
  else
    err "cloudflared installation failed. Inspect logs and try again."
    exit 1
  fi
fi

# -------------------------
# Cloudflare login
# -------------------------
echo
info "Next step: Authenticate cloudflared with your Cloudflare account."
echo "A browser window will open to allow login and permission to manage tunnels."
prompt "Press Enter to open the login page in the default browser (or Ctrl+C to cancel)."
read -r _

# This command will open a browser for the user and create credentials in ~/.cloudflared
if ! cloudflared login; then
  err "cloudflared login failed. Please run 'cloudflared login' manually and retry."
  exit 1
fi

# -------------------------
# Collect user inputs
# -------------------------
echo
printf "%s\n" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
printf "%s\n" "Please provide the following information. Keep entries simple and exact."
printf "%s\n" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
read -r -p "Domain (for example: example.com): " USER_DOMAIN
read -r -p "Full hostname / subdomain (for example: app.example.com): " HOSTNAME
read -r -p "Local port where the service is listening on localhost (for example: 8080): " LOCAL_PORT
read -r -p "Tunnel name (leave empty to auto-generate from hostname): " RAW_TUNNEL_NAME

if [[ -z "$USER_DOMAIN" || -z "$HOSTNAME" || -z "$LOCAL_PORT" ]]; then
  err "Domain, hostname and local port are required."
  exit 1
fi

TUNNEL_NAME="$RAW_TUNNEL_NAME"
if [[ -z "$TUNNEL_NAME" ]]; then
  # convert dots to hyphens for a safe name
  TUNNEL_NAME="${HOSTNAME//./-}"
fi

info "Summary of inputs:"
printf "  Domain:    %s\n" "$USER_DOMAIN"
printf "  Hostname:  %s\n" "$HOSTNAME"
printf "  Local port:%s\n" "$LOCAL_PORT"
printf "  Tunnel id: %s\n" "$TUNNEL_NAME"
echo

read -r -p "Proceed with creating the tunnel? (y/N): " CONF
case "$CONF" in
  [yY]|[yY][eE][sS]) ;;
  *) info "Operation cancelled by user."; exit 0 ;;
esac

# -------------------------
# Create tunnel
# -------------------------
info "Creating tunnel with name: $TUNNEL_NAME"
CREATE_OUT=$(cloudflared tunnel create "$TUNNEL_NAME" 2>&1) || {
  err "Failed to create tunnel. cloudflared output:"
  echo "$CREATE_OUT"
  exit 1
}

echo "$CREATE_OUT"

# Try to extract tunnel UUID from output or from credentials directory
TUNNEL_UUID=$(echo "$CREATE_OUT" | sed -n 's/.*Created tunnel \([^ ]*\).*/\1/p' || true)
if [[ -z "$TUNNEL_UUID" ]]; then
  # fallback: pick first json file name in ~/.cloudflared
  CAND_FILE=$(ls -1 "$HOME/.cloudflared"/*.json 2>/dev/null | head -n1 || true)
  if [[ -n "$CAND_FILE" ]]; then
    TUNNEL_UUID=$(basename "$CAND_FILE" .json)
  fi
fi

if [[ -z "$TUNNEL_UUID" ]]; then
  warn "Tunnel UUID could not be determined automatically."
  warn "Please ensure the tunnel was created and a credentials file exists in ~/.cloudflared."
else
  ok "Tunnel UUID: $TUNNEL_UUID"
fi

# -------------------------
# Create DNS route
# -------------------------
info "Creating DNS route for $HOSTNAME"
if cloudflared tunnel route dns "$TUNNEL_NAME" "$HOSTNAME"; then
  ok "DNS route created (Cloudflare will add a CNAME record)."
else
  warn "DNS route command reported an issue. Please verify that your Cloudflare account has the domain and that your login has required permissions."
fi

# -------------------------
# Create config file
# -------------------------
CONFIG_DIR="/etc/cloudflared"
CONFIG_FILE="${CONFIG_DIR}/config.yml"
info "Writing configuration to ${CONFIG_FILE}"

# Ensure directory exists
mkdir -p "$CONFIG_DIR"
chown root:root "$CONFIG_DIR"
chmod 755 "$CONFIG_DIR"

# Determine credential file path (if exists)
CRED_FILE="$HOME/.cloudflared/${TUNNEL_UUID}.json"
if [[ ! -f "$CRED_FILE" ]]; then
  # pick any json in ~/.cloudflared
  CAND=$(ls -1 "$HOME/.cloudflared"/*.json 2>/dev/null | head -n1 || true)
  if [[ -n "$CAND" ]]; then
    CRED_FILE="$CAND"
  else
    warn "No credentials json found in ~/.cloudflared. Some commands may fail until credentials exist."
    CRED_FILE=""
  fi
fi

# Compose YAML config
cat > "$CONFIG_FILE" <<EOF
# Cloudflared configuration created by cf-tunnel-wizard
tunnel: ${TUNNEL_UUID}
credentials-file: ${CRED_FILE}
ingress:
  - hostname: ${HOSTNAME}
    service: http://localhost:${LOCAL_PORT}
  - service: http_status:404
EOF

chown root:root "$CONFIG_FILE"
chmod 644 "$CONFIG_FILE"
ok "Configuration written."

# -------------------------
# Create systemd service
# -------------------------
SERVICE_NAME="cloudflared-${TUNNEL_NAME}.service"
SERVICE_PATH="/etc/systemd/system/${SERVICE_NAME}"

info "Installing a systemd unit: ${SERVICE_PATH}"
cat > "${SERVICE_PATH}" <<'UNIT'
[Unit]
Description=Cloudflare Tunnel for %i
After=network.target

[Service]
Type=simple
User=root
Environment=LOGFILE=/var/log/cloudflared/%I.log
ExecStart=/usr/local/bin/cloudflared tunnel --config /etc/cloudflared/config.yml run %i
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
UNIT

# The ExecStart path may differ depending on installation location.
# Try to determine correct binary path and replace if necessary.
CF_PATH=$(command -v cloudflared || true)
if [[ -n "$CF_PATH" && "$CF_PATH" != "/usr/local/bin/cloudflared" ]]; then
  sed -i "s|/usr/local/bin/cloudflared|${CF_PATH}|g" "${SERVICE_PATH}"
fi

mkdir -p /var/log/cloudflared
chown root:root /var/log/cloudflared
chmod 755 /var/log/cloudflared
systemctl daemon-reload

info "Enabling and starting the service now."
systemctl enable --now "${SERVICE_NAME}" || {
  warn "Service enable/start reported an issue. You can start the service manually later."
}

sleep 1
if systemctl is-active --quiet "${SERVICE_NAME}"; then
  ok "Service ${SERVICE_NAME} is active and running."
else
  warn "Service ${SERVICE_NAME} is not active. Check 'journalctl -u ${SERVICE_NAME} -f' for details."
fi

# -------------------------
# Final instructions
# -------------------------
echo
printf "%s\n" "════════════════════════════════════════════"
printf "%s\n" "Finished."
printf "%s\n" "════════════════════════════════════════════"
echo

printf "${BOLD}How to run the tunnel manually (one-off):${RESET}\n"
printf "  %s\n\n" "cloudflared tunnel run ${TUNNEL_NAME}"

printf "${BOLD}How to run the tunnel as a service (systemd):${RESET}\n"
printf "  %s\n" "sudo systemctl start ${SERVICE_NAME}"
printf "  %s\n" "sudo systemctl stop  ${SERVICE_NAME}"
printf "  %s\n" "sudo systemctl enable ${SERVICE_NAME}   # start on boot"
printf "  %s\n\n" "sudo systemctl disable ${SERVICE_NAME}  # disable on boot"

printf "${BOLD}Logs and status:${RESET}\n"
printf "  %s\n" "sudo journalctl -u ${SERVICE_NAME} -f"
printf "  %s\n\n" "tail -n 200 /var/log/cloudflared/${TUNNEL_NAME}.log"

printf "${BOLD}DNS records in Cloudflare:${RESET}\n"
printf "  %s\n" "A CNAME record should have been added at: ${HOSTNAME} -> ${TUNNEL_NAME}.cfargotunnel.com"
printf "\n"

ok "If you need to change port or hostname later:"
printf "  %s\n" "1) Update /etc/cloudflared/config.yml (modify service or hostname)."
printf "  %s\n" "2) Restart service: sudo systemctl restart ${SERVICE_NAME}"
printf "\n"

info "Wizard complete. Keep this script for future setup or adjustments."