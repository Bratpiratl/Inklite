extends SceneTree
## Headless-Simulation: rechnet N Zufallskämpfe und gibt pro Monster die Winrate aus.
##
## Aufruf: godot --headless --path game -s res://tools/simulate.gd -- --runs 1000 [--seed 1] [--level 1]
##
## Jedes Team kauft zufällig Monster, bis das Budget aus balance.json (sim.team_budget) verbraucht
## oder das Raster voll ist, und stellt sie auf zufällige Felder. So misst die Winrate, wie viel
## ein Monster für seinen Preis leistet.


func _init() -> void:
	var args := _parse_args(OS.get_cmdline_user_args())
	var runs: int = args.get("runs", 1000)
	var base_seed: int = args.get("seed", 1)
	var level: int = args.get("level", 1)

	var db := MonsterDb.from_file()
	var balance := GameData.load_balance()
	var sim := CombatSim.new(db, balance.get("combat", {}))
	var sim_rules: Dictionary = balance.get("sim", {})
	var team_rng := GameRng.new(base_seed)

	var stats: Dictionary = {}
	for id in db.ids():
		stats[id] = {"fights": 0, "wins": 0, "draws": 0}
	var draws := 0
	var total_ticks := 0
	var max_ticks := 0
	var side_wins := [0, 0]

	var started := Time.get_ticks_msec()
	for i in runs:
		var teams := [_random_team(db, sim_rules, level, team_rng), _random_team(db, sim_rules, level, team_rng)]
		var result := sim.simulate(teams[0], teams[1], base_seed * 1000003 + i)
		var winner: int = result["winner"]
		total_ticks += result["ticks"]
		max_ticks = maxi(max_ticks, result["ticks"])
		if winner == CombatSim.DRAW:
			draws += 1
		else:
			side_wins[winner] += 1
		for side in 2:
			var seen := {}
			for entry: Dictionary in teams[side]:
				seen[entry["id"]] = true
			for id: String in seen:
				stats[id]["fights"] += 1
				if winner == side:
					stats[id]["wins"] += 1
				elif winner == CombatSim.DRAW:
					stats[id]["draws"] += 1
	var elapsed := Time.get_ticks_msec() - started

	print("Kämpfe: %d  Stufe: %d  Seed: %d  Zeit: %d ms (%.2f ms/Kampf)" % [runs, level, base_seed, elapsed, float(elapsed) / maxi(runs, 1)])
	print("Seite A: %.1f %%  Seite B: %.1f %%  Unentschieden: %.1f %%" % [
		_pct(side_wins[0], runs), _pct(side_wins[1], runs), _pct(draws, runs)])
	print("Ticks im Schnitt: %.1f  Maximum: %d" % [float(total_ticks) / maxi(runs, 1), max_ticks])
	print("")
	print("%-16s %-7s %4s %5s %8s %8s" % ["Monster", "Typ", "Sel.", "Kosten", "Kämpfe", "Winrate"])
	var ids := db.ids()
	ids.sort_custom(func(a: String, b: String) -> bool:
		return _rate(stats[a]) > _rate(stats[b]))
	for id in ids:
		var def := db.get_def(id)
		var s: Dictionary = stats[id]
		var flag := ""
		if s["fights"] > 0 and (_rate(s) > 60.0 or _rate(s) < 40.0):
			flag = "  <-- Warnsignal"
		print("%-16s %-7s %4d %5d %8d %7.1f %%%s" % [id, def["type"], def["rarity"], def["cost"], s["fights"], _rate(s), flag])
	quit()


func _random_team(db: MonsterDb, sim_rules: Dictionary, level: int, rng: GameRng) -> Array:
	var budget: int = sim_rules.get("team_budget", 0)
	var max_size: int = sim_rules.get("max_team_size", CombatSim.SLOTS)
	var slots := range(CombatSim.SLOTS)
	rng.shuffle(slots)
	var team: Array = []
	while team.size() < max_size:
		var affordable: Array = db.ids().filter(func(id: String) -> bool:
			return int(db.get_def(id)["cost"]) <= budget)
		if affordable.is_empty():
			break
		var id: String = rng.pick(affordable)
		budget -= int(db.get_def(id)["cost"])
		team.append({"id": id, "level": level, "slot": slots[team.size()]})
	return team


## Winrate mit Unentschieden als halbem Sieg.
func _rate(s: Dictionary) -> float:
	if s["fights"] == 0:
		return 0.0
	return 100.0 * (s["wins"] + 0.5 * s["draws"]) / s["fights"]


func _pct(part: int, total: int) -> float:
	return 100.0 * part / maxi(total, 1)


func _parse_args(raw: PackedStringArray) -> Dictionary:
	var result := {}
	var i := 0
	while i < raw.size():
		var key := raw[i]
		if key.begins_with("--") and i + 1 < raw.size():
			result[key.substr(2)] = int(raw[i + 1])
			i += 2
		else:
			i += 1
	return result
