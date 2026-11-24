#!/bin/bash
# Log alerts: checks VictoriaLogs for security, admin and disk events and sends them through apprise-api.
# Run every 5 minutes from User Scripts. Each run covers the time since the previous run, so nothing is
# missed or sent twice. Ongoing conditions (bursts, silent sources) repeat at most once per cooldown.
# Manual test (prints what it would send, sends nothing, keeps its state in /tmp):
#   NONOTIFY=1 STATE_DIR=/tmp/log-alerts-test bash /boot/config/plugins/log-alerts/log-alerts.sh
# Settings below can be overridden by environment variables (the User Script wrapper sets the real values).

VL_URL="${VL_URL:-http://YOUR_SERVER_IP:9428}"
APPRISE_URL="${APPRISE_URL:-http://YOUR_SERVER_IP:8010/notify/YOUR_APPRISE_KEY}"
GATEWAY_HOST="${GATEWAY_HOST:-YOUR_GATEWAY_HOSTNAME}"   # hostname the UniFi gateway uses in syslog
UNRAID_HOST="${UNRAID_HOST:-YOUR_UNRAID_HOSTNAME}"      # hostname Unraid uses in syslog
IGNORE_ADMINS="${IGNORE_ADMINS:-}"   # comma-separated UniFi admin names whose logins and changes are not alerted
STATE_DIR="${STATE_DIR:-/mnt/user/appdata/log-alerts}"
NOTIFY=/usr/local/emhttp/webGui/scripts/notify

BURST_MIN="${BURST_MIN:-10}"        # NPM: look at the last N minutes...
BURST_LIMIT="${BURST_LIMIT:-20}"      # ...and alert when one client got this many 401/403 responses
BURST_COOLDOWN=3600
GW_SILENT_MIN="${GW_SILENT_MIN:-30}"    # alert if the gateway's syslog has been silent this long
CT_SILENT_MIN="${CT_SILENT_MIN:-60}"    # alert if no container logs have arrived this long
SILENT_COOLDOWN=21600
VL_DOWN_RUNS="${VL_DOWN_RUNS:-3}"      # alert after this many failed runs in a row (the nightly backup stops VictoriaLogs briefly)
LAG=60              # seconds; the newest minute is left for the next run so late lines are not missed
MAX_WINDOW=86400    # after a long outage, look back at most this far
MAX_LINES="${MAX_LINES:-10}"   # lines listed per section before "and N more"
MAX_BODY=1900       # characters; Discord rejects messages over 2000, so longer bodies are cut at a line end

# Kernel and disk messages worth an alert. No quotes or backslashes: it goes inside a LogsQL string.
DISK_RE='(?i)(i/o error|medium error|uncorrectable|ata[0-9.]+: (exception|failed command|hard resetting link)|md: disk[0-9]+ (read|write) error|smart.*(fail|error)|checksum error|zio.*error)'

mkdir -p "$STATE_DIR"
exec 9>"$STATE_DIR/lock"
flock -n 9 || exit 0

NOW=$(date +%s)
LAST_FILE="$STATE_DIR/last-run"
COOL="$STATE_DIR/cooldowns"
FAILS_FILE="$STATE_DIR/vl-fails"
touch "$COOL"

send() {  # send TITLE BODY TYPE(info|success|warning|failure)
  if [ "$NONOTIFY" = "1" ]; then
    printf '== %s [%s] ==\n%s\n\n' "$1" "$3" "$2"
    return 0
  fi
  jq -n --arg t "$1" --arg b "$2" --arg y "$3" '{title: $t, body: $b, type: $y}' |
    curl -sf -m 20 -H 'Content-Type: application/json' -d @- "$APPRISE_URL" >/dev/null && return 0
  "$NOTIFY" -e "Log alerts" -s "$1" -d "$2 (sent here because apprise-api did not answer)" -i alert
}

due() {  # due KEY SECONDS: succeeds (and records the time) if KEY has not alerted within SECONDS
  local last
  last=$(awk -v k="$1" '$1 == k {print $2}' "$COOL")
  [ -n "$last" ] && [ $((NOW - last)) -lt "$2" ] && return 1
  { awk -v k="$1" '$1 != k' "$COOL"; echo "$1 $NOW"; } > "$COOL.tmp" && mv "$COOL.tmp" "$COOL"
}

clear_cooldown() { awk -v k="$1" '$1 != k' "$COOL" > "$COOL.tmp" && mv "$COOL.tmp" "$COOL"; }

vlq() { curl -sf -m 30 "$VL_URL/select/logsql/query" --data-urlencode "query=$1"; }

# Cooldown entries older than a day are no longer needed.
awk -v n="$NOW" '(n - $2) < 86400' "$COOL" > "$COOL.tmp" && mv "$COOL.tmp" "$COOL"

# 0. Is VictoriaLogs up? If not, stop without moving the window forward, so the next run catches up.
if ! curl -sf -m 10 "$VL_URL/health" >/dev/null; then
  FAILS=$(( $(cat "$FAILS_FILE" 2>/dev/null || echo 0) + 1 ))
  echo "$FAILS" > "$FAILS_FILE"
  if [ "$FAILS" -ge "$VL_DOWN_RUNS" ] && due vl-down "$SILENT_COOLDOWN"; then
    send "VictoriaLogs is not answering" "No answer from $VL_URL for $FAILS runs in a row. Log alerts are paused until it is back." failure
  fi
  exit 1
fi
rm -f "$FAILS_FILE"
clear_cooldown vl-down

# Time window for event checks: from the previous run to a minute ago.
END=$((NOW - LAG))
START=$(cat "$LAST_FILE" 2>/dev/null)
[[ "$START" =~ ^[0-9]+$ ]] || START=$((END - 300))
[ $((END - START)) -gt "$MAX_WINDOW" ] && START=$((END - MAX_WINDOW))
[ "$START" -ge "$END" ] && exit 0
RANGE="_time:[$(date -u -d "@$START" +%FT%TZ), $(date -u -d "@$END" +%FT%TZ))"

SECTIONS=()
LEVEL=info

# jq helpers for section(): t = local time of the event, $ignored = IGNORE_ADMINS as a list.
# shellcheck disable=SC2016  # $ign and $ignored are jq variables, not shell ones
JQ_PRELUDE='def t: ._time | sub("\\.[0-9]+"; "") | fromdate | strflocaltime("%m-%d %H:%M");
  ($ign | split(",") | map(gsub("^ +| +$"; "")) | map(select(. != ""))) as $ignored | '

# section TITLE QUERY JQ_FORMAT: runs QUERY, formats each row with JQ_FORMAT (which may also drop rows with
# select), and adds a section if any rows are left. Returns 1 if the query failed.
section() {
  local out lines n body
  out=$(vlq "$2") || return 1
  lines=$(printf '%s' "$out" | jq -r --arg ign "$IGNORE_ADMINS" "$JQ_PRELUDE$3")
  n=$(printf '%s' "$lines" | grep -c .)
  [ "$n" -eq 0 ] && return 0
  body=$(printf '%s\n' "$lines" | head -n "$MAX_LINES")
  [ "$n" -gt "$MAX_LINES" ] && body="$body"$'\n'"...and $((n - MAX_LINES)) more"
  SECTIONS+=("**$1 ($n)**"$'\n'"$body")
}

FAILED=""

# 1. UniFi security events: IPS/IDS detections, honeypot hits and the like. Firewall-policy blocks are
#    left out; they only appear for policies with logging on and can be searched in VictoriaLogs.
section "UniFi security events" \
  "$RANGE app_name:CEF cef.extension.UNIFIcategory:Security -cef.name:\"Blocked by Firewall\" | sort by (_time)" \
  '"\(t)  \(.["cef.name"] // "?"): \(.["cef.extension.msg"] // "")"' || FAILED="$FAILED security"

# 2. UniFi admin access and setting changes. Logins and setting changes are shortened, e.g.
#    "claude made a change to  in X Firewall Policy settings. Source IP: ..." -> "claude changed firewall
#    policy "X" from ..."; any other message is listed as UniFi wrote it.
# shellcheck disable=SC2016  # $a, $m, $s and $ignored are jq variables
section "UniFi admin activity" \
  "$RANGE app_name:CEF cef.extension.UNIFIcategory:Audit | sort by (_time)" \
  'select((.["cef.extension.UNIFIadmin"] // "") as $a | any($ignored[]; . == $a) | not)
   | (.["cef.extension.msg"] // "") as $m
   | ($m | sub(" *Source IP: [^ ]+$"; "")
         | sub(" accessed UniFi Network using the (?<x>[^.]+)\\.$"; " logged in (\(.x))")
         | sub(" made a change to (?<f>.*?) ?in (?<x>.+) Firewall Policy settings\\.$";
               " changed \(if .f == "" then "" else .f + " in " end)firewall policy \"\(.x)\"")
         | sub(" made a change to (?<f>.*?) ?in (?<x>.+) settings\\.$";
               " changed \(if .f == "" then "" else .f + " in " end)\(.x) settings")) as $s
   | if $s == $m then "\(t)  \(.["cef.name"] // "?"): \($m)"
     else "\(t)  \($s)\(if .["cef.extension.src"] then " from " + .["cef.extension.src"] else "" end)" end' \
  || FAILED="$FAILED admin"

# 3. Disk and kernel I/O errors in the Unraid syslog.
section "Disk errors on $UNRAID_HOST" \
  "$RANGE hostname:\"$UNRAID_HOST\" _msg:~\"$DISK_RE\" -_msg:~\"loop[0-9]\" | sort by (_time)" \
  '"\(t)  \(.app_name // "?"): \(._msg | .[0:200])"' || FAILED="$FAILED disk"

if [ -n "$FAILED" ]; then
  echo "Query failed for:$FAILED. Nothing sent; the next run will retry the same window." >&2
  exit 1
fi

# 4. NPM: one client collecting many 401/403 responses (password guessing or a scanner).
if OUT=$(vlq "_time:${BURST_MIN}m container_name:npm stream:access status:in(401,403) | stats by (client) count() hits, count_uniq(vhost) sites | filter hits:>=$BURST_LIMIT | sort by (hits desc)"); then
  BURSTS=""
  while IFS=$'\t' read -r CLIENT HITS SITES; do
    [ -n "$CLIENT" ] || continue
    due "npm-burst-$CLIENT" "$BURST_COOLDOWN" && BURSTS="$BURSTS$CLIENT: $HITS responses on $SITES site(s)"$'\n'
  done < <(printf '%s' "$OUT" | jq -r '[.client, .hits, .sites] | @tsv')
  [ -n "$BURSTS" ] && SECTIONS+=("**NPM 401/403 bursts (last $BURST_MIN min)**"$'\n'"${BURSTS%$'\n'}")
fi

# 5. Sources that went quiet.
count() { vlq "$1 | stats count() c" | jq -r '.c // 0' 2>/dev/null; }
GW=$(count "_time:${GW_SILENT_MIN}m hostname:\"$GATEWAY_HOST\"")
if [ "${GW:-0}" = "0" ]; then
  due gw-silent "$SILENT_COOLDOWN" && SECTIONS+=("**UniFi syslog silent**"$'\n'"Nothing from $GATEWAY_HOST for $GW_SILENT_MIN minutes. Check Activity Logging (SIEM server) in UniFi.")
else
  clear_cooldown gw-silent
fi
CT=$(count "_time:${CT_SILENT_MIN}m container_name:*")
if [ "${CT:-0}" = "0" ]; then
  due ct-silent "$SILENT_COOLDOWN" && SECTIONS+=("**Container logs silent**"$'\n'"No container logs for $CT_SILENT_MIN minutes. Is vector running?")
else
  clear_cooldown ct-silent
fi

# Send one message for everything found, then move the window forward.
if [ ${#SECTIONS[@]} -gt 0 ]; then
  for S in "${SECTIONS[@]}"; do
    case "$S" in "**UniFi security events"*|"**Disk errors"*) LEVEL=failure ;; esac
  done
  [ "$LEVEL" = info ] && LEVEL=warning
  BODY=$(printf '%s\n\n' "${SECTIONS[@]}")
  if [ ${#BODY} -gt "$MAX_BODY" ]; then
    BODY="${BODY:0:$MAX_BODY}"
    BODY="${BODY%$'\n'*}"$'\n'"...(cut; search VictoriaLogs for the rest)"
  fi
  send "Log alerts: ${#SECTIONS[@]} item(s)" "$BODY" "$LEVEL"
fi
echo "$END" > "$LAST_FILE"
