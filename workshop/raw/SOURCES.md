# Rohdaten für den Balancing-Workshop

Stand: 03.10.2026. Neu laden mit `python3 workshop/raw/fetch_raw.py`.

Dieser Ordner ist per `.git/info/exclude` vom Repo ausgenommen, weil das Repo öffentlich ist.
Namen, Kartentexte und Werte gehören Blizzard bzw. berrymint. Nur für private Analyse, nicht ins Spiel.

## Dateien

| Datei | Inhalt | Quelle | Verlässlichkeit |
| --- | --- | --- | --- |
| battlegrounds/minions.json | 303 Diener im BG-Pool: Stufe, Angriff, Leben, Völker, Schlüsselwörter, Text, goldene Werte, Flags `duos_only` und `rotated_out` | HearthstoneJSON (aus den Spieldateien, Stand 01.10.2026) | hoch |
| battlegrounds/tavern_spells.json | 76 Tavernenzauber | HearthstoneJSON | hoch |
| battlegrounds/stats_mmr100.json | Durchschnittsplatz je Diener, gesamt und je Runde, aktueller Patch, alle Spieler (rund 87.000 Partien) | Firestone (öffentliches CDN) | hoch, aber nur Firestone-Nutzer |
| battlegrounds/stats_mmr50.json | dasselbe für die obere Hälfte nach MMR | Firestone | hoch |
| battlegrounds/rules.json | Wirtschaft, Shop, Pool, Kampf, je Wert mit Quelle | Hearthstone-Wiki, Patchnotes 36.6 | siehe je Wert |
| batomon/monsters_index.json | 136 Batomon: Seltenheit, Preis, Typen, Region, Fähigkeit auf Stufe 1 | batomon.com (Community-Seite, Daten aus Steam-Build 25600878, Balance 24) | hoch |
| batomon/rules.json | Shop-Ränge mit Seltenheitschancen, Reroll, Verkaufsformel, Leben, Board, Kampf, je Wert mit Quelle | batomon.com, offizielle Steam-Patchnotes | siehe je Wert |
| batomon/patch_notes.txt | Alle 38 offiziellen Ankündigungen seit der Demo, mit Begründung des Entwicklers zu jeder Balance-Änderung | Steam-News-API | hoch |

Aktiver BG-Pool im Solo-Modus: `duos_only == false` und `rotated_out == false` (253 Diener, davon 12 auf Stufe 7).

## Wichtigste Erkenntnisse

1. **Batomon kämpft ganz anders als BG.** Echtzeit mit Abklingzeiten, ein gemeinsamer HP-Pool je Team,
   6 Plätze im Raster 3 × 2, kein Angriff und kein Leben je Monster. Die BG-Diener (Angriff und Leben)
   passen deshalb nur zum BG-Kampf. Für den Batomon-Shop ist das egal, er funktioniert mit beiden.
2. **Die Shops unterscheiden sich grundlegend.**
   - BG: gemeinsamer Pool mit begrenzten Kopien, Tavernenstufe selbst kaufen, alles kostet 3 Gold, Gold 3 bis 10 und verfällt.
   - Batomon: kein gemeinsamer Pool, der Shop-Rang steigt automatisch um 1 pro Tag und bestimmt die Chancen auf 5 Seltenheiten
     (vollständige Tabelle Rang 1 bis 14+ in batomon/rules.json), Preis je Monster zwischen 10 und 60, Reroll 3.
3. **BG hat 6 Stufen (plus 7), Batomon 5 Seltenheiten.** Für die Zuordnung siehe offene Entscheidungen.
4. **Mehrfarbigkeit gibt es in beiden Spielen**: 46 von 136 Batomon haben zwei Typen, in BG nur 9 Diener
   (dazu 6 mit allen Völkern). Neu verteilte Farben können also deutlich mehr Doppelungen bekommen als BG.
5. **Echte Spielerdaten als Vergleich**: Für 250 der 253 aktiven Diener gibt es den Durchschnittsplatz.
   Damit lässt sich prüfen, ob die eigene Simulation dieselben Diener stark findet wie echte Spieler.
6. **Die Batomon-Patchnotes sind Lernmaterial**: Der Entwickler begründet fast jede Änderung mit Zahlen,
   z. B. „median DPS of Jinto teams almost 2 times higher than Pantra teams at days 10+“.

## Was fehlt

| Wert | Warum offen | Wie wir ihn bekommen |
| --- | --- | --- |
| Batomon: Gold pro Tag (Grundeinkommen) | nirgends öffentlich | Im Spiel über dem $-Betrag im Shop: Tooltip zeigt das Einkommen pro Tag |
| Batomon: Startgold | nur ein unbelegtes Fan-Wiki ($30) | Im Spiel an Tag 1 ablesen |
| Batomon: Team-HP pro Tag | nicht öffentlich, mehrfach geändert | Nur nötig, wenn wir den Batomon-Kampf nachbauen |
| BG: Tavernen-Aufstiegskosten | Wiki nennt 5, 7, 8, 11, 11, ohne Beleg | Für den Workshop unwichtig, da Batomon-Shop |
| BG: Schadensgrenze in frühen Runden | nur Presseberichte von 2025 | Unwichtig bei Batomon-Run mit Leben |

## Quellen

- HearthstoneJSON: https://api.hearthstonejson.com/v1/latest/enUS/cards.json
- Hearthstone-Wiki: https://hearthstone.wiki.gg/wiki/Battlegrounds, /Battlegrounds/Tavern_Tier, /Battlegrounds/Gold
- Patchnotes 36.6 (Aberrations, Naga raus): https://hearthstone.blizzard.com/en-us/news/24294373/updated-9292026-366-patch-notes
- Firestone-Statistiken: https://static.zerotoheroes.com/api/bgs/card-stats/mmr-100/last-patch/overview-from-hourly.gz.json
- Batomon-Daten: https://batomon.com/mechanics/monster-pool, /how-to-play, /mechanics/*, /batomon
- Batomon-Patchnotes: https://store.steampowered.com/news/app/4557380
- Batomon-Spielerdiskussionen: https://steamcommunity.com/app/4557380/discussions/

Bewusst nicht genutzt: die vielen Fan-Wikis (batomonshowdown.org, -game.wiki, .site usw.). Sie widersprechen sich
(z. B. 1 oder 3 Gratis-Rerolls pro Tag) und nennen selten Quellen. batomon.com dagegen gibt den Spiel-Build an.
