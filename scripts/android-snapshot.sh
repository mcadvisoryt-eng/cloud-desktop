#!/usr/bin/env bash
# Mirrors the Android data dir to the encrypted rclone remote so apps and data
# survive across sessions.
#
# Resilience rules (deliberate):
#   * A backup that does not complete must NEVER block the session.
#   * If it fails, we retry once, then write a log, upload that log to
#     <remote>:logs/ so you can read it later, and exit 0.
#   * Pruning old trash is best-effort and never fatal either.
#
# Runs rclone via sudo because redroid's /data is owned by uid 1000.
set -uo pipefail

REMOTE="${REMOTE:-crypt1:android}"
TRASH_REMOTE="${TRASH_REMOTE:-crypt1:trash}"
LOG_REMOTE="${LOG_REMOTE:-crypt1:logs}"
DATA_DIR="${DATA_DIR:-/var/redroid-data}"
STAMP="$(date -u +%Y%m%d-%H%M%S)"
LOG="/tmp/android-backup-${STAMP}.log"

export RCLONE_CONFIG="${HOME}/.config/rclone/rclone.conf"

log() { echo "[$(date -u +%H:%M:%S)] $*" | tee -a "$LOG"; }

# rclone, low CPU / idle I/O so a backup never makes the phone stutter.
rc() { sudo nice -n 19 ionice -c3 env RCLONE_CONFIG="$RCLONE_CONFIG" rclone "$@"; }

upload_log() {
  rc copyto "$LOG" "${LOG_REMOTE}/android-backup-${STAMP}.log" >/dev/null 2>&1 \
    || echo "::warning::could not upload the backup log to ${LOG_REMOTE}"
}

if [ ! -f "$RCLONE_CONFIG" ]; then
  log "no rclone.conf found; skipping Android backup"
  exit 0
fi

if [ ! -d "$DATA_DIR" ]; then
  log "$DATA_DIR does not exist; skipping Android backup"
  exit 0
fi

log "Backing up $DATA_DIR -> ${REMOTE} (trash: ${TRASH_REMOTE}/${STAMP})"

attempt=1
max_attempts=2
while :; do
  log "attempt ${attempt}/${max_attempts}"
  if rc sync "$DATA_DIR" "$REMOTE/" \
        --backup-dir "${TRASH_REMOTE}/${STAMP}" \
        --transfers 8 --checkers 4 --fast-list \
        --stats 30s --stats-one-line \
        --exclude '**/*.sock' \
        --exclude '**/lost+found/**' >>"$LOG" 2>&1; then
    log "Backup complete."
    # Prune trash older than 7 days (best-effort).
    rc delete --min-age 7d "$TRASH_REMOTE" >>"$LOG" 2>&1 || true
    rc rmdirs "$TRASH_REMOTE" --leave-root >>"$LOG" 2>&1 || true
    exit 0
  fi

  if [ "$attempt" -ge "$max_attempts" ]; then
    log "backup FAILED after ${attempt} attempts"
    log "uploading this log to ${LOG_REMOTE}/android-backup-${STAMP}.log and continuing WITHOUT blocking the session"
    upload_log
    echo "::warning::Android backup did not complete; log saved to ${LOG_REMOTE}/android-backup-${STAMP}.log — session continues"
    exit 0
  fi

  attempt=$((attempt + 1))
  sleep 20
done
