#!/usr/bin/env bash
# Runs the live desktop session for SESSION_MINUTES, taking an encrypted
# snapshot to rclone every SNAPSHOT_EVERY_MIN minutes. Monitors xrdp and
# restarts it if it dies. Exits cleanly so the workflow's "Trigger next
# session" step can chain the next runner.
#
# Responsiveness / latency notes:
#   * xrdp is health-checked every HEALTH_EVERY_SEC (default 15 s), not once
#     per snapshot interval, so a crash is repaired in seconds instead of up
#     to 30 minutes of downtime.
#   * ~10 min before the session ends the next runner is pre-queued (via gh)
#     so it starts the moment this one stops, removing the queue wait from
#     the handoff. The workflow's own trigger step then sees a queued run and
#     skips adding another.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SESSION_MINUTES="${SESSION_MINUTES:-330}"
SNAPSHOT_EVERY_MIN="${SNAPSHOT_EVERY_MIN:-30}"
HEALTH_EVERY_SEC="${HEALTH_EVERY_SEC:-15}"
PREQUEUE_BEFORE_MIN="${PREQUEUE_BEFORE_MIN:-10}"

xrdp_healthy() {
  ss -ltn 2>/dev/null | grep -q ':3389 '
}

restart_xrdp() {
  echo "[$(date -u +%FT%TZ)] ::warning:: xrdp is down — restarting"
  sudo service xrdp restart 2>/dev/null || sudo systemctl restart xrdp 2>/dev/null || true
}

start=$(date +%s)
last_snap=$start
prequeued=0
echo "::notice::Session started $(date -u +%FT%TZ). Running ${SESSION_MINUTES}m, snapshot every ${SNAPSHOT_EVERY_MIN}m, health check every ${HEALTH_EVERY_SEC}s."

while true; do
  now=$(date +%s)
  elapsed=$(( (now - start) / 60 ))
  remaining=$(( SESSION_MINUTES - elapsed ))
  if [ "$remaining" -le 0 ]; then
    echo "Session time budget reached after ${elapsed}m."
    break
  fi

  # Keep xrdp alive — cheap check, runs often.
  if ! xrdp_healthy; then restart_xrdp; fi

  # Pre-queue the next runner shortly before this session ends so the handoff
  # does not pay the trigger + queue latency. Best-effort only.
  if [ "$prequeued" -eq 0 ] && [ "$remaining" -le "$PREQUEUE_BEFORE_MIN" ]; then
    if [ -n "${GH_TOKEN:-}" ] && [ -n "${GH_REPOSITORY:-}" ]; then
      if gh workflow run desktop.yml --repo "$GH_REPOSITORY" 2>/dev/null; then
        echo "[$(date -u +%FT%TZ)] Next session pre-queued (${remaining}m left)."
        prequeued=1
      fi
    fi
  fi

  # Snapshot when due.
  since_snap=$(( (now - last_snap) / 60 ))
  if [ "$since_snap" -ge "$SNAPSHOT_EVERY_MIN" ]; then
    echo "[$(date -u +%FT%TZ)] Periodic checkpoint (elapsed ${elapsed}m)..."
    bash "$SCRIPT_DIR/snapshot.sh" || echo "::warning:: periodic snapshot failed, session continues"
    last_snap=$(date +%s)
  fi

  sleep "$HEALTH_EVERY_SEC"
done

echo "[$(date -u +%FT%TZ)] Session loop complete."
