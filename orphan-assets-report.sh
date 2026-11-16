#!/bin/bash
# Orphan Assets Report (read-only)
# Finds Kometa/Posterizarr asset folders whose movie or show no longer has
# video files on disk, then sends a summary through Unraid notifications
# (which forward to Discord). Nothing is moved or deleted.

ASSETS="/mnt/user/appdata/Kometa/assets"
MEDIA="/mnt/user/media/library"
REPORT_DIR="/mnt/user/backups/orphan-reports"
REPORT="$REPORT_DIR/orphans-$(date +%Y-%m-%d).txt"
NOTIFY="/usr/local/emhttp/webGui/scripts/notify"
EXT='.*\.(mkv|mp4|avi|m4v|ts|m2ts|iso|mov|wmv|mpg|mpeg|webm)$'

mkdir -p "$REPORT_DIR"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Folder names that still contain video files
# TV:     /mnt/user/media/library/tv/<library>/<show>/...   -> field 8
# Movies: name of the folder holding each video file (works at any depth)
find "$MEDIA/tv" -type f -regextype posix-extended -iregex "$EXT" \
  | awk -F/ '{print $8}' | sort -u > "$TMP/tv-media.txt"
find "$MEDIA/movies" -type f -regextype posix-extended -iregex "$EXT" -printf '%h\n' \
  | awk -F/ '{print $NF}' | sort -u > "$TMP/movie-media.txt"

# Safety: if a media scan comes back empty (share offline, path changed),
# stop instead of reporting everything as orphaned
if [ ! -s "$TMP/tv-media.txt" ] || [ ! -s "$TMP/movie-media.txt" ]; then
  "$NOTIFY" -e "Orphan Assets Report" -s "Orphan report skipped" \
    -d "Media scan returned no files. Check that $MEDIA is mounted." -i "warning"
  exit 1
fi

cd "$ASSETS" || exit 1
: > "$REPORT"
for lib in "TV Shows" "TV Shows - Anime"; do
  [ -d "$lib" ] || continue
  find "$lib" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort \
    | comm -23 - "$TMP/tv-media.txt" | sed "s|^|$lib/|" >> "$REPORT"
done
find "Movies" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort \
  | comm -23 - "$TMP/movie-media.txt" | sed 's|^|Movies/|' >> "$REPORT"

TOTAL=$(wc -l < "$REPORT")
TV=$(grep -c '^TV Shows' "$REPORT")
MOV=$(grep -c '^Movies/' "$REPORT")

# Sanity check: if more than 25% of a library's asset folders look orphaned,
# the matching is probably broken, so warn instead of reporting
TV_ALL=$(find "TV Shows" "TV Shows - Anime" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)
MOV_ALL=$(find "Movies" -mindepth 1 -maxdepth 1 -type d | wc -l)
if [ $((TV * 4)) -gt "$TV_ALL" ] || [ $((MOV * 4)) -gt "$MOV_ALL" ]; then
  "$NOTIFY" -e "Orphan Assets Report" -s "Orphan report looks wrong" \
    -d "TV: $TV of $TV_ALL, Movies: $MOV of $MOV_ALL flagged. Too many to be real, check folder matching. List: $REPORT" \
    -i "warning"
  exit 1
fi

if [ "$TOTAL" -eq 0 ]; then
  rm -f "$REPORT"
  "$NOTIFY" -e "Orphan Assets Report" -s "No orphan assets" \
    -d "All Kometa asset folders match media on disk." -i "normal"
  exit 0
fi

SIZE=$(tr '\n' '\0' < "$REPORT" | du -sch --files0-from=- 2>/dev/null | tail -1 | cut -f1)
SAMPLE=$(head -5 "$REPORT" | sed 's|.*/||' | paste -sd ';' - | sed 's/;/; /g')

"$NOTIFY" -e "Orphan Assets Report" \
  -s "$TOTAL orphan asset folders ($SIZE)" \
  -d "TV: $TV, Movies: $MOV. First few: $SAMPLE. Full list: $REPORT" \
  -i "normal"

# Keep the 12 newest reports
ls -1t "$REPORT_DIR"/orphans-*.txt 2>/dev/null | tail -n +13 | xargs -r -d '\n' rm -f