#!/bin/sh
# Stress test du build Debug (200 dépliages/repliages) : affiche STRESS-OK ou ECHEC.
# N'arrête que l'instance de test qu'il a lancée.
LOG="${TMPDIR:-/tmp}/notchkit-stress.log"
NOTCHKIT_STRESS=1 build.noindex/DerivedData/Build/Products/Debug/Notchkit.app/Contents/MacOS/Notchkit -module.claude.port 52799 > "$LOG" 2>&1 &
PID=$!
for _ in $(seq 1 60); do
    grep -q "STRESS-OK" "$LOG" && break
    kill -0 $PID 2>/dev/null || break
    sleep 5
done
grep -q "STRESS-OK" "$LOG" && echo STRESS-OK || echo ECHEC
kill $PID 2>/dev/null
