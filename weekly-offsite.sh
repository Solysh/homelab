#!/bin/bash
# Weekly encrypted offsite copy of the newest Appdata Backup to Dropbox.
# Test without changing anything:  DRY=1 bash /boot/config/plugins/rclone/weekly-offsite.sh

CONF=/boot/config/plugins/rclone/rclone.conf
SRCROOT=/mnt/user/backups/Appdata/appdata_backup
REMOTE="dropbox-crypt:"
KEEP=4
BW=1.0M
LOGDIR=/mnt/user/appdata/rclone-offsite
LOG="$LOGDIR/last-run.log"
NOTIFY=/usr/local/emhttp/webGui/scripts/notify
RC="rclone --config $CONF"
EXTRA=""
[ "$DRY" = "1" ] && EXTRA="--dry-run"

mkdir -p "$LOGDIR"
exec > "$LOG" 2>&1

notify() {
  [ "$DRY" = "1" ] && return
  "$NOTIFY" -e "Offsite backup" -s "$2" -d "$3" -i "$1"
}
fail() {
  echo "FAILED: $1"
  notify alert "Offsite backup FAILED" "$1 (log: $LOG)"
  exit 1
}

echo "$(date) start (DRY=${DRY:-0})"

# Wait up to 90 minutes for the Appdata Backup plugin to finish
for i in $(seq 1 90); do
  pgrep -f "appdata.backup/scripts/backup.php" > /dev/null || break
  sleep 60
done
pgrep -f "appdata.backup/scripts/backup.php" > /dev/null && fail "Appdata Backup still running after 90 minutes"

# Pick the newest backup folder and sanity check it
SRC=$(ls -dt "$SRCROOT"/ab_* 2>/dev/null | head -1)
SRC=${SRC%/}
[ -n "$SRC" ] && [ -d "$SRC" ] || fail "No backup folder found in $SRCROOT"
NAME=$(basename "$SRC")
echo "$NAME" | grep -Eq '^ab_[0-9]{8}_[0-9]{6}$' || fail "Unexpected folder name: $NAME"
find "$SRC" -maxdepth 0 -mtime -3 | grep -q . || fail "Newest backup $NAME is older than 3 days"
echo "Source: $SRC"

# Upload (copy never deletes anything)
$RC copy "$SRC" "${REMOTE}${NAME}" --bwlimit "$BW" --transfers 1 --stats 10m -v $EXTRA || fail "Upload failed"

# Verify sizes after a real upload
if [ "$DRY" != "1" ]; then
  CHK=$($RC check "$SRC" "${REMOTE}${NAME}" --size-only 2>&1)
  echo "$CHK"
  echo "$CHK" | grep -Eq ': 0 differences found' || fail "Size check after upload found differences"
fi

# Prune: keep only the newest $KEEP remote copies
LIST=$($RC lsf --dirs-only "$REMOTE" | tr -d '/' | grep -E '^ab_[0-9]{8}_[0-9]{6}$' | sort)
COUNT=$(echo "$LIST" | grep -c .)
echo "Remote copies: $COUNT"
if [ "$COUNT" -gt "$KEEP" ]; then
  echo "$LIST" | head -n $((COUNT - KEEP)) | while read -r D; do
    echo "Pruning $D"
    $RC purge "${REMOTE}${D}" $EXTRA || echo "WARNING: prune failed for $D"
  done
fi

echo "$(date) done"
notify normal "Offsite backup OK" "Uploaded $NAME to Dropbox (encrypted). Keeping the newest $KEEP copies."
