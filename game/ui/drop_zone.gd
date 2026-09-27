class_name DropZone
extends PanelContainer
## Ablagefläche für gezogene Monster, z. B. zum Verkaufen.

signal dropped(data: Dictionary)


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return data is Dictionary and data.get("kind", "") == UnitCell.DRAG_KIND


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	dropped.emit(data)
