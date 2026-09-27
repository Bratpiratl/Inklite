#!/usr/bin/env bash
# Führt alle GdUnit4-Tests headless aus. Aufruf aus dem Repo-Root: game/tools/run_tests.sh
#
# Warum ein Wrapper: GdUnit4 überspringt Testdateien mit Parse-Fehler stillschweigend und meldet
# trotzdem Exit 0. Hier schlägt der Lauf fehl, sobald Godot einen Skriptfehler ausgibt.
# --ignoreHeadlessMode ist nötig, weil GdUnit4 v5 headless sonst abbricht. Unsere Tests brauchen
# keine Eingabe-Events, deshalb ist das unkritisch.
set -uo pipefail
cd "$(dirname "$0")/../.."

# Berichte nicht als Projekt-Ressourcen importieren.
mkdir -p game/reports && touch game/reports/.gdignore

godot --headless --path game --import >/dev/null 2>&1
out=$(godot --headless --path game -s addons/gdUnit4/bin/GdUnitCmdTool.gd -a test --ignoreHeadlessMode "$@" 2>&1)
code=$?
clean=$(printf '%s\n' "$out" | sed 's/\x1b\[[0-9;]*[a-zA-Z]//g')

printf '%s\n' "$clean" | grep -E 'FAILED|Report:|Expecting|but was|^ +.?[0-9]+.?$|SCRIPT ERROR|Parse Error|Failed to load|Overall Summary'

if printf '%s\n' "$clean" | grep -qE 'SCRIPT ERROR|Parse Error|Failed to load script'; then
	echo "FEHLER: Skriptfehler, mindestens eine Testdatei wurde nicht ausgeführt."
	exit 1
fi
exit $code
