extends Control
## Shop-Phase: kaufen per Tippen, umstellen per Ziehen auf ein anderes Feld,
## verkaufen per Ziehen auf die Verkaufsfläche. Regeln stecken in RunState.

const CARD_SCENE := preload("res://ui/shop_card.tscn")
const HINT := "Tippe ein Angebot zum Kaufen. Ziehe Monster zum Umstellen oder nach unten zum Verkaufen."
const HINT_FULL := "Raster voll. Verkaufe schwache Monster (nach unten ziehen), um stärkere zu kaufen. Drei gleiche verschmelzen auch bei vollem Raster."
const FLASH_MERGE := Color(2.0, 1.8, 0.7)
const FLASH_TIME := 0.5
const ITEM_SIZE := 48

@onready var _hud: Hud = %Hud
@onready var _board: Board = %Board
@onready var _info: Label = %InfoLabel
@onready var _cards: HBoxContainer = %Cards
@onready var _reroll: Button = %RerollButton
@onready var _fight: Button = %FightButton
@onready var _shop_area: Control = %ShopArea
@onready var _sell_zone: DropZone = %SellZone
@onready var _sell_label: Label = %SellLabel
@onready var _item_bar: HBoxContainer = %ItemBar
@onready var _trinket_overlay: Control = %TrinketOverlay
@onready var _trinket_choices: ChoiceList = %TrinketChoices

var _run: RunState


func _ready() -> void:
	_run = Session.run
	if _run == null:
		Session.goto(Session.TITLE_SCENE)
		return
	_board.unit_tapped.connect(_on_unit_tapped)
	_board.unit_moved.connect(_on_unit_moved)
	_sell_zone.dropped.connect(_on_sell_dropped)
	_reroll.pressed.connect(_on_reroll)
	_fight.pressed.connect(_on_fight)
	_trinket_choices.chosen.connect(_on_trinket_chosen)
	_info.text = HINT
	_refresh()


func _refresh() -> void:
	_hud.show_run(_run)
	_board.show_board(_run.board, Session.db)
	_refresh_items()
	_trinket_overlay.visible = not _run.pending_trinkets.is_empty()
	if _trinket_overlay.visible:
		_trinket_choices.show_choices(_run.pending_trinkets)
	while _cards.get_child_count() < _run.offers.size():
		var card: ShopCard = CARD_SCENE.instantiate()
		var index := _cards.get_child_count()
		card.pressed.connect(func() -> void: _on_buy(index))
		_cards.add_child(card)
	for i in _cards.get_child_count():
		var card: ShopCard = _cards.get_child(i)
		card.visible = i < _run.offers.size()
		if not card.visible:
			continue
		var id: String = _run.offers[i]
		if id == "":
			card.show_empty()
		else:
			card.show_offer(Session.db.get_def(id), Session.db.level_stats(id, 1))
			card.disabled = not _run.can_buy(i)
	_reroll.text = "Neu würfeln (%d)" % _run.reroll_cost()
	_reroll.disabled = _run.gold < _run.reroll_cost()
	_fight.disabled = _run.unit_count() == 0 or not _run.can_fight()
	if _run.unit_count() == CombatSim.SLOTS and _info.text == HINT:
		_info.text = HINT_FULL
	elif _run.unit_count() < CombatSim.SLOTS and _info.text == HINT_FULL:
		_info.text = HINT


## Trainer und Trinkets als antippbare Symbole oben.
func _refresh_items() -> void:
	for child in _item_bar.get_children():
		child.queue_free()
	var ids: Array[String] = []
	if _run.trainer != "":
		ids.append(_run.trainer)
	ids.append_array(_run.trinkets)
	for id in ids:
		var button := Button.new()
		button.custom_minimum_size = Vector2(ITEM_SIZE, ITEM_SIZE)
		button.focus_mode = Control.FOCUS_NONE
		button.icon = Session.item_texture(id)
		button.expand_icon = true
		button.pressed.connect(func() -> void: _info.text = AbilityText.item_line(Session.item_def(id)))
		_item_bar.add_child(button)


func _on_trinket_chosen(id: String) -> void:
	if _run.choose_trinket(id):
		Session.save()
		_refresh()
		_info.text = "Neu: " + AbilityText.item_line(Session.item_def(id))


func _on_buy(index: int) -> void:
	var result := _run.buy(index)
	if not result["ok"]:
		return
	Session.save()
	_refresh()
	var unit: Dictionary = _run.board[result["slot"]]
	var text := AbilityText.unit_line(Session.db, unit)
	if not result["merges"].is_empty():
		var last: Dictionary = result["merges"][-1]
		text = "Verschmolzen zu Stufe %d!\n%s" % [last["level"], text]
		for merge: Dictionary in result["merges"]:
			_board.cell(merge["slot"]).flash(FLASH_MERGE, FLASH_TIME)
	_info.text = text


func _on_unit_tapped(slot: int) -> void:
	var unit: Variant = _run.board[slot]
	if unit == null:
		return
	_info.text = "%s\nVerkaufswert: %d Gold" % [
		AbilityText.unit_line(Session.db, unit), _run.sell_value(slot)]


func _on_unit_moved(from_slot: int, to_slot: int) -> void:
	if _run.move(from_slot, to_slot):
		Session.save()
		_refresh()


func _on_sell_dropped(data: Dictionary) -> void:
	var slot := int(data["slot"])
	var unit: Variant = _run.board[slot]
	if unit == null:
		return
	var value := _run.sell(slot)
	Session.save()
	_refresh()
	_info.text = "%s verkauft für %d Gold." % [Session.db.get_def(unit["id"])["name"], value]


func _on_reroll() -> void:
	if _run.reroll():
		Session.save()
		_refresh()


func _on_fight() -> void:
	Session.fight()
	Session.goto(Session.BATTLE_SCENE)


func _notification(what: int) -> void:
	if not is_node_ready():
		return
	if what == NOTIFICATION_DRAG_BEGIN:
		var data: Variant = get_viewport().gui_get_drag_data()
		if data is Dictionary and data.get("kind", "") == UnitCell.DRAG_KIND:
			_sell_label.text = "Hier ablegen zum Verkaufen\n+%d Gold" % _run.sell_value(int(data["slot"]))
			_sell_zone.visible = true
			_shop_area.modulate.a = 0.0
	elif what == NOTIFICATION_DRAG_END:
		_sell_zone.visible = false
		_shop_area.modulate.a = 1.0
