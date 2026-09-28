class_name BattleFx
extends Control
## Effektebene der Kampfansicht: Pixel-Partikel, Ringe, aufsteigende Zahlen und Bildschirmwackeln.
## Reine Darstellung. Der Zufall der Partikel kommt aus einem festen Seed, der bei jedem Neustart
## zurückgesetzt wird, damit ein Kampf beim erneuten Abspielen genau gleich aussieht.

const PIXEL := 3.0
const RNG_SEED := 7  # Kantenlänge eines Partikels in Canvas-Pixeln
const FLOAT_RISE := 26.0
const POP_SCALE := 1.7
const BIG_HIT := 5  # ab diesem Schaden: größere Zahl und Wackeln
const SHAKE_PATTERN: Array[Vector2] = [Vector2(3, -2), Vector2(-3, 2), Vector2(2, 3), Vector2(-2, -1), Vector2(1, 1)]
const CONFETTI_PER_COLOR := 16
const CONFETTI_LIFETIME := 2.2
const CONFETTI: Array[Color] = [Color(1, 0.85, 0.4), Color(0.56, 1, 0.42), Color(0.5, 0.8, 1), Color(1, 0.46, 0.46), Color(0.85, 0.7, 1)]

## Abspielgeschwindigkeit, setzt die Kampfansicht (1x, 2x).
var speed := 1.0

var _shake_tween: Tween
var _rng := GameRng.new(RNG_SEED)


## Räumt auf und setzt den Zufall zurück, damit eine Wiederholung gleich aussieht.
func clear() -> void:
	for child in get_children():
		child.queue_free()
	_rng = GameRng.new(RNG_SEED)


# --- Zahlen und Texte ---

## Text, der kurz aufploppt, aufsteigt und verblasst. anchor ist ein Feld oder ein Raster.
func float_text(anchor: Control, text: String, color: Color, font_size: int = 16) -> void:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 6)
	label.add_theme_font_size_override("font_size", font_size)
	add_child(label)
	label.size = Vector2(anchor.size.x + 48, font_size + 8)
	label.pivot_offset = label.size / 2.0
	label.position = _local(anchor) + Vector2(-24, anchor.size.y / 2.0 - label.size.y - 6)
	label.scale = Vector2.ONE * POP_SCALE
	var duration := BattleTiming.T_FLOAT / speed
	var tween := label.create_tween()
	tween.tween_property(label, "scale", Vector2.ONE, duration * 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(label, "position:y", label.position.y - FLOAT_RISE, duration).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(label, "modulate:a", 0.0, duration * 0.5).set_delay(duration * 0.5)
	tween.tween_callback(label.queue_free)


## Schadenszahl: große Treffer sind größer und lassen den Bildschirm wackeln.
func damage_number(anchor: Control, amount: int, color: Color, shake_target: Control) -> void:
	var big := amount >= BIG_HIT
	float_text(anchor, "-%d" % amount, color, 24 if big else 16)
	if big:
		shake(shake_target, 1.0)


# --- Partikel ---

## Funken beim Treffer, fliegen weg vom Angreifer (direction) und fallen.
func sparks(anchor: Control, color: Color, direction: Vector2 = Vector2.UP, amount: int = 10) -> void:
	_burst(anchor, color, amount, direction, 70.0, 60.0, 140.0, Vector2(0, 260), 0.35)


## Rauchwolke beim Tod.
func puff(anchor: Control) -> void:
	_burst(anchor, Color(0.62, 0.6, 0.68), 16, Vector2.UP, 180.0, 20.0, 70.0, Vector2(0, -30), 0.6)


## Aufsteigende Blasen (Gift) oder Funken (Buff).
func rise(anchor: Control, color: Color, amount: int = 8) -> void:
	_burst(anchor, color, amount, Vector2.UP, 35.0, 30.0, 60.0, Vector2(0, -40), 0.7, 0.5)


## Konfettiregen über die ganze Breite der Effektebene, gestaffelt von oben.
func confetti() -> void:
	for color in CONFETTI:
		var burst := _new_burst()
		burst.setup(_rng, color, CONFETTI_PER_COLOR, Vector2(size.x / 2.0, -8), Vector2(size.x / 2.0, 4),
			Vector2.DOWN, 25.0, 60.0, 160.0, CONFETTI_LIFETIME, PIXEL + 1.0, 0.8)
		burst.gravity = Vector2(0, 90)


func _burst(anchor: Control, color: Color, amount: int, direction: Vector2, spread: float,
		speed_min: float, speed_max: float, gravity: Vector2, lifetime: float, explosiveness: float = 1.0) -> void:
	var burst := _new_burst()
	burst.setup(_rng, color, amount, _local(anchor) + anchor.size / 2.0, anchor.size / 4.0, direction,
		spread, speed_min, speed_max, lifetime, PIXEL, lifetime * (1.0 - explosiveness))
	burst.gravity = gravity


func _new_burst() -> PixelBurst:
	var burst := PixelBurst.new()
	burst.speed = speed
	add_child(burst)
	return burst


# --- Ringe und Wackeln ---

## Quadratischer Pixel-Ring um ein Feld, der sich weitet und verblasst (Schild, Fähigkeit).
func ring(anchor: Control, color: Color) -> void:
	var box := Panel.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(color, 0.15)
	style.border_color = color
	style.set_border_width_all(3)
	box.add_theme_stylebox_override("panel", style)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	box.size = anchor.size
	box.position = _local(anchor)
	box.pivot_offset = box.size / 2.0
	box.scale = Vector2.ONE * 0.8
	var duration := 0.4 / speed
	var tween := box.create_tween().set_parallel()
	tween.tween_property(box, "scale", Vector2.ONE * 1.25, duration).set_ease(Tween.EASE_OUT)
	tween.tween_property(box, "modulate:a", 0.0, duration).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(box.queue_free)


## Kurzes Wackeln in festen Pixelschritten.
func shake(target: Control, strength: float) -> void:
	if _shake_tween != null and _shake_tween.is_valid():
		_shake_tween.kill()
	var home := Vector2.ZERO
	_shake_tween = target.create_tween()
	for offset in SHAKE_PATTERN:
		_shake_tween.tween_property(target, "position", home + (offset * strength).round(), 0.03 / speed)
	_shake_tween.tween_property(target, "position", home, 0.03 / speed)


func _local(control: Control) -> Vector2:
	return control.global_position - global_position
