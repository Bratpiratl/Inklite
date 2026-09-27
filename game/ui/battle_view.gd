extends Control
## Spielt die Ereignisliste des letzten Kampfes (Session.last_battle) ab. Rechnet selbst nichts aus:
## Werte kommen ausschließlich aus den Ereignissen. Eigenes Team ist Seite 0 (unten), Gegner Seite 1.

const SPEEDS: Array[float] = [1.0, 2.0]
const SKIP_SPEED := 1000.0

# Abspieldauern in Sekunden bei 1x.
const T_START := 0.6
const T_TICK := 0.3
const T_ATTACK := 0.24
const T_HIT := 0.08
const T_EFFECT := 0.18
const T_ABILITY := 0.08
const T_DEATH := 0.25
const T_FLOAT := 0.7
const FLOAT_RISE := 26.0

const COLOR_DAMAGE := Color(1, 0.36, 0.36)
const COLOR_BLOCK := Color(0.5, 0.8, 1)
const COLOR_POISON := Color(0.56, 1, 0.42)
const COLOR_ABILITY := Color(1, 0.85, 0.4)
const FLASH_HIT := Color(2.2, 2.2, 2.2)
const FLASH_POISON := Color(0.5, 1.8, 0.5)
const FLASH_SHIELD := Color(0.7, 1.2, 2.2)
const FLASH_ABILITY := Color(1.8, 1.6, 0.6)

@onready var _enemy_board: Board = %EnemyBoard
@onready var _player_board: Board = %PlayerBoard
@onready var _fx: Control = %FxLayer
@onready var _title: Label = %Title
@onready var _tick_label: Label = %TickLabel
@onready var _result_label: Label = %ResultLabel
@onready var _outcome_label: Label = %OutcomeLabel
@onready var _continue_button: Button = %ContinueButton
@onready var _replay_button: Button = %ReplayButton
@onready var _speed_button: Button = %SpeedButton

var _battle: Dictionary
var _db: MonsterDb
var _generation := 0  # Jeder Neustart erhöht das, laufende Wiedergaben brechen dann ab.
var _playing := false
var _skipping := false


func _ready() -> void:
	_battle = Session.last_battle
	_db = Session.db
	if _battle.is_empty():
		Session.goto(Session.TITLE_SCENE)
		return
	_continue_button.pressed.connect(_on_continue)
	_replay_button.pressed.connect(_start)
	_speed_button.pressed.connect(_toggle_speed)
	_update_speed_button()
	_start.call_deferred()


func _start() -> void:
	_generation += 1
	_skipping = false
	for child in _fx.get_children():
		child.queue_free()
	_enemy_board.clear()
	_player_board.clear()
	_result_label.text = ""
	_outcome_label.text = ""
	_title.text = "Runde %d" % _battle["round"]
	_play(_battle["events"], _generation)


func _play(events: Array, generation: int) -> void:
	_set_playing(true)
	for event: Dictionary in events:
		if generation != _generation or not is_inside_tree():
			return
		await _play_event(event)
	if generation == _generation:
		_set_playing(false)


func _set_playing(value: bool) -> void:
	_playing = value
	_continue_button.text = "Überspringen" if value else "Weiter"
	_replay_button.disabled = value


func _on_continue() -> void:
	if _playing:
		_skipping = true
		return
	Session.goto(Session.TITLE_SCENE if Session.run.is_over() else Session.SHOP_SCENE)


func _play_event(e: Dictionary) -> void:
	match e["ev"]:
		"start":
			_tick_label.text = ""
			for unit: Dictionary in e["units"]:
				var def := _db.get_def(unit["id"])
				_cell(unit["side"], unit["slot"]).show_unit(def["sprite"], unit["hp"], unit["atk"], unit["level"], unit["side"] == 1)
			await _wait(T_START)
		"tick":
			_tick_label.text = "Zug %d" % e["t"]
			await _wait(T_TICK)
		"attack":
			var direction := -1.0 if e["side"] == 0 else 1.0
			_cell(e["side"], e["slot"]).jump(direction, T_ATTACK / _speed())
			await _wait(T_ATTACK * 0.5)
		"damage":
			var cell := _cell(e["side"], e["slot"])
			cell.set_stats(e["hp"], e["shield"], e["poison"])
			var is_poison: bool = e["kind"] == Effects.KIND_POISON
			cell.flash(FLASH_POISON if is_poison else FLASH_HIT, T_EFFECT / _speed())
			if e["blocked"] > 0:
				_float_text(cell, "-%d" % e["blocked"], COLOR_BLOCK)
			if e["amount"] > 0 or e["blocked"] == 0:
				_float_text(cell, "-%d" % e["amount"], COLOR_POISON if is_poison else COLOR_DAMAGE)
			await _wait(T_HIT)
		"poison":
			var cell := _cell(e["side"], e["slot"])
			cell.set_stats(cell.hp, cell.shield, e["total"])
			cell.flash(FLASH_POISON, T_EFFECT / _speed())
			_float_text(cell, "+%d Gift" % e["amount"], COLOR_POISON)
			await _wait(T_EFFECT)
		"shield":
			var cell := _cell(e["side"], e["slot"])
			cell.set_stats(cell.hp, e["total"], cell.poison)
			cell.flash(FLASH_SHIELD, T_EFFECT / _speed())
			_float_text(cell, "+%d Schild" % e["amount"], COLOR_BLOCK)
			await _wait(T_EFFECT)
		"ability":
			_cell(e["side"], e["slot"]).flash(FLASH_ABILITY, T_EFFECT / _speed())
			await _wait(T_ABILITY)
		"death":
			_cell(e["side"], e["slot"]).die(T_DEATH / _speed())
			await _wait(T_DEATH)
		"end":
			_show_result(e["winner"])


func _show_result(winner: int) -> void:
	var run := Session.run
	match winner:
		0:
			_set_result("Sieg!", COLOR_POISON)
		1:
			_set_result("Niederlage", COLOR_DAMAGE)
		_:
			_set_result("Unentschieden", COLOR_ABILITY)
	if run.is_victory():
		_outcome_label.text = "Run gewonnen! %d Siege, %d Leben übrig." % [run.wins, run.lives]
	elif run.is_over():
		_outcome_label.text = "Keine Leben mehr. Run vorbei mit %d Siegen." % run.wins
	else:
		_outcome_label.text = "Siege %d/%d, Leben %d" % [run.wins, run.wins_to_victory(), run.lives]


func _set_result(text: String, color: Color) -> void:
	_result_label.text = text
	_result_label.add_theme_color_override("font_color", color)


func _float_text(cell: UnitCell, text: String, color: Color) -> void:
	if _skipping:
		return
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 5)
	label.add_theme_font_size_override("font_size", 16)
	_fx.add_child(label)
	label.size = Vector2(cell.size.x + 32, 22)
	label.position = cell.global_position - _fx.global_position + Vector2(-16, 8)
	var tween := label.create_tween().set_parallel()
	var duration := T_FLOAT / _speed()
	tween.tween_property(label, "position:y", label.position.y - FLOAT_RISE, duration)
	tween.tween_property(label, "modulate:a", 0.0, duration).set_delay(duration * 0.4)
	tween.chain().tween_callback(label.queue_free)


func _cell(side: int, slot: int) -> UnitCell:
	return (_player_board if side == 0 else _enemy_board).cell(slot)


func _speed() -> float:
	return SKIP_SPEED if _skipping else SPEEDS[Session.speed_index]


func _toggle_speed() -> void:
	Session.speed_index = (Session.speed_index + 1) % SPEEDS.size()
	_update_speed_button()


func _update_speed_button() -> void:
	_speed_button.text = "%dx" % int(SPEEDS[Session.speed_index])


## Beim Überspringen kehrt die Funktion ohne await zurück, der Rest läuft dann im selben Frame durch.
func _wait(seconds: float) -> void:
	if _skipping:
		return
	await get_tree().create_timer(seconds / _speed()).timeout
