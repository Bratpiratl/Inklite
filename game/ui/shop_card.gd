class_name ShopCard
extends Button
## Ein Angebot im Shop. Tippen zeigt die Info-Karte, Ziehen auf ein Feld kauft dorthin.

const SPRITE_ROOT := "res://assets/sprites/"
const SELECTED := Color(1.35, 1.3, 1.0)
const DRAG_KIND := "shop_offer"

var index := -1
var _has_offer := false


func show_offer(def: Dictionary, stats: Dictionary) -> void:
	_has_offer = true
	%Sprite.texture = load(SPRITE_ROOT + def["sprite"])
	%Sprite.visible = true
	%AtkLabel.text = str(stats["atk"])
	%HpLabel.text = str(stats["hp"])
	%CostLabel.text = Loc.t("COST", {"n": def["cost"]})
	%AtkLabel.visible = true
	%HpLabel.visible = true
	%CostLabel.visible = true


func set_selected(selected: bool) -> void:
	modulate = SELECTED if selected else Color.WHITE


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
	%MergeBadge.visible = false
	%Sprite.visible = false
	%AtkLabel.visible = false
	%HpLabel.visible = false
	%CostLabel.visible = false
	disabled = true
