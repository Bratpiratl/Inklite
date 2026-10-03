#!/usr/bin/env python3
"""Legt eine bereinigte Kopie eines Regelsatzes nach workshop/public/<name>/ für den öffentlichen Test-Build.

Aufruf: python3 workshop/export_public.py [regelsatz]   (Standard: jinto_bg)

Entfernt alles, was Namen oder Texte aus fremden Spielen enthält: "ref" (BG-Name, BG-Kartentext,
Batomon-Platz) und "note" (Vereinfachungen mit BG-Begriffen). Übrig bleiben eigene Platzhalternamen, Zahlen und die eigenen
Fähigkeits-Definitionen. Danach committen und pushen: die Pages-Action baut den Test-Build
nach /Inklite/workshop/.
"""
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parent
FORBIDDEN = ("bg_name", "bg_text", "slot_name", "slot_id", "bg_id", "Blutjuwel", "BG-", "Batomon", "Hearthstone")


def main():
    name = sys.argv[1] if len(sys.argv) > 1 else "jinto_bg"
    src = HERE / "rulesets" / name
    dst = HERE / "public" / name
    dst.mkdir(parents=True, exist_ok=True)

    ruleset = json.loads((src / "ruleset.json").read_text())
    ruleset["meta"] = {"name": "Workshop-Test", "version": ruleset.get("meta", {}).get("version", 1),
                       "notes": "Bereinigte Kopie aus workshop/export_public.py"}
    units = json.loads((src / "units.json").read_text())
    for u in units.get("units", []) + units.get("tokens", []):
        u.pop("ref", None)
        u.pop("note", None)
    ghosts = json.loads((src / "ghosts.json").read_text()) if (src / "ghosts.json").exists() else {"teams": []}

    out = {"ruleset.json": ruleset, "units.json": units, "ghosts.json": {"teams": ghosts.get("teams", [])}}
    for file, data in out.items():
        text = json.dumps(data, ensure_ascii=False, separators=(",", ":"))
        for word in FORBIDDEN:
            if word in text:
                sys.exit(f"Abbruch: {file} enthält noch {word}")
        (dst / file).write_text(text + "\n", encoding="utf-8")
    size = sum((dst / f).stat().st_size for f in out) // 1024
    print(f"{dst}: {len(units['units'])} Einheiten, {len(out['ghosts.json']['teams'])} Geisterteams, {size} KB")


if __name__ == "__main__":
    main()
