#!/usr/bin/env bash
# Baut einen spielbaren Test-Build mit einem Workshop-Regelsatz. Braucht kein root.
# Aufruf aus dem Repo-Root: workshop/build_play.sh [regelsatz] [--data ordner] [--out ordner]
#   Standard: Regelsatz jinto_bg aus workshop/rulesets/, Ausgabe workshop/play/<regelsatz>/.
#   Die Pages-Action ruft es mit --data workshop/public/jinto_bg --out build/web/workshop auf.
#   GODOT=<pfad> setzt das Godot-Programm (Standard: godot).
#
# Arbeitet auf einer Kopie von game/: dort wird tools/ws_play.tscn zur Hauptszene, der Regelsatz
# kommt nach res://ws_data/ und PWA wird abgeschaltet. Das Repo selbst bleibt unverändert.
# Ergebnis: workshop/play/<regelsatz>/index.html, ausgeliefert vom Editor unter /play/<regelsatz>/.
set -euo pipefail
cd "$(dirname "$0")/.."
NAME="jinto_bg"
SRC=""
OUT=""
while [ $# -gt 0 ]; do
	case "$1" in
		--data) SRC="$2"; shift 2 ;;
		--out) OUT="$2"; shift 2 ;;
		*) NAME="$1"; shift ;;
	esac
done
SRC="${SRC:-workshop/rulesets/$NAME}"
OUT="${OUT:-workshop/play/$NAME}"
GODOT="${GODOT:-godot}"
case "$OUT" in /*) ;; *) OUT="$PWD/$OUT" ;; esac
WORK="workshop/play/.build"
[ -f "$SRC/units.json" ] || { echo "Regelsatz fehlt: $SRC"; exit 1; }

mkdir -p "$WORK" "$OUT"
rsync -a --delete --exclude reports/ --exclude ws_data/ game/ "$WORK/game/"
mkdir -p "$WORK/game/ws_data"
cp "$SRC/ruleset.json" "$SRC/units.json" "$WORK/game/ws_data/"
[ -f "$SRC/ghosts.json" ] && cp "$SRC/ghosts.json" "$WORK/game/ws_data/"

sed -i 's|^run/main_scene=.*|run/main_scene="res://tools/ws_play.tscn"|' "$WORK/game/project.godot"
sed -i 's|^progressive_web_app/enabled=.*|progressive_web_app/enabled=false|' "$WORK/game/export_presets.cfg"
# JSON-Dateien außerhalb von data/ mit exportieren.
sed -i 's|^include_filter=.*|include_filter="*.json"|' "$WORK/game/export_presets.cfg"
# Das öffentliche Preset lässt tools/ weg; hier muss die Test-Szene mit hinein.
sed -i 's|^exclude_filter=.*|exclude_filter="addons/gdUnit4/*, test/*, reports/*"|' "$WORK/game/export_presets.cfg"

echo "Importiere ..."
"$GODOT" --headless --path "$WORK/game" --import >/dev/null 2>&1 || true
echo "Exportiere ..."
rm -rf "$OUT.tmp" && mkdir -p "$OUT.tmp"
"$GODOT" --headless --path "$WORK/game" --export-release "Web" "$OUT.tmp/index.html" 2>&1 | grep -vE '^Godot Engine|ObjectDB|^ +at:|resources still in use|savepack|first_scan|loading_editor|^\s*$' || true
[ -f "$OUT.tmp/index.pck" ] || { echo "Export fehlgeschlagen"; exit 1; }
rm -rf "$OUT" && mv "$OUT.tmp" "$OUT"
echo "Fertig: $OUT ($(du -sh "$OUT" | cut -f1))"
