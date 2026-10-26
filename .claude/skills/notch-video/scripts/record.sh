#!/bin/sh
# Tourne un scénario sur la vraie encoche avec le mode démo de Notchkit (build Debug), puis convertit
# la prise en WebM VP9 avec transparence pour HyperFrames.
#
# Usage : sh record.sh <dossier-du-tournage> [en] [fr] ...
#   <dossier>/<langue>/scenario.json  →  <dossier>/<langue>/notch.mov, notch.webm, timeline.json
# Sans langue : en et fr.
set -e
ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
SHOOT="$(cd "$1" && pwd)"; shift
LANGS="${*:-en fr}"
APP="$ROOT/build.noindex/DerivedData/Build/Products/Debug/Notchkit.app/Contents/MacOS/Notchkit"
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

# Une autre instance dessinerait une seconde encoche par-dessus : on s'arrête (on ne la tue jamais).
if pgrep -f "Notchkit.app/Contents/MacOS/Notchkit" >/dev/null; then
  echo "NOTCHKIT-OUVERT : quittez Notchkit (et l'instance lancée depuis Xcode) avant le tournage." >&2
  exit 2
fi

echo "Build Debug…"
(cd "$ROOT" && xcodebuild build -project Notchkit.xcodeproj -scheme Notchkit -derivedDataPath build.noindex/DerivedData \
  -destination 'platform=macOS' -quiet)

for L in $LANGS; do
  echo "Tournage ($L)…"
  NOTCHKIT_DEMO="$SHOOT/$L/scenario.json" "$APP" -module.claude.port 52798 -AppleLanguages "($L)" 2>&1 | grep DEMO
  ffmpeg -v error -y -i "$SHOOT/$L/notch.mov" -vf fps=60 -c:v libvpx-vp9 -pix_fmt yuva420p -b:v 0 -crf 22 \
    -row-mt 1 -deadline good -cpu-used 4 -auto-alt-ref 0 "$SHOOT/$L/notch.webm"
  echo "Prise prête : $SHOOT/$L/notch.webm"
  sleep 2
done
