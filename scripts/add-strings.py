#!/usr/bin/env python3
# Ajoute des chaînes (source française → anglais) à un catalogue .xcstrings, au format d'Xcode,
# sans réécrire le reste du fichier. Les builds en ligne de commande ne synchronisent pas le
# catalogue : chaque nouvelle clé doit être ajoutée à la main, avec « en » ET « fr ».
# Usage : scripts/add-strings.py fichier.json
#           objet JSON { "texte français": "English text" } → Localizable.xcstrings
#         scripts/add-strings.py --catalog Notchkit/Resources/InfoPlist.xcstrings fichier.json
#           objet JSON { "Clé": { "en": "...", "fr": "..." } }
import json, sys

args = sys.argv[1:]
catalog = "Notchkit/Resources/Localizable.xcstrings"
if "--catalog" in args:
    i = args.index("--catalog"); catalog = args[i + 1]; del args[i:i + 2]
entries = json.load(open(args[0], encoding="utf-8"))
text = open(catalog, encoding="utf-8").read()
existing = json.loads(text)["strings"]

def q(value): return json.dumps(value, ensure_ascii=False)

block, added, skipped = "", 0, 0
for key, value in entries.items():
    en, fr = (value["en"], value["fr"]) if isinstance(value, dict) else (value, key)
    if key in existing:
        skipped += 1
        continue
    block += f'''    {q(key)} : {{
      "localizations" : {{
        "en" : {{
          "stringUnit" : {{
            "state" : "translated",
            "value" : {q(en)}
          }}
        }},
        "fr" : {{
          "stringUnit" : {{
            "state" : "translated",
            "value" : {q(fr)}
          }}
        }}
      }}
    }},
'''
    added += 1

anchor = '  "strings" : {\n'
assert anchor in text
text = text.replace(anchor, anchor + block, 1)
json.loads(text)
open(catalog, "w", encoding="utf-8").write(text)
print(f"{catalog} : {added} ajoutée(s), {skipped} déjà présente(s)")
