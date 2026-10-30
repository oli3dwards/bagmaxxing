#!/bin/bash
# Real-world check; needs a person to unplug the Mac and close the lid.
#   Part 1, keep awake: once the lid closes, record every 5 s for 90 s: lid, battery,
#           heat and internet. A gap of more than 20 s between lines means the Mac slept.
#   Part 2, cut-out: with the lid still shut and on battery, pretend the battery is low
#           (LOW_BATTERY=100). The next check should send the phone notification and
#           sleep the Mac, once 2 minutes have passed since anyone touched it. Opening
#           the lid wakes it, and the pretend setting is removed.
set -uo pipefail
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
ROOT=$(cd "$(dirname "$0")/.." && pwd)
DIR="$HOME/Library/Application Support/lidawake"
CONF="$DIR/config.sh"
restore() { # takes the pretend setting out; anything else in config.sh stays
  [ -e "$CONF" ] || return 0
  sed -i '' '/^LOW_BATTERY=100$/d' "$CONF"
  [ -s "$CONF" ] || rm -f "$CONF"
}
trap restore EXIT

lid() { ioreg -r -k AppleClamshellState -d 1 | sed -n -E 's/.*"AppleClamshellState" = (Yes|No).*/\1/p'; }
stamp() { date '+%H:%M:%S'; }
batt() { pmset -g batt | grep -o -E "'[A-Za-z ]+'|[0-9]+%" | tr '\n' ' '; }
online() { curl -s -m 4 -o /dev/null -w '%{http_code}' http://captive.apple.com/hotspot-detect.html || true; }

echo "$(stamp) waiting up to 10 min for the lid to close"
for _ in $(seq 300); do [ "$(lid)" = Yes ] && break; sleep 2; done
[ "$(lid)" = Yes ] || { echo "FAIL: lid never closed"; exit 1; }

start=$(date +%s)
echo "PART 1: lid closed at $(stamp)"
prev=$start
while [ $(( $(date +%s) - start )) -lt 90 ]; do
  now=$(date +%s)
  echo "$(stamp) gap=$((now - prev))s lid=$(lid) $(batt)heat=$("$ROOT/build/lidawake-thermal") http=$(online)"
  prev=$now
  sleep 5
done

if [ "$(lid)" != Yes ]; then
  echo "lid opened during part 1; skipping part 2"
elif ! pmset -g batt | grep -q "'Battery Power'"; then
  echo "on mains power; skipping part 2 (the battery cut-out only applies on battery)"
else
  echo "PART 2: pretending the battery is low at $(stamp)"
  echo "LOW_BATTERY=100" >> "$CONF"
  armed=$(date +%s); prev=$armed
  while true; do
    sleep 2
    now=$(date +%s)
    if [ $((now - prev)) -gt 15 ]; then
      echo "slept at about $(date -r "$prev" '+%H:%M:%S'), woke at $(stamp) ($((now - prev))s asleep)"
      break
    fi
    prev=$now
    [ $((now - armed)) -gt 180 ] && { echo "FAIL: did not sleep within 180 s"; break; }
  done
  restore
fi

echo "--- lidawake log since the lid closed"
awk -v t="$(date -r "$start" '+%Y-%m-%d %H:%M:%S')" '($1" "$2) >= t' "$DIR/lidawake.log"
echo "--- macOS sleep/wake record since the lid closed"
pmset -g log | tail -n 3000 | awk -v t="$(date -r "$start" '+%Y-%m-%d %H:%M:%S')" \
  '($1" "$2) >= t && $4 ~ /^(Sleep|Wake|DarkWake)$/' | cut -c1-160
