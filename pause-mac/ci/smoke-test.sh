#!/bin/bash
# Runs the built app on a real Mac (GitHub's runner): checks it stays up, measures memory,
# and screenshots each screen in demo mode. Results land in ci-results/.
set -uo pipefail
cd "$(dirname "$0")/.."

APP_BIN="build/Pause.app/Contents/MacOS/Pause"
OUT="ci-results"
rm -rf "$OUT"; mkdir -p "$OUT/screenshots"
export PAUSE_DATA_DIR="$(mktemp -d)/pause-data"
FAILED=0

memory() {  # memory <pid> <label>
    local pid=$1 label=$2
    {
        echo "== $label =="
        # Physical footprint is what Activity Monitor's "Memory" column shows.
        footprint -p "$pid" 2>/dev/null | grep -iE "footprint|phys" | head -3 || true
        echo "rss_kb: $(ps -o rss= -p "$pid" | tr -d ' ')"
        echo
    } >> "$OUT/memory.txt"
}

stop() {  # stop <pid>
    kill "$1" 2>/dev/null
    for _ in 1 2 3 4 5; do kill -0 "$1" 2>/dev/null || return 0; sleep 1; done
    kill -9 "$1" 2>/dev/null
}

echo "## 1. Idle run (normal mode, 75s: covers the first save to disk)"
"$APP_BIN" > "$OUT/idle-run.log" 2>&1 &
PID=$!
sleep 5;  memory $PID "idle after 5s"
sleep 70; memory $PID "idle after 75s"
if kill -0 $PID 2>/dev/null; then echo "still running after 75s: OK"; else echo "CRASHED during idle run"; FAILED=1; fi
stop $PID

echo "## 2. Each screen, with sample data"
for scene in menu today urges settings guard block urge-logger; do
    "$APP_BIN" --demo "$scene" > "$OUT/$scene.log" 2>&1 &
    PID=$!
    sleep 7
    if kill -0 $PID 2>/dev/null; then
        screencapture -x "$OUT/screenshots/$scene.png" || echo "screenshot failed for $scene"
        memory $PID "with '$scene' open"
        echo "$scene: OK"
    else
        echo "$scene: CRASHED"; FAILED=1
    fi
    stop $PID
done

echo "## 3. Saved data"
ls -la "$PAUSE_DATA_DIR" "$PAUSE_DATA_DIR/activity" > "$OUT/data-files.txt" 2>&1
du -sh "$PAUSE_DATA_DIR" >> "$OUT/data-files.txt" 2>&1

echo "## 4. Crash reports"
mkdir -p "$OUT/crashes"
find ~/Library/Logs/DiagnosticReports -name 'Pause*' -mmin -30 -exec cp {} "$OUT/crashes/" \; 2>/dev/null
ls "$OUT/crashes"

cat "$OUT/memory.txt"
exit $FAILED
