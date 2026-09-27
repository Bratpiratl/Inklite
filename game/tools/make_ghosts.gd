extends SceneTree
## Erzeugt data/ghost_teams.json: Zufallsbots spielen nur den Shop durch (ohne Kämpfe) und
## geben ihr Team jeder Runde als Geisterteam ab. Einstellungen in balance.json ("ghosts").
## In M5 ersetzen die richtigen Bots diesen Generator.
##
## Aufruf: godot --headless --path game -s res://tools/make_ghosts.gd -- [--seed 1]

const OUT_PATH := "res://data/ghost_teams.json"


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var base_seed := 1
	var seed_index := args.find("--seed")
	if seed_index >= 0 and seed_index + 1 < args.size():
		base_seed = int(args[seed_index + 1])

	var db := MonsterDb.from_file()
	_db = db
	var balance := GameData.load_balance()
	var rules: Dictionary = balance.get("ghosts", {})
	var runs: int = rules.get("runs", 1)
	var rounds: int = rules.get("rounds", 1)
	var reroll_chance: int = rules.get("reroll_chance_percent", 0)

	var teams: Array = []
	for r in runs:
		var run := RunState.create(db, balance, [], base_seed * 7919 + r)
		var bot_rng := GameRng.new(base_seed * 104729 + r)
		for round_index in rounds:
			_shop_randomly(run, bot_rng, reroll_chance)
			teams.append({
				"id": "ghost_%03d_%02d" % [r, run.round_number],
				"round": run.round_number,
				"team": run.team(),
			})
			run.advance_round()

	# Ein Team pro Zeile: kleine Datei, lesbare Diffs.
	var lines: Array[String] = []
	for team in teams:
		lines.append("    " + JSON.stringify(team))
	var file := FileAccess.open(OUT_PATH, FileAccess.WRITE)
	file.store_string('{\n  "generator": "tools/make_ghosts.gd (Zufallsbot)",\n  "seed": %d,\n  "teams": [\n%s\n  ]\n}\n' % [
		base_seed, ",\n".join(lines)])
	file.close()
	print("%d Geisterteams für %d Runden geschrieben: %s" % [teams.size(), rounds, OUT_PATH])
	quit()


var _db: MonsterDb


## Raster voll: tauscht das schwächste Monster der Stufe 1 gegen ein selteneres Angebot.
func _upgrade(run: RunState, db: MonsterDb) -> bool:
	var weakest := -1
	var weakest_rarity := 99
	for slot in CombatSim.SLOTS:
		var unit: Variant = run.board[slot]
		if unit != null and unit["level"] == 1:
			var rarity := int(db.get_def(unit["id"])["rarity"])
			if rarity < weakest_rarity:
				weakest = slot
				weakest_rarity = rarity
	if weakest < 0:
		return false
	for i in run.offers.size():
		var id: String = run.offers[i]
		if id == "" or int(db.get_def(id)["rarity"]) <= weakest_rarity:
			continue
		if run.gold + run.sell_value(weakest) >= run.price(i):
			run.sell(weakest)
			return run.buy(i)["ok"]
	return false


func _shop_randomly(run: RunState, rng: GameRng, reroll_chance: int) -> void:
	while true:
		var buyable: Array = []
		for i in run.offers.size():
			if run.can_buy(i):
				buyable.append(i)
		if not buyable.is_empty():
			run.buy(rng.pick(buyable))
		elif _upgrade(run, _db):
			pass
		elif run.gold >= run.reroll_cost() and rng.next_int(100) < reroll_chance:
			run.reroll()
		else:
			return
