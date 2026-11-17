#!/bin/bash
# List the largest container log files, to spot runaway logging that fills docker.img.
# Read-only. Schedule: weekly in User Scripts, or run by hand.

du -ah /var/lib/docker/containers/ 2>/dev/null \
  | grep -- '-json\.log' \
  | sort -rh \
  | head -n 20
