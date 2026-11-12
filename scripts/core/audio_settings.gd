class_name AudioSettings
extends RefCounted
## Two volume sliders (owner, round 5): music and sound effects, changed in the pause menu and saved
## in user://settings.cfg. Music and effects play on their own buses, and nothing ever lowers the
## music when an effect plays: no ducking, no compressor on the master. The effects bus sits a few
## dB down so a pile of explosions doesn't push the sum past full scale (that clipping, or Windows
## "Loudness Equalization" reacting to it, is what makes music seem to dip).

const PATH := "user://settings.cfg"
const MUSIC_BUS := "Music"
const SFX_BUS := "SFX"
const SFX_HEADROOM_DB := -5.0
const STEP := 0.1

static var music := 0.8 # 0..1
static var sfx := 0.8


static func setup() -> void:
	for bus: String in [MUSIC_BUS, SFX_BUS]:
		if AudioServer.get_bus_index(bus) < 0:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, bus)
			AudioServer.set_bus_send(i, "Master")
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		music = cfg.get_value("audio", "music", music)
		sfx = cfg.get_value("audio", "sfx", sfx)
	_apply()


## kind "music" or "sfx", step +1 / -1.
static func change(kind: String, step: int) -> void:
	if kind == "music":
		music = clampf(snappedf(music + STEP * step, 0.01), 0.0, 1.0)
	else:
		sfx = clampf(snappedf(sfx + STEP * step, 0.01), 0.0, 1.0)
	_apply()
	var cfg := ConfigFile.new()
	cfg.load(PATH)
	cfg.set_value("audio", "music", music)
	cfg.set_value("audio", "sfx", sfx)
	cfg.save(PATH)


static func label() -> String:
	return "MUSIC %d%%  (- / +)     EFFECTS %d%%  ([ / ])" % [roundi(music * 100.0), roundi(sfx * 100.0)]


static func _apply() -> void:
	var mi := AudioServer.get_bus_index(MUSIC_BUS)
	var si := AudioServer.get_bus_index(SFX_BUS)
	AudioServer.set_bus_volume_db(mi, linear_to_db(maxf(music, 0.0001)))
	AudioServer.set_bus_mute(mi, music <= 0.001)
	AudioServer.set_bus_volume_db(si, linear_to_db(maxf(sfx, 0.0001)) + SFX_HEADROOM_DB)
	AudioServer.set_bus_mute(si, sfx <= 0.001)
