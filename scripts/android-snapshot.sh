#!/usr/bin/env bash
# Mirrors the Android data dir to the encrypted rclone remote so your apps and
# data survive across sessions. Runs rclone via sudo because redroid's /data is
# owned by uid 1000 inside the container.
#
# Note: this backs up a *running* Android, so it is a crash-consistent copy at
# best — Android is always writing. That is fine for a backup you restore onto
# a fresh container, but treat the newest few minutes as unreliable.
set -uo pipefail

REMOTE="${REMOTE:-crypt1:android}"
TRASH_REMOTE="${TRASH_REMOTE:-crypt1:trash}"
DATA_DIR="${DATA_DIR:-/var/redroid-data}"
STAMP="$(date -u +%Y%m%d-%H%M%S)"

export RCLONE_CONFIG="${HOME}/.config/rclone/rclone.conf"

if [ ! -f "$RCLONE_CONFIG" ]; then
  echo "::warning:: no rclone.conf found; skipping Android backup"
  exit 0
fi

if [ ! -d "$DATA_DIR" ]; then
  echo "::warning:: $DATA_DIR does not exist; skipping Android backup"
  exit 0
fi

echo "Backing up $DATA_DIR -> ${REMOTE} (trash: ${TRASH_REMOTE}/${STAMP})"

# Low CPU / idle I/O priority so the backup doesn't make the phone stutter.
sudo nice -n 19 ionice -c3 env RCLONE_CONFIG="$RCLONE_CONFIG" rclone sync "$DATA_DIR" "$REMOTE/" \
  --backup-dir "${TRASH_REMOTE}/${STAMP}" \
  --transfers 8 --checkers 4 --fast-list \
  --stats 30s --stats-one-line \
  --exclude '**/*.sock' \
  --exclude '**/lost+found/**'

# Prune trash older than 7 days.
sudo nice -n 19 ionice -c3 env RCLONE_CONFIG="$RCLONE_CONFIG" rclone delete --min-age 7d "$TRASH_REMOTE" 2>/dev/null || true
sudo nice -n 19 ionice -c3 env RCLONE_CONFIG="$RCLONE_CONFIG" rclone rmdirs "$TRASH_REMOTE" --leave-root 2>/dev/null || true

echo "Android backup complete."
