#!/usr/bin/env bash
# Mirrors /home/pc to the encrypted rclone remote defined by REMOTE.
# Runs rclone via sudo so it can read files owned by the 'pc' user —
# this avoids chown-ing the live home directory mid-session.
# Uses --backup-dir so deletions are recoverable for 7 days, then pruned.
#
# Latency note: the sync runs at idle CPU priority (nice 19) and idle I/O
# priority (ionice -c3) with fewer checkers, so a backup never competes with
# your interactive session for the runner's CPU or disk. This is what keeps
# the desktop from stuttering every time a snapshot fires.
set -uo pipefail

REMOTE="${REMOTE:-crypt:home}"
TRASH_REMOTE="${TRASH_REMOTE:-crypt:trash}"
STAMP="$(date -u +%Y%m%d-%H%M%S)"

# rclone's config was written by the workflow step to the runner user's home.
export RCLONE_CONFIG="${HOME}/.config/rclone/rclone.conf"

# Prefer the static binary installed at /usr/local/bin, fall back to apt's.
RCLONE_BIN="$(command -v rclone || echo rclone)"

if [ ! -f "$RCLONE_CONFIG" ]; then
  echo "::warning:: no rclone.conf found; skipping snapshot"
  exit 0
fi

if [ ! -d /home/pc ]; then
  echo "::warning:: /home/pc does not exist; skipping snapshot"
  exit 0
fi

echo "Snapshotting /home/pc -> ${REMOTE} (trash: ${TRASH_REMOTE}/${STAMP})"

# Run as root to read 'pc'-owned files without touching ownership.
# RCLONE_CONFIG is passed explicitly so sudo doesn't lose it.
# nice/ionice keep the transfer out of the interactive path.
sudo nice -n 19 ionice -c3 env RCLONE_CONFIG="$RCLONE_CONFIG" "$RCLONE_BIN" sync /home/pc "$REMOTE/" \
  --backup-dir "${TRASH_REMOTE}/${STAMP}" \
  --transfers 8 --checkers 4 --fast-list --links \
  --stats 30s --stats-one-line \
  --exclude '.cache/**' \
  --exclude 'Cache/**' \
  --exclude '**/cache2/**' \
  --exclude '**/startupCache/**' \
  --exclude '**/shader-cache/**' \
  --exclude '.xsession-errors' \
  --exclude '.ICEauthority' \
  --exclude 'gvfs/**'

# Prune trash older than 7 days so the Drive doesn't fill up forever.
sudo nice -n 19 ionice -c3 env RCLONE_CONFIG="$RCLONE_CONFIG" "$RCLONE_BIN" delete --min-age 7d "$TRASH_REMOTE" 2>/dev/null || true
sudo nice -n 19 ionice -c3 env RCLONE_CONFIG="$RCLONE_CONFIG" "$RCLONE_BIN" rmdirs "$TRASH_REMOTE" --leave-root 2>/dev/null || true

echo "Snapshot complete."
