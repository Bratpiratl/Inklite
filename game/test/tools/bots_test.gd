extends GdUnitTestSuite
## Bots spielen komplette Runs mit echten Daten, deterministisch je Seed.


func _play(bot_name: String, seed_value: int) -> RunState:
	var db := MonsterDb.from_file()
	var items := ItemDb.from_files()
	var balance := GameData.load_balance()
	var ghosts: Array = GameData.load_json("res://data/ghost_teams.json")["teams"]
	var bot := Bots.new(bot_name, db, items, GameRng.new(seed_value), balance["bots"])
	var run := RunState.create(db, balance, ghosts, seed_value, bot.choose_trainer(), items)
	var guard := 0
	while not run.is_over() and guard < 40:
		guard += 1
		bot.play_shop(run)
		assert_bool(run.can_fight()).is_true()
		run.fight()
	assert_bool(run.is_over()).is_true()
	return run


func test_every_bot_finishes_a_run() -> void:
	for bot_name in Bots.NAMES:
		var run := _play(bot_name, 3)
		assert_str(run.trainer).is_not_empty()


func test_bots_are_deterministic() -> void:
	for bot_name in Bots.NAMES:
		assert_dict(_play(bot_name, 8).to_dict()).is_equal(_play(bot_name, 8).to_dict())


func test_synergy_bot_picks_matching_trainer() -> void:
	var items := ItemDb.from_files()
	for s in 10:
		var bot := Bots.new("synergy", MonsterDb.from_file(), items, GameRng.new(s), {})
		var trainer := bot.choose_trainer()
		var matching := items.trainer_ids().filter(
			func(id: String) -> bool: return Bots._item_type(items.trainer(id)) == bot.focus_type)
		if not matching.is_empty():
			assert_array(matching).contains([trainer])
