class_name RunLogger
extends RefCounted
## Schreibt Run-Ereignisse als JSON Lines im Format aus PLAN.md, für Bots und echte Spieler gleich.
## Jede Zeile enthält den Kontext (Run-ID, Spielversion, bei Bots der Bot-Name).
##
##   shop:    was eine Würfelrunde angeboten hat und was davon gekauft wurde
##   sell:    verkauftes Monster
##   trinket: angebotene Trinkets und die Wahl
##   battle:  eigenes Team, Gegner, Ergebnis, Ticks und geschätzte Dauer in Sekunden bei 1x
##   run_end: Trainer, Trinkets, Siege, Leben, Runden

var context: Dictionary
var _sink: Callable


func _init(log_context: Dictionary, sink: Callable) -> void:
	context = log_context
	_sink = sink


static func version() -> String:
	return ProjectSettings.get_setting("application/config/version", "0")


static func unit_tag(unit: Dictionary) -> String:
	return "%s:%d" % [unit["id"], unit["level"]]


func shop(run: RunState, offered: Array, bought: Array) -> void:
	_write({"round": run.round_number, "ev": "shop", "offered": offered, "bought": bought, "gold": run.gold})


func sell(run: RunState, unit: Dictionary, value: int) -> void:
	_write({"round": run.round_number, "ev": "sell", "unit": unit_tag(unit), "value": value})


func trinket(run: RunState, offered: Array, chosen: String) -> void:
	_write({"round": run.round_number, "ev": "trinket", "offered": offered, "chosen": chosen})


func battle(run: RunState, team: Array, result: Dictionary) -> void:
	_write({
		"round": result["round"], "ev": "battle", "seed": result["seed"],
		"team": team.map(unit_tag), "enemy": result["ghost_id"], "result": result["result"],
		"ticks": result["ticks"], "duration_s": snappedf(BattleTiming.duration(result["events"]), 0.1),
		"wins": run.wins, "lives": run.lives,
	})


func run_end(run: RunState) -> void:
	_write({
		"ev": "run_end", "trainer": run.trainer, "trinkets": run.trinkets.duplicate(),
		"wins": run.wins, "lives": run.lives, "rounds": run.round_number, "victory": run.is_victory(),
	})


func _write(event: Dictionary) -> void:
	var line := context.duplicate()
	line.merge(event)
	_sink.call(line)
