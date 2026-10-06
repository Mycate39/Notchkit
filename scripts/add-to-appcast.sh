#!/bin/sh
# Ajoute une version en tête de appcast.xml (liste lue par Sparkle pour les mises à jour).
# Le .dmg est signé avec la clé EdDSA privée rangée dans le trousseau (créée par generate_keys).
# Usage : scripts/add-to-appcast.sh <Notchkit-x.y.z.dmg> <chemin/Notchkit.app> <notes.md> [appcast.xml] [url du .dmg]
set -eu

DMG="$1"
APP="$2"
NOTES="$3"
APPCAST="${4:-appcast.xml}"
SPARKLE_BIN="build/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin"

INFO="$(cd "$(dirname "$APP")" && pwd)/$(basename "$APP")/Contents/Info"
VERSION=$(defaults read "$INFO" CFBundleShortVersionString)
BUILD=$(defaults read "$INFO" CFBundleVersion)
URL="${5:-https://github.com/Mycate39/Notchkit/releases/download/v$VERSION/$(basename "$DMG")}"
# Sortie : sparkle:edSignature="…" length="…"
SIGNATURE=$("$SPARKLE_BIN/sign_update" "$DMG")

python3 - "$APPCAST" "$VERSION" "$BUILD" "$URL" "$SIGNATURE" "$NOTES" <<'PY'
import sys, os, html, email.utils
appcast, version, build, url, signature, notes = sys.argv[1:]
# Notes en Markdown simple → HTML (titres, listes, gras, code).
import re
body = []
in_list = False
for line in open(notes, encoding="utf-8").read().splitlines():
    text = html.escape(line.strip())
    text = re.sub(r"\*\*(.+?)\*\*", r"<b>\1</b>", text)
    text = re.sub(r"`(.+?)`", r"<code>\1</code>", text)
    if text.startswith("- "):
        if not in_list: body.append("<ul>"); in_list = True
        body.append(f"<li>{text[2:]}</li>")
        continue
    if in_list: body.append("</ul>"); in_list = False
    if text.startswith("## "): body.append(f"<h3>{text[3:]}</h3>")
    elif text: body.append(f"<p>{text}</p>")
if in_list: body.append("</ul>")
item = f"""    <item>
      <title>Notchkit {version}</title>
      <pubDate>{email.utils.formatdate(usegmt=True)}</pubDate>
      <sparkle:version>{build}</sparkle:version>
      <sparkle:shortVersionString>{version}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <description><![CDATA[{"".join(body)}]]></description>
      <enclosure url="{url}" {signature} type="application/octet-stream"/>
    </item>
"""
if os.path.exists(appcast):
    text = open(appcast, encoding="utf-8").read()
    marker = "<title>Notchkit</title>\n"
    text = text.replace(marker, marker + item, 1)
else:
    text = f"""<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Notchkit</title>
{item}  </channel>
</rss>
"""
open(appcast, "w", encoding="utf-8").write(text)
PY
echo "appcast : $VERSION ($BUILD) → $URL"
