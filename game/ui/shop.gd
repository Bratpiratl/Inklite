extends Control
## Shop-Phase. Tippen auf ein Angebot zeigt die Info-Karte (Bottom Sheet über dem Shop-Bereich)
## mit Kaufen. Tippen auf ein eigenes Monster zeigt die Karte mit Verkaufen. Ziehen stellt um oder verkauft
## über die Verkaufsfläche. Leiste oben, Trainer und Trinkets erklären sich per Tipp.
## Regeln stecken in RunState, hier wird nur angezeigt und weitergereicht.

const CARD_SCENE := preload("res://ui/shop_card.tscn")
const FLASH_MERGE := Color(2.0, 1.8, 0.7)
const FLASH_TIME := 0.5
const ITEM_SIZE := 48

enum CardMode { NONE, BUY, SELL, TIP }

@onready var _hud: Hud = %Hud
@onready var _board: Board = %Board
@onready var _hint: Label = %InfoLabel
@onready var _card: InfoCard = %InfoCard
@onready var _cards: HBoxContainer = %Cards
@onready var _reroll: Button = %RerollButton
@onready var _fight: Button = %FightButton
@onready var _shop_area: Control = %ShopArea
@onready var _sell_zone: DropZone = %SellZone
@onready var _sell_label: Label = %SellLabel
@onready var _item_bar: HBoxContainer = %Items
@onready var _trinket_overlay: Control = %TrinketOverlay
@onready var _trinket_choices: ChoiceList = %TrinketChoices

var _run: RunState
var _mode := CardMode.NONE
var _selected_offer := -1
var _selected_slot := -1
var _tip := ""


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
	_hud.info_requested.connect(_on_hud_info)
	_card.action_pressed.connect(_on_card_action)
	_card.closed.connect(_on_card_closed)
	%MenuButton.pressed.connect(func() -> void: Session.goto(Session.TITLE_SCENE))
	%HelpButton.pressed.connect(func() -> void: Session.open_help(Session.SHOP_SCENE))
	Audio.play_music("menu")
	_hint.text = Loc.t("SHOP_HINT")
	_refresh()
	_show_pending_tip()


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
		card.pressed.connect(func() -> void: _on_offer_tapped(index))
		card.add_to_group("silent_button")
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
			# Angebote bleiben antippbar, auch wenn das Gold fehlt: die Karte erklärt, warum.
			card.disabled = false
		card.set_selected(_mode == CardMode.BUY and i == _selected_offer)
	_reroll.text = Loc.t("SHOP_REROLL", {"cost": _run.reroll_cost()})
	_reroll.disabled = _run.gold < _run.reroll_cost()
	_fight.disabled = _run.unit_count() == 0 or not _run.can_fight()


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
		button.pressed.connect(_show_item.bind(id))
		_item_bar.add_child(button)


# --- Info-Karte ---

func _on_offer_tapped(index: int) -> void:
	var id: String = _run.offers[index]
	if id == "":
		return
	_mode = CardMode.BUY
	_selected_offer = index
	_card.show_monster({"id": id, "level": 1}, Session.db)
	_card.set_action(Loc.t("CARD_BUY", {"cost": _run.price(index)}), _run.can_buy(index))
	if _run.gold < _run.price(index):
		_card.set_note(Loc.t("CARD_NO_GOLD"))
	elif not _run.can_buy(index):
		_card.set_note(Loc.t("CARD_NO_SPACE"))
	else:
		var copies := _copies_on_board(id)
		if copies > 0:
			_card.set_note(Loc.t("CARD_COPIES", {"n": copies}))
	Audio.play("click")
	_refresh()


func _on_unit_tapped(slot: int) -> void:
	var unit: Variant = _run.board[slot]
	if unit == null:
		return
	_mode = CardMode.SELL
	_selected_slot = slot
	_card.show_monster(unit, Session.db)
	_card.set_action(Loc.t("CARD_SELL", {"gold": _run.sell_value(slot)}))
	if unit["level"] == 1:
		var copies := _copies_on_board(unit["id"])
		if copies > 1:
			_card.set_note(Loc.t("CARD_COPIES", {"n": copies}))
	_refresh()


func _show_item(id: String) -> void:
	_mode = CardMode.NONE
	_card.show_item(id, Session.item_def(id), id == _run.trainer)
	_refresh()


func _on_hud_info(topic: String) -> void:
	_mode = CardMode.NONE
	_card.show_text(Loc.t("HUD_%s_T" % topic), Loc.t("HUD_%s_INFO" % topic, {"max": _run.wins_to_victory()}))
	_refresh()


func _on_card_action() -> void:
	match _mode:
		CardMode.BUY:
			_buy(_selected_offer)
		CardMode.SELL:
			_sell(_selected_slot)
		CardMode.TIP:
			Prefs.mark_tip_seen(_tip)
			_card.close()


func _on_card_closed() -> void:
	_mode = CardMode.NONE
	_selected_offer = -1
	_selected_slot = -1
	_refresh()
	_show_pending_tip()


## Einmalige Tipps, wenn gerade nichts anderes auf der Karte steht.
func _show_pending_tip() -> void:
	if _card.visible or _trinket_overlay.visible:
		return
	var tip := ""
	if Prefs.tip_pending("shop"):
		tip = "shop"
	elif Prefs.tip_pending("full") and _run.unit_count() == CombatSim.SLOTS:
		tip = "full"
	elif Prefs.tip_pending("trinket") and not _run.trinkets.is_empty():
		tip = "trinket"
	if tip == "":
		return
	_tip = tip
	_mode = CardMode.TIP
	_card.show_text(Loc.t("TIP_TITLE"), Loc.t("TIP_" + tip.to_upper()), load("res://assets/logo.png"))
	_card.set_action(Loc.t("BTN_OK"))
	_refresh()


func _copies_on_board(id: String) -> int:
	var count := 0
	for unit: Variant in _run.board:
		if unit != null and unit["id"] == id and unit["level"] == 1:
			count += 1
	return count


# --- Aktionen ---

func _buy(index: int) -> void:
	var result := _run.buy(index)
	if not result["ok"]:
		Audio.play("error")
		return
	Audio.play("merge" if not result["merges"].is_empty() else "buy")
	Session.save()
	var unit: Dictionary = _run.board[result["slot"]]
	_mode = CardMode.NONE
	_selected_offer = -1
	_card.show_monster(unit, Session.db)
	if not result["merges"].is_empty():
		_card.set_note(Loc.t("SHOP_MERGED", {"level": result["merges"][-1]["level"]}))
		for merge: Dictionary in result["merges"]:
			_board.cell(merge["slot"]).flash(FLASH_MERGE, FLASH_TIME)
	_refresh()
	if _run.unit_count() == CombatSim.SLOTS and Prefs.tip_pending("full"):
		_card.close()


func _sell(slot: int) -> void:
	var unit: Variant = _run.board[slot]
	if unit == null:
		return
	var value := _run.sell(slot)
	Audio.play("sell")
	Session.save()
	_mode = CardMode.NONE
	_selected_slot = -1
	_card.show_text(Loc.monster(unit["id"]), Loc.t("SHOP_SOLD", {"name": Loc.monster(unit["id"]), "gold": value}))
	_refresh()


func _on_unit_moved(from_slot: int, to_slot: int) -> void:
	if _run.move(from_slot, to_slot):
		Session.save()
		_refresh()


func _on_sell_dropped(data: Dictionary) -> void:
	_sell(int(data["slot"]))


func _on_trinket_chosen(id: String) -> void:
	if _run.choose_trinket(id):
		Session.save()
		_refresh()
		_show_item(id)
		_card.set_note(Loc.t("SHOP_NEW_ITEM"))


func _on_reroll() -> void:
	if _run.reroll():
		Audio.play("reroll")
		Session.save()
		if _mode == CardMode.BUY:
			_card.close()
		_refresh()


func _on_fight() -> void:
	Session.fight()
	Session.goto(Session.BATTLE_SCENE)


## Ein Tipp daneben schließt die Karte. Hier landen nur Tipps, die kein Knopf und kein Monster abfängt.
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and _card.visible:
		_card.close()


func _notification(what: int) -> void:
	if not is_node_ready():
		return
	if what == NOTIFICATION_DRAG_BEGIN:
		var data: Variant = get_viewport().gui_get_drag_data()
		if data is Dictionary and data.get("kind", "") == UnitCell.DRAG_KIND:
			_card.close()
			_sell_label.text = Loc.t("SHOP_SELL_DROP", {"gold": _run.sell_value(int(data["slot"]))})
			_sell_zone.visible = true
			_shop_area.modulate.a = 0.0
	elif what == NOTIFICATION_DRAG_END:
		_sell_zone.visible = false
		_shop_area.modulate.a = 1.0
