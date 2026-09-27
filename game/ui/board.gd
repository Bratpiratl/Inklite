class_name Board
extends GridContainer
## 3x3-Raster einer Seite. Die vordere Reihe (Reihe 0) liegt immer zur Bildschirmmitte hin:
## beim eigenen Team oben, beim Gegner unten.

const CELL_SCENE := preload("res://ui/unit_cell.tscn")

@export var is_enemy := false
@export var floor_texture: Texture2D

var _cells: Array[UnitCell] = []  # Index = Slot aus combat_sim


func _ready() -> void:
	columns = CombatSim.COLS
	var by_visual: Array[UnitCell] = []
	for i in CombatSim.SLOTS:
		var cell: UnitCell = CELL_SCENE.instantiate()
		add_child(cell)
		cell.set_floor(floor_texture)
		by_visual.append(cell)
	_cells.resize(CombatSim.SLOTS)
	for visual in CombatSim.SLOTS:
		_cells[_slot_for_visual(visual)] = by_visual[visual]
	clear()


func cell(slot: int) -> UnitCell:
	return _cells[slot]


func clear() -> void:
	for c in _cells:
		c.clear()


@warning_ignore("integer_division")
func _slot_for_visual(visual: int) -> int:
	var row := visual / CombatSim.COLS
	var col := visual % CombatSim.COLS
	if is_enemy:
		row = CombatSim.ROWS - 1 - row
	return row * CombatSim.COLS + col
