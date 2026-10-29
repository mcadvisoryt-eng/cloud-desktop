#!/usr/bin/env bash
# Mirrors /home/pc to the encrypted rclone remote defined by REMOTE.
# Runs rclone via sudo so it can read files owned by the 'pc' user —
# this avoids chown-ing the live home directory mid-session.
# Uses --backup-dir so deletions are recoverable for 7 days, then pruned.
#
# Latency note: the sync runs at idle CPU priority (nice 19) and idle I/O
# priority (ionice -c3) with fewer checkers, so a backup never competes with
# your interactive session for the runner's CPU or disk.
#
# Resilience rules (deliberate):
#   * A backup that does not complete must NEVER block the session.
# Change detection: --checksum compares MD5s that the remote already stores, so
# a file is re-uploaded only when its content actually differs. Nothing is
# downloaded to compare — the hash comes from the remote's metadata (and for a
# crypt remote, rclone derives it from the backend's hashes).
#
#   * If it fails, we retry once, then write a log, upload that log to
#     <remote>:logs/ so you can read it later, and exit 0.
set -uo pipefail

REMOTE="${REMOTE:-crypt1:home}"
TRASH_REMOTE="${TRASH_REMOTE:-crypt1:trash}"
LOG_REMOTE="${LOG_REMOTE:-crypt1:logs}"
STAMP="$(date -u +%Y%m%d-%H%M%S)"
LOG="/tmp/linux-backup-${STAMP}.log"

# rclone's config was written by the workflow step to the runner user's home.
export RCLONE_CONFIG="${HOME}/.config/rclone/rclone.conf"

# Prefer the static binary installed at /usr/local/bin, fall back to apt's.
RCLONE_BIN="$(command -v rclone || echo rclone)"

# Fixed default topic so notifications work out of the box. Override any time by
# setting the NTFY_TOPIC secret; this value stays until you change it.
NTFY_TOPIC="${NTFY_TOPIC:-cloudpc-2c50b2a3b2ba989d}"

log() { echo "[$(date -u +%H:%M:%S)] $*" | tee -a "$LOG"; }

# ntfy push notification (https://ntfy.sh). Set NTFY_TOPIC as a repo secret to
# enable; without it this is a no-op and never blocks a backup.
notify() {
  if [ -z "${NTFY_TOPIC:-}" ]; then log "ntfy skipped: NTFY_TOPIC is not set"; return 0; fi
  if curl -fsS -m 15 -H "Title: ${1}" -H "Tags: ${2}" -H "Priority: ${3:-default}" \
       -d "${4}" "https://ntfy.sh/${NTFY_TOPIC}" >/dev/null 2>&1; then
    log "ntfy sent: ${1}"
  else
    log "ntfy failed: ${1}"
  fi
  return 0
}

# nice/ionice keep the transfer out of the interactive path.
rc() { sudo nice -n 19 ionice -c3 env RCLONE_CONFIG="$RCLONE_CONFIG" "$RCLONE_BIN" "$@"; }

upload_log() {
  rc copyto "$LOG" "${LOG_REMOTE}/linux-backup-${STAMP}.log" >/dev/null 2>&1 \
    || echo "::warning::could not upload the backup log to ${LOG_REMOTE}"
}

if [ ! -f "$RCLONE_CONFIG" ]; then
  log "no rclone.conf found; skipping snapshot"
  exit 0
fi

if [ ! -d /home/pc ]; then
  log "/home/pc does not exist; skipping snapshot"
  exit 0
fi

log "Snapshotting /home/pc -> ${REMOTE} (trash: ${TRASH_REMOTE}/${STAMP})"

# Heartbeat: refreshed on every snapshot so a watchdog can tell a WEDGED session
# (no snapshots at all) from a merely quiet one. Best-effort; never blocks.
printf '%s\n' "$(date -u +%FT%TZ)" > /tmp/heartbeat.txt
rc copyto /tmp/heartbeat.txt "${LOG_REMOTE}/heartbeat.txt" >/dev/null 2>&1 || true

attempt=1
max_attempts=2
while :; do
  log "attempt ${attempt}/${max_attempts}"
  if rc sync /home/pc "$REMOTE/" \
        --backup-dir "${TRASH_REMOTE}/${STAMP}" \
        --transfers 8 --checkers 4 --fast-list --links --checksum \
        --stats 30s --stats-one-line \
        --exclude '.cache/**' \
        --exclude 'Cache/**' \
        --exclude '**/cache2/**' \
        --exclude '**/startupCache/**' \
        --exclude '**/shader-cache/**' \
        --exclude '.ICEauthority' \
        --exclude 'gvfs/**' >>"$LOG" 2>&1; then
    log "Snapshot complete."
    rc copyto "$LOG" "${LOG_REMOTE}/linux-backup-latest.log" >/dev/null 2>&1 || true
    changed=$(grep -oE 'Transferred:[[:space:]]+[0-9]+' "$LOG" | tail -1 | grep -oE '[0-9]+' || true)
    notify "Linux backup ok" "white_check_mark" "default" \
      "cloudpc: ${changed:-0} file(s) changed, synced to ${REMOTE}"
    # Prune trash older than 7 days (best-effort).
    rc delete --min-age 7d "$TRASH_REMOTE" >>"$LOG" 2>&1 || true
    rc rmdirs "$TRASH_REMOTE" --leave-root >>"$LOG" 2>&1 || true
    exit 0
  fi

  if [ "$attempt" -ge "$max_attempts" ]; then
    log "snapshot FAILED after ${attempt} attempts"
    notify "Linux backup FAILED" "x" "high" \
      "cloudpc: snapshot failed after ${attempt} attempts — see ${LOG_REMOTE}/linux-backup-${STAMP}.log"
    log "uploading this log to ${LOG_REMOTE}/linux-backup-${STAMP}.log and continuing WITHOUT blocking the session"
    upload_log
    echo "::warning::Linux snapshot did not complete; log saved to ${LOG_REMOTE}/linux-backup-${STAMP}.log — session continues"
    exit 0
  fi

  attempt=$((attempt + 1))
  sleep 20
done
