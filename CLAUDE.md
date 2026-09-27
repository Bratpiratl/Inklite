# Projekt: Inklite

Asynchroner Monster-Autobattler, Hochformat, Godot 4 (Version siehe project.godot), GDScript, Web-Export als PWA.
Der vollständige Plan mit Meilensteinen steht in PLAN.md. Arbeite immer nur am Meilenstein, den ich dir nenne.

## Harte Regeln
- Alle Spielwerte in game/data/*.json. Keine Zahlen für Balance im Code.
- game/core/ enthält nur reine Logik: keine Nodes, keine Szenen, kein Rendering.
- Jeder Zufall über core/rng.gd mit Seed. Gleicher Seed und gleiche Teams = gleicher Kampf.
- combat_sim.gd gibt eine Ereignisliste zurück. ui/ spielt sie nur ab.
- Basisauflösung 360x640, stretch canvas_items + expand, Texturfilter Nearest.
- UI nur mit Containern und Ankern, Touch-Ziele mindestens 48x48.
- Renderer gl_compatibility, Web-Export single-threaded.
- Nur Assets aus assets/CREDITS.md verwenden. Neue Assets dort mit Quelle und Lizenz eintragen.
- Eigene Monster-Namen und Designs, keine Anlehnung an bestehende Marken.
- Keine langen Gedankenstriche in Texten und Kommentaren.

## Befehle
- Tests: godot --headless --path game -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a test
- Simulation: godot --headless --path game -s res://tools/simulate.gd -- --runs 10000
- Auswertung: python analysis/analyze.py logs/sim.jsonl

## Arbeitsweise
- Vor jedem Commit Tests und eine kurze Simulation laufen lassen.
- Nach jedem Meilenstein headless exportieren und prüfen, dass index.html, .js, .wasm und .pck entstehen.
- Kleine Commits mit klarer Nachricht, dann push auf main (deployt automatisch nach GitHub Pages).
- Am Ende jedes Meilensteins kurz zusammenfassen, was ich am Handy testen soll.
