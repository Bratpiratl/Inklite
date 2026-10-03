# Balancing-Workshop

Ein zweiter Regelsatz neben Inklite, nur zum Üben von Balancing. Er nutzt eigenen Kerncode
(`game/core/ws_*.gd`), Bots und Simulation (`game/tools/ws_*.gd`) und einen Web-Editor.
Das Spiel selbst bleibt davon unberührt.

Startpunkt: das Shop-Gerüst von Batomon Showdown (Region Jinto: Seltenheiten, Preise, Typen,
Chancen je Shop-Rang) mit Einheiten aus Hearthstone Battlegrounds (Angriff, Leben, Effekte),
Völker als Farben, Einheiten auch mehrfarbig.

## Was wo liegt

| Pfad | Inhalt | Im Repo |
| --- | --- | --- |
| `raw/` | Rohdaten beider Spiele mit Quellen (`raw/SOURCES.md`), neu laden mit `raw/fetch_raw.py` | nein |
| `mapping/jinto_bg.json` | Zuordnung Batomon-Platz zu BG-Diener, übersetzte Effekte | nein |
| `rulesets/<name>/` | Regelsatz: `ruleset.json`, `units.json`, `ghosts.json`, `changelog.jsonl`, `history/` | nein |
| `runs/<name>/<lauf>/` | Simulationsläufe: `summary.json`, `report.html`, Kopie des Stands | nein |
| `build_ruleset.py` | erzeugt einen Regelsatz aus Rohdaten und Zuordnung | ja |
| `analysis/ws_analyze.py` | Auswertung eines Logs zu `summary.json` und `report.html` | ja |
| `editor/` | Web-Editor (Python-Standardbibliothek plus statische Seite) | ja, ohne `config.local.json` |

Rohdaten, Zuordnung und Regelsätze enthalten Namen und Werte aus fremden Spielen. Das Repo ist
öffentlich, deshalb stehen diese Ordner in `.gitignore`. Nichts davon gehört ins veröffentlichte Spiel.

## Befehle (aus dem Repo-Root)

```
python3 workshop/raw/fetch_raw.py                                   # Rohdaten neu laden
python3 workshop/build_ruleset.py --force                           # Regelsatz neu erzeugen (überschreibt Editor-Stand!)
godot --headless --path game -s res://tools/ws_simulate.gd -- --ruleset workshop/rulesets/jinto_bg --runs 900 --ghosts 2
godot --headless --path game -s res://tools/ws_simulate.gd -- --ruleset workshop/rulesets/jinto_bg --mode fights --runs 5000
analysis/.venv/bin/python workshop/analysis/ws_analyze.py workshop/runs/jinto_bg/sim.jsonl --ruleset workshop/rulesets/jinto_bg
python3 workshop/editor/server.py --port 8741                       # Editor lokal
```

Tests: `game/tools/run_tests.sh` (enthält `game/test/workshop/`, ohne Daten von der Platte).

## Regeln des Regelsatzes

- **Tag**: Einkommen (`economy.income_by_day`, danach `income_growth_after` je Tag), Gold bleibt erhalten.
- **Shop**: 5 Plätze, Shop-Rang = Tag, Seltenheit nach `shop.rarity_weights_by_rank`, dann eine Einheit
  dieser Seltenheit. Kein gemeinsamer Pool. Einheiten, die man auf Höchststufe besitzt, kommen nicht mehr.
- **Preise** je Einheit, Verkauf = aufgerundet(Preis × Faktor der Stufe ÷ 2).
- **Brett**: 6 Teamplätze, 4 Bankplätze. 3 × Stufe 1 = Stufe 2, 2 × Stufe 2 = Stufe 3. Boni: stärkster bleibt.
- **Run**: 10 Leben, Niederlage kostet 1, 1, 2, 2, dann 3 Leben je Tag, eine Second Chance, Ende nach 10 Siegen.
- **Kampf** umschaltbar: `bg` (Reihe, abwechselnd links nach rechts, zufällige Ziele, Spott, Gegenschlag)
  oder `grid` (Raster 3 × 2, vordere Reihe zuerst, kein Gegenschlag, wie der Inklite-Kampf).

## Fähigkeiten

Eine Fähigkeit ist `{trigger, effect, target, ...}`. Die vollständige Liste der Bausteine steht in
`editor/validate.py` (`SCHEMA`) und im Editor unter „Hilfe“.

```json
{"trigger": "on_death", "effect": "summon", "token": "beetle", "times": 2}
{"trigger": "start_of_combat", "effect": "buff", "target": "allies_all", "only": {"color": "gruen"}, "atk": 1}
{"trigger": "on_ally_attack", "when": {"color": "gold"}, "effect": "buff", "target": "trigger_unit", "atk": 3, "hp": 1}
{"trigger": "avenge", "count": 3, "effect": "give_keyword", "target": "self", "keyword": "divine_shield"}
```

- `atk`, `hp`, `value`, `times` wachsen mit der Stufe (`board.level_scale`). Beschworene Spielsteine
  bekommen stattdessen die Stufe der Beschwörerin.
- Shop-Effekte (`on_buy`, `on_sell`, `end_of_turn`, ...) wirken dauerhaft. Kampf-Effekte nur mit `"permanent": true`.
- Passive Wirkungen (`passives`): `deathrattle_twice`, `battlecry_twice`, `end_of_turn_twice`.
- Neuer Baustein = Eintrag in `SCHEMA`, Umsetzung in `ws_combat.gd` bzw. `ws_run.gd`, Test in `game/test/workshop/`.

## Editor auf dem Server

Läuft per pm2 als `inklite-workshop` auf `127.0.0.1:8741`, öffentlich hinter nginx unter
`https://5-75-161-48.sslip.io/inklite-workshop/` (Snippet `/etc/nginx/snippets/inklite-workshop-https.conf`).
Zugang per Basic Auth, Daten in `editor/config.local.json` (wird beim ersten Start erzeugt).

```
workshop/editor/start.sh          # starten oder neu starten, kein root nötig (als root gibt es an brat ab)
pm2 logs inklite-workshop
```

Ohne öffentliche Adresse per SSH-Tunnel vom eigenen Rechner:
`ssh -N -L 8741:127.0.0.1:8741 root@5.75.161.48`, dann `http://localhost:8741/`.

## Selbst spielen

`workshop/build_play.sh [regelsatz]` baut in etwa 15 Sekunden einen Test-Build nach `workshop/play/<regelsatz>/`
(Kopie von `game/` mit `tools/ws_play.tscn` als Hauptszene und dem Regelsatz unter `res://ws_data/`).
Der Editor liefert ihn hinter dem Passwort unter `/inklite-workshop/play/<regelsatz>/` aus, Knopf unter „Simulation“.
Das öffentliche Spiel enthält die Szene nicht: dessen Export-Preset lässt `tools/` weg. Die Texte der Test-Szene
stehen bewusst fest im Code statt in `translations.csv`, weil sie nie ausgeliefert wird.

## Bekannte Grenzen

- Bots kaufen nach Preis, Verschmelzen und Farbe, nicht nach Effekten. Sie sind die Messlatte, keine Spieler.
- Batomon-Einkommen ab Tag 5 ist geschätzt (+5 je Tag), die Tage 1 bis 4 stammen aus einem beobachteten Run.
- 25 von 65 Einheiten sind gegenüber BG vereinfacht (`status` und `note` je Einheit).
- Kleine Stichproben: Legendäre Einheiten tauchen erst ab Rang 9 auf. Für Aussagen über sie 2000 Runs oder mehr nehmen.
