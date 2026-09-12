extends Node
## Owns all music/SFX playback — two dedicated buses (Music, SFX) exist under
## Master (see default_bus_layout.tres) purely so a future settings screen
## can expose independent volume sliders via AudioServer directly, without
## this script needing to know a settings UI exists.
##
## Every call here gates on ResourceLoader.exists() and no-ops if a path
## isn't there yet — the same "safe to wire in before the asset exists"
## contract GameData.hero_anim_frames/monster_anim_frames already use, so
## call sites can reference GameData.SFX_PATH/MUSIC_PATH entries for tracks
## that haven't been sourced yet without erroring.

const CROSSFADE_MIN_DB := -40.0

var _music_players: Array[AudioStreamPlayer] = []
var _current_music_idx := 0
var _current_music_path := ""
var _sfx_players: Array[AudioStreamPlayer] = []
var _sfx_next := 0


func _ready() -> void:
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.bus = "Music"
		add_child(p)
		_music_players.append(p)
	for i in 6:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_sfx_players.append(p)


## Crossfades to `path` over `fade_time` seconds; pass "" to just fade out
## whatever's playing. Repeat calls with the same path are a no-op (a screen
## re-render shouldn't restart its own music). Forces the loaded stream's own
## `loop` flag on regardless of import defaults, rather than trusting the
## format's default (AudioStreamOggVorbis/AudioStreamWAV both expose it),
## so a track always loops here without needing a matching .import tweak.
func play_music(path: String, fade_time: float = 1.0) -> void:
	if path == _current_music_path:
		return
	if path != "" and not ResourceLoader.exists(path):
		return
	var old_player := _music_players[_current_music_idx]
	var had_old := old_player.playing
	_current_music_idx = 1 - _current_music_idx
	var new_player := _music_players[_current_music_idx]
	_current_music_path = path
	if had_old:
		var fade_out := create_tween()
		fade_out.tween_property(old_player, "volume_db", CROSSFADE_MIN_DB, fade_time)
		fade_out.tween_callback(old_player.stop)
	if path == "":
		return
	var stream: AudioStream = load(path)
	if "loop" in stream:
		stream.loop = true
	new_player.stream = stream
	new_player.volume_db = CROSSFADE_MIN_DB
	new_player.play()
	var fade_in := create_tween()
	fade_in.tween_property(new_player, "volume_db", 0.0, fade_time)


func stop_music(fade_time: float = 1.0) -> void:
	play_music("", fade_time)


## One-shot SFX from a round-robin pool so two quick hits in the same round
## don't cut each other off the way a single shared AudioStreamPlayer would.
func play_sfx(path: String) -> void:
	if path == "" or not ResourceLoader.exists(path):
		return
	var p := _sfx_players[_sfx_next]
	_sfx_next = (_sfx_next + 1) % _sfx_players.size()
	p.stream = load(path)
	p.play()


## `linear` is 0.0-1.0 (what a settings slider would hand in) — converted to
## the dB scale AudioServer actually uses.
func set_music_volume(linear: float) -> void:
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), linear_to_db(clampf(linear, 0.0001, 1.0)))


func set_sfx_volume(linear: float) -> void:
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("SFX"), linear_to_db(clampf(linear, 0.0001, 1.0)))
