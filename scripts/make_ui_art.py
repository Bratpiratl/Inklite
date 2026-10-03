#!/usr/bin/env python3
"""Erzeugt die eigenen UI-Grafiken in game/assets/ui/bato/ (Knöpfe, Panels, Felder, Symbole).

Alles ist eigene Pixel-Art (CC0), hier als Code beschrieben, damit Farben und Größen
nachvollziehbar bleiben. Neu erzeugen: python3 scripts/make_ui_art.py
"""
from pathlib import Path

from PIL import Image

OUT = Path(__file__).resolve().parent.parent / "game" / "assets" / "ui" / "bato"

OUTLINE = (31, 27, 42, 255)
CLEAR = (0, 0, 0, 0)


def hex_color(value: str) -> tuple:
    value = value.lstrip("#")
    return tuple(int(value[i:i + 2], 16) for i in (0, 2, 4)) + (255,)


def button(fill: str, light: str, shade: str, pressed: bool) -> Image.Image:
    """Dicker Knopf: dunkle Kontur, heller Rand oben, dunkle Kante unten (5 Pixel, gedrückt 2)."""
    w, h = 12, 20
    img = Image.new("RGBA", (w, h), CLEAR)
    top = 3 if pressed else 0
    band = 2 if pressed else 5
    f, l, s = hex_color(fill), hex_color(light), hex_color(shade)
    for y in range(top, h):
        for x in range(w):
            edge_x = x in (0, w - 1)
            if y == top or y == h - 1 or edge_x:
                color = OUTLINE
            elif y <= top + 2:
                color = l
            elif y >= h - 1 - band:
                color = s
            else:
                color = f
            img.putpixel((x, y), color)
    for x, y in ((0, top), (w - 1, top), (0, h - 1), (w - 1, h - 1)):
        img.putpixel((x, y), CLEAR)
    return img


def framed(size: int, layers: list, corner_clear: int = 1) -> Image.Image:
    """Quadrat aus Ringen von außen nach innen, der letzte Eintrag füllt die Mitte."""
    img = Image.new("RGBA", (size, size), CLEAR)
    for y in range(size):
        for x in range(size):
            ring = min(x, y, size - 1 - x, size - 1 - y)
            img.putpixel((x, y), hex_color(layers[min(ring, len(layers) - 1)]))
    for i in range(corner_clear):
        for x, y in ((i, 0), (0, i), (size - 1 - i, 0), (size - 1, i),
                     (i, size - 1), (0, size - 1 - i), (size - 1 - i, size - 1), (size - 1, size - 1 - i)):
            img.putpixel((x, y), CLEAR)
    return img


def slot(fill: str, border: str, shade: str) -> Image.Image:
    """Feld im Team: runde Ecken, Rand, unten etwas dunkler."""
    size = 10
    img = framed(size, [border, border, fill])
    for x in range(1, size - 1):
        img.putpixel((x, size - 2), hex_color(shade))
    return img


def icon(rows: list, palette: dict) -> Image.Image:
    img = Image.new("RGBA", (len(rows[0]), len(rows)), CLEAR)
    for y, row in enumerate(rows):
        for x, key in enumerate(row):
            if key != ".":
                img.putpixel((x, y), hex_color(palette[key]))
    return img


HEART = [
    ".kk...kk.",
    "krrk.krrk",
    "krwrkrrrk",
    "krrrrrrrk",
    "krrrrrrdk",
    ".krrrrdk.",
    "..krrdk..",
    "...kdk...",
    "....k....",
]
TROPHY = [
    "kkkkkkkkkkk",
    "kywyyyyyydk",
    "kywyyyyyydk",
    ".kyyyyyydk.",
    ".kyyyyyydk.",
    "..kyyyydk..",
    "...kyydk...",
    "....kdk....",
    "...kyydk...",
    "..kkkkkkk..",
]
COIN = [
    "..kkkkk..",
    ".kwyyyyk.",
    "kwyydyyyk",
    "kyyydyydk",
    "kyyydyydk",
    "kyyydyydk",
    "kyyyyyddk",
    ".kyyddddk",
    "..kkkkk..",
]
GEAR = [
    "....kkk....",
    ".kk.kwk.kk.",
    ".kwkkwkkwk.",
    "..kwwwwwk..",
    "kkkwkkkwkkk",
    "kwwwk.kwwwk",
    "kkkwkkkwkkk",
    "..kwwwwwk..",
    ".kwkkwkkwk.",
    ".kk.kwk.kk.",
    "....kkk....",
]
PALETTE = {"k": "#1f1b2a", "r": "#ef3e55", "d": "#a8243b", "w": "#ffffff", "y": "#ffc62a"}
COIN_PALETTE = dict(PALETTE, d="#d98a12")
TROPHY_PALETTE = dict(PALETTE, d="#d98a12")
GEAR_PALETTE = dict(PALETTE, w="#e8e8f0")


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    buttons = {
        "white": ("#ffffff", "#ffffff", "#c9c7d6"),
        "yellow": ("#ffc62a", "#ffe27e", "#f0901e"),
        "red": ("#ec4660", "#ff8796", "#b02a44"),
        "blue": ("#4fb6f0", "#a2dcff", "#2a7fc0"),
        "grey": ("#a9a7b8", "#c4c2d0", "#7c7a90"),
    }
    for name, colors in buttons.items():
        button(*colors, pressed=False).save(OUT / f"btn_{name}.png")
        button(*colors, pressed=True).save(OUT / f"btn_{name}_pressed.png")
    framed(10, ["#1f1b2a", "#ffffff", "#ffffff", "#d3d2df", "#ffffff"]).save(OUT / "panel_white.png")
    framed(10, ["#12101a", "#4b4766", "#2a2638"]).save(OUT / "panel_dark.png")
    slot("#ffffff", "#c3c2d0", "#e6e5ee").save(OUT / "slot.png")
    icon(HEART, PALETTE).save(OUT / "icon_heart.png")
    icon(TROPHY, TROPHY_PALETTE).save(OUT / "icon_trophy.png")
    icon(COIN, COIN_PALETTE).save(OUT / "icon_coin.png")
    icon(GEAR, GEAR_PALETTE).save(OUT / "icon_gear.png")
    print("geschrieben nach", OUT)


if __name__ == "__main__":
    main()
