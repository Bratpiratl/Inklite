class_name UnitCell
extends Control
## Ein Feld des 3x3-Rasters: Boden, Monster-Sprite und Werte. Nur Darstellung, keine Spiellogik.
## Im Shop lassen sich Monster antippen und auf andere Felder oder eine DropZone ziehen.

signal tapped(slot: int)
signal dropped_on(from_slot: int, to_slot: int)
signal offer_dropped(offer_index: int, slot: int)

const DRAG_KIND := "board_unit"
const HIGHLIGHT := Color(1.45, 1.3, 0.75)
const SPRITE_ROOT := "res://assets/sprites/"
const LUNGE_DISTANCE := 16.0
const KNOCK_DISTANCE := 5.0
const HP_LAG_DELAY := 0.15
const HP_HIGH := Color(0.45, 0.85, 0.35)
const HP_MID := Color(0.95, 0.8, 0.3)
const HP_LOW := Color(0.95, 0.35, 0.3)
const DEAD_ALPHA := 0.0
const DRAG_SOURCE_ALPHA := 0.35
const EMPTY_FLOOR := Color(0.55, 0.55, 0.6)
const EMPTY_SLOT := Color(0.86, 0.86, 0.92)
const HIGHLIGHT_SLOT := Color(1.0, 0.8, 0.3)
const SLOT_STYLE := preload("res://ui/slot_style.tres")
const LEVEL_COLOR := Color(0.227451, 0.211765, 0.282353)
const LEVEL_MAX_COLOR := Color(0.941176, 0.564706, 0.117647)
const PILL_SIZE := Vector2(24, 15)

@onready var _floor: TextureRect = $Floor
@onready var _body: Control = $Body
@onready var _sprite: TextureRect = $Body/Sprite
@onready var _atk_label: Label = %AtkLabel
@onready var _hp_label: Label = %HpLabel
@onready var _shield_label: Label = %ShieldLabel
@onready var _poison_label: Label = %PoisonLabel
@onready var _level_label: Label = %LevelLabel
@onready var _hp_bar: Control = %HpBar
@onready var _hp_fill: ColorRect = %HpFill
@onready var _hp_lag: ColorRect = %HpLag

var slot := -1
var unit_id := ""
var level := 1
var atk := 0
## Im Kampf nur antippbar, im Shop auch ziehbar.
var draggable := true
var hp := 0
var shield := 0
var poison := 0
var max_hp := 1
## HP-Balken nur im Kampf, im Shop reichen die Zahlen.
var show_hp_bar := false

var _interactive := false
var _has_unit := false
## Prüft, ob ein gezogenes Shop-Angebot (Index) hier gekauft werden darf. Setzt der Shop.
var offer_check: Callable

var _tweens: Array[Tween] = []
var _highlight_tween: Tween
## Kartenstil im Shop: helles Feld mit Rand, Stufe oben links, Werte als Plaketten unten.
## Die Kampfansicht nutzt weiter den Boden.
var _card_style := false
var _ground: CanvasItem


func _ready() -> void:
	_ground = _floor


func set_card_style() -> void:
	_card_style = true
	var slot_panel := Panel.new()
	slot_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot_panel.add_theme_stylebox_override("panel", SLOT_STYLE)
	add_child(slot_panel)
	move_child(slot_panel, 0)
	slot_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_floor.visible = false
	_ground = slot_panel
	_ground.modulate = EMPTY_SLOT
	_pill(_atk_label, &"PillOrange", -PILL_SIZE.x - 1)
	_pill(_hp_label, &"PillRed", 1)
	_level_label.remove_theme_color_override("font_color")
	_level_label.theme_type_variation = &"PanelLabel"
	_level_label.add_theme_font_size_override("font_size", 10)
	_level_label.add_theme_color_override("font_outline_color", Color.WHITE)
	_level_label.add_theme_constant_override("outline_size", 4)
	_sprite.position.y += 4
	_level_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_level_label.position = Vector2(5, 3)
	_level_label.size = Vector2(40, 12)
	_level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT


func _pill(label: Label, variation: StringName, x_from_center: float) -> void:
	label.remove_theme_color_override("font_color")
	label.remove_theme_color_override("font_outline_color")
	label.remove_theme_constant_override("outline_size")
	label.remove_theme_font_size_override("font_size")
	label.theme_type_variation = variation
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	label.offset_left = x_from_center
	label.offset_right = x_from_center + PILL_SIZE.x
	label.offset_top = -PILL_SIZE.y - 4
	label.offset_bottom = -4


func set_floor(texture: Texture2D) -> void:
	_floor.texture = texture


func set_interactive(value: bool) -> void:
	_interactive = value
	mouse_filter = Control.MOUSE_FILTER_STOP if value else Control.MOUSE_FILTER_IGNORE


func show_unit(id: String, sprite_path: String, start_hp: int, start_atk: int, unit_level: int, flip: bool) -> void:
	unit_id = id
	level = unit_level
	atk = start_atk
	_stop_tweens()
	_has_unit = true
	_ground.modulate = Color.WHITE
	_body.position = Vector2.ZERO
	_body.modulate = Color.WHITE
	_body.scale = Vector2.ONE
	_body.rotation = 0.0
	_body.visible = true
	_sprite.texture = load(SPRITE_ROOT + sprite_path)
	_sprite.flip_h = flip
	_atk_label.text = str(atk)
	_level_label.text = Loc.t("LEVEL_SHORT", {"n": level})
	_level_label.visible = level > 1 or _card_style
	if _card_style:
		_level_label.add_theme_color_override("font_color", LEVEL_MAX_COLOR if level >= 3 else LEVEL_COLOR)
	max_hp = maxi(start_hp, 1)
	_hp_bar.visible = show_hp_bar
	set_stats(start_hp, 0, 0)
	_hp_lag.size.x = _hp_fill.size.x


func clear() -> void:
	_stop_tweens()
	_has_unit = false
	_ground.modulate = _empty_color()
	_body.visible = false


func set_stats(new_hp: int, new_shield: int, new_poison: int) -> void:
	hp = new_hp
	shield = new_shield
	poison = new_poison
	_hp_label.text = str(maxi(hp, 0))
	_shield_label.text = str(shield)
	_shield_label.visible = shield > 0
	_poison_label.text = str(poison)
	_poison_label.visible = poison > 0
	_update_hp_bar()


func set_atk(value: int) -> void:
	atk = value
	_atk_label.text = str(atk)


## Balken sofort auf den neuen Stand, der helle Rest läuft kurz hinterher.
func _update_hp_bar() -> void:
	max_hp = maxi(max_hp, hp)
	var ratio := clampf(float(hp) / max_hp, 0.0, 1.0)
	var width := roundf(_hp_bar.size.x * ratio)
	_hp_fill.size.x = width
	_hp_fill.color = HP_HIGH if ratio > 0.5 else (HP_MID if ratio > 0.25 else HP_LOW)
	if _hp_lag.size.x < width:
		_hp_lag.size.x = width
	else:
		var tween := _new_tween()
		tween.tween_interval(HP_LAG_DELAY)
		tween.tween_property(_hp_lag, "size:x", width, 0.25)


## Mittelpunkt des Feldes in globalen Koordinaten.
func center() -> Vector2:
	return global_position + size / 2.0


## Vorstoß Richtung Ziel und zurück. Der Aufprall liegt in der Mitte der Dauer.
func lunge(target_center: Vector2, duration: float) -> void:
	var offset := (target_center - center()).normalized() * LUNGE_DISTANCE
	var tween := _new_tween()
	tween.tween_property(_body, "position", offset.round(), duration * 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_property(_body, "position", Vector2.ZERO, duration * 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


## Kurz wegstoßen, weg vom Angreifer.
func knock(from: Vector2, duration: float) -> void:
	var dir := (center() - from).normalized()
	var tween := _new_tween()
	tween.tween_property(_body, "position", (dir * KNOCK_DISTANCE).round(), duration * 0.3).set_ease(Tween.EASE_OUT)
	tween.tween_property(_body, "position", Vector2.ZERO, duration * 0.7).set_ease(Tween.EASE_IN_OUT)


## Aufploppen zu Kampfbeginn.
func pop_in(delay: float, duration: float) -> void:
	_body.pivot_offset = _body.size / 2.0
	_body.scale = Vector2.ZERO
	var tween := _new_tween()
	tween.tween_interval(delay)
	tween.tween_property(_body, "scale", Vector2.ONE, duration).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func flash(color: Color, duration: float) -> void:
	var tween := _new_tween()
	_sprite.modulate = color
	tween.tween_property(_sprite, "modulate", Color.WHITE, duration)


## Aufblitzen, schrumpfen, wegkippen, ausblenden.
func die(duration: float) -> void:
	_body.pivot_offset = _body.size / 2.0
	_sprite.modulate = Color(3, 3, 3)
	var tween := _new_tween()
	tween.tween_property(_sprite, "modulate", Color.WHITE, duration * 0.3)
	tween.tween_property(_body, "scale", Vector2.ONE * 0.4, duration * 0.7).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(_body, "rotation", deg_to_rad(-25), duration * 0.7)
	tween.parallel().tween_property(_body, "modulate:a", DEAD_ALPHA, duration * 0.7)
	tween.tween_callback(clear)


# --- Eingabe (nur im Shop) ---

func _gui_input(event: InputEvent) -> void:
	if not _interactive or not _has_unit:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		tapped.emit(slot)
		accept_event()


func has_unit() -> bool:
	return _has_unit


func _get_drag_data(_at_position: Vector2) -> Variant:
	if not _interactive or not draggable or not _has_unit:
		return null
	var preview := Control.new()
	var image := TextureRect.new()
	image.texture = _sprite.texture
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.size = _sprite.size
	image.position = -_sprite.size / 2.0
	preview.add_child(image)
	set_drag_preview(preview)
	_body.modulate.a = DRAG_SOURCE_ALPHA
	return {"kind": DRAG_KIND, "slot": slot}


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if not (_interactive and draggable and data is Dictionary):
		return false
	var kind: String = data.get("kind", "")
	if kind == DRAG_KIND:
		return true
	if kind == ShopCard.DRAG_KIND:
		return offer_check.is_valid() and offer_check.call(int(data["index"]), slot)
	return false


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	if data.get("kind", "") == ShopCard.DRAG_KIND:
		offer_dropped.emit(int(data["index"]), slot)
	else:
		dropped_on.emit(int(data["slot"]), slot)


## Boden pulsiert golden: mögliches Ziel oder passender Verschmelz-Partner.
func set_highlight(value: bool) -> void:
	if _highlight_tween != null:
		_highlight_tween.kill()
		_highlight_tween = null
	var base := Color.WHITE if _has_unit else _empty_color()
	_ground.modulate = base
	if value:
		_highlight_tween = create_tween().set_loops()
		_highlight_tween.tween_property(_ground, "modulate", HIGHLIGHT_SLOT if _card_style else HIGHLIGHT, 0.35)
		_highlight_tween.tween_property(_ground, "modulate", base, 0.35)


func _empty_color() -> Color:
	return EMPTY_SLOT if _card_style else EMPTY_FLOOR


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END and _has_unit:
		_body.modulate.a = 1.0


func _new_tween() -> Tween:
	var tween := create_tween()
	_tweens.append(tween)
	tween.finished.connect(func() -> void: _tweens.erase(tween))
	return tween


func _stop_tweens() -> void:
	for tween in _tweens:
		tween.kill()
	_tweens.clear()
	_sprite.modulate = Color.WHITE
