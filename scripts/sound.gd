class_name Sound
extends Node
## Audio manager (Phase 4). One instance, made by attach() and parented to the tree root, so it survives Game's
## scene reloads: music and ambience carry on across restarts. Every static helper is a no-op until attached.
## Sounds come from SoundBank (synthesized, warmed on a worker thread) unless res://audio/<name>.ogg|.wav exists
## (drop-in replacement, like the art swap). Buses are built in code: Music, Sfx, World (ambience + positional),
## Ui, and a limiter on Master.
##   play()       one-shot on Sfx (or another bus), pooled, per-name voice cap, slight pitch jitter
##   play_at()    positional one-shot on World (the Game camera is the listener)
##   emitter()    looping positional player owned by a world node (engines, transformer hum, wing flutter)
##   loop()       named persistent loop with smoothed level/pitch (ambience beds, wind, car drone/engine)
##   set_glass()  low-pass on World/Music: 1 = inside the kid's car (muffled), 0 = in the daydream (open)
##   music() / intensity() / note()   the radio's procedural song (Music, Radio station x time of day): layers
##                by state, harmonised SFX pitch. next_station() = the car radio (R): tuning static, next station
##   pool_at() / pool_seq() / voice()   recorded variations: a random file from res://audio/<dir>/<prefix>*
##                (vehicle horns in audio/horns/<vehicle>/tap_*|long_*, civilian shouts in
##                audio/voices/<speaker>/<situation>_*, bird death squawks in audio/voices/bird/squawk_*),
##                dropped in and found at runtime. Voices play on the Voice
##                bus, whose effect chain is the "futz" (cheap-speaker sound: band-limited, overdriven, honky mids).

enum M { MENU, ZOOM, PLAY, DEAD, OVER }

## Vehicles with recorded horns (Car.horn_name(); "moto" is the motorcycle rider) and the civilian voice slots.
const HORNS := ["bubble", "hatch", "sedan", "taxi", "pickup", "van", "bus", "truck", "moto"]
const SPEAKERS := ["man", "woman", "kid"]
const SITUATIONS := ["stomp", "again", "hurt"]   ## first head-stomp, stomped again, knocked down
const BIRD_VOICE := "voices/bird/squawk"        ## a bird's last squawk (sliced, stomped or run into)
## A speaker with no recordings borrows the man's takes, pitched up.
const SPEAKER_PITCH := {"woman": 1.22, "kid": 1.42}
const POOL_EXTS := ["ogg", "wav", "mp3"]

static var inst: Sound
static var last_take := ""               ## snd_key of the last pool take started ("voices/man/stomp_2"), "" if none
static var stats := {}                    ## sound name -> times started (debug / bots)
## Per-sound volume trims (dB) from LEVELS [db], written by tools/sound_dashboard.gd. Key = synth/override name
## ("jump") or a recorded file relative to audio/ without extension ("horns/truck/tap_1").
static var trims := {}
static var bus_trims := {}                ## bus name -> dB added to BUS_DB (LEVELS [bus])
static var off := {}                      ## sound keys switched off in the dashboard (LEVELS [off]): never play
const OFF_DB := -80.0
const LEVELS := "res://audio/levels.cfg"
## Live link: the dashboard sends "trim <key> <db>", "bus <name> <db>", "reload <key>" here (debug builds only).
const LINK_PORT := 47811

const VOICES := 24
const VOICES_2D := 16
const MAX_SAME := 3                       ## concurrent voices per sound name (oldest is restarted)
const MAX_SAME_BY := {"coo": 2, "step_wire": 2, "step_street": 2, "step_roof": 2, "tick": 2}
const WORLD_GLASS_HZ := 520.0
const MUSIC_GLASS_HZ := 1500.0
const OPEN_HZ := 20000.0
## Bus levels. Voice sends into World (positional + the glass filter); the others into Master. Voice is boosted:
## the futz band-limit costs ~9 dB on speech.
const BUS_DB := {"Music": -6.0, "Sfx": -3.0, "World": -6.0, "Ui": -5.0, "Voice": 6.0}
const SETTINGS := "user://settings.cfg"
## Sounds the intro needs first; the warm-up thread builds these before the rest of SoundBank.NAMES.
const WARM_FIRST := ["splash_chime", "car_engine_ext", "car_drone", "amb_city", "amb_wind", "push_whoosh", "ui_start",
	"zoom_whoosh", "ninja_pop", "engine_car", "flutter", "transformer_hum", "engine_big", "moto", "jump",
	"double_jump", "slash", "slash_spin", "wire_land", "step_wire"]
## Music layer targets per state: PAD, BASS, DRUMS, LEAD (LEAD in PLAY follows intensity()).
const LAYERS := {
	M.MENU: [1.0, 0.7, 0.0, 0.0], M.ZOOM: [1.0, 1.0, 1.0, 0.0], M.PLAY: [1.0, 1.0, 1.0, 0.0],
	M.DEAD: [1.0, 1.0, 1.0, 0.0], M.OVER: [0.9, 0.55, 0.0, 0.0],
}
const LAYER_RATE := [0.8, 0.8, 0.75, 0.3]  ## fade speed per layer (level per second)
## Rendered songs kept in memory: the playing one + the two pre-rendered (next station, next phase) are the
## minimum; desktop keeps two more so flipping back to a station is instant. Phones keep RAM for the game.
static var MAX_SONGS := 3 if OS.has_feature("mobile") else 5
const TUNE_GAP := 0.22                    ## seconds of static between two stations
const HYPE_TIME := 6.0                    ## seconds the lead stays in after a combo / slice chain of 3+


var _players: Array[AudioStreamPlayer] = []
var _players_2d: Array[AudioStreamPlayer2D] = []
var _playing := {}                        ## player -> [sound name, start msec]
var _next := 0
var _rng := RandomNumberGenerator.new()
var _streams := {}                        ## resolved streams (overrides or SoundBank)
var _pools := {}                          ## pool key -> Array of AudioStream (recorded variations)
var _pool_last := {}                      ## pool key -> index played last (never twice in a row)
var _loops := {}                          ## name -> {p, level, cur, pitch, rate}
var _lp_world: AudioEffectLowPassFilter
var _lp_music: AudioEffectLowPassFilter
var _glass := Vector2(1.0, 1.0)           ## world, music
var _chirps := 0.0                        ## songbird chirps per second
var _chirp_t := 2.0
var _warm_task := -1
# music
var _music: AudioStreamPlayer
var _song: AudioStreamSynchronized
var _song_key := -1                       ## song_key() of the song in the player, -1 = none (rendering / tuning)
var _songs := {}                          ## song_key -> AudioStreamSynchronized (MAX_SONGS most recently used)
var _song_used := {}                      ## song_key -> msec last used
var _task := []                           ## [song_key, task id, holder] while a song renders
var _queue: Array[int] = []               ## song keys waiting to render
var _tuning := false                      ## a station switch is waiting for its song
var _mstate := M.MENU
var _layer := [0.0, 0.0, 0.0, 0.0]
var _lead := 0.0
var _hype := 0.0
var _music_level := 1.0
var _tape: Tween
var _emitters := []                       ## [AudioStreamPlayer2D, key] for live trims
var _link: PacketPeerUDP


## Create the manager once (Game._ready). Deferred add: the root is busy adding the main scene.
static func attach(tree: SceneTree) -> void:
	if inst:
		return
	inst = Sound.new()
	inst.name = "Sound"
	tree.root.add_child.call_deferred(inst)


static func _live() -> bool:
	return inst != null and inst.is_inside_tree()


## One-shot (not positional). pitch from note() for tuned sounds (pass jitter 0). delay in seconds.
static func play(name: String, pitch := 1.0, db := 0.0, delay := 0.0, jitter := 0.03, bus := "Sfx") -> void:
	if not _live():
		return
	if delay > 0.0:
		inst.get_tree().create_timer(delay).timeout.connect(inst._play.bind(name, pitch, db, jitter, bus))
	else:
		inst._play(name, pitch, db, jitter, bus)


## Positional one-shot at a world position (World bus, attenuated/panned around the camera).
static func play_at(name: String, pos: Vector2, pitch := 1.0, db := 0.0, delay := 0.0, jitter := 0.04) -> void:
	if not _live():
		return
	if delay > 0.0:
		inst.get_tree().create_timer(delay).timeout.connect(inst._play_at.bind(name, pos, pitch, db, jitter))
	else:
		inst._play_at(name, pos, pitch, db, jitter)


## Positional one-shot of a random recorded variation from pool `key` ("horns/truck/long", "voices/kid/stomp":
## res://audio/<key>*.ogg|wav|mp3), never the same file twice in a row. False if the pool has no files (callers
## fall back to a synthesized sound).
static func pool_at(key: String, pos: Vector2, pitch := 1.0, db := 0.0, delay := 0.0, bus := "World",
		jitter := 0.02) -> bool:
	return pool_seq([key], pos, pitch, db, 0.0, bus, delay, jitter)


## Pool picks back to back (honk patterns: tap, tap, long): each starts `gap` s after the previous one ends.
## False (and nothing plays) if any of the pools is empty.
static func pool_seq(keys: Array, pos: Vector2, pitch := 1.0, db := 0.0, gap := 0.08, bus := "World",
		delay := 0.0, jitter := 0.02) -> bool:
	last_take = ""
	if not _live():
		return false
	for k in keys:
		if inst._pool(k).is_empty():
			return false
	var t := delay
	for k in keys:
		var s := inst._pool_pick(k)
		last_take = str(s.get_meta("snd_key", ""))
		if t > 0.0:
			inst.get_tree().create_timer(t).timeout.connect(inst._play_stream_at.bind(k, s, pos, pitch, db, jitter, bus))
		else:
			inst._play_stream_at(k, s, pos, pitch, db, jitter, bus)
		t += s.get_length() / pitch + gap
	return true


## Number of recorded files in pool `key` (0 before attach).
static func pool_count(key: String) -> int:
	return inst._pool(key).size() if inst else 0


## A civilian shout (Voice bus = futzed): `speaker` (SPEAKERS) saying something for `situation` (SITUATIONS).
## A speaker without recordings uses the man's takes pitched up. False if there is nothing to say.
static func voice(speaker: String, situation: String, pos: Vector2, pitch := 1.0, db := 0.0, delay := 0.0) -> bool:
	if pool_at("voices/%s/%s" % [speaker, situation], pos, pitch, db, delay, "Voice", 0.0):
		return true
	return speaker != "man" and pool_at("voices/man/" + situation, pos, pitch * SPEAKER_PITCH.get(speaker, 1.0),
		db, delay, "Voice", 0.0)


## A dying bird's squawk: a random take from BIRD_VOICE through the Voice futz. False if the pool is empty.
static func bird_voice(pos: Vector2, pitch := 1.0, db := 0.0) -> bool:
	return pool_at(BIRD_VOICE, pos, pitch, db, 0.0, "Voice", 0.0)


## Every recorded file for pool `key`, loaded (sorted by file name). Static so the soundboard can use it.
static func pool_files(key: String) -> Array:
	var out := []
	var dir := "res://audio/" + key.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		return out
	var prefix := key.get_file()
	var files := Array(ResourceLoader.list_directory(dir))
	for f in DirAccess.get_files_at(dir):          # freshly dropped, not imported yet
		if not files.has(f):
			files.append(f)
	files.sort()
	for f: String in files:
		if f.begins_with(prefix) and POOL_EXTS.has(f.get_extension().to_lower()):
			var s := load_audio(dir.path_join(f))
			if s:
				s.set_meta("snd_key", (key.get_base_dir() + "/" + f.get_basename()))
				out.append(s)
	return out


## An audio file as a stream: the imported resource if there is one, else decoded straight from the file.
static func load_audio(path: String) -> AudioStream:
	if ResourceLoader.exists(path):
		return load(path) as AudioStream
	return load_raw(path)


## Decode an .ogg/.wav/.mp3 file directly (no import needed). Null if missing or unreadable.
static func load_raw(path: String) -> AudioStream:
	if not FileAccess.file_exists(path):
		return null
	match path.get_extension().to_lower():
		"ogg":
			return AudioStreamOggVorbis.load_from_file(path)
		"wav":
			return AudioStreamWAV.load_from_file(path)
		"mp3":
			return AudioStreamMP3.load_from_file(path)
	return null


## Read LEVELS into trims / bus_trims (static: the dashboard uses it too).
static func load_levels() -> void:
	trims.clear()
	bus_trims.clear()
	off.clear()
	var cfg := ConfigFile.new()
	if cfg.load(LEVELS) != OK:
		return
	for k in cfg.get_section_keys("db") if cfg.has_section("db") else []:
		trims[k] = float(cfg.get_value("db", k, 0.0))
	for k in cfg.get_section_keys("bus") if cfg.has_section("bus") else []:
		bus_trims[k] = float(cfg.get_value("bus", k, 0.0))
	for k in cfg.get_section_keys("off") if cfg.has_section("off") else []:
		if cfg.get_value("off", k, false):
			off[k] = true


## Volume trim (dB) for sound `name`, or for a recorded pool stream (its file key). OFF_DB if switched off.
static func trim_db(name: String, s: AudioStream = null) -> float:
	var key: String = s.get_meta("snd_key") if s and s.has_meta("snd_key") else name
	return OFF_DB if off.has(key) else trims.get(key, 0.0)


## Looping positional sound owned by `parent` (call from the parent's _ready; freed with it). Null if not attached.
static func emitter(parent: Node2D, name: String, db := 0.0, offset := Vector2.ZERO, max_dist := 1400.0) -> AudioStreamPlayer2D:
	if inst == null or not parent.is_inside_tree():
		return null
	var s := inst._stream(name)
	if s == null:
		return null
	var p := AudioStreamPlayer2D.new()
	p.stream = s
	p.bus = "World"
	p.volume_db = db + trim_db(name)
	p.position = offset
	p.max_distance = max_dist
	p.panning_strength = 1.2
	parent.add_child(p)
	p.play(inst._rng.randf() * s.get_length())
	stats[name] = stats.get(name, 0) + 1
	inst._emitters.append([p, name])
	return p


## Named loop with a target level (0..1, linear) and pitch, eased at `rate` level/second. Set it every frame or
## once; level 0 stops it.
static func loop(name: String, level: float, pitch := 1.0, bus := "World", rate := 3.0) -> void:
	if inst == null:
		return
	var l: Dictionary = inst._loops.get(name, {})
	if l.is_empty():
		var p := AudioStreamPlayer.new()
		p.bus = bus
		inst.add_child(p)
		l = {"p": p, "level": 0.0, "cur": 0.0, "pitch": pitch, "rate": rate}
		inst._loops[name] = l
	l.level = level
	l.pitch = pitch
	l.rate = rate


## 1 = inside the car: world (and music) heard through the glass; 0 = zoomed into the window.
static func set_glass(world: float, music_k: float) -> void:
	if inst:
		inst._glass = Vector2(world, music_k)


static func music(state: M) -> void:
	if inst:
		inst._set_mstate(state)


## Lead layer: fades in with scroll speed, and for a while after a combo / slice chain of 3+.
static func intensity(speed: float, chain: int) -> void:
	if inst == null:
		return
	inst._lead = clampf((speed - 440.0) / 160.0, 0.0, 1.0)
	if chain >= 3:
		inst._hype = HYPE_TIME


## Car radio: tune to the next station (Radio.STATIONS) with a burst of tuning static. Game shows the toast.
static func next_station() -> void:
	Radio.station = (Radio.station + 1) % Radio.count()
	if inst == null:
		return
	inst._play("radio_tune", 1.0, -3.0, 0.0, "Ui")
	inst._tune()


## pitch_scale for scale degree `step` (0 = root) of the current song's pentatonic scale, for sounds tuned to C.
static func note(step: int) -> float:
	var s: Dictionary = Radio.current()
	var key: int = s.key
	if key > 6:
		key -= 12
	var sc: Array = Music.MINOR_PENTA if Music.is_minor(s) else Music.MAJOR_PENTA
	step = maxi(step, 0)
	return pow(2.0, (key + int(sc[step % 5]) + 12 * floori(step / 5.0)) / 12.0)


## A world position within `dist` px (x) of the listener.
static func near(pos: Vector2, dist: float) -> bool:
	if not _live():
		return false
	var cam := inst.get_viewport().get_camera_2d()
	return cam != null and absf(pos.x - cam.get_screen_center_position().x) < dist


## Songbird chirps per second (Game: time of day x scenery x weather).
static func set_chirps(per_sec: float) -> void:
	if inst:
		inst._chirps = per_sec


## Per-round setup (Game._ready): ambience for the time of day, and this phase's song.
static func new_round() -> void:
	if inst == null:
		return
	var p := TimeOfDay.p()
	loop("amb_city", p.city, 1.0, "World", 0.4)
	loop("amb_crickets", p.crickets, 1.0, "World", 0.4)
	inst._chirps = p.chirps
	inst._want_song(inst._cur_key())


# --- instance ---

## Players and buses exist from creation: static calls arrive before the deferred add puts us in the tree.
func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	Settings.load_all()
	load_levels()
	_setup_buses()
	if OS.is_debug_build():
		_link = PacketPeerUDP.new()
		if _link.bind(LINK_PORT, "127.0.0.1") != OK:   # another game already has it
			_link = null
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	for i in VOICES_2D:
		var p := AudioStreamPlayer2D.new()
		p.bus = "World"
		p.max_distance = 1800.0
		p.panning_strength = 1.2
		add_child(p)
		_players_2d.append(p)
	_music = AudioStreamPlayer.new()
	_music.bus = "Music"
	add_child(_music)
	for v in HORNS:                              # recorded files load fast; have them ready before play
		_pool("horns/%s/tap" % v)
		_pool("horns/%s/long" % v)
	for sp in SPEAKERS:
		for sit in SITUATIONS:
			_pool("voices/%s/%s" % [sp, sit])
	_pool(BIRD_VOICE)
	var names: Array = WARM_FIRST.duplicate()
	for n in SoundBank.NAMES:
		if not names.has(n):
			names.append(n)
	_warm_task = WorkerThreadPool.add_task(_warm.bind(names), false, "sound bank")


## Worker thread: build the whole bank (intro sounds first) so plays never stall the game.
func _warm(names: Array) -> void:
	for n in names:
		if Music.abort:
			return
		SoundBank.build(n)


func _exit_tree() -> void:
	Music.abort = true                          # stop background renders so quitting doesn't wait on them
	if _link:
		_link.close()
		_link = null
	_emitters.clear()
	if _warm_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_warm_task)
		_warm_task = -1
	if not _task.is_empty():
		WorkerThreadPool.wait_for_task_completion(_task[1])
		_task = []
	# Quitting (we're never removed otherwise): stop every player in the tree and give the mixer a moment to
	# drop the playbacks, or ones started just before quit are reported as leaked at exit.
	var root := get_tree().root
	for c in root.find_children("*", "AudioStreamPlayer", true, false) \
			+ root.find_children("*", "AudioStreamPlayer2D", true, false):
		c.stop()
		c.stream = null
	OS.delay_msec(120)
	_streams.clear()
	_pools.clear()
	_songs.clear()
	_song = null
	SoundBank.clear()
	if inst == self:
		inst = null


func _setup_buses() -> void:
	setup_buses()
	_lp_world = AudioServer.get_bus_effect(AudioServer.get_bus_index("World"), 0)
	_lp_music = AudioServer.get_bus_effect(AudioServer.get_bus_index("Music"), 0)


## Build the buses + effects once (idempotent; static so the soundboard hears the same chain).
static func setup_buses() -> void:
	if AudioServer.get_bus_effect_count(0) == 0:
		var lim := AudioEffectHardLimiter.new()
		lim.ceiling_db = -0.5
		AudioServer.add_bus_effect(0, lim)
	for b in BUS_DB:
		var i := AudioServer.get_bus_index(b)
		if i < 0:
			i = AudioServer.bus_count
			AudioServer.add_bus(i)
			AudioServer.set_bus_name(i, b)
			AudioServer.set_bus_send(i, "World" if b == "Voice" else "Master")
		if AudioServer.get_bus_effect_count(i) > 0:
			continue
		if b == "World" or b == "Music":
			var f := AudioEffectLowPassFilter.new()
			f.cutoff_hz = OPEN_HZ
			f.resonance = 0.3
			AudioServer.add_bus_effect(i, f)
		elif b == "Voice":
			for fx in _futz():
				AudioServer.add_bus_effect(i, fx)
	apply_volumes()


## Bus levels: the mix (BUS_DB + dashboard trims) plus the player's volume sliders (Settings; all at 0 dB in the
## tools, which never load the player's settings) and mute.
static func apply_volumes() -> void:
	AudioServer.set_bus_volume_db(0, Settings.db("Master"))
	AudioServer.set_bus_mute(0, Settings.muted)
	for b in BUS_DB:
		var i := AudioServer.get_bus_index(b)
		if i >= 0:
			AudioServer.set_bus_volume_db(i, bus_db(b))


static func bus_db(b: String) -> float:
	var s := Settings.slider_for(b)
	return BUS_DB[b] + bus_trims.get(b, 0.0) + (Settings.db(s) if s != "" else 0.0)


## The futz: a voice through a small cheap speaker (phone / walkie-talkie / old radio). Steep band-limit to the
## speaker's range, overdrive it, band-limit again (the drive adds fizz), then a honky mid bump for the cone.
static func _futz() -> Array:
	var hp := AudioEffectHighPassFilter.new()
	hp.cutoff_hz = 420.0
	hp.resonance = 0.6
	hp.db = AudioEffectFilter.FILTER_24DB
	var drive := AudioEffectDistortion.new()
	drive.mode = AudioEffectDistortion.MODE_OVERDRIVE
	drive.pre_gain = 8.0
	drive.drive = 0.45
	drive.post_gain = -9.0
	var lp := AudioEffectLowPassFilter.new()
	lp.cutoff_hz = 3200.0
	lp.resonance = 0.6
	lp.db = AudioEffectFilter.FILTER_24DB
	var hp2 := AudioEffectHighPassFilter.new()
	hp2.cutoff_hz = 300.0
	hp2.db = AudioEffectFilter.FILTER_12DB
	var eq := AudioEffectEQ6.new()             # bands: 32, 100, 320, 1000, 3200, 10000 Hz
	eq.set_band_gain_db(2, -4.0)
	eq.set_band_gain_db(3, 5.0)
	eq.set_band_gain_db(4, 2.0)
	return [hp, drive, lp, hp2, eq]


## Override file or synthesized sound. block = false: null until the warm-up thread has built it.
func _stream(name: String, block := true) -> AudioStream:
	if _streams.has(name):
		return _streams[name]
	var s: AudioStream = null
	for ext in POOL_EXTS:
		var path := "res://audio/%s.%s" % [name, ext]
		s = load_audio(path)
		if s:
			_set_loop(s, SoundBank.LOOPS.has(name))
			break
	if s == null:
		s = SoundBank.build(name) if block else SoundBank.cached(name)
	if s:
		_streams[name] = s
	return s


func _pick(pool: Array, name: String) -> Node:
	var cap: int = MAX_SAME_BY.get(name, MAX_SAME)
	var same := []
	for p in pool:
		if p.playing and _playing.get(p, [""])[0] == name:
			same.append(p)
	if same.size() >= cap:
		same.sort_custom(func(a: Node, b: Node) -> bool: return _playing[a][1] < _playing[b][1])
		return same[0]
	for k in pool.size():
		var p: Node = pool[(_next + k) % pool.size()]
		if not p.playing:
			_next = (_next + k + 1) % pool.size()
			return p
	var oldest: Node = pool[0]
	for p in pool:
		if _playing.get(p, ["", 0])[1] < _playing.get(oldest, ["", 0])[1]:
			oldest = p
	return oldest


func _play(name: String, pitch: float, db: float, jitter: float, bus: String) -> void:
	if off.has(name):
		return
	var s := _stream(name)
	if s == null:
		return
	var p: AudioStreamPlayer = _pick(_players, name)
	p.stop()
	p.stream = s
	p.bus = bus
	p.volume_db = db + trim_db(name)
	p.pitch_scale = maxf(pitch * (1.0 + _rng.randf_range(-jitter, jitter)), 0.05)
	p.play()
	_playing[p] = [name, Time.get_ticks_msec(), name]
	stats[name] = stats.get(name, 0) + 1


## Loop flag for any stream type (override files of looping sounds).
static func _set_loop(s: AudioStream, on: bool) -> void:
	if s is AudioStreamOggVorbis:
		(s as AudioStreamOggVorbis).loop = on
	elif s is AudioStreamMP3:
		(s as AudioStreamMP3).loop = on
	elif s is AudioStreamWAV:
		var w := s as AudioStreamWAV
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD if on else AudioStreamWAV.LOOP_DISABLED
		if on:
			w.loop_begin = 0
			w.loop_end = int(w.get_length() * w.mix_rate)


func _play_at(name: String, pos: Vector2, pitch: float, db: float, jitter: float) -> void:
	if off.has(name):
		return
	var s := _stream(name)
	if s:
		_play_stream_at(name, s, pos, pitch, db, jitter, "World")


## Cached pool (see pool_files).
func _pool(key: String) -> Array:
	if not _pools.has(key):
		_pools[key] = pool_files(key)
	return _pools[key]


## Random file from a non-empty pool, not the one played last time.
func _pool_pick(key: String) -> AudioStream:
	var pool := _pool(key)
	var i := _rng.randi() % pool.size()
	if pool.size() > 1 and i == _pool_last.get(key, -1):
		i = (i + 1 + _rng.randi() % (pool.size() - 1)) % pool.size()
	_pool_last[key] = i
	return pool[i]


## `name` is the voice-cap / stats key (a sound name or a pool key).
func _play_stream_at(name: String, s: AudioStream, pos: Vector2, pitch: float, db: float, jitter: float,
		bus: String) -> void:
	var p: AudioStreamPlayer2D = _pick(_players_2d, name)
	p.stop()
	p.stream = s
	p.bus = bus
	p.global_position = pos
	p.volume_db = db + trim_db(name, s)
	p.pitch_scale = maxf(pitch * (1.0 + _rng.randf_range(-jitter, jitter)), 0.05)
	p.play()
	_playing[p] = [name, Time.get_ticks_msec(), s.get_meta("snd_key", name)]
	stats[name] = stats.get(name, 0) + 1


static func set_muted(m: bool) -> void:
	Settings.muted = m
	AudioServer.set_bus_mute(0, m)
	Settings.save()


func _process(delta: float) -> void:
	if InputMap.has_action("mute") and Input.is_action_just_pressed("mute"):
		set_muted(not Settings.muted)
	if InputMap.has_action("fullscreen") and Input.is_action_just_pressed("fullscreen"):
		Settings.fullscreen = not Settings.fullscreen
		Settings.apply()
		Settings.save()
	if _link:
		_poll_link()
	_update_loops(delta)
	_update_glass()
	_update_chirps(delta)
	_update_music(delta)


## Live link from tools/sound_dashboard.gd: apply trims to what's already sounding, swap replaced files in.
func _poll_link() -> void:
	while _link.get_available_packet_count() > 0:
		var msg := _link.get_packet().get_string_from_utf8().strip_edges()
		var ip := _link.get_packet_ip()
		var port := _link.get_packet_port()
		var a := msg.split(" ", false)
		if a.size() >= 3 and a[0] == "trim":
			_live_trim(a[1], float(a[2]))
		elif a.size() >= 3 and a[0] == "off":
			_live_trim(a[1], trims.get(a[1], 0.0), a[2] == "1")
		elif a.size() >= 3 and a[0] == "bus":
			bus_trims[a[1]] = float(a[2])
			var i := AudioServer.get_bus_index(a[1])
			if i >= 0 and BUS_DB.has(a[1]):
				AudioServer.set_bus_volume_db(i, bus_db(a[1]))
		elif a.size() >= 2 and a[0] == "reload":
			_live_reload(a[1])
		elif a.size() >= 1 and a[0] != "ping":
			continue
		if ip != "" and port > 0:
			_link.set_dest_address(ip, port)
			_link.put_packet("ok".to_utf8_buffer())


## New trim (and on/off state) for `key`; the change is applied to everything already sounding with it.
func _live_trim(key: String, db: float, is_off := off.has(key)) -> void:
	var before := trim_db(key)
	trims[key] = db
	if is_off:
		off[key] = true
	else:
		off.erase(key)
	var d := trim_db(key) - before
	if is_zero_approx(d):
		return
	for p in _playing:
		if is_instance_valid(p) and p.playing and _playing[p].size() > 2 and _playing[p][2] == key:
			p.volume_db += d
	for e in _emitters:
		if is_instance_valid(e[0]) and e[1] == key:
			e[0].volume_db += d
	_emitters = _emitters.filter(func(e: Array) -> bool: return is_instance_valid(e[0]))


func _live_reload(key: String) -> void:
	if key.contains("/"):                        # a recorded take: re-scan its folder's pools
		var dir := key.get_base_dir()
		for k in _pools.keys():
			if k.get_base_dir() == dir:
				_pools.erase(k)
				_pool_last.erase(k)
		return
	_streams.erase(key)
	if _loops.has(key):
		var p: AudioStreamPlayer = _loops[key].p
		p.stop()
		p.stream = null                            # _update_loops picks the new stream up next frame
	var s := _stream(key)
	for e in _emitters:
		if is_instance_valid(e[0]) and e[1] == key and s:
			var p: AudioStreamPlayer2D = e[0]
			var on := p.playing
			p.stream = s
			if on:
				p.play()


func _update_loops(delta: float) -> void:
	for name in _loops:
		var l: Dictionary = _loops[name]
		var p: AudioStreamPlayer = l.p
		l.cur = move_toward(l.cur, l.level, l.rate * delta)
		if l.cur > 0.001:
			if p.stream == null:
				p.stream = _stream(name, false)         # still warming up: starts once the thread has it
				if p.stream == null:
					continue
			p.volume_db = linear_to_db(l.cur) + trim_db(name)
			p.pitch_scale = lerpf(p.pitch_scale, maxf(l.pitch, 0.05), minf(delta * 5.0, 1.0))
			if not p.playing:
				p.play(_rng.randf() * p.stream.get_length())
				stats[name] = stats.get(name, 0) + 1
		elif p.playing:
			p.stop()


## Exponential cutoff between fully open and the glass; effects bypassed when open.
func _update_glass() -> void:
	if _lp_world:
		_lp_world.cutoff_hz = OPEN_HZ * pow(WORLD_GLASS_HZ / OPEN_HZ, clampf(_glass.x, 0.0, 1.5))
		AudioServer.set_bus_effect_enabled(AudioServer.get_bus_index("World"), 0, _glass.x > 0.01)
	if _lp_music:
		_lp_music.cutoff_hz = OPEN_HZ * pow(MUSIC_GLASS_HZ / OPEN_HZ, clampf(_glass.y, 0.0, 1.5))
		AudioServer.set_bus_effect_enabled(AudioServer.get_bus_index("Music"), 0, _glass.y > 0.01)


## Songbirds somewhere around the camera (more at dawn, none at night).
func _update_chirps(delta: float) -> void:
	if _chirps <= 0.0:
		return
	_chirp_t -= delta
	if _chirp_t > 0.0:
		return
	_chirp_t = -log(maxf(_rng.randf(), 0.01)) / _chirps
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return
	var at := cam.get_screen_center_position() + Vector2(_rng.randf_range(-700.0, 700.0), _rng.randf_range(-300.0, -60.0))
	_play_at("chirp" if _rng.randf() < 0.7 else "chirp2", at, _rng.randf_range(0.85, 1.2), -12.0, 0.0)


# --- music ---

## Song cache key for a station + time-of-day phase.
static func song_key(station: int, phase: int) -> int:
	return station * 10 + phase


func _cur_key() -> int:
	return song_key(Radio.station, TimeOfDay.phase())


## Make `key` the song: play it if it's rendered, else render it first. Then pre-render what's likely next: the
## next station at this time of day (the next R press) and this station's next phase (the next round change).
func _want_song(key: int) -> void:
	if _songs.has(key):
		_use_song(key)
	else:
		_queue.erase(key)
		if _task.is_empty() or _task[0] != key:
			_queue.push_front(key)
	var st := key / 10
	var ph := key % 10
	for nxt in [song_key((st + 1) % Radio.count(), ph), song_key(st, (ph + 1) % TimeOfDay.PRESETS.size())]:
		if not _songs.has(nxt) and not _queue.has(nxt) and (_task.is_empty() or _task[0] != nxt):
			_queue.append(nxt)


func _poll_render() -> void:
	if not _task.is_empty() and WorkerThreadPool.is_task_completed(_task[1]):
		WorkerThreadPool.wait_for_task_completion(_task[1])
		var holder: Array = _task[2]
		if not holder.is_empty() and holder[0] != null:
			_songs[_task[0]] = holder[0]
			_song_used[_task[0]] = Time.get_ticks_msec()
			_trim_songs()
			if _task[0] == _cur_key() and _song_key != _task[0]:
				_use_song(_task[0])
		_task = []
	if _task.is_empty() and not _queue.is_empty() and not Music.abort:
		var key: int = _queue.pop_front()
		var holder := []
		var id := WorkerThreadPool.add_task(_render.bind(Radio.song(key / 10, key % 10), key, holder), false, "music")
		_task = [key, id, holder]


## Songs are 4-10 MB each: keep the MAX_SONGS most recently used (never the one playing).
func _trim_songs() -> void:
	while _songs.size() > MAX_SONGS:
		var oldest := -1
		for k in _songs:
			if k != _song_key and (oldest < 0 or _song_used.get(k, 0) < _song_used.get(oldest, 0)):
				oldest = k
		if oldest < 0:
			return
		_songs.erase(oldest)
		_song_used.erase(oldest)


## Worker thread: one song.
func _render(song: Dictionary, key: int, holder: Array) -> void:
	holder.append(Music.render(song, Music.seed_for(key / 10, key % 10)))


func _use_song(key: int) -> void:
	if _song_key == key:
		return
	_song_key = key
	_song = _songs[key]
	_song_used[key] = Time.get_ticks_msec()
	_music.stream = _song
	loop("radio_static", 0.0, 1.0, "Music", 6.0)
	var tuned := _tuning
	_tuning = false
	_layer = [0.0, 0.0, 0.0, 0.0]
	if _mstate == M.DEAD:
		return
	_restart_music()
	if tuned:                                    # radio switch: the new station is already "on air", full layers
		_layer = _targets()
		_apply_layers()


## Tune to Radio.station (after next_station bumped it): cut the old song, a beat of static, then the new one;
## if it isn't rendered yet the static keeps hissing until it is.
func _tune() -> void:
	_tuning = true
	_music.stop()
	_song = null
	_song_key = -1
	loop("radio_static", 0.5, 1.0, "Music", 20.0)
	var key := _cur_key()
	get_tree().create_timer(TUNE_GAP).timeout.connect(func() -> void:
		if key == _cur_key() and _song_key == -1:
			_want_song(key))


func _restart_music() -> void:
	if _tape:
		_tape.kill()
		_tape = null
	_music.pitch_scale = 1.0
	_music_level = 1.0
	_layer = [0.0, 0.0, 0.0, 0.0]
	if _song:
		_music.play()


func _set_mstate(s: M) -> void:
	var prev := _mstate
	_mstate = s
	if s == M.DEAD:
		if prev != M.DEAD and _music.playing:
			_tape_stop()
	elif s == M.OVER or prev == M.DEAD or not _music.playing:
		_restart_music()                        # game over (or back from a stopped tape): from the top


## Death: the tape slows down and dies.
func _tape_stop() -> void:
	if _tape:
		_tape.kill()
	_tape = create_tween()
	_tape.tween_property(_music, "pitch_scale", 0.2, 1.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_tape.parallel().tween_property(self, "_music_level", 0.0, 1.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_tape.tween_callback(func() -> void:
		_music.stop()
		_music.pitch_scale = 1.0)


func _update_music(delta: float) -> void:
	_poll_render()
	if _song == null:
		return
	_hype = maxf(_hype - delta, 0.0)
	var target := _targets()
	for i in Music.STEMS:
		_layer[i] = move_toward(_layer[i], target[i], LAYER_RATE[i] * delta)
	_apply_layers()


## Layer levels the current music state asks for (PAD, BASS, DRUMS, LEAD).
func _targets() -> Array:
	var target: Array = LAYERS[_mstate].duplicate()
	if _mstate == M.PLAY:
		target[Music.LEAD] = maxf(_lead, 1.0 if _hype > 0.0 else 0.0)
	return target


func _apply_layers() -> void:
	if _song == null:
		return
	for i in Music.STEMS:
		_song.set_sync_stream_volume(i, linear_to_db(maxf(_layer[i] * _music_level, 0.00001)))
