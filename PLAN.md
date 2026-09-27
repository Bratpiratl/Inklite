# Inklite: Umsetzungsplan

Stand: 27.09.2026

## 1. Spielkonzept

Ein asynchroner Monster-Autobattler im Hochformat: Monster im Shop kaufen, auf einem 3x3-Raster aufstellen, gleiche verschmelzen und automatisch gegen gespeicherte Teams anderer Spieler kämpfen lassen.

Spielschleife pro Runde: Shop (kaufen, verkaufen, neu würfeln) -> Aufstellung (3x3-Raster, 3 gleiche verschmelzen) -> Kampf (automatisch gegen gespeichertes Gegnerteam) -> Ergebnis (Sieg +1 Trophäe, Niederlage -1 Leben) -> nächste Runde. Der Run endet nach 10 Siegen oder bei 0 Leben. Jede Runde bringt mehr Gold und stärkere Gegner. Jeder Run schreibt ein Log fürs Balancing.

### Vorbilder

| Spiel | Was wir übernehmen |
| --- | --- |
| Batomon Showdown | Monster sammeln, Trainer mit Spezialfähigkeit, Items und Trinkets, asynchrones PvP ohne Rundentimer, Run endet nach 10 Siegen |
| Tiny Auto Knights | 3x3-Raster, Position bestimmt die Reihenfolge von Angriffen und Fähigkeiten, gleiche Helden verschmelzen, Statuseffekte wie Rüstung, Gift und Frost |

### MVP-Umfang (Version 0.1)

- 12 eigene Monster in 4 Typen, 3 Seltenheiten
- Verschmelzen: 3 gleiche ergeben Stufe 2, drei Stufe-2-Monster ergeben Stufe 3
- 3x3-Raster, die vordere Reihe wird zuerst angegriffen
- 2 Statuseffekte (Gift, Schild), 6 Trinkets, 2 Trainer
- Gegner: vorab simulierte Geisterteams aus einer JSON-Datei, echtes PvP erst später
- Offline spielbar, Spielstand lokal gespeichert

Eigene Namen und eigene Designs, keine Anlehnung an Pokémon- oder Batomon-Figuren.

## 2. Tech-Stack und Workflow

| Baustein | Wahl | Warum |
| --- | --- | --- |
| Engine | Godot 4, aktuelle stabile Version fest pinnen | kostenlos, stark in 2D, eingebauter Web- und PWA-Export |
| Sprache | GDScript, kein C# | C#-Projekte lassen sich in Godot 4 nicht fürs Web exportieren |
| Code | GitHub-Repo | Claude Code arbeitet direkt darauf |
| Build | GitHub Actions, Godot headless | Vorlagen: github.com/rkoning/godot-web-test, github.com/abarichello/godot-ci |
| Hosting | GitHub Pages | kostenlos und mit HTTPS, das eine PWA braucht |
| Tests | GdUnit4 plus eigene Kampfsimulation | github.com/Randroids-Dojo/Godot-Claude-Skills als Hilfe |

Szenen (.tscn) und Skripte (.gd) sind Textdateien, die Claude Code direkt schreibt. Der Godot-Editor ist optional.

Ablauf pro Feature:
1. Aufgabe in Claude Code beschreiben.
2. Claude Code ändert Code, startet Godot headless für Tests und Simulation.
3. Push auf main: Action exportiert den Web-Build und deployt nach Pages.
4. Am Handy neu laden oder installierte App neu öffnen.

Web-Export single-threaded lassen (Standard seit Godot 4.3, braucht keine COOP/COEP-Header, läuft besser auf iOS, GitHub Pages kann diese Header nicht setzen).

## 3. Hochkant-Layout und PWA

```ini
[display]
window/size/viewport_width=360
window/size/viewport_height=640
window/handheld/orientation=1            ; Portrait
window/stretch/mode="canvas_items"
window/stretch/aspect="expand"

[rendering]
renderer/rendering_method="gl_compatibility"   ; nötig für WebGL 2
textures/canvas_textures/default_texture_filter=0   ; Nearest
2d/snap/snap_2d_transforms_to_pixel=true
```

- canvas_items statt viewport, damit Tweens und Partikel flüssig bleiben
- expand, damit jedes Seitenverhältnis ohne Balken gefüllt wird
- 16-Pixel-Sprites 3-fach skaliert (48 x 48)

Layout-Regeln:
- Oben: Leben, Trophäen, Gold, Runde
- Mitte: Gegner oben, eigenes 3x3-Raster unten
- Unten (Daumenbereich): Shop-Leiste, Buttons Neu würfeln und Kampf starten
- Touch-Ziele mindestens 48 x 48, UI nur aus Containern mit Ankern
- Safe Area über DisplayServer.get_display_safe_area() freihalten
- Querformat nicht sperren, sondern Hinweis "Bitte drehen" zeigen
- Sound erst nach dem ersten Tippen starten

PWA: Im Web-Export-Preset Progressive Web App aktivieren, Orientierung Portrait, Anzeige Fullscreen oder Standalone, Icons 144/180/512. Installation auf Android nur von echter Adresse, also über GitHub Pages testen.

## 4. Architektur

Spiellogik ist reiner GDScript-Code ohne Grafik mit festem Zufalls-Seed. Die Kampfsimulation liefert eine Ereignisliste, die Grafik spielt sie ab. Derselbe Code läuft am Handy und headless für 10.000 Kämpfe.

```text
game/
  project.godot
  data/                 alle Werte, nie im Code
    monsters.json
    trinkets.json
    trainers.json
    balance.json        Gold pro Runde, Shop-Chancen, Gegner-Skalierung
    ghost_teams.json    vorab simulierte Gegnerteams
  core/                 reine Logik, keine Nodes
    rng.gd  combat_sim.gd  effects.gd  shop.gd  run_state.gd
  ui/                   Szenen, nur Darstellung
    main.tscn  shop.tscn  board.tscn  battle_view.tscn  hud.tscn
  telemetry/logger.gd   schreibt JSON Lines
  tools/simulate.gd     headless: tausende Runs mit Bots
  assets/  sprites/ ui/ fonts/ audio/ CREDITS.md
  test/                 GdUnit4-Tests
analysis/analyze.py     Auswertung der Logs
.github/workflows/deploy.yml
CLAUDE.md
PLAN.md
```

Datenformat eines Monsters:

```json
{
  "id": "ember_pup",
  "name": "Glutwelpe",
  "type": "feuer",
  "rarity": 1,
  "cost": 3,
  "sprite": "creatures/ember_pup.png",
  "levels": [
    {"hp": 6,  "atk": 2, "ability": {"trigger": "on_attack", "effect": "poison", "value": 1}},
    {"hp": 12, "atk": 4, "ability": {"trigger": "on_attack", "effect": "poison", "value": 2}},
    {"hp": 24, "atk": 8, "ability": {"trigger": "on_attack", "effect": "poison", "value": 4}}
  ]
}
```

Fähigkeiten = Auslöser (Kampfstart, beim Angriff, beim Tod, Rundenende) + Effekt. Neue Monster meist ohne neuen Code.

Kampfregeln: rundenbasiert in Ticks, feste Reihenfolge nach Rasterposition, jeder Zufall über rng.gd, Grafik liest nur die Ereignisliste.

Asynchrones PvP später: Teamstände pro Runde auf kleinem Backend speichern, Gegner nach Runde und Siegen ziehen. Da der Kampf deterministisch ist, reicht es, Teams zu speichern.

## 5. Assets (alle CC0)

| Pack | Inhalt | Link |
| --- | --- | --- |
| Tiny Creatures (Clint Bellanger) | 180 Sprites, 16 x 16, über 100 Monster, über 50 Tiere | https://clintbellanger.itch.io/tiny-creatures |
| Tiny Dungeon (Kenney) | über 130 Sprites: Helden, Items, Kacheln | https://kenney-assets.itch.io/tiny-dungeon |
| Tiny Battle (Kenney) | über 180 Sprites im gleichen Stil | https://kenney.nl/assets |
| Pixel UI Pack (Kenney) | 750 UI-Elemente | https://kenney.nl/assets/pixel-ui-pack |
| Pattern Pixel Pack (Kenney) | über 50 Hintergrundmuster | https://kenney-assets.itch.io/pattern-pixel-pack |
| Kenney Sounds und Fonts | UI- und RPG-Sounds, Pixel-Schriften | https://opengameart.org/content/all-cc0-uploader-kenney |
| 16-bit RPG Music (HydroGene) | 28 Stücke im SNES-Stil | https://itch.io/game-assets/assets-cc0/tag-pixel-art |

Regeln: nur CC0 oder CC-BY, alles in assets/CREDITS.md eintragen, Lizenz auf der Seite prüfen, einheitlicher 16x16-Stil, ganzzahlig skalieren, Animationen per Tween.

## 6. Balancing

Bots simulieren tausende Runs headless, echte Runs loggen dieselben Ereignisse, jede Änderung an balance.json wird vorher und nachher gemessen.

Bots: Zufallsbot (Untergrenze), Gierbot (kauft teuerstes, verschmilzt sofort), Synergiebot (ein Typ, ein Trainer). Die Bot-Teams füllen ghost_teams.json.

| Kennzahl | Frage | Warnsignal (Startwert) |
| --- | --- | --- |
| Kampf-Winrate mit Monster X, je Runde | Ist X zu stark? | über 60 % oder unter 40 % |
| Pick-Rate (gekauft / angeboten) | Will jemand X? | unter 10 % oder über 50 % |
| Siege pro Run je Trainer | Sind Trainer fair? | Abstand zum Schnitt über 1 Sieg |
| Verteilung Siege pro Run | Ist die Kurve gut? | Spitze bei einer Runde = Wand |
| Kampfdauer | Kurzweilig? | länger als 40 Sekunden |
| Anteil Unentschieden | Zu defensiv? | über 10 % |

Winrates immer nach Runde trennen (Selektionseffekt).

Log-Format (JSON Lines):

```json
{"run":"a81f","v":"0.1.3","round":4,"ev":"shop","offered":["ember_pup","moss_toad","bolt_bat"],"bought":"moss_toad","gold":2}
{"run":"a81f","v":"0.1.3","round":4,"ev":"battle","seed":99121,"team":["moss_toad:2","ember_pup:1"],"enemy":"ghost_207","result":"win","ticks":17}
{"run":"a81f","v":"0.1.3","ev":"run_end","trainer":"koch","wins":7,"lives":0}
```

Balance-Runde: Wert ändern -> simulate.gd mit 10.000 Runs -> analyze.py erzeugt Bericht -> Vorhersage mit Ergebnis vergleichen -> mit echten Spielern gegenprüfen.

## 7. Meilensteine

### M0: Gerüst und Deployment
Fertig, wenn eine leere Hochkant-Szene unter der GitHub-Pages-Adresse läuft und sich am Handy installieren lässt.

Prompt:
> Lege ein Godot-4-Projekt im Ordner game/ an, nach den Regeln in CLAUDE.md. Setze die Projekteinstellungen für Hochformat 360x640, canvas_items, expand, Nearest-Filter, gl_compatibility. Erstelle ein Web-Export-Preset mit aktivierter PWA, Orientierung Portrait, single-threaded. Installiere Godot und die Export-Templates auf dem Server, exportiere einmal headless und prüfe, dass index.html, .js, .wasm und .pck entstehen. Lege .github/workflows/deploy.yml an, das bei jedem Push auf main exportiert und nach GitHub Pages deployt (Vorlage: rkoning/godot-web-test). Main-Szene: Titel, Button "Start", der einen Zähler hochzählt.

### M1: Kampfkern ohne Grafik
Fertig, wenn 1.000 Zufallskämpfe headless in wenigen Sekunden laufen und Tests grün sind.

Prompt:
> Baue game/core/: rng.gd, combat_sim.gd, effects.gd. Lies Monster aus data/monsters.json (lege 12 Monster in 4 Typen und 3 Seltenheiten an, Format wie in PLAN.md). Kampf auf zwei 3x3-Rastern, rundenbasiert in Ticks, Reihenfolge nach Position, vordere Reihe wird zuerst getroffen. Effekte: Gift, Schild. simulate(team_a, team_b, seed) gibt Ergebnis plus Ereignisliste zurück. Schreibe GdUnit4-Tests: Determinismus bei gleichem Seed, Gift tickt korrekt, Schild blockt Schaden. Lege tools/simulate.gd an, das N Zufallskämpfe rechnet und pro Monster die Winrate ausgibt.

### M2: Kampf sichtbar machen
Fertig, wenn du am Handy einen Kampf zwischen zwei festen Teams anschauen kannst.

Prompt:
> Lade Tiny Creatures und Kenney Tiny Dungeon (beide CC0) nach game/assets/ und trage sie in CREDITS.md ein. Baue ui/board.tscn (3x3-Raster, Sprites 3-fach skaliert) und ui/battle_view.tscn, die die Ereignisliste aus combat_sim abspielt: Angriff als kurzer Sprung, Schadenszahl als aufsteigender Text, Gift grün aufblitzen, Tod als Ausblenden. Geschwindigkeit 1x und 2x per Button. Layout: Gegner oben, eigenes Team unten, Buttons im Daumenbereich.

Falls Downloads von itch.io nicht klappen: ZIPs selbst herunterladen und ins Repo legen.

### M3: Shop und Run
Fertig, wenn ein kompletter Run spielbar ist.

Prompt:
> Baue core/shop.gd und core/run_state.gd, Werte aus data/balance.json: Gold pro Runde, Kosten, Neu-würfeln-Preis, Seltenheits-Chancen je Runde, Startleben. Kaufen per Tippen, Aufstellen und Verkaufen per Ziehen. 3 gleiche verschmelzen automatisch zur nächsten Stufe. Gegner kommen aus data/ghost_teams.json passend zur Runde. Siegbedingung 10 Siege, Niederlage bei 0 Leben. Speichere den laufenden Run lokal.

### M4: Trainer, Trinkets, Tiefe
Fertig, wenn 2 Trainer und 6 Trinkets spürbar andere Strategien ermöglichen.

Prompt:
> Füge data/trainers.json (2 Trainer mit je einer passiven Fähigkeit) und data/trinkets.json (6 Trinkets) hinzu. Fähigkeiten als Kombination aus Auslöser (Kampfstart, beim Angriff, beim Tod, Rundenende im Shop) und Effekt, ohne Sonderfall-Code pro Item. Trainer-Auswahl zu Beginn des Runs, Trinket-Wahl (1 aus 3) nach jedem zweiten Sieg. Tests für jeden Auslöser.

### M5: Balancing-Werkzeuge
Fertig, wenn ein Befehl 10.000 Bot-Runs simuliert und einen Bericht erzeugt.

Prompt:
> Baue drei Bots (Zufall, Gier, Synergie) für komplette Runs inklusive Shop. tools/simulate.gd schreibt jedes Ereignis als JSON Line nach logs/sim.jsonl, Format wie in PLAN.md, inklusive Spielversion. Erzeuge daraus ghost_teams.json. Schreibe analysis/analyze.py (pandas, matplotlib): Kampf-Winrate je Monster und Runde, Pick-Rate, Siege pro Run je Trainer und Bot, Verteilung der Siege, Kampfdauer. Ausgabe als report.html. Baue telemetry/logger.gd für echte Runs im selben Format plus einen Export-Button im Debug-Menü.

### M6: Polish und PWA-Feinschliff
Fertig, wenn sich das Spiel am Handy wie eine App anfühlt und offline startet.

Prompt:
> Titelbildschirm, Einstellungen (Ton, Geschwindigkeit), Run-Historie. Kenney-UI-Pack für Panels und Buttons, Kenney-Sounds für Klicks und Treffer, CC0-Musik mit Lautstärkeregler, Ton erst nach dem ersten Tippen. Safe Area für Notch beachten, Hinweis bei Querformat. PWA-Icons 144/180/512 aus einem Pixel-Logo, Ladebildschirm im Pixel-Stil.

### Später: echtes asynchrones PvP
Erst, wenn der Einzelspieler-Loop Spaß macht und die Bots eine gesunde Verteilung zeigen.

## 8. Referenzen

- Godot 4 Autobattler Tutorial: https://www.youtube.com/playlist?list=PL6SABXRSlpH_0UEV3gJ53I7a2eGL8pqs3 und https://github.com/guladam/godot_autobattler_course
- GDQuest Pixel Art in Godot 4: https://www.gdquest.com/library/pixel_art_setup_godot4/
- Godot Web-Export und PWA: https://docs.godotengine.org/en/latest/tutorials/export/exporting_for_web.html
- Godot mehrere Auflösungen: https://github.com/godotengine/godot-docs/blob/master/tutorials/rendering/multiple_resolutions.rst
- Tiny Auto Knights Devlog: https://mumpitzgames.itch.io/tinyautoknights/devlog
- Slay the Spire GDC 2019: https://www.gdcvault.com/play/1025731/-Slay-the-Spire-Metrics
- Riot Balance Framework: https://www.leagueoflegends.com/en-us/news/dev/dev-balance-framework-update/
