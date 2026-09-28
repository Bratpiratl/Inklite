"""Baut die kleinen Umlaute ä, ö, ü in Kenney Mini nach.

Kenney Mini zeichnet ä, ö, ü mit den Formen der großen Umlaute. Dieses Skript setzt die Glyphen
neu zusammen: Umriss von a, o, u plus die beiden Punkte aus Ä, Ö, Ü, so verschoben, dass sie mit
gleichem Abstand über dem Kleinbuchstaben sitzen. Kenney Mini ist CC0, Änderungen sind erlaubt.

Aufruf (aus dem Repo-Root, braucht fontTools, z. B. aus analysis/.venv):
    analysis/.venv/bin/python scripts/patch_font_umlauts.py <Kenney Mini.ttf> game/assets/fonts/kenney_mini.ttf
"""

import sys

from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.ttLib import TTFont

PAIRS = [("a", "A", 0xE4, 0xC4), ("o", "O", 0xF6, 0xD6), ("u", "U", 0xFC, 0xDC)]


def contours(glyph, glyf):
    """Liste von Konturen als Punktlisten (x, y, on_curve)."""
    coords, ends, flags = glyph.getCoordinates(glyf)
    result, start = [], 0
    for end in ends:
        result.append([(coords[i][0], coords[i][1], flags[i] & 1) for i in range(start, end + 1)])
        start = end + 1
    return result


def draw(pen, contour, dx=0, dy=0):
    pen.moveTo((contour[0][0] + dx, contour[0][1] + dy))
    for x, y, _ in contour[1:]:
        pen.lineTo((x + dx, y + dy))
    pen.closePath()


def main(src, dst):
    font = TTFont(src)
    glyf = font["glyf"]
    cmap = font.getBestCmap()
    for lower, upper, lower_uml, upper_uml in PAIRS:
        base = glyf[cmap[ord(lower)]]
        base_upper = glyf[cmap[ord(upper)]]
        umlaut_upper = glyf[cmap[upper_uml]]
        base.recalcBounds(glyf)
        base_upper.recalcBounds(glyf)
        cap_top = base_upper.yMax
        # Punkte = Konturen des großen Umlauts, die ganz über dem Großbuchstaben liegen.
        dots = [c for c in contours(umlaut_upper, glyf) if min(p[1] for p in c) >= cap_top]
        if len(dots) != 2:
            raise SystemExit(f"{upper_uml:x}: {len(dots)} Punkt-Konturen gefunden statt 2")
        dy = base.yMax - cap_top
        dx = round(((base.xMin + base.xMax) - (base_upper.xMin + base_upper.xMax)) / 2)
        pen = TTGlyphPen(None)
        for contour in contours(base, glyf):
            draw(pen, contour)
        for dot in dots:
            draw(pen, dot, dx, dy)
        name = cmap[lower_uml]
        glyf[name] = pen.glyph()
        font["hmtx"][name] = font["hmtx"][cmap[ord(lower)]]
    font.save(dst)
    print(f"Geschrieben: {dst}")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
