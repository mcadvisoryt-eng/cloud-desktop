#!/usr/bin/env bash
# Runs while the emulator is up: starts the browser viewers, then keeps the
# session alive and pre-queues the next run near the end.
#
# Called from the reactivecircus/android-emulator-runner `script:` hook, so the
# emulator is already booted and `adb` points at it.
set -uo pipefail

SESSION_MINUTES="${SESSION_MINUTES:-330}"

# The emulator's adb serial is emulator-5554; don't assume it.
SERIAL="$(adb devices | awk 'NR==2 && $2=="device" {print $1}' | head -1)"
SERIAL="${SERIAL:-emulator-5554}"
echo "using device: $SERIAL"

# Keep the guest awake and smooth.
adb -s "$SERIAL" shell svc power stayon true || true
adb -s "$SERIAL" shell settings put system screen_off_timeout 2147483647 || true
adb -s "$SERIAL" shell settings put global window_animation_scale 0 || true
adb -s "$SERIAL" shell settings put global transition_animation_scale 0 || true
adb -s "$SERIAL" shell settings put global animator_duration_scale 0 || true

# --- Viewer #0: webscreen — WebRTC, the lowest-latency transport we have.
# WebRTC does its own NAT traversal, runs on UDP, and renders frames as they
# arrive instead of buffering them for smoothness (that buffer alone is worth
# ~90ms at p50). Single static binary; see TUNNEL.md. ---
WS_PIN="${WEBSCREEN_PIN:-123456}"
if [ ! -x /tmp/webscreen ]; then
  curl -fsSL -o /tmp/webscreen \
    https://github.com/huonwe/webscreen/releases/latest/download/webscreen-linux-amd64 \
    && chmod +x /tmp/webscreen || echo "::warning::could not download webscreen"
fi
if [ -x /tmp/webscreen ]; then
  nohup /tmp/webscreen -host 0.0.0.0 -port 8079 -pin "$WS_PIN" >/tmp/webscreen.log 2>&1 &
  sleep 5
  echo "--- webscreen ---"; tail -10 /tmp/webscreen.log || true
  echo "::notice::webscreen (WebRTC) ready: http://${TS_HOSTNAME}.<your-tailnet>.ts.net:8079  PIN ${WS_PIN}"
fi

# --- Viewer #1: stream-droid, scrcpy backend. scrcpy encodes H.264 on the
# device and streams it natively; the browser decodes via WebCodecs/MSE.
# (scrcpy 5.0 also hardware-decodes, so the server side is cheap.) ---
nohup npx -y stream-droid "$SERIAL" --capture scrcpy --headless --port 3200 >/tmp/stream-droid.log 2>&1 &
sleep 15
echo "--- stream-droid ---"; tail -20 /tmp/stream-droid.log || true
echo "::notice::stream-droid viewer: http://${TS_HOSTNAME}.<your-tailnet>.ts.net:3200/"

# --- Viewer #2: scrcpy -> Xvnc (TigerVNC) -> websockify -> noVNC.
# Xvnc is ONE process that is both the X server and the VNC server, so there is
# no Xvfb + x11vnc pair to fall out of sync — which is what left a black
# screen on the previous setup. ---
export DISPLAY=:99
Xvnc :99 -geometry 540x960 -depth 24 -SecurityTypes None -rfbport 5900 \
     -AlwaysShared -localhost no >/tmp/xvnc.log 2>&1 &
sleep 3
# Make sure adb still has the device before scrcpy tries to attach to it.
if [[ "$SERIAL" == *:* ]]; then adb connect "$SERIAL" >/dev/null 2>&1 || true; fi
# scrcpy's flags differ by version: apt ships 1.25, which has NO --no-audio
# and NO --render-driver (both arrived in 2.0). Passing them makes scrcpy exit
# instantly and the VNC display stays black. So probe --help and only pass what
# this build actually understands. `-b` and --max-size exist in every version.
SCRCPY_HELP="$(scrcpy --help 2>&1 || true)"
SCRCPY_EXTRA=""
echo "$SCRCPY_HELP" | grep -q -- '--no-audio'      && SCRCPY_EXTRA="$SCRCPY_EXTRA --no-audio"
echo "$SCRCPY_HELP" | grep -q -- '--render-driver' && SCRCPY_EXTRA="$SCRCPY_EXTRA --render-driver=software"
echo "$SCRCPY_HELP" | grep -q -- '--max-fps'       && SCRCPY_EXTRA="$SCRCPY_EXTRA --max-fps ${SCRCPY_MAX_FPS:-30}"
echo "scrcpy $(scrcpy --version 2>&1 | head -1) — extra flags:${SCRCPY_EXTRA:-none}"
scrcpy -s "$SERIAL" --max-size "${SCRCPY_MAX_SIZE:-540}" -b "${SCRCPY_BITRATE:-4M}" \
      $SCRCPY_EXTRA --window-title Android >/tmp/scrcpy.log 2>&1 &
sleep 5
websockify --web /usr/share/novnc 6080 localhost:5900 >/tmp/websockify.log 2>&1 &
sleep 2
for f in xvnc scrcpy websockify; do echo "--- $f ---"; tail -15 "/tmp/$f.log" || true; done
echo "::notice::noVNC viewer: http://${TS_HOSTNAME}.<your-tailnet>.ts.net:6080/vnc.html (raw VNC :5900)"

# --- Path check: is Tailscale direct or relaying via DERP? A DERP path costs
# ~6x throughput and >100ms of latency, and is the usual reason a tailnet feels
# slow. See TUNNEL.md. ---
echo "--- tailscale status ---"; tailscale status | head -5 || true
echo "--- tailscale netcheck ---"; tailscale netcheck 2>/dev/null | head -25 || true

start=$(date +%s); prequeued=0
while true; do
  now=$(date +%s)
  elapsed=$(( (now - start) / 60 ))
  remaining=$(( SESSION_MINUTES - elapsed ))
  if [ "$remaining" -le 0 ]; then echo "Session budget reached after ${elapsed}m."; break; fi

  adb get-state >/dev/null 2>&1 || { echo "::warning::emulator is gone — stopping the session"; break; }

  if [ "$prequeued" -eq 0 ] && [ "$remaining" -le 10 ] && [ -n "${GH_TOKEN:-}" ] && [ -n "${GH_REPOSITORY:-}" ]; then
    if gh workflow run android-emulator.yml --repo "$GH_REPOSITORY" 2>/dev/null; then
      echo "Next session pre-queued (${remaining}m left)."; prequeued=1
    fi
  fi
  sleep 15
done
echo "Session loop complete."
