extends Control
## Spielt die Ereignisliste des letzten Kampfes (Session.last_battle) ab. Rechnet selbst nichts aus:
## Werte kommen ausschließlich aus den Ereignissen. Eigenes Team ist Seite 0 (unten), Gegner Seite 1.

const SPEEDS: Array[float] = [1.0, 2.0, 3.0]
const SKIP_SPEED := 1000.0

const POP_STAGGER := 0.04
const POP_TIME := 0.25
const RESULT_POP := 1.8

const COLOR_DAMAGE := Color(1, 0.36, 0.36)
const COLOR_BLOCK := Color(0.5, 0.8, 1)
const COLOR_POISON := Color(0.56, 1, 0.42)
const COLOR_ABILITY := Color(1, 0.85, 0.4)
const FLASH_HIT := Color(2.2, 2.2, 2.2)
const FLASH_POISON := Color(0.5, 1.8, 0.5)
const FLASH_SHIELD := Color(0.7, 1.2, 2.2)
const FLASH_ABILITY := Color(1.8, 1.6, 0.6)
const COLOR_ITEM := Color(0.85, 0.7, 1)

@onready var _enemy_board: Board = %EnemyBoard
@onready var _player_board: Board = %PlayerBoard
@onready var _fx: BattleFx = %FxLayer
@onready var _shake_target: Control = $Margin
@onready var _title: Label = %Title
@onready var _tick_label: Label = %TickLabel
@onready var _result_label: Label = %ResultLabel
@onready var _outcome_label: Label = %OutcomeLabel
@onready var _continue_button: Button = %ContinueButton
@onready var _replay_button: Button = %ReplayButton
@onready var _speed_button: Button = %SpeedButton
@onready var _card: InfoCard = %InfoCard

var _battle: Dictionary
var _db: MonsterDb
var _generation := 0  # Jeder Neustart erhöht das, laufende Wiedergaben brechen dann ab.
var _playing := false
var _skipping := false
var _hit_from := Vector2.ZERO  # woher der letzte Treffer kam, für Rückstoß und Funkenrichtung
var _source := Vector2i(-1, -1)  # (Seite, Slot) des letzten Angreifers oder der letzten Fähigkeit
var _dealt: Dictionary = {}  # Vector2i(Seite, Slot) -> verursachter Schaden in diesem Kampf


func _ready() -> void:
	_battle = Session.last_battle
	_db = Session.db
	if _battle.is_empty():
		Session.goto(Session.TITLE_SCENE)
		return
	_continue_button.pressed.connect(_on_continue)
	_replay_button.pressed.connect(_start)
	_speed_button.pressed.connect(_toggle_speed)
	_enemy_board.unit_tapped.connect(_on_unit_tapped.bind(1))
	_player_board.unit_tapped.connect(_on_unit_tapped.bind(0))
	_card.action_pressed.connect(func() -> void:
		Prefs.mark_tip_seen("battle")
		_card.close())
	_update_speed_button()
	Audio.play_music("battle")
	_start.call_deferred()


func _start() -> void:
	_generation += 1
	_skipping = false
	_fx.clear()
	_enemy_board.clear()
	_player_board.clear()
	_result_label.text = ""
	_outcome_label.text = ""
	_card.close()
	_dealt = {}
	_source = Vector2i(-1, -1)
	_title.text = Loc.t("BATTLE_ROUND", {"n": _battle["round"]})
	_outcome_label.text = _round_end_text()
	if Prefs.tip_pending("battle"):
		_card.show_text(Loc.t("TIP_TITLE"), Loc.t("TIP_BATTLE"), load("res://assets/logo.png"))
		_card.set_action(Loc.t("BTN_OK"))
	_play(_battle["events"], _generation)


func _play(events: Array, generation: int) -> void:
	_set_playing(true)
	for event: Dictionary in events:
		if generation != _generation or not is_inside_tree():
			return
		_play_event(event)
		await _wait(BattleTiming.wait_after(event))
	if generation == _generation:
		_set_playing(false)


func _set_playing(value: bool) -> void:
	_playing = value
	_continue_button.text = Loc.t("BATTLE_SKIP" if value else "BTN_CONTINUE")
	_replay_button.disabled = value


func _on_continue() -> void:
	if _playing:
		_skipping = true
		return
	Session.goto(Session.TITLE_SCENE if Session.run.is_over() else Session.SHOP_SCENE)


## Zeigt ein Ereignis an. Wie lange danach gewartet wird, bestimmt BattleTiming.
func _play_event(e: Dictionary) -> void:
	_fx.speed = _speed()
	match e["ev"]:
		"start":
			_tick_label.text = ""
			var index := 0
			for unit: Dictionary in e["units"]:
				var def := _db.get_def(unit["id"])
				var cell := _cell(unit["side"], unit["slot"])
				cell.show_unit(unit["id"], def["sprite"], unit["hp"], unit["atk"], unit["level"], unit["side"] == 1)
				if not _skipping:
					cell.pop_in(index * POP_STAGGER / _speed(), POP_TIME / _speed())
				index += 1
		"tick":
			_tick_label.text = Loc.t("BATTLE_TURN", {"n": e["t"]})
		"attack":
			Audio.play_hit()
			var attacker := _cell(e["side"], e["slot"])
			var target := _cell(e["to_side"], e["to_slot"])
			_source = Vector2i(e["side"], e["slot"])
			_hit_from = attacker.center()
			attacker.lunge(target.center(), BattleTiming.T_ATTACK / _speed())
		"damage":
			_on_damage(e)
		"poison":
			var cell := _cell(e["side"], e["slot"])
			Audio.play("poison")
			cell.set_stats(cell.hp, cell.shield, e["total"])
			cell.flash(FLASH_POISON, BattleTiming.T_EFFECT / _speed())
			if not _skipping:
				_fx.rise(cell, COLOR_POISON)
				_fx.float_text(cell, Loc.t("FLOAT_POISON", {"n": e["amount"]}), COLOR_POISON)
		"shield":
			var cell := _cell(e["side"], e["slot"])
			Audio.play("shield")
			cell.set_stats(cell.hp, e["total"], cell.poison)
			cell.flash(FLASH_SHIELD, BattleTiming.T_EFFECT / _speed())
			if not _skipping:
				_fx.ring(cell, COLOR_BLOCK)
				_fx.float_text(cell, Loc.t("FLOAT_SHIELD", {"n": e["amount"]}), COLOR_BLOCK)
		"ability":
			var source: String = e.get("source", "")
			var anchor: Control = _cell(e["side"], e["slot"]) if e["slot"] >= 0 else _board(e["side"])
			_hit_from = anchor.global_position + anchor.size / 2.0
			_source = Vector2i(e["side"], e["slot"])
			if source == "":
				_cell(e["side"], e["slot"]).flash(FLASH_ABILITY, BattleTiming.T_EFFECT / _speed())
				if not _skipping:
					_fx.ring(anchor, COLOR_ABILITY)
			elif not _skipping:
				# Trainer oder Trinket: Name über dem auslösenden Monster oder mittig über dem Raster.
				_fx.ring(anchor, COLOR_ITEM)
				_fx.float_text(anchor, Loc.item(source), COLOR_ITEM)
		"buff":
			var cell := _cell(e["side"], e["slot"])
			cell.set_atk(e["atk"])
			cell.set_stats(e["hp"], cell.shield, cell.poison)
			cell.flash(FLASH_ABILITY, BattleTiming.T_EFFECT / _speed())
			if not _skipping:
				_fx.rise(cell, COLOR_ABILITY, 10)
				_fx.float_text(cell, Loc.t("FLOAT_ATK" if e["stat"] == "atk" else "FLOAT_HP", {"n": e["amount"]}), COLOR_ABILITY)
		"death":
			Audio.play("death")
			var cell := _cell(e["side"], e["slot"])
			cell.die(BattleTiming.T_DEATH / _speed())
			if not _skipping:
				_fx.puff(cell)
				_fx.shake(_shake_target, 0.7)
		"end":
			_show_result(e["winner"])


func _on_damage(e: Dictionary) -> void:
	var cell := _cell(e["side"], e["slot"])
	# Schaden zählt für den letzten Angreifer bzw. die letzte Fähigkeit. Gift lässt sich keinem
	# einzelnen Monster zuordnen und zählt nicht mit.
	if e["kind"] != Effects.KIND_POISON and _source.y >= 0 and _source.x != e["side"]:
		_dealt[_source] = int(_dealt.get(_source, 0)) + int(e["amount"]) + int(e["blocked"])
	cell.set_stats(e["hp"], e["shield"], e["poison"])
	var kind: String = e["kind"]
	var is_poison := kind == Effects.KIND_POISON
	cell.flash(FLASH_POISON if is_poison else FLASH_HIT, BattleTiming.T_EFFECT / _speed())
	if _skipping:
		return
	var away := (cell.center() - _hit_from).normalized()
	if is_poison:
		_fx.rise(cell, COLOR_POISON, 6)
	else:
		cell.knock(_hit_from, BattleTiming.T_EFFECT / _speed())
		if e["blocked"] > 0:
			_fx.sparks(cell, COLOR_BLOCK, away, 8)
		if e["amount"] > 0:
			_fx.sparks(cell, Color.WHITE if kind == Effects.KIND_ATTACK else COLOR_ABILITY, away)
	if e["blocked"] > 0:
		_fx.float_text(cell, "-%d" % e["blocked"], COLOR_BLOCK)
	if e["amount"] > 0 or e["blocked"] == 0:
		_fx.damage_number(cell, e["amount"], COLOR_POISON if is_poison else COLOR_DAMAGE, _shake_target)


func _show_result(winner: int) -> void:
	var run := Session.run
	match winner:
		0:
			_set_result(Loc.t("BATTLE_WIN"), COLOR_POISON)
			Haptics.pulse(Haptics.WIN)
			if not _skipping:
				_fx.confetti()
		1:
			_set_result(Loc.t("BATTLE_LOSS"), COLOR_DAMAGE)
		_:
			_set_result(Loc.t("BATTLE_DRAW"), COLOR_ABILITY)
	if run.is_over():
		Audio.play("run_won" if run.is_victory() else "run_lost")
	else:
		Audio.play("win" if winner == 0 else "loss")
	if run.is_victory():
		_outcome_label.text = Loc.t("BATTLE_RUN_WON", {"wins": run.wins, "lives": run.lives})
	elif run.is_over():
		_outcome_label.text = Loc.t("BATTLE_RUN_LOST", {"wins": run.wins})
	else:
		_outcome_label.text = Loc.t("BATTLE_STATUS", {"wins": run.wins, "max": run.wins_to_victory(), "lives": run.lives})
	var mvp := _mvp()
	if mvp != "":
		_outcome_label.text += "\n" + mvp


## Bester Kämpfer des eigenen Teams nach verursachtem Schaden.
func _mvp() -> String:
	var best := Vector2i(-1, -1)
	for key: Vector2i in _dealt:
		if key.x == 0 and (best.y < 0 or _dealt[key] > _dealt[best]):
			best = key
	if best.y < 0:
		return ""
	var cell := _cell(0, best.y)
	return Loc.t("BATTLE_MVP", {"name": Loc.monster(cell.unit_id), "n": _dealt[best]})


## Ergebnis ploppt groß auf und setzt sich.
func _set_result(text: String, color: Color) -> void:
	_result_label.text = text
	_result_label.add_theme_color_override("font_color", color)
	_result_label.pivot_offset = _result_label.size / 2.0
	_result_label.scale = Vector2.ONE * RESULT_POP
	_result_label.create_tween().tween_property(_result_label, "scale", Vector2.ONE, 0.35) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Ein Tipp daneben schließt die Karte.
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and _card.visible:
		_card.close()


## Tippen auf ein Monster zeigt seine aktuellen Kampfwerte. Der Kampf läuft dabei weiter.
func _on_unit_tapped(slot: int, side: int) -> void:
	var cell := _cell(side, slot)
	if not cell.has_unit():
		return
	_card.show_monster({"id": cell.unit_id, "level": cell.level}, _db,
		{"atk": cell.atk, "hp": cell.hp, "shield": cell.shield, "poison": cell.poison})
	_card.set_note(Loc.t("CARD_DEALT", {"n": int(_dealt.get(Vector2i(side, slot), 0))}))


func _cell(side: int, slot: int) -> UnitCell:
	return _board(side).cell(slot)


func _board(side: int) -> Board:
	return _player_board if side == 0 else _enemy_board


## Was Trainer und Trinkets am Ende der Shop-Phase bewirkt haben.
func _round_end_text() -> String:
	var lines: Array[String] = []
	for entry: Dictionary in _battle.get("round_end", []):
		var monster_name := ""
		if entry["slot"] >= 0:
			for unit: Dictionary in _battle["events"][0]["units"]:
				if unit["side"] == 0 and unit["slot"] == entry["slot"]:
					monster_name = Loc.monster(unit["id"])
		lines.append(AbilityText.round_end_line(entry, Loc.item(entry["id"]), monster_name))
	return "\n".join(lines)


func _speed() -> float:
	return SKIP_SPEED if _skipping else SPEEDS[Prefs.speed_index]


func _toggle_speed() -> void:
	Prefs.set_value("speed_index", (Prefs.speed_index + 1) % SPEEDS.size())
	_update_speed_button()


func _update_speed_button() -> void:
	_speed_button.text = "%dx" % int(SPEEDS[Prefs.speed_index])


## Beim Überspringen kehrt die Funktion ohne await zurück, der Rest läuft dann im selben Frame durch.
func _wait(seconds: float) -> void:
	if _skipping:
		return
	await get_tree().create_timer(seconds / _speed()).timeout
