class_name Board
extends GridContainer
## 3x3-Raster einer Seite. Die vordere Reihe (Reihe 0) liegt immer zur Bildschirmmitte hin:
## beim eigenen Team oben, beim Gegner unten. Mit interactive lassen sich Monster antippen und ziehen.

signal unit_tapped(slot: int)
signal unit_moved(from_slot: int, to_slot: int)

const CELL_SCENE := preload("res://ui/unit_cell.tscn")

@export var is_enemy := false
@export var interactive := false
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
		cell.set_interactive(interactive)
		cell.tapped.connect(unit_tapped.emit)
		cell.dropped_on.connect(unit_moved.emit)
		_cells[slot] = cell
	clear()


func cell(slot: int) -> UnitCell:
	return _cells[slot]


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
		_cells[slot].show_unit(db.get_def(unit["id"])["sprite"], hp, atk, unit["level"], is_enemy)


@warning_ignore("integer_division")
func _slot_for_visual(visual: int) -> int:
	var row := visual / CombatSim.COLS
	var col := visual % CombatSim.COLS
	if is_enemy:
		row = CombatSim.ROWS - 1 - row
	return row * CombatSim.COLS + col
