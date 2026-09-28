extends Node
## Autoload: Musik und Soundeffekte. Ton startet erst nach dem ersten Tippen (Browser-Regel und Plan).
## Alle Buttons klicken automatisch, außer sie stehen in der Gruppe "silent_button".

const MUSIC := {
	"menu": preload("res://assets/audio/music/menu.ogg"),
	"battle": preload("res://assets/audio/music/battle.ogg"),
}
const SFX := {
	"click": preload("res://assets/audio/sfx/click.ogg"),
	"buy": preload("res://assets/audio/sfx/buy.ogg"),
	"sell": preload("res://assets/audio/sfx/sell.ogg"),
	"merge": preload("res://assets/audio/sfx/merge.ogg"),
	"reroll": preload("res://assets/audio/sfx/reroll.ogg"),
	"error": preload("res://assets/audio/sfx/error.ogg"),
	"hit_1": preload("res://assets/audio/sfx/hit_1.ogg"),
	"hit_2": preload("res://assets/audio/sfx/hit_2.ogg"),
	"hit_3": preload("res://assets/audio/sfx/hit_3.ogg"),
	"death": preload("res://assets/audio/sfx/death.ogg"),
	"shield": preload("res://assets/audio/sfx/shield.ogg"),
	"poison": preload("res://assets/audio/sfx/poison.ogg"),
	"win": preload("res://assets/audio/sfx/win.ogg"),
	"loss": preload("res://assets/audio/sfx/loss.ogg"),
	"run_won": preload("res://assets/audio/sfx/run_won.ogg"),
	"run_lost": preload("res://assets/audio/sfx/run_lost.ogg"),
}
const HITS := ["hit_1", "hit_2", "hit_3"]
const PLAYERS := 8
## Gleicher Effekt höchstens so oft pro Sekunde, sonst klingt ein voller Kampf wie Rauschen.
const MIN_REPEAT_S := 0.06
const MUSIC_BUS := "Music"
const SFX_BUS := "SFX"

var _music: AudioStreamPlayer
var _players: Array[AudioStreamPlayer] = []
var _next_player := 0
var _next_hit := 0
var _last_played: Dictionary = {}
var _unlocked := false
var _wanted_music := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for bus in [MUSIC_BUS, SFX_BUS]:
		if AudioServer.get_bus_index(bus) < 0:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, bus)
	_music = AudioStreamPlayer.new()
	_music.bus = MUSIC_BUS
	add_child(_music)
	for i in PLAYERS:
		var player := AudioStreamPlayer.new()
		player.bus = SFX_BUS
		add_child(player)
		_players.append(player)
	for stream: AudioStreamOggVorbis in MUSIC.values():
		stream.loop = true
	Prefs.changed.connect(_apply_volumes)
	_apply_volumes()
	get_tree().node_added.connect(_on_node_added)


func _input(event: InputEvent) -> void:
	if _unlocked:
		return
	if (event is InputEventMouseButton or event is InputEventScreenTouch) and event.pressed:
		_unlocked = true
		if _wanted_music != "":
			var wanted := _wanted_music
			_wanted_music = ""
			play_music(wanted)


func play_music(track: String) -> void:
	if not _unlocked:
		_wanted_music = track
		return
	if _music.playing and _music.stream == MUSIC[track]:
		return
	_music.stream = MUSIC[track]
	_music.play()


func play(effect: String) -> void:
	if not _unlocked:
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_last_played.get(effect, -1.0)) < MIN_REPEAT_S:
		return
	_last_played[effect] = now
	var player := _players[_next_player]
	_next_player = (_next_player + 1) % _players.size()
	player.stream = SFX[effect]
	player.play()


## Treffer reihum aus drei Varianten, damit es nicht monoton klingt.
func play_hit() -> void:
	play(HITS[_next_hit])
	_next_hit = (_next_hit + 1) % HITS.size()


func _apply_volumes() -> void:
	_set_bus_volume(MUSIC_BUS, Prefs.music_volume)
	_set_bus_volume(SFX_BUS, Prefs.sfx_volume)


func _set_bus_volume(bus: String, volume: float) -> void:
	var index := AudioServer.get_bus_index(bus)
	AudioServer.set_bus_mute(index, volume <= 0.0)
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(volume, 0.001)))


func _on_node_added(node: Node) -> void:
	if node is BaseButton:
		node.pressed.connect(func() -> void:
			if not node.is_in_group("silent_button"):
				play("click"))
