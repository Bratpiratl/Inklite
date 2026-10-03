extends Control
## Titelbildschirm: weiterspielen, neuer Run, Workshop, Historie, Einstellungen, klassischer Modus.

const PARADE_SIZE := 5
const BOB_HEIGHT := 4.0
const BOB_TIME := 0.5

@onready var _continue: Button = %ContinueButton
@onready var _start: Button = %StartButton
@onready var _parade: HBoxContainer = %Parade

func _ready() -> void:
	_continue.pressed.connect(_on_continue)
	_start.pressed.connect(_on_start)
	%HistoryButton.pressed.connect(func() -> void: Session.goto(Session.HISTORY_SCENE))
	%WorkshopButton.pressed.connect(func() -> void:
		Session.workshop_test = true
		Session.goto(Session.WORKSHOP_SCENE))
	%SettingsButton.pressed.connect(func() -> void: Session.goto(Session.SETTINGS_SCENE))
	%HelpButton.pressed.connect(func() -> void: Session.open_help(Session.TITLE_SCENE))
	%ClassicButton.pressed.connect(func() -> void:
		Session.classic_mode = not Session.classic_mode
		Audio.play("click")
		_show_mode())
	%VersionLabel.text = Loc.t("VERSION", {"v": RunLogger.version()})
	_build_parade()
	_show_mode()
	Audio.play_music("menu")


## Neuer Modus: Fortsetzen und Neuer Run laufen über den Workshop-Regelsatz. Klassisch: alter Ablauf.
func _show_mode() -> void:
	var has_workshop := FileAccess.file_exists(Session.WORKSHOP_DATA)
	if not has_workshop:
		Session.classic_mode = true
	var has_save := Session.has_save() if Session.classic_mode else Session.has_workshop_save()
	_continue.visible = has_save
	# Die wichtigste Aktion bekommt den hellen Button.
	_start.theme_type_variation = &"" if has_save else &"PrimaryButton"
	_continue.theme_type_variation = &"PrimaryButton"
	%WorkshopButton.visible = has_workshop and not Session.classic_mode
	%Subtitle.text = Loc.t("TITLE_CLASSIC" if Session.classic_mode else "TITLE_SUBTITLE")
	%ClassicButton.visible = has_workshop
	%ClassicButton.text = Loc.t("BTN_CLASSIC_BACK" if Session.classic_mode else "BTN_CLASSIC")


func _on_start() -> void:
	if Session.classic_mode:
		Session.goto(Session.TRAINER_SCENE)
		return
	Session.workshop_test = false
	Session.workshop_continue = false
	Session.goto(Session.WORKSHOP_SCENE)


func _on_continue() -> void:
	if not Session.classic_mode:
		Session.workshop_test = false
		Session.workshop_continue = true
		Session.goto(Session.WORKSHOP_SCENE)
	elif Session.load_run():
		Session.goto(Session.SHOP_SCENE)
	else:
		Session.clear_save()
		_continue.visible = false


## Ein paar Monster hüpfen versetzt unter dem Logo. Reine Deko, Zufall darf hier aus der Uhr kommen.
func _build_parade() -> void:
	var ids := Session.db.ids()
	var rng := GameRng.new(Time.get_ticks_usec())
	rng.shuffle(ids)
	for i in mini(PARADE_SIZE, ids.size()):
		var holder := Control.new()
		holder.custom_minimum_size = Vector2(48, 48 + BOB_HEIGHT)
		var sprite := TextureRect.new()
		sprite.texture = load(Session.SPRITE_ROOT + Session.db.get_def(ids[i])["sprite"])
		sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		sprite.size = Vector2(48, 48)
		sprite.position.y = BOB_HEIGHT
		holder.add_child(sprite)
		_parade.add_child(holder)
		var tween := sprite.create_tween().set_loops()
		tween.tween_interval(i * BOB_TIME / PARADE_SIZE)
		tween.tween_property(sprite, "position:y", 0.0, BOB_TIME).set_trans(Tween.TRANS_SINE)
		tween.tween_property(sprite, "position:y", BOB_HEIGHT, BOB_TIME).set_trans(Tween.TRANS_SINE)
