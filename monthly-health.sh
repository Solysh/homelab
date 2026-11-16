#!/bin/bash
# Monthly health check for the server. Sends one Discord summary through Unraid notifications.
# Manual test (prints the report, sends nothing):
#   NONOTIFY=1 bash /boot/config/plugins/health-check/monthly-health.sh

RCCONF=/boot/config/plugins/rclone/rclone.conf
STATE_DIR="${STATE_DIR:-/boot/config/plugins/health-check}"
OUTDIR="${OUTDIR:-/mnt/user/appdata/health-check}"
STATE="$STATE_DIR/smart-crc.state"
REPORT="$OUTDIR/last-report.txt"
NOTIFY=/usr/local/emhttp/webGui/scripts/notify
EXPECT_DRIVES=7
CAP_LIMIT=95
EXCLUDE_CONTAINERS=""   # space-separated container names that are meant to be stopped

mkdir -p "$OUTDIR" "$STATE_DIR"
ISSUES=()
REPORT_LINES=()
ok()   { REPORT_LINES+=("OK    $1"); }
warn() { REPORT_LINES+=("WARN  $1"); ISSUES+=("$1"); }

# 1. Containers
BAD=""
while read -r NAME STATUS; do
  case " $EXCLUDE_CONTAINERS " in *" $NAME "*) continue ;; esac
  case "$STATUS" in Up*) ;; *) BAD="$BAD $NAME" ;; esac
done < <(docker ps -a --format '{{.Names}} {{.Status}}' 2>/dev/null)
[ -z "$BAD" ] && ok "All containers running" || warn "Containers not running:$BAD"

# 1b. Web UIs answering (a container can be Up while the app inside is hung)
HOSTIP=YOUR_SERVER_IP   # LAN IP of the server
SERVICES="plex:32400 sonarr:8989 radarr:7878 prowlarr:9696 seerr:5055 tautulli:8181 nzbget:6789 audiobookshelf:13378 npm:81 posterizarr:8000 chaptarr:8789 clonarr:6060 apprise-api:8010 tracearr:3001"
DOWN=""
for SVC in $SERVICES; do
  CODE=$(curl -s -o /dev/null -m 10 -w '%{http_code}' "http://${HOSTIP}:${SVC#*:}/")
  { [ "$CODE" -ge 100 ] && [ "$CODE" -lt 500 ]; } 2>/dev/null || DOWN="$DOWN ${SVC%%:*}($CODE)"
done
[ -z "$DOWN" ] && ok "All $(echo $SERVICES | wc -w) web UIs responding" || warn "Web UIs not responding:$DOWN"

# 2. Array
MD=$(mdcmd status 2>/dev/null)
mdv() { echo "$MD" | grep -E "^$1=" | cut -d= -f2; }
[ "$(mdv mdState)" = "STARTED" ] && ok "Array started" || warn "Array state is '$(mdv mdState)'"
[ "$(mdv sbSyncErrs)" = "0" ] && ok "No parity sync errors" || warn "Parity sync errors: '$(mdv sbSyncErrs)'"
[ "$(mdv mdNumDisabled)" -le 1 ] 2>/dev/null && ok "Disabled disks: $(mdv mdNumDisabled) (1 is the empty parity-2 slot)" || warn "Disabled disks: '$(mdv mdNumDisabled)' (expected 1)"
[ "$(mdv mdNumInvalid)" -le 1 ] 2>/dev/null && ok "Invalid disks: $(mdv mdNumInvalid) (1 is the empty parity-2 slot)" || warn "Invalid disks: '$(mdv mdNumInvalid)' (expected 1)"

# 3. Pool fullness
HOT=""
while read -r N C; do
  P=${C%\%}
  [ "$P" -ge "$CAP_LIMIT" ] 2>/dev/null && HOT="$HOT $N($C)"
done < <(zpool list -H -o name,cap 2>/dev/null)
[ -z "$HOT" ] && ok "All pools under ${CAP_LIMIT}% full" || warn "Pools at or over ${CAP_LIMIT}%:$HOT"

# 3b. ZFS pool health
ZS=$(zpool status -x 2>&1)
if [ "$ZS" = "all pools are healthy" ]; then
  ok "ZFS: all pools healthy"
else
  warn "ZFS reports a problem: $(echo "$ZS" | tr '\n' ' ' | cut -c1-200)"
fi

# 4. VMs
ALLVMS=$(virsh list --all --name 2>/dev/null | sed '/^$/d' | sort)
if [ -z "$ALLVMS" ]; then
  warn "No VMs listed (libvirt down?)"
else
  RUNVMS=$(virsh list --state-running --name 2>/dev/null | sed '/^$/d' | sort)
  VMBAD=$(comm -23 <(echo "$ALLVMS") <(echo "$RUNVMS") | tr '\n' ',')
  [ -z "$VMBAD" ] && ok "VMs running" || warn "VM not running: ${VMBAD%,}"
fi

# 5. Appdata backup
LASTBK=$(ls -dt /mnt/user/backups/Appdata/appdata_backup/ab_*/ 2>/dev/null | head -1)
if [ -z "$LASTBK" ]; then
  warn "No appdata backup folder found"
else
  BKN=$(basename "$LASTBK")
  tail -3 "${LASTBK}backup.log" 2>/dev/null | grep -q DONE && ok "Latest appdata backup finished ($BKN)" || warn "Latest appdata backup log does not end in DONE ($BKN)"
  find "$LASTBK" -maxdepth 0 -mtime -2 | grep -q . || warn "Latest appdata backup is more than 2 days old ($BKN)"
fi

# 6. Kometa
KC=$(grep -c CRITICAL /mnt/user/appdata/Kometa/logs/meta.log 2>/dev/null)
[ "${KC:-x}" = "0" ] && ok "Kometa: no CRITICAL lines" || warn "Kometa CRITICAL lines: ${KC:-meta.log not found}"

# 7. Plex database trouble strings
PLEXLOGS="/mnt/user/appdata/plex/Library/Application Support/Plex Media Server/Logs"
if [ -d "$PLEXLOGS" ]; then
  PC=$(find "$PLEXLOGS" -name "Plex Media Server*.log" -exec grep -hiE "database is locked|malformed|corrupt|SQLITE_BUSY" {} + 2>/dev/null | grep -vc "DatabaseFixups")
  [ "$PC" = "0" ] && ok "Plex logs: no lock or corruption messages" || warn "Plex logs: $PC lock or corruption messages"
else
  warn "Plex log folder not found"
fi

# 8. Drive health (CRC errors compared with last month, keyed by serial number)
declare -A OLD
if [ -f "$STATE" ]; then
  while read -r S V; do OLD[$S]=$V; done < "$STATE"
fi
NEW=""
SEEN=0
for DEV in /dev/sd?; do
  H=$(smartctl -H "$DEV" 2>/dev/null)
  echo "$H" | grep -Eq "PASSED|FAILED" || continue
  SEEN=$((SEEN + 1))
  SER=$(smartctl -i "$DEV" 2>/dev/null | awk -F: '/Serial Number/{gsub(/ /,"",$2); print $2}')
  echo "$H" | grep -q PASSED || warn "SMART health FAILED on $DEV ($SER)"
  A=$(smartctl -A "$DEV" 2>/dev/null)
  BADATTR=$(echo "$A" | awk '/Reallocated_Sector_Ct|Current_Pending_Sector|Offline_Uncorrectable/ && ($10+0)>0 {printf "%s=%s ", $2, $10}')
  [ -z "$BADATTR" ] || warn "Drive $SER ($DEV) has nonzero SMART counters: $BADATTR"
  CRC=$(echo "$A" | awk '/UDMA_CRC_Error_Count/{print $10+0}')
  if [ -n "$CRC" ]; then
    NEW="$NEW$SER $CRC"$'\n'
    if [ -n "${OLD[$SER]}" ] && [ "$CRC" -gt "${OLD[$SER]}" ]; then
      warn "Drive $SER ($DEV) CRC errors rose from ${OLD[$SER]} to $CRC (check cable)"
    fi
  fi
done
[ -n "$NEW" ] && printf "%s" "$NEW" > "$STATE"
[ "$SEEN" -ge "$EXPECT_DRIVES" ] && ok "SMART read from $SEEN drives" || warn "Only $SEEN drives reported SMART (expected $EXPECT_DRIVES)"

# 9. Dropbox offsite copies
NEWEST=$(rclone --config "$RCCONF" lsf --dirs-only dropbox-crypt: 2>/dev/null | tr -d '/' | grep -E '^ab_[0-9]{8}_[0-9]{6}$' | sort | tail -1)
if [ -z "$NEWEST" ]; then
  warn "Dropbox: no offsite copies found (or Dropbox unreachable)"
else
  AGE=$(( ( $(date +%s) - $(date -d "${NEWEST:3:8}" +%s) ) / 86400 ))
  [ "$AGE" -le 9 ] && ok "Dropbox: newest offsite copy is $NEWEST ($AGE days old)" || warn "Dropbox: newest offsite copy is $AGE days old ($NEWEST)"
fi

# Report
{ echo "Monthly health check, $(date)"; printf '%s\n' "${REPORT_LINES[@]}"; } | tee "$REPORT"

if [ "$NONOTIFY" != "1" ]; then
  if [ ${#ISSUES[@]} -eq 0 ]; then
    "$NOTIFY" -e "Health check" -s "Monthly health check: all clear" -d "${#REPORT_LINES[@]} checks passed. Report: $REPORT" -i normal
  else
    DESC=$(printf '%s; ' "${ISSUES[@]}")
    "$NOTIFY" -e "Health check" -s "Monthly health check: ${#ISSUES[@]} issue(s)" -d "$DESC" -i alert
  fi
fi
