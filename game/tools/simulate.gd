extends SceneTree
## Headless-Simulation.
##
## Standard: komplette Bot-Runs, jedes Ereignis als JSON Line nach logs/sim.jsonl.
##   godot --headless --path game -s res://tools/simulate.gd -- --runs 10000
##   Optionen: --seed N, --bot random|greedy|synergy|all, --out Pfad, --ghosts (schreibt data/ghost_teams.json)
##
## Zufallskämpfe mit Winrate je Monster (Kampfkern ohne Shop):
##   godot --headless --path game -s res://tools/simulate.gd -- --mode fights --runs 1000 [--level 1]

const GHOSTS_PATH := "res://data/ghost_teams.json"
const DEFAULT_OUT := "../logs/sim.jsonl"


func _init() -> void:
	var args := _parse_args(OS.get_cmdline_user_args())
	if args.get("mode", "runs") == "fights":
		_simulate_fights(args)
	else:
		_simulate_runs(args)
	quit()


# --- Bot-Runs ---

func _simulate_runs(args: Dictionary) -> void:
	var runs := int(args.get("runs", 1000))
	var base_seed := int(args.get("seed", 1))
	var bot_arg: String = args.get("bot", "all")
	var bot_names: Array[String] = Bots.NAMES if bot_arg == "all" else [bot_arg]
	var out_path := ProjectSettings.globalize_path("res://").path_join(args.get("out", DEFAULT_OUT)).simplify_path()

	var db := MonsterDb.from_file()
	var items := ItemDb.from_files()
	var balance := GameData.load_balance()
	var ghosts: Array = GameData.load_json(GHOSTS_PATH)["teams"]
	var ghosts_per_round := int(balance["sim"].get("ghosts_per_round", 24))

	DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
	var file := FileAccess.open(out_path, FileAccess.WRITE)
	if file == null:
		push_error("Log nicht schreibbar: %s" % out_path)
		return
	var sink := func(line: Dictionary) -> void: file.store_line(JSON.stringify(line))

	var stats := {}
	var ghost_pool := {}  # Runde -> Array von Geisterteams (Reservoir-Stichprobe)
	var seen_per_round := {}
	var pool_rng := GameRng.new(base_seed * 31 + 7)
	var started := Time.get_ticks_msec()

	for i in runs:
		var bot_name: String = bot_names[i % bot_names.size()]
		var run_seed := (base_seed * 1000003 + i) % 2147483647
		var bot := Bots.new(bot_name, db, items, GameRng.new(run_seed ^ 0x5bd1e995), balance.get("bots", {}))
		var run := RunState.create(db, balance, ghosts, run_seed, bot.choose_trainer(), items)
		run.logger = RunLogger.new({"run": "%s-%06d" % [bot_name, i], "v": RunLogger.version(), "bot": bot_name}, sink)
		while not run.is_over():
			bot.play_shop(run)
			_collect_ghost(ghost_pool, seen_per_round, pool_rng, ghosts_per_round, run, bot_name, i)
			run.fight()
		_count(stats, bot_name, run)

	file.close()
	var elapsed := Time.get_ticks_msec() - started
	print("%d Runs in %.1f s, Log: %s" % [runs, elapsed / 1000.0, out_path])
	_print_run_stats(stats)
	if args.has("ghosts"):
		_write_ghosts(ghost_pool, base_seed)


## Nimmt das Team vor dem Kampf in eine gleichmäßige Stichprobe je Runde auf.
func _collect_ghost(pool: Dictionary, seen: Dictionary, rng: GameRng, per_round: int, run: RunState, bot_name: String, run_index: int) -> void:
	var r := run.round_number
	seen[r] = seen.get(r, 0) + 1
	var ghost := {
		"id": "ghost_%s_%05d_%02d" % [bot_name, run_index, r], "round": r, "wins": run.wins,
		"bot": bot_name, "trainer": run.trainer, "trinkets": run.trinkets.duplicate(), "team": run.team(),
	}
	if not pool.has(r):
		pool[r] = []
	if pool[r].size() < per_round:
		pool[r].append(ghost)
	else:
		var j := rng.next_int(seen[r])
		if j < per_round:
			pool[r][j] = ghost


func _write_ghosts(pool: Dictionary, base_seed: int) -> void:
	var rounds := pool.keys()
	rounds.sort()
	var lines: Array[String] = []
	for r: int in rounds:
		for ghost: Dictionary in pool[r]:
			lines.append("    " + JSON.stringify(ghost))
	var file := FileAccess.open(GHOSTS_PATH, FileAccess.WRITE)
	file.store_string('{\n  "generator": "tools/simulate.gd --ghosts (Bots: %s)",\n  "seed": %d,\n  "teams": [\n%s\n  ]\n}\n' % [
		", ".join(Bots.NAMES), base_seed, ",\n".join(lines)])
	file.close()
	print("%d Geisterteams für %d Runden geschrieben: %s" % [lines.size(), rounds.size(), GHOSTS_PATH])


func _count(stats: Dictionary, bot_name: String, run: RunState) -> void:
	for key in ["bot:" + bot_name, "trainer:" + run.trainer, "alle"]:
		if not stats.has(key):
			stats[key] = {"runs": 0, "wins": 0, "victories": 0, "draws": 0}
		stats[key]["runs"] += 1
		stats[key]["wins"] += run.wins
		stats[key]["draws"] += run.draws
		stats[key]["victories"] += 1 if run.is_victory() else 0


func _print_run_stats(stats: Dictionary) -> void:
	print("%-18s %6s %8s %10s %8s" % ["Gruppe", "Runs", "Siege", "gewonnen", "Unent."])
	var keys := stats.keys()
	keys.sort()
	for key: String in keys:
		var s: Dictionary = stats[key]
		var n := maxi(s["runs"], 1)
		print("%-18s %6d %8.2f %9.1f %% %8.2f" % [key, s["runs"], float(s["wins"]) / n, 100.0 * s["victories"] / n, float(s["draws"]) / n])


# --- Zufallskämpfe ---

## Jedes Team kauft zufällig Monster, bis das Budget aus balance.json (sim.team_budget) verbraucht
## oder das Raster voll ist. So misst die Winrate, wie viel ein Monster für seinen Preis leistet.
func _simulate_fights(args: Dictionary) -> void:
	var runs := int(args.get("runs", 1000))
	var base_seed := int(args.get("seed", 1))
	var level := int(args.get("level", 1))

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


## --schluessel wert, oder --schalter ohne Wert (dann true). Zahlen werden zu int.
func _parse_args(raw: PackedStringArray) -> Dictionary:
	var result := {}
	var i := 0
	while i < raw.size():
		var key := raw[i]
		if not key.begins_with("--"):
			i += 1
			continue
		var name := key.substr(2)
		if i + 1 < raw.size() and not raw[i + 1].begins_with("--"):
			var value := raw[i + 1]
			result[name] = int(value) if value.is_valid_int() else value
			i += 2
		else:
			result[name] = true
			i += 1
	return result
