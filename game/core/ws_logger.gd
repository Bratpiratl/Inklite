class_name WsLogger
extends RefCounted
## Schreibt Workshop-Runs als JSON Lines, ähnlich RunLogger. Jede Zeile trägt den Kontext (Run, Bot, Regelsatz).
##   shop:    Angebot einer Würfelrunde und was davon gekauft wurde
##   sell:    verkaufte Einheit
##   battle:  eigenes Team, Gegner, Ergebnis, Angriffe
##   run_end: Siege, Leben, Tage

var context: Dictionary
var _sink: Callable


func _init(log_context: Dictionary, sink: Callable) -> void:
	context = log_context
	_sink = sink


static func unit_tag(unit: Dictionary) -> String:
	return "%s:%d" % [unit["id"], unit["level"]]


func shop(run: WsRun, offered: Array, bought: Array) -> void:
	_write({"day": run.day, "ev": "shop", "rank": run.rank(), "offered": offered, "bought": bought, "gold": run.gold})


func sell(run: WsRun, unit: Dictionary, value: int) -> void:
	_write({"day": run.day, "ev": "sell", "unit": unit_tag(unit), "value": value})


func battle(run: WsRun, b: Dictionary) -> void:
	_write({
		"day": b["day"], "ev": "battle", "seed": b["seed"], "team": b["team"].map(unit_tag),
		"enemy": b["ghost_id"], "enemy_strength": b.get("ghost_strength", -1), "result": b["result"], "attacks": b["attacks"], "ticks": b["ticks"],
		"survivors": b["survivors"], "winner": b["winner"], "wins": run.wins, "lives": run.lives, "gold_left": run.gold,
	})


func run_end(run: WsRun) -> void:
	_write({
		"ev": "run_end", "wins": run.wins, "losses": run.losses, "draws": run.draws, "lives": run.lives,
		"days": run.day - 1, "victory": run.is_victory(),
	})


func _write(event: Dictionary) -> void:
	var line := context.duplicate()
	line.merge(event)
	_sink.call(line)
