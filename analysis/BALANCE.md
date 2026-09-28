# Balance-Protokoll

Jede Änderung an Spielwerten: vorher messen, Vorhersage aufschreiben, nachher messen, vergleichen.
Messung jeweils mit 10.000 Bot-Runs (`tools/simulate.gd -- --runs 10000`) und `analysis/analyze.py`.
Monster-Winrates sind bereinigt (Abstand zum Rundenschnitt plus 50), siehe Bericht.

## Runde 1 (28.09.2026, Version 0.1.0)

Ausgangslage: Geister aus Bot-Runs, Gegner nach Runde und Siegen (ghost_match_pool 5).
Bots: Gier 9,4 Siege, Synergie 7,3, Zufall 4,3. Trainer Olm 7,11, Asha 6,86.

| Änderung | Warum | Vorhersage | Ergebnis |
| --- | --- | --- | --- |
| Abspielpausen in ui/battle_timing.gd um 20 % kürzer | 7,2 % der Kämpfe über 40 s (späte Runden, volle Raster) | 1 bis 2 % über 40 s | 0,8 % über 40 s, p90 von 38,0 auf 29,9 s. Eingetroffen. |
| Dornengolem HP 18 auf 16 (je Stufe verdoppelt) | spät 60 bis 63 % bereinigt | ab Runde 9 etwa 57 % | 60,4 % wie vorher. Nicht eingetroffen: die Stärke kommt von den Dornen (1 Schaden je Treffer gegen ihn), nicht von den HP. |

Offen für Runde 2:
- Dornengolem über die Dornen oder die Kosten angehen, nicht über HP.
- Tropfschnecke in Runde 1 schwach (24 %), Moosunke in Runde 1 stark (72 %).
- Tiefenwal in Runden 4 bis 6 über 60 %.
- Rundenschnitt schwankt stark (Runde 2 und 6 um 75 %, Runde 1 und 3 um 45 %). Vermutlich Geister-Stichprobe, weitere Geister-Iterationen prüfen.
