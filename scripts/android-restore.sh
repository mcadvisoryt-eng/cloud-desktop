#!/usr/bin/env bash
# Restore the Android data dir from the encrypted rclone remote.
#
# Why this is a script with a subtree list: restoring the whole root made rclone
# enumerate the entire encrypted tree (media/, caches, …) before copying
# anything, which stalled for tens of minutes with no output. We restore only
# the subtrees that actually matter, and the caller wraps this in `timeout` so a
# slow remote can never hang the boot.
#
# Resilience: a failure is logged, uploaded to <remote>:logs/, and never fatal —
# the session starts either way.
set -uo pipefail

REMOTE="${REMOTE:-crypt1:android}"
LOG_REMOTE="${LOG_REMOTE:-crypt1:logs}"
DATA_DIR="${DATA_DIR:-/var/redroid-data}"
STAMP="$(date -u +%Y%m%d-%H%M%S)"
LOG="/tmp/android-restore-${STAMP}.log"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXCLUDES="${EXCLUDES:-$SCRIPT_DIR/android-excludes.txt}"

export RCLONE_CONFIG="${HOME}/.config/rclone/rclone.conf"

# Only these subtrees are restored. media/ (user storage: photos, downloads) is
# deliberately skipped — it is the biggest tree and the slowest to enumerate.
SUBTREES="${SUBTREES:-data app system misc local user}"

log() { echo "[$(date -u +%H:%M:%S)] $*" | tee -a "$LOG"; }

rc() { sudo env RCLONE_CONFIG="$RCLONE_CONFIG" rclone "$@"; }

if [ ! -f "$RCLONE_CONFIG" ]; then
  log "no rclone.conf — starting with empty Android data"
  exit 0
fi

if ! rclone listremotes 2>/dev/null | grep -q '^crypt1:$'; then
  log "no crypt1 remote — starting with empty Android data"
  exit 0
fi

failed=0
for d in $SUBTREES; do
  log "restoring $d ..."
  if rc copy "$REMOTE/$d/" "$DATA_DIR/$d" \
        --transfers 32 --checkers 32 --stats 30s --stats-one-line \
        --exclude-from "$EXCLUDES" >>"$LOG" 2>&1; then
    log "restored $d"
  else
    log "restore of $d did not complete"
    failed=1
  fi
done

if [ "$failed" -eq 1 ]; then
  rc copyto "$LOG" "${LOG_REMOTE}/android-restore-${STAMP}.log" >/dev/null 2>&1 \
    || echo "::warning::could not upload the restore log to ${LOG_REMOTE}"
  echo "::warning::some Android data did not restore; log saved to ${LOG_REMOTE}/android-restore-${STAMP}.log — starting anyway"
fi

# redroid runs as uid 1000 inside the container.
sudo chown -R 1000:1000 "$DATA_DIR" 2>/dev/null || true
log "restore finished"
exit 0
