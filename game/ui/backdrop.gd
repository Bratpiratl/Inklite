class_name Backdrop
extends ColorRect
## Hintergrund der Menüs und des Shops: Petrol mit großen, blassen Kachelformen. Nur Zeichnung.

const BASE := Color(0.113725, 0.403922, 0.462745)
const SHAPE := Color(0.152941, 0.47451, 0.537255)
const TILE := 104.0
const BLOCK := 44.0
const NOTCH := 18.0


func _ready() -> void:
	color = BASE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func _draw() -> void:
	var rows := int(ceil(size.y / TILE)) + 1
	var cols := int(ceil(size.x / TILE)) + 1
	for row in rows:
		for col in cols:
			var shift := TILE / 2.0 if row % 2 == 1 else 0.0
			var corner := Vector2(col * TILE + shift - TILE / 4.0, row * TILE + 12.0)
			# Block mit ausgeschnittener Ecke und einem schrägen Streifen, wie gefaltetes Papier.
			draw_rect(Rect2(corner, Vector2(BLOCK, BLOCK)), SHAPE)
			draw_rect(Rect2(corner + Vector2(BLOCK - NOTCH, 0), Vector2(NOTCH, NOTCH)), BASE)
			draw_colored_polygon(PackedVector2Array([
				corner + Vector2(BLOCK + 6, 4), corner + Vector2(BLOCK + 14, 4),
				corner + Vector2(BLOCK + 14 - BLOCK * 0.6, BLOCK * 0.6 + 4), corner + Vector2(BLOCK + 6 - BLOCK * 0.6, BLOCK * 0.6 + 4),
			]), SHAPE)
