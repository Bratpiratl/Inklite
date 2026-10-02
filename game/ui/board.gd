class_name Board
extends GridContainer
## 3x3-Raster einer Seite. Die vordere Reihe (Reihe 0) liegt immer zur Bildschirmmitte hin:
## beim eigenen Team oben, beim Gegner unten. Mit interactive lassen sich Monster antippen und ziehen.

signal unit_tapped(slot: int)
signal unit_moved(from_slot: int, to_slot: int)
signal offer_dropped(offer_index: int, slot: int)

const CELL_SCENE := preload("res://ui/unit_cell.tscn")

@export var is_enemy := false
@export var interactive := false
## Nur antippen zum Ansehen, ohne Ziehen (Kampfansicht).
@export var inspectable := false
@export var floor_texture: Texture2D

var _cells: Array[UnitCell] = []  # Index = Slot aus combat_sim


func _ready() -> void:
	columns = CombatSim.COLS
	_cells.resize(CombatSim.SLOTS)
	for visual in CombatSim.SLOTS:
		var cell: UnitCell = CELL_SCENE.instantiate()
		add_child(cell)
		var slot := _slot_for_visual(visual)
		cell.slot = slot
		cell.set_floor(floor_texture)
		cell.set_interactive(interactive or inspectable)
		cell.draggable = interactive
		cell.show_hp_bar = not interactive
		cell.tapped.connect(unit_tapped.emit)
		cell.dropped_on.connect(unit_moved.emit)
		cell.offer_dropped.connect(offer_dropped.emit)
		_cells[slot] = cell
	clear()


func cell(slot: int) -> UnitCell:
	return _cells[slot]


func set_offer_check(check: Callable) -> void:
	for c in _cells:
		c.offer_check = check


## Hebt die Felder hervor, für die filter(slot) true liefert. Leerer Callable: nichts.
func highlight(filter: Callable) -> void:
	for slot in CombatSim.SLOTS:
		_cells[slot].set_highlight(filter.is_valid() and filter.call(slot))


func clear() -> void:
	for c in _cells:
		c.clear()


## Zeigt ein Raster im Format von RunState.board (null oder {"id", "level"} je Slot).
func show_board(board: Array, db: MonsterDb) -> void:
	for slot in CombatSim.SLOTS:
		var unit: Variant = board[slot]
		if unit == null:
			_cells[slot].clear()
			continue
		var stats := db.level_stats(unit["id"], unit["level"])
		var hp := int(stats["hp"]) + int(unit.get("hp_bonus", 0))
		var atk := int(stats["atk"]) + int(unit.get("atk_bonus", 0))
		_cells[slot].show_unit(unit["id"], db.get_def(unit["id"])["sprite"], hp, atk, unit["level"], is_enemy)


## Abwürfe in die Fugen zwischen den Feldern gehen an das nächste Feld. Ohne das bricht Godot den Zug
## ab, sobald der Finger zwischen zwei Feldern losgelassen wird.
func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	var target := _cell_at(at_position)
	return target != null and target._can_drop_data(at_position - target.position, data)


func _drop_data(at_position: Vector2, data: Variant) -> void:
	var target := _cell_at(at_position)
	if target != null:
		target._drop_data(at_position - target.position, data)


func _cell_at(at_position: Vector2) -> UnitCell:
	var best: UnitCell = null
	var best_distance := INF
	for c in _cells:
		var distance := (c.position + c.size / 2.0).distance_squared_to(at_position)
		if distance < best_distance:
			best_distance = distance
			best = c
	return best


@warning_ignore("integer_division")
func _slot_for_visual(visual: int) -> int:
	var row := visual / CombatSim.COLS
	var col := visual % CombatSim.COLS
	if is_enemy:
		row = CombatSim.ROWS - 1 - row
	return row * CombatSim.COLS + col
