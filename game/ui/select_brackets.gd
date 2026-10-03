class_name SelectBrackets
extends Control
## Orange Eckwinkel um eine ausgewählte Karte oder Wahl. Nur Zeichnung, fängt keine Eingaben ab.

const COLOR := Color(0.968627, 0.635294, 0.105882)
const OUTLINE := Color(0.121569, 0.105882, 0.164706)
const ARM := 10.0
const THICK := 3.0
const OUTSET := 3.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(queue_redraw)


func _draw() -> void:
	var r := Rect2(Vector2.ONE * -OUTSET, size + Vector2.ONE * OUTSET * 2.0)
	for corner in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
		var sx := 1.0 if corner.x == r.position.x else -1.0
		var sy := 1.0 if corner.y == r.position.y else -1.0
		var origin: Vector2 = corner - Vector2(THICK if sx < 0 else 0.0, THICK if sy < 0 else 0.0)
		var horizontal := Rect2(Vector2(origin.x if sx > 0 else corner.x - ARM, origin.y), Vector2(ARM, THICK))
		var vertical := Rect2(Vector2(origin.x, origin.y if sy > 0 else corner.y - ARM), Vector2(THICK, ARM))
		for part in [horizontal, vertical]:
			draw_rect(part.grow(1.0), OUTLINE)
		for part in [horizontal, vertical]:
			draw_rect(part, COLOR)
