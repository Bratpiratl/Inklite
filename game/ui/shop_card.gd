class_name ShopCard
extends Button
## Ein Angebot im Shop. Tippen kauft.

const SPRITE_ROOT := "res://assets/sprites/"
const SELECTED := Color(1.35, 1.3, 1.0)


func show_offer(def: Dictionary, stats: Dictionary) -> void:
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


func show_empty() -> void:
	%Sprite.visible = false
	%AtkLabel.visible = false
	%HpLabel.visible = false
	%CostLabel.visible = false
	disabled = true
