#!/bin/zsh
# Generic UI loop: N times → press REFRESH → press ACTION → wait → read result → close tab.
# Prints ONE line per iteration to stdout; full snapshots go to $LOG.
#   APP=Safari REFRESH="Refresh" ACTION="Open link" N=3 ./loop.sh
set -u
cd "${0:a:h}"; [[ -x ./axmd ]] || swiftc -O axmd.swift -o axmd || exit 1
APP=${APP:-Safari} REFRESH=${REFRESH:?label to press first} ACTION=${ACTION:?label to press second}
N=${N:-3} LOG=${LOG:-axmd_loop.md} WAIT=${WAIT:-6}
idx() { ./axmd "$APP" --grep "\"$1\"" | head -1 | cut -d' ' -f1 | grep -E '^[0-9]+$'; }
waitpage() { local t=0; while (( t < WAIT*2 )); do ./axmd "$APP" --text --root webarea 2>/dev/null | grep -q ' h "' && return 0; sleep 0.5; ((t++)); done; return 1; }

LOCK=${TMPDIR:-/tmp}/axmd-loop.lock
mkdir "$LOCK" 2>/dev/null || { echo "loop already running ($LOCK)"; exit 1; }
trap 'rmdir "$LOCK"' EXIT
echo "# axmd loop $(date '+%F %T') app=$APP" > "$LOG"
for i in $(seq 1 $N); do
  r=$(idx "$REFRESH") || { echo "$i | abort: '$REFRESH' not found"; exit 2; }
  ./axmd "$APP" --press $r >/dev/null; sleep 1.5
  a=$(idx "$ACTION") || { echo "$i | abort: '$ACTION' not found"; exit 2; }
  href=$(./axmd "$APP" --urls --grep "\"$ACTION\"" | head -1 | grep -o '<.*>')
  ./axmd "$APP" --press $a >/dev/null; sleep 1; waitpage || true
  page=$(./axmd "$APP" --text --root webarea)
  printf '\n## %d %s\n```text\n%s\n```\n' $i "$href" "$page" >> "$LOG"
  echo "$i | $href | $(print -r -- "$page" | grep -m1 ' h "' | cut -d'"' -f2)"
  [[ $APP == Safari ]] && osascript -e 'tell application "Safari" to close current tab of window 1'
  sleep 1
done
echo "log: $LOG ($(( $(wc -c < "$LOG") / 4 )) tok est.)"
