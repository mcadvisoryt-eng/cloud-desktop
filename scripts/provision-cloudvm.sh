#!/usr/bin/env bash
# provision-cloudvm.sh — turn a fresh Ubuntu 22.04/24.04 VM into the same
# low-latency XFCE + xrdp desktop as the GitHub workflow, but with no 6-hour
# cap and a real persistent disk.
#
# Run it on a VM in an INDIAN region (Mumbai / Hyderabad / Pune / Chennai /
# Bangalore) — that is where the latency win comes from (~5-30 ms RTT instead
# of ~180-250 ms to a US runner).
#
# Usage (on the VM, as root or with sudo):
#   sudo DESKTOP_PASSWORD='YourPass1' TS_AUTHKEY='tskey-auth-...' \
#        ./scripts/provision-cloudvm.sh
#
# Optional env:
#   DESKTOP_USER  (default: pc)
#   TS_HOSTNAME   (default: cloudpc)
set -euo pipefail

DESKTOP_USER="${DESKTOP_USER:-pc}"
TS_HOSTNAME="${TS_HOSTNAME:-cloudpc}"
: "${DESKTOP_PASSWORD:?set DESKTOP_PASSWORD (the RDP password)}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y --no-install-recommends \
  xfce4 xfce4-terminal thunar xclip xdg-utils \
  xrdp dbus-x11 xorgxrdp \
  firefox \
  fonts-noto-cjk fonts-noto-color-emoji \
  policykit-1-gnome \
  python3

# --- desktop user + session ------------------------------------------------
if ! id "$DESKTOP_USER" >/dev/null 2>&1; then
  useradd -m -s /bin/bash "$DESKTOP_USER"
fi
echo "${DESKTOP_USER}:${DESKTOP_PASSWORD}" | chpasswd
usermod -aG ssl-cert "$DESKTOP_USER" 2>/dev/null || true
mkdir -p "/home/$DESKTOP_USER/.config"
# xrdp runs ~/.xsession on login. It MUST be launched through dbus-launch, or
# xfce4-session aborts with "Unable to determine failsafe session name".
cat > "/home/$DESKTOP_USER/.xsession" <<'XSEOF'
#!/bin/sh
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
export XDG_CONFIG_DIRS=/etc/xdg
xset s off -dpms 2>/dev/null || true
exec dbus-launch --exit-with-session startxfce4
XSEOF
chmod +x "/home/$DESKTOP_USER/.xsession"
chown "$DESKTOP_USER:$DESKTOP_USER" "/home/$DESKTOP_USER/.xsession"

# --- latency tuning (identical to the Actions workflow) --------------------
if [ -f "$SCRIPT_DIR/tune-xrdp.py" ]; then
  python3 "$SCRIPT_DIR/tune-xrdp.py" /etc/xrdp/xrdp.ini
fi

# --- XFCE: no compositor, no animations ------------------------------------
XFWM_DIR="/home/$DESKTOP_USER/.config/xfce4/xfconf/xfce-perchannel-xml"
mkdir -p "$XFWM_DIR"
cat > "$XFWM_DIR/xfwm4.xml" <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfwm4" version="1.0">
  <property name="general" type="empty">
    <property name="use_compositing" type="bool" value="false"/>
    <property name="box_move" type="bool" value="false"/>
    <property name="box_resize" type="bool" value="false"/>
  </property>
</channel>
XML
chown -R "$DESKTOP_USER:$DESKTOP_USER" "/home/$DESKTOP_USER"

systemctl enable --now xrdp

# --- Tailscale (the only way in; no public ports needed) -------------------
if ! command -v tailscale >/dev/null 2>&1; then
  curl -fsSL https://tailscale.com/install.sh | sh
fi
if [ -n "${TS_AUTHKEY:-}" ]; then
  tailscale up --authkey="$TS_AUTHKEY" --hostname="$TS_HOSTNAME" --accept-routes
else
  echo ":: warning :: TS_AUTHKEY not set — run 'tailscale up' manually to expose the desktop"
fi

echo "Done. RDP to ${TS_HOSTNAME}.<your-tailnet>.ts.net:3389 as ${DESKTOP_USER}."
