#!/usr/bin/env python3
"""Platzhalter-Sprites für den Workshop-Test: jede Einheit bekommt ein Tiny-Creatures-Bild.

Ausgewählt wird nach Farbe: Die erste Farbe der Einheit wird mit der Durchschnittsfarbe der Bilder
verglichen, das ähnlichste freie Bild gewinnt. Ergebnis:
  game/assets/sprites/workshop/<id>.png  (schwarzer Rand transparent, wie bei den Monstern)
  game/tools/ws_play_sprites.json         (id -> Pfad unter assets/sprites/)
Eigene Bilder: einfach die PNG-Datei mit gleichem Namen ersetzen oder den Pfad in der JSON ändern.
Neu erzeugen: python3 scripts/make_ws_sprites.py [units.json]
Vorhandene Einträge in der JSON bleiben erhalten, nur neue Einheiten bekommen ein Bild.
"""
import json
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
TILES = ROOT / "game/assets/packs/tiny_creatures/Tiles"
OUT = ROOT / "game/assets/sprites/workshop"
MAPPING = ROOT / "game/tools/ws_play_sprites.json"
UNITS = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "workshop/public/jinto_bg/units.json"

# Tiere und Monster, keine Menschen und keine winzigen Bilder. Die 12 Monster des Hauptspiels fehlen.
POOL = [
    1, 2, 3, 4, 6, 8, 9, 11, 12, 14, 24, 25, 26, 27, 31, 32, 33, 35, 39, 40, 41, 42, 43, 44, 46, 48,
    49, 50, 54, 55, 61, 62, 63, 64, 65, 69, 70, 76, 77, 78, 79, 80, 81, 90, 91, 92, 93, 94, 95, 96,
    97, 99, 100, 101, 102, 104, 105, 106, 107, 109, 111, 112, 113, 115, 116, 118, 120, 121, 122,
    123, 124, 125, 126, 127, 129, 131, 132, 133, 134, 135, 136, 137, 138, 140, 141, 142, 143, 144,
    145, 146, 147, 149, 151, 152, 153, 155, 156, 157, 159, 160, 161, 162, 163, 164, 165, 166, 167,
    170, 171, 172, 173, 175, 176, 178, 179, 180,
]
# Spielsteine mit naheliegendem Bild.
TOKENS = {"beetle": 144, "microbot": 83, "skeleton": 2, "tentacle": 9, "wasserling": 46,
          "eternal_knight": 19, "turtle": 149, "sewer_rat": 178}


def tile_path(number: int) -> Path:
    return TILES / f"tile_{number:04d}.png"


def transparent(img: Image.Image) -> Image.Image:
    """Schwarz, das mit dem Rand verbunden ist, wird durchsichtig (Flutfüllung von außen)."""
    img = img.convert("RGBA")
    w, h = img.size
    px = img.load()
    stack = [(x, y) for x in range(w) for y in (0, h - 1)] + [(x, y) for x in (0, w - 1) for y in range(h)]
    seen = set()
    while stack:
        x, y = stack.pop()
        if (x, y) in seen or not (0 <= x < w and 0 <= y < h):
            continue
        seen.add((x, y))
        r, g, b, a = px[x, y]
        if a == 0 or (r, g, b) == (0, 0, 0):
            px[x, y] = (0, 0, 0, 0)
            stack += [(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)]
    return img


def mean_color(img: Image.Image) -> tuple:
    """Durchschnitt der farbigen Pixel ohne die dunkle Kontur."""
    pixels = [p[:3] for p in img.getdata() if p[3] > 0 and sum(p[:3]) > 120]
    if not pixels:
        return (0, 0, 0)
    return tuple(sum(c[i] for c in pixels) / len(pixels) for i in range(3))


def hex_rgb(value: str) -> tuple:
    value = value.lstrip("#")
    return tuple(int(value[i:i + 2], 16) for i in (0, 2, 4))


def main() -> None:
    data = json.loads(UNITS.read_text(encoding="utf-8"))
    rules = json.loads((UNITS.parent / "ruleset.json").read_text(encoding="utf-8"))
    hexes = {c["id"]: hex_rgb(c["hex"]) for c in rules.get("colors", [])}
    mapping = json.loads(MAPPING.read_text(encoding="utf-8")) if MAPPING.exists() else {}
    used = {int(Path(p).stem.split("_")[-1]) for p in mapping.values() if Path(p).stem.startswith("tile_")}
    OUT.mkdir(parents=True, exist_ok=True)
    images = {n: transparent(Image.open(tile_path(n))) for n in set(POOL) | set(TOKENS.values())}
    colors = {n: mean_color(img) for n, img in images.items()}
    free = [n for n in POOL if n not in TOKENS.values()]

    def assign(unit_id: str, number: int) -> None:
        images[number].save(OUT / f"{unit_id}.png")
        mapping[unit_id] = f"workshop/{unit_id}.png"

    for token in data.get("tokens", []):
        if token["id"] not in mapping and token["id"] in TOKENS:
            assign(token["id"], TOKENS[token["id"]])
    for unit in data.get("units", []) + data.get("tokens", []):
        if unit["id"] in mapping:
            continue
        target = hexes.get((unit.get("colors") or ["grau"])[0], (140, 140, 140))
        choices = [n for n in free if n not in used] or free
        best = min(choices, key=lambda n: sum((colors[n][i] - target[i]) ** 2 for i in range(3)))
        used.add(best)
        assign(unit["id"], best)
    MAPPING.write_text(json.dumps(mapping, indent=1, ensure_ascii=False, sort_keys=True) + "\n", encoding="utf-8")
    print(f"{len(mapping)} Einheiten zugeordnet, Bilder in {OUT}")


if __name__ == "__main__":
    main()
