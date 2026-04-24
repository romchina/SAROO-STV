#!/bin/bash
set -e
cd "$(dirname "$0")"
pkill -9 yabause 2>/dev/null || true
sleep 1
yabause -a -b ~/.yabause/bios.bin --binary=/tmp/ip.bin:0x06004000 > /tmp/yabause.log 2>&1 &
YPID=$!
echo "PID=$YPID"
i=0
while [ "$i" -lt 60 ]; do
  if ! kill -0 "$YPID" 2>/dev/null; then
    echo "yabause exited at t=${i}s"
    break
  fi
  sleep 1
  i=$((i+1))
done
kill "$YPID" 2>/dev/null || true
echo "--- log ---"
cat /tmp/yabause.log
