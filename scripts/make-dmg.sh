#!/bin/sh
# Crée l'image disque de distribution : Notchkit.app et un raccourci vers Applications,
# pour l'installation par glisser-déposer.
# Usage : scripts/make-dmg.sh <chemin/Notchkit.app> <dossier de sortie>
set -eu

APP="$1"
OUT_DIR="$2"
VERSION=$(defaults read "$(cd "$(dirname "$APP")" && pwd)/$(basename "$APP")/Contents/Info" CFBundleShortVersionString)
NAME="Notchkit-$VERSION"
STAGING=$(mktemp -d)
trap 'rm -rf "$STAGING"' EXIT

ditto "$APP" "$STAGING/Notchkit.app"
ln -s /Applications "$STAGING/Applications"

rm -f "$OUT_DIR/$NAME.dmg"
hdiutil create -volname "Notchkit $VERSION" -srcfolder "$STAGING" -fs HFS+ -format UDZO \
    -imagekey zlib-level=9 -ov "$OUT_DIR/$NAME.dmg" >/dev/null
echo "$OUT_DIR/$NAME.dmg"
