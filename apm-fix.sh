#!/bin/bash
# Turn off aggressive drive power management (APM) at array start, so drives
# don't park their heads every few seconds and rack up load cycles.
# 254 = maximum performance without spin-down; Unraid's own spin-down timer still applies.
# Schedule: "At Startup of Array" in User Scripts.

DRIVES="${DRIVES:-/dev/sd[b-h]}"   # array drives; edit to match your server

for dev in $DRIVES; do
  [ -b "$dev" ] || continue
  hdparm -B 254 "$dev"
done
