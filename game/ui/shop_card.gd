class_name ShopCard
extends Button
## Ein Angebot im Shop. Tippen zeigt die Info-Karte, Ziehen auf ein Feld kauft dorthin.
## Aussehen: Karte in der Typfarbe, Werte als Plaketten, unten Name und Preis. Fehlt das Gold,
## wird sie grau und der Preis rot.

const SPRITE_ROOT := "res://assets/sprites/"
const DRAG_KIND := "shop_offer"
const TYPE_COLORS := {
	"feuer": Color(0.941176, 0.517647, 0.298039),
	"wasser": Color(0.309804, 0.619608, 0.909804),
	"moos": Color(0.454902, 0.756863, 0.25098),
	"blitz": Color(0.94902, 0.760784, 0.188235),
}
const POOR_COLOR := Color(0.662745, 0.654902, 0.721569)
const EMPTY_COLOR := Color(0.25, 0.23, 0.32, 0.55)
const OUTLINE := Color(0.121569, 0.105882, 0.164706)
const POOR_SPRITE := Color(0.55, 0.55, 0.6)
const PRICE_COLOR := Color(0.227451, 0.211765, 0.282353)
const PRICE_POOR := Color(0.85, 0.15, 0.25)

var index := -1
var _has_offer := false
var _type := ""
var _base_color := POOR_COLOR


func show_offer(def: Dictionary, stats: Dictionary) -> void:
	_has_offer = true
	_type = def.get("type", "")
	_base_color = TYPE_COLORS.get(_type, POOR_COLOR)
	%Sprite.texture = load(SPRITE_ROOT + def["sprite"])
	%AtkLabel.text = str(stats["atk"])
	%HpLabel.text = str(stats["hp"])
	%CostLabel.text = Loc.t("COST", {"n": def["cost"]})
	%NameLabel.text = Loc.monster(def["id"])
	_show_parts()


## Angebot ohne MonsterDb (Workshop-Test): Name, Bild, Werte, Preis und Kartenfarbe direkt.
func show_custom(unit_name: String, texture: Texture2D, atk: int, hp: int, cost: int, color: Color) -> void:
	_has_offer = true
	_base_color = color
	%Sprite.texture = texture
	%AtkLabel.text = str(atk)
	%HpLabel.text = str(hp)
	%CostLabel.text = Loc.t("COST", {"n": cost})
	%NameLabel.text = unit_name
	disabled = false
	_show_parts()


func _show_parts() -> void:
	for node: CanvasItem in [%Sprite, %AtkLabel, %HpLabel, %Footer]:
		node.visible = true
	set_affordable(true)


## Grau mit rotem Preis, wenn das Gold nicht reicht. Antippen bleibt möglich, die Karte erklärt es.
func set_affordable(value: bool) -> void:
	_apply_color(_base_color if value else POOR_COLOR)
	%Sprite.modulate = Color.WHITE if value else POOR_SPRITE
	%CostLabel.add_theme_color_override("font_color", PRICE_COLOR if value else PRICE_POOR)


func set_selected(selected: bool) -> void:
	%Brackets.visible = selected


func set_frozen(value: bool) -> void:
	%FrozenFrame.visible = value


## Wie viele gleiche Monster auf Stufe 1 schon im Team stehen, z. B. "2/3". 0 blendet aus.
func set_merge_progress(copies: int, needed: int) -> void:
	%MergeBadge.text = Loc.t("MERGE_PROGRESS", {"n": copies, "max": needed})
	%MergeBadge.visible = copies > 0


func _get_drag_data(_at_position: Vector2) -> Variant:
	if not _has_offer:
		return null
	var preview := Control.new()
	var image := TextureRect.new()
	image.texture = %Sprite.texture
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.size = %Sprite.size
	image.position = -%Sprite.size / 2.0
	preview.add_child(image)
	set_drag_preview(preview)
	return {"kind": DRAG_KIND, "index": index}


func show_empty() -> void:
	_has_offer = false
	set_frozen(false)
	set_selected(false)
	%MergeBadge.visible = false
	for node: CanvasItem in [%Sprite, %AtkLabel, %HpLabel, %Footer]:
		node.visible = false
	_apply_color(EMPTY_COLOR, false)
	disabled = true


func _apply_color(color: Color, outlined: bool = true) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = color
	normal.set_corner_radius_all(3)
	normal.anti_aliasing = false
	if outlined:
		normal.border_color = OUTLINE
		normal.set_border_width_all(2)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = color.darkened(0.15)
	for state in ["normal", "hover", "focus", "disabled"]:
		add_theme_stylebox_override(state, normal)
	for state in ["pressed", "hover_pressed"]:
		add_theme_stylebox_override(state, pressed)
