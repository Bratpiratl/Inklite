extends SceneTree
## Headless-Simulation für den Balancing-Workshop.
##
## Bot-Runs, jedes Ereignis als JSON Line:
##   godot --headless --path game -s res://tools/ws_simulate.gd -- --ruleset workshop/rulesets/jinto_bg --runs 2000
##   Optionen: --seed N, --bot random|greedy|synergy|all, --combat bg|grid, --out Pfad (relativ zum Repo),
##             --ghosts N (vorher N Durchgänge, die ghosts.json im Regelsatz neu erzeugen)
## Zufallskämpfe mit Winrate je Einheit (ohne Shop):
##   ... -- --ruleset ... --mode fights --runs 5000 [--budget 120] [--level 1]
## Am Ende steht eine Zusammenfassung als JSON in <out>.summary.json (für den Editor).

const DEFAULT_RULESET := "workshop/rulesets/jinto_bg"


func _init() -> void:
	var args := _parse_args(OS.get_cmdline_user_args())
	var rs := WsRuleset.load_dir(args.get("ruleset", DEFAULT_RULESET))
	if rs == null:
		quit(1)
		return
	if args.get("mode", "runs") == "fights":
		_simulate_fights(rs, args)
	else:
		var iterations := int(args.get("ghosts", 0))
		for it in iterations:
			print("Geister-Durchgang %d von %d" % [it + 1, iterations])
			var ghost_args := args.duplicate()
			ghost_args["seed"] = int(args.get("seed", 1)) * 7919 + it
			ghost_args.erase("out")
			_simulate_runs(rs, ghost_args, true)
		_simulate_runs(rs, args, false)
	quit()


func _repo_path(path: String) -> String:
	if path.is_absolute_path():
		return path
	return ProjectSettings.globalize_path("res://").path_join("..").path_join(path).simplify_path()


# --- Bot-Runs ---

func _simulate_runs(rs: WsRuleset, args: Dictionary, collect_ghosts: bool) -> void:
	var runs := int(args.get("runs", 1000))
	var base_seed := int(args.get("seed", 1))
	var bot_arg: String = args.get("bot", "all")
	var bot_names: Array[String] = WsBots.NAMES if bot_arg == "all" else [bot_arg]
	var combat_mode: String = args.get("combat", "")
	var ruleset_name := rs.dir.get_file()

	var file: FileAccess = null
	var out_path := ""
	if args.has("out") or not collect_ghosts:
		out_path = _repo_path(args.get("out", "workshop/runs/%s/sim.jsonl" % ruleset_name))
		DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
		file = FileAccess.open(out_path, FileAccess.WRITE)
	var sink := func(line: Dictionary) -> void:
		if file != null:
			file.store_line(JSON.stringify(line))

	var per_day := int(rs.section("sim").get("ghosts_per_day", 60))
	var pool := {}
	var seen := {}
	var pool_rng := GameRng.new(base_seed * 31 + 7)
	var stats := {}
	var learn := {"battles": []}
	var started := Time.get_ticks_msec()

	for i in runs:
		var bot_name: String = bot_names[i % bot_names.size()]
		var run_seed := (base_seed * 1000003 + i) % 2147483647
		var bot := WsBots.new(bot_name, rs, GameRng.new(run_seed ^ 0x5bd1e995))
		var run := WsRun.create(rs, run_seed, combat_mode)
		run.logger = WsLogger.new({"run": "%s-%06d" % [bot_name, i], "bot": bot_name, "focus": bot.focus_color,
			"ruleset": ruleset_name, "combat": run._combat.mode}, sink)
		while not run.is_over():
			bot.play_shop(run)
			if collect_ghosts:
				_collect_ghost(pool, seen, pool_rng, per_day, run, bot_name, i)
			var b := run.fight()
			if collect_ghosts and not b.is_empty():
				_record_battle(learn, b)
		_count(stats, bot_name, run)

	if file != null:
		file.close()
	var elapsed := (Time.get_ticks_msec() - started) / 1000.0
	print("%d Runs in %.1f s (%s)" % [runs, elapsed, rs.dir])
	_print_stats(stats)
	if collect_ghosts:
		rs.unit_values = _learned_values(learn)
		_write_ghosts(rs, pool, base_seed)
	if out_path != "":
		print("Log: %s" % out_path)
		var summary := {"runs": runs, "seconds": elapsed, "seed": base_seed, "combat": combat_mode if combat_mode != "" else rs.combat_mode(),
			"ruleset": ruleset_name, "groups": stats, "log": out_path}
		var sf := FileAccess.open(out_path + ".summary.json", FileAccess.WRITE)
		sf.store_string(JSON.stringify(summary, " "))
		sf.close()


func _collect_ghost(pool: Dictionary, seen: Dictionary, rng: GameRng, per_day: int, run: WsRun, bot_name: String, index: int) -> void:
	var d := run.day
	seen[d] = seen.get(d, 0) + 1
	var ghost := {"id": "g_%s_%05d_%02d" % [bot_name, index, d], "day": d, "wins": run.wins, "bot": bot_name, "team": run.battle_team()}
	if not pool.has(d):
		pool[d] = []
	if pool[d].size() < per_day:
		pool[d].append(ghost)
	else:
		var j := rng.next_int(seen[d])
		if j < per_day:
			pool[d][j] = ghost


## Merkt sich je Kampf Tag, Ergebnis und beteiligte Einheiten (jede einmal).
func _record_battle(learn: Dictionary, b: Dictionary) -> void:
	var score := 0.5
	if b["winner"] == 0:
		score = 1.0
	elif b["winner"] == 1:
		score = 0.0
	var ids := {}
	for entry: Dictionary in b["team"]:
		ids[entry["id"]] = true
	learn["battles"].append([int(b["day"]), score, ids.keys()])


## Bereinigte Winrate je Einheit wie in ws_analyze.py: Abstand zum Tagesschnitt plus 50.
func _learned_values(learn: Dictionary) -> Dictionary:
	var day_sum := {}
	var day_n := {}
	for rec: Array in learn["battles"]:
		day_sum[rec[0]] = day_sum.get(rec[0], 0.0) + rec[1]
		day_n[rec[0]] = day_n.get(rec[0], 0) + 1
	var unit_sum := {}
	var unit_n := {}
	for rec: Array in learn["battles"]:
		var adj: float = rec[1] - day_sum[rec[0]] / day_n[rec[0]]
		for id: String in rec[2]:
			unit_sum[id] = unit_sum.get(id, 0.0) + adj
			unit_n[id] = unit_n.get(id, 0) + 1
	var values := {}
	for id: String in unit_sum:
		# Unter 30 Kämpfen zu unsicher, dann bleibt der Preis allein maßgeblich.
		if unit_n[id] >= 30:
			values[id] = snappedf(50.0 + 100.0 * unit_sum[id] / unit_n[id], 0.1)
	return values


func _write_ghosts(rs: WsRuleset, pool: Dictionary, base_seed: int) -> void:
	var days := pool.keys()
	days.sort()
	var teams: Array = []
	var lines: Array[String] = []
	for d: int in days:
		for ghost: Dictionary in pool[d]:
			teams.append(ghost)
			lines.append("  " + JSON.stringify(ghost))
	rs.ghosts = teams
	var path := rs.dir.path_join("ghosts.json")
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string('{"generator": "tools/ws_simulate.gd --ghosts", "seed": %d, "unit_values": %s, "teams": [\n%s\n]}\n' % [
		base_seed, JSON.stringify(rs.unit_values), ",\n".join(lines)])
	f.close()
	print("%d Geisterteams für %d Tage: %s" % [teams.size(), days.size(), path])


func _count(stats: Dictionary, bot_name: String, run: WsRun) -> void:
	for key in ["bot:" + bot_name, "alle"]:
		if not stats.has(key):
			stats[key] = {"runs": 0, "wins": 0, "victories": 0, "days": 0, "draws": 0}
		var s: Dictionary = stats[key]
		s["runs"] += 1
		s["wins"] += run.wins
		s["draws"] += run.draws
		s["days"] += run.day - 1
		s["victories"] += 1 if run.is_victory() else 0


func _print_stats(stats: Dictionary) -> void:
	print("%-14s %6s %7s %9s %6s %7s" % ["Gruppe", "Runs", "Siege", "gewonnen", "Tage", "Unent."])
	var keys := stats.keys()
	keys.sort()
	for key: String in keys:
		var s: Dictionary = stats[key]
		var n := maxi(s["runs"], 1)
		print("%-14s %6d %7.2f %8.1f %% %6.1f %7.2f" % [key, s["runs"], float(s["wins"]) / n,
			100.0 * s["victories"] / n, float(s["days"]) / n, float(s["draws"]) / n])


# --- Zufallskämpfe ---

func _simulate_fights(rs: WsRuleset, args: Dictionary) -> void:
	var runs := int(args.get("runs", 1000))
	var base_seed := int(args.get("seed", 1))
	var level := int(args.get("level", 1))
	var budget := int(args.get("budget", 120))
	var sim := WsCombat.new(rs, args.get("combat", ""))
	var rng := GameRng.new(base_seed)
	var ids := rs.units.keys()
	ids.sort()
	var stats := {}
	for id in ids:
		stats[id] = {"fights": 0, "wins": 0, "draws": 0}
	var draws := 0
	var total_attacks := 0
	var started := Time.get_ticks_msec()
	for i in runs:
		var teams := [_random_team(rs, ids, budget, level, rng), _random_team(rs, ids, budget, level, rng)]
		var result := sim.simulate(teams[0], teams[1], base_seed * 1000003 + i)
		total_attacks += result["attacks"]
		if result["winner"] == WsCombat.DRAW:
			draws += 1
		for side in 2:
			var seen := {}
			for entry: Dictionary in teams[side]:
				seen[entry["id"]] = true
			for id: String in seen:
				stats[id]["fights"] += 1
				if result["winner"] == side:
					stats[id]["wins"] += 1
				elif result["winner"] == WsCombat.DRAW:
					stats[id]["draws"] += 1
	var elapsed := Time.get_ticks_msec() - started
	print("Kämpfe: %d  Modus: %s  Budget: %d  Zeit: %d ms  Unentschieden: %.1f %%  Angriffe im Schnitt: %.1f" % [
		runs, sim.mode, budget, elapsed, 100.0 * draws / maxi(runs, 1), float(total_attacks) / maxi(runs, 1)])
	ids.sort_custom(func(a: String, b: String) -> bool: return _rate(stats[a]) > _rate(stats[b]))
	print("%-6s %-12s %4s %5s %7s %8s" % ["Id", "Name", "Sel.", "Preis", "Kämpfe", "Winrate"])
	for id: String in ids:
		var def := rs.get_def(id)
		print("%-6s %-12s %4d %5d %7d %7.1f %%" % [id, def.get("name", ""), def.get("rarity", 0), def.get("cost", 0), stats[id]["fights"], _rate(stats[id])])


func _random_team(rs: WsRuleset, ids: Array, budget: int, level: int, rng: GameRng) -> Array:
	var slots := range(rs.team_slots())
	rng.shuffle(slots)
	var team: Array = []
	var left := budget
	while team.size() < slots.size():
		var affordable := ids.filter(func(id: String) -> bool: return rs.cost(id) <= left)
		if affordable.is_empty():
			break
		var id: String = rng.pick(affordable)
		left -= rs.cost(id)
		team.append({"id": id, "level": level, "slot": slots[team.size()]})
	return team


func _rate(s: Dictionary) -> float:
	return 0.0 if s["fights"] == 0 else 100.0 * (s["wins"] + 0.5 * s["draws"]) / s["fights"]


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
